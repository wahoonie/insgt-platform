# Account Classification Architecture

**Repo:** `insgt-api` · **Consumers:** `insgt-ops` teams page, Pipedrive nightly push
**Status:** Slices 1a and 1b deployed to production 2026-09-10, with slice 4's column and API; slice 2 deployed to production 2026-09-11; slice 3 deployed to production 2026-09-14; see §9
**Version:** 6 · **Last updated:** 2026-09-14 (slice 3 implemented)
**Supersedes:** v5 (2026-09-11), v4 (2026-09-10), v3 (2026-09-08), v2 (2026-09-05), v1 (2026-08-27). See §10–§14 for what changed and why.
**Companion files:** `account-classification-codebase-notes.md` (the `file:line` map),
`account-classification-drift-audit-2026-09-07.md` (the evidence behind v3),
`shift-memo-slice-1b-2026-09-10.md` (what slice 1b moves, account by account),
`../plans/account-classification-slice-2.md` (slice 2's survey, plan and the fourteen gaps it
pinned), `../plans/account-classification-slice-3.md` (slice 3's survey, plan and the fifteen gaps
it pinned), `../runbooks/deploy-account-classification-2.md` (the slice 2 deploy),
`../runbooks/deploy-account-classification-3.md` (the slice 3 deploy), and the contract
spec `insgt-api/spec/architecture/account_classification_spec.rb` (§5.1–§5.4 and §4.2–§4.3 pinned
on the canonical fixtures; later slices append to it).

---

## 1. Purpose

Classify all active accounts along four independent axes so that segments can be filtered in
`insgt-ops` and pushed to Pipedrive as computed labels, without any human maintaining a list.

| Axis | Question it answers | Home | Mutable |
| :--- | :--- | :--- | :--- |
| **Type** | What kind of business is this? | `accounts.account_type` | Manual, rarely |
| **Lifecycle** | How recently did they buy? | `account_metrics.lifecycle_type` | Nightly |
| **Value** | How much do they buy? | `account_metrics.value_type` / `peak_value_type` | Nightly |
| **Origin** | Where did they come from? | `accounts.marketing_source_id` (self-reported) + a derived acquisition reference, column **undecided — see D6** | Set once |

These are orthogonal by design. Every earlier attempt to express recency and frequency in a
single flat enum produced overlapping and non-exhaustive categories.

### Population

**4,067 active accounts** (dev DB, measured 2026-09-08). Under today's shoot predicate (completed
parent, order type not Reshoot or Recapture, dated by first completed log) the trailing 365 days
hold **2,005 completed parents across 937 accounts**. Under the §5.1 `property`-only universe they
hold **1,484 across 509**. The gap between those two pairs is the headline of the slice 1b shift
memo: 428 accounts have completed work in the last year and none of it is property work. The memo
(2026-09-10) found the lifetime version larger: 4,027 accounts have a completed parent under
today's predicate and 2,071 under §5.1; the 1,956 that lose every shoot are the headshot-only and
event-only histories §4.2 describes.

v1 said ~2,800. That figure was the Pipedrive record count, not the account count. v2 said 4,279,
measured 2026-09-01; that figure was stale. Dan's account cleanup of 2026-08-31 soft-deleted 219
accounts, confirmed against a production snapshot on 2026-09-08 (4,076 active, 351 deleted; the
dev restore trails it by nine). The gap between accounts and Pipedrive records — roughly 1,270 —
is a real reconciliation problem and is scoped into slice 7 (§9) rather than assumed away.

### Non-goals

- No `acquisition_channel` enum merging self-reported source with derived event origin. Two
  facts, two columns.
- No `Dormant` lifecycle value. `>3 years` does not change the action taken; sort within
  `lapsed` by `most_recent_shoot_at` instead.
- No `account_type` on the customer-facing order form.
- No bidirectional Pipedrive sync. Push only.
- **No account structure axis.** See §8, decision Q7 — the data did not support it.
- **No changes to `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` or
  `MARGIN_LTV_FIELD_VISIT_EXCLUDED_ORDER_TYPE_IDS`.** Margin is out of scope for this document
  and the constants stay untouched. §10 records what the shipped backfill says about them.

---

## 2. Vocabulary

**Parent order** — a booked job at a property or an event. The unit counted as "a shoot."

**Child order** — a separate task requiring its own photographer visit, with its own
`order_type`, timing, and scheduling logic. May be performed by a different photographer than
the parent. Carries a `parent_pays` flag indicating whether it bills with the parent or
separately. *Example: parent order Aug 1 for home photos; child order Aug 16 for aerial photos.*

**Order service** — an add-on line item (virtual staging, extra photos, delivery upgrade,
custom URL). Attaches to either a parent or a child order. **Not** an `order_type`, therefore
outside the category enum entirely.

**Reshoot** — an agent-initiated, billable return visit because the property changed: a room was
painted, staging was added or removed, the exterior looks different in another season. $145.
Entrenched customer-facing vocabulary used by agents and by Don. This meaning is correct and is
not changing.

**Recapture** — a service-recovery return visit, at $0, because Insight Photos got something
wrong. Order type id 300, key `recapture`. See §2.1.

**Qualifying shoot** — a parent order of `category_type: property`, `status_type: active`, with a
completed `order_log`. See §5.1 for the full scope definitions.

### 2.1 The Reshoot / Recapture split

Service-recovery visits have historically been booked as $0 Reshoots. That conflates a quality
event with a revenue event: the same order type carries "the seller repainted and wants new
photos" and "we blew the exposure and have to go back."

Going forward, service-recovery visits are a separate order type, **Recapture**, at $0. ADR 002
(`docs/decisions/002-recapture-order-type.md`) records the decision;
`db/migrate/20260901120000_create_recapture_order_type.rb` is the replayable record.

**Historical data is not reclassified.** There is no reliable way to distinguish a
comped-because-we-erred reshoot from a comped-because-good-customer reshoot in existing rows. The
distinction starts at the cutover date and is bounded, not backfilled.

**Cutover date:** the `created_at` of `order_types` id 300 in production, written when the
migration ran there. The migration header and ADR 002 carry 2026-09-01 as the decision date; the
deploy that created the row followed on or after 2026-09-02 (`heroku/master` a3e40e9). On the
2026-09-08 production restore the row's `created_at` is **2026-09-02 12:01:26 UTC**, which the
recapture runbook's confirmation line also records; `deploy-account-classification-1a-1b.md` step
4 re-reads it in production.

Recapture is created with `cart` NULL, which is the only thing that keeps it off the
customer-facing order form (`CartsController#items` filters `cart IS NOT NULL`). `public: false`
is also set, as documentation of intent; `order_types.public` is never used in a WHERE clause.

Predicates refer to Recapture by its pinned id, `Order::RECAPTURE_ORDER_TYPE_ID = 300`, checked by
`rake order_types:verify_pinned_ids`, not by `category_type: recovery`. ADR 002 explains why a
runtime lookup by key is unsafe inside `NOT IN (?)`: a nil there evaluates to NULL for every row
and silently empties the shoot universe.

**Known metric discontinuity.** From cutover, `lifetime_reshoot_rate` measures something
different than it did before. Reshoot becomes a pure revenue signal; Recapture becomes the
quality signal, carried by `rolling_90_recapture_rate` and `lifetime_recapture_rate`. Any
photographer KPI built on reshoot rate should read the recapture rate for periods after cutover
and should not compare across the boundary. Expect a step change in the series.
`orders:audit_reshoots` keeps reporting the "$0 total (comped)" bucket as the pre-cutover
baseline, by design.

---

## 3. Schema changes

### 3.0 Enum column convention

All new enum columns follow the existing `*_type` smallint convention (`status_type` et al.):
integer-backed, declared as a Rails enum, **values start at 1**, `prefix: true`. Starting at 1
keeps NULL as the only "unset" state and avoids 0/nil ambiguity in queries and form params.

```ruby
class OrderType < ApplicationRecord
  enum :category_type, { property: 1, brand: 2, marketing: 3, internal: 4, recovery: 5 }, prefix: true
end
```

`prefix: true` on every new enum, so the generated methods are `category_type_internal?` and
`Account.account_type_internal`, never `internal?`. Unprefixed, `internal`, `property`, `other`,
and `commercial` read as questions about the record rather than about one column, and they would
claim bare scope names on heavily-queried models for good. Both shipped enums are pinned
value-by-value in `spec/models/order_type_spec.rb` and `spec/models/account_spec.rb`, including
the absence of the unprefixed names. The `insgt-api` skill §3 owns the rule.

**Exception, deliberately taken:** the tier columns are `value_type` and `peak_value_type`, not
`value_tier_type` / `historical_tier_type`. v1 chose the longer names for suffix consistency;
they read redundantly, and "tier" survives in conversation and in this document regardless of
what the column is called. `lifecycle_type` keeps its name unchanged.

### 3.1 `order_types` — add `category_type`

**Shipped.** Four migrations, `db/migrate/20260904120000..3`: nullable add, exhaustive backfill
keyed on `order_types.key`, unvalidated CHECK, validate-and-flip. That is the repo's sequence for
any column that ends NOT NULL (`insgt-api/README.md` §Migrations). End state:

```ruby
# order_types.category_type  smallint  NOT NULL  no default
```

| Value | Int | Covers |
| :--- | :-- | :--- |
| `property` | 1 | Residential listing, commercial, property management, **Reshoot**, Quick Pics, standalone floor plan, Reprocess — Disclosure Compliance, virtual staging, custom property website address, personalized web address, Matterport hosting renewal, free Instagram reel, video walkthrough, Stagers Special, Introductory Package, Custom Package, and all child order types (aerial, Matterport, Zillow 3D, twilight, floor plan). 34 rows. |
| `brand` | 2 | Work on the agent, sold to the agent: WebPortrait, Agent Intro Video, Social Reel. 3 rows. |
| `marketing` | 3 | InsightPhotos' own lead generation: Free Web Portrait, WebPortrait Event, Headshot Event, Paparazzi, Top Agent Video, Forefront Escrow Reels. 6 rows. |
| `internal` | 4 | Not a shoot: Photo Shoot Discount, Virtual Tour Discount, Test Package, Scheduler Event, Stock Photos. 5 rows. |
| `recovery` | 5 | **Recapture**. 1 row. |

`null: false` with no default is deliberate: adding a new order type forces the classification
decision at creation rather than defaulting silently. When Insight Reels becomes an order type,
someone must decide. There is deliberately no `ensure_category_type` counterpart to `ensure_key`:
`key` can be derived from the name, a category cannot, and a guessed category is worse than a
rejected record. `OrderType` validates presence so the omission reports through `errors` rather
than as a `NotNullViolation`.

**Why `recovery` is its own category rather than `internal`.** A Recapture is real property work
at a real property requiring a real photographer trip. It earns $0 and is not a job won, so it is
excluded from counts and revenue. But it is not Test Package. Filing it under `internal` would
encode "doesn't count as revenue" while erasing "does cost a $115 field visit," in the one bucket
nobody would think to look in when margin work resumes. A separate value costs one enum slot and
keeps the physical fact queryable:

- Shoot count and revenue: `category_type = property`. Recapture out.
- Field visits, when margin is picked back up: `category_type IN (property, recovery)`.
- Photographer quality KPI: the recapture rate is the metric directly, with no price-based
  heuristic.

**Note:** because child orders carry their own `order_type`, category alone does not identify a
shoot. See §5.1.

**Backfill was exhaustive on day one.** `db/migrate/20260904120001` is the permanent record of
how the 49 rows (38 active, 11 soft-deleted) were categorised on 2026-09-04, keyed on `key`, and
it raises on any row the map misses, any key with no row, and any key listed twice. Several
placements are judgement calls no rule recovers: `free_web_portrait` is `marketing` (the
giveaway) while the paid `web_portrait` is `brand`; `reprocess_disclosure_compliance` is
`property`, not `recovery`, because it reprocesses a property shoot's photos.

