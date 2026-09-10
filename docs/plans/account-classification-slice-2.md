# Account classification — slice 2: the numeric `account_metrics` columns and the nightly recompute

**Repo:** `insgt-api`. No changes elsewhere (the ops interface can render the new fields later; that is an insgt-ops release, not this slice).
**Contract:** `docs/architecture/account-classification.md` v4 — §3.4 (the columns), §5.1 (scopes; the "which scope drives what" table at 505–508 assigns all three shoot-derived columns), §5.3 (shoot date), §5.4 (counts, dates, revenue), §6 steps 1–2 (nightly job), §4.1 and §9 (the worklist ordering pin), §4.3 (zero-count semantics and "never decays").
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Status:** Phase 0 survey and Phase 1 plan complete; STOP for approval. Nothing implemented.
**Survey date:** 2026-09-10, against `insgt-api` `master` at cf0745d (1b merged at 514e5c4; working tree clean; `feat/account-classification-1b` deleted) and the dev DB restored from the 2026-09-10 production snapshot (4,078 active accounts; `account_metrics` rows written by production's 02:31 UTC nightly under the *old* definition on the rolling-90 columns — quoted below only as such; `lifetime_parent_count` and `lifetime_value_cents` on the spot-check accounts already equal the live scopes, so those rows post-date the deploy-day recompute).

## Scope

1. §3.4 — five nullable columns on `account_metrics`, no defaults, no index: `rolling_365_parent_count` (integer), `rolling_365_value_cents` (bigint), `peak_365_parent_count` (integer), `peak_365_ended_on` (date), `active_user_count` (integer).
2. §5.4 / §6 steps 1–2 — `AccountMetrics::Calculator` computes all five; `metrics:recompute` writes them nightly with no change to `RecomputeAll` or the rake task.
3. §3.4 — the two ad hoc derivations of `rolling_365_parent_count` and `active_user_count` (`accounts:joint_ownership`, the slice 1b memo task) are reconciled to the calculator.
4. `GET /accounts/:id/metrics` emits `rolling_365_parent_count`, `peak_365_parent_count`, `peak_365_ended_on` beside the other counts and `rolling_365_value_cents` inside the owner-only money block. `active_user_count` is not emitted (G10: the same fact already ships on every account row as `user_count`).
5. Contract spec additions for §5.4's counts and revenue rules; codebase notes; a v5 amendment; a deploy runbook.

## Out of scope — do not touch

1. `lifecycle_type`, `lifecycle_type_at`, `value_type`, `peak_value_type`, the two §3.4 indexes, the thresholds config — slice 3.
2. Any Pipedrive code (§6 step 4, slice 7).
3. `system_metrics` — no fleet mirror of the five (G6); its calculator and its stale "12 positional binds" comment (`system_metrics/calculator.rb:40–41, 204`) are left alone and noted.
4. The accounts index ordering for the worklist (G9 — sketch only).
5. `AccountAudit::SHOOT_VOLUME_TIERS` and its `no shoots` row — slice 3 makes them read the enum; slice 2 only changes where the count comes from.
6. The existing columns' computation: `parent_counts_sql` (its bind list is untouched; only its stale bind-count comment is corrected) and `lifetime_value_sql` (the value query duplicates the per-row revenue expression rather than refactoring it — precedent: `margin_revenue_sql`, `shoot_values_sql`).
7. `MARGIN_LTV_*`, `SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS`, `OrderQuery` (§10).
8. `AccountReport.annual_report`'s `paid_at` columns (§5.3, already flagged); `ChurnReport`'s trailing-365 *account roster* (`lib/churn_report.rb:57,177–184`) — a different question, left alone.
9. Completion hygiene (§5.2's 201 unclosed parents).
10. insgt-ops: the `AccountMetricSummary` interface, the two render components, and the three stale pre-1b comments found there — listed for the ops follow-up under Write-back.

---

## Phase 0 — survey

### Done

Read the contract sections, the codebase notes (re-verified against cf0745d: the schema, calculator, `order.rb`, `accounts.rake`, `account_classification.rake`, `account_query.rb`, contract-spec and rake-spec rows; every entry is true, several line ranges have drifted — listed under Write-back), the shipped slice 1b code, the metrics pipeline end to end, every metrics-table migration, the two ad hoc derivations, the accounts index query path and its one server-side-sort precedent, the three deploy runbooks and their README, the ops consumer, and the spec suites the slice copies. Measured the population on the dev restore. Prototyped the peak query against an independent Ruby pass and against the document's forward window, and timed the four new queries per account including the worst case.

### Prerequisites — all landed (facts)

| Prerequisite | Evidence |
| :-- | :-- |
| Slice 1a `order_types.category_type` NOT NULL | `db/schema.rb:13` version `2026_09_04_120004`; `db/schema.rb:649` |
| Slice 1b scopes | `app/models/order.rb:176–196` (`property_work` 176–180, `qualifying` 181, `qualifying_parents` 182, `billable` 183–189, `pending_shoots` 190–196); `Order.shoot_date_sql` at 220–228 |
| Calculator reads the scopes | `app/services/account_metrics/calculator.rb:217–222` (`shoots_sql` = `Order.qualifying_parents … shoot_date_sql AS shoot_at`), 226–231 (`visits_sql`), 294–296 (`billable_sql`) |
| 1b merged and deployed | `git log`: 514e5c4 merge of `feat/account-classification-1b`, cf0745d on top; `git status --porcelain` empty; `deploy-account-classification-1a-1b.md` status "Deployed 2026-09-10"; `AccountMetric.count` 4,081 vs 4,078 active accounts (the 3 accounts with shoots and no row are all `status_type 2`) |
| Contract spec exists | `spec/architecture/account_classification_spec.rb` (300 lines; §5.1–§5.4; "later slices append") |
| Nightly job is the one §6 extends | `app/services/account_metrics/recompute_all.rb:40–54` (`find_each(batch_size: 1000)` over active accounts → `Calculator.call`, then `SystemMetrics::Calculator.call`); `lib/tasks/metrics.rake:142–168`; `docs/ops/metrics-recompute-cron.md` (Heroku Scheduler, 02:30 UTC scheduled, 02:31 observed on 2026-09-10; not self-scheduling); `spec/services/account_metrics/recompute_all_spec.rb` stubs the calculator, so it is untouched |
| Recompute is a deploy-window step, three-for-three | `deploy-account-metric.md:43–48`, `deploy-recapture.md:70–78` ("rather than waiting for the 02:30 Heroku Scheduler run"), `deploy-account-classification-1a-1b.md:140–147`; `20260901120001:20–23` says the same |
| Suite runs here | `bundle exec rspec spec/models/order_type_spec.rb` → 4 examples, 0 failures (test DB host `db`); `rubocop` runs on stock defaults — there is no `.rubocop.yml` |

### What this slice touches

| File | Lines | What it is today | Slice 2 change |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 18–49 | `account_metrics`: every `*_count` is `integer NOT NULL DEFAULT 0`, every `*_cents` is `bigint` (sums NOT NULL DEFAULT 0, the four shoot-value columns nullable), every temporal column `datetime`; one unique index on `account_id`; **no `date` column on either metrics table** (every `t.date` in the schema is named `*_on`, so `peak_365_ended_on` follows the naming) | +5 columns (G2, G13); every schema row below shifts by 5 lines |
| `db/schema.rb` | 1102–1133 | `system_metrics`: column-for-column the same list (minus `account_id`, plus `singleton`); `SystemMetrics::Calculator` mirrors every account column | untouched (G6) |
| `db/schema.rb` | 118–130 | `accounts_users`: `account_id, user_id, role_id, status_type smallint default 1`; one row per (account, user, **role**), no unique constraint; duplicate rows exist in production (`accounts.rake:123–129`) | read via `Account#users_count` |
| `db/migrate/20260623130000_add_rolling_90_shoot_value_to_metrics.rb` | 15–21 | Closest template: two nullable `bigint` columns, `def change`, plain `add_column`, header explaining NULL; every one of the seven post-create metrics migrations has this shape — no `disable_ddl_transaction!`, no `safety_assured`, no backfill, no index, recompute is the backfill | pattern to copy, minus the `%i[account_metrics system_metrics]` loop |
| `db/migrate/20260901120001_add_recapture_counts_to_metrics.rb` | 3–4, 20–27 | "the two tables are deliberately column-for-column parallel"; "Existing rows keep those values until the next `rake metrics:recompute`, which is a runbook step for this deploy"; "add_column with a non-volatile default is metadata-only on PG 11+" | header voice to copy; the parallel claim is amended (G6) |
| `db/migrate/20260715120000_add_shoot_dates_to_metrics.rb` | 31–42 | The repo's standing argument against `:date` on these tables (40–42: "`paid_at` is UTC (`config.time_zone` is unset). Truncating server-side would freeze the UTC calendar day and misdate evening Pacific activity"), and against live intra-day facts in the snapshot (31–39: the pending count) | answered in G13 and G1 |
| `config/initializers/strong_migrations.rb` | 7, 18, 32, 44–51 | `start_after = 20260806120000` (so this migration **is** checked), `target_version = 15`, `auto_analyze = true`, `safe_by_default` deliberately off | a nullable `add_column` with no default passes every check (`check_add_column` raises only on a non-nil default, json, generated or auto-incrementing column); `check_down` is the gem default `false` (`strong_migrations-2.8.0/lib/strong_migrations.rb:41`) |
| `app/services/account_metrics/calculator.rb` | 33–52 | `#compute` → `computed_values`: a merge chain of per-concern hashes ending in `computed_at` (51); `#call` writes via `assign_attributes` + `save!` (22–27) and never reads the stored row | +4 merges |
| same | 54–74, 248–290 | `parent_counts` and `parent_counts_sql`: **11 positional binds** (`sed -n 249,289p … \| grep -o "?" \| wc -l` → 11; the comments at 54 and 244 say 12 — stale), `cutoff = 90.days.ago` at 59, "a misordering fails silently" 244–247, `COUNT(*) FILTER (WHERE shoots.shoot_at >= ?)` at 252 — inclusive lower bound, **no upper bound** | **bind list untouched** — the 365 count is its own method (G3); the two stale comments corrected to 11 in commit 2 (comment only) |
| same | 96–105, 435–444 | `rolling_90_shoot_value` / `_sql`: two aggregates from one windowed CTE, `WHERE shoot_values.shoot_at >= ?` at 442, two binds | shape to copy for the new windowed queries |
| same | 294–296 | `billable_sql`: `Order.billable.where(account_id:).select('orders.id').to_sql` — no date column | +`#{Order.shoot_date_sql} AS shoot_at` (G5) |
| same | 306–321 | `lifetime_value_sql`: `SUM(order_type_price + services)` via `LEFT JOIN LATERAL` over active `order_services`, one bind, `COALESCE(…, 0)::bigint`; reads the CTE only through `JOIN orders o ON o.id = billable.id` | untouched; per-row expression copied |
| same | 205–208 | `exec`: skips `sanitize_sql_array` when there are no binds (String#% hazard) | reused; the peak query has no binds and is called `exec(sql)` like `shoot_dates_sql` (116) |
| same | 217–231 | `shoots_sql` / `visits_sql`: the only place the universe enters the class; `to_sql` carries no `?` | reused by the 365 count and the peak query |
| `app/models/account.rb` | 116–117, 557–561 | `has_many :accounts_users, -> { where(status_type active) }` and `has_many :users, -> { where(users.status_type active).distinct }, through:` — the model's definition of an account's users; **`Account#users_count`** (557–561) is the same predicate as a count: `User.joins(accounts_users).where(account_id, both statuses active).distinct.count`, written against `id` so it works for an unsaved `Account.new(id:)` (the association is a null scope there) | the calculator calls `users_count` (G1) |
| `app/helpers/accounts_helper.rb` | 101–103 | `set_user_count!` → `user_count` on every account row; ops reads it as `userCount` and sorts by it client-side | untouched (G10) |
| `app/models/account_metric.rb` | 1–11 | `belongs_to :account`, no CrudAttribution, no validations | untouched |
| `spec/factories/account_metrics.rb` | 1–14 | defaults exactly for the NOT NULL columns plus `computed_at`; none for the nullable ones | no defaults for the five (G11) |
| `app/views/accounts_metrics/show.json.jbuilder` | 58–87 | explicit per-field whitelist (no attribute dump); counts top-level; money inside `if current_user.system_role?(:system_owner)` (81–87); `Jbuilder.key_format camelize: :lower` (`config/environment.rb:7`) camelises automatically; comment at 67–71 still says the shoot dates are "dated by `orders.paid_at`" (stale since 1b) | +3 top-level, +1 in the money block; fix the stale comment |
| `app/controllers/accounts_metrics_controller.rb` | 9, 20–32 | roles admin/scheduler/owner; renders a pending-only body when the row is missing | untouched |
| `spec/requests/accounts_metrics_spec.rb` | 101–176, 194–240 | "happy path" shape; money-gating `before` seeds explicit values (196–203), `money_keys` (206–210) asserted present for owner and absent for admin/scheduler, and the owner example asserts a seeded value (212–218) | +3 keys in the shape with seeded values, `rolling365ValueCents` seeded and in `money_keys`, +1 example for a never-recomputed row |
| `lib/tasks/accounts.rake` | 454–467 | `joint_ownership` ARCHITECTURE NOTES: "`account_metrics.rolling_365_parent_count` DOES NOT EXIST YET … derived from the SAME shoot universe … cutoff moved to 365 days"; 449–455: "Definitions of active user, in-scope account, and owner are accounts:composition's … so the 'sharing an owner' number here reconciles with the one that read-out prints" | rewritten: read the stored columns without narrowing scope (G8) |
| same | 508–522, 534–578, 582–585 | `shoot_cutoff = 365.days.ago`; `qualifying_parents_sql` as the `shoots` CTE (555–561, `>= :shoot_cutoff`); `active_user_count` = `COUNT(*)` over the `memberships` CTE of **DISTINCT (account_id, user_id)** with both statuses active (540–545, 565–566); `rolling_365_parent_count` = `COALESCE(shoot_counts.shoot_count, 0)` (573); `owner_memberships` and `shared_owner_user_ids` are built from `scoped_accounts` (546–554); the `.squish` heredoc forbids `--` comments (524–525); `rows.empty?` → "No accounts in scope. Check the exclusion list." (582–585) | `memberships`, `shoots`, `shoot_counts` CTEs go; `LEFT JOIN account_metrics`; `scoped_accounts` and the owner CTEs stay exactly as they are |
| same | 629–638 | the read-out's definition lines: "Active user = users.status_type 1 holding an active accounts_users row", "Window = trailing 365 days … (derived here; account_metrics has no rolling_365 column yet)" | cite the stored columns and print `MIN(computed_at)` |
| same | 38–48, 666–667 | `SHOOT_VOLUME_TIERS` mirrors §4.3's bands with a `no shoots` row consumed as `tier_range.cover?(account[:shoots])` over a COALESCEd 0 | untouched; works because the stored count is 0, never NULL, once recomputed (G2), and unrecomputed accounts are partitioned out before the tables (G8) |
| `lib/tasks/account_classification.rake` | 27, 187–200, 393, 398, 417–419, 558 | NEW is "`Calculator#compute`: the live definition, never saved" (27, 398); `new_trailing_365` is a second derivation of the same count from the same scope (187–200), called at 393, merged at 419 into the CSV column `new_rolling_365_parent_count` (417); the OLD literal SQL at 94–120 must stay literal | delete `new_trailing_365`; read `compute[:rolling_365_parent_count]` at 419 (G8) |
| `spec/lib/tasks/accounts_rake_spec.rb` | 538–590, 587–681, 683–768 | `joint_ownership` examples: helpers `membership` (556), `solo_account` (563), `duplicate_membership` via `insert_all` (569–576), `reports` (578); nine "which accounts count as joint" examples and nine "shoot weighting" examples (366-day boundary 697, child 711, reshoot/recapture 721, headshot 732, `scheduled_at` dating 743, two logs 751, re-completed 760); ~25 `task.invoke` sites | each example recomputes before invoking; +2 examples |
| `spec/lib/tasks/account_classification_rake_spec.rb` | 21–34, 40–147 | `run_task` swaps stdout and invokes with `CSV=`; `csv_row(account)` reads the per-account CSV (32–34); six examples, none asserting the 365 column (`grep -n "trailing_365\|rolling_365"` → empty); the stored-row cross-check (140) compares the 1b column set only | +1 example for the memo's `new_rolling_365_parent_count` source |
| `spec/services/account_metrics/calculator_spec.rb` | 396–409, 412–450, 452–478, 480–493 | the patterns: `create_completed_order(account:, completed_at:, scheduled_at:)`, relative dates with ≥10 days of slack from the cutoff, no `travel_to` anywhere in the file, `update_columns(order_type_price:, paid_at:, parent_pays:)`, `create(:order_service, order:, price:, quantity:)`, the internal type via `find_or_create_order_type_with_id(9_002, category_type: :internal)` (441); the empty-state example lists every column | +4 contexts |
| `spec/support/completed_orders.rb` | 15–28, 35–59 | `create_completed_order`, `find_or_create_order_type_with_id(id, category_type:)`, `PINNED_CATEGORY_TYPES` | reused |
| `spec/factories/accounts_users.rb`, `spec/factories/orders.rb` | 1–15; 1–8 | `role_id` = `account_owner`, `status_type 1`; a soft-deleted membership needs `update_columns` after create (CrudAttribution forces active on create); the order factory sets no `scheduled_at`, `paid_at` or `order_type_price` | reused |
| `spec/architecture/account_classification_spec.rb` | 45–300 | canonical fixtures (`booked`, `completed`, `ids`, `shoot_date`); §5.1–§5.4 pinned incl. "excludes a cancelled order" (52–56) and "requires no completed log: money is money" (197–201); `SQL composition` guard last (292–299) | +§5.4 counts, peak, revenue window, `active_user_count`; inserted before `SQL composition` |
| `lib/api_search.rb`, `lib/metadata.rb` | 16–30; 43–58 | `query`: `.select(options[:select])` (defaults to `accounts.*`), `.reorder` only when `options[:order]` is set, **`.distinct` always**; `Metadata.calculate` does `query.distinct.count` or wraps a `having` relation | untouched (G9) |
| `app/models/concerns/account_query.rb` | 54–70, 189–191, 329–335 | `search`: filters then `query(options)`; never sets `options[:order]` (`grep -n "options\[:order\]"` → empty); `where_only_once` sets `options[:group]` + `HAVING`; `where_account_type` → `accounts.account_type IS NULL` for `Account::UNCLASSIFIED` | untouched (G9) |
| `app/controllers/accounts_controller.rb` | 296–302 | `search_params`: ten filters plus pagination; no sort key; `params[:order]` is **not** copied through | untouched (G9) |
| `app/models/concerns/user_query.rb`, `app/controllers/users_controller.rb` | 220–226, 343–345, 410–416; 37–41, 336–341 | the repo's only server-side sort: frozen `DIRECTORY_SORTS` whitelist, `NULLS LAST`, `Arel.sql`, `users.id ASC` tiebreak, 400 on an unrecognised sort; also `COUNT(*) OVER (PARTITION BY …)` at 182 and 195 — window functions are house style (with `ROW_NUMBER() OVER` in `lib/listing_export.rb:92`, `lib/order_url_export.rb:74`, all wrapped in a subquery and filtered outside); a frame clause is not (`grep -rniE 'RANGE BETWEEN\|ROWS BETWEEN' app lib` → empty) | the precedents for the slice 4 sketch (G9) and the peak query (G4) |
| `insgt-ops …/account-list/account-list-row.model.ts`, `account-list-page.ts` | 55–66; 88–90, 285–287 | "Client-side sort of the LOADED PAGE ONLY — the API has no sort params"; no default sort; `rolling_365_parent_count` is not a row key | — (G9) |
| `insgt-ops …/account-metric-summary.model.ts`, `.service.ts` | 61–108; 20–25, 36–39 | `AccountMetricSummary`: every field optional; the service returns the raw body (`instanceClass: Object`), nothing strips unknown keys | additive API fields are safe; interface fields are the ops follow-up |
| `insgt-ops …/account-metrics.ts`, `…/account-info-card.ts` | 150–199 (incl. `hasContent` 152–161); 276–295 | explicit render lists | — (ops follow-up) |
| `docs/runbooks/README.md`, `deploy-account-classification-1a-1b.md` | 1–19; 1–186 | the runbook convention (`deploy-<feature>.md`; Status `Draft` / `Ready` / `Deployed <date> [by <name>]`; `## Deploy log`) and the shape to copy (header, Summary, "Deploy order and the window it closes", Prerequisites checklist with the rspec count, numbered Steps with commands, Rollback split code-only / schema, Deploy log) | the slice 2 runbook (below) |

### Collisions (grep, output pasted)

```
$ cd apps/insgt-api && grep -rn "rolling_365\|peak_365\|active_user_count\|peak_value_type\|lifecycle_type\|value_type" app lib spec db config --include=*.rb --include=*.rake --include=*.yml -l
lib/tasks/accounts.rake
lib/tasks/account_classification.rake
db/migrate/20260904120004_add_account_type_to_accounts.rb
```

The first two are the §3.4 derivations this slice removes (SQL aliases, hash keys, and the `SHOOT_VOLUME_TIERS` comment naming `value_type`); the third is the slice 4 migration's header describing the worklist (`:16`, a comment, not a definition). No column, scope, method, or constant carries any of the five names.

```
$ ls db/migrate | grep -i "slice_2\|202609[1-9]"
(empty)
$ grep -rln "AddSlice2ColumnsToAccountMetrics" db spec
(empty)
$ grep -rln "rolling365\|peak365\|activeUserCount\|peakValueType\|lifecycleType\|valueType\|rolling_365\|active_user_count" apps/insgt-ops/src
(empty)
```

Nearest neighbour, not a collision: `userCount` (`user_count` from `Account#users_count`) — see G1/G10.

### Measurements (dev DB, 2026-09-10 production snapshot, read-only, from the scopes unless stated)

| Question | Result |
| :-- | :-- |
| Active accounts | 4,078 (`AccountMetric.count` 4,081) |
| Accounts with a qualifying parent ever | 2,074; qualifying parents fleet-wide 15,565, none with a NULL shoot date, none future-dated |
| Trailing-365 qualifying parents (`shoot_at >= now − 365d`) | 1,486 shoots across 515 accounts — **the production memo's own row** (`shift-memo-slice-1b-2026-09-10-production.md:28`, "1,486 / 515"; §9's 1,476 was the earlier dev restore); per account 0: 3,563 · 1: 277 · 2–5: 178 · 6–11: 41 · 12+: 19 |
| The worklist cohort (`account_type IS NULL`) on this restore | all 4,078 — the restore's `account_type` column was migrated locally, so the five accounts §4.1 says are classified in production read NULL here; 87% of the cohort ties at zero trailing shoots, so any `ORDER BY rolling_365_parent_count DESC` discriminates ~12% of rows and the tiebreak carries the rest (G9) |
| Peak 365-day window count, per account with shoots | 1: 1,071 · 2–5: 701 · 6–11: 191 · 12+: 111 |
| `rolling_365 <= peak_365` violations | 0 of 2,074 |
| Peak prototype (backward closed window, below) vs an independent Ruby pass over the same dates, five busiest accounts | identical counts and end dates: 10288 → 81 / 2026-07-03; 88 → 31 / 2026-06-08; 1123 → 26 / 2026-08-28; 11510 → 25 / 2026-08-14; 1593 → 35 / 2021-08-09. A separate pass using the document's *forward half-open* window also gives 81 / 31 / 26 — the count is insensitive to the window's direction and closure on real data; only the recorded end date differs (10288: forward end 2026-06-12, last shoot of the peak run 2026-07-03) |
| Worst case for the peak scan (most lifetime shoots) | account 58, 304 qualifying parents: peak 57 ending 2021-04-24; the peak query 2.35 ms (mean of 20) against 23.2 ms for `compute` today; next: 78 (234), 88 (225), 1842 (204) |
| Billable rows on active accounts | 16,717; **0 with a NULL shoot date**; 1 without a completed log (dated by `scheduled_at`); 0 future-dated; 1,591 rows across 536 accounts in the trailing 365 days; **0 paid-then-cancelled rows in the window** |
| Σ billable revenue, trailing 365 / lifetime | **$429,047.00** (42,904,700 cents) / **$3,701,878.00** — the lifetime figure equals the production memo's headline to the dollar, so the copied expression is the calculator's |
| Accounts with trailing-365 value > 0 and trailing-365 qualifying parents = 0 | 3 (brand or marketing revenue, or a self-paying child, with no property parent in the year) — a legal state, not a violation |
| `active_user_count`, plain `COUNT(*)` vs `COUNT(DISTINCT user_id)` with the user active | differ for **411** accounts; plain says 453 multi-user accounts, distinct says **102** (101 with the read-out's three exclusions; Q7 measured ~100); 440 (account, user) pairs hold more than one active role |
| distinct users, any status vs active users only | differ for 4 accounts |
| Active-user distribution (distinct, active) | 0: 5 · 1: 3,971 · 2: 87 · 3+: 15 (max 6) |
| Spot-check accounts: trailing-365 value (rows) · active users (membership rows) · stored `lifetime_value_cents` | 10288: 832,500 (55) · **6 (9 rows)** · 1,209,500 — 88: 1,168,500 (35) · 1 (1) · 5,430,300 — 1123: 600,000 (27) · 4 (4) · 3,622,800 — 11510: 702,000 (29) · 1 (1) · 702,000 — 1593: 582,000 (23) · 2 (2) · 3,925,500 |
| `Calculator#compute` today (unsaved) | 11.1 ms/account over the 150 busiest, 8.1 ms over 150 random |
| The four new queries, per account | +3.9 ms (busiest 150), +3.0 ms (random 150) — roughly +35–45% per account, ≈ +15 s across the fleet |

Prototype (read-only): the peak query is one window function over the calculator's own `shoots` CTE, nested in a subquery and filtered outside, as the four existing window sites are —

```sql
WITH shoots AS (<shoots_sql>),
     windowed AS (
       SELECT shoots.shoot_at,
              COUNT(*) OVER (ORDER BY shoots.shoot_at
                             RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW) AS window_count
         FROM shoots)
SELECT window_count AS peak_365_parent_count, shoot_at::date AS peak_365_ended_on
  FROM windowed ORDER BY window_count DESC, shoot_at DESC LIMIT 1
```

### Where the document and the code disagree (quoted both ways; resolved in the gaps, flagged for Dan)

1. **`active_user_count`.** §3.4: "a plain `COUNT(*)` over active `accounts_users`. No judgment." Code: `accounts.rake:527–529` "accounts_users is one row per (account, user, ROLE) with no unique constraint, so a plain COUNT(*) reports a one-agent account as a team"; the model's `has_many :users` is distinct-and-active (`account.rb:116–117`); `Account#users_count` (557–561) is that predicate as a count and already ships as `user_count`; the read-out's `memberships` CTE (540–545) is the same. Measured: the two disagree for 411 accounts and the plain count quadruples the multi-user population (453 vs 102); spot-check account 10288 has 6 users across 9 rows. Q7's "100 of 115" was measured with the distinct predicate. → G1.
2. **Nullability.** §3.4: "All nine are nullable; none takes a factory default." Every existing count on `account_metrics` is `NOT NULL DEFAULT 0` (`schema.rb:20–26`) and the recapture migration states that convention. → G2 (the document wins; the reason is the deploy window).
3. **Which table.** §3.4 adds to `account_metrics` only. `20260901120001:3–4`: "the two tables are deliberately column-for-column parallel". → G6.
4. **The peak window's direction and end date.** §5.4: "Evaluate the window forward from each qualifying shoot date … Record the window's end date in `peak_365_ended_on`." Forward from a shoot on day *d* the window ends on *d* + 365, a date not yet reached for any account whose peak is recent. → G4.
5. **`:date` on a metrics table.** §3.4 declares `peak_365_ended_on` a `date`; `20260715120000:40–42` argued against `:date` on these tables. → G13.
6. **"Never decays."** §4.3: `peak_value_type` "reads `peak_365_parent_count`. Monotonic; never decays." §5.3: "a reschedule rewrites history and `first_shoot_at` can move backward. This is correct behaviour." A full-history recompute follows history edits. → G14.

### Unverified

- Production runtime of `metrics:recompute` (the 1a/1b deploy log says "not recorded"); the per-account figures above are dev-DB, unsaved compute.
- Whether `heroku/master` carries cf0745d (not verifiable from the devcontainer). Irrelevant to this slice's diff, relevant to the runbook's merge step.
- The Heroku Scheduler registration itself (outside the repo).
- The 3 stale `account_metrics` rows behind 4,081 vs 4,078 were not matched to the 3 soft-deleted accounts with shoots.
- ADR 002 records no reasoning for mirroring the recapture columns onto `system_metrics` (`grep -n -i "system_metrics\|mirror\|parallel" docs/decisions/002-recapture-order-type.md` → one unrelated hit); the migration header is the only written record of that decision.
- An independent review query put "accounts with trailing value and no trailing count" at 23; the query above gives 3. The post-deploy check treats the state as legal and reports whatever the deploy-day query returns; the two queries were not reconciled.

---

## Phase 1 — plan

### Gaps pinned

**G1 — `active_user_count` is `Account#users_count`, stored.** Rule: the calculator writes `@account.users_count` — `COUNT(DISTINCT users.id)` over `accounts_users` with the membership active **and** the user active (`account.rb:557–561`), the same predicate as the model's `has_many :users` (`account.rb:116–117`), the read-out's `memberships` CTE (`accounts.rake:540–545`) and `AccountsUser.search` (`accounts_user.rb:42–44`). One definition, already on the wire as `user_count`, so the stored column equals what the accounts index shows and what the Q7 read-out printed. The calculator's one non-heredoc aggregation, with a comment saying why, and saying not to switch it to `@account.users.count`: the memo builds the calculator on `Account.new(id:)` (`account_classification.rake:398`), where the association is a null scope and counts 0, while `users_count` is written against `id` and works. The "live fact in a nightly snapshot" objection (`20260715120000:31–39` kept the pending count out for that reason) is answered by the document: §3.4 stores it "so the teams page can find the ~100 multi-human accounts" — a segment filter reads the snapshot; the row's `user_count` stays the live value. Alternative rejected: the document's literal `COUNT(*)` — it counts roles, reads 453 accounts as teams where 102 are, and the document's own purpose is the distinct number. Also rejected: a fourth copy of the predicate as a heredoc in the calculator (§5.1's rule against copying conditions). **This corrects a §3.4 sentence; it goes in the v5 amendment and is an open question so Dan can veto it.**

**G2 — nullable, no default, and what NULL means.** All five `null: true`, no default, no factory default. NULL means "not computed since slice 2 shipped" — every row between `db:migrate` and the first `metrics:recompute`, and every row again if the code is rolled back while the columns stay. The calculator never writes NULL for a count: `rolling_365_parent_count`, `peak_365_parent_count`, `active_user_count` are `0` for an account with nothing (a real zero, §4.3 — the tier column is where zero becomes NULL, in slice 3); `rolling_365_value_cents` is `0` like `lifetime_value_cents`. `peak_365_ended_on` is NULL exactly when `peak_365_parent_count` is 0 (no window exists). This is also what keeps `SHOOT_VOLUME_TIERS`' `(0..0)` row working when the read-out reads the column (G8). Alternative rejected: `NOT NULL DEFAULT 0` like the seven existing counts — it makes an unrecomputed row indistinguishable from a real zero for the whole deploy window, and the document says nullable. The migration header states that this table now carries two count conventions and why.

**G3 — the rolling-365 window is the rolling-90 window with the cutoff moved, in its own query.** `shoot_at >= 365.days.ago` (a `Time`, taken once per method like `cutoff = 90.days.ago` at `calculator.rb:59,99`), no upper bound, over the same `shoots` CTE. Same shape as `accounts.rake:508,559` and the memo's `cutoff_365`. A shoot exactly 365 days ago is in. The count is its own method and SQL (`rolling_365_parent_count_sql`, one `COUNT(*) FILTER` over `shoots`, one bind) rather than a twelfth column in `parent_counts_sql`: the bind list is "silent-failure territory" (`calculator.rb:244–247`) and out of scope, and the extra CTE evaluation is ~1 ms (measured). The two comments claiming "12 positional binds" (54, 244) are corrected to 11 in the same commit — comment only; the mirror's copy (`system_metrics/calculator.rb:40–41, 204`) is left and noted. Alternative rejected: a closed `[now − 365d, now]` window — no existing window has an upper bound and no completed shoot is future-dated today. Each new method takes its own `N.days.ago`; the three existing `Time.current` reads per `#compute` are not collapsed into one memoised `now` (that would be a behaviour change to shipped columns).

**G4 — the peak is the maximum of the rolling-365 series, evaluated at each shoot.** For each qualifying parent shoot dated *e*, count the account's qualifying parents with `shoot_at` in `[e − 365 days, e]` (closed, matching `>=` on both sides); `peak_365_parent_count` is the maximum; `peak_365_ended_on` is the *e* of the maximal window, the **latest** such *e* on a tie (`ORDER BY window_count DESC, shoot_at DESC LIMIT 1`), cast to a UTC date (G13). One Postgres window function (`RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW`, PG 11+; `target_version` is 15; verified on PG 15: peer rows at an identical timestamp count in each other's window and a row one microsecond past the boundary excludes the 365-day-old row), in SQL like everything else in the class, over the same `shoots` CTE — so the peak can never read a different universe or date than the rolling count. Window functions are house style already (`user_query.rb:182,195`, `listing_export.rb:92`, `order_url_export.rb:74`, each nested in a subquery and filtered outside, as here); the frame clause is new and is what the contract spec's closed-window example pins. Why backward rather than the document's "forward": the set of maximal windows is the same either way (slide any window until an end hits a shoot), so the count is identical — verified against an independent Ruby pass and against a forward half-open pass, and by the fleet-wide invariant `rolling_365 <= peak_365` holding for all 2,074 accounts (a reviewer's brute force over all 2,074, including the 115 accounts with duplicate shoot timestamps, agreed on both count and end date). The end date differs: backward, `peak_365_ended_on` is the last shoot of the peak run, always a real date in the past, which is what "ordered by `peak_365_ended_on DESC`" (§4.3's reactivation cohort) wants; forward, it is *d* + 365, in the future for anyone whose peak is recent (account 1123's forward window ends on survey day + 1). Alternative rejected: the literal forward window with `ended_on = d + 365 days`. A Ruby pass was also rejected: the class is all-SQL by design (`calculator.rb:10`). **Open question for Dan** because it re-words a §5.4 sentence.

**G5 — `rolling_365_value_cents` is the trailing-365 slice of `lifetime_value_cents`.** The universe is not open: §5.1's "which scope drives what" table (`account-classification.md:505–508`) assigns `rolling_365_parent_count` and `peak_365_parent_count` to `qualifying_parents` and `rolling_365_value_cents` to `billable`, beside `lifetime_value_cents`; only the date on the billable row was undecided. Same rows (`Order.billable` for the account), same per-row expression (`order_type_price` + active `order_services`, `calculator.rb:309–319`), filtered to rows whose own `shoot_date_sql >= 365.days.ago` — D2: a self-paying child is placed by its own `scheduled_at`, a parent by its own. `billable_sql` gains `#{Order.shoot_date_sql} AS shoot_at` (the correlated subquery is written against the `orders` alias, which `Order.billable` provides, exactly as `shoots_sql` does); `lifetime_value_sql` reads the CTE only by `id` and is unaffected. No `paid_at` fallback: §5.3 resolves the date, and a billable row that is neither scheduled nor completed has no date and falls out of the window (measured: 0 such rows today, so the sum of the windows reconciles to lifetime). A paid-then-cancelled, unrefunded order in the window **is** revenue (`Order.billable` has no completion or cancellation condition — the contract spec's "money is money" example) while it is not a shoot; the reverse of §5.4's refund case, and pinned as such. Invariant: `rolling_365_value_cents <= lifetime_value_cents` always; `rolling_365_value_cents > 0` with `rolling_365_parent_count = 0` is legal (3 accounts today). Alternative rejected: dating revenue by `paid_at` — §5.3 rules it out and D2 names the child's `scheduled_at`.

**G6 — no `system_metrics` mirror.** The document's schema change names `account_metrics` only and is aware of the mirror (it calls the recapture columns "mirrored on `system_metrics`" and outside the document); three of the five (`peak_365_*`, `active_user_count`) have no fleet meaning and a fleet peak would not be a sum of account peaks (`system_metrics/calculator.rb:8–11` forbids deriving fleet figures from account rows). No spec asserts column parity between the two tables. The recapture migration's "column-for-column parallel" sentence becomes "parallel for the shared columns" in the new migration's header. Alternative rejected: mirroring the two rolling-365 columns — nothing reads a fleet trailing-year figure (the memo and the joint-ownership read-out print it from the rows).

**G7 — no index.** The five are read with the row they live on; the two orderings the document defines over them — the worklist's `rolling_365_parent_count DESC` (§4.1, G9) and the reactivation cohort's `peak_365_ended_on DESC` (§4.3, slice 3, filtered by `lifecycle_type` and `peak_value_type` first) — run over ≤ 4,078 rows. §3.4's two indexes are on slice 3's enum columns and, with `safe_by_default` off, will need the explicit `disable_ddl_transaction!` + `algorithm: :concurrently` pattern of `20260818120000` — slice 3's problem, noted so it is not forgotten.

**G8 — the two ad hoc derivations.** (a) `accounts:joint_ownership` reads `account_metrics.rolling_365_parent_count` and `account_metrics.active_user_count` through a `LEFT JOIN account_metrics ON account_metrics.account_id = scoped_accounts.id` in its one query; the `memberships`, `shoots` and `shoot_counts` CTEs go. **`scoped_accounts` stays exactly as it is** (active minus the exclusion list), so `owner_memberships`, `shared_owner_user_ids` and the "Owners holding more than one in-scope account" line are untouched and still reconcile with `accounts:composition` as the task's header promises (449–455). The two columns come back nullable and every in-scope account reaches Ruby; accounts whose `rolling_365_parent_count` is NULL (no row yet, or never recomputed under slice 2) are partitioned into an *unweighed* set that is dropped from the segment, tier and top-N tables (their multi-user status is unknown) and counted on a new Context line, while they still take part in the shared-owner test. The `rows.empty?` message gains a second clause for the deploy window ("no in-scope account has a recomputed row yet — run metrics:recompute"), and the definition lines cite the columns, print `MIN(computed_at)`, and say the weighted tables cover recomputed accounts only. The read-out becomes as fresh as the nightly instead of the invocation, which is acceptable for a weighing tool and is said on its Window line. Alternative rejected: keeping the live derivation with a "why" comment — the document allows it, the dev-restore workflow slightly favours it (a restore carries the source's nightly rows), and its spec is written against live fixtures; but the read-out would be the one place the 365-day predicate survives outside the calculator, and drift there is exactly the two-definitions failure §3.4 names. The spec cost is mechanical: each example runs `AccountMetrics::RecomputeAll.call` before `task.invoke`. (b) The memo task deletes `new_trailing_365` and reads `rolling_365_parent_count` from the `Calculator#compute` hash it already builds per account (`:398`, merged at `:419`). NEW stays "the live definition, never saved" (`:27`) — this is not a stored read — the memo's Counts table (`:558`) and CSV column are unchanged, and the stored-row cross-check (`:352–366`) compares the 1b column set only. Alternative rejected: leaving the function — it would be the last copy of the predicate.

**G9 — the worklist ordering waits for slice 4's remaining work; slice 2 ships the column only.** Reasons: (1) the accounts index emits no `ORDER BY` at all today — `AccountQuery#search` never sets `options[:order]` and `search_params` copies only the ten filters, so the sort is new plumbing with one precedent, the users directory (`user_query.rb:220–226, 410–416`; `users_controller.rb:37–41`), not a one-line change; (2) `ApiSearch#query` selects `accounts.*` and applies `.distinct` unconditionally (`lib/api_search.rb:20–25`), and Postgres rejects `ORDER BY` on a column absent from a `DISTINCT` select list, so the sort needs a `LEFT JOIN account_metrics` (LEFT — the worklist is exactly the accounts with no row yet), the column added to `options[:select]`, an `ORDER BY … DESC NULLS LAST, accounts.id` tiebreak — load-bearing, since 87% of the worklist ties at zero (measured) and NULL rows must sort after real zeros — a check that `Metadata.calculate`'s `distinct.count` still counts accounts, and the `where_only_once` `GROUP BY` interaction (`account_query.rb:189–191`) — index-query surgery unrelated to computing the column; (3) insgt-ops sorts the loaded page client-side and documents "the API has no sort params" (`account-list-row.model.ts:59–66`); the worklist control is slice 4's remaining ops work, and its template (`userDirectorySorts`, `user-directory.model.ts:60–68`) already exists there — the API sort key and the ops control ship together, reviewable as one unit; (4) it keeps slice 2 in the "new columns, nothing reads them yet" gate row. Sketch for slice 4: `sort=rolling_365_parent_count` and `direction` accepted by `search_params` (400 on anything else, per `validate_account_type_filter`), a frozen `ACCOUNT_SORTS` map in `AccountQuery`, `join_on[:account_metrics]` pushed idempotently like `join_shoots!`, `options[:select] = 'accounts.*, account_metrics.rolling_365_parent_count'`, `Arel.sql('account_metrics.rolling_365_parent_count DESC NULLS LAST, accounts.id ASC')`, the export either inheriting or stripping the sort. Alternative rejected: shipping the API sort key now — it is the same work whenever it ships, and shipping it with no caller changes the slice's risk class for nothing visible.

**G10 — the endpoint emits four of the five.** `rolling_365_parent_count`, `peak_365_parent_count`, `peak_365_ended_on` (ISO date) top-level beside `rolling_90_parent_count`; `rolling_365_value_cents` inside the `system_owner` block with `lifetime_value_cents` (revenue is owner-only, `show.json.jbuilder:75–80`), and added to the request spec's `money_keys` with a seeded value. `active_user_count` is **not** emitted: the same fact already crosses the wire on every account row as `user_count`, live; a second name for it on the metrics endpoint is the two-names failure the `last_shoot_at` rule exists to prevent, and the stored copy is for the nightly snapshot and slice 3's filters, not the dialog. §6's "the label is always explainable" is served by the three counts and the date, which are the inputs slice 3's labels read. Keys camelise automatically (`peak_365_ended_on` → `peak365EndedOn`, confirmed in the red run and pinned); ops ignores unknown keys, so nothing breaks there. While in the file, the 67–71 comment (`paid_at`) is corrected to §5.3; comment only.

**G11 — factories.** No defaults for the five in `spec/factories/account_metrics.rb` (the "nullable column whose NULL means something" recipe, `CLAUDE.md` §Testing); the factory's existing defaults are exactly the NOT NULL set, which stays the rule. A new request-spec example asserts a factory row (never recomputed) emits the three counts and the date as `null`.

**G12 — commits.** The standing instruction (memory: *never commit; Dan reviews and commits*) and the skill's loop ("6. Commit") disagree. This plan lists commit boundaries and messages; the implementation session stops at each boundary with the diff in the working tree and the message drafted, and Dan commits — unless he says at this gate that the session may commit on a `feat/account-classification-2` branch.

**G13 — `peak_365_ended_on` is a `date`, the UTC date of the shoot timestamp.** §3.4 names the column and the type; `20260715120000:40–42` argued against `:date` for `first_shoot_at` because a displayed appointment must localise. This column is not an appointment: it is a cohort ordering key (§4.3, `ORDER BY peak_365_ended_on DESC`) and a coarse "when were they last at peak" answer, and the app runs in UTC (`config/application.rb:29` leaves `time_zone` unset, so `Time.zone` is UTC and a spec's `680.days.ago.to_date` equals the SQL `::date`). A late-evening Pacific shoot dates to the next UTC day; the ordering is unaffected. Cast as `shoot_at::date` in the query, assigned raw (`load_defaults 7.2` enables `postgresql_adapter_decode_dates`, so `exec_query` returns a `Date`, as it returns `Time` for the shoot dates at `calculator.rb:113–114`). Alternative rejected: `peak_365_ended_at` as a `datetime` — the document names the column, and a datetime would invite the localisation the document did not ask for.

**G14 — the peak is overwritten nightly like every other column; it is not a ratchet.** §4.3 says `peak_value_type` "reads `peak_365_parent_count`. Monotonic; never decays." A full-history recompute is monotonic in the sense that matters — the passage of time cannot lower it, unlike the rolling count, which decays as shoots age out — but it can fall when history itself is edited: a reschedule that pulls a shoot out of the run (§5.3: "a reschedule rewrites history … This is correct behaviour"), a soft-deleted order, an order type whose category changes. The calculator today never reads the stored row (`calculator.rb:22–27`), and `peak_365_*` keep that: pure overwrite. Alternative rejected: `max(stored, computed)` — it would freeze an inflated peak from a deleted duplicate order, would be the first column to read its own previous value, and could not be reproduced from history. The v5 amendment says what "never decays" means.

### Approach per unit of work

| Unit | Where | How | Runtime |
| :-- | :-- | :-- | :-- |
| Migration | `db/migrate/20260911120000_add_slice_2_columns_to_account_metrics.rb` | one `change` with five `add_column :account_metrics` lines, `null: true`, no default, no index; header in the recapture migration's voice (what each column is, why nullable and why this table now has two count conventions, why no mirror, no backfill — the first `metrics:recompute` fills them, run as a runbook step); `migrate`, `rollback`, `migrate`; schema diff must be the five lines inside `create_table "account_metrics"` plus the version line, nothing else | metadata-only |
| `rolling_365_parent_count` | `calculator.rb` new `rolling_365_parent_count` / `rolling_365_parent_count_sql` | `WITH shoots AS (#{shoots_sql}) SELECT COUNT(*) FILTER (WHERE shoots.shoot_at >= ?)`; one bind `365.days.ago`; `(row[...] \|\| 0).to_i`; merged in `computed_values` after `parent_counts`; the "12 binds" comments at 54 and 244 corrected to 11 | +1 query, ~1 ms |
| `peak_365_parent_count`, `peak_365_ended_on` | new `peak_365` / `peak_365_sql` | the prototype above over `shoots_sql`; no binds (`exec(sql)`, as `shoot_dates_sql`); no row → `0` / `nil`; date assigned raw | +1 query, ~1–2.5 ms |
| `rolling_365_value_cents` | new `rolling_365_value` / `rolling_365_value_sql`; `billable_sql` gains `shoot_at` | `WITH billable AS (…) SELECT COALESCE(SUM(price + services), 0)::bigint … WHERE billable.shoot_at >= ?`; two binds in text order (order_services status, cutoff), the per-row expression copied from `lifetime_value_sql` | +1 query, ~1 ms |
| `active_user_count` | new `active_user_count` | `{ active_user_count: @account.users_count }` with the comment from G1 | +1 query, <1 ms |
| Endpoint | `show.json.jbuilder`, request spec | as G10 | — |
| Read-outs | `accounts.rake`, `account_classification.rake`, both rake specs | as G8 | — |
| Contract spec | `spec/architecture/account_classification_spec.rb` | new `describe` blocks for §5.4 counts, peak, revenue window, `active_user_count`, NULL-vs-0; before the `SQL composition` guard | — |

Estimated nightly delta: +3–4 ms per account (worst case +2.5 ms on the peak alone), ≈ +15 s over 4,078 accounts on dev hardware; the sweep stays single-threaded and per-account, and no instrumentation exists to see it — the runbook records the wall-clock this time.

### Spec plan — boundary cases by name

`spec/services/account_metrics/calculator_spec.rb`, four new contexts (pattern: 396–409; relative dates with ≥10 days of slack, no `travel_to`):

- **rolling 365** — shoot at `364.days.ago` counts, `366.days.ago` does not; a shoot at `200.days.ago` counts in 365 and not in 90 (the canary that the new cutoff is not the old one; deliberate break: `365.days.ago` → `90.days.ago` in the new method); a **cancelled** parent in the window (`order_event_id` = the `canceled` event, no completed log) reads 0; a child under an in-window parent is not counted; a refunded shoot (`paid_at: nil`) still counts; a recapture parent does not; a headshot-only account reads 0 (reuse the 378–393 fixture); `scheduled_at: 400.days.ago` with `completed_at: 10.days.ago` is out (dated by the visit); `rolling_365_parent_count >= rolling_90_parent_count` on the happy-path fixture.
- **peak 365** — three shoots 700, 690, 680 days ago and one 10 days ago → `peak 3`, `rolling 1`, `ended_on = 680.days.ago.to_date`; two shoots on fixed dates exactly 365 days apart (`2024-03-01 17:00` and `2025-03-01 17:00`) → `peak 2` (closed window; deliberate break: `INTERVAL '364 days'`, which moves the lower bound to 2024-03-02); a tie between two three-shoot runs → `ended_on` is the later run's last shoot; a cancelled parent alone → `0` / `nil`; no shoots → `0` and `nil`; `peak >= rolling` on the happy-path fixture.
- **rolling 365 value** — one fixture, every amount pinned. In window: paid parent 10,000 + service 2,000 (+12,000); self-paying child of it, completed 20 days ago, 1,500 paid (+1,500); paid headshot 12,500 (+12,500); refunded parent 3,000 (0, still a shoot); `parent_pays` child 4,500 (0); internal order 500 with `paid_at` (0). Out of window: paid parent 5,000 at `400.days.ago` (0); D2 child of the paid parent, `completed_at: 20.days.ago, scheduled_at: 400.days.ago, parent_pays: false, paid_at: Time.current`, 1,500 (0 — placed by its own visit). Expected: `rolling_365_value_cents == 26_000`, `lifetime_value_cents == 32_500`, `rolling_365_parent_count == 2` (the paid and the refunded parents), `lifetime_parent_count == 3`. Deliberate break: `365.days.ago` → `3650.days.ago` in the new method makes the two 400-day rows count → red. Second example: a parent priced 10,000, `booked(paid_at: 10.days.ago, scheduled_at: 20.days.ago)`, then cancelled with `paid_at` intact → `rolling_365_value_cents == 10_000` while `rolling_365_parent_count == 0` (deliberate break: add `.where(Order.completed_log_sql)` to the value query → red). Third: on the existing lifetime-value fixture at 413–438, every row is in window, so `rolling_365_value_cents == 26_000 == lifetime_value_cents` (assert `eq`, not `<=`).
- **active users** — owner only → 1; owner with two roles → 1; duplicate membership row (via `insert_all`, as `accounts_rake_spec.rb:569–576`) → 1; second user with `account_member` → 2; soft-deleted membership (create then `update_columns(status_type: 2)`) → not counted; membership to a soft-deleted user → not counted; no memberships → 0; equals `account.users_count`. Deliberate break: remove `.distinct` from `Account#users_count`, confirm the two-roles and duplicate-row examples go red, restore.
- **empty state** (452–478) gains the five: counts 0, value 0, `peak_365_ended_on` nil.

`spec/requests/accounts_metrics_spec.rb`: the happy-path row seeds `rolling_365_parent_count: 7, peak_365_parent_count: 12, peak_365_ended_on: Date.new(2026, 7, 3), rolling_365_value_cents: 987_654` and asserts `rolling365ParentCount == 7`, `peak365ParentCount == 12`, `peak365EndedOn == '2026-07-03'` (the camelCase key pinned from the red run); the money-gating `before` seeds `rolling_365_value_cents: 987_654`, `money_keys` gains `rolling365ValueCents`, the owner example asserts the value and the admin/scheduler examples its absence; a new example: a factory row emits the three counts and the date as `null`; no `activeUserCount` key anywhere.

`spec/lib/tasks/accounts_rake_spec.rb`: a `run_task` helper (`AccountMetrics::RecomputeAll.call` then `task.invoke`) replaces the ~25 `task.invoke` sites; two new examples: an account created after the recompute (no metrics row) is counted on the Context line and excluded from the segment tables; an owner holding one recomputed and one un-recomputed account is still reported as sharing an owner. The existing predicate examples keep their assertions — they now prove the stored columns, which is the point.

`spec/lib/tasks/account_classification_rake_spec.rb`: one example — a completed property parent with `scheduled_at: 200.days.ago`, `completed_at: 195.days.ago`, `paid_at: 10.days.ago` → `csv_row(account)['new_rolling_365_parent_count'] == '1'` and `['new_rolling_90_parent_count'] == '0'`. Red before the calculator change (the key is absent from `compute` → `''`); deliberate break: read `compute[:rolling_90_parent_count]` → `'0'` → red.

`spec/architecture/account_classification_spec.rb`: the §5.4 invariants above on the canonical fixtures — the 365 boundary, parents only, the refund, the cancelled order (out of the count, in the value when paid), the `parent_pays` child, D2 placement, `peak >= rolling`, the closed peak window, the tie rule, `active_user_count == users_count`, "value may be positive when the count is 0", and "a never-recomputed row reads NULL, a recomputed empty account reads 0".

Every spec: red first (missing method / column), green, then the deliberate break with the red output pasted.

### Commit sequence (`git-commit-messages`; subjects final, bodies where a tier earns one)

1. `feat: add the slice 2 columns to account_metrics` — migration + `schema.rb`. Body: nullable with no default so a row that predates the first recompute reads NULL, not 0; `account_metrics` only; the first `metrics:recompute` is the backfill.
2. `feat: count qualifying parents over the trailing 365 days` — `rolling_365_parent_count_sql` + spec; the two "12 positional binds" comments corrected to 11.
3. `feat: record each account's peak 365-day shoot count and when it ended` — `peak_365_sql` + spec. Body: the backward window is the maximum of the rolling series; the end date is a real shoot date (G4); overwritten nightly, not a ratchet (G14).
4. `feat: sum billable revenue over the trailing 365 days` — `rolling_365_value_sql`, `billable_sql` date, spec.
5. `feat: store each account's active user count` — `active_user_count` via `Account#users_count` + spec. Body: one definition, the one `user_count` already ships; not the association, which is a null scope on the memo's unsaved account (G1).
6. `feat: expose the slice 2 metrics on the account metrics endpoint` — jbuilder + request spec (+ the comment fix).
7. `refactor: read joint ownership volume and users from account_metrics` — `accounts.rake`, its spec, the memo task's `new_trailing_365` removal and its spec example. Body: the two derivations §3.4 names; the read-out now cannot disagree with the dashboard; scope and the owner test unchanged so the shared-owner count still reconciles with composition.
8. `test: pin the slice 2 rules in the classification contract spec`.
9. Platform repo (write-back): `docs: amend account classification to v5 for slice 2`, `docs: update the classification codebase notes for slice 2`, `docs: add the slice 2 deploy runbook`.

### Post-deploy verification (reasoned before the code exists)

After `heroku run rake metrics:recompute -a insgtapi` (required — the columns are NULL until the first sweep; the 02:30 UTC nightly would fill them otherwise):

```bash
heroku run rails runner 'puts AccountMetric.joins(:account).where(accounts: { status_type: 1 }).where(rolling_365_parent_count: nil).count' -a insgtapi   # expect 0
```

and, from a fresh restore or via `rails runner`, the invariant set (all expected 0 violations unless stated):

| Check | Expected | Why |
| :-- | :-- | :-- |
| `rolling_365_parent_count IS NULL` on an active account | 0 rows | every active account was swept |
| `rolling_365_parent_count > peak_365_parent_count` | 0 | the trailing window is one of the windows the peak ranges over (G4); measured 0 on dev |
| `rolling_90_parent_count > rolling_365_parent_count` | 0 | same universe, same date, shorter window |
| `rolling_365_parent_count > lifetime_parent_count` | 0 | subset |
| `(peak_365_ended_on IS NULL) <> (peak_365_parent_count = 0)` | 0 | a window exists iff a shoot exists |
| `peak_365_ended_on > CURRENT_DATE` | 0 | backward windows end on a shoot date |
| `rolling_365_value_cents > lifetime_value_cents` | 0 | subset of billable rows |
| `rolling_365_value_cents > 0 AND rolling_365_parent_count = 0` | ≈ 3 on the snapshot (a legal state, G5) | brand/marketing revenue or a self-paying child, no property parent in the year |
| `SUM(rolling_365_parent_count)` over active accounts | = `Order.qualifying_parents` on active accounts with `shoot_date_sql >= 365.days.ago` (1,486 across 515 accounts on the 2026-09-10 snapshot — the production memo's row 28; re-derive on the day) | one definition, and the number Don was handed |
| `SUM(rolling_365_value_cents)` over active accounts | = the trailing-365 billable sum from the scopes (42,904,700 cents on the snapshot); `SUM(lifetime_value_cents)` = 370,187,800 unchanged | one expression |
| accounts with `active_user_count > 1` | ≈ 102 (dev 2026-09-10; Q7 said 100 on 2026-09-01) | G1 |
| accounts with `active_user_count = 0` | ≈ 5 | measured |
| `active_user_count` ≠ `Account#users_count` for any active account | 0 | same method |
| `accounts:joint_ownership` "shoots in the window across N accounts" line | equals the two sums above | the read-out now reads the columns |

The two fleet sums are expected to match the live re-derivation within the qualifying parents (or billable rows) whose shoot date falls between the sweep's cutoff and the check's cutoff — roughly four shoots a day; list them with `shoot_date_sql BETWEEN <sweep start − 365d> AND <check time − 365d>` and treat a difference equal to that count as explained. Or pin the check's cutoff to `MIN(computed_at) − INTERVAL '365 days'`.

Spot checks (values measured from the scopes on the 2026-09-10 snapshot, not from the prototype; production on deploy day will differ by the shoots completed since, so re-derive with the fleet queries before comparing):

| Account | `rolling_365_parent_count` | `peak_365_parent_count` | `peak_365_ended_on` | `rolling_365_value_cents` | `active_user_count` | `lifetime_parent_count` |
| --: | --: | --: | :-- | --: | --: | --: |
| 10288 | 55 | 81 | 2026-07-03 | 832,500 | **6** (9 membership rows) | 82 |
| 88 | 29 | 31 | 2026-06-08 | 1,168,500 | 1 | 225 |
| 1123 | 26 | 26 | 2026-08-28 | 600,000 | 4 | 153 |
| 11510 | 25 | 25 | 2026-08-14 | 702,000 | 1 | 25 |
| 1593 | 20 | 35 | 2021-08-09 | 582,000 | 2 | 164 |

Account 10288 is the G1 canary: reading 9 in production means `DISTINCT` or the users join was lost. Account 1593 is the reactivation-cohort shape §4.3 describes: an anchor five years ago, occasional now. Account 1123's peak is its current run (`peak == rolling`), the case where `>=` must not be `>`. Account 11510's peak equals its lifetime and its trailing value equals its stored `lifetime_value_cents` (702,000): every shoot is inside one year.

Nightly runtime: record it in the runbook's deploy log this time (the 1a/1b log says "not recorded"); expect the previous duration plus ~15 s.

No shift memo: no existing value moves. `metrics:recompute` writes the same values to every existing column it wrote last night; the reconciliation §3.4 asks for is the read-out's own line and the sums above, not a hand-over.

### Deploy runbook — `docs/runbooks/deploy-account-classification-2.md` (written in the write-back, in the 1a/1b shape)

- **Header:** Last updated; Repos: insgt-api; Estimated duration: ~15 min (the recapture deploy's ~20 min minus its ops step); Status: `Draft` until reviewed, `Ready` after the plan gate, `Deployed <date> by Dan` after.
- **Summary:** the five columns and the calculator; no existing number moves; no memo; ops untouched.
- **Deploy order and the window it closes:** old code on the new schema is safe (additive nullable; `AccountMetric#save!` writes known attributes only; `SELECT *` gains columns nothing reads). New code on the old schema: `Calculator#call` raises `ActiveModel::UnknownAttributeError` on every account (caught per account, logged, `Failed: 4078`) and the metrics dialog 500s (the jbuilder reads the four). The window is push → `db:migrate`, and the Procfile has no `release:` phase. Two ways to close it, chosen at the plan gate (open question 6): **(A)** the 1a/1b sequence — `heroku maintenance:on`, push, migrate, `db:migrate:status`, restart, `maintenance:off` — a couple of minutes of 503; **(B)** two pushes — commit 1 alone, migrate, then the rest — no maintenance, one more build.
- **Prerequisites:** `bundle exec rspec` green on the branch with the example count on the day; branch merged to `master` with `--no-ff`, `origin/master` pushed; no deploy in flight; open questions 1–5 answered and reflected in the diff; a baseline: `heroku run rake accounts:joint_ownership -a insgtapi` output kept (its "shoots in the window across N accounts" line is what the stored columns must reproduce).
- **Steps:** 1 back up (`pg:backups:capture`, `download`, `mv latest.dump tmp/production-latest-<date>_lock.dump`); 2 push per the chosen shape, watch the build; 3 `heroku run rake db:migrate -a insgtapi`, `heroku run rails db:migrate:status -a insgtapi` (one migration `up`), `heroku restart --app insgtapi`, maintenance off if (A); 4 `time heroku run rake metrics:recompute -a insgtapi` in the window (the recapture precedent), duration into the deploy log — if the deploy lands shortly before 02:30 UTC the nightly would do it, but the dialog would show nulls until then, so run it anyway; 5 the NULL-count command and the invariant table; 6 the spot-check table incl. the value and users columns; 7 insgt-ops: nothing to deploy — its interface ignores the new keys.
- **Rollback:** code only — `heroku rollback --app insgtapi`; the columns stay, stop being written, and hold last night's values (the dialog and the read-out keep showing them; say so). Schema — `heroku run rake db:rollback STEP=1 -a insgtapi` drops the five; `strong_migrations` does not check the down direction (`check_down` defaults to `false`, `strong_migrations-2.8.0/lib/strong_migrations.rb:41`); nothing references them once the code is rolled back.
- **Deploy log:** dated bullets with the migration timing, the recompute wall-clock, the invariant results, the spot-check comparison.

### Risks

- **G1 and G4 re-word the document.** Both are recorded above and in the open questions; if Dan keeps the literal text, the units change (plain `COUNT(*)`: a heredoc without `DISTINCT` or the users join, and `active_user_count` then disagrees with `user_count` on the same screen; forward window: `[d, d + 365 days]`, `ended_on = d + 365`) and the spot-check table's `peak_365_ended_on` column moves; nothing else in the plan does.
- **`joint_ownership` becomes nightly-fresh instead of live**, and its weighted tables drop accounts without a computed row. Acceptable for an audit read-out; stated on its Window and Context lines; the shared-owner count is unaffected (G8).
- **The dev restore's stored rows are old-definition** on the rolling-90 columns until a local `metrics:recompute`: run it locally before the verification pass or the invariant queries compare new columns to pre-1b values.
- **Timezone of `peak_365_ended_on`** (G13): a late-evening Pacific shoot dates to the next UTC day. Ordering unaffected; noted in the column comment.
- **Two extra CTE evaluations per account** (the 365 count and the peak both re-run `shoots_sql`, as the median/average/rolling-90 queries already do). Measured +3–4 ms; not worth a shared CTE that would couple the units.
- **`accounts_rake_spec` churn**: ~25 call sites change to `run_task`; each example now runs the full calculator for its handful of accounts plus `SystemMetrics::Calculator` (which works inside the transactional fixtures — it already runs unstubbed in its own spec). Runtime impact measured during the loop; if it is material, the helper recomputes only the accounts the example built.

### Write-back (part of the slice)

- **v5 amendment:** header lines 3–11 (Status, Version 5, Last updated, Supersedes, Companion files incl. the new runbook); §3.4:282 "Not yet implemented (slices 2 and 3)" → the five shipped, the four enum-side columns still slice 3; §3.4:295–301 the two derivations reconciled; §3.4's `active_user_count` sentence corrected to "the count `Account#users_count` already serves as `user_count`" with the 411 / 453-vs-102 measurement (G1); §5.1's table loses its three "(slice 2)" labels; §5.4's peak sentence re-worded to the backward window and the end-date rule with the "same maximum" argument (G4); §4.3's "never decays" qualified — the peak does not decay with time but is recomputed from history and follows history edits (G14); `peak_365_ended_on` as a UTC date (G13); §4.1/§9 worklist ordering pinned to slice 4's remaining work with G9's reasons and the sketch; §6 steps 1–2 marked done; the endpoint's field set and why `active_user_count` stays off the wire (G10); §9 status row; change log §13.
- **Codebase notes:** retire row :12's "no §3.4 column exists" and re-range `account_metrics` to 18–54; bump :11's version; shift every `db/schema.rb` row below the table by +5 (:13 `accounts.account_type`, :14 `marketing_events`, :15 `order_types`, :16 `orders`, :17 `system_metrics`); rewrite :56 (`parent_counts`, 58–74, 11 binds) and re-line :57–:65 for the four inserted methods; rewrite :76 and :77 together as the read-out's LEFT JOIN, partition and definition lines; add a row for `account_classification.rake` where the memo reads `compute[:rolling_365_parent_count]` (today :419) instead of retiring a row that was never written; re-line :87 and :113 (the joint-ownership universe examples are 711–768 today) and extend :115 with the memo example; add rows for the migration, `Account#users_count` (557–561) and `has_many :users` (116–117), `spec/factories/account_metrics.rb`, `spec/requests/accounts_metrics_spec.rb`, the jbuilder lines, the contract-spec ranges, `accounts_users` (the `lib/status_type.rb` row already exists at :94), `accounts_helper.rb:101–103`, `config/initializers/strong_migrations.rb`, the four window-function sites and `DIRECTORY_SORTS`; correct the drift found: `order.rb` scopes 176–196 (not 175–195), `account_query.rb` `where_only_once` 167–192, `accounts.rake` 454–467 / 520–522 / 555–561 / 635–638; note `system_metrics/calculator.rb:40–41, 204`'s "12 positional binds" as known-stale; add the runbook and v5 to the Repo documentation table; rewrite "Branch and deploy state".
- **Contract spec:** commit 8.
- **Runbook:** as above, with the deploy log filled in.
- **Ops follow-up** (not this slice, recorded so it is not lost): `AccountMetricSummary` gains `rolling365ParentCount?`, `peak365ParentCount?`, `peak365EndedOn?`, `rolling365ValueCents?`; render points `account-metrics.ts:150–199` (and its `hasContent` guard) / `account-info-card.ts:276–295`; three stale pre-1b comments (`account-metric-summary.model.ts:85–89, 98–103`; `account-info-card.ts:284–287`).

### Gates

"New columns, nothing reads them yet" plus the endpoint: **after plan (this STOP); after verification; at the end.** The review runs `predeploy-review-rails` with the Codex pass over the whole diff. Traps the review must not accept, beyond the skill's list: a `DEFAULT 0` on any of the five; any window predicate outside `calculator.rb` (the read-out must join, not re-derive); `peak_365_sql` reading anything but `shoots_sql`; `rolling_365_value_sql` reading `qualifying_parents` instead of `billable` (the silently-low number §5.1 warns about) or gaining a completion condition; `active_user_count` restating the association's conditions instead of calling `users_count`, or reading `@account.users` (null scope on the memo's unsaved account); a `system_metrics` column; an `activeUserCount` key on the wire; a change to `parent_counts_sql`'s bind list or to `lifetime_value_sql`; a narrowed `scoped_accounts` in the read-out; a spec whose deliberate-break red was not shown.

### Open questions for the engineer

1. **G1** — accept `Account#users_count` (distinct active users, active membership) as the definition of `active_user_count`, correcting §3.4's "plain `COUNT(*)`"? (Measured: 411 accounts differ; 453 vs 102 multi-user accounts; account 10288 reads 6, not 9.)

Accept.

2. **G4** — accept the backward window (identical maximum; `peak_365_ended_on` = the last shoot of the peak run) in place of §5.4's forward wording?

Accept.

3. **G8** — `joint_ownership` reads the stored columns (its spec recomputes before each example), rather than keeping its live derivation with a stated reason?

Remove the two hand-rolled copies, acceptable that it becomes a nightly-fresh

4. **G9** — agree the worklist sort key ships with slice 4's remaining work rather than here?

slice 2 ships the column and nothing else

5. **G12** — may the session commit on a `feat/account-classification-2` branch, or does it stop at each boundary for you to commit?

Session may commit on feature branch: feat/account-classification-2. Do NOT merge onto master.

6. **Deploy shape** — (A) maintenance window, one push, or (B) two pushes, migration first?

A - maintenance window, one push.

### Next phase, if approved

Implementation loop, one unit per the table above, starting with the migration (`migrate`, `rollback`, `migrate`, schema diff pasted), then the four calculator units red → green → deliberate break, then the endpoint, the read-outs, the contract spec; verification against a locally recomputed restore; two review rounds; write-back.
