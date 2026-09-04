# Account Classification Architecture

**Repo:** `insgt-api` · **Consumers:** `insgt-ops` teams page, Pipedrive nightly push
**Status:** Design agreed, pre-implementation
**Version:** 2 · **Last updated:** 2026-09-01
**Supersedes:** v1 (2026-08-27). See §10 for what changed and why.

---

## 1. Purpose

Classify all active accounts along four independent axes so that segments can be filtered in
`insgt-ops` and pushed to Pipedrive as computed labels, without any human maintaining a list.

| Axis | Question it answers | Home | Mutable |
| :--- | :--- | :--- | :--- |
| **Type** | What kind of business is this? | `accounts.account_type` | Manual, rarely |
| **Lifecycle** | How recently did they buy? | `account_metrics.lifecycle_type` | Nightly |
| **Value** | How much do they buy? | `account_metrics.value_type` / `peak_value_type` | Nightly |
| **Origin** | Where did they come from? | `accounts.marketing_source_id` (self-reported) + `accounts.marketing_event_id` (derived) | Set once |

These are orthogonal by design. Every earlier attempt to express recency and frequency in a
single flat enum produced overlapping and non-exhaustive categories.

### Population

**4,279 active accounts** (dev DB, measured 2026-09-01), carrying 1,991 qualifying shoots in the
trailing window.

v1 of this document said ~2,800. That figure was the Pipedrive record count, not the account
count. The gap of roughly 1,479 accounts is a real reconciliation problem and is now scoped into
slice 7 (§9) rather than assumed away.

### Non-goals

- No `acquisition_channel` enum merging self-reported source with derived event origin. Two
  facts, two columns.
- No `Dormant` lifecycle value. `>3 years` does not change the action taken; sort within
  `lapsed` by `most_recent_shoot_at` instead.
- No `account_type` on the customer-facing order form.
- No bidirectional Pipedrive sync. Push only.
- **No account structure axis.** See §8, decision Q7 — the data did not support it.
- **No changes to `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` or
  `MARGIN_LTV_FIELD_VISIT_EXCLUDED_ORDER_TYPE_IDS`.** Those constants decompose cleanly into
  `category_type` plus a `requires_field_visit` boolean, but margin is out of scope for this
  document and the constants stay untouched. Recorded in §10 so the analysis isn't lost.

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
wrong. New order type. See §2.1.

**Qualifying shoot** — a parent order of `category_type: property`, `status_type: active`, with a
completed `order_log`. See §5.1 for the full scope definitions.

### 2.1 The Reshoot / Recapture split

Service-recovery visits have historically been booked as $0 Reshoots. That conflates a quality
event with a revenue event: the same order type carries "the seller repainted and wants new
photos" and "we blew the exposure and have to go back."

Going forward, service-recovery visits are a separate order type, **Recapture**, at $0.

**Historical data is not reclassified.** There is no reliable way to distinguish a
comped-because-we-erred reshoot from a comped-because-good-customer reshoot in existing rows. The
distinction starts at the cutover date and is bounded, not backfilled.

**Cutover date:** _[record the date the Recapture order type row was created]_

Recapture is created with `public: false` so it cannot be selected from the customer-facing order
form.

**Known metric discontinuity.** From cutover, `lifetime_reshoot_rate` measures something
different than it did before. Reshoot becomes a pure revenue signal; Recapture becomes the
quality signal. Any photographer KPI built on reshoot rate should read `category_type: recovery`
for periods after cutover and should not compare across the boundary. Expect a step change in the
series.

---

## 3. Schema changes

### 3.0 Enum column convention

All new enum columns follow the existing `*_type` smallint convention (`status_type` et al.):
integer-backed, declared as a Rails enum, **values start at 1**. Starting at 1 keeps NULL as the
only "unset" state and avoids 0/nil ambiguity in queries and form params.

```ruby
class OrderType < ApplicationRecord
  enum :category_type, { property: 1, headshot: 2, event: 3, internal: 4, recovery: 5 }
end
```