**Test-only default.** `spec/factories/order_types.rb` defaults `category_type` to `property`.
Production creation paths still have to state one; a spec building an order type through the
factory does not. Specs that hand-build an `OrderType` set it explicitly
(`spec/support/completed_orders.rb`, `spec/models/order_type_key_spec.rb`, the three `release_on`
request specs). `insgt-api/CLAUDE.md` §Testing records the recipe.

**API.** The enum name crosses the wire, not the integer. `OrderTypesController` validates the
value on create and update and permits it to admin and owner only; `OrderTypesHelper` serialises
it; the ops order-type form reads and writes it.

**Slice 1b moved every predicate onto the column** through the §5.1 scopes
(`feat/account-classification-1b`, 7aa170b..afeb1f7). `Order.shoots`,
`AccountQuery#join_shoots!`, both metrics calculators, `AccountPendingShootsService`,
`ChurnReport`, `accounts:joint_ownership`, the `orders:audit_reshoots` linkage and the first-shoot
KPI read the scopes; the only id list left is the margin-only
`SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS` (§10).

### 3.2 `marketing_events` — no `event_type`

v2 proposed a five-value `event_type` on `marketing_events`. **Not added, and not planned.**

`marketing_events` is a headshot-event-only container: it groups the orders a
`MarketingEventImport` creates against one `order_type_id`
(`app/models/marketing_event_import.rb`). Paparazzi, caravan, and sponsorship work exist as
orders and are classified by `order_types.category_type` (`paparazzi` is `marketing`). Per-event
reporting therefore reads `orders.marketing_event_id` joined to `order_types.category_type`; a
second kind column on the event table would duplicate that.

There is no partial implementation anywhere: no column, no enum, no factory, no spec, no consumer
in insgt-ops. `marketing_events` has no organisation association either — v2 said it did; it has
`orders` and an optional scheduling `order` only. Recorded here because no commit message records
the decision.

### 3.3 `accounts` — add `account_type`

**Shipped.** Merged to `master` at c999b29 (2026-09-08) and deployed to production with slices 1a and 1b
on 2026-09-10 (`db/migrate/20260904120004`).

```ruby
add_column :accounts, :account_type, :integer, limit: 2   # nullable, no default; db/migrate/20260904120004
```

`account_type` — see §4.1. Nullable and undefaulted on purpose, and it stays that way: NULL means
"nobody has looked at this account," which is the distinction the classification worklist depends
on. Defaulting to `agent` would erase it across every existing row. There is no presence
validation for the same reason, and `spec/factories/accounts.rb` deliberately sets no default so
the unset state is exercised.

**`accounts.marketing_event_id` was not added.** v2's derived-origin column assumed an event is
the acquiring unit. The open alternative is `accounts.acquisition_order_id`, a foreign key to
`orders`, on the theory that acquisition is captured uniformly across event and non-event order
types — an event order still carries `orders.marketing_event_id`, so the event is reachable through
the order. This is decision **D6**, open; see §7. Nothing in code or commit history argues either
side yet; the arguments below are the ones raised in review.

- For `acquisition_order_id`: one column covers every acquisition path, event or not; the event
  is one join away; it keeps working if events stop being the only lead-generation vehicle.
- For `marketing_event_id`: it answers the per-event ROI question directly and matches v2 §5.5 as
  written; an order reference is indirect for that report.

Until D6 closes, slice 6 is blocked and §5.5 is stale.

`marketing_source_id` stays exactly as it is. Self-reported channel at signup and derived
acquisition are different facts and both are worth keeping. Do not add organization rows to
`marketing_sources` to represent headshot events.

### 3.4 `account_metrics` — nine columns and one index, in two slices

**Slice 2** (`20260911120000`, merged as `d98632f`, migrated in production 2026-09-11):

```ruby
add_column :account_metrics, :rolling_365_parent_count, :integer
add_column :account_metrics, :rolling_365_value_cents,  :bigint
add_column :account_metrics, :peak_365_parent_count,    :integer
add_column :account_metrics, :peak_365_ended_on,        :date
add_column :account_metrics, :active_user_count,        :integer
```

**Slice 3** (`20260912120000` for the columns, `20260912120001` for the index — two files, because
a concurrent index cannot run inside a transaction and a failure would otherwise leave the columns
added with `schema_migrations` unmarked):

```ruby
add_column :account_metrics, :lifecycle_type,    :integer, limit: 2
add_column :account_metrics, :lifecycle_type_at, :datetime
add_column :account_metrics, :value_type,        :integer, limit: 2
add_column :account_metrics, :peak_value_type,   :integer, limit: 2

# Its own migration, with disable_ddl_transaction!, a leading remove_index … if_exists: true, and
# algorithm: :concurrently spelled by hand in BOTH directions.
add_index :account_metrics, %i[lifecycle_type value_type],
          name: 'index_account_metrics_on_lifecycle_type_and_value_type',
          algorithm: :concurrently, if_not_exists: true
```

All nine are nullable; none takes a factory default (`insgt-api/CLAUDE.md`, "a nullable column
whose NULL means something").

**One index, not two.** v5 asked for `[:account_id, :lifecycle_type]` as well. It is not shipped:
`db/schema.rb` already carries `index_account_metrics_on_account_id` as UNIQUE, so there is at most
one row per account and a composite leading on `account_id` cannot improve any lookup that index
does not already answer — it would only be a second key to write on every nightly sweep. The kept
index serves the one access path that is not a single-row lookup, the teams-page segment filter
`WHERE lifecycle_type = ? AND value_type = ?`, and even that is precautionary over a 4,081-row,
776 kB table.

**The v5 index snippet did not run.** Written without `algorithm:`, it raises: `strong_migrations`
2.8.0 rejects any non-concurrent `add_index` against an existing table regardless of row count, and
`safe_by_default` is off in this repo. The spelling above is the one the repo's three existing
concurrent-index migrations use, and `down` repeats `algorithm: :concurrently` by hand because
`StrongMigrations.check_down` is false — nothing warns in that direction, and a plain
`remove_index` would take the ACCESS EXCLUSIVE lock the forward migration exists to avoid.

**What NULL means on the five.** Every count already on `account_metrics` is `NOT NULL DEFAULT 0`;
these are not, and the table now carries two count conventions on purpose. NULL means "not
computed since slice 2 shipped" — every row between `db:migrate` and the first
`metrics:recompute`, and every row again if the code is rolled back while the columns stay. The
calculator never writes NULL to a count: a swept account with no history reads a real 0 (§4.3's
zero rule lands on the tier columns in slice 3, not here), and `rolling_365_value_cents` reads 0
like `lifetime_value_cents`. `peak_365_ended_on` is NULL exactly when `peak_365_parent_count` is
0: no window exists. `accounts:joint_ownership` partitions on this distinction, which is why a
default was rejected.

**`peak_365_ended_on` is a UTC date**, the `::date` of the shoot timestamp that ends the peak
window. It is a cohort ordering key (§4.3) and a coarse "when were they last at peak", not an
appointment, so it does not localise; a late-evening Pacific shoot dates to the next UTC day and
the ordering is unaffected. `first_shoot_at` stays a datetime for the opposite reason
(`20260715120000`).

**No `system_metrics` mirror, no index.** Three of the five have no fleet meaning and a fleet peak
is not a sum of account peaks; nothing reads a fleet trailing-year figure. The five are read with
the row they live on, and the two orderings defined over them run across ~4,100 rows. The
"column-for-column parallel" claim in `20260901120001` holds for the shared columns only from
here.

Naming follows the existing `rolling_90_*` / `lifetime_*` convention and reuses `parent_count`
as the term for a qualifying shoot.

**`most_recent_shoot_at` already exists — do not add `last_shoot_at`.** A second column for the
same fact is how a Pipedrive label ends up disagreeing with a teams-page filter.

**Four recapture columns already exist** from ADR 002 (`rolling_90_recaptured_parent_count`,
`lifetime_recaptured_parent_count`, `rolling_90_recapture_rate`, `lifetime_recapture_rate`),
mirrored on `system_metrics`. They are outside this document.

**The two ad hoc derivations are gone.** `accounts:joint_ownership` reads
`rolling_365_parent_count` and `active_user_count` through a `LEFT JOIN account_metrics`; the
shift memo reads `rolling_365_parent_count` from the `Calculator#compute` hash it already builds.
Neither predicate exists anywhere but the calculator now. The cost is freshness: the read-out is
as current as the last `metrics:recompute`, says so on a Snapshot line, and sets accounts with no
recomputed row aside as *unweighed* — dropped from its segment, tier and top-N tables and counted
on a Context line, since neither their volume nor their team size is known — while they still take
part in the shared-owner test, which reads `accounts_users`. `scoped_accounts` is untouched, so
the "sharing an owner" count still reconciles with `accounts:composition`.

**On the wire.** `GET /accounts/:id/metrics` emits `rolling_365_parent_count`,
`peak_365_parent_count` and `peak_365_ended_on` top-level beside `rolling_90_parent_count` (counts,
readable by admins and schedulers — the inputs the slice 3 labels read, so a label is explainable
from the dialog) and `rolling_365_value_cents` inside the owner-only money block. Keys camelise.
`active_user_count` is **not** emitted: the same fact already ships live on every account row as
`user_count`, and a second name for it is the two-names failure the `last_shoot_at` rule exists to
prevent; the stored copy serves the nightly snapshot and slice 3's filters.

**`lifecycle_type_at` records when the current label first held**, and it is **derived from the
account's own history**, not stamped when a nightly sweep notices a change. It is what the
Pipedrive push debounces against, and it answers "how long have they been At Risk."

| Label | `lifecycle_type_at` |
| :--- | :--- |
| `prospect` | `NULL` — the label has no start event |
| `new` | `first_shoot_at` |
| `active` | the later of the current run's start and `first_shoot_at + 90 days` |
| `cooling` | `most_recent_shoot_at + 91 days` |
| `at_risk` | `most_recent_shoot_at + 181 days` |
| `lapsed` | `most_recent_shoot_at + 366 days` |

The three degrading stamps are the **exact instants the floored-day rule of §4.2 crosses each
boundary**: `cooling` begins at the first moment floored days reach 91, which is precisely
`most_recent_shoot_at + 91 days`. Label and stamp are therefore two readings of one number and
cannot contradict each other. Verified across all 1,863 degrading rows on the 2026-09-10 restore:
re-evaluating §4.2 **at** each stored stamp reproduces the stored label for every row. The
one-day-earlier offsets (`+90 / +180 / +365`) fail that test on all 1,863, because at those
instants the account is still in the warmer band.

**The `active` stamp is deliberately outside that re-derivation check.** It is a named calendar
offset from the first shoot, not the first instant of a band, so evaluating §4.2 at exactly
`first_shoot_at + 90 days` still returns `new` — the `new` comparison is continuous and inclusive.
That single-instant overlap is intended, and account 10288's canary depends on it. Apply the
re-derivation check to the three degrading labels only.

The `active` stamp needs the **run start** because "still coming" began when they came back, not
when they last booked. A run is an unbroken sequence of qualifying visits with no gap of 91 days
or more (the first gap that would have taken the account out of `active`). Where the run reaches
back past the first shoot, the account became `active` when it stopped being `new`, hence the
`max`. Measured: of the 152 `active` accounts, 142 have an earlier gap long enough that their run
starts after their first shoot, and the derived "active since" has a median age of 85 days against
34 for "since the last shoot" — the run start carries information the last visit does not.

**Why not a stored-row comparison.** §6 step 3 originally read "update `lifecycle_type_at` only
when the value actually changes," which describes a mechanism: compare the computed label to the
stored one and stamp `Time.current` on a difference. That was rejected on three grounds, and the
derived rule satisfies the *property* it was reaching for — a derived stamp is stable for as long
as the label holds and moves exactly when the label moves.

- **It is wrong on day one and stays wrong.** Every row would read "since the deploy date,"
  including 1,557 `lapsed` accounts whose measured median true hold is 1,655 days and whose
  maximum is 3,666. The column could not answer the question §3.4 gives it until the label next
  changed.
- **It would be the first column here to read its own previous value**, which the calculator
  rejects in writing for `peak_365_parent_count` (slice 2, G14).
- **It is not reproducible on the memo path.** `account_classification:shift_memo_1b` builds the
  calculator on an unsaved `Account.new(id:)` to read the live definition, and `Calculator#compute`
  promises in writing that it "does not look at the row." A stored comparison would either move
  into `#call`, leaving the memo's live definition incomplete, or falsify that comment.

A code rollback that leaves the columns in place, or any re-run after a restore, would also
fabricate a change on the next sweep under the stamped rule. Under the derived rule it does not.

`active_user_count` is `Account#users_count`: `COUNT(DISTINCT users.id)` over `accounts_users`
with the membership active **and** the user active — the predicate behind `has_many :users`, the
one the accounts index already ships as `user_count`, and the one Q7 measured with. v4 said "a
plain `COUNT(*)`"; that counts roles, because `accounts_users` holds one row per (account, user,
role) with no unique constraint (440 pairs held more than one active role on the 2026-09-10
snapshot). Measured against the plain count: 411 accounts differ and the multi-user population
reads 453 instead of 102; account 10288 reads 9 where it has 6 people. No judgment, no manual
classification. It exists so the teams page can find the ~100 multi-human accounts that a team or
brokerage product would be sold into. It is a derived fact, not a classification axis — see §8,
Q7. The calculator calls the method rather than restating the condition, and calls `users_count`
rather than `users.count` because the shift memo builds the calculator on an unsaved
`Account.new(id:)`, where the association is a null scope.

