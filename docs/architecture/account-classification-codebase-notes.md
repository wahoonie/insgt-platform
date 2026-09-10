# Account Classification — codebase notes

The `file:line` map for `docs/architecture/account-classification.md`. Read at Phase 0 of every slice; verify the entries the slice depends on before surveying fresh. Flat and factual: file, line, what it is, which slice or commit put it there. Paths are `apps/insgt-api` unless prefixed.

Established by the drift audit of 2026-09-07 (`account-classification-drift-audit-2026-09-07.md`) against `feat/account-account-type` at 393005e; rewritten 2026-09-10 for slice 1b against `feat/account-classification-1b` at afeb1f7; re-ranged 2026-09-10 for slice 2 against `feat/account-classification-2` at ca49f32. A moved line is a reason to update this file, not to distrust it.

## Schema

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 13 | Schema version `2026_09_11_120000` | slice 2, bdb9a7e |
| `db/schema.rb` | 18–53 | `account_metrics`: `first_shoot_at` 42, `most_recent_shoot_at` 43; recapture columns 44–47; **the five §3.4 numeric columns 48–52** (`rolling_365_parent_count`, `rolling_365_value_cents`, `peak_365_parent_count`, `peak_365_ended_on` (`date`), `active_user_count`), nullable, no default; unique index on `account_id` 53. The four enum-side columns and the two §3.4 indexes do not exist (slice 3) | slice 2, bdb9a7e |
| `db/schema.rb` | 105 | `accounts.account_type` smallint, nullable, no default | slice 4, 94485f8 |
| `db/schema.rb` | 481–492 | `marketing_events`: no `event_type` | (slice 5 void) |
| `db/schema.rb` | 654 | `order_types.category_type` smallint `null: false`, no default | slice 1a, 81bf2e0 |
| `db/schema.rb` | 723, 788 | `orders.marketing_event_id` and its index | 2015 |
| `db/schema.rb` | 1107–1138 | `system_metrics`: mirror of the shoot-date and recapture columns (1131–1136); **no slice 2 column** — the mirror stops at the shared columns (§3.4, G6) | pre-1a / ADR 002; slice 2 by omission |
| `db/schema.rb` | 118–130 | `accounts_users`: `account_id, user_id, role_id, status_type`; one row per (account, user, role); uniqueness is a model validation on create, not a constraint — 440 pairs held more than one active role on the 2026-09-10 snapshot, 0 exact duplicate rows | legacy |
| `db/migrate/20260911120000_add_slice_2_columns_to_account_metrics.rb` | 1–67 | The five columns; header: what each is, why nullable with no default and what NULL means (two count conventions, 27–33), **why a code-only rollback leaves them stale rather than NULL** (35–38), why no `system_metrics` mirror (44–48), no backfill and no index (50–54), strong_migrations-clean (56–58); `add_column`s 61–65 | slice 2, bdb9a7e / 9572e1c |
| `db/migrate/20260715120000_add_shoot_dates_to_metrics.rb` | 14–30, 40–42 | Why the shoot dates were dated by `paid_at` (**superseded** by §5.3, slice 1b); why `first_shoot_at` is a datetime, not a date — the argument `peak_365_ended_on` answers in the slice 2 migration header | pre-1a |
| `db/migrate/20260901120000_create_recapture_order_type.rb` | 41–42, 77–112 | Recapture row pinned at id 300, key `recapture`, price 0, `cart: nil`, `public: false` | ADR 002, 35f71c5 |
| `db/migrate/20260901120001_add_recapture_counts_to_metrics.rb` | 3–4, 29–36 | Four recapture columns on both metrics tables; the "column-for-column parallel" claim at 3–4 holds for the shared columns only since slice 2 | ADR 002, 35f71c5 |
| `db/migrate/20260904120000..3` | — | `category_type`: nullable add, backfill (`CATEGORY_KEYS` at `..120001:38–59`), unvalidated CHECK, validate-and-flip | slice 1a, 81bf2e0 |
| `db/migrate/20260904120004_add_account_type_to_accounts.rb` | 35 | Nullable add of `account_type` | slice 4, 94485f8 |
| `config/initializers/strong_migrations.rb` | 7, 18, 49–51 | `start_after = 20260806120000` (every classification migration is checked), `target_version = 15`, `safe_by_default` deliberately off (indexes state `disable_ddl_transaction!` + `algorithm: :concurrently` explicitly — slice 3's two indexes will) | pre-1a |

No `spec/architecture` existed before 1b; `scope :qualifying` existed on no branch before 7aa170b.

## Models — the scopes (slice 1b) and the membership predicate

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/order.rb` | 127–175 | ARCHITECTURE NOTES for the classification scopes: the three questions, why completed log, why category not ids, why `parent_pays IS NOT TRUE` on `billable` only, the building block and the pending derivation, refunds, `ZERO_SHOOTS_SQL` kept separate | 1b, 7aa170b |
| `app/models/order.rb` | 176–180 | `scope :property_work` — active, `category_type = property`, `joins(:order_type)`. Building block, not a consumer scope | 1b, 7aa170b |
| `app/models/order.rb` | 181 | `scope :qualifying` = `property_work.where(completed_log_sql)` | 1b, 7aa170b |
| `app/models/order.rb` | 182 | `scope :qualifying_parents` = `qualifying.where(parent_id: nil)` — pinned structurally by the contract spec | 1b, 7aa170b |
| `app/models/order.rb` | 183–189 | `scope :billable` — not internal, active, `paid_at` present, `parent_pays IS NOT TRUE`, **no completion or cancellation condition** (§5.4: a paid-then-cancelled order is revenue) | 1b, 7aa170b |
| `app/models/order.rb` | 190–196 | `scope :pending_shoots` — `property_work`, parents, NOT completed, `scheduled_at >= now`, not canceled | 1b, 7aa170b |
| `app/models/order.rb` | 202–210 | `Order.completed_log_sql`: the EXISTS over `order_logs`, sanitized | 1b, 7aa170b |
| `app/models/order.rb` | 220–228 | `Order.shoot_date_sql`: `COALESCE(orders.scheduled_at, (SELECT MIN(order_logs.created_at) …))` — the one §5.3 definition; written against the `orders` alias, so it composes into any scope's `select` (`shoots_sql`, `billable_sql`) | 1b, 7aa170b |
| `app/models/order_event.rb` | 17–31 | `OrderEvent.completed_id` (memoised `find_by!`), `canceled_id` (memoised `find_by`) | 1b, 7aa170b |
| `app/models/order.rb` | 22, 43 | `RESHOOT_ORDER_TYPE_ID = 6`, `RECAPTURE_ORDER_TYPE_ID = 300` — name a kind of child in the rate numerators; never a universe | legacy / ADR 002 |
| `app/models/order.rb` | 45–55, 84–86 | `SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS` (margin only, §10); `MARGIN_LTV_*` (untouched) | 1b, 19fe446 / afeb1f7 |
| `app/models/account.rb` | 51 | `ZERO_SHOOTS_SQL` (keeps headshots; deliberately not a shoot predicate) | pre-1a |
| `app/models/account.rb` | 116–117 | `has_many :accounts_users` (active) and `has_many :users` (active users, `.distinct`, through) — the model's definition of an account's people | legacy |
| `app/models/account.rb` | 257–261 | `Account#order_count` → `orders.qualifying_parents.count`, or the search's `shoot_count` alias | 1b, 19fe446 |
| `app/models/account.rb` | 557–561 | **`Account#users_count`**: `COUNT(DISTINCT users.id)` over `accounts_users`, membership active AND user active, written against `id` so it works on an unsaved `Account.new(id:)`. The §3.4 definition of `active_user_count` (G1) and what the accounts index ships as `user_count` | legacy; adopted by slice 2, b6e3b33 |
| `app/helpers/accounts_helper.rb` | 101–103 | `set_user_count!` → `user_count` on every account row (ops reads `userCount`) — why `active_user_count` is not on the metrics endpoint (G10) | legacy |
| `app/models/order.rb` | 1082, 1108 | `issue_refund` sets `paid_at: nil` (refunds self-correct, §5.4) | pre-1a |

## Query concerns and services

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/concerns/account_query.rb` | 153–158 | `where_created_on` → `join_shoots!` | pre-1a |
| `app/models/concerns/account_query.rb` | 167–192 | `where_only_once` (`def` at 182): count from `join_shoots!`, in-flight exclusion `NOT EXISTS (Order.pending_shoots …)`, `paid_at IS NOT NULL` FILTER; sets `options[:group]` + `HAVING` — the `GROUP BY` interaction slice 4's worklist sort must check (G9) | 1b, 19fe446 |
| `app/models/concerns/account_query.rb` | 211–224 | `join_shoots!` (`def` at 219): `INNER JOIN orders` plus `orders.id IN (Order.qualifying_parents.select(:id).to_sql)`; the idempotent `join_on[…]` pattern slice 4's `account_metrics` join copies | 1b, 19fe446 |
| `app/models/concerns/account_query.rb`, `app/controllers/accounts_controller.rb`, `lib/api_search.rb` | — | The accounts index emits no `ORDER BY` (`search` never sets `options[:order]`; `search_params` copies no sort key; `ApiSearch#query` selects `accounts.*` with `.distinct` unconditionally) — the four reasons the worklist ordering waits for slice 4 (§9, G9) | surveyed slice 2 |
| `app/models/concerns/user_query.rb` | 182, 195; 220–226, 344, 412 | `COUNT(*) OVER (PARTITION BY …)` — window functions are house style; `DIRECTORY_SORTS` — the repo's one server-side sort (`NULLS LAST`, `Arel.sql`, id tiebreak, 400 on unknown), the template for slice 4's `ACCOUNT_SORTS` | legacy |
| `lib/listing_export.rb`, `lib/order_url_export.rb` | 92; 74 | `ROW_NUMBER() OVER`, nested in a subquery and filtered outside — the shape `peak_365_window_sql` follows; no frame clause existed before slice 2 | legacy |
| `app/models/concerns/order_query.rb` | 247 | Hardcoded `NOT IN (3,12,19)` — out of scope, still present | legacy |
| `app/services/account_metrics/calculator.rb` | 33–35 | `#compute`: the attributes, unsaved (the memo reads it) | 1b, b8a8b85 |
| `app/services/account_metrics/calculator.rb` | 39–56 | `computed_values`: the merge chain; slice 2's four merges at 42–46 | slice 2 |
| `app/services/account_metrics/calculator.rb` | 58–79 | `parent_counts`: **11** positional binds (comment 58 corrected from 12 in cbee3f0), universe is the CTE; bind list untouched by slice 2 | 1b, ff4b1f9; comment slice 2 |
| `app/services/account_metrics/calculator.rb` | 80–88 | `rolling_365_parent_count`: one bind, `365.days.ago`; why its own query and not a twelfth column | slice 2, cbee3f0 |
| `app/services/account_metrics/calculator.rb` | 90–109 | `peak_365_window`: `peak_365_parent_count` (0 when no shoots) and `peak_365_ended_on` (raw `Date`, nil when 0); why overwrite not ratchet (G14) | slice 2, 352725b / c6179c1 |
| `app/services/account_metrics/calculator.rb` | 111–114 | `lifetime_value`: one bind | 1b, 9e86a49 |
| `app/services/account_metrics/calculator.rb` | 116–121 | `rolling_365_value`: two binds in text order (services status, cutoff) | slice 2, 73dd025 |
| `app/services/account_metrics/calculator.rb` | 123–138 | `active_user_count`: `@account.users_count` — the one non-heredoc aggregation; why not a heredoc, why not `users.count` (G1); cites v4 §3.4 as the corrected text | slice 2, b6e3b33 / 9572e1c |
| `app/services/account_metrics/calculator.rb` | 174–179 | `shoot_dates` over `visits_sql` | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 264–268 | `exec`: skips `sanitize_sql_array` when there are no binds (String#% hazard); `peak_365_window_sql` and `shoot_dates_sql` go through it bind-less | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 276–292 | `shoots_sql` (`qualifying_parents` + shoot date, `to_sql`), `visits_sql` (`qualifying`); why interpolation is bind-safe; the one place the universe enters the class | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 307–353 | `parent_counts_sql`: `WITH shoots AS (…)`, windows by `shoot_at`, child EXISTS by order-type id; comment 304 says 11 binds | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 355–360 | `rolling_365_parent_count_sql`: `COUNT(*) FILTER (WHERE shoots.shoot_at >= ?)` over the shoots CTE, inclusive, no upper bound | slice 2, cbee3f0 |
| `app/services/account_metrics/calculator.rb` | 362–403 | `peak_365_window_sql`: one `COUNT(*) OVER (ORDER BY shoot_at RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW)` over **`shoots_sql`** — the parents-only universe, pinned by the contract spec — `ORDER BY window_count DESC, shoot_at DESC LIMIT 1`, `shoot_at::date`; why backward (cites v4 §5.4), why closed, why latest on a tie (G4) | slice 2, 352725b / c6179c1 / 9572e1c |
| `app/services/account_metrics/calculator.rb` | 406–415 | `billable_sql`: `Order.billable` + `shoot_date_sql AS shoot_at` (each row's own date, D2); `lifetime_value_sql` reads it by `id` only | 1b, 9e86a49; date slice 2, 73dd025 |
| `app/services/account_metrics/calculator.rb` | 417–435 | `lifetime_value_sql` (`Order.billable` plus services); SQL text untouched by slice 2 | 1b, 9e86a49 |
| `app/services/account_metrics/calculator.rb` | 437–469 | `rolling_365_value_sql`: the same rows and per-row expression, `WHERE billable.shoot_at >= ?`; why no completion condition, why the expression is duplicated | slice 2, 73dd025 |
| `app/services/account_metrics/calculator.rb` | 472–, 500–536 | `margin_revenue_sql`, `margin_visit_count_sql`: legacy margin universe (§10) | pre-1a; comment afeb1f7 |
| `app/services/account_metrics/calculator.rb` | 538–592 | `shoot_values_sql`, median / average / rolling-90 over the shoots CTE | 1b, e72d1ac |
| `app/services/account_metrics/calculator.rb` | 594–601 | `shoot_dates_sql`: MIN/MAX of `visits.shoot_at` | 1b, ff4b1f9 |
| `app/services/system_metrics/calculator.rb` | 41, 204 | "12 positional binds" — **known-stale** (the list carries 11, as in the account calculator); left for a later cleanup, out of slice 2's scope | 1b |
| `app/services/system_metrics/calculator.rb` | 8–11, 45, 189–200, 252–275, 391 | Fleet mirrors of the shared columns; the note at 8–11 forbids deriving fleet figures from account rows — why there is no fleet peak (G6) | 1b |
| `app/services/account_metrics/recompute_all.rb` | 40–54 | The nightly sweep §6 extends: `find_each` over active accounts → `Calculator.call` (errors caught per account), then `SystemMetrics::Calculator`; untouched by slice 2 | pre-1a |
| `app/views/accounts_metrics/show.json.jbuilder` | 67–85 | `rolling_365_parent_count`, `peak_365_parent_count` (79–80) and `peak_365_ended_on` as an ISO date (85), top-level, outside the owner guard; why `active_user_count` is not emitted (75–78) | slice 2, 18bbb48 |
| `app/views/accounts_metrics/show.json.jbuilder` | 87–94 | Shoot dates comment corrected to §5.3 (was `paid_at`) | slice 2, 18bbb48 |
| `app/views/accounts_metrics/show.json.jbuilder` | 102–109 | The owner-only money block; `rolling_365_value_cents` at 104 | slice 2, 18bbb48 |
| `app/controllers/accounts_metrics_controller.rb` | 9, 20–32 | Roles admin/scheduler/owner; pending-only body when the row is missing; untouched | pre-1a |
| `app/services/account_pending_shoots_service.rb` | 18–39 | `Order.pending_shoots.where(account_id:).count` | 1b, 36d96ef |
| `app/services/account_csv_export_service.rb` | 84–106 | `first_shoot_dates`, `shoot_counts`, `account_ids` | 1b, 19fe446 |
| `app/services/marketing_source_metrics_service.rb` | 49, 84, 110 | `EXCLUDED_ACCOUNT_IDS = [2, 2555]`; `parent_pays IS NOT TRUE` revenue predicate (untouched) | legacy |

## Rake tasks and lib

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/churn_report.rb` | 12–24, 98–104 | Activity = `Order.qualifying_parents` minus caller exclusions, plucked with `shoot_date_sql` | 1b, 98f4b7c |
| `lib/tasks/accounts.rake` | 16–26, 38–48 | `COMPOSITION_EXCLUDED_ACCOUNT_IDS` (26), `SHOOT_VOLUME_TIERS` (47) — unchanged; the tiers' `no shoots` row works because the stored count is 0, never NULL, once recomputed | pre-1a |
| `lib/tasks/accounts.rake` | 454–475 | `joint_ownership` ARCHITECTURE NOTES: both counts are READ from `account_metrics`; the freshness trade; the unweighed partition and why it still joins the shared-owner test | slice 2, 0d041e3 |
| `lib/tasks/accounts.rake` | 488–560 | The task: `scoped_accounts` CTE **unchanged** (526–530), `owner_memberships` / `shared_owner_user_ids` unchanged, `LEFT JOIN account_metrics` (555), the two columns and `oldest_computed_at` (547–553) in one query; the completed-event guard removed (a3fbb9a) | slice 2, 0d041e3 / a3fbb9a |
| `lib/tasks/accounts.rake` | 578–599 | Row mapping with `recomputed:`; `weighed, unweighed = accounts.partition` (594); the deploy-window refusal (596–599) | slice 2, 0d041e3 |
| `lib/tasks/accounts.rake` | 625–645 | Definition lines citing the columns; Window and Snapshot lines; the unweighed count on the header and at 722 in Context | slice 2, 0d041e3 |
| `lib/tasks/accounts.rake` | 150–175 | `accounts:composition` — byte-identical to cf0745d (its own `memberships` CTE stays) | pre-1a |
| `lib/tasks/orders.rake` | 362–375, 396–403, 426–428 | Linkage notes and `universe_parents_sql` | 1b, 8bebc4a |
| `lib/tasks/account_classification.rake` | 1–33 | ARCHITECTURE NOTES for the shift memo; 27–30: every NEW column comes from `Calculator#compute`, including the trailing-365 count since slice 2 | 1b, b8a8b85; slice 2, 0d041e3 |
| `lib/tasks/account_classification.rake` | 94–170 | `OLD_COUNTS_SQL`, `OLD_VALUES_SQL`, `OLD_REVENUE_SQL` (literal ids, `paid_at` dating); `cutoff_365` (bound at 367) still feeds the OLD SQL and the ageing bucket | 1b, b8a8b85 |
| `lib/tasks/account_classification.rake` | 383, 404 | The calculator built on `Account.new(id:)` (383) — why `users_count` not `users.count`; `new_rolling_365_parent_count: n[:rolling_365_parent_count]` (404) — `new_trailing_365` deleted | slice 2, 0d041e3 |
| `lib/tasks/account_classification.rake` | 358– | `account_classification:shift_memo_1b` (`OUT=`, `CSV=`) | 1b, b8a8b85 |
| `lib/tasks/metrics.rake` | 142–168, 295, 381– | `metrics:recompute` (untouched); `margin_ltv_exclusion_impact`; `metrics:churn` | legacy |
| `docs/ops/metrics-recompute-cron.md` | — | Heroku Scheduler, 02:30 UTC, not self-scheduling — the window the slice 2 runbook avoids | pre-1a |
| `lib/tasks/order_types.rake` | 13–19, 23–42 | `PINNED_ORDER_TYPE_IDS` and `order_types:verify_pinned_ids` | ADR 002 |
| `lib/account_report.rb` | 739–789; 8, 782–850 | `first_shoot_kpi_*`; `annual_report` keeps `paid_at` columns (flagged §5.3) | 1b, ebb23ff; legacy |
| `lib/status_type.rb` | 4–7 | `active: 1`, `deleted: 2` | legacy |

## Specs

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `spec/architecture/account_classification_spec.rb` | 45–130 | `Order.qualifying` on the canonical fixtures | 1b, 7aa170b |
| `spec/architecture/account_classification_spec.rb` | 131–144 | `qualifying_parents` is `qualifying` + `parent_id IS NULL` (SQL equality pin) | 1b |
| `spec/architecture/account_classification_spec.rb` | 145–209 | `Order.billable` incl. the `IS NOT TRUE` pin and "money is money" | 1b |
| `spec/architecture/account_classification_spec.rb` | 210–248 | `Order.shoot_date_sql` | 1b |
| `spec/architecture/account_classification_spec.rb` | 249–291 | `Order.pending_shoots` | 1b |
| `spec/architecture/account_classification_spec.rb` | 293–421 | **§3.4 / §4.3 / §5.4 slice 2 rules** on the canonical fixtures: 364/366, parents only, refund at zero revenue, paid-no-log as revenue not shoot, `parent_pays` child (paid, so the rule is what excludes it — 592237f), D2 child dating, `rolling <= peak`, the closed 365-day frame on fixed dates, the tie rule, `ended_on` NULL iff peak 0, `active_user_count == users_count`, real 0 vs NULL; the parents-only example (312–320) pins the PEAK's universe too | slice 2, 24c2f50 / 592237f / f5c01e8 |
| `spec/architecture/account_classification_spec.rb` | 423–431 | No `?` in any scope's `to_sql` — also guards the CTEs the calculator interpolates | 1b |
| `spec/support/completed_orders.rb` | 15–28, 30–59 | `create_completed_order`, `PINNED_CATEGORY_TYPES`, `find_or_create_order_type_with_id(…, category_type:)` | 1b, 7aa170b |
| `spec/factories/account_metrics.rb` | 1–14 | Defaults for the NOT NULL columns only; **none for the five slice 2 columns** (G11) | slice 2 by omission |
| `spec/factories/accounts_users.rb` | 1–15 | `role_id` = `account_owner`; one row per (account, user, role) | legacy |
| `spec/services/account_metrics/calculator_spec.rb` | 414–507 | `rolling 365 parent count`: 364/366, the 200-day canary vs rolling-90, cancelled, child, refunded, recapture/headshot, late-closed, `>= rolling_90` | slice 2, cbee3f0 |
| `spec/services/account_metrics/calculator_spec.rb` | 509–582 | `peak 365 parent count`: an old run and its end date, the fixed-date 365-day boundary, the tie, cancelled-only, `peak == rolling` on the current run | slice 2, 352725b |
| `spec/services/account_metrics/calculator_spec.rb` | 584–627 | `lifetime value` (1b) + `rolling_365_value_cents == lifetime` when every row is in window | 1b, 9e86a49; slice 2, 73dd025 |
| `spec/services/account_metrics/calculator_spec.rb` | 629–704 | `rolling 365 value`: every amount pinned in and out of window, the paid-then-cancelled mirror, `<= lifetime` | slice 2, 73dd025 / 592237f |
| `spec/services/account_metrics/calculator_spec.rb` | 706–797 | `active user count`: roles vs people, duplicate row via `insert_all`, soft-deleted membership and user, zero, `== users_count`; the context header and the duplicate-row comment both state what the snapshot holds — 440 multi-role pairs, 0 duplicate rows, uniqueness validated on create only | slice 2, b6e3b33 / f706f2d / ca49f32 |
| `spec/services/account_metrics/calculator_spec.rb` | 799–830 | `empty state`: the five read 0 / 0 / 0 / nil / 0 | slice 2, b6e3b33 |
| `spec/services/system_metrics/calculator_spec.rb` | — | Fleet mirrors; no slice 2 example (no mirror) | 1b |
| `spec/requests/accounts_metrics_spec.rb` | 101–211 | Happy path seeds the five and asserts `rolling365ParentCount` 7, `peak365ParentCount` 12, `peak365EndedOn` `'2026-07-03'`, no `activeUserCount` key (185–193) | slice 2, 18bbb48 |
| `spec/requests/accounts_metrics_spec.rb` | 213–227 | A never-recomputed factory row emits the four as null | slice 2, 18bbb48 |
| `spec/requests/accounts_metrics_spec.rb` | 229–290 | Money gating: `rolling365ValueCents` in `money_keys`, present for owner, absent for admin and scheduler; the three counts asserted present for admin (274–276) and scheduler (284–286), which is what pins them OUTSIDE the owner guard | slice 2, 18bbb48 / e85a8ca |
| `spec/lib/tasks/accounts_rake_spec.rb` | 538–900 | `accounts:joint_ownership`: `run_task` recomputes then invokes (579–582); which accounts count (596–691); shoot weighting (692–788) incl. the 200-day canary that the read-out weighs a year, not the rolling-90 column (716–723); tiers (789); top list (810); **unrecomputed accounts** (851–896: left out and named, shared owner still seen, a row that predates slice 2 — the real deploy-window state — at 878, refusal when none recomputed); refusals (898, the role guard only — the completed-event example went with its guard in a3fbb9a) | 1b, 0abc4cc; slice 2, 0d041e3 / a3fbb9a |
| `spec/lib/tasks/account_classification_rake_spec.rb` | 40–50 | The memo's `new_rolling_365_parent_count` comes from the calculator: 200-day shoot → `'1'` there and `'0'` in the rolling-90 column | slice 2, 0d041e3 |
| `spec/lib/tasks/orders_rake_spec.rb` | 372–410 | Linkage examples | 1b, 8bebc4a |
| `spec/models/account_search_only_once_spec.rb`, `spec/services/account_csv_export_service_spec.rb`, `spec/services/account_pending_shoots_service_spec.rb`, `spec/lib/churn_report_spec.rb`, `spec/lib/account_report_first_shoot_kpi_spec.rb` | — | Slice 1b consumer specs, unchanged | 1b |
| `spec/models/order_type_spec.rb`, `spec/models/account_spec.rb` | 12–20; 17–29 | Pin `category_types` and `account_types` integer-for-integer | slice 1a / slice 4 |

## Repo documentation

| File | What it is |
| :-- | :-- |
| `CLAUDE.md` §Testing | Adding a required column; adding a nullable column whose NULL means something (the recipe the five slice 2 columns follow) |
| `README.md` §Migrations | strong_migrations and the four-migration NOT NULL sequence |
| `insgt-platform/docs/architecture/account-classification.md` | The contract, v5 (2026-09-10) |
| `insgt-platform/docs/plans/account-classification-slice-2.md` | Slice 2's survey, plan, the fourteen gaps and Dan's decisions on the six open questions |
| `insgt-platform/docs/architecture/shift-memo-slice-1b-2026-09-10.md`, `…-production.md` | What slice 1b moved; the hand-over copy |
| `insgt-platform/docs/runbooks/deploy-account-classification-1a-1b.md` | Deploying 1a and 1b together |
| `insgt-platform/docs/runbooks/deploy-account-classification-2.md` | Deploying slice 2: maintenance window, one push, recompute in the window, the invariant table and spot checks |
| `insgt-platform/docs/decisions/002-recapture-order-type.md` | ADR 002 |

## Branch and deploy state, 2026-09-10 (slice 2 implemented, not deployed)

| Ref | Head | Carries |
| :-- | :-- | :-- |
| `heroku/master`, `origin/master`, `master` | cf0745d (2026-09-10) | Slices 1a, 1b, slice 4's column and API — what production runs |
| `feat/account-classification-2` | ca49f32 | Slice 2: 9 implementation commits (bdb9a7e..24c2f50), 4 round-1 review fixes (e85a8ca..f706f2d), 3 round-2 review fixes (9572e1c..ca49f32); not merged. Round 1 was a full seven-lens Claude review plus Codex; round 2 was partial — three lenses died on a model usage limit (see the runbook's review note) |
| insgt-ops `main` | 4bae4a91 | Order-type `categoryType` form and the account-type UI; version 9.58.0; no slice 2 change (the four new keys are ignored) |
| dev database | 2026-09-10 production snapshot (4,079 active accounts; account #12244 created 13:46 UTC after the plan's survey), migrated to 20260911120000 and recomputed under slice 2 at 16:27 UTC | Every active account's `account_metrics` row carries the slice 2 columns; the verification figures in the runbook's deploy log |
