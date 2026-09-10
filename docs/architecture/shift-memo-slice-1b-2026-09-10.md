# Account classification — slice 1b shift memo

Generated 2026-09-10 11:06 UTC against `insgt_api_development` (latest order 2026-09-08 13:48 UTC), insgt-api `afeb1f7`. Reproduce: `bin/rails account_classification:shift_memo_1b OUT=<memo.md> CSV=<rows.csv>`.

## What changed

- A shoot is now a completed **property** parent order (`Order.qualifying_parents`). Headshot and event parents leave every count and value; reshoots enter them; recaptures stay out. **4,027 accounts had a shoot under the old definition; 2,071 do now.** The 1,956 that lose every shoot have only headshot or event history and read as prospects (§4.2); the association and internal accounts among them are the case §4.2 says to exclude from outreach by `account_type`.
- Shoot dates read `scheduled_at`, falling back to the first completed log, over parents **and** child visits (`Order.qualifying`). `paid_at` is no longer a date, so completed unpaid shoots are dated.
- Lifetime value is money collected (`Order.billable`): paid, any category but internal, `parent_pays IS NOT TRUE`. A parent-paid add-on's catalogue price leaves the total; unpaid and refunded orders leave it too.
- Visible elsewhere: the teams dashboard order count and CSV export count the same shoots; "Only did one shoot" keeps its in-flight guard; the account dialog's pending count now includes a reshoot booked ahead.

## Population

| | Accounts |
| :-- | --: |
| Active accounts | 4,076 |
| Accounts where at least one of count, date, value or revenue moves | 4,051 |
| Accounts with a stored `account_metrics` row checked against the legacy SQL | 4,054 |
| Stored rows whose `rolling_90_parent_count` differs (the 90-day window slid since the nightly ran 2026-09-08 02:31 UTC) | 12 |
| Stored rows that disagree on any other column (stale row, written under new code, or orders changed since) | 1 on `lifetime_value_cents` (2555) |

## Reconciliation against v3's figures

v3 measured the 2026-09-08 dev restore; this run measures a newer one on a later day, so every figure moves by the orders and accounts that changed in between and by the trailing window sliding forward. The definitions are the same. The one figure that does not reconcile in kind is the third row: v3 read "undated shoots gain a date", but only the property share does — the rest leave the universe.

| Figure | v3 | This run, old definition | This run, new definition |
| :-- | --: | --: | --: |
| Trailing-365 completed parents / accounts | 2,005 / 937 | 2,028 / 949 | 1,476 / 512 |
| Same, v3's property-only figure (dated by the completed log then; by the shoot date now) | 1,484 / 509 | — | as above |
| Accounts with trailing-year work and none of it property | 428 | 437 | — |
| Completed parents with no `paid_at` ("undated today") | 3,004 | 2,972 | **162 are property and gain a date; the rest leave the universe** |
| `parent_pays` children carrying a price | 3,726 / $684,555 | 3,734 / $686,045.00 | — |
| `internal`-category orders with a `paid_at` | 1 / $5 | 1 / $5.00 | — |

## Counts

| Column | Accounts down | Accounts up | Unchanged | Σ old | Σ new |
| :-- | --: | --: | --: | --: | --: |
| `lifetime_parent_count` | 2,299 | 123 | 1,654 | 18,372 | 15,551 |
| `rolling_90_parent_count` | 105 | 6 | 3,965 | 453 | 344 |
| `rolling_365_parent_count` | 466 | 16 | 3,594 | 2,028 | 1,476 |
| `lifetime_reshot_parent_count` | 0 | 1 | 4,075 | 190 | 192 |

Accounts with any shoot, old vs new: 4,027 → 2,071. `lifetime_reshoot_rate`: rose for 15 accounts, fell for 38, became NULL for 1,961 (no shoots left in the denominator).

## Dates

| Column | Gained a date | Lost a date | Moved earlier | Moved later | Same |
| :-- | --: | --: | --: | --: | --: |
| `first_shoot_at` | 17 | 46 | 2,040 | 14 | 0 |
| `most_recent_shoot_at` | 17 | 46 | 1,950 | 104 | 0 |

`most_recent_shoot_at` shift where both dates exist (2,054 accounts): under 7 days 1,904, 7–30 days 94, 31–90 days 24, over 90 days 32.

Lifecycle bucket (§4.2, as of today) transitions caused by the date change:

| From | To | Accounts |
| :-- | :-- | --: |
| prospect | cooling | 2 |
| prospect | lapsed | 15 |
| new | prospect | 10 |
| new | active | 1 |
| active | prospect | 4 |
| active | cooling | 2 |
| cooling | prospect | 1 |
| cooling | at_risk | 2 |
| at_risk | prospect | 4 |
| at_risk | active | 2 |
| at_risk | lapsed | 4 |
| lapsed | prospect | 27 |

## Shoot values