---

## 4. Enums

### 4.1 `accounts.account_type`

`agent: 1` · `property_manager: 2` · `homeowner: 3` · `builder: 4` · `commercial: 5` ·
`affiliate: 6` · `internal: 7` · `fsbo: 8` · `other: 9`

- `homeowner` and `fsbo` are distinct: a homeowner ordering photos through an agent is not the
  same customer as one selling the property themselves.
- `affiliate` — escrow, title, lender (industry term; not "partner")
- `internal` — test and staff accounts. Given 19 years of accumulated data, one predicate that
  excludes junk from every segment justifies the slot by itself.

`fsbo` was split out of `homeowner` when the enum was implemented; v2 as first written listed eight
values with FSBO glossed onto `homeowner`. **The integers are the contract — a value may be added
but never renumbered or reused — so `other` is 9, not 8.** This paragraph exists so a reader
holding an older copy can tell a correction from a renumbering. The enum as shipped is
`app/models/account.rb`, pinned value-by-value in `spec/models/account_spec.rb`.

Manual entry only. The API serialises the enum name to admin, scheduler, owner, and processor
roles and omits it for photographers; admin, owner, and scheduler may set it; a blank clears it.
The accounts index accepts `account_type=<name>` and the sentinel `account_type=unset` for the
worklist (`Account::UNCLASSIFIED`).

Backfill by confidence tier: brokerage present + property orders → `agent`; organization linked
to a NARPM-affiliated org → `property_manager`; known test patterns → `internal`. Everything else
stays NULL. Worklist is `account_type IS NULL` ordered by `rolling_365_parent_count DESC`; the
filter exists and the column exists (slice 2); the ordering ships with slice 4's remaining work,
not with the column — see §9 for why and the sketch.

**Four existing constants are the seed for the `internal` backfill, and they disagree with each
other.** `MarketingSourceMetricsService::EXCLUDED_ACCOUNT_IDS = [2, 2555]`,
`MARGIN_LTV_EXCLUDED_ACCOUNT_IDS = [2, 2555]` (`lib/tasks/metrics.rake`),
`AccountReport::IGNORE_ACCOUNT_IDS = [2, 89, 2555]`, and
`AccountAudit::COMPOSITION_EXCLUDED_ACCOUNT_IDS = [2, 89, 2555]` (`lib/tasks/accounts.rake`).
Account 89 ("Insight Photos Marketing", three parent orders 2022–2023) is excluded by two and
counted by two. Determine which is correct before seeding, because whichever answer is used
becomes the answer. Once `account_type: internal` is populated, all four retire in favour of the
column; until then `Account#account_type` does not supersede them.

**The `property_manager` backfill heuristic reads unaudited data.** It depends on
`accounts_organizations` (untyped) and `organizations.type_of`, where `set_type!` silently
defaults blank to `brokerage`, five of the eight enum values have no code path, and there is no
`property_management` type at all. An organization type audit is a prerequisite of slice 4, not a
separate concern. It belongs to the accounts-versus-users workstream (§8, Q7) and slice 4 blocks
on it.

**Status 2026-09-10.** Column, model, API, role gates and index filter are in production (deployed
with slices 1a and 1b); the ops edit dialog and filter are on insgt-ops `main` and ship with its
next release. The 2026-09-10 production snapshot holds five hand-classified accounts (one `agent`,
four `internal`); the twelve classified in the dev DB on 2026-09-05..07 did not survive the
restore and were test entries. No tiered backfill task exists; the organization type audit has
not started.

### 4.2 `account_metrics.lifecycle_type`

Six values, derived from `most_recent_shoot_at` and `first_shoot_at`.

| Value | Int | Rule |
| :--- | :-- | :--- |
| `prospect` | 1 | `most_recent_shoot_at IS NULL` |
| `new` | 2 | `first_shoot_at` within 90 days — **precedence over `active`** |
| `active` | 3 | ≤ 90 days since `most_recent_shoot_at` |
| `cooling` | 4 | 91–180 days |
| `at_risk` | 5 | 181–365 days |
| `lapsed` | 6 | > 365 days |

`new` and `active` overlap by construction. The precedence rule is stated so two correct
implementations cannot produce different answers.

**The arithmetic, pinned.** The three degrading boundaries compare **floored whole days**; `new`
is a **continuous** comparison against 90 days. The asymmetry is inherited from the rule slice 1b
already shipped in the shift memo, and it is preserved deliberately rather than tidied: the table
above is written in whole days, floored days are what Don was already shown, and unifying `new`
onto floored days was measured to change 0 of 4,078 accounts.

```ruby
return :prospect if most_recent_shoot_at.nil?
return :new if first_shoot_at && (now - first_shoot_at) <= 90.days

days = ((now - most_recent_shoot_at) / 1.day).floor
if days <= 90 then :active elsif days <= 180 then :cooling elsif days <= 365 then :at_risk else :lapsed end
```

A day exactly on a boundary belongs to the **warmer** label: 90 days is still `active`, 365 days is
still `at_risk`. Measured on the 2026-09-10 restore, the floored rule differs from a continuous
interval for 2 of 4,078 accounts (2394 and 3661, both 365.8 days out; `at_risk` under the floor
rule), and for 0 accounts on the `new` boundary. Both had crossed into `lapsed` under either rule
three days later, which is the drift these labels are supposed to have.

**`new` is a pure override, never a tie-break.** `most_recent_shoot_at >= first_shoot_at` always,
so a first shoot inside 90 days implies a visit inside 90 days: every `new` account also satisfies
the `active` rule. Measured: 0 accounts have a first shoot inside 90 days and no visit inside 90
days. The precedence rule therefore only ever *overrides*; it never breaks a tie between two
labels that could both have been reached.

**Distribution.** On a full production sync of 2026-09-14 (4,136 active accounts, every one swept
under this code): `prospect` 2,061 · `new` 58 · `active` 156 · `cooling` 133 · `at_risk` 168 ·
`lapsed` 1,560. On the earlier 2026-09-10 restore evaluated 2026-09-11 14:20 UTC (4,078 accounts),
the figures the plan reasoned out before the code existed and which the implementation reproduced
exactly: `prospect` 2,004 · `new` 61 · `active` 152 · `cooling` 138 · `at_risk` 166 ·
`lapsed` 1,557. These drift with the clock and must be re-derived on any deploy day: replayed
three days later the same data gave `new` 58 · `active` 153 · `cooling` 134 · `at_risk` 169 ·
`lapsed` 1,560, with all 13 movers identifiable by account id. Measured churn with no new shoots:
2 accounts change label the next day, 29 within seven days. How long each degrading label has
actually held, derived from history: `cooling` median 41 days (max 90), `at_risk` median 73
(max 185), `lapsed` median 1,655 (max 3,666).

**`lapsed` implies `value_type IS NULL`**, structurally: no qualifying visit in 365 days means no
qualifying parent in 365 days. Measured — every one of the 1,557 `lapsed` accounts and all 2,004
`prospect` accounts carried a NULL `value_type`. The two labels are still orthogonal where it
matters: account 1842 is `cooling` with `value_type: anchor`, and 2687 is `at_risk` with `core`.

**Lifecycle cannot flap.** Days-since-last-shoot increases monotonically between shoots and
resets on a new one. It degrades, then jumps back on a real event. No hysteresis needed.

**`prospect` holds two different populations.** Because `qualifying` is property-only, any account
that transacts exclusively on headshots or events has `most_recent_shoot_at IS NULL` and reads
`prospect`, even with real revenue. Measured 2026-09-08: 428 accounts completed work in the
trailing 365 days and none of it was `property` (437 on the 2026-09-10 restore). Over all
history the population is larger: 1,956 of the 4,027 accounts with a completed parent today have
no property shoot at all and read as prospects once slice 1b ships (memo). Two cases:

- A headshot-only agent who has never bought listing work. Genuinely a prospect. Correct.
- An organization-as-account, e.g. the SDAR account carrying paparazzi orders. Transacts
  regularly. Reading it as a prospect is wrong.

There is currently no marker distinguishing an organization-proxy account from an agent account.
The typed `accounts_organizations` edge that would provide one lives in the accounts-versus-users
workstream. Until then, the mitigation is a filter, not a schema change: **exclude
`account_type IN (internal, other)` from any prospect outreach segment or Pipedrive prospect
push.** An account with `lifecycle_type: prospect` and non-zero `rolling_365_value_cents` is also
a useful review flag for the classification worklist.

### 4.3 `value_type` and `peak_value_type`

Shared enum:

| Value | Int | Parent shoots in window |
| :--- | :-- | :--- |
| `single` | 1 | 1 |
| `occasional` | 2 | 2–5 |
| `core` | 3 | 6–11 |
| `anchor` | 4 | 12+ |

`value_type` reads `rolling_365_parent_count`. Current worth; decays, which is correct.
`peak_value_type` reads `peak_365_parent_count`. Monotonic against the passage of time — ageing
shoots out of the window can only lower the rolling count, never this one — but it is recomputed
from history every night like every other column, not ratcheted against its own stored value. A
reschedule that pulls a shoot out of the run, a soft-deleted order, or an order type whose
category changes can lower it, and that is correct for the same reason §5.3 gives for
`first_shoot_at` moving: history was edited. `max(stored, computed)` was rejected — it would
freeze an inflated peak from a deleted duplicate order and be the first column to read its own
previous value.

**NULL, not `single`, when the count is zero.** A zero count is a real zero; the tier is
undefined. Consistent with the propagate-null convention, and with the precedent already in the
calculator: a rate over a zero denominator stores NULL rather than `0.0000`, so "no shoots yet"
stays distinguishable from "0%".

