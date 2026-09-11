# Account classification — slice 3: `lifecycle_type` / `value_type` / `peak_value_type` + the thresholds config

**Repo:** `insgt-api`. No changes elsewhere (the insgt-ops teams page reads these labels in its own release; see Out of scope 2).
**Contract:** `docs/architecture/account-classification.md` v5 — §3.0 (enum convention), §3.4 (the four remaining columns and the two indexes), §4.2 (`lifecycle_type`), §4.3 (`value_type` / `peak_value_type`), §5.1 and §5.3 (which universe and which date each input reads), §6 step 3 (derive from a single thresholds config; `lifecycle_type_at` only when the value changes).
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Status:** Phase 0 survey and Phase 1 plan complete; STOP for approval. Nothing implemented.
**Survey date:** 2026-09-11, against `insgt-api` `master` at **d98632f** (slice 2 merged; working tree clean; `heroku/master` = `origin/master` = `master` = d98632f) and the dev DB restored from the 2026-09-10 production snapshot, migrated to `20260911120000` and recomputed under slice 2 (4,078 active accounts, 4,081 metric rows, `max(computed_at)` 2026-09-11 13:33:32 UTC; 3 rows unrecomputed — the 3 soft-deleted accounts slice 2 recorded).

## Scope

1. §3.4 — four nullable columns on `account_metrics`, no defaults: `lifecycle_type`, `value_type`, `peak_value_type` (`:integer, limit: 2`) and `lifecycle_type_at` (`:datetime`).
2. §3.0 / §4.2 / §4.3 — three Rails enums on `AccountMetric`, `prefix: true`, values from 1, pinned integer-for-integer in a new `spec/models/account_metric_spec.rb`.
3. §6 step 3 — **one thresholds config object**, `AccountClassification` in `lib/account_classification.rb`, owning the §4.2 day boundaries and the §4.3 volume bands and nothing else.
4. §6 step 3 — `AccountMetrics::Calculator` derives all four in Ruby from values it already computes, plus one new SQL query for the active-run start (G1, G5).
5. Reconcile the **three** copies of these rules that already exist in the repo rather than adding a fourth: `AccountClassificationShiftMemo#lifecycle` (`lib/tasks/account_classification.rake:83–94`), `LIFECYCLE_ORDER` (`:48`), and `AccountAudit::SHOOT_VOLUME_TIERS` (`lib/tasks/accounts.rake:47–48`) — the last of which already promises in writing that it must not diverge from these columns (G2, G3).
6. `GET /accounts/:id/metrics` emits the four labels (enum names, ISO timestamp), top-level, outside the owner-only money block (G7).
7. Contract-spec additions for §4.2 and §4.3; factory left without defaults; codebase notes; a v6 amendment; a deploy runbook.
8. The §3.4 indexes — **see G6 and G15**; the recommendation is one index, in its own migration.

## Out of scope — do not touch

1. Any Pipedrive code, including the §6 `value_type` push debounce and the whitelist (slice 7).
2. The accounts-index filters (`lifecycle_type=`, `value_type=`) and the insgt-ops teams page. Slice 2's G9 settled the precedent: the query plumbing ships with the consumer that calls it, not with the column. The sketch is recorded under Write-back.
3. Slice 4's `account_type` backfill, the organization type audit, and the worklist sort key.
4. D6, §5.5 Origin, slice 6.
5. `system_metrics` — no fleet mirror of the four (G10), consistent with slice 2's G6.
6. `ChurnReport`'s own trailing-365 roster (`lib/churn_report.rb:57,177–184`) — a different question, its own definition, left alone.
7. Every existing `account_metrics` column's computation, `parent_counts_sql`'s bind list, `shoot_dates_sql`, `MARGIN_LTV_*`, `SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS`, `OrderQuery`.
8. §4.2's prospect-outreach mitigation (`exclude account_type IN (internal, other)`) — a rule for whoever defines a segment, not a column.
9. The insgt-ops `AccountMetricSummary` interface and render components — the ops follow-up, listed under Write-back.

---

## Phase 0 — survey

### Done

Read the contract sections; the codebase notes (re-verified against d98632f — the slice 2 rows hold); the slice 2 plan and its fourteen gaps; `AccountMetrics::Calculator` end to end; `RecomputeAll`, `metrics:recompute` and its spec; every metrics migration, all three concurrent-index migrations, `strong_migrations.rb` and the installed gem's `add_index` check; the jbuilder and its controller; the three rake artifacts that already carry these rules; the enum declarations, `ApplicationRecord`, and the pinning specs; `lib/status_type.rb` and `config/application.rb`'s autoload configuration; the contract spec's slice 2 block and its hand-off comment to slice 3. Measured the whole population under §4.2 and §4.3 on the dev restore, cross-checked it against the shipped memo implementation, and prototyped the active-run query fleet-wide and per account.

### Prerequisites — all landed (facts)

| Prerequisite | Evidence |
| :-- | :-- |
| Slice 2's five numeric columns in production | `db/schema.rb:13` version `2026_09_11_120000`; `db/schema.rb:48–52`; §9, "Deployed 2026-09-11 … recompute 2 min 36.89 s over 4,078 accounts, 0 failed" |
| The inputs the labels read are populated | dev restore: 0 active accounts with `rolling_365_parent_count IS NULL`; 0 active accounts with no metric row; `max(computed_at)` 2026-09-11 13:33:32 UTC |
| §5.1 scopes and §5.3 date | `app/models/order.rb:176–196`; `Order.shoot_date_sql` 220–228; `Order.qualifying.select(…).to_sql` carries no `?` (re-verified in the prototype) |
| Calculator shape slice 3 extends | `calculator.rb:22–27` (`find_or_initialize_by` → `assign_attributes(compute)` → `save!`), `:29–35` (`compute`), `:39–56` (`computed_values`, fourteen merges) |
| A Ruby-derived, NULL-on-zero precedent exists | `calculator.rb:10–12` ("Rates are derived in Ruby so the denominator-zero case can store NULL (not 0.0000), which preserves the distinction between 'no orders yet' and '0% reshoot rate'"), implemented at `:201–214` (`rate` returns `nil` on a zero denominator) |
| `lib/` is autoloaded and eager-loaded | `config/application.rb:17` `config.autoload_lib(ignore: %w[assets tasks])`, `:20`, `:21`; `lib/status_type.rb` is the shared value-object precedent, called as `StatusType.active` from model scopes |
| Concurrent-index precedents (three) | `db/migrate/20260818120000_add_directory_indexes_to_users_and_accounts_users.rb`, `20260727120000_add_address_components_index_to_properties.rb`, `20260828120002_add_key_index_to_order_types.rb` — each `disable_ddl_transaction!`, index-name constants, explicit `up`/`down`, leading `remove_index … algorithm: :concurrently, if_exists: true`, then `add_index … algorithm: :concurrently, if_not_exists: true` |
| strong_migrations is in force for a new migration | `config/initializers/strong_migrations.rb:7` `start_after = 20260806120000`, `:18` `target_version = 15`, `:32` `auto_analyze = true`, `safe_by_default` left off (`:44–51`); gem 2.8.0 (`Gemfile.lock:533`) |
| Enum + pinning precedent | `app/models/account.rb:90`, `app/models/order_type.rb:87`, pinned value-by-value at `spec/models/account_spec.rb:17–29` |
| The contract spec already hands §4.3's zero rule to this slice | `spec/architecture/account_classification_spec.rb:405–407`, verbatim: "§4.3's zero rule belongs to the tier columns in slice 3. On these five, 0 is a real zero and NULL means 'not computed since slice 2 shipped'" |

### What this slice touches

