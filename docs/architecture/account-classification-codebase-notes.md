# Account Classification — codebase notes

The `file:line` map for `docs/architecture/account-classification.md`. Read at Phase 0 of every slice; verify the entries the slice depends on before surveying fresh. Flat and factual: file, line, what it is, which slice or commit put it there. Paths are `apps/insgt-api` unless prefixed.

Established by the drift audit of 2026-09-07 (`account-classification-drift-audit-2026-09-07.md`) against `feat/account-account-type` at 393005e; rewritten 2026-09-10 for slice 1b against `feat/account-classification-1b` at afeb1f7. A moved line is a reason to update this file, not to distrust it.

## Schema

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 13 | Schema version `2026_09_04_120004` | — |
| `db/schema.rb` | 18–49 | `account_metrics`: no §3.4 column exists; `first_shoot_at` 42, `most_recent_shoot_at` 43; recapture columns 44–47 | pre-1a / ADR 002 |
| `db/schema.rb` | 100 | `accounts.account_type` smallint, nullable, no default | slice 4, 94485f8 |
| `db/schema.rb` | 476–487 | `marketing_events`: no `event_type` | (slice 5 void) |
| `db/schema.rb` | 649 | `order_types.category_type` smallint `null: false`, no default | slice 1a, 81bf2e0 |
| `db/schema.rb` | 718, 783 | `orders.marketing_event_id` and its index | 2015 |
| `db/schema.rb` | 1126–1131 | `system_metrics` mirror of the shoot-date and recapture columns | pre-1a / ADR 002 |
| `db/migrate/20260715120000_add_shoot_dates_to_metrics.rb` | 14–30 | Why the shoot dates were dated by `paid_at`; **superseded** by §5.3 and slice 1b (the migration is permanent and cannot be edited) | pre-1a |
| `db/migrate/20260901120000_create_recapture_order_type.rb` | 41–42, 77–112 | Recapture row pinned at id 300, key `recapture`, price 0, `cart: nil`, `public: false` | ADR 002, 35f71c5 |
| `db/migrate/20260901120001_add_recapture_counts_to_metrics.rb` | 29–36 | Four recapture columns on both metrics tables | ADR 002, 35f71c5 |
| `db/migrate/20260904120000..3` | — | `category_type`: nullable add, backfill (`CATEGORY_KEYS` at `..120001:38–59`), unvalidated CHECK, validate-and-flip | slice 1a, 81bf2e0 |
| `db/migrate/20260904120004_add_account_type_to_accounts.rb` | 35 | Nullable add of `account_type` | slice 4, 94485f8 |

Slice 1b added no migration. No `spec/architecture` existed before 1b; `scope :qualifying` existed on no branch before 7aa170b.

## Models — the scopes (slice 1b)

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/order.rb` | 127–174 | ARCHITECTURE NOTES for the classification scopes: the three questions, why completed log, why category not ids, why `parent_pays IS NOT TRUE` on `billable` only, the building block and the pending derivation, refunds, `ZERO_SHOOTS_SQL` kept separate | 1b, 7aa170b |
| `app/models/order.rb` | 175–179 | `scope :property_work` — active, `category_type = property`, `joins(:order_type)` (plain INNER JOIN; OrderType's default scope is an order, not a filter). Building block, not a consumer scope | 1b, 7aa170b |
| `app/models/order.rb` | 180 | `scope :qualifying` = `property_work.where(completed_log_sql)` | 1b, 7aa170b |
| `app/models/order.rb` | 181 | `scope :qualifying_parents` = `qualifying.where(parent_id: nil)` — pinned structurally by the contract spec | 1b, 7aa170b |
| `app/models/order.rb` | 182–188 | `scope :billable` — not internal, active, `paid_at` present, `parent_pays IS NOT TRUE`, no completion | 1b, 7aa170b |
| `app/models/order.rb` | 189–195 | `scope :pending_shoots` — `property_work`, parents, NOT completed, `scheduled_at >= now`, not canceled (`OrderEvent.canceled_id \|\| -1`) | 1b, 7aa170b |
| `app/models/order.rb` | 201–209 | `Order.completed_log_sql`: the EXISTS over `order_logs`, sanitized | 1b, 7aa170b |
| `app/models/order.rb` | 219–228 | `Order.shoot_date_sql`: `COALESCE(orders.scheduled_at, (SELECT MIN(order_logs.created_at) …))` as a correlated scalar subquery — the one §5.3 definition | 1b, 7aa170b |
| `app/models/order_event.rb` | 17–31 | `OrderEvent.completed_id` (memoised `find_by!`), `canceled_id` (memoised `find_by`, nil left to the caller) | 1b, 7aa170b |
| `app/models/order.rb` | 22 | `RESHOOT_ORDER_TYPE_ID = 6` — read only by the reshoot-rate numerators, `Order.reshoots`, `orders:audit_reshoots` | legacy |
| `app/models/order.rb` | 43 | `RECAPTURE_ORDER_TYPE_ID = 300` — recapture-rate numerators and the audit; never in a universe predicate | ADR 002 |
| `app/models/order.rb` | 45–55 | `SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS` — **margin only**: `margin_visit_count` ×2 and `metrics:margin_ltv_exclusion_impact` (§10). `FIELD_JOB_EXCLUDED_ORDER_TYPE_IDS` and `Order.shoots` are gone | 1b, 19fe446 / afeb1f7 |
| `app/models/order.rb` | 84–86 | `MARGIN_LTV_*` (untouched, §10); comment no longer claims the shared columns are all-types | legacy; comment 9e86a49 |
| `app/models/account.rb` | 51 | `ZERO_SHOOTS_SQL` (keeps headshots; deliberately not a shoot predicate) | pre-1a |
| `app/models/account.rb` | 257–261 | `Account#order_count` → `orders.qualifying_parents.count`, or the search's `shoot_count` alias | 1b, 19fe446 |
| `app/models/order.rb` | 1082, 1108 | `issue_refund` sets `paid_at: nil` (refunds self-correct, §5.4) | pre-1a |