`median_shoot_value_cents`: rose for 237 accounts (32 of them from a $0 median), fell for 42, became NULL for 1,961 (no property shoots). A shoot's value is still its own price; only the universe changed.

## Revenue

| | Cents |
| :-- | --: |
| Σ `lifetime_value_cents`, old (every active order) | $4,474,186.00 |
| Σ `lifetime_value_cents`, new (`Order.billable` plus services) | $3,698,648.00 |
| Drop | $775,538.00 |
| of which `parent_pays` children (3,843 rows; price plus services) | $705,240.00 |
| of which unpaid or refunded rows (3,962 rows) | $70,293.00 |
| of which `internal` rows with a `paid_at` (1 rows) | $5.00 |
| Residual (must be $0) | $0.00 |

The `parent_pays` bucket is price plus services on every parent-paid child; v3's $684,555 was `order_type_price` on the 3,734 children carrying one ($686,045.00 here), which is the same population measured two ways. Accounts whose `lifetime_value_cents` falls: 768; rises: 0.

Independent check — what Stripe charged on the same orders:

| | Cents |
| :-- | --: |
| Σ `transactions` net of refunds, active orders of active accounts | $3,609,832.00 |
| Σ `lifetime_value_cents`, new | $3,698,648.00 |
| Gap | $88,816.00 |
| of which billable orders with no transaction row (895 rows: manual and offline payments) | $92,201.00 |
| of which price minus amount charged on billable orders that have one | -$2,825.00 |
| less charges on orders billable does not count (10 rows) | $560.00 |
| Residual (must be $0) | $0.00 |

Why Σ shoot values ≠ lifetime value (they answer different questions: list price of jobs done vs money collected):

| | Cents |
| :-- | --: |
| Σ shoot values over `qualifying_parents` | $3,527,509.00 |
| − qualifying parents that are unpaid or refunded | $22,251.00 |
| + paid self-paying children | $188,760.00 |
| + paid brand and marketing parents | $4,300.00 |
| + paid property parents with no completed log | $330.00 |
| = Σ `lifetime_value_cents`, new | $3,698,648.00 (residual $0.00) |

## Completion hygiene (§5.2)

Property parents scheduled in the past with no completed log. These are not shoots until someone closes them; the ones under 90 days old are the accounts whose `most_recent_shoot_at` may read older than reality.

| Scheduled | Parents | In canceled state |
| :-- | --: | --: |
| 0-30 days | 21 | 0 |
| 31-90 days | 2 | 0 |
| 91-365 days | 14 | 0 |
| over a year | 164 | 12 |

## Largest movers

By lifetime value:

| Account | Old | New |
| :-- | --: | --: |
| 2663 Robert Antoniadis | $100,985.00 | $69,595.00 |
| 141 Mike Williams | $47,016.00 | $30,596.00 |
| 88 Tamara Kapa | $67,833.00 | $54,303.00 |
| 63 Ken & Caroll Dembowski | $50,924.00 | $39,169.00 |
| 2362 Scott Voak | $30,230.00 | $19,465.00 |
| 1801 Irina Polyak | $37,200.00 | $26,555.00 |
| 169 Ken May | $33,625.00 | $23,615.00 |
| 218 Brian Reifeiss | $36,393.00 | $26,918.00 |
| 10 Rick Sauer | $29,770.00 | $20,460.00 |
| 412 Sharon Miller | $31,804.00 | $22,699.00 |

By lifetime shoot count:

| Account | Old | New |
| :-- | --: | --: |
| 2 InsightPhotos | 236 | 4 |
| 2275 NSDCR NSDCR | 53 | 0 |
| 3266 Hot Properties | 47 | 0 |
| 2836 PSAR | 46 | 0 |
| 2663 Robert Antoniadis | 152 | 168 |
| 2435 Esperanza Rodmel | 14 | 1 |
| 8737 Women's Council of Realtors | 10 | 0 |
| 3076 Victor Herrera | 8 | 0 |
| 11058 Tony Escalante | 8 | 0 |
| 78 Mukesh Jain | 226 | 234 |

By most recent shoot date:

| Account | Old | New |
| :-- | --: | --: |
| 38 Jim Berns | 2018-02-12 | 2022-03-10 |
| 151 Ryan Johnson | 2020-07-07 | 2023-08-31 |
| 585 Barbara Hanson | 2016-06-15 | 2019-03-08 |
| 2551 Martha Morales | 2020-08-01 | 2022-05-04 |
| 2435 Esperanza Rodmel | 2026-01-24 | 2024-06-26 |
| 606 Michelle Plastiras | 2017-01-07 | 2018-07-11 |
| 3140 Trevor Wayne | 2022-12-04 | 2024-05-28 |
| 798 Richard Bui | 2017-10-28 | 2019-03-21 |
| 2040 Linda Insinger | 2020-06-14 | 2019-04-11 |
| 220 Mark Schultz | 2015-11-13 | 2016-11-11 |
