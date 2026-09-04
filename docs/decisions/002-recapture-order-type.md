# Decision: Recapture Order Type

**Status**: Accepted
**Date**: 2026-09-01

## Context

"Reshoot" is entrenched customer-facing vocabulary. Agents and Don use it to mean an
agent-initiated, **billable** return visit because the property changed — a room was painted, new
staging arrived, the exterior needs a different season. That meaning is correct and is not
changing.

Service-recovery visits — where we go back because *we* got something wrong — have historically
been booked as $0 Reshoots. That conflates a quality event with a revenue event, and it makes the
reshoot rate unusable as either signal: it is neither "how often do customers pay us to come
back" nor "how often do we get it wrong."

The audit as of 2026-09-01, across all history:

| | Count | Share |
| :--- | ---: | ---: |
| Total reshoot orders | 464 | |
| $0 | 145 | 31.2% |
| Charged | 318 | 68.5% |
| Negative total | 1 | |

Of the 318 charged: 299 collected, 7 billed through the parent (`parent_pays`), 12 uncollected.
Charged reshoot revenue $46,717; collected $44,370.

## Problem

The 145 $0 reshoots are a mix of two unrelated things — visits comped because we erred, and
visits comped for goodwill toward a good customer. **Nothing in the schema distinguishes them.**
There is no flag, no note field, no reliable pattern in the data. The information was never
recorded because there was never a place to record it.

So the quality signal we actually want — "what fraction of shoots did we have to go back and
fix" — cannot be recovered from history at any price.

## Options Considered

**Backfill the existing $0 reshoots.** Rejected: it would require a human to re-adjudicate 145
orders from memory, most of them years old, with no source of truth to check against. The result
would look authoritative and be guesswork.

**A boolean flag on the Reshoot order type** (`service_recovery: true`). Rejected: it leaves the
two kinds of visit sharing one order type, so every existing consumer of "reshoot" keeps mixing
them, and every new consumer has to remember the flag. The distinction is a different kind of
job, not an attribute of one job.

**Add `order_types.category_type` first**, then classify Recapture under it. Deferred, not
rejected — see `account-classification-architecture.md` slice 1. It requires a category vocabulary
covering every non-shoot row (delivery options, editing add-ons, fees, discounts, internal/test
packages) plus a per-row backfill decision for all 48 existing types, and it touches every
consumer of the shoot predicates. That is a strategic call with a large blast radius, and
Recapture does not need to wait behind it.

**A new order type, bounded forward.** Chosen.

## Decision

**Introduce a `Recapture` order type at $0, ops-created only, effective 2026-09-01.**

- **No backfill.** Not one existing Reshoot is reclassified. The distinction starts at the cutover
  and is bounded forward only.
- **Reshoot is unchanged** — same name, same price, same behavior, same meaning.
- A recapture attaches to the shoot it corrects via `parent_id`, mirroring how reshoots already
  hang off their parent. This is what lets the recapture rate mean "of the shoots we did, how many
  did we have to go back and fix," and it makes the corrected photos roll up to the original
  listing.
- The order-type id is **pinned at 300** by `db/migrate/20260901120000`, not sequence-assigned.
  `order_types.key = 'recapture'` is the identity; `rake order_types:verify_pinned_ids` checks the
  constant against it.

### Why the id is pinned rather than resolved by key

Twelve predicate sites bind this id into raw SQL, several inside `order_type_id NOT IN (?)`. A
runtime `find_by(key:)` can return `nil`, and a `nil` in that list renders as `NOT IN (6, NULL)`,
which evaluates to NULL for **every** row — silently emptying the shoot universe fleet-wide. The
failure would appear as "the metrics all went to zero last night," with no error anywhere. A
pinned integer constant cannot fail that way. The cost is drift risk, which the verify task covers.

### Why `cart` and not `public`

`order_types.public` is serialized but is **never used in a WHERE clause anywhere in the
application**. It does not gate anything. The agent-facing PWA order form is gated solely by
`CartsController#items` filtering `cart IS NOT NULL`. Recapture keeps `cart` NULL, which is what
actually makes it ops-only; `public: false` is set as documentation of intent, not as a control.

## Consequences

**Good**

- The recapture rate is a clean delivery-quality signal from 2026-09-01 forward.
- The reshoot rate becomes a clean revenue signal for the first time.
- Historical numbers are untouched, so nothing anyone has already seen changes.

**Bad, or at least worth knowing**

- **There is a discontinuity at 2026-09-01.** Any chart of reshoot rate spanning that date will
  show a step down, because service-recovery visits stop being counted as reshoots. This is the
  document that explains it. Do not "fix" the step.
- **The recapture rate has no history.** It starts at zero coverage and only becomes meaningful
  after enough post-cutover volume accumulates.
- **Recapture and reshoot rates overlap and must never be summed.** One parent can carry both a
  reshoot child and a recapture child. The two numerators are not disjoint and share the same
  `parent_count` denominator, so adding the rates can exceed 100% and means nothing.
- **`lifetime_child_count` counts recapture children.** `child_count_sql` has no order-type
  filter, and reshoot children already count there. Left as-is deliberately: it is a
  work-performed count, not a shoot or revenue number. Do not read it as billable work.
- **Recaptures incur no $115 in `lifetime_margin_value_cents`.** They are excluded from
  `margin_visit_count` alongside reshoots, so a real photographer visit is costed at zero. This is
  the same accepted inaccuracy reshoot already carries; revisit both together or neither.
- **`lifetime_value_cents` includes recaptures at $0.** Harmless, but a recapture carrying
  `order_services` would surface as revenue under a $0 order type. That would be a data-entry
  error, and it is better to see it than to suppress it.
- The two shoot-predicate families (`Order::FIELD_JOB_EXCLUDED_ORDER_TYPE_IDS` and
  `Order::SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS`) now diverge explicitly rather than by prose.
  That divergence pre-dates this change; it is only being named.

## Notes

**The cutover date lives in four places**, each for a different reader:

1. This ADR — authoritative, and where an analyst charting across the boundary should land.
2. `db/migrate/20260901120000_create_recapture_order_type.rb` — permanent and replayable, travels
   with the schema.
3. `order_types.description` on the row itself — visible in the ops admin form.
4. `order_types.created_at` on the row — machine-readable. Because the id is pinned, no order can
   reference type 300 before the migration runs, so "a recapture predating the cutover" is not a
   state the data can reach.

**Deliberately out of scope**, and still open:

- Whether reshoots should enter the account metrics at all. They are currently excluded from the
  shoot universe; the classification doc's `property` category would include them. Including them
  would raise parent counts and pull median/average shoot value down (318 orders averaging ~$147).
  That is a published-number change and needs its own slice with a before/after for Don.
- `order_types.category_type` — see Options Considered.
- The one negative-total reshoot: order 1263, account 93, 2016-03-16. `order_type_price` 0 with a
  lone −$2,000¢ discount service line, top-level, unpaid. Costs that account $20 of
  `lifetime_value_cents`. Inspected and left alone — a decade-old artifact that should not shape
  the type design.