This makes `account_metrics` carry **two NULL conventions across the four slice 3 columns**, and
the difference is load-bearing. On `value_type` and `peak_value_type`, NULL is a fact about the
*account*: the count is zero. On `lifecycle_type`, NULL is a fact about the *sweep*: the row has
not been recomputed since slice 3 shipped. An account that has never been shot is `prospect`, not
NULL — that is what the label is for. `lifecycle_type_at` follows `lifecycle_type` except that it
is also NULL for every `prospect`, which has no start event. The resulting invariant, checked
after every sweep: `lifecycle_type_at IS NULL` exactly when the row is unswept or the account is a
`prospect`.

The trap this hides is that both counts are coerced to a real `0` upstream and are never nil, so a
band lookup that does not special-case zero files every shootless account under `single` — 3,563
of 4,078 rows on the survey restore, the single largest population in the fleet.

`lib/tasks/accounts.rake` mirrored these bands as `SHOOT_VOLUME_TIERS` for the joint-ownership
read-out, with a separate "no shoots" row for the zero case, and its own comment promised the two
must not diverge once the columns landed. **Slice 3 closed that**: the four ranges are now read
from `AccountClassification::VALUE_BANDS` and only the printed labels stay local. The read-out's
output was verified byte-identical before and after.

**Distributions.** On the 2026-09-14 production sync (4,136 accounts), `value_type`: NULL 3,621 ·
`single` 279 · `occasional` 177 · `core` 40 · `anchor` 19; `peak_value_type`: NULL 2,061 ·
`single` 1,072 · `occasional` 701 · `core` 191 · `anchor` 111. On the 2026-09-10 restore (4,078),
`value_type`: NULL 3,563 · `single` 277 · `occasional` 178 · `core` 41 · `anchor` 19;
`peak_value_type`: NULL 2,004 · `single` 1,071 · `occasional` 701 · `core` 191 · `anchor` 111. The
reactivation cohort is 42 accounts on both.

**Two identities worth checking after any sweep**, because they are structural rather than
incidental and hold on both datasets. NULL `peak_value_type` equals the `prospect` count exactly:
no visit ever means no parent ever. NULL `value_type` equals `prospect` plus `lapsed` exactly: no
visit in 365 days means no parent in 365 days. On the 2026-09-14 sync that is 2,061 and
2,061 + 1,560 = 3,621. Note that
`peak_value_type` does **not** drift with the clock — it is monotonic against the passage of time —
so unlike the lifecycle figures, movement there between two runs over the same data is a finding
rather than expected decay.

**Band-edge population, for the flap the debounce exists to absorb:** 277 accounts sit at a
trailing count of 1, 79 at 2, 26 at 5, 3 at 11 and 4 at 12. Nothing in slice 3 debounces; the push
is slice 7's, at the push boundary, by design.

`value_type` *can* flap as shoots roll off the back of the window. Store the true value nightly
and debounce at the Pipedrive push boundary (§6), not in the database. Ops sees truth.

**Reactivation cohort:** `lifecycle_type = lapsed AND peak_value_type = anchor`, ordered by
`peak_365_ended_on DESC`.

---

## 5. Derivation rules

### 5.1 Scopes

Three scopes, one base. The split is **visit versus money**, not parent versus child. **Shipped
in slice 1b** (`app/models/order.rb`, 7aa170b); the code below is the shipped shape, and the
contract spec pins it on the canonical fixtures.

```ruby
# Building block: active, category property. Not a consumer scope — it exists so qualifying and
# pending_shoots are the same base plus one condition each.
scope :property_work, -> {
  joins(:order_type)
    .where(order_types: { category_type: OrderType.category_types[:property] })
    .where(status_type: StatusType.active)
}

# Did we go there? Parents and children. No payment condition.
scope :qualifying, -> { property_work.where(completed_log_sql) }

# Is it a shoot? The above, parents only.
scope :qualifying_parents, -> { qualifying.where(parent_id: nil) }

# Did they pay us? All categories except internal. No completion condition.
scope :billable, -> {
  joins(:order_type)
    .where.not(order_types: { category_type: OrderType.category_types[:internal] })
    .where(status_type: StatusType.active)
    .where.not(paid_at: nil)
    .where('orders.parent_pays IS NOT TRUE')
}

# Booked ahead (§5.2): the same base, parents only, NOT completed, not cancelled.
scope :pending_shoots, -> {
  property_work
    .where(parent_id: nil)
    .where.not(completed_log_sql)
    .where('orders.scheduled_at >= ?', Time.current)
    .where('orders.order_event_id IS NULL OR orders.order_event_id != ?', OrderEvent.canceled_id || -1)
}
```

`Order.completed_log_sql` is the `EXISTS` over `order_logs` for the `completed` event and
`Order.shoot_date_sql` (§5.3) sits beside it: class methods returning sanitized SQL fragments over
the `orders` alias. `OrderEvent.completed_id` and `canceled_id` are memoised per process.

**`qualifying_parents` is defined as `qualifying` plus one condition**, never assembled
independently; the contract spec asserts the two relations' SQL differ by exactly that clause.
Everything downstream reads one of these; nothing re-derives them, raw SQL included. **A raw-SQL
consumer takes the relation's `to_sql` into a CTE or an `IN (…)`** — `AccountMetrics::Calculator`
is the pattern — never a copy of the conditions. `to_sql` inlines every value as a literal, so
the text carries no `?` for positional binds to collide with; the contract spec pins that too.

**`billable` is deliberately not named `qualifying_*`.** The two answer different questions and
must not look interchangeable at call sites. A revenue query written against `qualifying` out of
habit returns a silently low number with no error.

**`pending_shoots` is a derivation, not a fourth question.** `AccountPendingShootsService` counts
it live, and the teams "only did one shoot" filter uses it as its in-flight exclusion: the count is
the contract's (`qualifying_parents`, paid), the exclusion is the segment's own because it feeds
outreach, and an account with one completed shoot and another booked ahead is not a one-shoot
account to call. It includes reshoots and excludes recaptures, like the completed count it sits
beside on the account dialog — decision of 2026-09-08, amending Q2.

**One derivation lives outside `order.rb`.** The `orders:audit_reshoots` linkage read-out splits
the denominator into "in the universe" (`property_work` parents) and "completed", so its three
uncounted buckets stay distinct. It says so where it does it.

**`SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS` survives for margin only** (§10): `margin_visit_count`
in both calculators and `metrics:margin_ltv_exclusion_impact`. `FIELD_JOB_EXCLUDED_ORDER_TYPE_IDS`
and `Order.shoots` are gone; `RESHOOT_ORDER_TYPE_ID` names a kind of child in the reshoot-rate
numerators and nothing else.

Which scope drives what:

| Reads `qualifying` | Reads `qualifying_parents` | Reads `billable` | Reads `pending_shoots` |
| :--- | :--- | :--- | :--- |
| `first_shoot_at` | `rolling_365_parent_count` | `rolling_365_value_cents` | `AccountPendingShootsService` |
| `most_recent_shoot_at` | `peak_365_parent_count` | `lifetime_value_cents` and the LTV columns | `where_only_once`'s in-flight exclusion |
| CSV export "First Shoot" | `lifetime_parent_count` | | |
| `AccountReport.first_shoot_kpi_rows` | `rolling_90_parent_count` | | |
| | reshoot and recapture rate denominators | | |
| | `median_shoot_value_cents`, `average_shoot_value_cents`, rolling-90 value pair | | |
| | `Account#order_count`, CSV export "Order Count" | | |
| | `AccountQuery#join_shoots!` (`where_only_once`, `where_created_on`) | | |
| | `ChurnReport` (plus the caller-injected exclusions) | | |
| | `accounts:joint_ownership` | | |
| | `orders:audit_reshoots` linkage denominator | | |



### 5.2 Why completed log, not status

**`status_type` does not encode cancellation.** It has exactly two values, `active: 1` and
`deleted: 2`, both soft-delete. Cancellation lives in `orders.order_event_id` against the
`OrderEvent` whose tag is `canceled` — one L, and every existing consumer looks it up by that
string.

Rather than a negative predicate over an open set of terminal states, the scope uses a positive
predicate: **a shoot is a parent with a completed `order_log`.** This is what
`AccountMetrics::Calculator` already does (over its own id-based universe), and it disposes of
three questions without a ruling:

- **Cancelled** — never gets a completed log. Excluded automatically.
- **Booked but never delivered** — never gets a completed log. Excluded automatically.
  `AccountPendingShootsService` surfaces these separately and live, which is the correct home
  for a forward-looking count.
- **Any terminal state invented later** — excluded by default rather than by remembering to add
  it to a blocklist.

Same reasoning as `null: false` with no default on `category_type`: force the decision, don't
default silently.

**The dependency this creates:** completion hygiene. A shoot that happened but was never marked
complete does not count. `AccountPendingShootsService` bounds its window to `scheduled_at >= now`
specifically because orders get abandoned and never closed. If that population is large, the
count runs behind reality. Measured 2026-09-10 (memo): 201 property parents scheduled in the
past with no completed log — 21 under 30 days old, 2 at 31–90 days, 14 at 91–365, 164 over a year
(12 of those in canceled state). Small; the 23 under 90 days are the accounts whose
`most_recent_shoot_at` may read older than reality. No fix in slice 1b.

### 5.3 Shoot date

**`COALESCE(orders.scheduled_at, MIN(order_logs.created_at))`** where the log is the completed
event. Shipped as `Order.shoot_date_sql`, a correlated scalar subquery
(`COALESCE(orders.scheduled_at, (SELECT MIN(order_logs.created_at) …))`) so one string serves a
scope `select`, a `pluck`, a `minimum`, and the calculators' CTEs. Every dated consumer calls it:
both calculators, `ChurnReport`, `accounts:joint_ownership`, the CSV export, and the first-shoot
KPI. On the 2026-09-08 restore, 2 completed property parents have no `scheduled_at` and take the
fallback.

`paid_at` is out. It cannot produce a date for a row the predicate accepts: a completed but unpaid
shoot has `paid_at IS NULL`, and pay-after-delivery guarantees a window where that is true for
every order. `paid_at` was never a date semantic; it was standing in for the headshot exclusion
(the `where_only_once` comment says as much), and `category_type` now does that job properly.

`scheduled_at` is the day the photographer was at the property. It is what Don means by "their
last shoot," it matches the field `AccountPendingShootsService` uses on the forward side, and it
stays correct when an order sits unclosed for months.

`scheduled_at` is mutable, so a reschedule rewrites history and `first_shoot_at` can move
backward. This is correct behaviour: the visit genuinely happened on the new date.

**The KPI moved with it.** `db/migrate/20260715120000` chose `paid_at` so `first_shoot_at` would
agree with `AccountReport#first_shoot_kpi_year_ago`; the reconciliation now runs the other way.
`AccountReport.first_shoot_kpi_rows` (slice 1b) reads the earliest `qualifying` visit by this date
and counts `qualifying_parents`, with no payment condition, so it and `first_shoot_at` cannot
disagree. `AccountReport.annual_report` still carries `paid_at`-based first-order columns; it was
not named by this document and was left alone, so its "first date" can differ from
`first_shoot_at` by the payment lag.

**Direction of the shift, measured** (`shift-memo-slice-1b-2026-09-10.md`): `most_recent_shoot_at`
moves for every dated account, since `paid_at` never equals `scheduled_at` — earlier for 1,950
accounts and later for 104 (prepaid orders are paid before the visit), 93% by under 7 days; 75
accounts change §4.2 bucket on the day this ships. **v3's "3,004 undated shoots gain a date" was
wrong in kind:** those are completed parents with no `paid_at` under the old universe (2,972 on
the newer restore), and only 162 of them are property and gain a date; the rest are headshot and
event parents that leave the universe entirely. 17 accounts gain a date, 46 lose one (paid
non-property work only).

### 5.4 Counts, dates and revenue

**Counts** — `qualifying_parents`. Parents only. A child order never increments a shoot count,
and neither does an order service.

