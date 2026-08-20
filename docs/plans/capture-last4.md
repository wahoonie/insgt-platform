# Capture Stripe `last4` on Accounts and Transactions

## Context

The account row and the transaction row both store a card `brand` but no `last4`, so every
card label in the product reads `Visa` instead of `Visa •••• 4242`. Agents can't tell which
card is on file, and ops can't match a historical charge to a card.

This adds `last4` in two places with **deliberately different contracts**:

- `accounts.last4` — the card **currently** on file. Mutable; changes when the saved card changes.
- `transactions.last4` — an immutable snapshot of the card **actually charged**. Never rewritten.

Existing rows keep `last4 = nil`. No bulk backfill, no rake task, no scheduled job. Active
accounts acquire it two ways: when they save/replace a card, and lazily on shoot creation.

---

## Pre-implementation report (requested in §1)

**1. Stripe model/API style.** Legacy **Sources / Cards** end to end. `stripe` gem 18.3.0
sending API version `2026-01-28.clover`. No PaymentMethods, SetupIntents, or PaymentIntents
anywhere in the repo.
- Cards saved via `Stripe::Customer.create(source: tok_…, expand: ['default_source'])`
  ([account.rb:474](apps/insgt-api/app/models/account.rb#L474)) and
  `Stripe::Customer.update(cus_…, source: tok_…, expand: ['default_source'])` ([:493](apps/insgt-api/app/models/account.rb#L493)).
- Charging via `Stripe::Charge.create` with either `customer: cus_…` (stored card → Stripe
  charges `default_source`) or `source: tok_…` (one-time card) —
  [transaction_stripe.rb:91-100](apps/insgt-api/app/models/concerns/transaction_stripe.rb#L91-L100).
- `stripe_token` = "has a Stripe customer"; `brand` = "has a card". `card_on_file?` is
  `stripe_token? && brand?` ([:306](apps/insgt-api/app/models/account.rb#L306)). Exactly one card
  per customer is enforced by `prune_superseded_cards` ([:590](apps/insgt-api/app/models/account.rb#L590)).
- The model is **`Account`** (table `accounts`), not `Agent`.

**2. Where account `brand` is populated.** `Account#card_brand(customer, options)`
([:637](apps/insgt-api/app/models/account.rb#L637)) reads `customer[:default_source][:brand]` off the
expanded Customer response, falls back to the client-supplied `options[:brand]`, and raises
`MissingCardBrand` if both are blank. Persisted via `record_card!` at
[:477](apps/insgt-api/app/models/account.rb#L477) (create) and [:495](apps/insgt-api/app/models/account.rb#L495) (update).

**3. Where transaction `brand` is populated.** Mass-assigned pre-validation in
`Transaction.new_for_order` ([transaction.rb:31-32](apps/insgt-api/app/models/transaction.rb#L31-L32))
from `options[:brand]`, which is `order.account.brand` on both customer paths
([transaction_stripe.rb:32](apps/insgt-api/app/models/concerns/transaction_stripe.rb#L32),
[:37](apps/insgt-api/app/models/concerns/transaction_stripe.rb#L37)) and the raw client param on the
one-time-card path. It is **never** read off the Charge response today.

**4. Where the two `last4` values will be captured.**
- Account: from the same expanded `customer[:default_source]` Card object that already yields
  `brand` — one refactored extractor, three callers.
- Transaction: from the **Charge response** inside `charge`, preferring
  `payment_method_details.card.last4` and falling back to the legacy `source.last4`.

**Two gem facts verified in `stripe-18.3.0` source, both load-bearing:**
- `Stripe::Customer` does **not** define `retrieve`; it inherits
  `APIResource.retrieve(id, opts = {})` where the second argument is **request options, not
  params**. `retrieve(token, expand: […])` silently sends `Expand:` as an HTTP *header*, no
  `expand[]` query param, and `default_source` returns as a bare id string. The correct form is
  the overloaded hash: `Stripe::Customer.retrieve({ id: stripe_token, expand: ['default_source'] })`.
  (`Customer.create`/`update` are generated as `(params, opts)` and are already correct.)
- `payment_method_details.card.brand` is the **machine enum** (`visa`, `mastercard`, `amex`,
  `link`, …) while legacy `Card#brand` is **display-cased** (`Visa`, `MasterCard`,
  `American Express`, `Girocard`). Not a bijection. Every `brand` in the database is
  display-cased. **Therefore only `last4` is ever read from a Charge — never `brand`.**

---

## The invariant

> `brand` and `last4` are one value in two columns. **Every statement that writes `brand` writes
> `last4` in the same statement; every statement that doesn't write `brand` doesn't write `last4`.**
> `last4` is never non-null while `brand` is null.

Enforced structurally by making the extractor always return both keys — `last4: nil` when Stripe
didn't inline the card — so a card swap whose response omits `default_source` can't leave the old
digits behind under a new brand ("MasterCard •••• 4242" over a Visa). `reconcile_failed_card_deletion`
([:550](apps/insgt-api/app/models/account.rb#L550)) already satisfies this unmodified: its
card-survived branch writes neither column, and its other branch delegates to `clear_card_on_file`.

---

## 1. Migration

`db/migrate/20260730120000_add_last4_to_accounts_and_transactions.rb` — one migration, two
`add_column`s in one DDL transaction (atomic; two migrations can half-apply).

```ruby
class AddLast4ToAccountsAndTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :last4, :string
    add_column :transactions, :last4, :string
  end
end
```

Nullable, no default, no `limit`, no index, no backfill, no Stripe call. Mirrors the unlimited
`accounts.brand`. Deliberately **no** `limit`: a `StringDataRightTruncation` would land inside
`before_create :charge`, the one place where a schema failure means Stripe captured money and the
row was never written. ARCHITECTURE-style header comment per repo convention (see
`20260727120000_add_address_components_index_to_properties.rb`). Run locally and commit the
`db/schema.rb` version bump.

---

## 2. `app/models/account.rb`

**2a. Replace `card_brand` with `card_attributes`** ([:637](apps/insgt-api/app/models/account.rb#L637)) —
returns both halves, always including `:last4`:

```ruby
def card_attributes(customer, options)
  card = customer[:default_source]
  card = nil unless card.is_a?(Stripe::StripeObject)
  brand = card ? card[:brand] : nil
  brand = options[:brand] if brand.blank?
  raise MissingCardBrand, "account #{id}: card attached to #{customer[:id]}, no brand resolved" if brand.blank?

  { brand: brand, last4: card ? card[:last4].presence : nil }
end
```

Preserve the existing bracket-access and raise-on-blank-brand comments verbatim; add why the
explicit `last4: nil` matters and why there is deliberately **no** client fallback for `last4`
(the checkout client isn't a trustworthy source, and nil is honest — the UI shows brand alone).
Update both call sites to `record_card!(card_attributes(customer, options), customer)`
([:477](apps/insgt-api/app/models/account.rb#L477), [:495](apps/insgt-api/app/models/account.rb#L495)).

**2b. Add `last4: nil` to the three card-clearing writes** — `recreate_stripe_customer`
([:513](apps/insgt-api/app/models/account.rb#L513)), `clear_card_on_file`
([:521](apps/insgt-api/app/models/account.rb#L521)), `clear_stripe_customer`
([:528](apps/insgt-api/app/models/account.rb#L528)). Add a comment to
`reconcile_failed_card_deletion` stating that writing neither column is the invariant, not an omission.

**2c. New public `sync_card_on_file!`** (after `create_payment_customer`, [:312](apps/insgt-api/app/models/account.rb#L312)) —
this is §10's centralized sync. A method on `Account`, **not** a service: every line of Stripe
logic already lives here, `Stripe::Customer.retrieve` is already called at
[:537](apps/insgt-api/app/models/account.rb#L537), and a service would have to duplicate the private
`record_card!` / `card_attributes` / `UnrecordedCard` contract. Note that reasoning in the comment
so a later session doesn't "fix" it toward the `insgt-api` skill default.

```ruby
def sync_card_on_file!
  return false if stripe_token.blank?

  customer = Stripe::Customer.retrieve({ id: stripe_token, expand: ['default_source'] })
  return false if customer.nil? || customer[:deleted]
  return false unless customer[:default_source].is_a?(Stripe::StripeObject)

  record_card!(card_attributes(customer, {}), customer)
  true
end
```

Comment must call out (i) the overloaded-id hash and why `retrieve(token, expand:)` silently
fails, and (ii) that returning `false` without touching the row when there's no default source is
deliberate — a background refresh must never be what removes a card from the UI. Writes **both**
columns from the same object the save path reads, so it's self-healing for `brand` too and can't
introduce casing drift.

**2d. New public `enqueue_card_sync`** (near `card_on_file?`) — the one-shot guard:

```ruby
def enqueue_card_sync
  return false unless stripe_token.present? && last4.blank?

  AccountCardSyncWorker.perform_async(id)
  true
end
```

`last4.blank?` is what makes it one-shot — the worker's own write clears the guard (§8).

---

## 3. `app/workers/account_card_sync_worker.rb` (new)

Repo worker pattern: `include Sidekiq::Worker`, `include Sidekiq::Status::Worker`,
`sidekiq_options retry: false`. `perform(account_id)` → `Account.find_by(id:)&.sync_card_on_file!`.

- `rescue Stripe::StripeError` → `Rails.logger.error "[AccountCardSyncWorker] …"` and **swallow**
  (unlike `PropertyDataLookupWorker`, which re-raises — a Stripe blip here is self-healing and
  would otherwise flood the dead set).
- `rescue StandardError` → log + `Notifier.send_error_email('AccountCardSyncWorker failure', …)`
  + re-raise. `UnrecordedCard` means a row that can't be saved and needs a human, matching how
  `Account#rescue_stripe_error` escalates the same condition.

---

## 4. `app/models/order.rb` — lazy backfill trigger (§7, §8, §11)

One line at each of the two agent-facing shoot-request entry points, **outside**
`request_shoot`'s `order_types` loop (that loop can create N orders) and not conditional on order
success — the sync is about the account, not the order:

```ruby
current_user.accounts.first&.enqueue_card_sync
```

- `Order.request_shoot` ([:1131](apps/insgt-api/app/models/order.rb#L1131)) — before the loop.
- `Order.create_from_cart` ([:1080](apps/insgt-api/app/models/order.rb#L1080)) — after building the order.
  `Cart#request_shoot` and `CartsController#request_shoot` both funnel here, so two call sites
  cover three routes.

**Explicit call sites, not an Order callback** — matching `Property.enqueue_property_facts_lookup`
([property.rb:445-469](apps/insgt-api/app/models/property.rb#L445-L469)), which documents its rejection
of a callback for exactly this. An `after_create_commit` would need `order.account` loaded on
every order ever created — imports and seeds included — to service a one-time fix.

**Deliberately excluded:** ops-created orders, child orders, double bookings, headshot orders —
these aren't "an agent creates a new shoot". Safe to exclude because §9 is a second free backfill:
any account paying with its card on file gets `last4` from the charge response at no extra Stripe
call. Document this as a stated non-goal.

Never blocks booking: `perform_async` only enqueues, and the worker rescues everything.

---

## 5. `app/models/concerns/transaction_stripe.rb` — snapshot + free account backfill

In `charge` ([:99](apps/insgt-api/app/models/concerns/transaction_stripe.rb#L99)), after the existing
`self.amount =`:

```ruby
self.last4 = charged_card_last4(stripe_charge)
backfill_account_last4
```

Assigning inside `before_create` lands on the INSERT — the same established pattern as
`charge_token` (`limit: 256, null: false`, assigned only there). `last4` is nullable and
unvalidated, so there is zero risk to the `brand` `null: false` column or its presence validation.
Use `.presence` because `cleanup_attributes`' blank-nillification runs *before* `charge`.

**`charged_card_last4(stripe_charge)`** (private) — prefer
`stripe_charge[:payment_method_details][:card]`, fall back to `stripe_charge[:source]`, return
`card[:last4].presence` or nil. Bracket access + `is_a?(Stripe::StripeObject)` guards throughout
(StripeObject has no `dig`; dot-access on an absent field raises `NoMethodError`). No `expand`
needed — both fields are inlined by default and neither is expandable. Comment must state that
`brand` is deliberately not read here, with the casing reason.

**`backfill_account_last4`** (private) — §9's free half:

```ruby
def backfill_account_last4
  return if token_type != Transaction.types[:customer][:id]
  return if last4.blank?

  account = order&.account
  return if account.blank? || account.brand.blank? || account.last4 == last4

  account.update_columns(last4: last4, updated_by_id: User.system.id)
rescue StandardError => e
  Rails.logger.error "[Transaction#backfill_account_last4] Failed for Order##{order_id}: " \
                     "#{e.class} — #{e.message}"
end
```

- Only on the stored-card path — `token_type == customer` means Stripe charged `default_source`,
  so the charged card **is** the saved card. On the one-time-card path the account is never
  touched (§9's Mastercard-•••• 1234 case).
- **Its own `rescue` is not optional.** This runs inside `before_create` on a charge Stripe has
  already captured; `charge`'s own rescue converts anything it catches into
  `ActiveRecord::RecordInvalid` and aborts the save — money taken, no transaction row, order never
  marked paid. Nothing here may reach it.
- `brand.blank?` guard keeps the invariant unconditional. Always overwrites rather than
  filling-only-when-blank, so a stale `last4` heals here.

**Leave `charge`'s `return false` alone** ([:103](apps/insgt-api/app/models/concerns/transaction_stripe.rb#L103)) —
it doesn't halt a `before_create` in Rails 5+, but the branch is unreachable for card charges and
fixing it (`throw :abort`) is a user-visible 500→422 change that deserves its own diff. Add a
one-line note so the new code isn't read as depending on it.

---

## 6. Serializers

- [accounts_helper.rb:159](apps/insgt-api/app/helpers/accounts_helper.rb#L159) `set_stripe_token` — add
  `json.set!(:last4, account.last4)`. Admin/scheduler gating unchanged.
- [accounts_helper.rb:165](apps/insgt-api/app/helpers/accounts_helper.rb#L165) `set_account_payment_info` —
  add `json.set!(:last4, account.last4)`. Already gated on `card_on_file?`, so `brand` is
  guaranteed present and `last4` may be an explicit null, which the templates branch on.
- [transactions_helper.rb:14](apps/insgt-api/app/helpers/transactions_helper.rb#L14) — add `:last4` to
  the `json.extract!` list.

`Jbuilder.key_format camelize: :lower` leaves `last4` as `last4` — no camelCase surprise.

---

## 7. Angular (§13)

JSON changes are purely additive, so these can land in any order relative to the API.

**insgt-ops**
- `src/app/shared/pipes/card.pipe.ts` (new) — one pure function plus a thin pipe wrapper so ops
  has exactly one implementation of the display rule:
  ```ts
  export const cardLabel = (brand?: string, last4?: string): string =>
    brand ? (last4 ? `${brand} •••• ${last4}` : brand) : '';
  ```
  `@Pipe({ name: 'appCardLabel', standalone: true, pure: true })`. Register in
  `src/app/shared/shared.module.ts` declarations + exports beside `MarketingSourcePipe` /
  `NationalNumberPipe`.
- `src/app/shared/models/account.model.ts:45` and `src/app/shared/models/transaction.model.ts` —
  add `last4?: string;` beside `brand?: string;`.
- `features/accounts/components/account-stripe/account-stripe.ts` — add `last4` to the `Vm`
  interface and `cardLabel: cardLabel(account.brand, account.last4)` to the `computed` (importing
  the pure function, per angular-core's signals pattern). Template renders `vm.cardLabel` in the
  `data-cy="account-stripe-brand"` div. `"Visa •••• 4242"` satisfies the existing
  `should('contain.text', 'Visa')` assertion — substring match, structurally safe. Leave
  `confirmDelete()`'s dialog string on `brand` alone.
- `src/app/orders/transactions/order-transactions.component.html:30` and
  `src/app/scheduler/order/scheduler-order.component.html:791` — apply `| appCardLabel : …last4`.
  (Flag: `order.transaction` singular on the scheduler line looks dead — no serializer emits it;
  `set_order_transaction` emits a `transactions` array.)
- `cypress/e2e/accounts/account-stripe.cy.ts` — add `last4` to the `accountWithCard` fixture and
  **two new** examples: `last4: '4242'` → `'Visa •••• 4242'`; `last4: null` → `'Visa'` with no
  bullets. Don't modify the existing three.
- Bump `package.json` version per the deploy runbook convention.

**insgt-app**
- `src/app/users/store/account.model.ts` and `src/app/cart/store/transaction.model.ts` — add
  `last4?: string;` to `Account` and `Transaction`. **Leave `StripeTransaction` alone** — do not
  add `last4` to the outbound payload, and do not permit it in `transaction_params`; that would
  give the snapshot column the untrustworthy client provenance we're avoiding.
- `orders/checkout/order-checkout.component.ts` — one `get cardOnFileLabel()` applying the same
  rule; use it in both template spots (`using {{ … }} on file`, `Pay with existing {{ … }} card on
  file instead?`).
- `billing/invoice/invoice.component.html:150` — `Paid online using {{ … }}`, preserving the
  existing wording and adding the digits.

---

## 8. Tests (RSpec — `test/` minitest is dead)

**`spec/support/stripe.rb`** — add `CHARGES_URL`, a `stripe_charge_body(...)` builder taking
`network_brand:` (machine enum on `payment_method_details.card`) and `brand:` (display casing on
legacy `source`) as *separate* keywords with no mapping between them, precisely so a spec can prove
the app reads `last4` from the charge and never `brand`. Add `payment_method_details: false` /
`source: false` switches to exercise the fallback and both-missing cases. Add a `last4:` keyword to
`stripe_card_body`. Tag every new example `:stripe` (net connect is **allowed** by default in this
suite — an untagged Stripe spec silently hits the live API).

**No `spec/factories/transactions.rb`.** `before_create :charge` fires unconditionally, so a
factory would carry a hidden network prerequisite. Build through `Transaction.new_for_order(...)`
then `.save(user)`.

1. **`spec/models/transaction_charge_spec.rb` (new)** — *write this first*; it is the first coverage
   `before_create :charge` has ever had, and `after_create :log_for_order` drives `order.trigger`
   / `OrderEvent` machinery, which is the biggest practical risk in the plan (mitigate with
   `spec/support/order_events.rb`, or stub `trigger` as `order_request_shoot_spec.rb` does).
   - `last4` from `payment_method_details.card`; from `source` when pmd is absent; nil when both
     absent and the row still saves.
   - **Regression guard for the casing decision:** charge returns `network_brand: 'mastercard'`,
     transaction persists `'Visa'` from `new_for_order`.
   - `charge_token` and `amount` still land.
   - Account backfill: customer path writes `account.last4`; one-time-card path leaves the account
     untouched; `brand`-nil account untouched; **an account row that can't validate
     (`update_columns(url: 'a.co')`) does not fail the payment** — the most important example here.
2. **`spec/models/account_stripe_spec.rb` (extend)** — create and update paths persist `last4`;
   `default_source: false` → client-fallback brand with `last4` nil; **the swap regression** (starts
   `Visa/4242`, update returns no `default_source`, asserts `last4` is now **nil**); the three
   clearing paths null `last4`; `reconcile_failed_card_deletion` card-survived branch retains both;
   `#sync_card_on_file!` writes both and **asserts the request carries `expand[]=default_source`
   as a query param** (the only guard against the `retrieve` signature trap), returns false for nil
   token / deleted customer / no default source, raises `UnrecordedCard` on a rejected row.
3. **`spec/workers/account_card_sync_worker_spec.rb` (new)** — delegates; no-ops for a missing
   account; swallows `Stripe::StripeError`; re-raises + emails ops on `UnrecordedCard`.
4. **`spec/models/order_request_shoot_spec.rb` (extend)** — the enqueue matrix via
   `AccountCardSyncWorker.jobs` (repo convention under `Sidekiq::Testing.fake!`), with
   `before { AccountCardSyncWorker.jobs.clear }`: enqueued when `stripe_token` present and `last4`
   blank; **not** enqueued when `last4` present; not enqueued when `stripe_token` nil. Plus **one**
   `Sidekiq::Testing.inline!` example for the literal §15 criterion — shoot creation succeeds and
   `last4 == '4242'`; and a Stripe-error example proving creation still succeeds with `last4` nil
   and the failure logged. Don't make `inline!` file-wide.
   (`create_from_cart`'s enqueue isn't directly covered — no cart factory; both call sites reduce
   to the same one-line guard, which is unit-tested. Note it in the spec.)
5. **`spec/requests/orders_payment_info_spec.rb` (extend)** — `last4` in the order-nested account
   payload; `'last4' => nil` when the card is on file but digits are unknown (the templates branch
   on the key being present).

---

## 9. Deploy note

**Per your decision: single deploy, migrate immediately after.** Recording the window so it's in
the runbook rather than a surprise — Heroku cuts dynos over to new code before `db:migrate` runs by
hand, so for ~60–90s new code runs against the old schema:

- a card payment in the window → `self.last4 =` raises → `rescue` → `RecordInvalid` → charge
  captured at Stripe with **no transaction row and the order not marked paid**;
- a card save → `ActiveModel::UnknownAttributeError` → card left attached at Stripe;
- `GET /accounts/:id` and every order show → 500.

Mitigation: run `heroku run rails db:migrate -a insgtapi` immediately after the release completes,
during low traffic, and reconcile any charge in that window from the Stripe dashboard. I'll add
this to `/workspace/docs/runbooks/` mirroring `deploy-credit-card.md`'s ordering section, and note
that a `release: bundle exec rails db:migrate` Procfile phase is the durable fix for a future
change.

---

## Verification

```bash
cd /workspace/apps/insgt-api
rails db:migrate && rails db:migrate:status | tail -5   # confirm both columns, schema bump
bundle exec rspec spec/models/transaction_charge_spec.rb spec/models/account_stripe_spec.rb \
                  spec/models/transaction_spec.rb spec/models/order_request_shoot_spec.rb \
                  spec/workers/account_card_sync_worker_spec.rb \
                  spec/requests/orders_payment_info_spec.rb
bundle exec rspec                                        # full suite green
rubocop <changed files>                                  # no .rubocop.yml — plain defaults
```

```bash
cd /workspace/apps/insgt-ops && npx ng lint insight-ops   # confirm still 14 pre-existing errors, none in changed files
# Cypress must run on the host, not the devcontainer:
npx cypress run --spec "cypress/e2e/accounts/account-stripe.cy.ts"
```

Manual smoke (against Stripe test mode): save a card → account shows `Visa •••• 4242`; replace it
with a Mastercard → account updates, the January transaction still reads `Visa •••• 4242`; pay with
a one-time alternate card → transaction records the alternate, account unchanged; clear
`accounts.last4` on a test account and request a shoot → worker repopulates it and booking succeeds.

## Post-implementation report

I'll close with the eight items requested: tests run, lint on changed files, changed-file list, the
exact Stripe objects behind each `last4`, where account metadata is synchronized, where transaction
metadata is captured, confirmation that historical transactions are never written from the account
row, and the Stripe edge cases left unchanged (`charge`'s non-halting `return false`;
`reconcile_failed_card_deletion`'s stale-label policy; no PaymentMethods migration; no client-supplied
`last4`; ops/child/double-booking/headshot orders not triggering the lazy backfill).
