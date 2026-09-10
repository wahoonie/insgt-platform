# Drift audit: Account Classification Architecture v2 vs `insgt-api`

**Date:** 2026-09-07 · **Contract:** `docs/architecture/account-classification.md` v2 (2026-09-05) · **Repo audited:** `apps/insgt-api`, branch `feat/account-account-type` at 393005e, `master` at 1b88f09, `heroku/master` at a3e40e9 (2026-09-02). Read-only; no code changed.

Evidence conventions: `file:line` is the insgt-api path unless prefixed. SQL was run read-only against the dev DB (a production restore) through `rails runner` on 2026-09-07. Migration evidence comes from `db/migrate/` and `db/schema.rb`; this repo has no `structure.sql` (`ls db/` = `migrate schema.rb seeds.rb`). Facts, assumptions, and estimates are labelled where they differ.

Status vocabulary: **matches** · **intentional deviation** · **unintentional drift** · **not yet implemented** · **document is silent** (plus **document is stale** where the prompt asked for it).

---

## 1. Reconciliation table

| # | § | Document says | Code does (`file:line`) | Status |
| :-- | :-- | :-- | :-- | :-- |
| 1 | §2.1 | Recapture is a new order type, `recovery`, at $0 | Row id 300, key `recapture`, price 0, category 5: `db/migrate/20260901120000_create_recapture_order_type.rb:41-42, 77-112`; `Order::RECAPTURE_ORDER_TYPE_ID = 300` `app/models/order.rb:43`; drift guard `lib/tasks/order_types.rake:13-19`. Dev DB `SELECT id, key, price, public, (cart IS NULL), category_type, created_at FROM order_types WHERE key = 'recapture'` = `300, recapture, 0, false, true, 5, 2026-09-02 11:58:42 UTC` | matches |
| 2 | §2.1 | "created with `public: false` so it cannot be selected from the customer-facing order form" | `public: false` is set (`20260901120000:97`; dev DB `public = false`), but the same migration says `public` "is never used in a WHERE clause anywhere in the app" and `cart: nil` "is the ONLY gate" (`:93-97`). ADR 002 §"Why `cart` and not `public`" says the same | unintentional drift, document fix |
| 3 | §2.1 | Cutover date: `_[record the date the Recapture order type row was created]_` (line 86, unfilled) | Migration header: "Before 2026-09-01 there was no Recapture type" (`20260901120000:5-6`). ADR 002: "effective 2026-09-01". Runbook `docs/runbooks/deploy-recapture.md:6`: "Status: Not yet deployed". `git branch -a --contains 35f71c5` includes `remotes/heroku/master` (head a3e40e9, 2026-09-02). Dev DB row `created_at` 2026-09-02 11:58:42 UTC is the local migrate, not production | unintentional drift, document fix (placeholder unfilled; runbook status stale; the authoritative value is production `order_types.created_at` for id 300, not read from here) |
| 4 | §2.1 | Reshoot is the revenue signal, Recapture the quality signal; no $0 heuristic | Reshoot rate numerator is any active child with `order_type_id = 6`, no price test (`app/services/account_metrics/calculator.rb:56-58, 236-262`); recapture rate uses child `order_type_id = 300` (`:57, 59, 245-253, 140-149`). `grep -rni comped app lib` hits only `lib/tasks/orders.rake` and the `order.rb:33-34` comment. `orders:audit_reshoots` still buckets "$0 total (comped)" (`orders.rake:576-578, 623`) but names itself "the pre-cutover baseline for the Reshoot/Recapture split" (`:566-570`) | matches |
| 5 | §2.1 | "Any photographer KPI built on reshoot rate should read `category_type: recovery`" | Recapture predicates bind the pinned id 300, never the category (`calculator.rb:57, 59`; `order.rb:43, 62-63, 133`). ADR 002 §"Why the id is pinned rather than resolved by key" | intentional deviation (ADR 002: a nil in `NOT IN (?)` empties the universe); wording should say id/key |
| 6 | §2.1 | Historical data is not reclassified | `20260901120000:10-11` "NOTHING IS BACKFILLED". Dev DB `SELECT COUNT(*) FROM orders WHERE order_type_id = 300` = 0 | matches |
| 7 | §3.0 | New enum columns: smallint, Rails `enum`, values start at 1, no default | `db/schema.rb:649` `t.integer "category_type", limit: 2, null: false`; `db/schema.rb:100` `t.integer "account_type", limit: 2`; `app/models/order_type.rb:87-88`; `app/models/account.rb:87-88`. Dev DB `information_schema.columns` `column_default` = NULL for both | matches |
| 8 | §3.0 | Sample `enum :category_type, {…}` shows no options | Both enums are `prefix: true` (`order_type.rb:87-88`, `account.rb:87-88`), recorded in `CLAUDE.md:53-55` and `.claude/skills/insgt-api/SKILL.md:154-168`, pinned by `spec/models/order_type_spec.rb:26-33` and `spec/models/account_spec.rb:35-42` | document is silent, document fix |
| 9 | §3.0 | No `string` enum slipped through | `grep -rn "enum " app/models` = the two integer enums only; `app/models/property.rb:22` is a comment ("the codebase does not use Rails enums", now stale) | matches |
| 10 | §3.0 | Tier columns are `value_type` / `peak_value_type`, not `value_tier_type` | Columns absent (row 32). `lib/tasks/accounts.rake:38-39` still cites "the `value_tier_type` enum in … §4.3" | unintentional drift, code fix (comment) |
| 11 | §3.1 | `add_column :order_types, :category_type, :integer, limit: 2, null: false` (one line) | Four migrations: nullable add `20260904120000:39`; backfill `20260904120001`; unvalidated CHECK `20260904120002:28`; validate, `change_column_null`, drop CHECK `20260904120003:30-32`. End state `schema.rb:649`. `README.md:102`: "takes **four** migrations, never one" | matches (end state); document is silent on the sequence |
| 12 | §3.1 | `property: 1, brand: 2, marketing: 3, internal: 4, recovery: 5` | `order_type.rb:87`; pinned exactly `spec/models/order_type_spec.rb:12-20`; backfill map keys 1–5 `20260904120001:38-59` | matches (deviation 3 confirmed integer-for-integer) |
| 13 | §3.1 | No default; classification forced at creation; not derivable | `order_type.rb:73-79, 90` (`validates :category_type, presence: true`; "no ensure_category_type"); `20260904120003:19-23`; `spec/models/order_type_spec.rb:38-43` | matches |
| 14 | §3.1 | Backfill exhaustive on day one, by `key` | `20260904120001:12-15, 38-59` (`CATEGORY_KEYS` keyed on `key`); `:98-102` raises on any NULL row; `:107-112` on an unknown key; `:116-120` on a duplicate | matches |
| 15 | §3.1 | Every row has a category | Dev DB `SELECT category_type, COUNT(*) FROM order_types GROUP BY 1` = `1:34, 2:3, 3:6, 4:5, 5:1` (49 rows; 38 active, 11 soft-deleted). `SELECT COUNT(*) FROM order_types WHERE category_type IS NULL` = 0 | matches |
| 16 | §3.1 | Category membership table | Dev DB `string_agg(key) GROUP BY category_type`: every type the table names is in the named category. `brand` = web_portrait, agent_intro_video, social_reel. `marketing` = free_web_portrait, web_portrait_event, headshot_event, paparazzi, top_agent_video, forefront_escrow_reels. `internal` = photo_shoot_discount, virtual_tour_discount, test_package, scheduler_event, stock_photos. `recovery` = recapture. Nine `property` rows the table does not name: virtual_staging, custom_property_website_address, personalized_web_address, matterport_3d_hosting_renewal, free_instagram_reel, video_walkthrough, stagers_special, introductory_package, custom_package (`20260904120001:40-49`) | matches; document is silent on the nine |
| 17 | §3.1 (via §10) | "`MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` is the non-listing set, which is `category_type != property`" | `order.rb:92-94`. Dev DB: five `property` ids are in the list (4 stagers_special, 27 matterport_3d_hosting_renewal, 34 personalized_web_address, 74 free_instagram_reel, 207 reprocess_disclosure_compliance) and seven non-property ids are not (8, 9, 30, 70, 108, 243, 300) | unintentional drift, document fix (§10 analysis does not hold against the shipped backfill) |
| 18 | §3.1 | (the 111-failure fixture sites) | Explicit `category_type` at `spec/support/completed_orders.rb:40` (`:property`), `spec/models/order_type_key_spec.rb:10` (`:property`), `spec/requests/orders_processing_release_on_spec.rb:20`, `orders_show_release_on_spec.rb:18`, `orders_release_on_update_spec.rb:26` (`:marketing`). Commit 6f6279d | matches |
| 19 | §3.1 | `null: false` with no default "forces the classification decision" | Test factory defaults it: `spec/factories/order_types.rb:8-11` `category_type { :property }`. A new spec building through the factory never states a category. Sanctioned by `CLAUDE.md:117-121`. Contrast `spec/factories/accounts.rb:1-7` (no `account_type` default; `spec/models/account_search_account_type_spec.rb:23-25` says why) | document is silent, document fix (state the test-only default) |
| 20 | §3.1 | (API surface) | Enum name serialized `app/helpers/order_types_helper.rb:4-9`; write validated `app/controllers/order_types_controller.rb:7, 55-61`; admin/owner-only param `:69-74` (commit e5bcdc4). insgt-ops reads `categoryType` (`apps/insgt-ops/src/app/features/order-types/data-access/order-type.model.ts`) | document is silent |
| 21 | §3.1 | (readers) | No predicate reads `category_type`: `grep -rn category_type app lib` = model, controller, helper, plus `lib/tasks/accounts.rake:470-472` saying "that column does not exist either … When category_type ships, this task and the Calculator move together" | not yet implemented (1b); the rake comment is stale, code fix |
| 22 | §3.2 | `add_column :marketing_events, :event_type …`, `headshot: 1 … other: 5` | No column: `schema.rb:476-487`. Dev DB `information_schema.columns WHERE table_name = 'marketing_events'` = 10 columns, no `event_type`. `grep -rnE event_type app lib config spec db/migrate db/schema.rb` = exit 1. `git log --all -S'event_type' -- db/migrate app/models/marketing_event.rb spec` = empty. No factory (`spec/factories/marketing_events.rb` absent). `grep -rln marketing_event spec` = exit 1. insgt-ops `grep -rnE '\beventType\b|event_type' src` = exit 1 | intentional deviation (deviation 1). No commit message records it: `git log --all --grep=event_type` = none |
| 23 | §3.2 | "Table already exists with an `organizations` association (PSAR, SDAR, …)" | `app/models/marketing_event.rb:1-13`: `has_many :orders`, `belongs_to :order`, nothing else. `grep -rn organization app/models/marketing_event.rb app/models/concerns/marketing_event_query.rb` = exit 1; `grep -rn marketing_event app/models/organization.rb` = exit 1. 193 active rows | unintentional drift, document fix (moot once §3.2 is removed; do not carry the claim into v3) |
| 24 | §3.3 | "`accounts` — add two columns" | One added: `db/migrate/20260904120004_add_account_type_to_accounts.rb:35`; `schema.rb:100` | intentional deviation (deviation 2); heading stale, document fix |
| 25 | §3.3 | `account_type` nullable, no default, one migration | `20260904120004:14-20, 35`; dev DB `is_nullable = YES`, `column_default = NULL`; no presence validation (`account.rb:70-74`, no `validates :account_type`) | matches |
| 26 | §3.3 | (nil-validity spec split from the persisted check) | `spec/models/account_spec.rb:44-50` asserts validity on an unsaved record (comment explains CrudAttribution's `updated_by_id`); `:52-56` persists nil and reloads; `:58-70` unknown name and integer 10 raise | matches |
| 27 | §3.3 | `add_reference :accounts, :marketing_event, foreign_key: true, null: true, index: true` | Never added: `create_table "accounts"` (`schema.rb:51` onward) has no such column; dev DB `information_schema.columns` for `accounts` returns only `account_type`, `marketing_source_id` of the four asked. `grep -rnE 'add_reference :accounts, :marketing_event'` and `'accounts\.marketing_event_id'` = exit 1. `git log --all -S'marketing_event_id' -- db/migrate app/models/account.rb` = only abbe6206 and 6f460387 (2015: `orders` and `marketing_event_imports`) | intentional deviation (deviation 2). Never added, so not "added and removed" |
| 28 | §3.3 | (alternative `accounts.acquisition_order_id`) | `grep -rnE acquisition_order_id …` = exit 1; `git log --all -S'acquisition_order_id'` = empty. Only `lib/tasks/metrics.rake:172`: "created_at is the only acquisition proxy — no acquired_at column exists" | not yet implemented; open decision D6. No code comment or commit records arguments for either side |
| 29 | §3.3 | `marketing_source_id` stays exactly as it is | `schema.rb` accounts `marketing_source_id bigint`; `account.rb:118-120` | matches |
| 30 | §3.3 | "across all 4,279 rows" | Dev DB `SELECT COUNT(*) FROM accounts WHERE status_type = 1` = 4,067 (351 deleted; 219 of them soft-deleted on 2026-08-31) | unintentional drift, document fix (re-measure). Cause not established; assumption: the zero-order account cleanup, commit 637a8f5 and `accounts:audit_zero_orders` |
| 31 | §3.3 | (API, roles, index filter) | Serialized to admin/scheduler/owner/processor `app/helpers/accounts_helper.rb:64-70`; write gate admin/owner/scheduler `app/controllers/accounts_controller.rb:24, 210-216, 265-270`; owner may update `account.rb:684-692`; index filter `accounts_controller.rb:25, 231-238, 301`, `app/models/concerns/account_query.rb:66, 327-333`; sentinel `Account::UNCLASSIFIED` `account.rb:105`. Specs `spec/requests/accounts_account_type_spec.rb`, `spec/models/account_search_account_type_spec.rb` | document is silent |
| 32 | §3.4 | Nine new `account_metrics` columns and two indexes | None exist: `schema.rb:18-49`. Dev DB `information_schema.columns` for the nine returns only `first_shoot_at`, `most_recent_shoot_at`. `grep -rnE 'lifecycle_type|lifecycle_type_at|\bvalue_type\b|peak_value_type|peak_365'` = exit 1; `grep -rnE 'rolling_365|active_user_count' app` = exit 1 | not yet implemented (slices 2, 3) |
| 33 | §3.4 | `most_recent_shoot_at` exists; do not add `last_shoot_at` | `schema.rb:42-43`; `db/migrate/20260715120000_add_shoot_dates_to_metrics.rb:50-51`; `grep last_shoot_at` = exit 1 | matches |
| 34 | §3.4 | (precursors) | `rolling_365_parent_count` and `active_user_count` exist as SQL aliases in `lib/tasks/accounts.rake:575, 582` (composition read-out), with `:456-472` stating the column "DOES NOT EXIST YET" and using the calculator universe dated by first completed log | document is silent; slice 2 must reconcile or retire the rake derivation |
| 35 | §3.4 | (columns not in the list) | Four recapture columns exist since `20260901120001`: `rolling_90_recaptured_parent_count`, `lifetime_recaptured_parent_count`, `rolling_90_recapture_rate`, `lifetime_recapture_rate` (`schema.rb:44-47`; mirrored on `system_metrics` `:1128-1131`) | document is silent (ADR 002) |
| 36 | §4.1 | Nine values, `fsbo: 8`, `other: 9` | `account.rb:87-88`; pinned exactly `spec/models/account_spec.rb:17-29` | matches (deviation 4 confirmed) |
| 37 | §4.1 | `EXCLUDED_ACCOUNT_IDS = [2, 2555]` and `IGNORE_ACCOUNT_IDS = [2, 89, 2555]` disagree on 89 | `app/services/marketing_source_metrics_service.rb:49` `[2, 2555]`; `lib/account_report.rb:8` `[2, 89, 2555]`. Both live: used at `marketing_source_metrics_service.rb:84`, `marketing_source_accounts_service.rb:53`, `account_report.rb:302, 685` | matches (still disagree) |
| 38 | §4.1 | "Two existing constants" | Two more: `MARGIN_LTV_EXCLUDED_ACCOUNT_IDS = [2, 2555]` `lib/tasks/metrics.rake:8`; `COMPOSITION_EXCLUDED_ACCOUNT_IDS = [2, 89, 2555]` `lib/tasks/accounts.rake:26` (`:16-25` explains why it does not reuse the margin list). Four lists, split 2–2 on account 89 | document is silent, document fix |
| 39 | §4.1 | Retire both once `account_type: internal` is populated | Not retired. Nothing reads `account_type_internal` in place of a list: `grep -rn 'account_type_internal\|account_types\[' app lib` = `account.rb:81-82` (comment) and `account_query.rb:332` (filter). `account.rb:79-80` says `internal` "supersedes" the constants | not yet implemented; comment overstates, code fix |
| 40 | §4.1 | Tiered backfill; worklist `account_type IS NULL` ordered by `rolling_365_parent_count DESC` | No backfill task: `grep -rn account_type lib/tasks` = exit 1. Dev DB `SELECT account_type, COUNT(*) FROM accounts WHERE status_type = 1 GROUP BY 1` = `1:5, 7:7, NULL:4055`; the 12 rows were written through the API (`updated_by_id = 2`, 2026-09-05 to 2026-09-07) and include account 2 = 7 (`internal`), account 89 = 7 (`internal`), account 2555 = NULL. `IS NULL` filter exists (`account_query.rb:329`); the ordering needs a column that does not exist | not yet implemented (backfill; ordering blocked on slice 2). Assumption: the dev-DB writes are hand tests of the ops UI, not a backfill |
| 41 | §4.1 | `set_type!` defaults blank to `brokerage`; no `property_management` type; org-type audit is a slice 4 prerequisite | `app/models/organization.rb:45, 100, 143-144` (`self.type_of = Organization.types[:brokerage][:id] if type_of.blank?`). No audit artefact in `docs/` or `apps/insgt-api/docs` | matches; audit not started |
| 42 | §4.2 | `lifecycle_type`, six values | `grep lifecycle_type` = exit 1; `lifecycle_label` = exit 1 | not yet implemented (slice 3) |
| 43 | §4.3 | `value_type` / `peak_value_type`, bands 1, 2–5, 6–11, 12+, NULL at zero | Columns absent (grep exit 1; `historical_tier` exit 1; `value_tier` only at `accounts.rake:38`). Bands already mirrored as `SHOOT_VOLUME_TIERS` `lib/tasks/accounts.rake:47-48` with a separate "no shoots" row (`:43-46`) | not yet implemented; document is silent on the rake mirror |
| 44 | §4.2 | Exclude `account_type IN (internal, other)` from any prospect push | No push exists: `grep -rni pipedrive app lib config Gemfile` = comments only (`accounts_controller.rb:254`, `accounts_helper.rb:68`) | not yet implemented (slice 7) |
| 45 | §5.1 | `Order.qualifying`, `Order.qualifying_parents`, `Order.billable` | `grep -rnE 'scope :qualifying'`, `'qualifying_parents'`, `'scope :billable'`, `'\.billable\b'` = exit 1 each; `git log --all -S'scope :qualifying'` = empty | not yet implemented (the scope half of slice 1a did not land) |
| 46 | §5.1 | Nothing re-derives the scopes | Interim predicates in production: `Order.shoots` `order.rb:151-153`; `AccountQuery#join_shoots!` `account_query.rb:215-222`; calculator `parent_counts_sql` `calculator.rb:222-233`; `ChurnReport` `lib/churn_report.rb:93-98`; `AccountPendingShootsService` `app/services/account_pending_shoots_service.rb:27, 66-71`; `accounts.rake:456-472` | not yet implemented (1b rewrites them) |
| 47 | §5.1 | `billable` uses `parent_pays IS NOT TRUE`, "the existing convention in three places" | SQL sites: `marketing_source_metrics_service.rb:110`, `marketing_source_accounts_service.rb:81`, `account_report.rb:682, 692`, `orders.rake:578, 587, 656, 702`. Ruby `== true`: `order.rb:455`, `account_report.rb:848` | matches (convention); "three" undercounts, document fix |
| 48 | §5.1 | "`IS NOT TRUE`, not `= false` … suggests NULLs exist in older rows" | Dev DB `SELECT parent_pays, COUNT(*) FROM orders WHERE status_type = 1 AND parent_id IS NOT NULL GROUP BY 1` = `false:1231, true:3731`; NULL count = 0 | document fix (soften the NULL claim; keep `IS NOT TRUE`) |
| 49 | §5.2 | `status_type` has exactly `active: 1`, `deleted: 2` | `lib/status_type.rb:4-7` | matches |
| 50 | §5.2 | Cancellation lives in `order_event_id` against tag `canceled` | `app/models/concerns/order_sql.rb:146`, `account_pending_shoots_service.rb:47`, `app/services/account_order_metrics_service.rb:89`; dev DB `order_events` id 35 = `canceled` | matches |
| 51 | §5.2 | The completed-`order_log` predicate "is what `AccountMetrics::Calculator` already does" | `calculator.rb:190-192` (`completed_event_id`), `:222-233` joins the completed log. Universe is `order_type_id NOT IN (6, 300)`, not `category_type = property` | matches (completion); universe not yet implemented |
| 52 | §5.2 | `AccountPendingShootsService` bounds to `scheduled_at >= now` | `account_pending_shoots_service.rb:55-57, 70` | matches |
| 53 | §5.2 / D4 | `Order.shoots`: reshoots in, headshots out, no delivery. `join_shoots!`: same. Calculator: reshoots out, headshots in, delivery required | `order.rb:63, 151-153` (`FIELD_JOB_EXCLUDED_ORDER_TYPE_IDS = [3, 300]`, active parents, no log join); `account_query.rb:215-222` (same, raw SQL); `calculator.rb:54, 222-233` (`SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS = [6, 300]`, completed log). All three also exclude recapture (300) | matches; document is silent on recapture in the D4 table |
| 54 | §5.2 | Completion hygiene "worth measuring during slice 1b" | Not measured | not yet implemented |
| 55 | §5.3 | Shoot date is `COALESCE(scheduled_at, MIN(order_logs.created_at))`; `paid_at` is out | `calculator.rb:457-458` `MIN(shoots.paid_at)`, `MAX(shoots.paid_at)`; `:107-113`. `20260715120000:14-30` records why `paid_at` was chosen: to agree with `lib/account_report.rb` `first_shoot_kpi_year_ago` | not yet implemented (slice 1b); document is silent on the `account_report.rb` consumer the migration reconciled with |
| 56 | §5.3 | The `where_only_once` comment says `paid_at` stood in for the headshot exclusion | `account_query.rb:171-175` | matches |
| 57 | §5.3 | Direction of the shift | Dev DB: 3,004 active completed parents have `paid_at IS NULL` (undated today, dated under §5.3) | document is silent; fact for the 1b shift memo |
| 58 | §5.4 | Counts read `qualifying_parents`, dates `qualifying`, revenue `billable` | Counts: `calculator.rb:222-233`, all categories except types 6 and 300. Dev DB completed parents in that universe by category = `1:15274, 2:3, 3:3065, 4:6`. Revenue: `lifetime_value_sql` `:278-292` sums every active order with no `paid_at`, `parent_pays`, or category condition | not yet implemented (1b, 2) |
| 59 | §5.4 | A `parent_pays` child's revenue is already in the parent's total | Dev DB: 3,726 active `parent_pays` children carry `order_type_price > 0`, sum 68,455,500 cents, all inside `lifetime_value_cents` today | document is silent on the size; fact for the 1b shift memo |
| 60 | §5.4 | Revenue covers all categories except `internal` | Dev DB: 1 active `internal`-category order with `paid_at`, 500 cents | matches (negligible) |
| 61 | §5.4 | `paid_at` does not survive a refund | `order.rb:1108` `refund_state = { …, paid_at: nil }` inside `issue_refund` (`:1082`) | matches |
| 62 | §5.4 / D4 | Shoot-value columns admit $0 non-property parents today | `calculator.rb:363-386, 392-415`, universe `NOT IN (6, 300)` | matches (D4 consequence); fix not yet implemented (1b) |
| 63 | §5.5 | Set `accounts.marketing_event_id` from the earliest `brand`/`marketing` order | No column (row 27). `orders.marketing_event_id` exists (`schema.rb:718, 783`), so attendance is queryable. §1 axis table also names the column | document is stale, pending D6 |
| 64 | §5.6 | Cancel At Door: no predicate change | `Service::CANCEL_AT_DOOR_ID = 16` `app/models/service.rb:22`; read-out `lib/tasks/orders.rake:755-799` (commit 01e3725); no predicate references it | matches |
| 65 | §9 1a | `category_type` + backfill + the three §5.1 scopes | Column, backfill, API: commits 81bf2e0, 6f6279d, e5bcdc4, merged to `master` at 1b88f09 (2026-09-04). Not on `heroku/master` (head a3e40e9, 2026-09-02), so not deployed (assumption: `heroku/master` is production). No deploy runbook in `docs/runbooks/`. Scopes: row 45 | partially landed |
| 66 | §9 1b | Consumers rewritten onto the scopes + shift memo | Rows 51, 53, 55, 58. `grep -rli "shift memo" docs apps/insgt-api/docs` = the design document only | not started |
| 67 | §9 2 | New numeric columns incl. `active_user_count` + nightly recompute | Row 32; calculator unchanged for these; precursor row 34 | not started |
| 68 | §9 3 | Lifecycle and value enums + thresholds config | Rows 42–43 | not started |
| 69 | §9 4 | `accounts.account_type` + ops classification UI + tiered backfill | Column, model, API, roles, filter: commits 94485f8, f7b5a58, 96c8f44, 39833b6, 393005e on `feat/account-account-type`, unmerged (`git log master..feat/account-account-type` = 5 commits). Ops UI on the insgt-ops branch of the same name: `src/app/accounts/dialogs/account-type/account-type-edit-dialog.ts`, `src/app/scheduler/order/scheduler-order.component.ts:137-141`, `src/app/features/accounts/pages/account-list/account-list-page.ts`; 10 cypress files uncommitted. Backfill and org-type audit: rows 40–41 | partially landed |
| 70 | §9 5 | `marketing_events.event_type` + backfill | Row 22 | void (deviation 1) |
| 71 | §9 6 | `accounts.marketing_event_id` derivation | Rows 27–28 | blocked on D6 |
| 72 | §9 7 | Pipedrive reconciliation + whitelisted push | Row 44 | not started; depends on 3 and 4; Origin leaves the whitelist until D6 (see amendments) |
| 73 | §9 | Shift memo "across all 4,279 accounts" | Row 30 | document fix |
| 74 | (refs) | Document path is `docs/architecture/account-classification.md` (platform `git status`: `D docs/account-classification-architecture.md`, `?? docs/architecture/`, uncommitted) | Nine sites cite the old path: `account.rb:60, 91`; `account_query.rb:308`; `accounts.rake:39, 457`; `spec/models/account_spec.rb:6`; `spec/models/account_search_account_type_spec.rb:6`; `spec/requests/accounts_account_type_spec.rb:11`; `20260904120004:4` | unintentional drift, code fix (comments) once the move is committed |

---

## 2. Unintentional drift

Each item: section, the delta, and whether it is a code fix or a document fix. Row numbers refer to the table above.

| # | § | Delta | Fix |
| :-- | :-- | :-- | :-- |
| D1 | §2.1 | Document says `public: false` is what keeps Recapture off the customer form. The gate is `cart IS NULL`; `public` is documentation only (row 2) | document |
| D2 | §2.1 | Cutover date placeholder is unfilled; three sources disagree (ADR and migration say 2026-09-01, runbook says not deployed, `heroku/master` carries the commit as of 2026-09-02). Production `order_types.created_at` for id 300 is the value to record (row 3) | document (design doc placeholder and `docs/runbooks/deploy-recapture.md:6`) |
| D3 | §3.0 | `lib/tasks/accounts.rake:38-39` cites the v1 name `value_tier_type` (row 10) | code (comment) |
| D4 | §3.1 / §10 | §10 claims `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` equals `category_type != property`. Five `property` ids are in the list and seven non-property ids are not (row 17) | document (correct the §10 analysis; the constants stay untouched) |
| D5 | §3.1 | `lib/tasks/accounts.rake:470-472` says `category_type` "does not exist either" (row 21) | code (comment; naturally resolved when 1b moves the task onto the scopes) |
| D6 | §3.2 | Document claims `marketing_events` has an `organizations` association; it has none (row 23) | document (do not carry into v3) |
| D7 | §3.3 | Heading says "add two columns"; one was added (row 24) | document |
| D8 | §3.3, §9 | Population 4,279 is stale; dev DB active accounts are 4,067 (row 30, 73) | document (re-measure and state the date; explain the 219 soft-deletes of 2026-08-31 if that is the cause) |
| D9 | §4.1 | Document names two internal-account constants; there are four, split 2–2 on account 89 (row 38) | document |
| D10 | §4.1 | `account.rb:79-80` says `internal` "supersedes" the constants; nothing reads it in their place yet (row 39) | code (comment) |
| D11 | §5.1 | "three places" for `parent_pays IS NOT TRUE`; there are eight SQL sites in four files plus two Ruby sites (row 47) | document |
| D12 | §5.1 | "suggests NULLs exist in older rows": zero active child orders have `parent_pays IS NULL` (row 48) | document (keep `IS NOT TRUE`; drop the inference) |
| D13 | (refs) | Nine code sites cite the pre-move document path (row 74) | code (comments), after the platform move is committed |
| D14 | tooling | `.claude/skills/slice-implementation/SKILL.md` §Migrations says "the three-migration pattern" and "`structure.sql`, never `schema.rb`. PostGIS." The repo ships four migrations for a NOT NULL column (`README.md:102`) and has only `schema.rb` (`ls db/`); platform commit e8aa9c7 already corrected the predeploy skill. The audit prompt inherits both phrases | skill (platform), before slice 2's Phase 0 runs against it |
| D15 | §3.0 | `app/models/property.rb:22` says "the codebase does not use Rails enums" (row 9) | code (comment), low priority |

Not drift, but recorded because the document is silent and the next slice will trip on them: rows 8 (`prefix: true`), 19 (factory default), 34 (rake precursors for `rolling_365_parent_count` and `active_user_count`), 35 (recapture columns on `account_metrics`), 53 (recapture in the D4 table), 55 (`account_report.rb` consumer of `paid_at`), 57 and 59 (shift sizes).

---

## 3. Proposed v3 amendments

Replacement text is drafted; v3 itself is not.

### §1 Purpose, axis table

Replace the Origin row with:

> | **Origin** | Where did they come from? | `accounts.marketing_source_id` (self-reported) + a derived acquisition reference, column **undecided, see D6** | Set once |

### §2.1 The Reshoot / Recapture split

Replace "Recapture is created with `public: false` so it cannot be selected from the customer-facing order form." with:

> Recapture is created with `cart` NULL, which is the only thing that keeps it off the customer-facing order form (`CartsController#items` filters `cart IS NOT NULL`). `public: false` is also set, as documentation of intent; `order_types.public` is never used in a WHERE clause. See ADR 002.

Replace the cutover line with:

> **Cutover date:** the `created_at` of `order_types` id 300 in production, written by `db/migrate/20260901120000` when it ran there. The migration and ADR 002 carry 2026-09-01 as the decision date; the deploy that created the row followed on or after 2026-09-02 (`heroku/master` a3e40e9). Record the production timestamp here once read: _[production `SELECT created_at FROM order_types WHERE id = 300`]_.

Add after "Known metric discontinuity":

> Predicates refer to Recapture by its pinned id, `Order::RECAPTURE_ORDER_TYPE_ID = 300`, checked by `rake order_types:verify_pinned_ids`, not by `category_type: recovery`. ADR 002 explains why a runtime lookup by key is unsafe inside `NOT IN (?)`.

### §3.0 Enum column convention

Replace the code sample with:

```ruby
class OrderType < ApplicationRecord
  enum :category_type, { property: 1, brand: 2, marketing: 3, internal: 4, recovery: 5 }, prefix: true
end
```

Add:

> Every new enum is declared `prefix: true`, so the generated methods are `category_type_internal?` and `Account.account_type_internal`, never `internal?`. Both shipped enums are pinned value-by-value in `spec/models/order_type_spec.rb` and `spec/models/account_spec.rb`, including the absence of the unprefixed names.

### §3.1 `order_types.category_type`

Replace the one-line migration with:

> Shipped as four migrations, `db/migrate/20260904120000..3`: nullable add, exhaustive backfill keyed on `order_types.key`, unvalidated CHECK, validate-and-flip. That is the repo's pattern for any column that ends NOT NULL (`insgt-api/README.md` §Migrations).

Add to the membership table's `property` row the nine unnamed rows: virtual staging, custom property website address, personalized web address, Matterport hosting renewal, free Instagram reel, video walkthrough, Stagers Special, Introductory Package, Custom Package.

Add after "Backfill is exhaustive on day one":

> **Test-only default.** `spec/factories/order_types.rb` defaults `category_type` to `property`. Production creation paths still have to state one; a spec building an order type through the factory does not. Specs that hand-build an `OrderType` set it explicitly (`spec/support/completed_orders.rb`, the `release_on` request specs).

### §3.2 (removed)

> ### 3.2 `marketing_events` — no `event_type`
>
> v2 proposed a five-value `event_type` on `marketing_events`. Not added, and not planned. `marketing_events` is a headshot-event-only container: it groups the orders a `MarketingEventImport` creates against one `order_type_id` (`app/models/marketing_event_import.rb:24`). Paparazzi, caravan, and sponsorship work exist as orders and are classified by `order_types.category_type` (`paparazzi` is `marketing`). Per-event reporting therefore reads `orders.marketing_event_id` joined to `order_types.category_type`; a second kind column on the event table would duplicate that. There is no partial implementation anywhere: no column, no enum, no factory, no spec, no consumer in insgt-ops. Recorded here because no commit message records the decision.

### §3.3 `accounts` — add one column

Replace the heading and the migration block with:

> ### 3.3 `accounts` — add `account_type`
>
> ```ruby
> add_column :accounts, :account_type, :integer, limit: 2   # nullable, no default; db/migrate/20260904120004
> ```

Delete the `marketing_event_id` paragraph and the naming caveat. Replace with:

> **`accounts.marketing_event_id` was not added.** v2's derived-origin column assumed an event is the acquiring unit. The open alternative is `accounts.acquisition_order_id`, a foreign key to `orders`, on the theory that acquisition is captured uniformly across event and non-event order types (an event order still carries `orders.marketing_event_id`, so the event is reachable through the order). This is decision **D6**, open; see §7. Nothing in code or commit history argues either side yet; the arguments below are the ones raised in review.
>
> - For `acquisition_order_id`: one column covers every acquisition path, event or not; the event is one join away; it keeps working if events stop being the only lead-generation vehicle.
> - For `marketing_event_id`: it answers the per-event ROI question directly and matches v2 §5.5 as written; an order reference is indirect for that report.
>
> Until D6 closes, slice 6 is blocked and §5.5 is stale.

Replace "across all 4,279 rows" with "across every existing row (4,067 active on 2026-09-07; v2's 4,279 was measured 2026-09-01 and is superseded)".

### §3.4 `account_metrics`

Add:

> Four recapture columns already exist from ADR 002 (`rolling_90_recaptured_parent_count`, `lifetime_recaptured_parent_count`, `rolling_90_recapture_rate`, `lifetime_recapture_rate`) and are outside this document. `lib/tasks/accounts.rake` derives `rolling_365_parent_count` and `active_user_count` ad hoc for the composition read-out, using the calculator's current universe; slice 2 replaces that derivation with the stored columns or states why the read-out keeps its own.

### §4.1 `accounts.account_type`

Replace "Two existing constants are the seed…" with:

> **Four existing constants are the seed for the `internal` backfill, and they disagree with each other.** `MarketingSourceMetricsService::EXCLUDED_ACCOUNT_IDS = [2, 2555]`, `MARGIN_LTV_EXCLUDED_ACCOUNT_IDS = [2, 2555]` (`lib/tasks/metrics.rake`), `AccountReport::IGNORE_ACCOUNT_IDS = [2, 89, 2555]`, and `AccountAudit::COMPOSITION_EXCLUDED_ACCOUNT_IDS = [2, 89, 2555]` (`lib/tasks/accounts.rake`). Account 89 ("Insight Photos Marketing", three parent orders 2022–2023) is excluded by two and counted by two. Determine which is correct before seeding. Once `account_type: internal` is populated, all four retire in favour of the column; until then `Account#account_type` does not supersede them, whatever the model comment says.

Add a status line:

> Status 2026-09-07: column, model, API, role gates, index filter, and the ops edit dialog are implemented on `feat/account-account-type` (unmerged). Twelve accounts were classified by hand through the ops UI in the dev DB (five `agent`, seven `internal`, including 2 and 89). No tiered backfill task exists. The worklist's `ORDER BY rolling_365_parent_count DESC` waits on slice 2.

### §5.1 Scopes

Replace "the existing convention in three places in the codebase" with "the existing convention in every revenue query in the codebase (`MarketingSourceMetricsService`, `MarketingSourceAccountsService`, `AccountReport`, `orders:audit_reshoots`)". Replace "Every existing consumer does, which suggests NULLs exist in older rows." with "Every existing consumer does. No active child order has a NULL `parent_pays` today; `IS NOT TRUE` is kept so that stays true by construction."

Add:

> Status 2026-09-07: none of the three scopes exists. The interim predicates are `Order.shoots`, `AccountQuery#join_shoots!`, and the calculator's `parent_counts_sql`; slice 1b retires them.

### §5.2 / §7 D4

Add a fourth column, Recapture, to the D4 table: **out** in all three rows, via `Order::FIELD_JOB_EXCLUDED_ORDER_TYPE_IDS` and `Order::SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS`.

### §5.3 Shoot date

Add:

> `db/migrate/20260715120000` chose `paid_at` so the metric agrees with `AccountReport#first_shoot_kpi_year_ago`. Moving to `scheduled_at` breaks that agreement; slice 1b either moves the KPI read-out with it or records that the two now differ and why.

### §5.5 Origin

Replace the section body with:

> **Stale pending D6.** v2 derived origin into `accounts.marketing_event_id` from the account's earliest `brand` or `marketing` order. That column was not added (§3.3). The rule survives in shape, set once from the earliest order and immutable, but its target column and therefore its predicate are undecided until D6 resolves between `marketing_event_id` and `acquisition_order_id`. Do not implement from this section.

### §7 Resolved decisions

Add:

> **D6 — Which column records acquisition: `accounts.marketing_event_id` or `accounts.acquisition_order_id`? → Open.** See §3.3 for the arguments recorded so far. Slice 6 and §5.5 wait on it.

### §9 Delivery slices

Replace the table with:

> | # | Slice | Status 2026-09-07 | Unblocks |
> | :-- | :--- | :--- | :--- |
> | 1a | `order_types.category_type` + exhaustive backfill + the three §5.1 scopes | Column and backfill merged to `master` (not deployed); scopes not started | 1b |
> | 1b | Rewrite `account_metrics` and `AccountQuery` consumers onto the scopes + shift memo | Not started | everything |
> | 2 | New `account_metrics` numeric columns incl. `active_user_count` + nightly recompute | Not started | 3, teams page |
> | 3 | `lifecycle_type` / `value_type` / `peak_value_type` + thresholds config | Not started | teams page, 7 |
> | 4 | `accounts.account_type` + ops classification UI + tiered backfill | Column, API, ops UI on an unmerged branch; backfill and org-type audit not started | 7 |
> | 5 | `marketing_events.event_type` + backfill | **Void.** See §3.2 | — |
> | 6 | Acquisition reference derivation (§5.5) | **Blocked on D6** | per-event ROI |
> | 7 | Pipedrive reconciliation + whitelisted push | Not started | — |

Add after "Slice 7 is two jobs, not one":

> **Slice 7 no longer depends on 5 or 6.** v2's push whitelist implied four axes; Origin was the only one that reached Pipedrive through slices 5 and 6. With 5 void and 6 blocked, the whitelist ships with Type, Lifecycle, and Value, and Origin is added to it when D6 closes and slice 6 lands. Slice 7 depends on 3 and 4, as before.

### §10 Analysis produced but deliberately not acted on

Replace the first paragraph of the `MARGIN_LTV_*` note with:

> The two constants do not decompose cleanly into `category_type` plus one boolean against the backfill as shipped. `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` contains five `property` types (Stagers Special, Matterport hosting renewal, personalized web address, free Instagram reel, Reprocess — Disclosure Compliance) and omits seven non-property types (the two discounts, Top Agent Video, Agent Intro Video, Forefront Escrow Reels, Social Reel, Recapture). Either the constant or the categorisation is wrong for those twelve, and that has to be decided before either is derived from the other. Still out of scope; still not acted on.

### §11 Changes from v2

> | Area | v2 | v3 | Why |
> | :--- | :--- | :--- | :--- |
> | §3.2 `marketing_events.event_type` | Five-value enum, slice 5 | Removed; slice 5 void | `marketing_events` is headshot-only; other event work is classified by `category_type` |
> | §3.3 `accounts.marketing_event_id` | Added, immutable, derived | Not added; column undecided (D6) | `acquisition_order_id` proposed as the uniform capture; unresolved |
> | §5.5 Origin | Derivation rule into `marketing_event_id` | Stale pending D6 | No target column |
> | §7 | D1–D5 closed | D6 added, open | Records the acquisition-column question |
> | §9 slices | 5 feeds 6 feeds ROI; 7 depends on 3, 4 | 5 void; 6 blocked on D6; 7 depends on 3, 4 only, Origin joins the whitelist later | Origin was the only axis routed through 5 and 6 |
> | §2.1 gate | `public: false` | `cart` NULL; `public` is documentation | `order_types.public` is dead (ADR 002) |
> | §2.1 cutover | Placeholder | Production `created_at` of row 300; deploy ≥ 2026-09-02 | Runbook and ADR disagree; the row is the record |
> | §3.0 | Sample without options | `prefix: true` on every new enum | Convention set when `account_type` shipped |
> | §3.1 | One-line `null: false` add | Four-migration sequence; factory default noted | strong_migrations; test convention in `CLAUDE.md` |
> | §4.1 constants | Two, disagreeing on 89 | Four, split 2–2 on 89 | `metrics.rake` and `accounts.rake` carry their own |
> | §5.1 `parent_pays` | "three places"; NULLs assumed | Every revenue query; no NULLs among active children | Measured |
> | §10 `MARGIN_LTV_*` | Decomposes into category + boolean | Does not, for twelve types | Measured against the backfill |
> | Population | 4,279 active (2026-09-01) | 4,067 active (2026-09-07) | Re-measured; cause to be confirmed |

---

## 4. Impact on the slice 2 prompt

The slice 2 prompt was not found in the repo (`grep -rlE "[Ss]lice 2|slice-2" --include=*.md` over `/workspace`, excluding `node_modules`, `.git`, `vendor`, `tmp`, `repomix-out` = exit 1; same for `*.txt` and `*.prompt`). The items below are reasoned from what a prompt written against v2 §3.4, §5.4, §6 and §9 must assert, following the `slice-implementation` template's Prerequisites and Gaps sections.

1. **Prerequisite "slice 1a landed" is only half true.** `order_types.category_type` exists and is backfilled; `Order.qualifying`, `Order.qualifying_parents`, and `Order.billable` do not exist (row 45). Every §3.4 numeric column is defined in terms of those scopes (§5.1 table). A Phase 0 prerequisite check phrased as "`Order.qualifying` exists" fails and is a STOP. The prompt has to either add the scopes to slice 2's scope, or wait for a 1a-scopes slice.
2. **Prerequisite "slice 1b landed" is false.** The calculator still dates by `paid_at` and uses `SHOOT_UNIVERSE_EXCLUDED_ORDER_TYPE_IDS` (rows 51, 55). Slice 2's §6 step 1, "recompute numeric columns from the scopes", cannot reuse a predicate the calculator does not have. If slice 2 goes first, it introduces a fourth universe next to the three D4 names, which is the exact failure Q1 rejects.
3. **Population and spot-check expectations.** Any expected value reasoned from 4,279 accounts or 1,991 qualifying shoots is off; the dev DB has 4,067 active accounts (row 30). Re-derive expectations after re-measuring.
4. **Existing ad hoc derivations must be reconciled, not ignored.** `lib/tasks/accounts.rake:575, 582` already compute `active_user_count` and `rolling_365_parent_count` under a different universe and date rule (row 34). The prompt's traps list should forbid a second definition, and the verification step should explain the delta between the rake read-out and the new column rather than accept both.
5. **Nullability and factories.** All nine §3.4 columns are nullable; `spec/factories/account_metrics.rb` must not default them. The `CLAUDE.md` rule for "a nullable column whose NULL means something" (`CLAUDE.md:128`) applies; the prompt should cite it as the reference pattern rather than the `category_type` factory default (row 19).
6. **Enum convention.** Slice 3 owns the enums, but any slice 2 column typed `limit: 2` for later enum use follows `prefix: true` (row 8). The prompt's "decisions already made" list, if it copied the v2 §3.0 sample, is missing that option.
7. **Migration evidence.** The prompt and the skill say `structure.sql` and "three-migration pattern"; the repo has `schema.rb` and uses four migrations for NOT NULL (D14). §3.4 columns are nullable, so single additive migrations apply, but a review that flags `schema.rb` as wrong is itself wrong.
8. **Deploy state.** `category_type` is merged but not on `heroku/master`; `account_type` is on an unmerged branch (rows 65, 69). Slice 2's rolling-deploy note has to sequence after both, and the recapture runbook's stale status (D2) should not be copied as a template.
9. **Document path.** Write-back and code comments should cite `docs/architecture/account-classification.md`; the nine existing sites still cite the old path (row 74).
10. **Worklist ordering ownership.** §4.1's `ORDER BY rolling_365_parent_count DESC` becomes possible only after slice 2. Neither slice 2 nor slice 4 is named as its owner (row 40); the prompt should pin it as a gap.
11. **Codebase notes now exist.** `docs/architecture/account-classification-codebase-notes.md` is the Phase 0 input from here on; the prompt's survey section can cite it instead of re-surveying the calculator.

---

## 6. Disposition (2026-09-08)

Applied the day after the audit. Nothing is committed; Dan reviews and commits. v3 of the document is `account-classification.md` (2026-09-08) and carries every document fix below.

| # | Fix | Where |
| :-- | :-- | :-- |
| D1 | `cart` NULL named as the gate; `public` as documentation | v3 §2.1 |
| D2 | Cutover defined as production `created_at` of row 300; decision date vs deploy date separated. Runbook status line rewritten: code on `heroku/master` since 2026-09-02, production migration run and timestamp still to record | v3 §2.1; `docs/runbooks/deploy-recapture.md:3, 6-8` |
| D3 | `value_tier_type` replaced with `value_type` / `peak_value_type` | `lib/tasks/accounts.rake:38-40` |
| D4 | §10 rewritten: the two lists answer different questions; twelve divergent types named; softer than the audit draft's "either is wrong" | v3 §10 |
| D5 | Comment now says the column exists but is unread until slice 1b | `lib/tasks/accounts.rake:470-472` |
| D6 | Organisation-association claim dropped; the §3.2 replacement states what the table actually has | v3 §3.2 |
| D7 | Heading is "add `account_type`" | v3 §3.3 |
| D8 | Population re-measured 2026-09-08: 4,067 active; 2,005 vs 1,484 trailing-365 shoots under the two predicates; 428 accounts with only non-property work; cause of the account delta left unconfirmed | v3 §1, §4.2, §9 |
| D9 | Four constants named, with files | v3 §4.1 |
| D10 | "supersedes" replaced with "once populated it replaces the four lists … nothing reads it in their place yet" | `app/models/account.rb:79-82` |
| D11 | "three places" replaced with the four revenue-query owners | v3 §5.4 |
| D12 | NULL inference dropped; measurement stated; `IS NOT TRUE` kept | v3 §5.4 |
| D13 | All references now point at `docs/architecture/account-classification.md`: the nine insgt-api sites, `.claude/skills/insgt-api/SKILL.md:154`, and `docs/decisions/002-recapture-order-type.md:52` (two sites the audit missed) | insgt-api, platform |
| D14 | Skill §Migrations: schema diff is `db/schema.rb` today, `structure.sql` once PostGIS lands; four-migration sequence named with the worked example | `.claude/skills/slice-implementation/SKILL.md:76-78` |
| D15 | Comment now says the frozen hash predates the enum convention | `app/models/property.rb:22` |

Also carried into v3 from the "document is silent" rows: `prefix: true` (§3.0), the test-only factory default and the API surface (§3.1), the recapture columns and the `accounts.rake` precursors (§3.4), the hand-classification status (§4.1), the interim predicates (§5.1), the `AccountReport` consumer and the 3,004 undated shoots (§5.3), the `parent_pays` double-count size (§5.4), Recapture in the D4 table (§7), and the worklist-ordering gap assigned to slice 2's plan (§9).

Not done, deliberately: the production cutover timestamp (needs a production read), the ADR's "effective 2026-09-01" (a dated record, left as the decision date), and any behaviour change in insgt-api (every code edit above is a comment).