- `rolling_365_parent_count` — qualifying parent shoots in the trailing 365 days: the rolling-90
  count's window with the cutoff moved, `shoot_at >= now − 365 days`, inclusive, no upper bound.
- `peak_365_parent_count` — the maximum of that rolling-365 series over the account's full
  history, evaluated at each qualifying shoot date: for each shoot dated *e*, the count of shoots
  in the closed window [*e* − 365 days, *e*]. `peak_365_ended_on` is the *e* of the maximal
  window, the latest such *e* on a tie, as a UTC date. One window function over the same shoots
  CTE the rolling count reads (`RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW`).

  The window runs **backward** from each shoot, where v4 said forward. The maximum is identical
  either way — slide any maximal window until an end meets a shoot and the count is unchanged;
  verified against an independent pass over all 2,074 accounts with shoots — but the end date is
  not: backward, it is the last shoot of the peak run, always a real date in the past, which is
  what "ordered by `peak_365_ended_on DESC`" (§4.3) needs; forward, it is *d* + 365, in the future
  for anyone whose peak run is recent. `rolling_365_parent_count <= peak_365_parent_count` always,
  since the trailing window is one of the windows the peak ranges over.

**Dates** — `qualifying`. Parents **and** children.

A child order is a real photographer visit to the property on its own date, potentially by a
different photographer. It updates `most_recent_shoot_at`. The visit is the fact being recorded,
so `parent_pays` is deliberately absent from the date predicate — a parent-paid aerial on Aug 16
and a separately-billed aerial on Aug 16 are the same day at the same property, and a checkout
convenience flag should not separate them.

The child still has to qualify: a cancelled aerial or a Recapture child does not move the date.

`first_shoot_at` is unaffected by child inclusion in practice. A child cannot exist without a
parent and the parent is always earlier, so the earliest qualifying row is a parent either way.
Stated so nobody later assumes an asymmetry that isn't there.

**Revenue** — `billable`, plus order service revenue.

`parent_pays IS NOT TRUE` is load-bearing and is the existing convention in every revenue query
in the codebase (`MarketingSourceMetricsService`, `MarketingSourceAccountsService`,
`AccountReport`, `orders:audit_reshoots`). A child order with `parent_pays = true` may carry an
`order_type_price` of $145, but that $145 was collected on the parent and is already in the
parent's total. Counting it again double-counts. A self-paying child (`parent_pays = false`, the
default) counts its own revenue.

Write `IS NOT TRUE`, not `= false`. Every existing consumer does. No active child order has a NULL
`parent_pays` today (3,731 true, 1,231 false, measured 2026-09-07); `IS NOT TRUE` is kept so that
stays true by construction.

**Shipped in slice 1b.** `lifetime_value_cents` reads `billable` plus the order services on those
rows in both calculators (9e86a49). Measured on the 2026-09-08 restore (memo): the fleet total
falls from $4,474,186 to $3,698,648. The $775,538 drop is $705,240 of `parent_pays` children
(price plus services on all 3,843 of them; v3's $684,555 was `order_type_price` on the 3,726 that
carry one), $70,293 of unpaid or refunded rows, and $5 of `internal`. Transactions confirm the
`parent_pays` rule: for 2,799 of 2,820 paid parents with such children, Stripe charged the
parent's own price alone. The new total sits $88,816 above Stripe's net charges, which is 895
billable orders with no transaction row (manual and offline payments) less two small terms; the
memo carries the bridge, residual $0.