## Query concerns and services

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/concerns/account_query.rb` | 153–158 | `where_created_on` → `join_shoots!` | pre-1a |
| `app/models/concerns/account_query.rb` | 166–192 | `where_only_once`: count from `join_shoots!`, in-flight exclusion `NOT EXISTS (Order.pending_shoots … )` at 186–187, `paid_at IS NOT NULL` FILTER as a payment fact | 1b, 19fe446 |
| `app/models/concerns/account_query.rb` | 211–224 | `join_shoots!`: `INNER JOIN orders` plus `orders.id IN (Order.qualifying_parents.select(:id).to_sql)` | 1b, 19fe446 |
| `app/models/concerns/order_query.rb` | 247 | Hardcoded `NOT IN (3,12,19)` — out of scope, still present | legacy |
| `app/services/account_metrics/calculator.rb` | 33–35 | `#compute`: the attributes, unsaved (memo reads it) | 1b, b8a8b85 |
| `app/services/account_metrics/calculator.rb` | 58–65 | `parent_counts`: 12 positional binds, universe is the CTE | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 76–79 | `lifetime_value`: one bind | 1b, 9e86a49 |
| `app/services/account_metrics/calculator.rb` | 115–120 | `shoot_dates` over `visits_sql` | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 205–209 | `exec`: skips `sanitize_sql_array` when there are no binds (String#% hazard) | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 217–230 | `shoots_sql` (`qualifying_parents` + shoot date, `to_sql`), `visits_sql` (`qualifying`); why interpolation is bind-safe | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 248–289 | `parent_counts_sql`: `WITH shoots AS (…)`, windows by `shoot_at`, child EXISTS by order-type id (kind of child, not a universe) | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 294–322 | `billable_sql`, `lifetime_value_sql` (`Order.billable` plus services) | 1b, 9e86a49 |
| `app/services/account_metrics/calculator.rb` | 354–370 | `margin_visit_count_sql`: legacy margin universe, explicitly not `parent_counts_sql`'s | pre-1a; comment afeb1f7 |
| `app/services/account_metrics/calculator.rb` | 392–446 | `shoot_values_sql`, median / average / rolling-90 over the shoots CTE | 1b, e72d1ac |
| `app/services/account_metrics/calculator.rb` | 448–455 | `shoot_dates_sql`: MIN/MAX of `visits.shoot_at` | 1b, ff4b1f9 |
| `app/services/system_metrics/calculator.rb` | 45, 189–200, 206, 252–275, 391 | Fleet mirrors of the above with no account predicate; margin visit count at 299 stays on the legacy constant | 1b, same commits |
| `app/services/account_pending_shoots_service.rb` | 18–39 | `Order.pending_shoots.where(account_id:).count`; the why-live notes kept; reshoots in, recaptures out | 1b, 36d96ef |
| `app/services/account_csv_export_service.rb` | 84–106 | `first_shoot_dates` (`Order.qualifying` + `minimum(shoot_date_sql)`), `shoot_counts` (`qualifying_parents`), `account_ids` | 1b, 19fe446 |
| `app/services/marketing_source_metrics_service.rb` | 49, 84, 110 | `EXCLUDED_ACCOUNT_IDS = [2, 2555]`; `parent_pays IS NOT TRUE` revenue predicate (untouched) | legacy |

## Rake tasks and lib

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/churn_report.rb` | 12–24, 98–104 | Activity = `Order.qualifying_parents` minus caller exclusions, plucked with `shoot_date_sql`; completion required, reshoots count | 1b, 98f4b7c |
| `lib/tasks/accounts.rake` | 456–462 | Why `joint_ownership` derives `rolling_365_parent_count` (slice 2's column does not exist) and from what | 1b, 0abc4cc |
| `lib/tasks/accounts.rake` | 517–523, 555–559, 635–636 | `qualifying_parents_sql` interpolated as the `shoots` CTE; the read-out's definition line | 1b, 0abc4cc |
| `lib/tasks/accounts.rake` | 16–26, 38–48 | `COMPOSITION_EXCLUDED_ACCOUNT_IDS`, `SHOOT_VOLUME_TIERS` (unchanged) | pre-1a |
| `lib/tasks/orders.rake` | 362–375, 396–403 | Linkage notes: the denominator is `qualifying_parents`, decomposed into `property_work` parents plus completion so the buckets stay distinct; a reshoot parent is inside the universe | 1b, 8bebc4a |
| `lib/tasks/orders.rake` | 426–428 | `universe_parents_sql` interpolated into `parent_in_denominator` | 1b, 8bebc4a |
| `lib/tasks/account_classification.rake` | 1–30 | ARCHITECTURE NOTES for the shift memo: why OLD is literal SQL cited to c999b29, the stored-row cross-check, how to reproduce | 1b, b8a8b85 |
| `lib/tasks/account_classification.rake` | 36–43 | `V3_FIGURES` printed beside this run's | 1b, b8a8b85 |
| `lib/tasks/account_classification.rake` | 84–160 | `OLD_COUNTS_SQL`, `OLD_VALUES_SQL`, `OLD_REVENUE_SQL` (literal ids 6 and 300, `paid_at` dating) | 1b, b8a8b85 |
| `lib/tasks/account_classification.rake` | 221–340 | `revenue_bridge`, `shoot_value_bridge`, `transactions_bridge`, `completion_hygiene` | 1b, b8a8b85 |
| `lib/tasks/account_classification.rake` | 342–360 | `stored_row_mismatches`, per column | 1b, b8a8b85 |
| `lib/tasks/account_classification.rake` | 362– | `account_classification:shift_memo_1b` (`OUT=`, `CSV=`) | 1b, b8a8b85 |
| `lib/tasks/metrics.rake` | 295 | `margin_ltv_exclusion_impact` reads the legacy constant (margin, §10) | legacy |
| `lib/tasks/metrics.rake` | 381– | `metrics:churn` injects `MARGIN_LTV_FIELD_VISIT_EXCLUDED_ORDER_TYPE_IDS` and `MARGIN_LTV_EXCLUDED_ACCOUNT_IDS` into `ChurnReport` (unchanged) | legacy |
| `lib/tasks/order_types.rake` | 13–19, 23–42 | `PINNED_ORDER_TYPE_IDS` and `order_types:verify_pinned_ids` | ADR 002 |
| `lib/account_report.rb` | 739–770 | `first_shoot_kpi_year_ago` (prints, writes CSV) | 1b, ebb23ff |
| `lib/account_report.rb` | 772–789 | `first_shoot_kpi_rows`: earliest `Order.qualifying` visit by `shoot_date_sql`, `qualifying_parents` count, no payment condition | 1b, ebb23ff |
| `lib/account_report.rb` | 8, 782–850 | `IGNORE_ACCOUNT_IDS`; `annual_report` keeps `paid_at`-based first-order columns (not named by the contract; flagged in v4 §5.3) | legacy |
| `lib/status_type.rb` | 4–7 | `active: 1`, `deleted: 2` | legacy |

## Specs

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `spec/architecture/account_classification_spec.rb` | 45–130 | `Order.qualifying` on the canonical fixtures: cancelled, booked-never-delivered, refunded, `parent_pays` and self-paying child, reshoot, recapture parent and child, headshot-only, internal with `paid_at`, completed unpaid, soft-deleted order, retired order type | 1b, 7aa170b |
| `spec/architecture/account_classification_spec.rb` | 131–144 | `qualifying_parents` is `qualifying` + `parent_id IS NULL` (SQL equality pin) | 1b |
| `spec/architecture/account_classification_spec.rb` | 145–209 | `Order.billable` incl. the `IS NOT TRUE` pin on a NULL `parent_pays` | 1b |
| `spec/architecture/account_classification_spec.rb` | 210–248 | `Order.shoot_date_sql`: `scheduled_at`, fallback, first of two logs, nil, never `paid_at` | 1b |
| `spec/architecture/account_classification_spec.rb` | 249–291 | `Order.pending_shoots` | 1b |
| `spec/architecture/account_classification_spec.rb` | 292–300 | No `?` in any scope's `to_sql` | 1b |
| `spec/support/completed_orders.rb` | 30–59 | `PINNED_CATEGORY_TYPES` (3 and 73 `marketing`, 300 `recovery`), `category_type:` override on `find_or_create_order_type_with_id` | 1b, 7aa170b |
| `spec/services/account_metrics/calculator_spec.rb` | — | Shoot dates by the shoot date, child visits and reshoots in the range, headshot-only account, rolling windows by `scheduled_at`, D4 median example, lifetime value rules | 1b, ff4b1f9 / e72d1ac / 9e86a49 |
| `spec/services/system_metrics/calculator_spec.rb` | — | Fleet mirrors: shoot-value universe, lifetime value, dates | 1b |
| `spec/models/account_search_only_once_spec.rb` | — | Universe examples, the in-flight exclusion (booked ahead blocks; abandoned and cancelled do not), agreement with `Account#order_count` | 1b, 19fe446 |
| `spec/services/account_csv_export_service_spec.rb` | — | Order Count and First Shoot columns | 1b, 19fe446 |
| `spec/services/account_pending_shoots_service_spec.rb` | — | Reshoot booked ahead counts, headshot does not | 1b, 36d96ef |
| `spec/lib/churn_report_spec.rb` | — | Completed visits dated by `scheduled_at`; injected exclusions layered on the scope | 1b, 98f4b7c |
| `spec/lib/tasks/accounts_rake_spec.rb` | 717–750 | Joint ownership counts a reshoot, ignores a recapture and a headshot event, dates by `scheduled_at` | 1b, 0abc4cc |
| `spec/lib/tasks/orders_rake_spec.rb` | 372–410 | Linkage: event parent outside the universe, completed reshoot parent counted, uncompleted reshoot parent pending | 1b, 8bebc4a |
| `spec/lib/tasks/account_classification_rake_spec.rb` | — | Memo rows, residuals, stored-row cross-check | 1b, b8a8b85 |
| `spec/lib/account_report_first_shoot_kpi_spec.rb` | — | KPI rows agree with `first_shoot_at` | 1b, ebb23ff |
| `spec/models/order_type_spec.rb` | 12–20 | Pins `category_types` integer-for-integer | slice 1a |
| `spec/models/account_spec.rb` | 17–29 | Pins `account_types` | slice 4 |

## Repo documentation

| File | What it is |
| :-- | :-- |
| `CLAUDE.md` §Testing | Adding a required column; adding a nullable column whose NULL means something |
| `README.md` §Migrations | strong_migrations and the four-migration NOT NULL sequence |
| `insgt-platform/docs/architecture/account-classification.md` | The contract, v4 (2026-09-10) |
| `insgt-platform/docs/architecture/shift-memo-slice-1b-2026-09-10.md` | What slice 1b moves, account by account, on the 2026-09-08 restore |
| `insgt-platform/docs/runbooks/deploy-account-classification-1a-1b.md` | Deploying 1a and 1b together; the memo hand-over is step 6 |
| `insgt-platform/docs/decisions/002-recapture-order-type.md` | ADR 002 |

## Branch and deploy state, 2026-09-10

| Ref | Head | Carries |
| :-- | :-- | :-- |
| `heroku/master`, `origin/master` | a3e40e9 (2026-09-02) | Recapture; not `category_type`, not `account_type` |
| `master` | c999b29 (2026-09-08) | `category_type` (1b88f09) and `account_type` (`feat/account-account-type` merged) |
| `feat/account-classification-1b` | afeb1f7 (2026-09-10) | Slice 1b, 12 commits on c999b29; not merged, not pushed |
| insgt-ops `main` | 4bae4a91 | Order-type `categoryType` form (782a8c85, in no tag) and the account-type UI; version 9.58.0 |
| dev database | 2026-09-08 production restore (4,076 active accounts; latest order 2026-09-08 13:48 UTC) | `account_metrics` rows from production's 2026-09-08 02:31 UTC nightly, i.e. the old definition — what the memo's cross-check relies on |