**Exception, deliberately taken:** the tier columns are `value_type` and `peak_value_type`, not
`value_tier_type` / `historical_tier_type`. v1 chose the longer names for suffix consistency;
they read redundantly, and "tier" survives in conversation and in this document regardless of
what the column is called. `lifecycle_type` keeps its name unchanged.

### 3.1 `order_types` — add `category_type`

```ruby
add_column :order_types, :category_type, :integer, limit: 2, null: false   # no default
```

| Value | Int | Covers |
| :--- | :-- | :--- |
| `property` | 1 | Residential listing, commercial, property management, **Reshoot**, Quick Pics, standalone floor plan, and all child order types (aerial, Matterport, Zillow 3D, twilight, floor plan) |
| `headshot` | 2 | WebPortrait, WebPortrait Event, Headshot Event, Free Web Portrait |
| `event` | 3 | Event Photos, Event Video, Paparazzi, Scheduler Event |
| `internal` | 4 | Test Package, Adjustment, Reprocess — Disclosure Compliance |
| `recovery` | 5 | **Recapture** |

`null: false` with no default is deliberate: adding a new order type forces the classification
decision at creation rather than defaulting silently. When Insight Reels becomes an order type,
someone must decide.

**Why `recovery` is its own category rather than `internal`.** A Recapture is real property work
at a real property requiring a real photographer trip. It earns $0 and is not a job won, so it is
excluded from counts and revenue. But it is not Test Package. Filing it under `internal` would
encode "doesn't count as revenue" while erasing "does cost a $115 field visit," in the one bucket
nobody would think to look in when margin work resumes. A separate value costs one enum slot and
keeps the physical fact queryable:

- Shoot count and revenue: `category_type = property`. Recapture out.
- Field visits, when margin is picked back up: `category_type IN (property, recovery)`.
- Photographer quality KPI: `category_type = recovery` is the metric directly, with no
  price-based heuristic.

**Note:** because child orders carry their own `order_type`, category alone does not identify a
shoot. See §5.1.

**Backfill is exhaustive on day one.** `null: false` with no default means every existing row in
`order_types` must be assigned before the migration lands. Enumerate the full table and assign a
category before writing the migration — that enumeration is also the check on whether five values
are sufficient.

### 3.2 `marketing_events` — add `event_type`

```ruby
add_column :marketing_events, :event_type, :integer, limit: 2, null: false
```

`headshot: 1` · `paparazzi: 2` · `caravan: 3` · `sponsorship: 4` · `other: 5`

Table already exists with an `organizations` association (PSAR, SDAR, NAHREP, NARPM, NSDCR) and
already groups headshot orders. This column separates event kinds for per-event ROI reporting.

### 3.3 `accounts` — add two columns

```ruby
add_column    :accounts, :account_type, :integer, limit: 2   # nullable, no default
add_reference :accounts, :marketing_event, foreign_key: true, null: true, index: true
```

`account_type` — see §4.1. Nullable and undefaulted on purpose: NULL means "nobody has looked at
this account," which is the distinction the classification worklist depends on. Defaulting to
`agent` would erase it across all 4,279 rows.

`marketing_event_id` — the event that **acquired** the account, set only when an event order is
the account's earliest order (§5.5). Immutable once set.

> **Naming caveat.** An account may have orders at several events over time. This column means
> *acquired at*, not *attended*. Attendance is queried through `orders.marketing_event_id`. If
> that ambiguity bites later, `acquisition_event_id` was the alternative name considered.

`marketing_source_id` stays exactly as it is. Self-reported channel at signup and derived event
origin are different facts and both are worth keeping. Do not add organization rows to
`marketing_sources` to represent headshot events.

### 3.4 `account_metrics` — add nine columns

