# Account Classification — codebase notes

The `file:line` map for `docs/architecture/account-classification.md`. Read at Phase 0 of every slice; verify the entries the slice depends on before surveying fresh. Flat and factual: file, line, what it is, which slice or commit put it there. Paths are `apps/insgt-api` unless prefixed.

Established by the drift audit of 2026-09-07 (`account-classification-drift-audit-2026-09-07.md`) against `feat/account-account-type` at 393005e; rewritten 2026-09-10 for slice 1b against `feat/account-classification-1b` at afeb1f7; re-ranged 2026-09-10 for slice 2 against `feat/account-classification-2` at ca49f32; re-ranged 2026-09-14 for slice 3 against `feat/account-classification-slice-3` (working tree, uncommitted). A moved line is a reason to update this file, not to distrust it.

## Schema

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 13 | Schema version `2026_09_12_120001` | slice 3 |
| `db/schema.rb` | 18–59 | `account_metrics`: `first_shoot_at` 42, `most_recent_shoot_at` 43; recapture columns 44–47; the five §3.4 numeric columns 48–52; **the four §3.4 label columns 53–56** (`lifecycle_type` `limit: 2`, `lifecycle_type_at` `datetime`, `value_type` and `peak_value_type` `limit: 2`), nullable, no default; unique index on `account_id` 57; **`index_account_metrics_on_lifecycle_type_and_value_type` 58**. `[account_id, lifecycle_type]` is deliberately absent (§3.4, G6) | 53–56, 58 slice 3 |
| `db/schema.rb` | 110 | `accounts.account_type` smallint, nullable, no default | slice 4, 94485f8 |
| `db/schema.rb` | 486–497 | `marketing_events`: no `event_type` | (slice 5 void) |
| `db/schema.rb` | 659 | `order_types.category_type` smallint `null: false`, no default | slice 1a, 81bf2e0 |
| `db/schema.rb` | 728, 793 | `orders.marketing_event_id` and its index | 2015 |
| `db/schema.rb` | 1112–1143 | `system_metrics`: mirror of the shoot-date and recapture columns (1136–1141); **no slice 2 or slice 3 column** — the mirror stops at the shared columns, and a fleet "lifecycle" is not a thing (§3.4, G6 / G10) | pre-1a / ADR 002; slices 2 and 3 by omission |
| `db/schema.rb` | 128–140 | `accounts_users`: `account_id, user_id, role_id, status_type`; one row per (account, user, role); uniqueness is a model validation on create, not a constraint — 440 pairs held more than one active role on the 2026-09-10 snapshot, 0 exact duplicate rows | legacy |
| `db/migrate/20260911120000_add_slice_2_columns_to_account_metrics.rb` | 1–67 | The five columns; header: what each is, why nullable with no default and what NULL means (two count conventions, 27–33), **why a code-only rollback leaves them stale rather than NULL** (35–38), why no `system_metrics` mirror (44–48), no backfill and no index (50–54), strong_migrations-clean (56–58); `add_column`s 61–65 | slice 2, bdb9a7e / 9572e1c |
| `db/migrate/20260912120000_add_classification_types_to_account_metrics.rb` | 1–91 | The four label columns. Header: what each column is and why `lifecycle_type_at` is derived rather than stamped (8–24), **the TWO NULL conventions these four columns carry** (33–51), `:integer, limit: 2` and why not `:smallint` (53–58), no `system_metrics` mirror (60–63), no backfill and why the index is a separate later file (65–70), why a code-only rollback is worse here than for slice 2 — a stale LABEL reads as a current judgment (72–77), strong_migrations-clean (79–83); explicit `up`/`down` 86–96 | slice 3 |
| `db/migrate/20260912120001_add_lifecycle_index_to_account_metrics.rb` | 1–60 | The one index. Header: the access path it serves (3–7), **why `[account_id, lifecycle_type]` is not shipped** (9–15), why it is precautionary (17–20), why it is its own file and lands after the columns (22–28), the concurrent-index deploy note and why `if_not_exists` alone would be worse (30–36), why `down` spells `algorithm: :concurrently` by hand (38–43), why §3.4's v5 snippet raises (45–48); `disable_ddl_transaction!` 50, name constant 52, `up`/`down` 54–66 | slice 3 |
| `db/migrate/20260715120000_add_shoot_dates_to_metrics.rb` | 14–30, 40–42 | Why the shoot dates were dated by `paid_at` (**superseded** by §5.3, slice 1b); why `first_shoot_at` is a datetime, not a date — the argument `peak_365_ended_on` answers in the slice 2 migration header | pre-1a |
| `db/migrate/20260901120000_create_recapture_order_type.rb` | 41–42, 77–112 | Recapture row pinned at id 300, key `recapture`, price 0, `cart: nil`, `public: false` | ADR 002, 35f71c5 |
| `db/migrate/20260901120001_add_recapture_counts_to_metrics.rb` | 3–4, 29–36 | Four recapture columns on both metrics tables; the "column-for-column parallel" claim at 3–4 holds for the shared columns only since slice 2 | ADR 002, 35f71c5 |
| `db/migrate/20260904120000..3` | — | `category_type`: nullable add, backfill (`CATEGORY_KEYS` at `..120001:38–59`), unvalidated CHECK, validate-and-flip | slice 1a, 81bf2e0 |
| `db/migrate/20260904120004_add_account_type_to_accounts.rb` | 35 | Nullable add of `account_type` | slice 4, 94485f8 |
| `config/initializers/strong_migrations.rb` | 7, 18, 49–51 | `start_after = 20260806120000` (every classification migration is checked), `target_version = 15`, `safe_by_default` deliberately off (indexes state `disable_ddl_transaction!` + `algorithm: :concurrently` explicitly — slice 3's index does, in both directions); `auto_analyze = true` at 32 fires an `ANALYZE` after each index build | pre-1a |

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
| `app/models/account_metric.rb` | 13–21 | `VALUE_TYPES = { single: 1, occasional: 2, core: 3, anchor: 4 }` — ONE constant feeding both tier enums, so the two can never describe different bands; why the names live in `AccountClassification` and the integers here (§3.0) | slice 3 |
| `app/models/account_metric.rb` | 23–44 | The three enums, all `prefix: true`. The comment records what was measured on Rails 7.2.3: an unprefixed `new` is REFUSED by Rails at class-definition time, but an unprefixed `active` is **not caught** and silently rebinds `ApplicationRecord`'s `scope :active` from `status_type = 1` to `lifecycle_type = 3`. Two enums sharing one frozen hash, both prefixed, is accepted | slice 3 |
| `app/models/application_record.rb` | 4, 18–20 | `scope :active` and `def active?`, inherited by every model — the reason `prefix: true` is load-bearing on `AccountMetric`. Note `account_metrics` has **no `status_type` column**, so both the inherited scope and the predicate are unusable on that model; the pin spec asserts the scope's SQL, not its result | legacy; surveyed slice 3 |
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
| `app/services/account_metrics/calculator.rb` | 39–59 | `computed_values`: the merge chain; slice 2's four merges at 45–49. Slice 3 assigns the chain to `values` and merges `classification(values)` LAST (58), because the labels are derived from columns computed above rather than from their own queries — the `derived_rates(counts)` shape widened to the whole result | slice 2; reshaped slice 3 |
| `app/services/account_metrics/calculator.rb` | 61–81 | `parent_counts`: **11** positional binds (comment 58 corrected from 12 in cbee3f0), universe is the CTE; bind list untouched by slice 2 | 1b, ff4b1f9; comment slice 2 |
| `app/services/account_metrics/calculator.rb` | 83–90 | `rolling_365_parent_count`: one bind, `365.days.ago`; why its own query and not a twelfth column | slice 2, cbee3f0 |
| `app/services/account_metrics/calculator.rb` | 92–112 | `peak_365_window`: `peak_365_parent_count` (0 when no shoots) and `peak_365_ended_on` (raw `Date`, nil when 0); why overwrite not ratchet (G14) | slice 2, 352725b / c6179c1 |
| `app/services/account_metrics/calculator.rb` | 114–117 | `lifetime_value`: one bind | 1b, 9e86a49 |
| `app/services/account_metrics/calculator.rb` | 119–124 | `rolling_365_value`: two binds in text order (services status, cutoff) | slice 2, 73dd025 |
| `app/services/account_metrics/calculator.rb` | 126–141 | `active_user_count`: `@account.users_count` — the one non-heredoc aggregation; why not a heredoc, why not `users.count` (G1); cites v4 §3.4 as the corrected text | slice 2, b6e3b33 / 9572e1c |
| `app/services/account_metrics/calculator.rb` | 169–180 | `shoot_dates` over `visits_sql` | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 182–204 | **`lifecycle_run`**: the instant the account's current unbroken run of visits began, or nil. NOT merged into `computed_values` — it is not a column, and `#call` assigns the compute hash straight onto the record. Carries the measurement that makes the run start worth having: 142 of 152 active accounts have an earlier gap, median derived "active since" 85 days vs 34 for "since the last visit" | slice 3 |
| `app/services/account_metrics/calculator.rb` | 236–283 | **`classification(values)`**: the four labels, derived in Ruby from the accumulated hash plus `lifecycle_run`. Takes its own `now` (slice 2's G3). Comment states it reads NO stored row and touches no association, so the memo's unsaved-`Account.new(id:)` path keeps working, and why `lifecycle_run` is called unconditionally rather than only for `active` | slice 3 |
| `app/services/account_metrics/calculator.rb` | 326–330 | `exec`: skips `sanitize_sql_array` when there are no binds (String#% hazard); `peak_365_window_sql` and `shoot_dates_sql` go through it bind-less | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 332–357 | `shoots_sql` (`qualifying_parents` + shoot date, `to_sql`) 340, `visits_sql` (`qualifying`) 352; why interpolation is bind-safe; the one place the universe enters the class. **`visits_sql`'s comment corrected in slice 3** — it said "Feeds the date range only" and now names both consumers and says why they must share a universe. The correction was missed on the first pass and caught in review round 2 | 1b, ff4b1f9; comment slice 3 |
| `app/services/account_metrics/calculator.rb` | 372–420 | `parent_counts_sql`: `WITH shoots AS (…)`, windows by `shoot_at`, child EXISTS by order-type id; comment 304 says 11 binds | 1b, ff4b1f9 |
| `app/services/account_metrics/calculator.rb` | 420–427 | `rolling_365_parent_count_sql`: `COUNT(*) FILTER (WHERE shoots.shoot_at >= ?)` over the shoots CTE, inclusive, no upper bound | slice 2, cbee3f0 |
| `app/services/account_metrics/calculator.rb` | 429–464 | `peak_365_window_sql`: one `COUNT(*) OVER (ORDER BY shoot_at RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW)` over **`shoots_sql`** — the parents-only universe, pinned by the contract spec — `ORDER BY window_count DESC, shoot_at DESC LIMIT 1`, `shoot_at::date`; why backward (cites v4 §5.4), why closed, why latest on a tie (G4) | slice 2, 352725b / c6179c1 / 9572e1c |
| `app/services/account_metrics/calculator.rb` | 466–521 | **`lifecycle_run_sql`**: two window passes over the SAME visits CTE the shoot dates come from — `LAG` marks every visit opening a run, a running `MAX(...) OVER (ORDER BY shoot_at ROWS UNBOUNDED PRECEDING)` carries the mark forward, the latest visit's carried value is the answer. **Reads `visits_sql`, not `shoots_sql`** (G5), because the lifecycle dates it must agree with do. `ROWS UNBOUNDED PRECEDING`, where `peak_365_window_sql`'s frame is a `RANGE` over time — the repo's second frame clause. Gap is `>= INTERVAL 'RUN_GAP_DAYS days'`, not `> ACTIVE_MAX_DAYS`; the comment carries the off-by-one. No binds, no NULL guard (0 of 16,711 fleet-wide qualifying visits are undated) | slice 3 |
| `app/services/account_metrics/calculator.rb` | 523–532 | `billable_sql`: `Order.billable` + `shoot_date_sql AS shoot_at` (each row's own date, D2); `lifetime_value_sql` reads it by `id` only | 1b, 9e86a49; date slice 2, 73dd025 |
| `app/services/account_metrics/calculator.rb` | 534–552 | `lifetime_value_sql` (`Order.billable` plus services); SQL text untouched by slice 2 | 1b, 9e86a49 |
| `app/services/account_metrics/calculator.rb` | 554–586 | `rolling_365_value_sql`: the same rows and per-row expression, `WHERE billable.shoot_at >= ?`; why no completion condition, why the expression is duplicated | slice 2, 73dd025 |
| `app/services/account_metrics/calculator.rb` | 589–, 617–653 | `margin_revenue_sql`, `margin_visit_count_sql`: legacy margin universe (§10) | pre-1a; comment afeb1f7 |
| `app/services/account_metrics/calculator.rb` | 655–709 | `shoot_values_sql`, median / average / rolling-90 over the shoots CTE | 1b, e72d1ac |
| `app/services/account_metrics/calculator.rb` | 711–718 | `shoot_dates_sql`: MIN/MAX of `visits.shoot_at`; **SQL text untouched by slice 3** | 1b, ff4b1f9 |
| `app/services/system_metrics/calculator.rb` | 41, 204 | "12 positional binds" — **known-stale** (the list carries 11, as in the account calculator); left for a later cleanup, out of slice 2's scope | 1b |
| `app/services/system_metrics/calculator.rb` | 8–11, 45, 189–200, 252–275, 391 | Fleet mirrors of the shared columns; the note at 8–11 forbids deriving fleet figures from account rows — why there is no fleet peak (G6) | 1b |
| `app/services/account_metrics/recompute_all.rb` | 40–54 | The nightly sweep §6 extends: `find_each` over active accounts → `Calculator.call` (errors caught per account), then `SystemMetrics::Calculator`; untouched by slice 2 | pre-1a |
| `app/views/accounts_metrics/show.json.jbuilder` | 67–85 | `rolling_365_parent_count`, `peak_365_parent_count` (79–80) and `peak_365_ended_on` as an ISO date (85), top-level, outside the owner guard; why `active_user_count` is not emitted (75–78) | slice 2, 18bbb48 |
| `app/views/accounts_metrics/show.json.jbuilder` | 87–109 | **The four slice 3 labels**, top-level and outside the owner guard (103, 107–109). Comment states why they are not money, that the ENUM NAME crosses the wire not the integer (§3.1), and the two NULL meanings on one block of four fields | slice 3 |
| `app/views/accounts_metrics/show.json.jbuilder` | 111–118 | Shoot dates comment corrected to §5.3 (was `paid_at`) | slice 2, 18bbb48 |
| `app/views/accounts_metrics/show.json.jbuilder` | 126–133 | The owner-only money block; `rolling_365_value_cents` at 128. **Nothing from slice 3 is inside it** | slice 2, 18bbb48 |
| `app/controllers/accounts_metrics_controller.rb` | 9, 20–32 | Roles admin/scheduler/owner; pending-only body when the row is missing; untouched | pre-1a |
| `app/services/account_pending_shoots_service.rb` | 18–39 | `Order.pending_shoots.where(account_id:).count` | 1b, 36d96ef |
| `app/services/account_csv_export_service.rb` | 84–106 | `first_shoot_dates`, `shoot_counts`, `account_ids` | 1b, 19fe446 |
| `app/services/marketing_source_metrics_service.rb` | 49, 84, 110 | `EXCLUDED_ACCOUNT_IDS = [2, 2555]`; `parent_pays IS NOT TRUE` revenue predicate (untouched) | legacy |

## Rake tasks and lib

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/churn_report.rb` | 12–24, 98–104 | Activity = `Order.qualifying_parents` minus caller exclusions, plucked with `shoot_date_sql` | 1b, 98f4b7c |
| `lib/account_classification.rb` | 1–151 | **The §6 thresholds config, new in slice 3.** ARCHITECTURE NOTES 3–35: the four consumers, why `lib/` is FORCED (`config.autoload_lib` ignores `lib/tasks`, so `app/services` cannot read a `.rake` file), why the enum integers are NOT here, why Symbols. `NEW_WINDOW` 43, the three day boundaries 48–50, `LIFECYCLE_ORDER` 54, `DEGRADING_START_DAYS` 62–66 (91/181/366, derived from the boundaries), `RUN_GAP_DAYS` 78 with the off-by-one derivation. `#lifecycle` 99–109 (floored days; the `new` asymmetry is inherited and must not be "fixed"), `#lifecycle_started_at` 130–137 (`fetch`, so an unknown label raises rather than storing a silent NULL), `#value_tier` 145–149 (nil for 0 — note the bands start at 1, so the guard is belt-and-braces today but is what holds the rule if a band is ever widened) | slice 3 |
| `lib/tasks/accounts.rake` | 16–26, 38–82 | `COMPOSITION_EXCLUDED_ACCOUNT_IDS` (26). **`SHOOT_VOLUME_TIERS` is gone**: slice 3 replaced it with `VALUE_BAND_LABELS` (55–60, the printed labels, still local and still literal because they are a test contract) and `AccountAudit.shoot_volume_tiers` (77–82), which prepends the `no shoots` row to `AccountClassification::VALUE_BANDS`. **A METHOD, not a constant** (66–73 says why: `rakefile` calls `load_tasks` without initializing the app, so an autoloaded constant referenced at rake FILE LOAD time aborts every `rake` invocation including `db:migrate`). Output verified byte-identical before and after | slice 3 |
| `lib/tasks/accounts.rake` | 701 | The one consumer, `AccountAudit.shoot_volume_tiers.each` (was `AccountAudit::SHOOT_VOLUME_TIERS.each`); `tier_range.cover?` unchanged | slice 3 |
| `lib/tasks/accounts.rake` | 454–475 | `joint_ownership` ARCHITECTURE NOTES: both counts are READ from `account_metrics`; the freshness trade; the unweighed partition and why it still joins the shared-owner test | slice 2, 0d041e3 |
| `lib/tasks/accounts.rake` | 488–560 | The task: `scoped_accounts` CTE **unchanged** (526–530), `owner_memberships` / `shared_owner_user_ids` unchanged, `LEFT JOIN account_metrics` (555), the two columns and `oldest_computed_at` (547–553) in one query; the completed-event guard removed (a3fbb9a) | slice 2, 0d041e3 / a3fbb9a |
| `lib/tasks/accounts.rake` | 578–599 | Row mapping with `recomputed:`; `weighed, unweighed = accounts.partition` (594); the deploy-window refusal (596–599) | slice 2, 0d041e3 |
| `lib/tasks/accounts.rake` | 625–645 | Definition lines citing the columns; Window and Snapshot lines; the unweighed count on the header and at 722 in Context | slice 2, 0d041e3 |
| `lib/tasks/accounts.rake` | 150–175 | `accounts:composition` — byte-identical to cf0745d (its own `memberships` CTE stays) | pre-1a |
| `lib/tasks/orders.rake` | 362–375, 396–403, 426–428 | Linkage notes and `universe_parents_sql` | 1b, 8bebc4a |
| `lib/tasks/account_classification.rake` | 1–33 | ARCHITECTURE NOTES for the shift memo; 27–30: every NEW column comes from `Calculator#compute`, including the trailing-365 count since slice 2 | 1b, b8a8b85; slice 2, 0d041e3 |
| `lib/tasks/account_classification.rake` | 48–65 | **`LIFECYCLE_ORDER` is gone**, replaced by the memoised `#lifecycle_order`, which maps `AccountClassification::LIFECYCLE_ORDER` to Strings. Same load-order reason as `shoot_volume_tiers`; the comment at 56–62 states it | slice 3 |
| `lib/tasks/account_classification.rake` | 96–112 | `#lifecycle` now delegates to `AccountClassification.lifecycle(...).to_s`. The arithmetic is unchanged — it is the rule slice 1b shipped, which is exactly why it could move — and `.to_s` sits at this boundary only, so the memo's CSV shape does not change | slice 3 |
| `lib/tasks/account_classification.rake` | 475 | The transition table sorts by `memo.lifecycle_order.index(...)` (was `memo::LIFECYCLE_ORDER`) | slice 3 |
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
| `spec/architecture/account_classification_spec.rb` | 426–585 | **§3.4 / §4.2 / §4.3 slice 3 rules** on the canonical fixtures: the six labels one fixture each, `new`-over-`active` precedence, the 365-still-`at_risk` and 366-`lapsed` boundary, the four bands at both edges of each (a loop that resets state per iteration), the zero-is-NULL rule beside a `prospect` label on the same row, `lapsed ⇒ value_type IS NULL`, `prospect ⇒ no stamp and no tiers`, every other label HAS a stamp, `value_type <= peak_value_type` as integers, and the config-vs-enum vocabulary equivalence in both directions for both enums | slice 3 |
| `spec/architecture/account_classification_spec.rb` | 587–595 | No `?` in any scope's `to_sql` — also guards the CTEs the calculator interpolates, including slice 3's `lifecycle_run_sql` | 1b |
| `spec/support/completed_orders.rb` | 15–28, 30–59 | `create_completed_order`, `PINNED_CATEGORY_TYPES`, `find_or_create_order_type_with_id(…, category_type:)` | 1b, 7aa170b |
| `spec/factories/account_metrics.rb` | 1–14 | Defaults for the NOT NULL columns only; **none for the five slice 2 columns or the four slice 3 columns** (G11) — so every factory row exercises the never-recomputed state, which is what the request spec's null examples assert | slices 2 and 3 by omission |
| `spec/factories/accounts_users.rb` | 1–15 | `role_id` = `account_owner`; one row per (account, user, role) | legacy |
| `spec/services/account_metrics/calculator_spec.rb` | 414–507 | `rolling 365 parent count`: 364/366, the 200-day canary vs rolling-90, cancelled, child, refunded, recapture/headshot, late-closed, `>= rolling_90` | slice 2, cbee3f0 |
| `spec/services/account_metrics/calculator_spec.rb` | 509–582 | `peak 365 parent count`: an old run and its end date, the fixed-date 365-day boundary, the tie, cancelled-only, `peak == rolling` on the current run | slice 2, 352725b |
| `spec/services/account_metrics/calculator_spec.rb` | 584–627 | `lifetime value` (1b) + `rolling_365_value_cents == lifetime` when every row is in window | 1b, 9e86a49; slice 2, 73dd025 |
| `spec/services/account_metrics/calculator_spec.rb` | 629–704 | `rolling 365 value`: every amount pinned in and out of window, the paid-then-cancelled mirror, `<= lifetime` | slice 2, 73dd025 / 592237f |
| `spec/services/account_metrics/calculator_spec.rb` | 706–797 | `active user count`: roles vs people, duplicate row via `insert_all`, soft-deleted membership and user, zero, `== users_count`; the context header and the duplicate-row comment both state what the snapshot holds — 440 multi-role pairs, 0 duplicate rows, uniqueness validated on create only | slice 2, b6e3b33 / f706f2d / ca49f32 |
| `spec/services/account_metrics/calculator_spec.rb` | 805–932 | **`lifecycle run start`**: nil with no visit, the lone visit, an unbroken run reaching the first visit, the return visit after a long gap, **a gap of exactly 90 days does NOT break the run, a FRACTIONAL gap that still floors to 90 does not either, and exactly 91 does** (the off-by-one, and the fractional example is the only one that distinguishes `>= 91 days` from `> 90 days`), determinism when the run starts on a date two visits share, a child visit inside the run (G5's canary), a cancelled order that cannot bridge a gap (its three dates are chosen so admitting the cancelled order changes the answer — as first written they did not, and round 2 caught it). Exercised through `#send` because the run start is not a column | slice 3 |
| `spec/services/account_metrics/calculator_spec.rb` | 934–1060 | **`lifecycle type`**: the six labels, the three degrading stamps asserted as explicit `+91 / +181 / +366` offsets, **a `new` account stamped at its FIRST visit after a second one** (the two dates must differ or the example guards nothing), a child visit keeping an account `active` where a parents-only reading would say `cooling`, and §4.2's two prospect populations incl. a paying headshot-only account | slice 3 |
| `spec/services/account_metrics/calculator_spec.rb` | 1062–1118 | **`lifecycle_type_at for an active account`**: the run start after a long gap, the `first_shoot_at + 90 days` handover when the run reaches back, and **the stamp not moving when the account simply books another shoot** — G1's stability property, the thing a debounce would otherwise have to provide | slice 3 |
| `spec/services/account_metrics/calculator_spec.rb` | 1120–1184 | **`value tiers`**: each band through the stored column, the zero-count NULL beside a set peak (the reactivation shape), and `value_type <= peak_value_type` as integers | slice 3 |
| `spec/services/account_metrics/calculator_spec.rb` | 1186–1226 | `empty state`: the five read 0 / 0 / 0 / nil / 0; slice 3 adds `'prospect'` / nil / nil / nil — the two NULL conventions in one example | slice 2, b6e3b33; slice 3 |
| `spec/services/system_metrics/calculator_spec.rb` | — | Fleet mirrors; no slice 2 example (no mirror) | 1b |
| `spec/requests/accounts_metrics_spec.rb` | 101–227 | Happy path seeds the five and the four, and asserts `rolling365ParentCount` 7, `peak365ParentCount` 12, `peak365EndedOn` `'2026-07-03'`, **`lifecycleType` `'at_risk'`, `lifecycleTypeAt` `'2026-07-29T21:45:00Z'`, `valueType` `'core'`, `peakValueType` `'anchor'`** (197–200 — enum NAMES, camelCase keys), no `activeUserCount` key | slice 2, 18bbb48; slice 3 |
| `spec/requests/accounts_metrics_spec.rb` | 229–243, 245–258 | A never-recomputed factory row emits the slice 2 four as null (229) and the slice 3 four as null (245). The second states that a null `lifecycleType` does NOT mean `prospect` | slice 2, 18bbb48; slice 3 |
| `spec/requests/accounts_metrics_spec.rb` | 260–338 | Money gating: `rolling365ValueCents` in `money_keys`, present for owner, absent for admin and scheduler; the counts AND **the four labels** asserted present for admin (312–320) and scheduler (326–332), which is what pins them OUTSIDE the owner guard. `money_keys` unchanged | slice 2, 18bbb48 / e85a8ca; slice 3 |
| `spec/lib/tasks/accounts_rake_spec.rb` | 538–900 | `accounts:joint_ownership`: `run_task` recomputes then invokes (579–582); which accounts count (596–691); shoot weighting (692–788) incl. the 200-day canary that the read-out weighs a year, not the rolling-90 column (716–723); tiers (789); top list (810); **unrecomputed accounts** (851–896: left out and named, shared owner still seen, a row that predates slice 2 — the real deploy-window state — at 878, refusal when none recomputed); refusals (898, the role guard only — the completed-event example went with its guard in a3fbb9a) | 1b, 0abc4cc; slice 2, 0d041e3 / a3fbb9a |
| `spec/lib/tasks/account_classification_rake_spec.rb` | 40–50 | The memo's `new_rolling_365_parent_count` comes from the calculator: 200-day shoot → `'1'` there and `'0'` in the rolling-90 column | slice 2, 0d041e3 |
| `spec/lib/tasks/orders_rake_spec.rb` | 372–410 | Linkage examples | 1b, 8bebc4a |
| `spec/models/account_search_only_once_spec.rb`, `spec/services/account_csv_export_service_spec.rb`, `spec/services/account_pending_shoots_service_spec.rb`, `spec/lib/churn_report_spec.rb`, `spec/lib/account_report_first_shoot_kpi_spec.rb` | — | Slice 1b consumer specs, unchanged | 1b |
| `spec/models/order_type_spec.rb`, `spec/models/account_spec.rb` | 12–20; 17–29 | Pin `category_types` and `account_types` integer-for-integer | slice 1a / slice 4 |
| `spec/models/account_metric_spec.rb` | 1–132 | **New in slice 3.** Pins all three enums integer-for-integer (15–33), `peak_value_types == value_types` (40), the config's names ⊆ the enum's keys for both vocabularies (47–53), and the three collision guards (75–116): `AccountMetric.new` still builds a record, `AccountMetric.active`'s SQL still names `status_type` and not `lifecycle_type`, the predicates are namespaced, and **`lifecycle_type_at` the column is kept distinct from `lifecycle_type_at_risk?` the predicate** — one underscore apart and both new in this slice. Also asserts an unclassified row is valid | slice 3 |
| `spec/lib/account_classification_spec.rb` | 1–206 | **New in slice 3.** The config as pure arithmetic, no database: `value_tier` at 0 / nil / both edges of all four bands; `lifecycle` at every boundary incl. **365 → `at_risk`, 366 → `lapsed`**, a fractional day flooring down, and **`new` ending one SECOND after the window** (the example that pins `new` as continuous where the degrading boundaries are floored); `lifecycle_started_at` for all six labels; `RUN_GAP_DAYS == 91` and `DEGRADING_START_DAYS` pinned as literals. Every expectation states its own offset rather than reading back the constant it pins | slice 3 |

## Repo documentation

| File | What it is |
| :-- | :-- |
| `CLAUDE.md` §Testing | Adding a required column; adding a nullable column whose NULL means something (the recipe the five slice 2 columns follow) |
| `README.md` §Migrations | strong_migrations and the four-migration NOT NULL sequence |
| `insgt-platform/docs/architecture/account-classification.md` | The contract, v6 (2026-09-14) |
| `insgt-platform/docs/plans/account-classification-slice-2.md` | Slice 2's survey, plan, the fourteen gaps and Dan's decisions on the six open questions |
| `insgt-platform/docs/architecture/shift-memo-slice-1b-2026-09-10.md`, `…-production.md` | What slice 1b moved; the hand-over copy |
| `insgt-platform/docs/runbooks/deploy-account-classification-1a-1b.md` | Deploying 1a and 1b together |
| `insgt-platform/docs/runbooks/deploy-account-classification-2.md` | Deploying slice 2: maintenance window, one push, recompute in the window, the invariant table and spot checks |
| `insgt-platform/docs/plans/account-classification-slice-3.md` | Slice 3's survey, plan and the fifteen gaps. **Its spot-check table's three degrading stamps are arithmetically wrong** (`+90 / +180 / +365`); its own G1 rule table (`+91 / +181 / +366`) is right and is what shipped — see §14 |
| `insgt-platform/docs/runbooks/deploy-account-classification-3.md` | Deploying slice 3: maintenance window, one push, two migrations, the required recompute, eleven invariants, the three distributions and the corrected spot checks |
| `insgt-platform/docs/decisions/002-recapture-order-type.md` | ADR 002 |

## Branch and deploy state, 2026-09-14 (slice 3 implemented and verified, not committed)

| Ref | Head | Carries |
| :-- | :-- | :-- |
| `heroku/master`, `origin/master`, `master` | d98632f (2026-09-11) | Slices 1a, 1b, slice 2, slice 4's column and API — what production runs |
| `feat/account-classification-slice-3` | d98632f, **working tree dirty** | Slice 3, uncommitted. 9 modified files, 5 new: the two migrations, `lib/account_classification.rb`, `spec/lib/account_classification_spec.rb`, `spec/models/account_metric_spec.rb`. Not committed, not merged, not pushed — the standing instruction is that Dan reviews the diff and commits |
| insgt-ops `main` | 4bae4a91 | No slice 3 change. It models **none** of the eight fields this endpoint now adds (slice 2's four and slice 3's four); every `AccountMetricSummary` field is optional, so the extra keys are ignored rather than breaking |
| dev database | 2026-09-10 production snapshot, migrated to `20260912120001` and recomputed under slice 3 at 13:12–13:14 UTC on 2026-09-14 | 4,078 active accounts swept, 0 failed, 1 min 11 s. All four label columns populated; all 11 post-deploy invariants 0 |

**Verification evidence, 2026-09-14.** Full suite 1,688 examples / 0 failures. Both migrations run
`migrate` → `rollback` → `migrate`; the schema diff is exactly four column lines, one index line and
the version bump. Replayed at the plan's survey instant (2026-09-11 14:20 UTC) the implementation
reproduces **every** figure the plan reasoned out before the code existed: all six lifecycle counts,
all five `value_type` counts, all five `peak_value_type` counts and the 42-account reactivation
cohort. Every difference at today's clock is accounted for by 13 named lifecycle movers and 3 named
band movers. `accounts:joint_ownership` output is byte-identical before and after the reconciliation.

**One correction to the plan** (§14 of the contract carries it): the plan's spot-check table gives
the three degrading stamps as `most_recent_shoot_at + 90 / 180 / 365 days`, where its own G1 rule
table says `+ 91 / 181 / 366`. The rule table is right. Re-evaluating §4.2 **at** each stored stamp
reproduces the stored label for all 1,863 degrading rows under the shipped offsets and for none of
them under the plan's table.

**One defect found and fixed during implementation, not anticipated by the plan.** Referencing an
autoloaded constant at rake FILE LOAD time aborts every `rake` invocation in the repo, `db:migrate`
included: `rakefile` requires `config/application` and calls `load_tasks` without initializing the
application, so Zeitwerk is not yet set up. Both read-out reconciliations now resolve the config in
a memoised method inside the module instead. The rake specs cannot catch this — they load task
files through `Rake.application.rake_require` inside an already-initialized app — so the only signal
is running an actual `rake` command.
