# Runbook: Credit Card Handling Deploy

**Last updated:** 2026-07-29
**Repos:** insgt-api, insgt-ops
**Estimated duration:** ~25 min (API build is slow — Ruby bump)
**Status:** Deployed 2026-07-30

## Summary

Fixes card add/edit/delete against Stripe. Splits the two questions the account row was
conflating: `stripe_token` = "has a Stripe customer", `brand` = "has a card". A Stripe customer
now outlives its cards, so deleting a card no longer drops the customer reference — which was
causing a **duplicate Stripe customer per account** on the next card added. Ops stops offering a
Remove Card button when there is no card to remove.

- **insgt-api** `feat/credit-card` — 3 commits vs `heroku/master` (`ca36c0c`, `519b44c`, `65aa8c7`)
- **insgt-ops** `feat/credit-card` — vs `v9.45.0`, version bumped to `9.46.0`

## Deploy API first — the order is not interchangeable

The deployed `Account#destroy_stripe_token` guards on `stripe_token.blank?` and nils **both**
`stripe_token` and `brand`. `card_on_file?` does not exist on it.

- **Ops first → data damage.** New Ops gates Remove Card on `brand`, which the deployed API
  already emits, so the button appears and appears to work — but the old endpoint wipes
  `stripe_token` along with the card, orphaning the Stripe customer. The next card added creates
  a duplicate customer. That is exactly the bug `519b44c` fixes.
- **API first → cosmetic only.** Old Ops gates the trash icon on `stripeToken`, so an account
  with a customer but no card shows a button that 422s "There is no card on file." That is the
  pre-existing bug, unchanged, and no data is touched.

## Prerequisites

- [X] `bundle exec rspec` green (new: `spec/models/account_stripe_spec.rb`,
      `spec/models/transaction_spec.rb`, `spec/requests/orders_payment_info_spec.rb`)
- [X] Cypress green — **must run on the host**, it cannot run in the devcontainer:
      `npx cypress run --spec "cypress/e2e/accounts/account-stripe.cy.ts"`
- [X] insgt-ops `package.json` version is `9.46.0`
- [X] Current CloudFront origin path noted — it is the Ops rollback target 1785332207
- [ ] No active deploy in flight

## Steps

### 1. Back up the database

```bash
heroku pg:backups:capture --app insgtapi
```

### 2. Deploy API

Heroku only builds `master`, and the work is on a feature branch. Merge first so `origin/master`
and `heroku/master` stay aligned — `heroku/master` is the ref every future deploy diffs against,
and pushing a feature branch straight to it leaves the two permanently out of step:

```bash
git checkout master && git merge --no-ff feat/credit-card
git push origin master
git push heroku master
```

To ship without merging (hotfix only), `git push heroku feat/credit-card:master` works, but then
reconcile `master` afterwards.

**Watch the build to completion.** This deploy bumps Ruby **3.4.8 → 3.4.10** (new `.ruby-version`,
plus `Gemfile` / `Gemfile.lock` / `.tool-versions`), so it is a full Ruby + bundle rebuild rather
than an incremental slug — slower than usual, and it fails loudly if 3.4.10 is unavailable for the
current stack. Both dyno types restart (`web: puma`, `backgroundworker: sidekiq -c 4`).

**No migrations.** `db/` is untouched and `schema.rb` is already at `2026_07_27_120000`. Skip
`db:migrate`.

```bash
heroku run rails db:migrate:status -a insgtapi   # confirm: all up, nothing pending
```

### 3. Verify API

- `GET /accounts/:id` as an admin or scheduler still returns both `stripeToken` and `brand`
  (`set_stripe_token` is unchanged by this deploy, and gated to those two roles).
- On a test account with a card, remove the card: `brand` → nil, `stripe_token` **retained**.
- Re-add a card: it attaches to the same `cus_…`, no duplicate customer.
- Order payment info now keys off `card_on_file?` — an account with a customer but no card must
  no longer report `existing_customer: true`.

### 4. Deploy Ops (insgt-ops)

```bash
npx ng lint insight-ops
npm run build:prod
```

**Do not chain these with `&&`** as the README shows. `ng lint` exits non-zero on **14
pre-existing** errors unrelated to this work, which would stop the build. Run them separately and
confirm the count is still 14 with none in `account-stripe`.

Then build prod → timestamped folder under `insgt-apps/ops/` → upload `dist/` → point CloudFront
distribution `E2GJ3L3JH70697` origin path at the new folder → **invalidate `/*`**. Follow the
operations deployment instructions in `insgt-ops/README.md`. The invalidation is required:
`index.html` and `ngsw.json` are not hash-busted.

Before switching the origin, record the **outgoing** folder as the rollback target and update the
`Rollback:` line in `insgt-ops/README.md` to it. Confirm `environment.prod.ts` `api.url` is
`https://insgtapi.herokuapp.com` — the app just deployed in step 2.

### 5. Smoke-test Ops (manual)

At `/#/accounts/:id/edit`, as **admin and scheduler** (the serializer gates `brand`/`stripeToken` to
those two roles — other roles see neither key):

| State | Expected |
|---|---|
| Card on file | brand + Stripe customer link + Remove Card |
| Customer, no card | notice + customer link, **no** Remove Card |
| Neither | notice only |

Then Remove Card: the confirm dialog names the brand (not "undefined"), the toast reads "Removed
card on file", and the panel keeps the **customer link** while switching to the no-card notice.

## Rollback

### Roll Ops back first, then the API

Reverting the API while new Ops is still live re-creates the orphaned-customer path from the
ordering section: new Ops offers Remove Card whenever `brand` is set, and the old endpoint wipes
`stripe_token` with it.

### API

```bash
heroku rollback --app insgtapi
```

Clean — no migrations to unwind. Note the rollback also restores Ruby 3.4.8.

### Ops

Repoint the CloudFront origin path to the previous folder and invalidate `/*` again.

### If a bad ordering already dropped customer references

An account left with `stripe_token` nil but a live customer at Stripe cannot be repaired from the
row alone. Either locate the customer in the Stripe dashboard by the account's email and write the
id back, or accept a duplicate customer on the next card add. Check for damage with accounts whose
`stripe_token` is nil but which have Stripe transaction history.