```ruby
add_column :account_metrics, :rolling_365_parent_count, :integer
add_column :account_metrics, :rolling_365_value_cents,  :bigint
add_column :account_metrics, :peak_365_parent_count,    :integer
add_column :account_metrics, :peak_365_ended_on,        :date
add_column :account_metrics, :lifecycle_type,           :integer, limit: 2
add_column :account_metrics, :lifecycle_type_at,        :datetime
add_column :account_metrics, :value_type,               :integer, limit: 2
add_column :account_metrics, :peak_value_type,          :integer, limit: 2
add_column :account_metrics, :active_user_count,        :integer

add_index :account_metrics, [:lifecycle_type, :value_type]
add_index :account_metrics, [:account_id, :lifecycle_type]
```

Naming follows the existing `rolling_90_*` / `lifetime_*` convention and reuses `parent_count`
as the term for a qualifying shoot.

**`most_recent_shoot_at` already exists — do not add `last_shoot_at`.** A second column for the
same fact is how a Pipedrive label ends up disagreeing with a teams-page filter.

`lifecycle_type_at` records when the current label first held. It is what the Pipedrive push
debounces against, and it answers "how long have they been At Risk."

`active_user_count` is a plain `COUNT(*)` over active `accounts_users`. No judgment, no manual
classification. It exists so the teams page can find the ~100 multi-human accounts that a team or
brokerage product would be sold into. It is a derived fact, not a classification axis — see §8,
Q7.

---

## 4. Enums

### 4.1 `accounts.account_type`

`agent: 1` · `property_manager: 2` · `homeowner: 3` · `builder: 4` · `commercial: 5` ·
`affiliate: 6` · `internal: 7` · `other: 8`

- `homeowner` — FSBO
- `affiliate` — escrow, title, lender (industry term; not "partner")
- `internal` — test and staff accounts. Given 19 years of accumulated data, one predicate that
  excludes junk from every segment justifies the slot by itself.

Manual entry only. Backfill by confidence tier: brokerage present + property orders → `agent`;
organization linked to a NARPM-affiliated org → `property_manager`; known test patterns →
`internal`. Everything else stays NULL. Worklist is `account_type IS NULL` ordered by
`rolling_365_parent_count DESC`.

**Two existing constants are the seed for the `internal` backfill, and they disagree with each
other.** `EXCLUDED_ACCOUNT_IDS = [2, 2555]` and `IGNORE_ACCOUNT_IDS = [2, 89, 2555]`. Account 89
is ignored in one place and counted in another. Determine which is correct before seeding, because
whichever list is used becomes the answer. Once `account_type: internal` is populated, both
constants should be retired in favour of the column.

**The `property_manager` backfill heuristic reads unaudited data.** It depends on
`accounts_organizations` (untyped) and `organizations.type_of`, where `set_type!` silently
defaults blank to `brokerage`, five of the eight enum values have no code path, and there is no
`property_management` type at all. An organization type audit is a prerequisite of slice 4, not a
separate concern. It belongs to the accounts-versus-users workstream (§8, Q7) and slice 4 blocks
on it.

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

**Lifecycle cannot flap.** Days-since-last-shoot increases monotonically between shoots and
resets on a new one. It degrades, then jumps back on a real event. No hysteresis needed.

**`prospect` holds two different populations.** Because `qualifying` is property-only, any account
that transacts exclusively on headshots or events has `most_recent_shoot_at IS NULL` and reads
`prospect`, even with real revenue. Two cases:

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
`peak_value_type` reads `peak_365_parent_count`. Monotonic; never decays.

**NULL, not `single`, when the count is zero.** A zero count is a real zero; the tier is
undefined. Consistent with the propagate-null convention.

`value_type` *can* flap as shoots roll off the back of the window. Store the true value nightly
and debounce at the Pipedrive push boundary (§6), not in the database. Ops sees truth.

**Reactivation cohort:** `lifecycle_type = lapsed AND peak_value_type = anchor`, ordered by
`peak_365_ended_on DESC`.

---

## 5. Derivation rules

### 5.1 Scopes

Three scopes, one base. The split is **visit versus money**, not parent versus child.