**What one shoot is worth** (`median_shoot_value_cents`, `average_shoot_value_cents`, the
rolling-90 pair): the parent's own `order_type_price` plus its own order services, over
`qualifying_parents`. Not plus `parent_pays` children (their price is inside the parent's), not
plus self-paying children (their own billable line). So Σ shoot values and `lifetime_value_cents`
answer different questions — list price of jobs done versus money collected — and reconcile only
through a bridge: Σ shoot values − unpaid or refunded qualifying parents + paid self-paying
children + paid brand and marketing parents + paid property parents with no completed log =
`lifetime_value_cents`. The memo measures each term; residual $0.

Revenue covers **all categories except `internal`**. A $125 WebPortrait is real money and belongs
in LTV; a $5 Test Package does not. Recapture excludes itself naturally — $0 means no `paid_at`.
(One `internal`-category order in 19 years carries a `paid_at`, for $5.)

`parent_pays` affects attribution, not timing. A child order's revenue is placed in the trailing
window by **the child's own `scheduled_at`**, resolved the same way as §5.3. Child orders have
independent timing by design.

**Refunds self-correct.** `Order#issue_refund` nils `paid_at`, so a refunded order drops out of
`billable` on the next nightly run with no special handling. It keeps its completed log, so it
still counts as a shoot and still sets recency, at zero revenue. That is correct — we went, we
delivered, the money came back — but it means `rolling_365_parent_count` and
`rolling_365_value_cents` can disagree in a way that looks like a bug and is not.

**The mirror case is also not a bug.** `billable` carries no completion and no cancellation
condition, and `rolling_365_value_cents` adds none: a paid, unrefunded order that was cancelled
after payment is revenue in the window while it is not a shoot, so the value can be positive where
the count is 0 (3 accounts on the 2026-09-10 snapshot). `rolling_365_value_cents` is the
trailing-365 slice of `lifetime_value_cents` — the same `billable` rows, the same per-row
expression, filtered to rows whose *own* §5.3 date falls in the window; a billable row that is
neither scheduled nor completed has no date and falls out of it (0 such rows today). Hence
`rolling_365_value_cents <= lifetime_value_cents` always.

### 5.5 Origin

**Stale pending D6.** v2 derived origin into `accounts.marketing_event_id` from the account's
earliest `brand` or `marketing` order that carried an event. That column was not added (§3.3).

The rule survives in shape: set once, from the account's **earliest** order only, immutable —
which is why it lives on `accounts` and not in `account_metrics`. An account that has been buying
for three years and then attends a PSAR headshot event was not acquired by that event. But the
target column, and therefore the predicate, are undecided until D6 resolves between
`marketing_event_id` and `acquisition_order_id`. Do not implement from this section.

### 5.6 Cancel At Door

**No predicate change.** Documented here because §5.1 invites the question and the schema does not
answer it.

Cancel At Door is a $35 `order_service` line item (`Service::CANCEL_AT_DOOR_ID`), not an order
type and not a status. The usual workflow is that the photographer is turned away, the fee is
added to the order, the shoot happens later on the same order, and the agent pays the shoot fee
plus the $35.

Measured 2026-09-01: **14 orders in 19 years**, totalling $3,335, with order totals of $215, $230,
$385, $250 and similar. These are full delivered shoots carrying an extra line item, not $35
no-media orders. They qualify, they should qualify, and their shoot values are correct.
`orders:cancel_at_door` is the read-out.

One of the 14 is unpaid at $230, presumably a case where the shoot never happened. Under the
completed-log predicate it is excluded automatically if nobody closed it, which is the right
outcome arrived at by accident rather than by design.

The $115 field-visit cost of a turned-away trip is invisible in all 14 cases. That is a margin
question and margin is parked.

---

## 6. Nightly job

Extend the existing `account_metrics` recompute (`metrics:recompute`, `AccountMetrics::RecomputeAll`)
rather than adding a second job.

1. Recompute numeric columns from `Order.qualifying`, `Order.qualifying_parents` and
   `Order.billable`. **Done in slice 2:** four merges on `AccountMetrics::Calculator`, no change to
   `RecomputeAll` or the rake task; +3 ms per account, ≈ +12 s over the fleet, 50 s wall on the
   dev restore. **The production sweep runs 2 min 36.89 s, 0 failed over 4,078 accounts**
   (2026-09-11). That is the baseline slice 3 extends, not the restore's 50 s: `heroku run` dyno
   start-up and the network hop to the database are inside it, and the prior production duration
   was never recorded.
2. Recompute `active_user_count` from active `accounts_users`. **Done in slice 2**, as
   `Account#users_count` (§3.4).
3. Derive `lifecycle_type`, `value_type`, `peak_value_type` and `lifecycle_type_at` from a single
   thresholds config object. **Done in slice 3:** one more merge on `AccountMetrics::Calculator`,
   taking the accumulated hash rather than running its own queries, plus one new window query for
   the active-run start. No change to `RecomputeAll` or the rake task.
   **The production sweep ran 2 min 37.79 s over 4,136 accounts, 0 failed** (2026-09-14), against
   slice 2's baseline of 2 min 36.89 s over 4,078. The
   extra window query therefore costs under a second across the whole fleet. That 2 min 37.79 s is
   the baseline slice 4 extends, not the 1 min 06 s the same sweep takes on a local sync of the
   same accounts: `heroku run` dyno start-up and the network hop sit inside the production figure.

   `lifecycle_type_at` is **derived from history** rather than stamped when the sweep notices a
   change (§3.4 carries the table and the three reasons). This preserves what this step was
   asking for — the stamp moves exactly when the label moves and is otherwise stable — while
   dropping a mechanism that would have been wrong on day one for every row, would have made this
   the first column to read its own previous value, and would have broken the shift memo's
   unsaved-account path.
4. Push changed computed fields to Pipedrive.

**Thresholds live in one Ruby config object**, not scattered across the job. Retuning a boundary
should not require a migration; the nightly run backfills.

That object is **`AccountClassification`, in `insgt-api/lib/account_classification.rb`** (slice 3):
frozen constants for the §4.2 day boundaries and the §4.3 volume bands, and three pure lookups over
them. No database, no model, and no enum integers — §3.0 puts those on `AccountMetric`, so the
config returns names and the model maps names to integers, with the contract spec pinning the two
vocabularies against each other in both directions.

It lives in `lib/` because the dependency direction is **forced, not chosen**:
`config.autoload_lib(ignore: %w[assets tasks])` means `lib/tasks/*.rake` is not autoloaded, so
`app/services` cannot reference anything defined in a `.rake` file. The shared rule therefore had
to move out of the rake file, and the rake files read it.

Three artifacts now read it, and there is no fourth copy of either rule:

- `AccountMetrics::Calculator#classification` — the stored columns.
- `AccountClassificationShiftMemo#lifecycle` and `#lifecycle_order`
  (`lib/tasks/account_classification.rake`) — the memo's live definition, which is only meaningful
  as a comparison if it and the stored column come from one rule.
- `AccountAudit#shoot_volume_tiers` (`lib/tasks/accounts.rake`) — the joint-ownership read-out's
  bands, keeping its own printed labels and its own "no shoots" row.

**A rake file must read the config lazily, inside a task.** `rakefile` requires
`config/application` and calls `load_tasks` *without* initializing the application, so Zeitwerk is
not yet set up while `.rake` files are being read. A constant in a `.rake` file that references
`AccountClassification` at file-load time aborts **every** `rake` invocation in the repo,
`db:migrate` included, with `NameError`. The two read-outs above resolve it in a memoised method
instead. The rake specs do not catch this, because they load task files through
`Rake.application.rake_require` inside an already-initialized app.

**Store inputs beside labels.** `lifecycle_type = lapsed` sitting next to `most_recent_shoot_at`
and `rolling_365_parent_count` means the label is always explainable without re-running anything.
Same principle as storing numerators alongside rates.

### Pipedrive push boundary

- One-way. Computed fields only. No Pipedrive code exists yet.
- The job writes to an **explicit whitelist of field IDs**. A push that syncs "everything on the
  account" will eventually overwrite a Judgment label set by hand, and that is the failure that
  makes the sync untrustworthy.
- The whitelist ships with Type, Lifecycle, and Value. Origin joins it when D6 closes and slice 6
  lands (§9).
- Debounce `value_type` changes: require the new value to hold before writing, so boundary
  oscillation does not fill the activity feed.
- **Reconciliation precedes push.** See §9, slice 7.

---

## 7. Resolved decisions

All five v1 open decisions are closed. One new decision, D6, is open. Recorded with reasoning
because the answers are not obvious from the schema.

**D1 — Does a child order update `most_recent_shoot_at`? → Yes.**
Reversed from v1's recommendation. A child order is a real photographer visit to the property on
its own date. The date column records visits; the count column records jobs won. They read
different rows deliberately, and §5.4 states which is which. `parent_pays` is deliberately absent
from the date predicate.

**D2 — Which date places child order revenue in the trailing-365 window? → The child's own
`scheduled_at`.**
Child orders have independent timing by design. `parent_pays` governs attribution (§5.4), not
placement in time.

**D3 — Which `status_type` values disqualify an order? → The question doesn't apply.**
`status_type` has two values, both soft-delete. Cancellation lives in `order_event_id`. Replaced
by the positive completed-log predicate. See §5.2.

**D4 — Do `first_shoot_at` and `most_recent_shoot_at` currently exclude non-property orders?
→ Partly, and by accident.**

The date columns exclude them incidentally: `shoot_dates_sql` reads `MIN/MAX(paid_at)`, Postgres
skips NULLs, and headshots and events are always $0 with no `paid_at`. So lifecycle built on
`most_recent_shoot_at` was not producing the failure v1 feared.

The count and value columns do not exclude them at all. `parent_counts_sql` has no `paid_at`
filter, so any parent with a completed log counts — including $0 Headshot Event, WebPortrait
Event, Event Photos, Event Video, Paparazzi and Scheduler Event orders. Consequences today, before
any of this ships:

- `lifetime_parent_count` includes non-property parents while `most_recent_shoot_at` excludes
  them. Two columns in one table, two universes.
- `lifetime_reshoot_rate` divides by an inflated denominator, understating the rate for any
  account with headshot history.
- `median_shoot_value_cents` and `average_shoot_value_cents` admit $0 parents at
  `shoot_value = 0`. An account with three property shoots and four headshot events has a median
  shoot value of $0 **right now**.

Three predicates are in production and no two agree; all three exclude Recapture:

| Site | Reshoots | Headshots | Recapture | Requires delivery |
| :--- | :--- | :--- | :--- | :--- |
| `Order.shoots` (`FIELD_JOB_EXCLUDED_ORDER_TYPE_IDS`) | in | out | out | no |
| `AccountQuery#join_shoots!` (same list, raw SQL) | in | out | out | no |
| `AccountMetrics::Calculator` (`SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS`) | **out** | **in** | out | **yes** |

**Resolved 2026-09-10.** All three predicates are gone; every consumer reads §5.1 and the shift
memo records the move.

**D5 — Confirm the coined column names. → Switch to `lifecycle_type`, `value_type`,
`peak_value_type`.** See §3.0.

**D6 — Which column records acquisition: `accounts.marketing_event_id` or
`accounts.acquisition_order_id`? → Open.**
See §3.3 for the arguments recorded so far. Slice 6 and §5.5 wait on it. Slice 7 does not.

---

## 8. Decision log

Ten questions, settled 2026-09-01. Recorded with the argument against, so a future reader can tell
which decisions were close and which were forced.

**Q1 — One shoot definition or two? → One, applied everywhere.**
The cheaper option was to leave existing columns alone and let `lifetime_parent_count` and
`rolling_365_parent_count` count different universes permanently. Rejected because that is exactly
the failure the "do not add `last_shoot_at`" rule exists to prevent, made worse by the shared
`parent_count` suffix hiding the disagreement.

**Q2 — Reshoot treatment? → Counts as a shoot and as revenue.**
A reshoot is a paid return visit the agent chose to book. It consumed a photographer trip and it
is evidence of an active account. With Recapture carrying the service-recovery case as its own
type, the thing that muddied the count is gone. `RESHOOT_ORDER_TYPE_ID` leaves the scope entirely;
it remains in use by the reshoot-rate numerator. **Amended 2026-09-08 (slice 1b plan):** it leaves
`AccountPendingShootsService` too — a reshoot booked ahead is pending, so the pending count and the
completed count on the account dialog read the same universe. The constant now names a kind of
child in the reshoot-rate numerators, `Order.reshoots`, and `orders:audit_reshoots`, and nothing
else.

**Q3 — Where does Recapture sit? → New `recovery: 5` category.**
Adding an enum value for one order type that did not yet exist, on the strength of a margin
calculation that is explicitly deferred, is speculative modeling. Accepted anyway because
`category_type` is `null: false` with no default: the classification is made once at creation and
is expensive to revisit across 19 years of backfilled rows. One enum slot now versus a data
migration later.

**Q4 — Shoot date? → `scheduled_at`, falling back to the completed log timestamp.**
The alternative, `MIN(order_logs.created_at)`, is append-only and immutable and always yields a
date for a qualifying row. Rejected because it is the delivery date, and the abandoned-order case
(closed months late) makes it badly wrong exactly where `scheduled_at` is right. The mutability
objection to `scheduled_at` points at correct behaviour.

**Q5 — Cancel At Door? → No predicate change.**
Settled by query rather than by reasoning: 14 orders, 19 years, and they are full shoots rather
than $35 stubs. See §5.6.

**Q6 — Fix shoot-value columns in slice 1? → Yes.**
Deferring them to slice 2 would have shipped a deliberate window where counts exclude headshots
and values do not. The extra work is mechanical: the same predicate substituted into SQL that
already exists. Done in slice 1b (e72d1ac).

**Q7 — Account structure as a fifth axis? → No.**
Proposed on the theory that joint accounts fragment value across rows, diluting the `anchor` tier
and salting the lapsed cohort. The data refuted it (measured 2026-09-01, against 4,279 accounts):

| Segment | Accounts | Shoots |
| :--- | ---: | ---: |
| Sole owner, one active user | 4,164 (97.3%) | 1,697 (85.2%) |
| More than one active user only | 100 (2.3%) | 280 (14.1%) |
| Owner owns another account only | 11 (0.3%) | 4 (0.2%) |
| Both | 4 (0.1%) | 10 (0.5%) |
| Joint by either test | 115 (2.7%) | 294 (14.8%) |

The dominant pattern is multi-user accounts — 100 of 115, carrying 280 of 294 shoots. Those are
agent-plus-assistant and property management companies, and they fragment nothing: the account is
the unit, the shoots are counted once, and a five-user account doing 20 shoots a year is correctly
an `anchor`. Joint accounts hold 35% of anchor accounts and 43.9% of anchor volume, and that
concentration is teams producing more work, measured accurately.

The pattern that genuinely fragments — one owner across two accounts — is 15 accounts and 14
shoots. Not worth a column.

And the case the axis was really aimed at, two agents who each own an account and co-list, is
invisible to both tests by construction. No manual classification would find it either; Don would
have to know account by account and keep knowing as pairings change. A label requiring omniscience
to populate is not a label.

What survives is `active_user_count` (§3.4): derived, free, and the target list for team and
brokerage products.

**Q8 — D1 and D2.** See §7.

**Q9 — Naming and scope shape.** Resolved into §5.1. Four sub-decisions: the visit fact wins over
the payment fact in the date predicate; completed log for the shoot predicate and `paid_at` for
revenue; revenue covers all categories except `internal`; `paid_at` does not survive a refund, so
refunds need no special handling. `most_recent_shoot_at` keeps its name despite now recording
visits rather than shoots — the rename touches consumers for a precision gain a comment delivers.

**Q10 — Slice ordering. → Split slice 1 at the visibility seam.** See §9.

---

## 9. Delivery slices

Independently shippable, in dependency order. Status as of 2026-09-11; the codebase notes carry
the `file:line` evidence.

| # | Slice | Status 2026-09-11 | Unblocks |
| :-- | :--- | :--- | :--- |
| 1a | `order_types.category_type` + exhaustive backfill + the three §5.1 scopes | **Deployed 2026-09-10** with 1b (`docs/runbooks/deploy-account-classification-1a-1b.md`); column, backfill and API 1b88f09, scopes 7aa170b | 1b |
| 1b | Rewrite existing `account_metrics` and `AccountQuery` consumers onto the scopes + shift memo | **Deployed 2026-09-10** (`master` merge 514e5c4 of 7aa170b..afeb1f7); memos `shift-memo-slice-1b-2026-09-10.md` (dev restore) and `shift-memo-slice-1b-2026-09-10-production.md` (the hand-over copy) | everything |
| 2 | New `account_metrics` numeric columns incl. `active_user_count` + nightly recompute | **Deployed 2026-09-11** (`master` merge d98632f of cf0745d..ca49f32, 16 commits); migration `20260911120000` logged 13:24:41 UTC, recompute 2 min 36.89 s over 4,078 accounts, 0 failed, every invariant 0; runbook `deploy-account-classification-2.md` | 3, teams page |
| 3 | `lifecycle_type` / `value_type` / `peak_value_type` + thresholds config | **Deployed 2026-09-14** (`master` merge f811e97 of b6621c2..f8abdd7, 7 commits; pushed 17:26 EDT). Recompute 2 min 37.79 s over 4,136 accounts, 0 failed; all 11 invariants 0; the re-derivation check 0 mismatches over all 4,136 rows; all six spot checks exact; `accounts:joint_ownership` tier labels and segment rows identical to the pre-change code. Migrations `20260912120000` (four columns) and `20260912120001` (one index), `lib/account_classification.rb`, three enums on `AccountMetric`, `lifecycle_run_sql` + `classification` on the calculator, four fields on the metrics endpoint, both rake read-outs reconciled onto the config. Suite 1,688 examples 0 failures; sweep 1 min 03 s over 4,078 accounts 0 failed on the dev restore; all 11 invariants 0; both migrations run migrate/rollback/migrate; `accounts:joint_ownership` byte-identical. Plan `../plans/account-classification-slice-3.md`, runbook `deploy-account-classification-3.md` | teams page, 7 |
| 4 | `accounts.account_type` + ops classification UI + tiered backfill | Column, API, role gates and filter **deployed 2026-09-10** with 1a and 1b; ops UI on insgt-ops `main`, pending its release; backfill and organization type audit not started | 7 |
| 5 | `marketing_events.event_type` + backfill | **Void.** See §3.2 | — |
| 6 | Acquisition reference derivation (§5.5) | **Blocked on D6** | per-event ROI |
| 7 | Pipedrive reconciliation + whitelisted push | Not started | — |

**Slices 1a and 1b deployed together on 2026-09-10.** 1a alone changed nothing anyone sees and 1b
could not run without it. `deploy-account-classification-1a-1b.md` is the record: maintenance
mode closed the window between release and migration (new code reads `category_type` on the
accounts index, the metrics dialog and the CSV export), the memo was produced against a production
snapshot before the first recompute, and it was handed to Don before the numbers changed. Slice
4's column and API went with the same push of `master`. From here every `account_metrics` row
carries the §5.1 definitions; the pre-1b numbers survive only in the two memos.

**Why 1a and 1b split.** 1a adds a column and defines scopes that nothing reads yet — nothing
moves, nothing is visible, and a backfill mistake is cheapest to catch at this point. 1b changes
what people see. Different risk, different review, two reviewable units for the same total work.

**The shift memo exists** (`shift-memo-slice-1b-2026-09-10.md`, reproducible with
`account_classification:shift_memo_1b OUT=… CSV=…`). Headline: 4,027 accounts had a shoot under
the old definition and 2,071 do under §5.1; `lifetime_parent_count` falls for 2,299 accounts and
rises for 123 (top-level reshoots), 18,372 → 15,551 fleet-wide, which is exactly 3,082
non-property parents out and 261 completed reshoots in; trailing-365 parents 2,028 → 1,476 (v3:
2,005 → 1,484 on the older restore); 437 accounts lose every trailing-year shoot (v3: 428);
`median_shoot_value_cents` rises for 237 accounts and becomes NULL for 1,961; revenue drops
$775,538; every reconciliation residual is $0. It computes the old definition from literal SQL
cited to c999b29 and cross-checks it against the stored `account_metrics` rows column by column.
The production copy (`shift-memo-slice-1b-2026-09-10-production.md`, 2026-09-10 snapshot: 4,078
accounts, 4,030 → 2,074 with a shoot, revenue $4,478,971 → $3,701,878) reconciled to the cent and
is what Don received. Re-running the task now that the nightly writes the new definition reports
every stored row as a mismatch on every column; that is the cross-check working, not the memo
breaking, and the two committed memos are the last runs where it could be made.

**The worklist ordering ships with slice 4's remaining work, not with slice 2's column.** Four
reasons: the accounts index emits no `ORDER BY` today — `AccountQuery#search` never sets
`options[:order]` and `search_params` copies no sort key — so the sort is new plumbing with one
precedent, the users directory (`DIRECTORY_SORTS`, `NULLS LAST`, an id tiebreak, 400 on an
unrecognised sort); `ApiSearch#query` selects `accounts.*` and applies `.distinct` unconditionally,
and Postgres rejects `ORDER BY` on a column absent from a `DISTINCT` select, so the sort needs a
`LEFT JOIN account_metrics` (LEFT — the worklist is exactly the accounts with no row yet), the
column in the select, `DESC NULLS LAST, accounts.id` (load-bearing: 87% of the worklist ties at
zero and NULL rows must sort after real zeros), and a check on `Metadata.calculate` and the
`where_only_once` `GROUP BY`; insgt-ops sorts the loaded page client-side and documents "the API
has no sort params", and its worklist control is slice 4's ops work — the sort key and the control
ship together as one reviewable unit; and shipping the key with no caller changes slice 2's risk
class for nothing visible. Sketch for slice 4: `sort=rolling_365_parent_count` and `direction` in
`search_params`, a frozen `ACCOUNT_SORTS` map in `AccountQuery`, `join_on[:account_metrics]`
pushed idempotently like `join_shoots!`, the export inheriting or stripping the sort.

**Slice 4 blocks on the organization type audit** (§4.1). The `property_manager` backfill
heuristic reads data whose hygiene is unverified.

**Slice 7 is two jobs, not one.** Roughly 1,270 accounts exist in `insgt-api` and not in
Pipedrive, so the push is preceded by a reconciliation, and reconciliation can create duplicates
in Don's primary interface. It also needs a decision that this document does not yet make: *which*
accounts are worth syncing. Accounts with no shoots ever, internal and test accounts, and
organization-proxy accounts are all in that gap, and dropping over a thousand unfamiliar records
into the CRM is an operational event regardless of whether the data is right. `account_type` and
`lifecycle_type` are what answer it, which is why slice 7 depends on 3 and 4 rather than on 2
alone.

**Slice 7 no longer depends on 5 or 6.** v2's push whitelist implied four axes; Origin was the
only one that reached Pipedrive through slices 5 and 6. With 5 void and 6 blocked, the whitelist
ships with Type, Lifecycle, and Value, and Origin is added to it when D6 closes and slice 6 lands.

---

## 10. Changes from v1

| Area | v1 | v2 | Why |
| :--- | :--- | :--- | :--- |
| Account population | ~2,800 | 4,279 active | v1 cited the Pipedrive record count. The gap is now scoped into slice 7. |
| `category_type` | 4 values | 5, adding `recovery` | Recapture is a $0 field visit; filing it under `internal` would erase the visit cost. |
| Reshoot | Ambiguous | Counts as shoot and revenue | Recapture now carries the service-recovery case separately. |
| Shoot predicate | `.where.not(status_type: CANCELLED_STATUSES)` | Completed `order_log` | `status_type` does not encode cancellation. Positive predicate over an open set of terminal states. |
| Scopes | One (`qualifying`) | Three (`qualifying`, `qualifying_parents`, `billable`) | Visit, job won, and money are three questions. `parent_pays` is what makes the third distinct. |
| Shoot date | Unstated (inherited `paid_at`) | `scheduled_at`, falling back to completed log | `paid_at` cannot date a row the predicate accepts. |
| D1 | Recommended no | Yes | The date column records visits, not jobs won. |
| Revenue scope | Implicitly property-only | All categories except `internal`, `paid_at` present, `parent_pays IS NOT TRUE` | Headshot and event revenue is real money. `parent_pays` prevents double-counting. |
| Existing consumers | Untouched | Rewritten in slice 1b | v1 would have left `lifetime_parent_count` and `rolling_365_parent_count` counting different universes permanently. |
| Tier column names | `value_tier_type` / `historical_tier_type` | `value_type` / `peak_value_type` | D5 resolved toward readability. |
| Slice 1 | One slice | 1a / 1b | Split at the visibility seam. |
| Slice 7 | Push only | Reconcile, then push | ~1,479 accounts missing from Pipedrive. |
| `active_user_count` | — | Added | Derived, free, and the target list for team and brokerage products. |

### Analysis produced but deliberately not acted on

**The `MARGIN_LTV_*` constants do not decompose cleanly into `category_type` plus one boolean.**
v2 claimed `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` was the non-listing set, i.e.
`category_type != property`. Measured against the shipped backfill (2026-09-07) it is not: the
list contains five `property` types (Stagers Special, Matterport hosting renewal, personalized
web address, free Instagram reel, Reprocess — Disclosure Compliance) and omits seven non-property
types (the two discounts, Top Agent Video, Agent Intro Video, Forefront Escrow Reels, Social Reel,
Recapture). The two answer different questions — kind of work versus margin-bearing listing
revenue — and the twelve differences are where those questions diverge. Deriving the constant from
the category would need a per-type decision for each of the twelve, plus the
`requires_field_visit` boolean for Virtual Staging and Quick Pics:

```ruby
add_column :order_types, :requires_field_visit, :boolean, null: false  # no default
```

If this is picked up later: keep the columns off any ops edit screen, migration-only, so changing
them still requires a reviewed commit. And verify the backfill by asserting the constant equals
the derived set in a spec, then deleting both in the same commit — a red diff names the wrong ids,
which beats a margin number moving unexplained.

`HEADSHOT_ID = 3` is `free_web_portrait`, categorised `marketing`; it is subsumed by
`category_type` and should go at the same time.
`RESHOOT_ORDER_TYPE_ID = 6` is a singleton reference; `order_types.key` now exists and
`rake order_types:verify_pinned_ids` checks the pinned constants against it. ADR 002 records why
the constants stay integers.

Out of scope for this document. Recorded so the analysis is not repeated.

**`OrderQuery#filter_canceled` has a pagination bug.** It post-filters in Ruby and adjusts `total`
by the current page's cancelled count rather than the global count. Unrelated to this work,
noted in passing.

---

## 11. Changes from v2

Sourced from `account-classification-drift-audit-2026-09-07.md`; row numbers there carry the
evidence.

| Area | v2 | v3 | Why |
| :--- | :--- | :--- | :--- |
| §3.2 `marketing_events.event_type` | Five-value enum, slice 5 | Removed; slice 5 void | `marketing_events` is headshot-only; other event work is classified by `category_type`. No commit recorded the decision, so this document does. |
| §3.3 `accounts.marketing_event_id` | Added, immutable, derived | Not added; column undecided (D6) | `acquisition_order_id` proposed as the uniform capture; unresolved. |
| §5.5 Origin | Derivation rule into `marketing_event_id` | Stale pending D6 | No target column. |
| §7 | D1–D5 closed | D6 added, open | Records the acquisition-column question. |
| §9 slices | 5 feeds 6 feeds ROI; 7 depends on 3, 4 | 5 void; 6 blocked on D6; 7 depends on 3, 4 only, Origin joins the whitelist later | Origin was the only axis routed through 5 and 6. |
| §9 status | Pre-implementation | Per-slice state; 1a split in fact; slice 2 pins the worklist ordering | Column and backfill shipped without the scopes. |
| §2.1 gate | `public: false` | `cart` NULL; `public` is documentation | `order_types.public` is dead (ADR 002). |
| §2.1 cutover | Placeholder | Production `created_at` of row 300; deploy on or after 2026-09-02 | Runbook and ADR disagreed; the row is the record. |
| §2.1 recapture predicate | `category_type: recovery` | Pinned id 300 | ADR 002: a nil inside `NOT IN (?)` empties the universe. |
| §3.0 | Sample without options | `prefix: true` on every new enum | Convention set when `account_type` shipped. |
| §3.1 | One-line `null: false` add | Four-migration sequence; nine unnamed `property` rows listed; test-only factory default noted; API and "nothing reads it yet" recorded | strong_migrations; test convention in `insgt-api/CLAUDE.md`. |
| §3.4 | Nine columns | Same nine, plus: recapture columns exist, two of the nine are derived ad hoc in `accounts.rake` | Slice 2 must reconcile, not duplicate. |
| §4.1 constants | Two, disagreeing on 89 | Four, split 2–2 on 89; status of the hand classification | `metrics.rake` and `accounts.rake` carry their own lists. |
| §4.2 | Two prospect populations | Measured: 428 accounts with only non-property work in the trailing year | Sizes the mitigation. |
| §5.1 | Three scopes | Same, plus status: none exists; interim predicates named | The scope half of 1a did not land. |
| §5.1 `parent_pays` | "three places"; NULLs assumed | Every revenue query; no NULLs among active children | Measured. |
| §5.3 | `paid_at` out | Same, plus the `AccountReport` consumer the migration reconciled with, and 3,004 undated shoots | Slice 1b has to move or record that consumer. |
| §5.4 | Revenue rules | Same, plus the size of today's `parent_pays` double-count ($684,555) | Shift memo input. |
| §7 D4 | Three-column table | Recapture column added | All three predicates exclude it. |
| §10 `MARGIN_LTV_*` | Decomposes into category + boolean | Does not, for twelve types | Measured against the backfill. |
| Population | 4,279 active (2026-09-01), 1,991 shoots | 4,067 active (2026-09-08); 2,005 vs 1,484 trailing-365 shoots under the two predicates | Re-measured; the v2 figure was stale (2026-08-31 cleanup, confirmed in production 2026-09-08). |
| Document path | `docs/account-classification-architecture.md` | `docs/architecture/account-classification.md` | Moved; every code and skill reference updated 2026-09-08. |

---

## 12. Changes from v3

Sourced from slice 1b (`feat/account-classification-1b`, 7aa170b..afeb1f7) and its memo
(`shift-memo-slice-1b-2026-09-10.md`).

| Area | v3 | v4 | Why |
| :--- | :--- | :--- | :--- |
| §5.1 scopes | Defined, not implemented | Shipped, plus the `property_work` building block and the `pending_shoots` derivation; consumers compose `to_sql`, never copy conditions | Two consumers needed the base without completion; a fourth question would have been a re-derivation |
| §5.1 table | Nine readers | Every reader named, including `Account#order_count`, the CSV export, `ChurnReport`, `joint_ownership`, the audit linkage and the KPI | The consumers moved; the table records which column each reads |
| §5.1 `where_only_once` | `join_shoots!` reads `qualifying_parents` | Count from `qualifying_parents`; in-flight exclusion from `pending_shoots` | The filter feeds outreach; work in flight disqualifies (decision 2026-09-08) |
| §5.2 completion hygiene | Not measured | 201 parents, 23 under 90 days | Memo |
| §5.3 fragment | Prose | `Order.shoot_date_sql`, a correlated scalar subquery | One string for scopes, plucks and CTEs |
| §5.3 KPI | Move or record | Moved; `annual_report` left and flagged | "Do not diverge" (decision 2026-09-08) |
| §5.3 "3,004 gain a date" | As stated | 162 property parents gain a date; the rest leave the universe | Wrong in kind, found by the memo |
| §5.4 revenue | Rule stated | Shipped; $775,538 drop decomposed; transactions confirm the `parent_pays` rule; the Stripe bridge reconciles | Memo |
| §5.4 shoot value | Implicit | Parent's own price over `qualifying_parents`; the bridge to LTV stated and measured | Gap 2 of the slice |
| §7 D4 | Open consequence | Resolved | Slice 1b |
| §8 Q2 | Reshoot exclusion stays in the pending service | Leaves it; pending includes reshoots | Same universe as the completed count beside it |
| §8 Q6 | Yes | Done | e72d1ac |
| §9 | 1a partially landed, 1b not started | 1a and 1b implemented, deploy together; memo exists | Runbook written |
| §2.1 cutover | Placeholder | 2026-09-02 12:01:26 UTC from the production restore | Runbook step 4 confirms |
| §3.4 | "accounts:composition" | `accounts:joint_ownership`, now on the scope | The derivation was misattributed |
| §4.2 | 428 trailing-year | Plus 1,956 with no property shoot ever | Memo headline |
| §10 | — | `SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS` is margin-only; goes with the `MARGIN_LTV_*` lists | Decision 2026-09-08 |
| §9 status (later on 2026-09-10) | 1a and 1b implemented, deploy together | 1a, 1b and slice 4's column and API deployed to production; ops UI pending its release | Deployed by Dan, 2026-09-10 |

---

## 13. Changes from v4

Sourced from slice 2 (`feat/account-classification-2`, cf0745d..ca49f32), its plan
(`docs/plans/account-classification-slice-2.md`, gaps G1–G14, decisions by Dan 2026-09-10) and the
two review rounds.

| Area | v4 | v5 | Why |
| :--- | :--- | :--- | :--- |
| §3.4 status | Nine columns, not yet implemented | The five numeric columns shipped; four enum-side columns and the two indexes still slice 3 | Slice 2 |
| §3.4 NULL | "All nine are nullable" | What NULL means on the five: not computed since slice 2 shipped; the calculator never writes NULL to a count; `peak_365_ended_on` NULL iff the peak is 0; two count conventions on one table, stated | G2 — the deploy window needs an unrecomputed row to be distinguishable from a real zero |
| §3.4 `active_user_count` | "a plain `COUNT(*)` over active `accounts_users`" | `Account#users_count` — distinct active users with an active membership, the count `user_count` already ships | G1, accepted 2026-09-10: the plain count counts roles; 411 accounts differ, 453 vs 102 multi-user, account 10288 reads 9 for 6 people |
| §3.4 derivations | Two ad hoc derivations to reconcile | Both removed; `joint_ownership` joins `account_metrics` and sets unrecomputed accounts aside as unweighed; the memo reads `compute` | G8, accepted 2026-09-10: nightly-fresh is acceptable for a weighing tool |
| §3.4 `peak_365_ended_on` | `date`, no more said | A UTC date; why it does not localise where `first_shoot_at` does | G13 |
| §3.4 mirror and index | Silent | No `system_metrics` mirror, no index; the "column-for-column parallel" claim narrowed to the shared columns | G6, G7 |
| §3.4 wire | Silent | Four of the five on `GET /accounts/:id/metrics`; revenue owner-only; `active_user_count` deliberately not emitted | G10 |
| §5.1 table | Three "(slice 2)" labels | Labels dropped | Shipped |
| §5.4 counts | "Evaluate the window forward … Record the window's end date" | Backward closed window, the maximum of the rolling series; end date is the last shoot of the peak run, latest on a tie; `rolling <= peak` invariant | G4, accepted 2026-09-10: same maximum, a real end date in the past |
| §5.4 revenue | Refunds self-correct | Plus the mirror: a paid-then-cancelled order is revenue and not a shoot; `rolling_365_value_cents` is the trailing slice of lifetime by each row's own date; `rolling <= lifetime` | G5 |
| §4.3 "never decays" | "Monotonic; never decays" | Monotonic against time; recomputed from history, follows history edits; no ratchet | G14 |
| §4.1 / §9 worklist ordering | "waits on slice 2's column" | Ships with slice 4's remaining work; four reasons and the sketch recorded | G9, accepted 2026-09-10 |
| §6 steps 1–2 | Planned | Done; runtime recorded | Slice 2 |
| §9 status | Slice 2 not started | Implemented and reviewed, not deployed; runbook written | Slice 2 |
| §9 status (later, 2026-09-11) | Slice 2 implemented and reviewed, not deployed | Deployed to production 2026-09-11; §6 carries a production sweep duration for slice 3 to extend | Deployed by Dan, 2026-09-11 |

---

## 14. Changes from v5

Sourced from slice 3 (`feat/account-classification-slice-3`, 7 commits b6621c2..f8abdd7, merged as
f811e97), its plan (`docs/plans/account-classification-slice-3.md`, gaps G1–G15) and the
implementation session of 2026-09-14, which measured everything below against a 2026-09-10
production restore.

| Area | v5 | v6 | Why |
| :--- | :--- | :--- | :--- |
| §3.4 heading | "add nine columns", all nine in one block | Split into the slice 2 block and the slice 3 block, with the two migration filenames and why the columns and the index are separate files | The single block read as one unshipped unit when five of the nine had already shipped |
| §3.4 index | Two indexes, `add_index` with no `algorithm:` | **One** index, `[lifecycle_type, value_type]`, concurrent in both directions with a leading `remove_index`; `[account_id, lifecycle_type]` dropped with the reason | G6 — the existing UNIQUE index on `account_id` means at most one row per account, so the composite cannot improve any lookup. G15 — the v5 snippet raises under `strong_migrations` and never ran |
| §3.4 `lifecycle_type_at` | "records when the current label first held" | The full derivation table, the run-start rule for `active`, and the three reasons a stored-row comparison was rejected | G1 — the literal reading stamps all 4,078 rows with the deploy date, including 1,557 `lapsed` accounts whose measured median hold is 1,655 days |
| §3.4 NULL | One convention, stated for the five numeric columns | Two conventions across the four new columns, stated explicitly: NULL is a *value* on the tier columns and an *unswept row* on `lifecycle_type` | G4 — both counts are coerced to a real 0 upstream, so a band lookup without a zero case files 3,563 accounts under `single` |
| §4.2 arithmetic | A table in whole days, rounding unstated | Floored whole days for the three degrading boundaries, continuous for `new`, written out; boundary days belong to the warmer label | G2 — the rule slice 1b already shipped. Differs from a continuous interval for 2 of 4,078 accounts and for 0 on the `new` boundary |
| §4.2 precedence | "`new` and `active` overlap by construction" | Proved a pure override: `most_recent_shoot_at >= first_shoot_at` always, and 0 accounts are `new` without also qualifying as `active` | Measured; two correct implementations cannot now differ on a tie |
| §4.2 / §4.3 figures | None | Full distributions for all three columns, the reactivation cohort, degrading-label hold times, band-edge population, and a warning about which figures drift with the clock | The implementation reproduced every v6 figure exactly when replayed at the survey instant |
| §4.3 zero rule | "NULL, not `single`" and a note that the read-out must not diverge | The `rate` precedent named, the coercion trap stated, and the divergence actually closed — `SHOOT_VOLUME_TIERS` now reads `VALUE_BANDS` | G3; the read-out's own comment had asked for this in writing |
| §6 step 3 | "Update `lifecycle_type_at` only when the value actually changes" | Marked done, and re-worded: the stamp is derived from history, which preserves the property that step was asking for without the mechanism | G1 |
| §6 config object | "one Ruby config object", unlocated | `AccountClassification` in `lib/account_classification.rb`, why `lib/` is forced rather than chosen, and the three artifacts that read it | G3 — `config.autoload_lib` ignores `lib/tasks`, so `app/services` cannot read a `.rake` file and the dependency only runs one way |
| §6 config object | Silent on load order | A rake file must read the config in a memoised method, never in a constant: `rakefile` calls `load_tasks` without initializing the app, so a load-time reference aborts every `rake` invocation including `db:migrate` | Found during implementation; the rake specs cannot catch it because they load task files inside an initialized app |
| §9 slice 3 | Not started | Deployed to production 2026-09-14, with the evidence; §6 carries a production sweep duration for slice 4 to extend | Slice 3 |

### Review findings that changed the code

Two rounds: a six-lens adversarial pass with three independent refuters per finding, and an
independent Codex review over the same working tree. Three findings survived and were fixed; the
rest were refuted or are already-intentional.

| Finding | Disposition |
| :--- | :--- |
| The run gap read `> 90 days` instead of `>= 91 days` | **Fixed.** The two agree on every whole number of days and disagree on every fraction between them. A gap of 90 days and 12 hours floors to 90, so the account never left `active` and the run must not break. No spec distinguished them; one now does |
| `lifecycle_started_at` returned `most_recent_shoot_at` for `new` instead of `first_shoot_at` | **Fixed.** The spec that was meant to guard it passed the SAME value as both arguments, so it could not tell them apart. Both the unit spec and a calculator example now use two different dates |
| The `new` boundary had no example distinguishing a continuous comparison from a floored one | **Fixed.** An example at one second past 90 days now pins it; it goes red under a floored `new` rule and nothing else did |
| The cancelled-order example did not actually guard the universe (round 2) | **Fixed.** Its three dates left a 92-day gap between the cancelled order and the next visit, so the run broke at the same place whether or not the cancelled order was admitted. Moved to dates where admitting it changes the answer; it now goes red if the run query widens past `Order.qualifying` |
| `visits_sql`'s comment still said "Feeds the date range only" (round 2) | **Fixed.** It has two consumers now. The correction was in the plan, missed on the first pass, and the codebase notes had already claimed it was done |
| Ties in `lifecycle_run_sql` are nondeterministic, possibly NULL (Codex) | **Refuted, then pinned anyway.** Measured 1,000 runs over five tie shapes: one distinct answer each, never NULL. It is structural, because a later peer's `LAG` is an earlier peer at the same instant, so its gap is zero and every peer's frame already contains the earlier ones. A regression example now says so |
| `lifecycle_run` runs for all 4,078 accounts although only ~152 are `active` (Codex) | **Already-intentional** (G5), and a one-line reversal if the cost is ever unwelcome. Branching on the label makes the sweep's cost depend on the data and leaves the query unexercised for five of the six labels. Measured cost: about 1.4 ms per account, roughly 6 s across the fleet against a 2 min 37 s baseline |
| Several independently sampled clocks in one snapshot could break `lapsed ⇒ value_type IS NULL` (Codex) | **Refuted.** The invariant is structural, not clock-dependent: `most_recent_shoot_at` ranges over visits and every parent is a visit, so an account whose latest visit is 366 days old has no parent inside 365 days. Closing the gap would take a full day of drift between two cutoffs sampled milliseconds apart. Per-method cutoffs are the convention slice 2 pinned as G3 |

**A process note worth keeping.** The adversarial reviewers were given permission to edit source in
order to confirm a spec goes red. Two of them left the tree modified, and a third left probe files
behind, while an independent reviewer was reading the same uncommitted working tree. Every edit was
found and reverted, and the suite, the sweep, the invariants, the spot checks and the read-out
comparison were all re-run against the final state. Reviewers that mutate a shared working tree
should be given a copy of it, not the tree itself.

**One correction to the slice 3 plan.** The plan's spot-check table computed the three degrading
stamps as `most_recent_shoot_at + 90 / 180 / 365 days`, where its own G1 rule table says
`+ 91 / 181 / 366`. The rule table is right and the spot-check table was arithmetically wrong.
Decisive evidence: re-evaluating §4.2 at each stored stamp reproduces the stored label for all
1,863 degrading rows under `+91 / +181 / +366`, and for **none** of them under `+90 / +180 / +365`,
because at those earlier instants the account is still in the warmer band. The runbook's spot-check
table carries the corrected values.