| File | Lines | What it is today | Slice 3 change |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 18–53 | `account_metrics`; slice 2's five columns at 48–52; **one unique index, on `account_id` (53)** | +4 columns; +1 index (G6); rows below shift |
| `db/migrate/20260911120000_…slice_2_columns…` | 1–67 | The header voice to copy (what each column is, what NULL means, why no mirror, why no backfill). Uses `def change` and **no `limit: 2`** — its columns are not enum-backed. `:53–54` says "§3.4's two indexes are on slice 3's enum columns and land with them" | voice copied; style not (G15) |
| `db/migrate/20260904120004_add_account_type_to_accounts.rb` | 11–12, 32–41 | The nullable enum-backed column precedent: "`:integer, limit: 2` (smallint), matching status_type on this table and category_type on order_types", and "Explicit up/down rather than `change` to keep the reversal spelled out, matching the surrounding migrations" | the column migration's shape (G15) |
| `db/migrate/20260727120000_…`, `20260828120002_…`, `20260818120000_…` | — | The three concurrent-index migrations; `20260727120000:22–25` states why `if_not_exists` alone is worse than nothing; `20260828120002:25–27` states why `change` must not be used for a concurrent index | the index migration's shape (G15) |
| `config/initializers/strong_migrations.rb` | 7, 18, 32, 44–51 | `start_after`, `target_version = 15`, `auto_analyze = true`, `safe_by_default` off | a non-concurrent `add_index` raises (G15) |
| `app/models/application_record.rb` | 4, 18–20 | **`scope :active`** and **`def active?`**, inherited by every model | why `prefix: true` is load-bearing (G9) |
| `app/models/account_metric.rb` | 1–11 | `belongs_to :account`; no enum, no validations, deliberately no CrudAttribution | +3 enums, +1 shared `VALUE_TYPES` constant |
| `app/services/account_metrics/calculator.rb` | 10–12 | "All aggregation is in SQL … Rates are derived in Ruby so the denominator-zero case can store NULL" | covers the new derivation as written |
| same | 22–27, 29–32 | `#call` loads the row, assigns, saves. `#compute`'s comment, verbatim: "The computed attributes, unsaved. The slice 1b shift memo … reads this to compare the live definition against the stored row **without touching it**" | unchanged — G1 keeps both true |
| same | 39–56 | `computed_values`; the inputs the labels read are merged at 42 (`rolling_365_parent_count`), 43 (`peak_365_window`) and 51 (`shoot_dates`) | +1 merge, after 54 |
| same | 84–87, 103–109 | the two counts, each coerced to a real `0`, never nil | the tier derivation must map 0 → NULL, not → `single` (G4) |
| same | 93–99 | verbatim: "`max(stored, computed)` … would be the first column here to read its own previous value" | the comment G1 preserves |
| same | 166–180 | `shoot_dates` over `visits_sql` (`Order.qualifying`, parents **and** children), assigned raw as `Time` | the lifecycle inputs; method unchanged |
| same | 201–214 | `derived_rates(counts)` / `rate` | the shape `classification` copies |
| same | 261–267 | `#exec`, and its empty-binds gotcha | reused |
| same | 285–292 | `visits_sql`; comment says "Feeds the date range only" | second consumer; comment corrected |
| same | 382–404 | `peak_365_window_sql` — the window-function shape to copy. **Reads `shoots_sql` (parents)** | pattern; the run query must read `visits_sql` (G5) |
| `app/services/account_metrics/recompute_all.rb` | 40–63 | `find_each` → `Calculator.call`, `rescue StandardError` per account, no transaction, no re-raise | untouched; see Risks |
| `spec/services/account_metrics/recompute_all_spec.rb` | 12, 26, 41, 55 | stubs `AccountMetrics::Calculator` entirely | cannot catch a slice 3 regression; see Risks |
| `lib/account_classification.rb` | — | **Does not exist** | new: the thresholds config (G3) |
| `lib/tasks/account_classification.rake` | 27–30 | verbatim: "Still not a stored read: `compute()` runs the query, it does not look at the row" | the second comment G1 keeps true |
| same | 48 | `LIFECYCLE_ORDER = %w[prospect new active cooling at_risk lapsed].freeze` | reads the enum/config (G3) |
| same | 83–94 | **A complete §4.2 implementation, shipped in slice 1b** | delegates to the config; behaviour identical (G2) |
| same | 383, 412–413 | `Calculator.new(Account.new(id:)).compute` on an **unsaved** account; the two `lifecycle` call sites | unchanged — and the reason `#compute` must stay pure (G1) |
| `lib/tasks/accounts.rake` | 38–48 | `SHOOT_VOLUME_TIERS`, whose comment says verbatim: "Same names deliberately: when those columns land, the joint-ownership read-out and the stored tier must not describe different bands", and "'no shoots' is this task's row, not a tier — the design stores NULL rather than a tier for a zero count" | the four bands come from the config; the zero row stays local (G3, G4) |
| same | 669–683 | the only consumer, `tier_range.cover?(account[:shoots])` | untouched |
| `spec/lib/tasks/accounts_rake_spec.rb` | 592–594, 804–806 | **the tier labels are a test contract**: `Regexp.escape(label)` over the constant, and three literal assertions on `'single (1)'`, `'anchor (12+)'` and `'no shoots'` | unchanged — which is what constrains G3's reconciliation |
| `app/views/accounts_metrics/show.json.jbuilder` | 67–85 | slice 2's block, which already says these counts are "the inputs the slice 3 labels read, so a label stays explainable without re-running anything" | +4 fields (G7) |
| `spec/factories/account_metrics.rb` | 1–13 | defaults for the NOT NULL columns only | none for the four (G11) |
| `spec/models/account_metric_spec.rb` | — | **Does not exist** | new: the three enum pins |
| `spec/services/account_metrics/calculator_spec.rb` | 414–830 | slice 2's contexts; the empty-state example lists every column | +3 contexts; empty state gains four |
| `spec/architecture/account_classification_spec.rb` | 293–421, 423–431 | slice 2's block with its `metric` helper (299–302); the `SQL composition` guard last | +§4.2 / §4.3, before the guard |
| `spec/requests/accounts_metrics_spec.rb` | 101–290 | the shape example, the never-recomputed example, the money gating | +4 keys, +the null case |

### Collisions (grep, output pasted)

```
$ grep -rn "lifecycle_type\|peak_value_type\|value_type\|VALUE_TIERS\|Thresholds" app lib spec db config --include=*.rb --include=*.rake
lib/tasks/accounts.rake:38-41   (the SHOOT_VOLUME_TIERS comment naming the enum)
(no column, constant, method or scope)

$ grep -rn "AccountClassification\b" app lib spec --include=*.rb --include=*.rake
(empty — only AccountClassificationShiftMemo at account_classification.rake:35,359
 and spec/lib/tasks/account_classification_rake_spec.rb:140)

$ grep -rn ":smallint" db/migrate db/schema.rb
(empty — every smallint in this repo is `:integer, limit: 2`)

$ grep -rn "lifecycle" app lib --include=*.rb --include=*.rake
lib/tasks/account_classification.rake:48,83,412,413,453,454,556,557,561
```

Three name hazards, all real:

- **`active: 3`** would, unprefixed, redefine `ApplicationRecord`'s inherited `scope :active` (`application_record.rb:4`) and `def active?` (`:18–20`) on `AccountMetric`.
- **`new: 2`** would, unprefixed, generate the class-level scope `AccountMetric.new`, shadowing `Class#new`.
- With the prefix, the predicate for `at_risk` is **`lifecycle_type_at_risk?`**, one underscore away from the reader for the new **column** `lifecycle_type_at`. Both names are used in this slice; the specs and the review must name each explicitly.

`prefix: true` is therefore required here, not decorative — on top of §3.0 mandating it and both shipped enums using it.

### Measurements (dev DB, 2026-09-10 production snapshot recomputed under slice 2, read-only)