```ruby
# Did we go there? Parents and children. No payment condition.
scope :qualifying, -> {
  joins(:order_type)
    .where(order_types: { category_type: OrderType.category_types[:property] })
    .where(status_type: StatusType.active)
    .where(<completed order_log exists>)
}

# Is it a shoot? The above, parents only.
scope :qualifying_parents, -> { qualifying.where(parent_id: nil) }

# Did they pay us? All categories except internal.
scope :billable, -> {
  joins(:order_type)
    .where.not(order_types: { category_type: OrderType.category_types[:internal] })
    .where(status_type: StatusType.active)
    .where.not(paid_at: nil)
    .where('orders.parent_pays IS NOT TRUE')
}
```

**`qualifying_parents` is defined as `qualifying` plus one condition**, never assembled
independently. Everything downstream reads one of these three; nothing re-derives them.

**`billable` is deliberately not named `qualifying_*`.** The two answer different questions and
must not look interchangeable at call sites. A revenue query written against `qualifying` out of
habit returns a silently low number with no error.

Which scope drives what:

| Reads `qualifying` | Reads `qualifying_parents` | Reads `billable` |
| :--- | :--- | :--- |
| `first_shoot_at` | `rolling_365_parent_count` | `rolling_365_value_cents` |
| `most_recent_shoot_at` | `peak_365_parent_count` | LTV columns |
| | `lifetime_parent_count` | |
| | `rolling_90_parent_count` | |
| | `lifetime_reshoot_rate` denominator | |
| | `median_shoot_value_cents` | |
| | `average_shoot_value_cents` | |
| | rolling-90 value pair | |
| | `AccountQuery#join_shoots!` | |

### 5.2 Why completed log, not status

**`status_type` does not encode cancellation.** It has exactly two values, `active: 1` and
`deleted: 2`, both soft-delete. Cancellation lives in `orders.order_event_id` against the
`OrderEvent` whose tag is `canceled` — one L, and every existing consumer looks it up by that
string.

Rather than a negative predicate over an open set of terminal states, the scope uses a positive
predicate: **a shoot is a parent with a completed `order_log`.** This is what
`AccountMetrics::Calculator` already does, and it disposes of three questions without a ruling:

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
count runs behind reality. Worth measuring during slice 1b.

### 5.3 Shoot date

**`COALESCE(orders.scheduled_at, MIN(order_logs.created_at))`** where the log is the completed
event.

`paid_at` is out. It cannot produce a date for a row the predicate accepts: a completed but unpaid
shoot has `paid_at IS NULL`, and pay-after-delivery guarantees a window where that is true for
every order. `paid_at` was never a date semantic; it was standing in for the headshot exclusion
(the `where_only_once` comment says as much), and `category_type` now does that job properly.

`scheduled_at` is the day the photographer was at the property. It is what Don means by "their
last shoot," it matches the field `AccountPendingShootsService` uses on the forward side, and it
stays correct when an order sits unclosed for months.

`scheduled_at` is mutable, so a reschedule rewrites history and `first_shoot_at` can move
backward. This is correct behaviour: the visit genuinely happened on the new date.

**Direction of the shift:** both candidates are earlier than `paid_at`, so `most_recent_shoot_at`
moves back in time. Days for most accounts, weeks for slow payers. Accounts sitting near a 90 or
180 day boundary will tip one bucket further along on the day this ships. This belongs in the
shift memo (§9, slice 1b).

### 5.4 Counts, dates and revenue

**Counts** — `qualifying_parents`. Parents only. A child order never increments a shoot count,
and neither does an order service.

- `rolling_365_parent_count` — qualifying parent shoots in the trailing 365 days.
- `peak_365_parent_count` — maximum count over any 365-day window in the account's full history.
  Evaluate the window forward from each qualifying shoot date; at ~4,300 accounts the cost is
  negligible. Record the window's end date in `peak_365_ended_on`.

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

`parent_pays IS NOT TRUE` is load-bearing and is the existing convention in three places in the
codebase. A child order with `parent_pays = true` may carry an `order_type_price` of $145, but
that $145 was collected on the parent and is already in the parent's total. Counting it again
double-counts. A self-paying child (`parent_pays = false`, the default) counts its own revenue.

Write `IS NOT TRUE`, not `= false`. Every existing consumer does, which suggests NULLs exist in
older rows.

Revenue covers **all categories except `internal`**. A $125 WebPortrait is real money and belongs
in LTV; a $5 Test Package does not. Recapture excludes itself naturally — $0 means no `paid_at`.

`parent_pays` affects attribution, not timing. A child order's revenue is placed in the trailing
window by **the child's own `scheduled_at`**, resolved the same way as §5.3. Child orders have
independent timing by design.

**Refunds self-correct.** `paid_at` does not survive a refund, so a refunded order drops out of
`billable` on the next nightly run with no special handling. It keeps its completed log, so it
still counts as a shoot and still sets recency, at zero revenue. That is correct — we went, we
delivered, the money came back — but it means `rolling_365_parent_count` and
`rolling_365_value_cents` can disagree in a way that looks like a bug and is not.

### 5.5 Origin

Set `accounts.marketing_event_id` when the account's **earliest** order has a `category_type` of
`headshot` or `event` and carries a `marketing_event_id`. Copy that event reference up to the
account.

Only when it is the earliest order. An account that has been buying for three years and then
attends a PSAR headshot event was not acquired by that event.

Set once, never recomputed. Origin is immutable — this is precisely why it lives on `accounts`
and not in `account_metrics`.

### 5.6 Cancel At Door

**No predicate change.** Documented here because §5.1 invites the question and the schema does not
answer it.

Cancel At Door is a $35 `order_service` line item, not an order type and not a status. The usual
workflow is that the photographer is turned away, the fee is added to the order, the shoot happens
later on the same order, and the agent pays the shoot fee plus the $35.

Measured 2026-09-01: **14 orders in 19 years**, totalling $3,335, with order totals of $215, $230,
$385, $250 and similar. These are full delivered shoots carrying an extra line item, not $35
no-media orders. They qualify, they should qualify, and their shoot values are correct.

One of the 14 is unpaid at $230, presumably a case where the shoot never happened. Under the
completed-log predicate it is excluded automatically if nobody closed it, which is the right
outcome arrived at by accident rather than by design.

The $115 field-visit cost of a turned-away trip is invisible in all 14 cases. That is a margin
question and margin is parked.

---

## 6. Nightly job

Extend the existing `account_metrics` recompute rather than adding a second job.

1. Recompute numeric columns from `Order.qualifying`, `Order.qualifying_parents` and
   `Order.billable`.
2. Recompute `active_user_count` from active `accounts_users`.
3. Derive `lifecycle_type`, `value_type`, `peak_value_type` from a single thresholds config
   object. Update `lifecycle_type_at` only when the value actually changes.
4. Push changed computed fields to Pipedrive.

**Thresholds live in one Ruby config object**, not scattered across the job. Retuning a boundary
should not require a migration; the nightly run backfills.

**Store inputs beside labels.** `lifecycle_type = lapsed` sitting next to `most_recent_shoot_at`
and `rolling_365_parent_count` means the label is always explainable without re-running anything.
Same principle as storing numerators alongside rates.

### Pipedrive push boundary

- One-way. Computed fields only.
- The job writes to an **explicit whitelist of field IDs**. A push that syncs "everything on the
  account" will eventually overwrite a Judgment label set by hand, and that is the failure that
  makes the sync untrustworthy.
- Debounce `value_type` changes: require the new value to hold before writing, so boundary
  oscillation does not fill the activity feed.
- **Reconciliation precedes push.** See §9, slice 7.

---

## 7. Resolved decisions

All five v1 open decisions are closed. Recorded with reasoning because the answers are not
obvious from the schema.

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

The count and value columns do not exclude them at all. `reshoot_counts_sql` has no `paid_at`
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

Three predicates were in production and no two agreed:

| Site | Reshoots | Headshots | Requires delivery |
| :--- | :--- | :--- | :--- |
| `Order.shoots` | in | out | no |
| `AccountQuery#join_shoots!` | in | out | no |
| `AccountMetrics::Calculator` | **out** | **in** | **yes** |

Slice 1b brings all of them onto the §5.1 scopes. Numbers move; see the shift memo.