| Question | Result |
| :-- | :-- |
| Active accounts / metric rows / unrecomputed | 4,078 / 4,081 / 3 |
| **`lifecycle_type` distribution** under the shipped memo rule | `prospect` 2,004 · `new` 61 · `active` 152 · `cooling` 138 · `at_risk` 166 · `lapsed` 1,557 |
| The same under a continuous-interval reading | identical but `at_risk` 164 / `lapsed` 1,559 — **2 accounts differ** (2394, 3661; both 365.8 days out). The floor rule says `at_risk`. See G2 |
| **`value_type`** from `rolling_365_parent_count` | NULL (count 0) 3,563 · `single` 277 · `occasional` 178 · `core` 41 · `anchor` 19 |
| **`peak_value_type`** from `peak_365_parent_count` | NULL (count 0) 2,004 · `single` 1,071 · `occasional` 701 · `core` 191 · `anchor` 111 |
| Is `new` a subset of `active`? | **Yes, structurally and in fact.** `most_recent_shoot_at >= first_shoot_at` always, so a first shoot within 90 days implies a visit within 90 days. Accounts with `first_shoot_at` inside 90 days and no visit inside 90 days: **0**. The precedence rule is a pure override, never a tie-break |
| Integrity of the inputs | 0 rows with `first_shoot_at IS NULL AND most_recent_shoot_at IS NOT NULL`; 0 with `most_recent_shoot_at < first_shoot_at`; 0 prospects with `rolling_365_parent_count > 0`; 0 prospects with `peak_365_parent_count > 0`; 0 accounts with a visit and `peak_365_parent_count = 0` |
| `lifecycle` × `value_type` cross-tab | `lapsed` (1,559) and `prospect` (2,004) are **entirely** NULL-tier; every non-NULL tier sits in `new`, `active`, `cooling` or `at_risk`. `lapsed ⇒ value_type IS NULL` is structural: no visit in 365 days ⇒ no qualifying parent in 365 days |
| Orthogonality is real | account 1842 is `cooling` with `value_type: anchor` (12 trailing shoots, last visit 122 days ago); account 2687 is `at_risk` with `core` |
| Reactivation cohort (§4.3: `lapsed` + `peak_value_type: anchor`) | **42 accounts**; by `peak_365_ended_on DESC` the head is 2912 (peak 15, ended 2024-10-24), then 2103, 3035, 2426, 2476 |
| Boundary population | within ±3 days of the 90-day boundary: 12 · of 180: 14 · of 365: 5. Exactly 90.0 days: 0 · exactly 180.0: 0 · in [365, 366): 2 |
| Daily churn with no new shoots | 2 accounts change label tomorrow; 29 within seven days |
| Band-edge population for `value_type` (flap exposure, §4.3) | count 1: 277 · 2: 79 · 5: 26 · 6: 14 · 11: 3 · 12: 4 |
| Prospects carrying trailing-365 revenue (§4.2's review flag) | 2 — accounts 3068 ($350.00) and 11232 ($330.00), both `lifetime_parent_count` 0, `account_type` unset |
| **How long each degrading label has actually held** (derived from history) | `cooling` median 41 days (max 90) · `at_risk` median 73 (max 185) · **`lapsed` median 1,655 days, max 3,666** |
| Active-run prototype, fleet-wide | 2,074 accounts scanned in 57.3 ms; of the 152 `active` accounts, **142** have a prior gap longer than 90 days (their run starts after their first shoot) and 10 do not |
| Derived "active since" vs "since last shoot" | median 85 days vs 34 — the run start carries information the last shoot does not |
| Per-account cost of the run query | ~1.4 ms (mean over 50 active accounts), against the peak query's 2.35 ms worst case in slice 2 |
| `account_metrics` size | 4,081 rows, 776 kB heap, 224 kB of indexes |

Spot-check accounts, one per label, computed from the rules on this restore (`now` = 2026-09-11 14:20 UTC):

| Account | lifecycle | `lifecycle_type_at` (derived) | held | `value_type` | `peak_value_type` | inputs |
| --: | :-- | :-- | --: | :-- | :-- | :-- |
| 3 | `prospect` | nil | — | NULL | NULL | no visit ever |
| 11364 | `new` | 2026-07-06 22:00 | 66 d | `occasional` | `occasional` | first 2026-07-06, last 2026-08-16, r365 2 |
| 10288 | `active` | 2025-09-10 18:30 | 365 d | `anchor` | `anchor` | first 2025-06-12 (= run start), last 2026-07-03, r365 54, peak 81 |
| 1842 | `cooling` | 2026-08-09 16:00 | 32 d | `anchor` | `anchor` | last 2026-05-11 (122 d), r365 12, peak 38 |
| 2687 | `at_risk` | 2026-07-29 21:45 | 43 d | `core` | `anchor` | last 2026-01-30 (223 d), r365 7, peak 44 |
| 58 | `lapsed` | 2026-06-02 15:00 | 100 d | NULL | `anchor` | last 2025-06-02 (465 d), peak 57 ended 2021-04-24 |

Account 10288's stamp is the `new → active` handover (`first_shoot_at + 90 days`), because its current run reaches back to its first shoot. Account 58 is the reactivation-cohort shape and slice 2's worst-case peak account.

### Where the document and the code disagree (quoted both ways; resolved in the gaps)

1. **`lifecycle_type_at`.** §6 step 3: "Update `lifecycle_type_at` only when the value actually changes" — a write rule against the stored row. Three shipped comments say the calculator does not work that way: `calculator.rb:29–32` ("reads this to compare the live definition against the stored row **without touching it**"), `account_classification.rake:27–30` ("Still not a stored read: `compute()` runs the query, it does not look at the row"), and `calculator.rb:93–99` ("would be the first column here to read its own previous value"). Measured cost of the literal reading: on day one all 4,078 rows are stamped with the deploy date, including 1,557 `lapsed` accounts whose true median hold is **1,655 days**. → **G1**.
2. **The §4.2 arithmetic.** The document's table is in whole days and does not say how a partial day rounds. The repo already answers it at `account_classification.rake:85–91` (floor). Two accounts read differently under a continuous interval today. → **G2**.
3. **The document's index snippet raises.** §3.4:280–281 is `add_index :account_metrics, [:lifecycle_type, :value_type]` with no `algorithm:`. `strong_migrations-2.8.0/lib/strong_migrations/checks.rb:153` raises on any non-concurrent `add_index` against an existing table, **regardless of row count**, and `safe_by_default` is off. Copied literally, `rake db:migrate` fails in dev. → **G15**.
4. **Two indexes.** §3.4 asks for `[:lifecycle_type, :value_type]` **and** `[:account_id, :lifecycle_type]`, but `db/schema.rb:53` already carries a **unique** index on `account_id`, so the second can never beat a single-row lookup that already exists. The table is 4,081 rows / 776 kB. → **G6**.
5. **"Thresholds live in one Ruby config object"** (§6), but three copies of these rules already exist (`account_classification.rake:48`, `:83–94`, `accounts.rake:47–48`) — one of which promises in writing not to diverge from the columns this slice adds. → **G3**.
6. **Migration style.** Slice 2's migration uses `def change` (`20260911120000:60`); `20260904120004:32–33` — the nullable-enum-column precedent — says "Explicit up/down rather than `change` to keep the reversal spelled out, matching the surrounding migrations." → **G15**.
7. **§3.4's heading is stale**: "add nine columns", with all nine in one code block, five of which shipped in slice 2. Disambiguated two lines below, but the heading reads as one unshipped unit. → Write-back.
8. **`value_type` "can flap … debounce at the Pipedrive push boundary, not in the database"** (§4.3). Nothing in slice 3 debounces; the push is slice 7. Recorded so the review does not read the absence as an omission.

### Unverified

- Production runtime of `metrics:recompute` after this slice. The baseline is the contract's own 2 min 36.89 s over 4,078 accounts (2026-09-11); the estimate below is dev-hardware arithmetic on top of it.
- Whether Rails 7.2 accepts two `enum` declarations sharing one values hash on one model when both carry `prefix: true`. Expected to work (generated methods differ by prefix); proven or disproven in commit 2's first red/green cycle. No other model in this repo declares two enums over one vocabulary.
- Whether the concurrent index build on 4,081 rows registers at all in the deploy log; `auto_analyze = true` adds an `ANALYZE account_metrics` after it (`strong_migrations.rb:32`, gem `checker.rb:118–120`).
- The two accounts at the 365-day boundary (2394, 3661) were read once and cross into `lapsed` under either rule within a day; they will not be the same accounts on deploy day.
- insgt-ops was not surveyed for this slice beyond slice 2's recorded note that every `AccountMetricSummary` field is optional. The ops follow-up is listed, not planned.

---

## Phase 1 — plan

### Gaps pinned

**G1 — `lifecycle_type_at` is derived from history, not stamped when the nightly notices a change.** The calculator computes the instant the current label began, as a pure function of `first_shoot_at`, `most_recent_shoot_at` and the account's visit series:

| Label | `lifecycle_type_at` |
| :-- | :-- |
| `prospect` | `nil` — the label has no start event (G13) |
| `new` | `first_shoot_at` |
| `active` | `max(current_run_started_at, first_shoot_at + 90.days)` — the start of the current run of visits with no gap longer than 90 days, or the moment the account stopped being `new`, whichever is later (G5) |
| `cooling` | `most_recent_shoot_at + 91.days` |
| `at_risk` | `most_recent_shoot_at + 181.days` |
| `lapsed` | `most_recent_shoot_at + 366.days` |

The three degrading stamps are the exact instants the floor-to-days rule (G2) crosses each boundary, so a label and its timestamp come from one set of numbers and cannot disagree.

This **satisfies §6 step 3 rather than contradicting it**: a derived stamp moves exactly when the label moves and is otherwise stable. While an account stays `active`, a further shoot inside the 90-day gap leaves the run start untouched; a shoot after a longer gap begins a new run, which is also the moment the label returned to `active`. While it stays `cooling`, `most_recent_shoot_at` is unchanged by definition. What the derivation removes is the *mechanism*, not the guarantee.

Why not the literal reading (compare to the stored row in `#call`, stamp `Time.current` on a difference):

- It is wrong on day one for every row and stays wrong for as long as the label holds. 1,557 accounts would read "lapsed since 2026-09-12" against a measured median true hold of 1,655 days and a maximum of 3,666. §3.4 says the column "answers 'how long have they been At Risk'"; the literal rule cannot answer it until the label next changes.
- It makes `lifecycle_type_at` the first column here to read its own previous value — which `calculator.rb:93–99` rejects in writing for `peak_365_parent_count`, and which slice 2 pinned as G14. That comment would have to be amended to stay true.
- It is not reproducible on the memo path: `account_classification.rake:383` builds the calculator on an unsaved `Account.new(id:)` for "the live definition, never saved", and `:27–30` promises "`compute()` … does not look at the row". A stored comparison either moves into `#call` (so `#compute` returns no stamp at all, and the memo's live definition is incomplete) or falsifies both comments.
- A code rollback with the columns left in place, or any re-run after a restore, fabricates a change on the next sweep.

Rejected alternatives: (a) the literal rule with a one-time derived backfill — two definitions for one column, and the backfill is this derivation anyway; (b) `most_recent_shoot_at` as the `active` stamp — it re-stamps on every shoot, exactly the false "change" a debounce exists to suppress. **Open question 1: this re-words §6 step 3.**

**G2 — the §4.2 arithmetic is the one already shipped in this repo.** Verbatim from `lib/tasks/account_classification.rake:83–94`, unchanged by this slice:

```ruby
return 'prospect' if most_recent_shoot_at.nil?
return 'new' if first_shoot_at && (now - first_shoot_at) <= 90.days

days = ((now - most_recent_shoot_at) / 1.day).floor
if days <= 90 then 'active' elsif days <= 180 then 'cooling' elsif days <= 365 then 'at_risk' else 'lapsed' end
```

Floored whole days for the three degrading boundaries; a continuous comparison for `new`. This is the reading §4.2's table is written in ("91–180", "181–365", "> 365"), and it is what slice 1b's memo already told Don. Measured: it differs from a continuous interval for **2 of 4,078 accounts** (2394, 3661 — `at_risk` under the floor rule) and for **0 accounts** on the `new` boundary. The arithmetic runs on `Time`, not `Date`: `first_shoot_at` and `most_recent_shoot_at` are raw UTC `Time`s (`calculator.rb:171–178`). The `new`/degrading asymmetry is inherited, not introduced; the config's comment says so, so nobody "fixes" it into a behaviour change. Alternative rejected: unifying `new` onto floored days — it changes shipped behaviour for no measurable gain.

**G3 — the thresholds config is `AccountClassification`, in `lib/account_classification.rb`.** One module: frozen constants and three pure lookups, no database, no model.

```ruby
module AccountClassification
  NEW_WINDOW       = 90.days     # `new` takes precedence over `active` (§4.2)
  ACTIVE_MAX_DAYS  = 90
  COOLING_MAX_DAYS = 180
  AT_RISK_MAX_DAYS = 365
  LIFECYCLE_ORDER  = %i[prospect new active cooling at_risk lapsed].freeze
  VALUE_BANDS = [[:single, (1..1)], [:occasional, (2..5)], [:core, (6..11)], [:anchor, (12..Float::INFINITY)]].freeze

  def self.lifecycle(first_shoot_at:, most_recent_shoot_at:, now:)                       # → Symbol
  def self.lifecycle_started_at(lifecycle:, first_shoot_at:, most_recent_shoot_at:, run_started_at:)  # → Time | nil
  def self.value_tier(count)                                                             # → Symbol | nil (nil when 0 or nil)
end
```

Home: `lib/` is autoloaded and eager-loaded (`config/application.rb:17,20,21`) and already holds `lib/status_type.rb`, a value object called from model scopes — the same role. The **direction of the dependency is forced**, not chosen: `config.autoload_lib(ignore: %w[assets tasks])` means `lib/tasks/*.rake` is not autoloaded, so `app/services` cannot reference anything defined in a `.rake` file. The shared rule has to move out of `account_classification.rake` into `lib/`, and the rake tasks read it — never the reverse. **There is no thresholds-object precedent to copy**: the nearest constants (`lib/churn_report.rb:53`, `app/services/property_facts_service.rb:53`) are bare constants on their consuming class, which is exactly what fails here — this vocabulary has four consumers (the calculator, two rake read-outs, and slice 7's push). Name: `AccountClassification` matches the document and the rake namespace, is free (grep above), and is not tied to `account_metrics`. `VALUE_BANDS` is `[name, Range]` pairs because that is the shape `AccountAudit::SHOOT_VOLUME_TIERS` already consumes (`accounts.rake:669–683`, `tier_range.cover?`). The **enum integers do not live here** — §3.0 puts them on the model; the config returns names, the enum maps names to integers, and the contract spec pins the two against each other.

The three existing copies are reconciled, not left. That constant's own comment is the instruction: "when those columns land, the joint-ownership read-out and the stored tier must not describe different bands."

- `account_classification.rake:83–94` becomes a delegation. The config returns **Symbols**; the memo's public output is strings (its CSV columns and `LIFECYCLE_ORDER = %w[…]` at `:48`), so the delegation is `AccountClassification.lifecycle(…).to_s` and `LIFECYCLE_ORDER` becomes `AccountClassification::LIFECYCLE_ORDER.map(&:to_s)`. The memo's committed CSV format does not change.
- `SHOOT_VOLUME_TIERS` takes its four non-zero **ranges** from `VALUE_BANDS` and keeps its **display labels** exactly as they are (`'single (1)'`, `'occasional (2-5)'`, `'core (6-11)'`, `'anchor (12+)'`, plus the leading `['no shoots', (0..0)]` row). The labels are a test contract — `spec/lib/tasks/accounts_rake_spec.rb:592–594` escapes them out of the constant and `:804–806` asserts three of them literally — and they are not enum names, so generating them from the config would break three examples to no end. One copy of the bands, in the config; one copy of the human labels, in the read-out that prints them.

**G4 — NULL on a tier column is a value; NULL on `lifecycle_type` is not.** `value_type` and `peak_value_type` are `nil` when their count is 0 (§4.3, and `accounts.rake:43–46`: "'no shoots' is this task's row, not a tier — the design stores NULL rather than a tier for a zero count"), which is the `rate` precedent at `calculator.rb:210–214`. The trap is that both counts are coerced to a real `0` upstream (`calculator.rb:86,106`), so a naive band lookup maps 0 into `single`; `value_tier` returns nil for 0 and for nil, and the spec pins both. `lifecycle_type`, by contrast, is never nil from the calculator — `prospect` is the no-shoot label — so NULL there means only "not computed since slice 3 shipped", the deploy-window state slice 2's G2 defined. **The four columns carry two NULL conventions deliberately**, and the migration header says so. Measured after a sweep: 3,563 rows `value_type IS NULL`, 2,004 `peak_value_type IS NULL`, 0 `lifecycle_type IS NULL`.

**G5 — the active-run start is one window query over `visits_sql`, not `shoots_sql`.** New `lifecycle_run` / `lifecycle_run_sql`, in the shape of `peak_365_window_sql` (`calculator.rb:382–404`): a window function nested in a subquery and filtered outside — `LAG` over the visit dates marks a run start wherever the gap exceeds the config's window, a running `max` carries it forward, and the last row's carried value is returned. The universe is **`visits_sql` — `Order.qualifying`, parents and children** — because lifecycle reads `first_shoot_at` and `most_recent_shoot_at`, which `shoot_dates` computes from that same CTE (`calculator.rb:166–180, 285–292`). Reading `shoots_sql` would give an account whose recent visits are child orders a run start that contradicts its own `most_recent_shoot_at`. The gap threshold comes from the config, not a literal. Measured: 1.4 ms per account; 57.3 ms for all 2,074 accounts with visits in one pass. It runs unconditionally like every other query in the class — no `if label == :active` branch, which would make the sweep's cost depend on the data and the method harder to test. `visits_sql`'s "Feeds the date range only" comment is corrected to name both consumers. Alternative rejected: adding a third output column to `shoot_dates_sql` — it would work, and slice 2 set the precedent by adding a date to `billable_sql`, but a separate query leaves a shipped query's SQL text untouched, which is what the trap list asks for.

**G6 — one index, not two.** Ship `%i[lifecycle_type value_type]`; do **not** ship `[:account_id, :lifecycle_type]`. `db/schema.rb:53` already carries `index_account_metrics_on_account_id UNIQUE`: at most one row per account, so the composite cannot improve any lookup. The kept index serves the one access path that is not a primary-key lookup — the teams-page segment filter `WHERE lifecycle_type = ? AND value_type = ?` — and even that runs over 4,081 rows in a 776 kB table, so it is precautionary, in the spirit of `20260818120000`'s own "this is precautionary; it is here so the default page load does not degrade as the table grows". **Open question 2: §3.4 asks for both.** If Dan wants both, it is one more `remove_index`/`add_index` pair in the same migration and nothing else moves.

**G7 — the endpoint emits all four, top-level.** `lifecycleType`, `valueType`, `peakValueType` as **enum names** (§3.1: "The enum name crosses the wire, not the integer") and `lifecycleTypeAt` as `iso8601`, outside the `system_owner` guard beside the slice 2 counts — the jbuilder's own comment (`show.json.jbuilder:67–78`) already states the reason: the counts are there "so a label stays explainable without re-running anything." A label with its inputs and its start beside it is the whole of that promise. Keys camelise automatically and are pinned from the red run. Nulls land safely: every `AccountMetricSummary` field in insgt-ops is optional.

**G8 — no index filters, no ops work in this slice.** Slice 2's G9 settled it: the accounts index emits no `ORDER BY` and copies no sort key, and its filter plumbing ships with the consumer that calls it. A `lifecycle_type=` / `value_type=` filter needs a `LEFT JOIN account_metrics` in `AccountQuery`, checks against `ApiSearch#query`'s unconditional `.distinct` and `where_only_once`'s `GROUP BY`, and an ops control to drive it — one reviewable unit, with slice 4's worklist sort. Sketch recorded under Write-back.

**G9 — three enums on `AccountMetric`, `prefix: true`, one shared vocabulary constant.**

```ruby
VALUE_TYPES = { single: 1, occasional: 2, core: 3, anchor: 4 }.freeze
enum :lifecycle_type, { prospect: 1, new: 2, active: 3, cooling: 4, at_risk: 5, lapsed: 6 }, prefix: true
enum :value_type, VALUE_TYPES, prefix: true
enum :peak_value_type, VALUE_TYPES, prefix: true
```

`prefix: true` is load-bearing three times over (see Collisions): `active` would redefine `ApplicationRecord`'s inherited `scope :active` and `active?`, `new` would shadow `AccountMetric.new`, and two columns share one vocabulary. The pin spec asserts the three integer maps and the **absence** of the unprefixed names, as `spec/models/account_spec.rb:17–29` does for `account_type`, and asserts that `AccountMetric` still answers `active?` from `ApplicationRecord` and that `AccountMetric.new` still builds a record.

**G10 — no `system_metrics` mirror.** Slice 2's G6 reasoning and evidence: `system_metrics/calculator.rb:3–12` forbids deriving fleet figures from account rows, and a fleet "lifecycle" is not a thing. A fleet segment count is a `GROUP BY` over 4,081 rows whenever anyone wants one.

**G11 — factories take no defaults for the four**, per `insgt-api/CLAUDE.md` §Testing's "a nullable column whose NULL means something" recipe, which slice 2 followed. A factory row therefore exercises the never-recomputed state, and the request spec asserts it emits the four as `null`.

**G12 — commits.** The standing instruction (never commit; Dan reviews and commits) and the skill's loop disagree, as in slice 2, whose answer was "the session may commit on `feat/account-classification-2`, do NOT merge onto master." **Open question 5** asks whether the same holds for `feat/account-classification-3`.

**G13 — `prospect` carries no timestamp.** `lifecycle_type_at` is NULL for every `prospect`, giving a checkable invariant: `lifecycle_type_at IS NULL` exactly when `lifecycle_type IS NULL` (never computed) or `lifecycle_type = prospect`. The alternative — `accounts.created_at` — is exact and free, and was rejected because it would put a second name on a column that already exists, the failure the `last_shoot_at` rule in §3.4 exists to prevent. A consumer that wants "prospect since" joins `accounts`.

**G14 — no shift memo; no existing number moves.** All four columns are new and nothing reads them yet. The one visible read-out that changes is `accounts:joint_ownership`'s tier table, and only in where its bands come from: the four non-zero rows of `SHOOT_VOLUME_TIERS` become `AccountClassification::VALUE_BANDS`, whose ranges are identical (1..1, 2..5, 6..11, 12..∞ — compared line by line above), so every printed number is unchanged. The verification proves it by diffing the read-out before and after, and the rake spec's pinned tier output (`accounts_rake_spec.rb:804–806`) passing unchanged is the same evidence.

**G15 — migration shape: two migrations, explicit `up`/`down`, `limit: 2`, concurrent in both directions.**

- **Two files.** `20260912120000` adds the four columns; `20260912120001` adds the index. A concurrent index needs `disable_ddl_transaction!`, and all three of the repo's index migrations contain index statements and nothing else; the worked precedent for "new column, then index on it" is the deliberate split at `20260828120000` → `20260828120002`. Combined, the four `add_column`s would run outside a transaction and a failure on the `CREATE INDEX CONCURRENTLY` would leave columns added and `schema_migrations` unmarked. (Slice 2's header said the indexes "land with" slice 3's columns — that is about the slice, not the file.)
- **`:integer, limit: 2`** for the three enum columns — `:smallint` appears nowhere in this repo (grep above); `20260904120004:11–12` states the rule. `lifecycle_type_at` is `:datetime`, like every other temporal column on this table.
- **Explicit `up`/`down`, not `change`**, in both migrations: `20260904120004:32–33` states the convention for the column migration, and for the index migration `change` is actively wrong — `20260828120002:25–27` explains that it "would auto-reverse into a NON-concurrent `remove_index`, taking exactly the ACCESS EXCLUSIVE lock the forward migration goes out of its way to avoid." Slice 2's `def change` is the divergence here, not the rule.
- **`algorithm: :concurrently` in `down` too**, spelled by hand. `StrongMigrations.check_down` is `false` (gem `lib/strong_migrations.rb:41`; the initializer never sets it), and `checker.rb:216` short-circuits the whole check in the down direction — nothing will warn, and a plain `remove_index` takes an ACCESS EXCLUSIVE lock on rollback.
- **Leading `remove_index … if_exists: true`** before each `add_index … if_not_exists: true`. `20260727120000:22–25`: "`add_index(if_not_exists: true)` on its own is WORSE: IF NOT EXISTS keys purely on the relation name, so it skips silently and reports success while the invalid, unusable index survives." `StrongMigrations.remove_invalid_indexes` is commented out (`strong_migrations.rb:42`).
- **No `SET LOCAL lock_timeout`** and no `safety_assured` — `20260828120000:32–41` records why the idiom is unavailable after `start_after`, and no live `safety_assured` exists anywhere in `db/migrate`.
- `auto_analyze = true` fires an `ANALYZE account_metrics` after the index build; the runbook's timing note accounts for it.

### Approach per unit of work

| Unit | Where | How | Runtime |
| :-- | :-- | :-- | :-- |
| Migration (columns) | `db/migrate/20260912120000_add_classification_types_to_account_metrics.rb` | `up`/`down`, four `add_column`s per G15; header in the slice 2 migration's voice — what each column is, the two NULL conventions (G4), no mirror, no backfill (the first `metrics:recompute` is it), strong_migrations-clean; `migrate`, `rollback`, `migrate`; the schema diff must be four lines inside `create_table "account_metrics"` plus the version line | metadata-only |
| Migration (index) | `db/migrate/20260912120001_add_lifecycle_index_to_account_metrics.rb` | `20260818120000` copied exactly: `disable_ddl_transaction!`, name constant, `up`/`down`, remove-then-add, concurrent both ways; header states the access path and why `[account_id, lifecycle_type]` is absent (G6) | sub-second on 4,081 rows, plus one ANALYZE |
| Thresholds config | `lib/account_classification.rb` + `spec/lib/account_classification_spec.rb` | G3; pure Ruby, no DB; the unit spec covers every band edge and every day boundary directly | — |
| Enums | `app/models/account_metric.rb` + `spec/models/account_metric_spec.rb` | G9 | — |
| `lifecycle_run` | `calculator.rb` new `lifecycle_run` / `lifecycle_run_sql` | G5; one window query over `visits_sql`; returns `run_started_at` or nil | +1 query, ~1.4 ms |
| `classification` | `calculator.rb` new private `classification(values)` | Ruby derivation from `values[:first_shoot_at]`, `[:most_recent_shoot_at]`, `[:rolling_365_parent_count]`, `[:peak_365_parent_count]` and `lifecycle_run`, through `AccountClassification`; one `now = Time.current` taken inside the method, as every other method takes its own cutoff (slice 2's G3); merged **after** `shoot_dates` so its inputs exist | Ruby only |
| Read-out reconciliation | `accounts.rake:47–48`, `account_classification.rake:48, 83–94` | the tiers constant keeps its `no shoots` row and takes the other four from `VALUE_BANDS`; `LIFECYCLE_ORDER` and `#lifecycle` read the config. Behaviour-preserving, and the existing specs passing unchanged is the proof | — |
| Endpoint | `show.json.jbuilder`, request spec | G7 | — |
| Contract spec | `spec/architecture/account_classification_spec.rb` | §4.2 and §4.3 on the canonical fixtures, before the `SQL composition` guard | — |

`computed_values` gains one merge. Because `classification` consumes earlier merges rather than returning an independent hash, it takes the accumulated hash — the `derived_rates(counts)` pattern at `calculator.rb:53`, extended to the merged result:

```ruby
values = counts.merge(…).merge(shoot_dates).merge(timing_averages).merge(derived_rates(counts)).merge(margin_value)
values.merge(classification(values)).merge(computed_at: Time.current)
```

Estimated nightly delta: **+1.4 ms per account**, ≈ **+6 s** over 4,078 accounts on dev hardware, against the production baseline of 2 min 36.89 s (§6). The derivation itself is arithmetic on values already in memory.

### Spec plan — boundary cases by name

`spec/lib/account_classification_spec.rb` (new, pure unit): `value_tier` at 0 → nil, nil → nil, 1 → `:single`, 2 and 5 → `:occasional`, 6 and 11 → `:core`, 12 and 500 → `:anchor`; `lifecycle` with `most_recent_shoot_at` nil → `:prospect`; a first shoot exactly 90 days ago → `:new`; a first shoot 91 days ago with a visit yesterday → `:active`; a last visit exactly 90 days ago → `:active`, 91 → `:cooling`, 180 → `:cooling`, 181 → `:at_risk`, **365 → `:at_risk`, 366 → `:lapsed`** (the 2394/3661 case, G2); a fractional day inside each band floors down; `lifecycle_started_at` for each of the six per G1's table. Deliberate break: `ACTIVE_MAX_DAYS` 90 → 91 turns the 91-day example red; `.floor` → `.ceil` turns the 365-day example red.

`spec/models/account_metric_spec.rb` (new): the three integer maps pinned value-by-value; `AccountMetric.value_types == AccountMetric.peak_value_types`; every `AccountClassification::VALUE_BANDS` name is a key of `AccountMetric.value_types` and every `LIFECYCLE_ORDER` name a key of `AccountMetric.lifecycle_types`; and the three collision guards — `AccountMetric.new` still builds a record, `AccountMetric.active` is still `ApplicationRecord`'s status scope, and `AccountMetric.new.respond_to?(:lapsed?)` is false while `:lifecycle_type_lapsed?` is true. Deliberate break: drop `prefix: true` from the lifecycle enum and show the red.

`spec/services/account_metrics/calculator_spec.rb`, three new contexts (pattern: the slice 2 contexts at 414–830; relative dates with ≥10 days of slack, no `travel_to`):

- **lifecycle** — no qualifying visit → `prospect`, `lifecycle_type_at` nil, both tiers nil; a first and only shoot 10 days ago → `new`, stamped at the shoot; a first shoot 200 days ago with a visit 10 days ago → `active`; **a child order 10 days ago under a parent 200 days ago → `active`, not `cooling`** (lifecycle reads `Order.qualifying`; the canary for G5's universe); a last visit 120 days ago → `cooling` stamped at `last + 91 days`; 250 days → `at_risk` at `last + 181`; 400 days → `lapsed` at `last + 366`; a cancelled parent alone → `prospect`; a recapture alone → `prospect`; a headshot-only account → `prospect` with positive `lifetime_value_cents` (§4.2's two populations).
- **`lifecycle_type_at` for `active`** — visits 400, 395 and 10 days ago (a gap over 90 days) → stamped at the 10-day-ago visit; visits every 30 days from 300 days ago → stamped at `first_shoot_at + 90 days`; adding a further visit yesterday to the second fixture does **not** move the stamp (the §6 step 3 stability property, G1). Deliberate break: widen the run query's gap to 900 days → the first example goes red.
- **value tiers** — `rolling_365_parent_count` 0 with `peak_365_parent_count` set → `value_type` nil, `peak_value_type` set (an account whose shoots are all older than a year); 1 → `single`; 5 → `occasional`; 6 → `core`; 12 → `anchor`; `peak_value_type` never below `value_type` on the same fixture. Deliberate break: make `value_tier(0)` return `:single` → the zero example goes red.
- **empty state** (the existing example listing every column) gains the four: `'prospect'`, nil, nil, nil.

`spec/requests/accounts_metrics_spec.rb`: the happy-path row seeds `lifecycle_type: :at_risk, lifecycle_type_at: Time.utc(2026, 7, 29, 21, 45), value_type: :core, peak_value_type: :anchor` and asserts `lifecycleType == 'at_risk'`, `valueType == 'core'`, `peakValueType == 'anchor'`, `lifecycleTypeAt == '2026-07-29T21:45:00Z'` (camelCase keys pinned from the red run); the never-recomputed factory example asserts all four `null`; the admin and scheduler examples assert the four are **present** (they are not money); `money_keys` is unchanged.

`spec/architecture/account_classification_spec.rb`, before the `SQL composition` guard, using the existing `metric` helper (299–302): §4.2's six rules on the canonical fixtures including the `new`-over-`active` precedence and the 365/366 boundary; §4.3's bands and the zero-is-NULL rule; and four cross-column invariants — `lapsed ⇒ value_type IS NULL`; `prospect ⇒ lifecycle_type_at IS NULL and both tiers NULL`; `value_type ≤ peak_value_type` as integers (because `rolling ≤ peak` and the bands are monotone); and `VALUE_BANDS` names ≡ `AccountMetric.value_types` keys, so the config and the enum cannot drift.

`spec/lib/tasks/accounts_rake_spec.rb` and `spec/lib/tasks/account_classification_rake_spec.rb`: **no new examples and no changed assertions.** Both read-outs are behaviour-preserving after G3's reconciliation — the tier ranges move to the config while the display labels and the memo's string output stay — and their existing examples passing unchanged is the evidence, specifically the label assertions at `accounts_rake_spec.rb:592–594, 804–806`. A changed expectation in either file means the reconciliation changed behaviour and is wrong.

Every spec: red first (missing constant / method / column), green, then the deliberate break with the red output pasted.

### Commit sequence (`git-commit-messages`; subjects final)

1. `feat: add the classification label columns to account_metrics` — migration + `schema.rb`. Body: nullable, no default; `lifecycle_type` NULL means not computed while `value_type` NULL means a zero count; the first `metrics:recompute` is the backfill.
2. `feat: add the lifecycle and value enums to AccountMetric` — model + pin spec. Body: `prefix: true` is required, not decorative — `active` would take `ApplicationRecord`'s scope, `new` would shadow `AccountMetric.new`, and two columns share one vocabulary.
3. `feat: hold the classification thresholds in one config object` — `lib/account_classification.rb` + unit spec. Body: §6's "one Ruby config object"; the floor-to-days rule is the one already shipped in the shift memo.
4. `refactor: read the shift memo's lifecycle rule from the config` — `account_classification.rake`; existing spec unchanged.
5. `refactor: read the joint ownership volume bands from the config` — `accounts.rake`; the `no shoots` row stays local; existing spec unchanged.
6. `feat: find when an account's current run of visits began` — `lifecycle_run_sql` + spec. Body: the universe is `Order.qualifying`, parents and children, because the lifecycle dates are; the gap comes from the config.
7. `feat: derive each account's lifecycle and value labels` — `classification` + specs. Body: derived from history rather than stamped on change (G1), with the 1,655-day measurement; NULL tier on a zero count, the `rate` precedent.
8. `feat: expose the classification labels on the account metrics endpoint` — jbuilder + request spec.
9. `test: pin the slice 3 rules in the classification contract spec`.
10. `feat: index account_metrics by lifecycle and value` — the concurrent index migration, last, so a rollback of the labels never leaves an index on absent columns.
11. Platform repo (write-back): `docs: amend account classification to v6 for slice 3`, `docs: update the classification codebase notes for slice 3`, `docs: add the slice 3 deploy runbook`.

### Post-deploy verification (reasoned before the code exists)

After `heroku run rake metrics:recompute -a insgtapi` (required — the four columns are NULL until the first sweep). **Read the task's own summary line first**: `RecomputeAll` rescues `StandardError` per account and the rake task still exits 0 (`recompute_all.rb:60–63`, `metrics.rake:168`), so a config-object bug fails all 4,078 accounts without failing the command.

```bash
heroku run rails runner 'puts AccountMetric.joins(:account).where(accounts: { status_type: 1 }).where(lifecycle_type: nil).count' -a insgtapi   # expect 0
```

Invariants, all expected 0 violations:

| Check | Why |
| :-- | :-- |
| `lifecycle_type IS NULL` on an active account | every active account was swept; `prospect` covers "no shoots" |
| `lifecycle_type = prospect AND lifecycle_type_at IS NOT NULL` | G13 |
| `lifecycle_type <> prospect AND lifecycle_type_at IS NULL` | every other label has a start instant |
| `lifecycle_type_at > now()` | derived stamps are past instants |
| `value_type IS NOT NULL AND rolling_365_parent_count = 0`, and its mirror `value_type IS NULL AND rolling_365_parent_count > 0` | §4.3's zero rule, both directions |
| the same pair for `peak_value_type` / `peak_365_parent_count` | |
| `value_type > peak_value_type` (as integers) | `rolling ≤ peak` (slice 2's G4) and the bands are monotone |
| `lifecycle_type = lapsed AND value_type IS NOT NULL` | structural: no visit in 365 days ⇒ no qualifying parent in 365 days |
| `lifecycle_type = prospect AND peak_value_type IS NOT NULL` | no visit ever ⇒ no parent ever |
| `accounts:joint_ownership` tier table, before vs after | identical numbers — G14 |

Every label check re-derives from the row's own stored inputs, not from `now()`, so a mismatch is a bug rather than drift. The one check that needs a clock — the distribution — pins its cutoff to `AccountMetric.minimum(:computed_at)`, the idiom the slice 2 runbook already uses (`deploy-account-classification-2.md:152–153`), because `computed_at` is taken per account (`calculator.rb:55`) across a sweep that runs 2 min 37 s, so two accounts on the same boundary can legitimately land in different buckets within one run.

| Column | Expected (2026-09-10 restore figures; re-derive on the day) |
| :-- | :-- |
| `lifecycle_type` | `prospect` 2,004 · `new` 61 · `active` 152 · `cooling` 138 · `at_risk` 166 · `lapsed` 1,557 |
| `value_type` | NULL 3,563 · `single` 277 · `occasional` 178 · `core` 41 · `anchor` 19 |
| `peak_value_type` | NULL 2,004 · `single` 1,071 · `occasional` 701 · `core` 191 · `anchor` 111 |
| `lapsed AND peak_value_type = anchor` | 42 — the §4.3 reactivation cohort |

Spot checks: the six-account table above (3, 11364, 10288, 1842, 2687, 58 — one per label), re-derived on deploy day. Account 10288 is the `new → active` handover canary: a stamp equal to its `first_shoot_at` means the `max` with the run start was lost; a stamp equal to its `most_recent_shoot_at` means the run scan was dropped. Account 58 is the reactivation-cohort shape.

Runtime: record the sweep's wall-clock in the deploy log; expect 2 min 36.89 s + ~6 s.

**No shift memo** (G14): every column is new, and the one read-out that changes prints identical numbers.

### Deploy runbook — `docs/runbooks/deploy-account-classification-3.md` (written in the write-back, in the slice 2 shape)

Header (Repos: insgt-api; ~15 min; Status Draft → Ready → Deployed). Summary: four columns, one index, no existing number moves, no memo, ops untouched. **Deploy order and the window it closes** — identical in kind to slice 2: old code on the new schema is safe (additive nullable columns; `save!` writes only the attributes `compute` carries), new code on the old schema raises `ActiveModel::UnknownAttributeError` per account and 500s the metrics dialog, so the window is push → `db:migrate`. Slice 2's answer was **(A) maintenance window, one push**; this plan assumes the same unless open question 4 says otherwise. Prerequisites: full `rspec` green with the example count on the day; `--no-ff` merge to `master`; a kept `accounts:joint_ownership` baseline to diff. Steps: backup; push; `db:migrate` (two migrations `up`; the index runs outside a transaction, sub-second on 4,081 rows, plus an `ANALYZE` from `auto_analyze`); restart; `time heroku run rake metrics:recompute` and read its failure summary; the NULL count; the invariant table; the distribution table; the six spot checks; the `joint_ownership` diff. **Rollback:** code only (`heroku rollback`) leaves the four columns holding the last sweep's labels while `computed_at` keeps refreshing nightly — the same trap `20260911120000:35–38` and the slice 2 runbook (`:236–241`) spell out, and it must be stated here too, because a stale *label* reads as current in a way a stale count does not. Schema: `db:rollback STEP=2` drops the index (concurrently, by hand) then the columns.

### Risks

- **G1 re-words §6 step 3.** If Dan keeps the literal rule, commit 6 and `lifecycle_run_sql` disappear, the comparison moves into `#call` (not `#compute`), `calculator.rb:93–99` and `account_classification.rake:27–30` must be amended so they stay true, the `lifecycle_type_at` examples become change-detection examples, and the spot-check column reads the deploy date for every row. Nothing else in the plan moves.
- **A config-object bug fails silently at fleet scale.** `RecomputeAll` rescues per account and the rake task exits 0; `recompute_all_spec.rb` stubs the calculator entirely (`:12,26,41,55`), so no existing spec covers the integration. Mitigated by reading the failure summary and the NULL count as the first two verification steps, and by the contract spec exercising the real calculator.
- **The `new`/degrading arithmetic asymmetry** (G2) is inherited and deliberately preserved; a reviewer will flag it, so the config comment must say it is intentional and measured at 0 affected accounts.
- **Two enums over one vocabulary** is unproven in this repo (Unverified). Fallback: two identical literal hashes plus the contract spec's equality assertion, which is there either way.
- **The run query is the repo's second frame clause** (`ROWS UNBOUNDED PRECEDING`; slice 2 introduced `RANGE BETWEEN … PRECEDING`). Prototyped on PG 15 fleet-wide and per account; the contract spec pins the gap semantics on fixed dates.
- **`value_type` flap is real and unmitigated by design** (§4.3): 79 accounts sit at count 2 and 26 at count 5, either side of a band edge. Ops sees truth; the debounce is slice 7's, at the push boundary. Recorded so the review does not read it as an oversight.
- **`lifecycle_type_at` vs `lifecycle_type_at_risk?`** — one underscore apart, both introduced here. A misread in a spec expectation would pass silently.

### Write-back (part of the slice)

- **v6 amendment:** header (Status, Version 6, Last updated, Supersedes, Companion files incl. this plan and the new runbook); §3.4's heading corrected from "add nine columns" and its code block split into shipped and new; the index line reduced to one index with G6's reason and G15's spelling; §3.4's `lifecycle_type_at` sentence extended with the derivation table and why it is not a stored-row comparison (G1); §4.2 gains the floored-day arithmetic, the `new ⊆ active` proof and the measured distribution; §4.3 gains the NULL-on-zero restatement against the shipped `rate` precedent and the two tier distributions; §6 step 3 marked done and re-worded per G1; §6's "thresholds live in one Ruby config object" points at `lib/account_classification.rb` and names the three artifacts that now read it; §9's slice 3 row; a new change log §14.
- **Codebase notes:** rows for the two migrations, `lib/account_classification.rb`, the three enums and the `VALUE_TYPES` constant, `classification` / `lifecycle_run` / `lifecycle_run_sql`, the jbuilder lines, the new and extended specs; re-range every `db/schema.rb` row below `account_metrics`; correct `visits_sql`'s "date range only" note; change the memo and tiers rows to say they delegate; add `application_record.rb:4,18–20` as the reason the prefix is load-bearing; rewrite "Branch and deploy state".
- **Contract spec:** commit 9.
- **Ops follow-up** (not this slice, recorded so it is not lost): insgt-ops models **none** of slice 2's four API fields today (`grep -rn "rolling365\|peak365" apps/insgt-ops/src` → empty, against a jbuilder that emits them at `:79,80,85,104`), so slice 3's four would make eight unmodelled fields on one endpoint; `AccountMetricSummary` (`account-metric-summary.model.ts:61–108`) gains all eight, optional; the render points are the two components slice 2 listed; **`account-metric-summary.model.ts:99–103` still says `firstShootAt` is "dated by `orders.paid_at` — a PAYMENT timestamp"**, which §5.3 stopped being true in slice 1b and which is precisely the input `lifecycle_type` is derived from, so it must be corrected before anyone builds a segment UI on it; the teams-page segment filter is its own unit and needs the API filter sketched in G8 — `lifecycle_type=` / `value_type=` in `search_params` with a 400 on an unknown value (the `validate_account_type_filter` precedent), a frozen map in `AccountQuery`, an idempotent `join_on[:account_metrics]` like `join_shoots!`, and the `.distinct` / `GROUP BY` checks slice 2's G9 enumerated.

### Gates

Slice character: "new columns, nothing reads them yet" **plus** an endpoint change and two read-outs that must not move. Real gates: **after plan (this STOP); after verification; at the end.** The review runs `predeploy-review-rails` with the Codex pass over the whole diff. Traps the review must not accept, beyond the skill's list:

- A default on any of the four columns, or a `NOT NULL`.
- `value_type` or `peak_value_type` reading `single` for a zero count; `lifecycle_type` reading NULL for an account with no shoots (it is `prospect`).
- Any day boundary or volume band written as a literal outside `lib/account_classification.rb` — including in a spec expectation, which must state the date rather than recompute it from the constant.
- `lifecycle_run_sql` reading `shoots_sql` instead of `visits_sql`, or re-deriving the qualifying predicate instead of composing the scope's `to_sql`.
- `#compute` reading the stored `AccountMetric` row (G1), or `classification` touching the database or an `@account` association (the unsaved-account path, `account_classification.rake:383`).
- A fourth copy of the §4.2 rule or the §4.3 bands anywhere.
- An enum without `prefix: true`; a spec that asserts `lifecycle_type_at` where it means `lifecycle_type_at_risk?`, or the reverse.
- A changed `SHOOT_VOLUME_TIERS` display label, a dropped `no shoots` row, or a label generated from an enum name (G3).
- The config returning strings, or the memo's CSV columns changing shape.
- A `system_metrics` column; a change to `parent_counts_sql`'s bind list, `shoot_dates_sql`, or any slice 2 query's SQL text.
- An index on `[account_id, lifecycle_type]` unless open question 2 says so; any `add_index` or `remove_index` without `algorithm: :concurrently`; `def change` in the index migration; `if_not_exists` without a leading `remove_index`.
- A changed assertion in `accounts_rake_spec.rb` or `account_classification_rake_spec.rb` — G3's reconciliation is behaviour-preserving, and a changed expectation means it was not.
- A spec whose deliberate-break red output was not shown.

### Open questions for the engineer

1. **G1** — accept that `lifecycle_type_at` is **derived from history** (prospect nil; `new` at `first_shoot_at`; `active` at the current run's start or `first_shoot_at + 90 days`, whichever is later; the degrading labels at `most_recent_shoot_at + 91 / 181 / 366 days`) rather than stamped `Time.current` when the nightly sees a change, re-wording §6 step 3? Measured: the literal rule stamps all 4,078 rows with the deploy date, including 1,557 `lapsed` accounts whose true median hold is 1,655 days, and it would falsify three shipped comments.
2. **G6** — ship **one** index (`[lifecycle_type, value_type]`) and record why `[:account_id, :lifecycle_type]` is not added, given the existing unique index on `account_id` and a 4,081-row table? Or ship both as §3.4 asks?
3. **G7** — emit all four labels on `GET /accounts/:id/metrics`, outside the owner-only money block, beside the slice 2 counts?
4. **Deploy shape** — (A) maintenance window, one push, as slice 2 did; or (B) two pushes, migration first?
5. **G12** — may the session commit on `feat/account-classification-3` (no merge to `master`), as it did for slice 2?

### Next phase, if approved

The implementation loop, one unit per the approach table, in commit order: the column migration (`migrate`, `rollback`, `migrate`, schema diff pasted), the enums and the config red → green → deliberate break, the two read-out reconciliations (proven by their unchanged specs), the run query, the derivation, the endpoint, the contract spec, and the index migration last. Then verification against a locally recomputed restore, two review rounds, and the write-back.