**D5 — Confirm the coined column names. → Switch to `lifecycle_type`, `value_type`,
`peak_value_type`.** See §3.0.

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
it remains in use by the reshoot-rate numerator and `AccountPendingShootsService`.

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
already exists.

**Q7 — Account structure as a fifth axis? → No.**
Proposed on the theory that joint accounts fragment value across rows, diluting the `anchor` tier
and salting the lapsed cohort. The data refuted it:

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

Independently shippable, in dependency order.

| # | Slice | Unblocks |
| :-- | :--- | :--- |
| 1a | `order_types.category_type` + exhaustive backfill + the three §5.1 scopes | 1b |
| 1b | Rewrite existing `account_metrics` and `AccountQuery` consumers onto the scopes + shift memo | everything |
| 2 | New `account_metrics` numeric columns incl. `active_user_count` + nightly recompute | 3, teams page |
| 3 | `lifecycle_type` / `value_type` / `peak_value_type` + thresholds config | teams page, 7 |
| 4 | `accounts.account_type` + ops classification UI + tiered backfill | 7 |
| 5 | `marketing_events.event_type` + backfill | 6 |
| 6 | `accounts.marketing_event_id` derivation | per-event ROI |
| 7 | Pipedrive reconciliation + whitelisted push | — |

**Why 1a and 1b split.** 1a adds a column and defines scopes that nothing reads yet — nothing
moves, nothing is visible, and a backfill mistake is cheapest to catch at this point. 1b changes
what people see. Different risk, different review, two reviewable units for the same total work.

**Slice 1b produces a shift memo before it ships.** Compute old and new side by side across all
4,279 accounts, diff, and hand Don the list of accounts whose numbers move and by how much, with
the direction stated: shoot counts fall for accounts with headshot or event history, median and
average shoot values rise as $0 parents leave, reshoot rate denominators change, and
`most_recent_shoot_at` moves earlier. That converts "numbers changed and nobody knows why" into a
one-page memo.

**Slice 4 blocks on the organization type audit** (§4.1). The `property_manager` backfill
heuristic reads data whose hygiene is unverified.

**Slice 7 is two jobs, not one.** Roughly 1,479 accounts exist in `insgt-api` and not in
Pipedrive, so the push is preceded by a reconciliation, and reconciliation can create duplicates
in Don's primary interface. It also needs a decision that this document does not yet make: *which*
accounts are worth syncing. Accounts with no shoots ever, internal and test accounts, and
organization-proxy accounts are all in that gap, and dropping 1,479 unfamiliar records into the
CRM is an operational event regardless of whether the data is right. `account_type` and
`lifecycle_type` are what answer it, which is why slice 7 depends on 3 and 4 rather than on 2
alone.

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

**The `MARGIN_LTV_*` constants decompose into two facts.**
`MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` is the non-listing set, which is
`category_type != property`. `MARGIN_LTV_FIELD_VISIT_EXCLUDED_ORDER_TYPE_IDS` adds Virtual Staging
and Quick Pics, which are property work performed without a photographer trip. So the two lists
are `category_type` plus one boolean:

```ruby
add_column :order_types, :requires_field_visit, :boolean, null: false  # no default
```

Both constants then disappear. If this is picked up later: keep the columns off any ops edit
screen, migration-only, so changing them still requires a reviewed commit. And verify the backfill
by asserting the constant equals the derived set in a spec, then deleting both in the same commit
— a red diff names the wrong ids, which beats a margin number moving unexplained.

`HEADSHOT_ID = 3` is subsumed by `category_type: headshot` and should go at the same time.
`RESHOOT_ORDER_TYPE_ID = 6` is a singleton reference and wants an `order_types.tag` column
instead, which generalizes to future "this specific type" lookups and survives seed divergence
between environments.

Out of scope for this document. Recorded so the analysis is not repeated.

**`OrderQuery#filter_canceled` has a pagination bug.** It post-filters in Ruby and adjusts `total`
by the current page's cancelled count rather than the global count. Unrelated to this work,
noted in passing.