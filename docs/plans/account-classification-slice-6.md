# Account classification — slice 6: event attribution (6a host columns, backfill and the ops host field; 6b the nightly derivation with a dry-run memo; 6c the per-host ROI read-out, endpoint and ops panel)

**Decisions:** every decision this plan could not take from the contract or the code is listed under "Decisions taken" at the end, as OQ1–OQ11, with Dan's answers of 2026-10-06. Three of them differ from the draft's recommendation and are folded through the document: **OQ1** keeps §5.5's `Order.shoot_date_sql` for event orders; **OQ5** builds the ROI endpoint and ops panel in this slice; **OQ7** puts `organizations.marketing_source_id` on the organization payload as a read-only field. The smaller ambiguities the draft pinned along the way are listed after the table as Q12–Q18. Dan confirmed all of them on 2026-10-06.

**Repos:** `insgt-api` (6a-api, 6b, 6c-api) and `insgt-ops` (6a-ops, 6c-ops). Platform repo for the write-back. Two repos means two commits per cross-repo change; the deploy order is stated per sub-slice.
**Contract:** `docs/architecture/account-classification.md` v9 — §1 (Origin row), §3.2 (`:232–259`), §3.3 (`:276–288`), §3.5 (`:455–483`), §4.1 (`:535–540`, the proxy input slice 6 changes), §5.1, §5.3, §5.5 (`:1012–1052`), §6 step 4 (`:1108–1112`), §7 D6, §9 slice 6 row (`:1327`) and the two slice 6 paragraphs (`:1390–1398`), §16 "What slice 6 changes in shipped work" (`:1663–1671`).
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails`; for 6a-ops `angular-core`, `insgt-ops-angular-developer`, `angular-unit-testing`, `predeploy-review-angular`.
**Status:** Plan, 2026-10-02; adversarial pass the same day (one independent reviewer over the draft against the contract, both codebases and the skills: 20 findings, 11 upheld and folded in, 9 noted and folded in where they changed a sentence). Nothing implemented. Dan answered the eleven decision points on 2026-10-06 ("Decisions taken" at the end), and those answers were folded into this document the same day. OQ2 and OQ8 change the contract's text, OQ5 and OQ7 add to it, and OQ3, OQ4 and OQ11 settle the map §3.5 asks for. OQ3 and OQ11 are hard to reverse once 6b has run. Four slice prompts are carved from this document in `slice-implementation`'s template: 6a-api (events 1 and 2), 6a-ops (event 3), 6b with 6c-api (events 4–6), and 6c-ops (event 7). The STOP gates written into this plan are the implementation sessions' gates and stand.
**Re-baseline, 2026-10-06:** `insgt-api` `master` is at 5110228 and `insgt-ops` `main` at 232f8fc2 (**9.64.0**). `git diff --stat` from the survey SHAs touches none of the files this plan cites, except that `accounts_helper.rb`'s `marketing_source` lines moved to `:73–78`; references below are corrected. Ops shipped 9.62.0–9.64.0 in the meantime, so this slice's releases are **9.65.0** (6a-ops) and **9.66.0** (6c-ops). Re-check both version numbers at implementation.
**Survey date:** 2026-10-02, against `insgt-api` `master` at **b0dc6c4** (`heroku/master` = `origin/master` = `master`, tree clean, slice 4e deployed), `insgt-ops` `main` at **d4c3a9ac** (9.61.0 live, tree clean), and the dev database (production restore; `schema_migrations` max `20260912120001`, `max(account_metrics.computed_at)` 2026-10-01 02:32:43 UTC, 4,144 active accounts). Three read-only survey passes (api, ops, database — every runner script opened with `SET default_transaction_read_only = on`); every `file:line` below was read at those SHAs; every number carries the id of the query in Appendix A.

---

## The slice cut

Cut at the dependency seams (the read-out must be deployed before the map it feeds can be written; API before ops; the production `APPLY` before the nightly hook) and the visibility seams. Seven deploy events, none of them a maintenance window. Applying the architecture-planning test — *when this is deployed, what changes for the person who uses the system?* — rows 1 and 2 both read "nothing", and the reason is stated: the map cannot be written until the read-out runs in production, and the read-out cannot run until it is deployed (`heroku run` executes the deployed slug; the Procfile has no release phase).

| # | Scope | Prerequisite | Repo | What becomes visible on deploy | Deploy ordering | Gates |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| **6a-i** | `Organization.types[:association]` (OQ2); the two reference columns with unvalidated FKs (two migrations, strong_migrations shape); the two factories; the host read-out `marketing_events:audit_hosts` | OQ2 answered | insgt-api; docs (host audit doc) | **Nothing.** Two nullable columns nothing reads; a read-only task. The production read-out is run from this slug and the map is written from it | Event 1. No window: no model, helper or controller reads the columns yet | "new columns, nothing reads them yet" → after plan; after verification (the read-out) |
| **6a-ii** | The hand-mapped host backfill migration (hosts created, events mapped, hosts mapped to sources) and the FK validation migration; the model associations and the active-organization validation; `organization_id` accepted and `organizationId` / `organizationName` rendered on marketing events; `marketingSourceId` / `marketingSourceName` on the organization payload to admin and scheduler (OQ7, G19) | Event 1 migrated; the production read-out compared with the dev run; the map written | insgt-api; docs (runbook) | **Nothing in the product.** Events carry a host in the database, and the API accepts a key ops does not send yet. Organization payloads carry two new keys that ops ignores. The marketing-source KPI does not move, because no account is written | Event 2. No window: the columns already exist, so the new helper line is safe at any instant; the backfill runs by hand after the push | "new columns, nothing reads them yet" plus a data backfill → after plan; after verification |
| **6a-ops** | A standalone host picker (search-as-you-type over active organizations, "Hosted by Insight Photos" pinned first), required on both event forms; `organizationId` / `organizationName` on the model; the ninth organization type mirrored (OQ2); release **9.65.0** | Event 2 in production and curl-verified | insgt-ops; docs (v10 part 1, notes) | **Schedulers:** every new event needs a host; existing events show theirs; "Hosted by Insight Photos" stores NULL | Event 3, after event 2. Roll ops back first if both must go: 9.65.0 against the old API would drop the host silently (unpermitted param) and block saves on the edit form (required field, no value) | "changes what a human sees" → all |
| **6b** | `EventAttribution` service (plan / `apply!`), rake `account_classification:attribute_event_hosts` (dry run by default, `APPLY=true`, `OUT=`, `CSV=`), the §5.5 contract-spec block; **then, its own push after the production `APPLY`**, the one-line hook in `metrics:recompute` (OQ6) | Event 2 applied in production (hosts and sources exist) | insgt-api; docs (memo, runbook, v10 part 2, notes) | **Don and Dan:** after `APPLY`, the owner-only marketing-source KPI's `attributed_accounts` rises 178 → 269 on the restore (OQ1, OQ3, OQ4, OQ11; see "Derived" under Measurements, M7b, S5 and M15). Per source: `NSDCR event` 6 → 76, `PSAR event` 20 → 33, `SDAR event` 7 → 15; the accounts report and the account edit page show the derived source on those accounts | Events 4 (service + task; no migration) and 5 (the nightly hook, strictly after `APPLY`) | "touches existing computed values" → all, plus the `APPLY` STOP |
| **6c-api** | `HeadshotHostRoi` service + `marketing_events:host_roi` read-out + `docs/architecture/headshot-host-roi-<date>.md`; the owner-only `GET /kpis/headshot_hosts` action, jbuilder and request spec (OQ5, G20) | Event 2 in production (hosts on events). Does **not** depend on 6b's write (§5.5) | insgt-api; docs | **Dan and Don:** a per-host document (attendees, converts, already customers, lifetime value, no-host bucket) for the headshot-event decision; the endpoint has no client until 6c-ops | Event 6, or folded into event 4's push (Q17) | "read-out" → after plan; at the end. "New endpoint" → after plan |
| **6c-ops** | A standalone OnPush `HeadshotHostRoi` panel beside `kpis/components/marketing-source/`, on the KPIs page; Cypress; release **9.66.0** (OQ5, G20) | Event 6 in production and curl-verified | insgt-ops; docs (notes) | **Owner:** a "Headshot event hosts" table on the KPIs page | Event 7, after event 6. It rides 9.65.0 instead only if event 6 is in production before event 3 ships | "changes what a human sees" → all |

**Order and why.** 6a-i → the production read-out → the map → 6a-ii → 6a-ops → 6b (push, dry run, STOP, `APPLY`) → the hook → 6c-api → 6c-ops. 6a-i exists only because the read-out has to run in production before the migration that consumes its map can be written, and because moving every column reader to event 2 is what makes both events windowless. 6b must follow 6a-ops by at least one working day: the attribution reads hosts, and the window between events 2 and 3 is when a scheduler can create an event with an ambiguous NULL host (G5). 6c-api can be built any time after event 2; it rides event 4's push if ready. 6c-ops follows 6c-api because the panel has nothing to call until then.

## Scope

1. §3.5 — `marketing_events.organization_id` and `organizations.marketing_source_id`, both nullable, both FKs, in the strong_migrations shape (G1).
2. §3.5 / §4.1-adjacent — a ninth `Organization.types` value, `association: 9`, in both repos (G2, OQ2).
3. §3.5 — the host read-out and its document, then the hand-mapped backfill migration: host organizations created where missing, every pre-cutoff event mapped to a host or to nil, the host → source map for the three hosts whose event sources exist (G3–G5).
4. §3.2 / §3.5 — `organization_id` on `POST`/`PUT /marketing_events`, `organizationId` and `organizationName` on the event payload, 422 when the id does not resolve to an active organization (G6). `marketingSourceId` and `marketingSourceName` on the organization payload, read-only, admin and scheduler only (G19, OQ7).
5. §3.5 — the required ops host field on **both** event forms (G7, G8).
6. §5.5 / §6 step 4 — the derivation, the memo, the write, the nightly hook (G9–G16).
7. §5.5 last paragraph — the per-host ROI read-out (G17), the owner-only `GET /kpis/headshot_hosts`, and its ops panel (G20, OQ5).
8. Write-back: host audit document, production memo, v10 amendment (two parts if the weeks differ), codebase notes gaining a "Marketing events and hosts" section, two runbooks, the §5.5 contract-spec block.

## Out of scope — do not touch

1. Any change to `Order.shoot_date_sql`, the §5.1 scopes, `AccountMetrics::Calculator`, `RecomputeAll`, or `SystemMetrics::Calculator` (§16: "Slices 1a–3: nothing"). The derivation composes `Order.qualifying_parents.where.not(paid_at: nil).to_sql` and `Order.shoot_date_sql`; it never re-derives them.
2. Setting `marketing_source_id` on headshot-created accounts at creation (§3.3 forbids it). Also stamping `scheduled_at` on new headshot orders in `OrderHeadshot`, which is **a recorded gap, not a non-issue**. Under OQ1 event orders are dated by `Order.shoot_date_sql`, so until `OrderHeadshot` stamps the event date, every new attendee is dated by the delivery log, 1–30 days late (M8d). That keeps losing the fastest converts (S2). v10 records it as a follow-on, and the memo prints how many credits the rule costs on the day (G13).
3. The headshot flow's latent defects, recorded not fixed: `lib/order_headshot.rb:132` calls an undefined `errors` in a class method (a missing contractor is a `NameError`, not `MissingContractor`); `:51` `Order.find_by` without a status filter reuses soft-deleted orders; `:80` matches an existing account by exact name (`"first last"`), so two agents with one name share an account and therefore an attribution.
4. `AccountReport.headshot_event_report` (`lib/account_report.rb:8–150`), whose host parse is three hardcoded substrings (`:55–72`), and `headshot_kpi2` (`:969–1019`, undefined `query`). Re-pointing the former at `marketing_events.organization_id` is a follow-on; console-only.
5. A write path for `organizations.marketing_source_id`, whether an ops form field, a permitted param or a public-id conversion. §3.5 says "set the same way, for hosts only", so writes are migration-only. Under OQ7 the value is on the wire read-only (G19). Ops does not render it in this slice; the ROI panel shows the source from its own endpoint.
6. New `marketing_sources` rows (SDREA, YPN, brokerage hosts). The table doubles as the public signup list (`GET /marketing_sources` is unauthenticated, `marketing_sources_controller.rb:2–3`), so a new source is a customer-facing change (OQ4).
7. `convert_market_source_public_id_to_id` (`accounts_controller.rb:159–173`): `return if marketing_source.blank?` at `:165` means a scheduler can replace a derived source but cannot clear it. §5.5's "a scheduler's override wins" holds for replacement; recorded as a gap in the API, not this slice's.
8. The organizations `autocomplete` endpoint's missing status filter and limit (`organization.rb:76–84`): a soft-deleted organization can be picked; the 6a API validation answers 422. Follow-on.
9. The dead `MarketingEventsController#autocomplete` (`:10–12`, no route, no model method); `marketing_event_imports` (legacy, 135 rows, last 2023-10-27, M10).
10. Person-level attribution; the Pipedrive push (slice 7); `annual_report`; the `property_manager` proxy in the 4b backfill (§4.1 `:535–540`: accepted, not guarded).
11. The ops organizations list page and form beyond the ninth type appearing in their existing type select; the account "team organizations" dialog; `AutocompleteComponent`'s three resource types.
12. A `Host` column on the ops events dashboard (follow-on; the read-out and the memo are the review surface for the backfill).

---

## Phase 0 — survey

### Prerequisites — all landed (facts)

| Prerequisite | Evidence |
| :-- | :-- |
| D6 closed; §3.5 and §5.5 written; slice 6 unblocked | contract v9 `:8`, `:1218–1226`, `:1327` |
| `Order.qualifying_parents`, `Order.shoot_date_sql`, composable without `?` | `app/models/order.rb:181–182, 220–228`; `spec/architecture/account_classification_spec.rb:676–683` |
| `Account.account_type_internal` is the exclusion set every consumer reads (slice 4e) | `marketing_source_metrics_service.rb:112–113`; `marketing_source_accounts_service.rb:83–85`; codebase notes "retired in slice 4e" rows |
| `marketing_sources` rows for the three association event hosts | `lib/tasks/marketing_source.rake:7–12` (`nsdcr_event`, `psar_event`, `sdar_event`); M4 (ids 2, 3, 4; `nahrep` 100, `narpm` 67 also exist) |
| The 4b write pattern to copy: one SELECT, `update_all` with `User.system` and one batch stamp, the WHERE re-check, two self-checks, dry run / `APPLY=true` / `OUT=` / `CSV=` | `lib/tasks/account_type_backfill.rake:88–89, 226–244, 480–505, 551–606` |
| The hand-mapped backfill migration to copy | `db/migrate/20260904120001_backfill_order_types_category_type.rb:38–59` (map), `:63–65` (throwaway class), `:67–84` (`up`/`down`), `:89–121` (`verify!`: unmapped rows, keys with no row, keys listed twice) |
| The read-out shape to copy | `lib/tasks/organizations.rake:9–43` (module, memoised lookups, `select_all` with named binds, raw SQL because of `default_scope`), `:264–275` (task, `VERBOSE`, empty-table refusal) |
| strong_migrations: `start_after 20260806120000`, `target_version 15`, `safe_by_default` off | `config/initializers/strong_migrations.rb:7, 18, 51`; gem 2.8.0, `checks.rb:167–204` (`add_reference` needs `index: { algorithm: :concurrently }` and `foreign_key: { validate: false }`) |
| `User.system` = `User.find(1)` | `app/models/user.rb:113–115` |
| Rake-file load-order rule (no autoloaded constant at file scope) | `lib/tasks/accounts.rake:51–58`; contract §6 `:1138–1144` |
| The spec helpers: `create_completed_order`, ids 3 and 73 pinned `marketing`; `marketing_source` factory; **no** factory for `marketing_events` or `organizations` | `spec/support/completed_orders.rb:15–28, 35–39`; `spec/factories/marketing_sources.rb`; `ls spec/factories` |
| Ops: both event forms, legacy NgModule / `UntypedFormGroup`; route gates admin, scheduler, owner | `orders/summary/create-marketing-event.component.ts:74–81`; `marketing-events/form/marketing-event-form.component.ts:80–85`; `marketing-event-routing.module.ts:15, 22, 29`; `orders/order-routing.module.ts:18` |

### What this slice touches

**insgt-api — schema and models (6a-api)**

| File | Lines | Today | Change |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 13 | version `2026_09_12_120001` | four new migrations |
| same | 486–497 | `marketing_events`: `name` NOT NULL, `description`, `scheduled_at`, `status_type`, audit columns, `order_id` + index; **no organization column, no FK** | `organization_id` bigint nullable, index, FK to `organizations` |
| same | 819–838 | `organizations`: `type_of` smallint NOT NULL, `name` NOT NULL, …; **no indexes, no `marketing_source_id`** | `marketing_source_id` bigint nullable, index, FK to `marketing_sources` |
| same | 499–513 | `marketing_sources`: `public_id` NOT NULL unique, `key` unique, `name`, `position`, `status_type` | read only |
| same | 107, 111, 1259 | `accounts.marketing_source_id` + index + FK (the slice 6b target column) | read only |
| same | 728, 793 | `orders.marketing_event_id` + index; no FK | read only |
| `app/models/marketing_event.rb` | 5, 8, 10, 12 | `has_many :orders`; `belongs_to :order, optional: true`; `default_scope { order('scheduled_at DESC') }`; name presence | + `belongs_to :organization, optional: true` and a validation that a given `organization_id` resolves to an active organization (G6) |
| `app/models/organization.rb` | 29–31, 32–41, 43, 97–109, 143–145 | name uniqueness scoped to `status_type, type_of`; `type_of` range `1..max`; `default_scope` by name; `types` frozen hash of eight; `set_type!` blank → brokerage | + `association: { id: 9, name: 'Association' }` (OQ2); + `belongs_to :marketing_source, optional: true`, `has_many :marketing_events` |
| `app/models/marketing_source.rb` | 5, 7 | `has_many :accounts`; `scope :active` | + `has_many :organizations` |
| `db/migrate/20260106191303_add_marketing_source_to_accounts.rb` | 3 | `add_reference … foreign_key: true` — predates `start_after`, never checked | the shape 6a must **not** copy (G1) |

**insgt-api — the event API (6a-api)**

| File | Lines | Today | Change |
| :-- | :-- | :-- | :-- |
| `app/controllers/marketing_events_controller.rb` | 3 | `authorize_for(:system_admin, :system_scheduler)` on everything | unchanged |
| same | 58–60 | `permit(:name, :description, :scheduled_at, :order_id)` | + `:organization_id` |
| same | 16–30, 32–38 | `create` / `update` through `save(current_user)` / `update(…, current_user)` with `render_errors` | unchanged; the model validation makes a bad id a 422 |
| `app/helpers/marketing_events_helper.rb` | 5 | `json.extract!(marketing_event, :id, :name, :description, :scheduled_at, :order_id)` | + `organization_id`, + `organization_name` (the `marketing_source_name` precedent, `accounts_helper.rb:73–77`: the association object is already loaded) |
| `app/views/marketing_events/{show,index}.json.jbuilder` | — | both call `set_marketing_event!` | unchanged |
| `app/helpers/orders_helper.rb` | 101, 386 | orders render `marketingEventId` | unchanged |
| `app/helpers/organizations_helper.rb` | 2–12, 52–56 | `set_organization!` → `set_organization_attributes!` (`id, name, type_of, url, email, parent_id, property_id`), no audience check | + `marketingSourceId` (public id) and `marketingSourceName` in `set_organization!`, admin/scheduler only (G19) |
| same, its callers | — | `organizations/{show,index}.json.jbuilder`; `accounts_helper.rb:181` (relationships); `accounts_organizations_helper.rb:19`; **`sessions_helper.rb:65`** (the session's `broker` block, which agents receive) | why G19 gates by role: the payload reaches customers |
| `spec/requests/marketing_events_spec.rb` | — | **does not exist** (`grep -rln 'marketing_event' spec` → incidental hits only) | new |

**insgt-api — the headshot flow and the data the derivation reads (6b)**

| File | Lines | What it is | Consequence |
| :-- | :-- | :-- | :-- |
| `lib/order_headshot.rb` | 45–53 | `find_order_for_account` builds `Order.new(account_id:, marketing_event_id:, order_type_id:)` — **no `scheduled_at`**, no status, no parent | `Order.shoot_date_sql` falls back to the completed log for every event order (M8b: 2,654 of 2,654 have `scheduled_at` NULL); → G9 / OQ1 |
| same | 69–83 | match by active `Email` → owner account, else exact name, else create | the 376 "existing customer attended" accounts (M9a) are matched, not created; the name match is a known collision (Out of scope 3) |
| same | 98–102 | `Account.new(name:, scheduler_id:)` — no source, no `account_type` | §3.3 holds in code: attendees are not sourced at creation |
| `app/models/order.rb` | 94 | `belongs_to :marketing_event, optional: true` | the join the derivation uses |
| `app/models/concerns/order_sql.rb` | 54 | selects `orders.marketing_event_id` | unchanged |
| `app/services/account_metrics/recompute_all.rb` | 40–54 | the sweep: `find_each` → `Calculator.call` → `SystemMetrics::Calculator.call`; header `:6–11` says metrics only | **unchanged**; the hook goes in the rake task (G15) |
| `lib/tasks/metrics.rake` | 143–170 | `metrics:recompute`: `DRY_RUN=true` (`:145`), the `completed` guard (`:150–153`), `RecomputeAll.call` (`:158–164`), the summary (`:166–169`) | + the attribution step between `:164` and `:166` (G15), honouring `DRY_RUN` |
| `docs/ops/metrics-recompute-cron.md` | 26–30 | Heroku Scheduler 02:30 UTC, not self-scheduling | the window the 6b runbook avoids |
| `app/controllers/accounts_controller.rb` | 159–173 | `convert_market_source_public_id_to_id`: public id → integer; `return if marketing_source.blank?` (`:165`) | the only ops write path; cannot clear (Out of scope 7) |
| `app/helpers/accounts_helper.rb` | 65–78 | `marketingSourceId` (public id), `marketingSourceName`, `marketingSourceOther` to admin, scheduler, owner, processor | where the derived value becomes visible per account |
| `app/services/marketing_source_metrics_service.rb` | 88–117 | the KPI: `LEFT JOIN marketing_sources`, paid predicate `:107–110`, internal exclusion `:112–113`, `GROUP BY a.marketing_source_id` | moves on `APPLY`; the memo predicts it (G13) |
| `app/services/marketing_source_accounts_service.rb` | 57–88 | the drill-down, same predicate | moves with it |
| `app/controllers/kpis_controller.rb` | 3, 17–21, 25–31 | owner-only (`authenticate_system_owner`); `marketing_sources` hands a service result to a jbuilder, `marketing_source_accounts` (integer id) | + `headshot_hosts` in `marketing_sources`' shape (G20) |
| `app/views/kpis/marketing_sources.json.jbuilder`; `config/routes.rb` | all; 112 | `metadata` + `data` rows; `resources :kpis` | + `headshot_hosts.json.jbuilder`; + the collection route |
| `spec/requests/kpis_marketing_sources_spec.rb` | — | the owner-only request spec | the shape `kpis_headshot_hosts_spec.rb` copies |
| `lib/account_report.rb` | 8–150 | `headshot_event_report`: hosts parsed as `name.include?('SDAR'|'PSAR'|'NSDCR')` (`:55–72`), falling back to the container order's account name (`:54`) | the pre-existing host parse, hardcoded; Out of scope 4 |

**insgt-ops (6a-ops)**

| File | Lines | Today | Change |
| :-- | :-- | :-- | :-- |
| `src/app/orders/summary/create-marketing-event.component.ts` | 74–81 | the scheduler's real create path: `orderId, name, scheduledAt, description, notificationId` (required) | + `host` control, required (G7); submit maps it to `organizationId` |
| `…/create-marketing-event.component.html` | 82–86 | the notification `mat-select` | + the picker above it |
| `src/app/orders/summary/order-summary.component.html` | 27, 44 | renders the block when `order.orderTypeId === headshotEventId` (73, `features/order-types/data-access/order-type.model.ts:6`) | unchanged |
| `src/app/orders/edit/order-edit.module.ts` | 47, 107 | declares `CreateMarketingEventComponent` | imports the standalone picker |
| `src/app/marketing-events/form/marketing-event-form.component.ts` | 80–85, 57–68 | `id, name, description, scheduledAt` (required); `validateForm` toasts and emits `form.value` | + `host`, required; the emit maps to `organizationId` |
| `…/marketing-event-form.component.html` | 48–67 | date and time controls | + the picker |
| `src/app/marketing-events/form/marketing-event-form.module.ts` | — | `SharedModule` only | imports the picker |
| `src/app/marketing-events/{new,edit}/*.page.ts` | 46–58; 51–63 | `Create` / `Update` dispatch `form.value` | unchanged (the form maps before emitting) |
| `src/app/marketing-events/store/marketing-event.service.ts` | 18–24 | `endpoint: 'marketing_events', nameSpace: 'marketingEvent'` → body `{ marketingEvent: {…} }` | unchanged; `organizationId: null` survives (`buildApiParams` drops only `undefined` at the top level, `shared/api/api.service.ts:184–185`, and the namespace object is `cloneDeep`'d, `:194–195`) |
| `src/app/shared/models/marketing-event.model.ts` | 3–10 | class: `id, name, description, scheduledAt, orderId, notificationId` | + `organizationId?: number \| null`, `organizationName?: string \| null` |
| `src/app/shared/models/organization.model.ts` | 48–57 | `OrganizationTypes`, eight entries | + `{ id: 9, name: 'Association' }` |
| `src/app/organizations/store/organization.service.ts` | 106–110, 125–140 | `autocomplete()` always sends `resourceType` (default `-1`), which the API turns into `where(type_of: '-1')` → **empty** | not used by the picker (G7) |
| `src/app/shared/autocomplete/autocomplete.component.ts` | 29, 112–134, 151–156 | legacy, non-standalone, three resource types, hand-built results table | not reused (G7) |
| `src/app/accounts/form/account-form.component.html` | 68–72 | the `[value]="null"` blank option that clears a column — optional control | the null-on-the-wire precedent; the required case has none (G7) |
| `src/app/accounts/dialogs/account-type/account-type-edit-dialog.ts` | 121–123 | the `'null'` string → `null` mapping | the sentinel-mapping precedent |
| `package.json` | 3 | 9.64.0 (re-baseline; 9.61.0 at the survey) | 9.65.0 (6a-ops), 9.66.0 (6c-ops) |
| `src/app/kpis/components/marketing-source/marketing-source.ts` | 1–60 | standalone, OnPush, `inject()`, signals, `MatTableModule` + `MatSortModule`; local state, no NgRx; `MarketingSourceKpiService` in `kpis/data-access/` | the shape the 6c-ops panel copies (G20) |
| `src/app/kpis/pages/kpis-list/kpis-list.{html,module.ts}` | 21; 8 | `<app-marketing-source>` imported into the legacy page module | + the new panel beside it |
| `cypress/e2e/marketing-source/marketing-source.cy.ts` | — | the panel's Cypress spec | the shape the 6c-ops spec copies |
| `cypress/e2e/accounts/team-account-type-edit.cy.ts` | 1–18, 46–49, 60, 74–77, 126 | the fixture / intercept / `click('right')` / `.should('be.null')` shape | the shape the new spec copies |

### Collisions (grep, output pasted)

```
$ grep -rn organization_id app lib spec db/schema.rb | grep -i marketing                 (insgt-api)
(empty)
$ grep -rni 'EventAttribution\|event_attribution\|attribute_event\|HeadshotHostRoi\|host_roi\|audit_hosts\|MarketingEventAudit' app lib spec
(empty)
$ grep -rniw roi app lib spec
(empty)
$ grep -rn ":association\|'Association'" app lib spec                                     (insgt-api)
(empty — type_of 9 is unused; organizations hold 1,2,5,6,7 only, M5c)
$ grep -rnw "organizationId\|hostOrganization\|HOSTED_BY_INSIGHT\|hostedByInsight\|marketingSourceId" src cypress   (insgt-ops)
hostOrganization / HOSTED_BY_INSIGHT / hostedByInsight: (empty)
organizationId: organizations routing, listing MLS override, phone model, account search params — none on MarketingEvent
marketingSourceId: accounts, scheduler order page, KPIs — none on MarketingEvent or Organization
```

### Measurements (dev DB = production restore, 2026-10-02 01:15–01:18 UTC and 02:0x UTC; query ids in Appendix A)

| Question | Result | Query |
| :-- | :-- | :-- |
| `marketing_events` | **196**, all active (0 soft-deleted); 49 with a container order (`order_id`), all from 2024-08 onward and all type 73; 147 without; 5 with no active order; 3 with `scheduled_at` NULL (14 Marketing, 31 Aerial Marketing, 35 Glen Oaks Escrow Booth — all with 0 orders) | M1, S4 |
| Event orders | **2,654 active + 11 soft-deleted**, all `free_web_portrait` (id 3, `marketing`) except 2 soft-deleted `introductory_package` on "Test Marketing Event"; **every one has `scheduled_at` NULL**; the shoot date falls back to the completed log for 2,653, is NULL for 1 (event 1333); the lag event → completion: < 1 day 62, 1–7 days 1,983, 7–30 days 597, 30+ days 10, before the event 1 | M2, M8a–d, S3 |
| Container-order accounts | 2 InsightPhotos (42 events), 2275 "NSDCR NSDCR" (3), 2836 "PSAR" (1), 11058 (2), 11649 (1) — the organization-proxy accounts §4.2 describes, not a host signal | S4 |
| Host tokens parsed from names (ESTIMATE, the read-out is the authority) | PSAR 55 (locations Chula Vista / El Cajon / San Diego), **NSDCAR 41 (2017–2020) and NSDCR 11 (2021 on) — one association under two names**, SDAR 21, SDREA 1, YPN 1 = 130; the other 66 are brokerages, lenders, title and escrow companies, a stager, and Insight's own rows (14, 31, 35, 2 Test, 73 Misc., 147 Caravan). 29 "Expo 2016-06-16" carries no token but is NSDCR's (OQ11) | M3 |
| Host organizations | **None of PSAR, NSDCAR, NSDCR, SDAR, SDREA, YPN, NAHREP or NARPM exists in `organizations`**; `%association%` → 0 rows; no `type_of` value fits (mls, brokerage, lender, stager, agent team, franchise, social media, office); lender, stager and office have no rows | M5a–e |
| Brokerage hosts with an existing organization | Burke 92, San Diego Castles 629, Devine Fog 2814, ELITE Homes 47, New Palace 138, Plaza 127, Sea Coast 157, Silva 117, Sunshine 100, Tidal 240, ROA California 2017 (Women of ROA), Shay Realtors 62 (Ray Shay); franchise-vs-office choices for Windermere, Harcourts, Coldwell Banker, Carrington, Century 21, Realty Executives, RE/MAX, Pacific Sotheby's, United; **none** for 17 lenders / title / escrow / misc hosts | M5f |
| `marketing_sources` | 17 active; event sources 2 `nsdcr_event` (6 accounts), 3 `psar_event` (20), 4 `sdar_event` (7); 100 `nahrep` (2), 67 `narpm` (1); **179** sourced active accounts in all (M4's column sums; = 4,144 − 3,965, M6), of which the KPI counts 178 because one is `internal` | M4, M6, S5 |
| The §5.5 universe (active, source NULL, not internal) | **3,955** of 4,144 active (3,965 source-NULL; 11 internal) | M6 |
| Of the universe: with an active event order; of those with a paid qualifying parent | 2,306; **349** | M7a |
| **Credited under §5.5 as written** (latest event order dated by the shoot date strictly before the first paid listing) | **200**; 149 attended only after buying; 45 of the 200 also attended after; 0 ties | M7a |
| Credited with event orders dated by `marketing_events.scheduled_at` (the draft's OQ1 alternative, **not adopted**) | 203 = the 200 + 996, 1467, 1516. Each bought 1–5 days after the event, and the headshot was delivered after the listing (S2). Under the rule as written these three are after-buyers. Kept as the measure of what the delivery-date rule costs | M7f, S2 |
| Credited by host token (§5.5 as written) | NSDCAR 42 · NSDCR 18 · PSAR 13 · SDAR 8 · SDREA 4 · YPN 1 · other 114. The three hosts with an existing event source: 81 if NSDCAR = NSDCR (OQ3), and **91** once event 29 ("Expo", 10 credits) is mapped to NSDCR (OQ11, M15). The event-date figures for comparison: NSDCAR 44, other 115, 83 | M7b, S5 |
| Credited accounts with more than one hosted event before buying | 32 (last touch decides) | S5 |
| Already-sourced active accounts with an event order (skipped) | 26; their sources: `psar_event` 16, `sdar_event` 7, `nsdcr_event` 2, `other` 1 | M9c–d |
| Internal accounts with an event order | 1 (1534 Test McName) | S3 |
| Attendees created by the headshot flow vs matched to an existing account | 2,157 accounts created within a minute of an event order; 376 accounts matched for an event order; 13 anomalies (created later — merges). The buckets are per order, so an attendee who returned to a later event is in both; they do not sum to the 2,333 distinct attendees (M12b) | M9a |
| Marketing-source KPI today | `total_accounts` 4,133, `attributed_accounts` 178 (4.3%), `total_gross_cents` 372,928,500; NSDCR event 6 / PSAR event 20 / SDAR event 7 | S5 |
| ROI, APPROXIMATE (attendees counted once per token, converts regardless of order) | PSAR 807 attendees / 31 converts; NSDCAR 446 / 91; SDAR 300 / 22; NSDCR 193 / 73; distinct over all events 2,333 / 354, converts' lifetime value $924,229 | M12, M12b |

Derived (labelled), under the decisions taken (OQ1 shoot date, OQ3 NSDCAR = NSDCR, OQ4 three sources):
- The first `APPLY` writes **91** rows (ESTIMATE from M7b and M15: 42 + 18 + 13 + 8, plus event 29's 10 under NSDCR). The 81 without event 29 is the event-date estimate of 83 less 1467 and 1516, the two NSDCAR fast converts.
- `attributed_accounts` moves 178 → 269 (6.5%). Per source: `NSDCR event` 6 → 76, `PSAR event` 20 → 33, `SDAR event` 7 → 15.
- Of the other 109 credited accounts (200 − 91), **107** stay NULL with a host that has no source (brokerage, lender, SDREA, YPN), and **2** stay NULL because their latest event is 147, which has no host (G11). The memo lists both groups by host. 996 (Coldwell Banker) is the third account the event date would have added.

The dry run is the authority for the day's number.

### Where the document, the code and the data disagree (quoted both ways; resolved in the gaps)

1. **§5.5 `:1022–1023`: the event order is "dated by `Order.shoot_date_sql`."** `lib/order_headshot.rb:45–53` never sets `scheduled_at`, and M8b finds 2,654 of 2,654 event orders with it NULL, so the rule dates attendance by the delivery log, 1–30 days late (M8d), NULL for one order. → **G9 / OQ1: the contract's text stands.** The distortion is recorded, and the `OrderHeadshot` stamping gap goes in Out of scope 2.
2. **§3.5 `:457–459`: `add_reference … foreign_key: true, null: true`.** strong_migrations 2.8.0 raises on it (`checks.rb:167–204`); the only such migration in the repo predates `start_after` (`20260106191303`). The v5 index snippet had the same defect (§14). → **G1.**
3. **§3.3 `:286–288`: "host organizations (NARPM, PSAR, NAHREP) already exist as sources."** True of `marketing_sources` (M4); false of `organizations` (M5a–e: none exist), and §3.5 points `marketing_events.organization_id` at `organizations`. → **G2 / OQ2.**
4. **§3.2 `:248–250`: legacy paparazzi rows "are identified by the slice 6 host read-out" and §3.5 `:479`: the read-out lists "every event whose orders are not headshot orders."** M11: every event order is type 3; the non-headshot rows are identifiable by name only (14, 31, 35, 147, 29, 56, 2, 73). → the read-out prints the name-only candidates (G3).
5. **§3.5 `:480–481`: the migration "raises on any event the map misses."** Production events created between the map and the deploy would fail `db:migrate`. → **G5 / OQ8**: raise for pre-cutoff events only.
6. **§9 `:1327` says 6a adds "the required ops host field" (one).** Two forms create events (`create-marketing-event.component.ts`, the one schedulers use from the order page; `marketing-event-form.component.ts`, the `/marketing-events/new` page). → **G7.**
7. **§3.5 `:468–470`: "Hosted by Insight Photos" is an option stored as NULL on a required field.** Angular's `Validators.required` treats `null` as empty, and no form in ops has a required control with a labelled null option (survey §6). → **G8.**
8. **§4.1 `:535–540`** anticipates NARPM-hosted events, and **§9 `:1395–1396`** says the first run moves accounts "into PSAR, NAHREP, NARPM and the other hosts." M3/M4: zero NARPM and zero NAHREP events in 196; `nahrep` (100) and `narpm` (67) are self-reported sources with 2 and 1 accounts. No action in code; v10 corrects §9's sentence, and the §4.1 proxy note stands for the day such an event is held.
9. **§3.5 `:480`: "Dan maps each token to an `organization_id`."** G4 keys the map by event id and its values are host **names** resolved to one active organization at run time, because the host rows do not exist yet (disagreement 3) and so have no ids to write into a migration. Flagged here so v10 records the value side as well as the key side.

### Unverified

- Production beyond what the restore shows: the event list may have grown since the sync; the production read-out (runbook step 1) is the authority for the map.
- Whether `organizations:audit_types`'s spec enumerates `Organization.types` by count (a ninth type would add a `[NO ROWS]` row); checked in the loop.
- No spec suite was run in this session (read-only survey).

---

## Phase 1 — plan

### Gaps pinned

**G1 — The reference columns ship in the strong_migrations shape, four files across two pushes.** `disable_ddl_transaction!`; `add_reference :marketing_events, :organization, index: { algorithm: :concurrently }, foreign_key: { validate: false }` (file 1, event 1); the same for `:organizations, :marketing_source` (file 2, event 1); the host backfill (file 3, event 2, G5); `validate_foreign_key :marketing_events, :organizations` and `validate_foreign_key :organizations, :marketing_sources` (file 4, event 2). The gem accepts the first two as written and raises on §3.5's snippet (`checks.rb:167–204`); a separate file for the validation is **chosen, not demanded** — the gem only insists it not run inside a transaction that already holds a write lock (`checks.rb:492–494`) — so that validation runs after the backfill has written every `organization_id`. Nullable, no default, no backfill of NULL — §3.5 states both NULL meanings and both are expected. Explicit `up`/`down`, `remove_index … algorithm: :concurrently` spelled by hand in `down` (the `20260912120001` lesson). Rolling-deploy: additive nullable columns, old code ignores them, and every reader of the columns (associations, validation, helper) is in event 2, after the columns exist — which is why neither event needs a window. v10 replaces §3.5's snippet, as v6 replaced §3.4's.

**G2 — Hosts are organizations typed `association: 9`, and the value is added to both repos' type lists (OQ2).** `Organization.types` gains `association: { id: 9, name: 'Association' }` (`organization.rb:97–109`; the range validation at `:32–41` follows `max` automatically); `spec/models/organization_spec.rb` (new, or the nearest existing) pins the nine integers; ops `OrganizationTypes` (`organization.model.ts:48–57`) gains the entry so the organizations page can filter and create hosts. Typing associations as `brokerage` is rejected on evidence, not taste: the slice 4 `agent` tier and `User#update_broker`'s "brokerage present" read `type_of = 2` (`account_type_backfill.rake:120`, `user.rb:191–194`), so a PSAR edge on an account would make it "brokerage present". The organization-type audit's advice against a ninth value (§8 Q7) was about representing an account's NARPM affiliation; an association is a kind of organization the hash lacks, which is a different question.

**G3 — The host read-out is `marketing_events:audit_hosts`, module `MarketingEventAudit`, in a new `lib/tasks/marketing_events.rake`, and its document is `docs/architecture/marketing-event-host-audit-<date>.md`.** Read-only, raw SQL (`MarketingEvent` and `Organization` both carry a `default_scope` order), `VERBOSE=true` for ids, the empty-table refusal. It prints, in order: (1) every event — id, name, `scheduled_at`, `order_id`, the container order's account name, active order count, order-type keys — because 196 rows fit on a page and the map is written per event; (2) the token parse (M3's rules, carried in the module as the *draft* only) with counts and the names it cannot parse; (3) for each non-acronym token, the active organizations whose name `ILIKE '%token%'` (id, name, `type_of`) — M5f's table, so the map can point at existing rows; (4) the name-only Insight / paparazzi / booth / caravan candidates (disagreement 4); (5) events with no active orders, events with `scheduled_at` NULL, container-order accounts; (6) **after the backfill has run**, the same task prints events by host organization with the host's source, the nil bucket, and **events with a NULL host created after the map's cutoff** (G5) — so the one task is both the pre-backfill survey and the post-backfill invariant. The document carries the production run, M3's draft token table, and the map Dan settles (OQ3, OQ4) — the input to G4, in the organization-type audit's shape.

**G4 — The backfill is a migration with three hand maps and a creator for missing hosts.** `20261005120002_backfill_marketing_event_hosts.rb` (date placeholder): `HOSTS = [{ name: 'PSAR', type_of: 9 }, { name: 'NSDCR', type_of: 9 }, …, { name: 'Guild Mortgage', type_of: 3 }, …]` — created through a throwaway `HostOrganization < ActiveRecord::Base` by name when no active row with that name exists, raising when the name exists under a different `type_of` (ambiguity is a decision, not a default) — `created_by_id: 1`, `status_type: 1`; `HOST_BY_EVENT_ID = { 1 => 'Windermere Homes & Estates', 2 => nil, …, 1401 => 'SDAR' }` — **keyed by event id, not by token**: a token parser in a migration would have to survive `2012-12-10` for 2021, `2-24-02-09`, `Heashots`, and NSDCAR/NSDCR being one host (M2), and §3.5's "token mapped twice" check becomes "a host name resolving to more than one active organization"; `SOURCE_BY_HOST = { 'PSAR' => 'psar_event', 'NSDCR' => 'nsdcr_event', 'SDAR' => 'sdar_event' }`, keyed by `marketing_sources.key` and resolved at run time, never the integer. `up`: create hosts → `verify!` → two `update_all`s. `verify!` raises naming every offender for: a pre-cutoff event (G5) missing from the map; a map key with no event row; a host name in the map that is not in `HOSTS`; a host resolving to 0 or more than 1 active organizations; a source key with no active row; a `SOURCE_BY_HOST` key not in `HOSTS`. `down`: NULL both columns; organizations the migration created are **not** deleted (soft-delete is the repo's only delete, and a `down` that soft-deletes rows ops may have edited is worse than leaving them). `return if events.count.zero?` guards the test database. Why a migration and not a rake task, against 4b's G3: this backfill is exhaustive, keyed on a natural key, raises on misses, and the values are ops-editable afterwards — the `category_type` shape, which §3.5 names. Location tokens are ignored (one PSAR, one NSDCR), per §3.5.

**G5 — The migration raises only for events created before the map's cutoff; later events stay NULL and are listed (OQ8).** `MAP_CUTOFF = Time.utc(<production read-out timestamp>)`. Production has no `release:` phase (Procfile; slice 2 runbook `:41–42`), so `db:migrate` runs by hand after the push, and a raise there for one event a scheduler created that morning means a code change and a second push. Between events 1 and 3 the ops form cannot send a host, so a few NULLs of the ambiguous kind are expected; the read-out's post-backfill section (G3 item 6) names them, the 6a-ops runbook step has Dan set them from the edit page, and 6b's memo repeats the list. The contract's rule still holds for every event that existed when the map was written. The dev run exercises the rule: one fixture event inserted with `created_at > MAP_CUTOFF` and no map entry must leave `migrate` green and appear in the read-out's "unmapped since the cutoff" section (spec plan).

**G6 — The event API: `organization_id` permitted; `organizationId` and `organizationName` rendered to the existing admin/scheduler audience; a non-resolving id is a 422; an absent key is NULL (OQ9).** `belongs_to :organization, optional: true` plus `validate :organization_is_active, if: -> { organization_id.present? }` — `optional: true` skips Rails' presence check entirely, so without the validation a stale id reaches the FK and raises `InvalidForeignKey` (a 500). Any active organization is a valid host at the API, because 66 of 196 events were brokerage-, lender- or title-hosted and the practice continues (events 310, 871, 1201, 1236 are 2024–2026). The API does not require the key on create: the form enforces the choice (§3.5 `:468–470`) and ops is the only client. `organizationName` beside the id because the picker must render the current host on the edit form without a second request — the `marketing_source_name` precedent (`accounts_helper.rb:73–77`). On the **index** that name is an N+1 unless preloaded: `MarketingEventQuery#search` (`marketing_event_query.rb:8–14`) is `ApiSearch#query` with no includes and the helper runs per row, so `search` gains `includes(:organization)` (or the helper reads a selected `organizations.name`), and the request spec asserts the index's query count does not grow with the page. All of this is event 2 (G1): the association, the validation and the helper line must not deploy before the columns exist.

**G7 — One standalone host picker, used by both legacy forms; no NgRx slice; the organizations autocomplete endpoint as its source.** New code is modern (`insgt-ops-angular-developer`: standalone, `inject()`, signals, typed forms — the exact file names per `angular-core` at implementation), imported into `MarketingEventFormModule` and `OrderEditModule` (standalone components import into NgModules). It is a `ControlValueAccessor` over `mat-autocomplete`: the panel pins **"Hosted by Insight Photos"** first and lists organizations matching the typed term from `GET /organizations/autocomplete?term=` (JWT-only, so the owner role on the event routes is not 403ed as it would be by `GET /organizations`, `organizations_controller.rb:3`; prefix `ILIKE`, `id,name`, `organization.rb:76–84`). The call is made directly with `term` only — **not** through `OrganizationService.autocomplete`, which always sends `resourceType` and turns the query into `where(type_of: '-1')` (`organization.service.ts:106–110, 125–140`), and not through `AutocompleteComponent`, whose three resource types and results table are the brokerage-office shape. The two legacy forms each gain one control in their existing `UntypedFormGroup` style (the skill's "match the file" rule) and map it on submit; nothing else in them changes. 200 ms debounce as the existing autocomplete does. **Reference patterns:** `src/app/shared/account-multi-select/account-multi-select.ts` (standalone `:47`, `MatAutocompleteModule` `:8`, `inject()` `:60`, the debounced search) for the component's shape, and `src/app/shared/forms/v2/form-field.component.ts` (`NG_VALUE_ACCESSOR` `:28, 40`) for the `ControlValueAccessor` wiring; `account.model.ts`'s `accountTypes` for a pinned-vocabulary spec.

**G8 — "Required with a labelled null" is solved by an object-valued control, mapped to `organizationId: null | number` at the form boundary.** The control's value is `MarketingEventHost = { kind: 'insight' } | { kind: 'organization'; id: number; name: string }`, or `undefined` before a choice; `Validators.required` passes on either object and fails on `undefined`, which is the behaviour §3.5 asks for and which `null` cannot provide. Two pure functions beside the type, Vitest-covered: `hostFromMarketingEvent({ organizationId, organizationName })` (`null` → insight; a number → organization; `undefined` → `undefined`, so an event from an old API or a new event blocks save until a choice is made) and `organizationIdFromHost(host)` (insight → `null`; organization → `id`). `null` reaches the API as JSON `null` because `buildApiParams` drops only top-level `undefined` and clones the namespace object (`api.service.ts:184–185, 194–195`); the PUT body is `{ marketingEvent: { …, organizationId: null } }` and Cypress pins it with `.should('be.null')` (the `team-account-type-edit.cy.ts:126` idiom). Alternatives rejected: a `'null'` string sentinel on the control (`account-type-edit-dialog.ts:121–123` does this and its own comment calls it a trap); a radio plus a conditional autocomplete (two controls for one fact).

**G9 — Event orders and paid listings are both dated by `Order.shoot_date_sql`, as §5.5 step 2 says. An event order with a NULL shoot date is excluded. The comparison is strict, and the tiebreak is `orders.created_at`, then `orders.id` (OQ1).** Dan kept the contract's text. The consequence is measured, not hidden:
- Every event order has `orders.scheduled_at` NULL (M8b), so its shoot date is the completion log, 1–30 days after the event for 2,580 of 2,654 orders (M8d).
- The three fastest converts (996, 1467, 1516) shot a listing 1–5 days after the event, and their headshot was delivered after that (S2). They are after-buyers under this rule and are not credited (M7f: 200, not 203).
- The memo prints them under G13's "credited only under the event date" line.
- Out of scope 2 records the `OrderHeadshot` stamping gap, which is what keeps the distortion going for new attendees.

**The NULL-dated event order.** Event 1333's one order has no completed log, so its shoot date is NULL. A NULL date can be neither "before" nor "latest", so the order drops out of the event-order set before ranking. The account is then judged on its other event orders, if it has any. 0 such orders belong to paid accounts today (M7a), so the rule changes no number. A named spec pins it so that a later `NULLS LAST` cannot slip it in.

**Strict `<`.** An event order shot at the same instant as the listing did not precede it (M7a: 0 such rows today). Same calendar day at different instants: 1 account, credited.

**The tiebreak.** §5.5's tiebreak orders the "latest event order". It changes the answer only when two **different** events' orders share a shoot date, have different hosts and both precede the listing: the later-created order's host wins (spec plan). Two orders on one event are the same host either way.

**The first paid listing shoot** is `Order.qualifying_parents.where.not(paid_at: nil)` composed as `to_sql`, dated by `Order.shoot_date_sql`, earliest by `(shoot date, created_at, id)`. v10 does not rewrite §5.5 step 2. It adds the NULL exclusion and the recorded distortion.

**G10 — The derivation's universe and its NULL trap.** Active accounts with `marketing_source_id IS NULL` and `id NOT IN (Account.account_type_internal.select(:id).to_sql)` — the slice 4e form, because `account_type <> 7` drops the 2,682 untyped accounts (M6) through three-valued logic, the 4b `COALESCE` lesson again. Named spec: an untyped account is written; an `internal` account is not. Soft-deleted accounts, soft-deleted event orders and soft-deleted paid listings are excluded by `status_type = 1` on each; the event row's own `status_type` is **not** filtered (a deleted event still happened; 0 exist today, S4) — recorded, and a one-line reversal.

**G11 — Last touch has no fallback.** The latest event order before the first paid listing decides alone: if its event has no host (NULL) or its host has no source, the account stays NULL even when an earlier hosted event exists. §5.5 step 2 picks one order and step 3 tests that order's chain; falling back to the previous hosted event would be a second rule. Named spec case; 32 accounts had more than one hosted event before buying (S5), so the memo prints how many would differ under "latest hosted event" for information only.

**G12 — The write is the 4b write.** `EventAttribution` in `app/services/event_attribution.rb` (not in `lib/tasks`: the nightly task and the memo task both call it, and `lib/tasks` is not autoloadable, §6 `:1124–1127`), `module_function`-style class methods: `plan(now:)` — **one SELECT**, the CTE chain the measurements used (universe → event orders with the G9 date → paid listings → first paid → credit with `DISTINCT ON`), returning a `Plan` struct with rows carrying `account_id, host organization, source id and key, crediting event id and date, first paid listing date`, plus the not-credited populations tagged by reason; `apply!(plan, applied_at)` — one `Account.transaction`: snapshot of every sourced row, one `UPDATE accounts SET marketing_source_id = plan.source_id, marketing_source_other = NULL, updated_by_id = 1, updated_at = applied_at FROM (<the plan SELECT re-run>) plan WHERE accounts.id = plan.account_id AND accounts.marketing_source_id IS NULL AND accounts.status_type = 1 AND accounts.id NOT IN (<internal>)`, raise `SelfCheckFailed` unless written = planned and unless the snapshot re-reads unchanged. `applied_at = Time.current.floor(6)` taken once; the (actor, stamp) pair is the batch key and the reversal key, as 4b. **Two things §5.5 does not name, pinned here:** the write also sets `marketing_source_other = NULL` — `Account#marketing_source_other_blank_unless_other` (`account.rb:127–128, 917–927`) 422s the next ops save of any account carrying stale free text beside a non-`other` source, so leaving it would turn a derived attribution into a broken edit page; and the derivation never writes a source keyed `other` (raise — a derived source is a host's). Both go into v10. Idempotent: written rows leave the universe. Runtime: the measurement CTEs ran in < 0.2 s over 29,410 orders and 386,559 logs (M14).

**G13 — The memo and the CSV (`account_classification:attribute_event_hosts`, `lib/tasks/event_attribution.rake`).** Dry run by default; `APPLY=true`; `OUT=`; `CSV=`; files opened before any work; the post-commit rescue prints the batch pair — 4b's task shape (`account_type_backfill.rake:551–606`). The memo: header (generated at, database, latest order, git SHA, DRY RUN / APPLIED); the funnel (universe, with event orders, with a paid listing, credited, attended after buying, already sourced, internal); **the write table by host → source** with count and summed `lifetime_value_cents`; credited accounts whose host has no source, by host (the 107); credited accounts whose latest event has no host; the G11 information line; **credited only under the event date** (G9: accounts that are after-buyers by the delivery log but bought after the event itself, with host and gap in days; 996, 1467, 1516 on the restore), for information only, because it measures the Out of scope 2 gap; event orders excluded for a NULL shoot date; the 26 already-sourced accounts with their self-reported source beside the derived host (for Don: agreement or not); events with a NULL host created after the cutoff (G5); **the KPI prediction** — `attributed_accounts` before → after and per-source `account_count` deltas, computed with `MarketingSourceMetricsService`'s own predicate so the runbook's after-table reconciles to it; when applied, the After section (written, `applied_at`, both self-checks). CSV: one row per universe account with an event order — `account_id, name, action` (`write` / `skip_after_buying` / `skip_no_paid_listing` / `skip_latest_unhosted` / `skip_host_no_source`), `host, source_key, crediting_event_id, crediting_event_date, first_paid_listing_at, lifetime_value_cents, lifecycle_type`. As §9 says: the memo goes to Don before the numbers move.

**G14 — Contract spec.** A `describe '§5.5 event attribution'` block in `spec/architecture/account_classification_spec.rb` before `SQL composition` (`:674`), after the worklist block (`:652–672`): the five §5.5 rules on the canonical fixtures (G16's list), the strict comparison, the tiebreak, the no-fallback rule, never-overwrite, the internal exclusion, and "the plan's SQL contains no `?`".

**G15 — The nightly hook is one call in `metrics:recompute`, after `RecomputeAll`, deployed after the production `APPLY` (OQ6).** `lib/tasks/metrics.rake` between `:164` and `:166`: `EventAttribution.call(dry_run:)` printing `Attributed N accounts (host → n …)` or `[DRY RUN] Would attribute N`. Not inside `RecomputeAll` (§6 step 4; its header promises metrics only, `:6–11`) and not a merge on the calculator (`#compute` runs on an unsaved account for the memo). Failure handling follows the sweep's: rescue, log, print `Event attribution failed: …`, keep the metrics summary and the exit code — a bad night of attribution must not read as a failed recompute. The env-gated alternative (a config var flipped after `APPLY`) was rejected: a permanent flag to remember at the Render move. Two pushes, as 4b → 4e.

**G16 — Spec fixtures.** No `marketing_events` or `organizations` factory exists and the 4a/4b specs build organizations by hand (`organizations_rake_spec.rb:36–42`); this slice adds `spec/factories/marketing_events.rb` (name, `scheduled_at`, `created_by_id: 1`; **no default host** — NULL means something, `insgt-api/CLAUDE.md` §Testing) and `spec/factories/organizations.rb` (name sequence, `type_of: 2`, `status_type: 1`, `created_by_id: 1`; trait `:association`). Headshot orders in specs: `create(:order, account:, marketing_event:, order_type_id: 3, scheduled_at: nil)` plus a completed log where the shoot-date fallback is under test; paid listings via `create_completed_order(account:, completed_at:, paid_at:)`.

**G17 — The ROI read-out, and the two words §5.5 leaves open (OQ10; OQ5 adds the endpoint and panel, G20).** `HeadshotHostRoi` service (`app/services/headshot_host_roi.rb`, `.call(now:)` → rows) and `marketing_events:host_roi` in `lib/tasks/marketing_events.rake` printing it, document `docs/architecture/headshot-host-roi-<date>.md`. §5.5 `:1048–1050` defines attendees as accounts whose last headshot order "before the first paid listing shoot, where there is one" is at the host, and converts as "those with a paid listing shoot" — which leaves the after-buyer (149 accounts, M7a: bought first, attended later) with no host under the first clause and counted as a convert under the second. Pinned: every active, non-internal account with an event order lands under **exactly one host** — the host of its last event order before its first paid listing shoot, or, when no event order precedes that shoot (no paid listing at all, or an after-buyer), the host of its latest event order; **converts** = attendees whose first paid listing shoot is **after** the crediting event; **already customers** = after-buyers, a separate column, never converts. So per host: events, attendees, converts, conversion %, already customers, converts' `lifetime_value_cents` (from `account_metrics`), the host's source or `none`; a "no host" row; totals that equal the distinct attendee count. That count was 2,332 on the restore (M12b's 2,333 less 1534), less any account whose only event order is event 1333's NULL-dated one (G9; at most 1; re-measured in Phase 0). Reads the same CTE as `EventAttribution.plan` with the "already sourced" filter removed, so it is one derivation with two readers (the §6 config lesson). Event orders are therefore dated by `Order.shoot_date_sql` here too (OQ1), and "after the crediting event" means after that order's shoot date. Independent of 6b's write (§5.5 `:1048–1051`). Dan confirmed these rules as pinned (OQ10). The reason is that the read-out must keep acquisition and retention apart while still counting every attendee once: converts measure acquisition, and already-customers measure events serving existing clients. v10 words §5.5's last paragraph to state the attendee, convert and already-customer rules. The service is the single source for the read-out and for G20's endpoint.

**G18 — Commits.** The session does not commit; Dan commits (standing). Branches: `feat/account-classification-slice-6-hosts` (6a-api), `feat/marketing-event-host` (6a-ops), `feat/account-classification-slice-6-attribution` (6b; the hook as its own later commit on the same branch, pushed after `APPLY`), 6c-api on the attribution branch or its own, `feat/headshot-host-roi-panel` (6c-ops).

**G19 — `organizations.marketing_source_id` on the organization payload, read-only, admin and scheduler only (OQ7).** Two lines in `set_organization!` (`organizations_helper.rb:2–12`), following the `accounts_helper.rb:73–77` precedent: `marketingSourceId` is the source's **public id** (never the integer, as on accounts) and `marketingSourceName` is its name. Both sit inside `if current_user&.authorize_for_system?(:system_admin, :system_scheduler)`.
- **Why the role gate:** `set_organization!` is embedded widely, including in the session's `broker` block (`sessions_helper.rb:65`), which agents receive. Outside the audience the keys are omitted, not sent as null.
- **What stays the same:** `set_organization_attributes!` and the `parent` block do not change. Nothing is permitted on write, and §3.5's migration-only write path holds (Out of scope 5).
- **Event 2:** the line ships there with the other column readers (G1).
- **N+1:** `organizations/index` renders a page of organizations, so the association is an N+1 unless `includes(:marketing_source)` is added where the index loads. The request spec asserts the query count does not grow with the page, as G6 does for events.

**G20 — The ROI endpoint and panel (OQ5).** ESTIMATE +1–2 days over the read-out.
- **API (6c-api):** `KpisController#headshot_hosts` in `marketing_sources`' shape (`kpis_controller.rb:17–21`): owner-only through the existing `authenticate_system_owner`. It calls `HeadshotHostRoi.call` and hands the rows and totals to `app/views/kpis/headshot_hosts.json.jbuilder`, which returns `metadata` (distinct attendees, converts, already customers, the totals check) and `data`, one row per host plus the no-host row. Each row carries `organizationId` (null for no host), `name`, `events`, `attendees`, `converts`, `conversionPercentage`, `alreadyCustomers`, `convertsLifetimeValueCents` and `marketingSourceName` (null for `none`). It also needs a collection route under `resources :kpis` (`routes.rb:112`) and `spec/requests/kpis_headshot_hosts_spec.rb` in `kpis_marketing_sources_spec.rb`'s shape. Event 6.
- **Ops (6c-ops):** a standalone OnPush component beside `kpis/components/marketing-source/` with the same shape: `inject()`, signals, `MatTableModule` + `MatSortModule`, local state, no NgRx slice. It has a service and a model in `kpis/data-access/`, is added to `kpis-list` next to `<app-marketing-source>`, and is covered by Cypress in `marketing-source.cy.ts`'s shape. File names follow `angular-core` at implementation. The no-host row renders last under a stable label. Release 9.66.0, event 7.

### Approach per unit of work

| Unit | Where | How | Runtime / size |
| :-- | :-- | :-- | :-- |
| Ninth type (OQ2) | `organization.rb:97–109` + `spec/models/organization_spec.rb` (new); ops `organization.model.ts:48–57` + spec | G2 | — |
| Reference migrations ×2 (event 1) + validate (event 2) | `db/migrate/2026100512000{0,1,3}_*.rb` | G1; headers in the `20260912120001` voice | concurrent indexes on 196 and 719 rows (M1, M5c); sub-second |
| Models | `marketing_event.rb`, `organization.rb`, `marketing_source.rb` | G6; `belongs_to … optional: true`, the active-organization validation | — |
| Host read-out | `lib/tasks/marketing_events.rake` + `spec/lib/tasks/marketing_events_rake_spec.rb` | G3; `OrganizationAudit`'s shape | six aggregates; sub-second |
| Backfill migration | `db/migrate/20261005120002_backfill_marketing_event_hosts.rb` | G4, G5; three frozen maps, throwaway classes, `verify!` | 196 events |
| Event API | controller `:59`, helper `:5`, `spec/requests/marketing_events_spec.rb` (new) | G6 | — |
| Factories | `spec/factories/{marketing_events,organizations}.rb` | G16 | — |
| Ops type + model | `organization.model.ts`, `marketing-event.model.ts` | G2, G8 | — |
| Ops picker | `src/app/features/marketing-events/…` (names per `angular-core`): the component, `marketing-event-host.model.ts` (type + two pure functions + Vitest) | G7, G8 | ESTIMATE ~150 lines; one new standalone component, no new chunk |
| Ops forms | `create-marketing-event.component.{ts,html}`, `marketing-event-form.component.{ts,html}`, the two modules | G7, G8; one control each, legacy style | — |
| Ops Cypress | `cypress/e2e/marketing-events/marketing-event-host.cy.ts` | both forms | — |
| Ops release | `package.json` 9.65.0 | tag `v9.65.0`, `npm run deploy:prod` on a clean `main` (4d's steps) | — |
| Derivation | `app/services/event_attribution.rb` + `spec/services/event_attribution_spec.rb` | G9–G12 | the plan SELECT < 0.2 s (measured shape) |
| Memo task | `lib/tasks/event_attribution.rake` + `spec/lib/tasks/event_attribution_rake_spec.rb` | G13 | — |
| Contract block | `spec/architecture/account_classification_spec.rb` before `:674` | G14 | — |
| Nightly hook | `lib/tasks/metrics.rake:164–166` + `metrics_rake_spec.rb` example | G15 | adds the plan SELECT to a 2 min 38 s sweep |
| Organization payload | `organizations_helper.rb:2–12`, the organizations index's load, `spec/requests/organizations_marketing_source_spec.rb` (new) | G19 | — |
| ROI | `app/services/headshot_host_roi.rb`, the rake task, spec | G17 | — |
| ROI endpoint | `kpis_controller.rb`, `app/views/kpis/headshot_hosts.json.jbuilder`, `routes.rb:112`, `spec/requests/kpis_headshot_hosts_spec.rb` | G20 | — |
| ROI panel | `src/app/kpis/components/headshot-hosts/…` and `kpis/data-access/…` (names per `angular-core`), `kpis-list`, Cypress, `package.json` 9.66.0 | G20 | ESTIMATE ~150 lines; the marketing-source panel's shape without its dialog |

### Spec plan — boundary cases by name

`spec/lib/tasks/marketing_events_rake_spec.rb` (new; bootstrap from `organizations_rake_spec.rb:22–30`): an event per token prints under its token with its count; a name with no acronym prints in the unparsed list with its ILIKE candidates; an event with no active orders prints in section 5; an event with `scheduled_at` NULL prints; the container-order account name prints; after a host is set (`update_columns(organization_id:)`) the post-backfill section counts it under the host and prints its source or `none`; an event created after `MAP_CUTOFF` with a NULL host prints in "unmapped since the cutoff"; `VERBOSE=true` lists ids; the empty-table refusal. Deliberate break: drop `orders.status_type` from the active-order count → the no-active-orders example goes red.

**The backfill migration** (not specced; run): `migrate`, `rollback`, `migrate` with the schema diff pasted; then on the dev sync, three deliberate breaks pasted red: remove one pre-cutoff event id from the map → raises naming it; point a host at a name that resolves to two active organizations (create a duplicate first) → raises; name a source key with no row → raises. And one green path that proves G5: insert an event with `created_at > MAP_CUTOFF` and no map entry → `migrate` succeeds, the row's host is NULL, and `marketing_events:audit_hosts` lists it under "unmapped since the cutoff"; then move its `created_at` before the cutoff → the same `migrate` raises.

`spec/requests/marketing_events_spec.rb` (new; JWT helpers as `accounts_account_type_spec.rb:21–45`): **create with `organizationId`** → stored, `show` renders `organizationId` and `organizationName`; **create with `organizationId: null`** → NULL, rendered `null`; **create without the key** → NULL (G6, pinned so OQ9's answer is visible); **a soft-deleted organization** → 422 with the message; **an id with no row** → 422, not 500 (deliberate break: remove the validation → `InvalidForeignKey`); **update changes and clears the host**; **index renders both keys**; **a photographer is still refused** (the gate is unchanged).

`spec/requests/organizations_marketing_source_spec.rb` (new; G19), with a host carrying `psar_event`:
- **admin and scheduler** get `marketingSourceId` = the source's public id and `marketingSourceName` "PSAR event". A host without a source gets both `null`.
- **an agent's session `broker` block** and **a photographer** get neither key: they are absent, not null (deliberate break: move the lines outside the role check → red).
- **`marketingSourceId` in a `PUT /organizations/:id` body** is ignored and the column is unchanged, because there is no write path.
- **the index's query count** does not grow with the page (deliberate break: drop the preload → red).

`spec/requests/kpis_headshot_hosts_spec.rb` (new; G20; `kpis_marketing_sources_spec.rb`'s shape):
- **owner** gets the rows and the metadata, and the no-host row has `organizationId: null`.
- **admin, scheduler and photographer** are refused.
- the rows equal `HeadshotHostRoi.call`'s, so the endpoint adds no logic.
- the totals check in `metadata` holds.

`spec/models/organization_spec.rb`: the nine integers pinned; `association` is a valid `type_of`; `set_type!` still defaults a blank to brokerage (a regression guard for the range change).

`spec/services/event_attribution_spec.rb` (new) — the §5.5 rules, each a fixture built from a host organization (`:association`) with or without a source, an event, a headshot order (`order_type_id: 3`, `scheduled_at: nil`) whose completed log is its shoot date (G9), and listings via `create_completed_order`:
- **credited**: headshot delivered 2024-03-05, first paid listing 2024-03-10 → the host's source written; a fixture seeded with stale `marketing_source_other` text via `update_columns` reads NULL afterwards (deliberate break: drop the column from the UPDATE → red);
- **a soft-deleted event with an active order before the listing** → credited (G10: the event's status is not a filter; this example is what a later "fix" would turn red);
- **attended only after buying**: listing 2024-03-10, event 2024-04-01 → NULL;
- **the S2 shape, pinned the contract's way**: event `scheduled_at` 2024-03-01, listing 2024-03-03, the headshot's completed log 2024-03-08 → **not** credited, `skip_after_buying`, and listed under the memo's "credited only under the event date" line (deliberate break: date the event order by `marketing_events.scheduled_at` → credited, red). This is OQ1's guard;
- **an event order with no completed log** (NULL shoot date) → excluded before ranking. With an earlier dated hosted order before the listing, that order credits; alone, the account is not credited and does not error (deliberate break: `NULLS LAST` ranking → the NULL order is treated as latest, red);
- **two hosted events before buying**: PSAR 2024-01, SDAR 2024-02, listing 2024-03 → SDAR's source (last touch);
- **latest event unhosted**: PSAR 2024-01, an Insight event (NULL host) 2024-02, listing 2024-03 → NULL (G11; deliberate break: fall back to the latest hosted event → red);
- **host without a source** → NULL, reason `skip_host_no_source`;
- **event on the listing's day, same instant** → NULL (strict); one second earlier → credited;
- **orders on two different events with the same shoot date, different hosts with different sources**, both before the listing → the later-created order's host wins (deliberate break: reverse the `created_at, id` order → the other source, red); two orders on one event are the same host and only pin `crediting_event_order_id`;
- **already sourced** (self-reported Google search, hosted event before buying) → untouched; the plan lists it with both values;
- **internal** → untouched; **untyped (`account_type` NULL)** → written (G10; deliberate break: `account_type <> 7` → red);
- **soft-deleted account / soft-deleted event order / soft-deleted paid listing** → not credited; **a paid headshot order** (81 exist) is not a listing; **a paid child property order** is not a parent; **an unpaid completed listing** → attendee, not credited; **paid then refunded** (`paid_at` nil) → same;
- **a derived source keyed `other`** → `apply!` raises before writing;
- **`apply!`**: written rows carry `updated_by_id == 1` and one `updated_at`; planned ≠ written (a planned row sourced between plan and apply) → `SelfCheckFailed`, rolled back; a second `apply!` plans 0.

`spec/lib/tasks/event_attribution_rake_spec.rb` (new, 4b's `run_task` shape): dry run writes nothing and prints the funnel and the host table; `APPLY=true` writes and prints After; second `APPLY` plans 0 and `updated_at` does not move; `OUT=` / `CSV=` with G13's columns, the credited account's `action` `write`, the after-buyer's `skip_after_buying`; the output-path failure before any write; the KPI prediction lines equal `MarketingSourceMetricsService.call` run after the write (the reconciliation the runbook relies on).

`spec/lib/tasks/metrics_rake_spec.rb`: `metrics:recompute` prints the attribution line after the recompute summary's inputs; `DRY_RUN=true` writes no source; a stubbed raise in `EventAttribution.call` prints the failure line and the task still prints `Done.`.

`spec/architecture/account_classification_spec.rb` — G14's block.

`spec/services/headshot_host_roi_spec.rb` (new): two hosts and an unhosted event; an account that attended both before buying counts once, under the later host, as a convert; an account with no paid listing counts under its latest event's host, not a convert; **an account that bought first and attended later** counts under its latest event's host as an already-customer and not a convert (deliberate break: drop the "after" test → it becomes a convert, red); converts ≤ attendees per row; the no-host row; internal excluded; hosts + no-host = the distinct attendee total; the source column reads the key or `none`. Deliberate break: count attendees per event instead of per account → the totals example goes red.

**insgt-ops Vitest** — `marketing-event-host.model.spec.ts`: `hostFromMarketingEvent` maps `null` → insight, a number → organization with the name, `undefined` → `undefined`; `organizationIdFromHost` maps insight → `null`, organization → the id; `organization.model.spec.ts` (or the nearest): `OrganizationTypes` holds exactly the nine API ids. No component test in Vitest (`angular-unit-testing`).

**insgt-ops Cypress** — `cypress/e2e/marketing-events/marketing-event-host.cy.ts` (the `team-account-type-edit.cy.ts` shape; `GET /organizations/autocomplete*` stubbed with two hosts): on `/#/marketing-events/new`: **Save without a host** → the toast, no request; **"Hosted by Insight Photos"** → `request.body.marketingEvent.organizationId` is `null`; **typing `PS` and choosing PSAR** → the id; on `/#/marketing-events/:id/edit` with a stubbed event carrying `organizationId: 7, organizationName: 'PSAR'`: **the picker shows PSAR** and an unchanged save sends 7; with `organizationId: null` it shows the Insight option. On the order page (`GET /orders/:id` stubbed with `orderTypeId: 73`, the notification collection stubbed): **the create block shows the picker and blocks without a choice**; **Insight → `null` in `POST /marketing_events`**. The order page's stub set is the heaviest part of the file (Risks).

**insgt-ops 6c-ops** — Cypress in `marketing-source.cy.ts`'s shape (`GET /kpis/headshot_hosts*` stubbed with two hosts and the no-host row): the panel renders on the KPIs page for the owner; the rows sort by converts descending by default; the no-host row renders last under its label; a host without a source shows `none`; an empty `data` shows the empty state; a 500 shows the error state. Vitest only if the panel gains a pure mapper (`angular-unit-testing`).

Every spec: red first, green, then the deliberate break with the red output pasted. `ng build` before any ops commit.

### Commit sequence (`git-commit-messages`; subjects final; Dan commits)

**insgt-api `feat/account-classification-slice-6-hosts` (6a-i) — deploy event 1**

1. `feat: add an association organization type` (OQ2) — `Organization.types`, the pin spec. Body (tier 2): hosts of headshot events are boards and associations, and typing them brokerage would make any linked account "brokerage present" to the slice 4 tier.
2. `feat: add host and marketing source reference columns` — migrations 1 and 2 only, plus `spec/factories/{marketing_events,organizations}.rb`. **No association, validation or helper in this commit.** Body (tier 3, ordering constraint): the strong_migrations shape; the FKs are unvalidated here and validated in event 2 after the backfill, by choice; nothing reads the columns until event 2, so the push needs no window.
3. `feat: audit marketing event hosts` — `lib/tasks/marketing_events.rake` + spec. Body (tier 2): hosts live only in the event name; the read-out drafts the map, is run in production before the map is written, and after the backfill is its invariant.

Platform repo, with event 1: `docs: add the slice 6 plan`; after the production read-out: `docs: record the marketing event host audit`.

**insgt-api, the same branch continued (6a-ii) — deploy event 2, after the map is written from the production read-out**

4. `feat: backfill marketing event hosts from the hand map` — migration 3 (hosts, events, sources) and migration 4 (validate both FKs). Body (tier 3, decision among alternatives): keyed by event id with host names as values, not token → id, and why; the cutoff rule and the window it covers; `down` leaves created organizations.
5. `feat: accept and render the host organization on marketing events` — the three model associations, the active-organization validation, controller, helper, the index preload, request spec. Body (tier 2): `organizationName` so the edit form renders without a second request; an absent key is NULL by design; preloaded on the index.
5a. `feat: render a host's marketing source on the organization payload` (OQ7) — the two helper lines behind the role check, the index preload, request spec. Body (tier 2): read-only, because §3.5 keeps writes in the migration; gated because the session's broker block reaches agents.

Platform repo, with event 2: `docs: add the slice 6 hosts deploy runbook`.

**insgt-ops `feat/marketing-event-host` (6a-ops) — deploy event 3, after event 2's curls pass**

6. `feat: mirror the association organization type`.
7. `feat: add a host organization picker` — the standalone component, the model with its two mappers, Vitest. Body (tier 2): object-valued so `required` can distinguish "no host chosen" from "hosted by Insight Photos", which is stored as null.
8. `feat: require a host on both marketing event forms` — the two forms, the model fields, Cypress. Body (tier 2): two forms create events; the order-page block is the one schedulers use.
9. `chore: bumped version` — 9.65.0.

Platform repo, after event 3: `docs: amend account classification to v10 for the event hosts`, `docs: update the classification codebase notes for the event hosts`.

**insgt-api `feat/account-classification-slice-6-attribution` (6b, 6c-api) — deploy events 4, 5, 6**

10. `feat: derive event attribution into marketing_source_id with a dry-run memo` — the service, the task, both specs, the §5.5 contract block. Body (tier 3, code would mislead): event orders are dated by `Order.shoot_date_sql` as the contract says, even though that is the delivery date (the fast converts it costs are printed, not credited), and a NULL-dated order is excluded; last touch has no fallback; `marketing_source_other` cleared and why; `APPLY=true` is the only write path; the (actor, stamp) batch key.
11. `feat: report headshot event ROI per host` — the service, the read-out, spec. Body (tier 2): one account under one host; converts are attendees who bought after; independent of the attribution write.
11a. `feat: serve headshot host ROI on the KPIs endpoint` (OQ5) — the action, the route, the jbuilder, request spec. Body (tier 1 unless the review finds a reason).
12. (after the production `APPLY`, event 5) `feat: run event attribution in the nightly recompute` — the hook, the spec example. Body (tier 3, ordering): must not deploy before the first `APPLY`; failure keeps the metrics summary.

Platform repo: before event 4 `docs: add the slice 6 attribution deploy runbook`; after `APPLY` `docs: record the production event attribution memo`, `docs: record the headshot host ROI read-out`, the v10 amendment extended (or v11 if the weeks differ), `docs: update the classification codebase notes for event attribution`.

**insgt-ops `feat/headshot-host-roi-panel` (6c-ops) — deploy event 7, after event 6's curl passes**

13. `feat: add the headshot event hosts KPI panel` — the component, its service and model, the `kpis-list` entry, Cypress. Body (tier 2): one row per host plus no host, read from the owner-only endpoint; converts and already-customers stay separate columns.
14. `chore: bumped version` — 9.66.0.

### Post-deploy verification (reasoned before the code exists)

**Event 1 (6a-i).** Push (no window) → `heroku run rake db:migrate` → `db:migrate:status` shows the two reference migrations → `SELECT count(*) FROM marketing_events WHERE organization_id IS NOT NULL` = 0 and the same for organizations → every events endpoint byte-identical (the helper is unchanged) → **the production read-out** (`heroku run --no-tty --exit-code rake marketing_events:audit_hosts -a insgtapi > …`) compared line for line with the dev run: 196 events on the restore; any newer event goes into the map; `MAP_CUTOFF` is that run's timestamp. STOP: the map (OQ3, OQ4, OQ11) is written into migration 3 from this document.

**Event 2 (6a-ii).** Push (no window: the columns exist) → `heroku run rake db:migrate` runs the backfill and the validation → `db:migrate:status` shows all four. Invariants:

| # | Check | Expected |
| :-- | :-- | :-- |
| 1 | `SELECT type_of, count(*) FROM organizations WHERE type_of = 9 GROUP BY 1` | the number of association hosts in `HOSTS` (5 under the draft map: PSAR, NSDCR, SDAR, SDREA, YPN) |
| 2 | `SELECT count(*) FROM organizations WHERE marketing_source_id IS NOT NULL` | 3 (OQ4), each keyed as `SOURCE_BY_HOST` says |
| 3 | `SELECT count(*) FROM marketing_events WHERE organization_id IS NULL` | the map's nil count plus any event created after the cutoff (printed by the read-out's post-backfill section) |
| 4 | the read-out's events-by-host table | equals the map's per-host totals; PSAR 55 and NSDCR 53 under the map (NSDCAR 41 + NSDCR 11 + event 29) |
| 5 | `GET /marketing_events/1137` as scheduler | `organizationId` = PSAR's id, `organizationName` `"PSAR"`; `GET /marketing_events/14` → both `null` |
| 6 | `PUT /marketing_events/1137` with `organizationId: null` then back | round-trips; a bogus id → 422 |
| 7 | `MarketingSourceMetricsService.call[:metadata]` | **unchanged** from the pre-deploy read (6a writes no account) |
| 8 | ops 9.64.0 (still live) | events pages unchanged — the old client ignores the new keys |
| 9 | the index: `GET /marketing_events?per_page=25` | one query for organizations, not twenty-five (router log) |
| 10 | `GET /organizations/<PSAR id>` as scheduler; the same as an agent's session with `include=broker` | `marketingSourceId` = `psar_event`'s public id, `marketingSourceName` "PSAR event"; the agent's payload has neither key (G19) |

**Event 3 (6a-ops).** `git tag v9.65.0 && npm run deploy:prod` on a clean `main`. On site: both forms show the host picker; Save without a choice toasts; Insight sends `null` (network tab); an existing event shows its host; the read-out's "unmapped since the cutoff" list is worked through on the edit page and re-run to 0.

**Event 4 (6b).** No migration, no window; not scheduler-window sensitive (the hook is not in this push). Then:

```bash
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts -a insgtapi > memo-dry-run.md   # STOP: read it, hand it to Don
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts APPLY=true -a insgtapi > memo-applied.md
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts -a insgtapi > memo-second-dry-run.md   # plans 0
```

Invariants after `APPLY` (`<stamp>` is the memo's `applied_at` with microseconds):

| # | Check | Expected |
| :-- | :-- | :-- |
| 1 | `SELECT count(*) FROM accounts WHERE updated_by_id = 1 AND updated_at = '<stamp>'` | = the memo's written count (ESTIMATE 91) |
| 2 | the same rows: `marketing_source_id IS NOT NULL AND marketing_source_other IS NULL AND status_type = 1 AND (account_type IS NULL OR account_type <> 7)` | all |
| 3 | `SELECT marketing_source_id, count(*) … WHERE updated_at = '<stamp>' GROUP BY 1` | = the memo's host → source table |
| 4 | second dry run | plans 0; the funnel's "already sourced" grew by exactly the written count |
| 5 | `MarketingSourceMetricsService.call` | `attributed_accounts` = before + written (178 + 91 = 269 on the restore); per-source `account_count` deltas = row 3; `total_accounts` unchanged |
| 6 | `MarketingSourceAccountsService.call(3)` | lists the PSAR writes; sums to the summary row |

Spot checks, reasoned from the restore under the decisions taken (OQ1 shoot date; OQ3 NSDCAR = NSDCR → `nsdcr_event` 2; PSAR → 3; SDAR → 4; brokerage hosts without a source). The credited rows were drawn from S1, which used the event date. Their event-to-listing gaps are months to years, far beyond the 1–30 day delivery lag, so the shoot date credits them too. The dry run confirms each:

| Account | Why | Expected `marketing_source_id` |
| :-- | :-- | :-- |
| 77 Kim Glynn | NSDCAR Vista 2020-02-03, first paid listing 2020-07-25 | 2 |
| 572 Serena Alexander | SDAR 2016-05-20, first paid 2018-07-11 | 4 |
| 1467 Giovanni Ruiz | NSDCAR 2018-01-30, listing 2018-02-02, headshot delivered 2018-02-07 — the S2 shape (G9) | NULL (`skip_after_buying`); listed under the memo's "credited only under the event date" |
| 214 Maria Lopez | NSDCAR 2019-02-25, first paid 2022-11-21, attended NSDCR again 2025-11-25 | 2 (the later event does not move it) |
| 10 Rick Sauer | Windermere event 1 (2015-07-15), first paid 2016-04-01 — a host with no source | NULL; memo list "host without a source" |
| 47 Kurt Kinsey | first paid 2015-08-27, attended 2016-06-16 | NULL (`skip_after_buying`) |
| 823 Adam Nobert | already `nsdcr_event` | unchanged, `updated_at` unchanged |
| 1534 Test McName | `internal` | unchanged |
| lowest-id account credited to PSAR in the dry run | the memo names it | 3 |

**Event 5 (the hook).** Push after `APPLY`; the next 02:30 UTC run prints `Attributed 0 accounts` (or the day's new converts); `heroku logs` shows the line after the recompute summary. **Event 6 (6c-api):** `GET /kpis/headshot_hosts` as owner returns the read-out's rows exactly, and as scheduler it is refused. The read-out's distinct attendee total equals `count(DISTINCT account_id)` over active event orders **with a non-NULL shoot date** on active, non-internal accounts (2,332 on the restore, M12b's 2,333 less 1534, less at most one account for event 1333's NULL-dated order, G9); converts per host ≤ attendees; the association rows' converts ≥ the 6b writes per host (converts include the already-sourced); already-customers per host sum to the 149 after-buyers of M7a plus the sourced and the no-paid-listing populations the memo names. **Event 7 (6c-ops):** `git tag v9.66.0 && npm run deploy:prod` on a clean `main`. On site as owner, the KPIs page shows the panel, and its rows and totals match event 6's curl. The no-host row is last.

### Runbooks (written in the write-back, in the slice 4 shape)

`docs/runbooks/deploy-account-classification-6-hosts.md` — events 1, 2 and 3: no window at any step; event 1's push and migrate, the production read-out and the STOP for the map; event 2's push, migrate, the invariant table and the curls; the ops release and the cutoff clean-up; rollback: `heroku rollback` keeps the columns (additive), ops first. `docs/runbooks/deploy-account-classification-6-attribution.md` — events 4 to 7: dry run → STOP → `APPLY` → second dry run → invariants → spot checks → the KPI before/after table → the hook push → the ROI read-out and endpoint → the ops panel release; the reversal keyed on (1, `<stamp>`).

### Risks

- **The map is judgment over 196 rows and the production list may have grown.** The read-out ships in event 1 and runs in production before the map is written (the first draft of this plan had it running before its own deploy — the adversarial pass caught it); the cutoff rule (G5) keeps a late event from failing `db:migrate`; a wrong host is fixed from the ops edit page after event 3.
- **The contract's dating rule under-credits fast converts** (OQ1). Delivery-log dates trail the event by 1–30 days, so an attendee who buys within that lag is an after-buyer: 3 accounts on the restore, 2 of them NSDCR writes lost. Every new attendee carries the same distortion until `OrderHeadshot` stamps the event date (Out of scope 2). The memo's "credited only under the event date" line shows the cost on each run, and the S2-shape spec and spot check 1467 pin the rule.
- **The ninth type touches a frozen hash two repos copy** (OQ2). `organizations:audit_types` and its spec may enumerate the hash; checked in the loop. The ops `OrganizationTypes` must land in 9.65.0 or the organizations page cannot show hosts.
- **A `Validators.required` control holding `null`** silently blocks every save of an Insight-hosted event — G8's object value is the whole fix; the Cypress `null` assertion is the guard.
- **The ops window between events 1 and 3** creates ambiguous NULL hosts; G5's list closes it by hand.
- **9.65.0 against a rolled-back API** drops the host on create (unpermitted param) and blocks saves on edit; roll ops back first; the silent-update window of 4d's G19 applies.
- **The NULL trap** on the internal exclusion (G10) would write 0 of the 2,682 untyped accounts' share; the named example and planned = written catch it.
- **The nightly hook deployed early** would write without the memo; it is its own commit and push behind `APPLY` (G15), and the runbook names the order.
- **Headshot-flow name collisions** (Out of scope 3) can put an event order on the wrong account; the memo's 376 "matched existing" accounts are where to look if a spot check surprises.
- **The organization autocomplete returns soft-deleted rows**; the API's 422 is the backstop; 7 such rows exist (M5c).
- **The order-page Cypress spec** needs the order edit page's stub set; if it grows past the file limit, the create block's coverage moves to a second file rather than being dropped.
- **`organizationName` on the index is an N+1 without the preload** (G6); invariant 9 and the request spec's query-count example are the guards. The same holds for `marketingSourceName` on the organizations index (G19).
- **The organization payload reaches agents** through the session's `broker` block. An ungated `marketingSourceId` would leak an internal attribution to customers. G19's role check and its absent-key example are the guard.
- **No `release:` phase** means every `db:migrate` is a hand step after the push, and a raise in the backfill is a second push, not a rollback.

### Write-back (part of the slice)

- **Host audit document** `docs/architecture/marketing-event-host-audit-<date>.md` (G3) — the production run, the draft token table, the settled map, OQ3/OQ4's answers.
- **Production memo** `docs/architecture/event-attribution-memo-<date>-production.md` — the `APPLY` run, the hand-over copy; **ROI document** `headshot-host-roi-<date>.md`.
- **v10 amendment, part 1 (after event 3):** §3.2 — hosts live on the column, the read-out and the map; §3.3 — the sentence about hosts existing as sources corrected (sources yes, organizations no, now created); §3.5 — the strong_migrations shape, the ninth type, the map keyed by event id with host **names** as values and the run-time resolution rule, the cutoff rule, `organizationName` and the index preload, the two forms and the picker, and the read-only, role-gated `marketingSourceId` / `marketingSourceName` on the organization payload, with writes still migration-only (OQ7); §9 slice 6 row split 6a-i / 6a-ii / 6a-ops / 6b / 6c-api / 6c-ops with status, and the "into PSAR, NAHREP, NARPM" sentence corrected (no NAHREP or NARPM event exists); a §18 change log.
- **v10 part 2 (after `APPLY`):** §5.5 step 2 **kept** (OQ1) and amended with three things: a NULL-dated event order is excluded; the comparison is strict; the delivery-date distortion is recorded with S2's three accounts and the memo line that measures it. Also the no-fallback rule; the universe's `NOT IN` form; `marketing_source_other` cleared on write and the `other` refusal; §6 step 4 marked done with the hook's placement and failure rule; §9's "Slice 6b is visible" paragraph with the measured move; §5.5's last paragraph worded to state the attendee, convert and already-customer rules (OQ10), with the owner-only `GET /kpis/headshot_hosts` and its ops panel as the read-out's surfaces (OQ5); the follow-ons recorded (`OrderHeadshot` stamping the event date on new event orders; `headshot_event_report` re-pointed; the autocomplete filter; the source-clearing gap).
- **Codebase notes:** a "Marketing events and hosts" section (`db/schema.rb` rows, `marketing_event.rb`, `order_headshot.rb:45–53, 69–102`, the controller and helper lines, the four migrations, the two rake files, `event_attribution.rb`, `headshot_host_roi.rb`, the specs, the ops picker and the two forms, `organization.model.ts:48–58`, `organizations_helper.rb`'s role-gated source fields, `KpisController#headshot_hosts` and the ops KPI panel); the `metrics.rake` row extended; "Branch and deploy state" rewritten.
- **Contract spec:** commit 10.

### Gates, and traps for the adversarial review

Gates per the slice-cut table. Reviews: `predeploy-review-rails` over each API branch, `predeploy-review-angular` over the ops branch, each with the Codex pass over an rsync copy of the tree (the §14/§15 process notes). Traps beyond the skill's list:

*Hosts (6a-i, 6a-ii):* `add_reference … foreign_key: true` or a non-concurrent index; any association, validation or helper change in event 1's commits; a backfill keyed by token or carrying a name parser; a map that resolves a host by `ILIKE`; the integer 2, 3 or 4 for a source instead of its key; a `down` that soft-deletes organizations; a raise for post-cutoff events, or no raise for pre-cutoff ones; `type_of` 2 on an association; a validation that 422s an absent `organization_id`; `organizationName` on the index without `includes(:organization)` (or an equivalent single query); a factory default on `marketing_events.organization_id`; an autoloaded constant at rake file scope; `marketingSourceId` on the organization payload outside the admin/scheduler check, as the integer instead of the public id, sent as `null` to an agent instead of omitted, or permitted on write; the organizations index without the `marketing_source` preload.

*Ops (6a-ops):* `Validators.required` on a control whose Insight value is `null`; a `'null'` string sentinel; the picker built on `OrganizationService.autocomplete` or `AutocompleteComponent`; a type filter on the host search; a new NgRx slice; only one of the two forms changed; a component test in Vitest; a release from a dirty tree or without the ninth type.

*Attribution (6b):* the event order or the listing dated by anything but `Order.shoot_date_sql` (OQ1), including a quiet "fix" to `marketing_events.scheduled_at`; a NULL-dated event order ranked as latest or as before; `account_type <> 7`; a fallback to an earlier hosted event; a non-strict comparison; a write reachable without `APPLY=true`, outside the transaction, without the WHERE re-check, or without `updated_by_id` and one stamp; `marketing_source_other` left as-is on write; the hook inside `RecomputeAll` or merged into the calculator; the hook in the same push as the first `APPLY`; a memo whose KPI prediction uses a different paid predicate than `MarketingSourceMetricsService`; a re-derived shoot predicate.

*ROI (6c):* attendees counted per event or per token; the report reading `accounts.marketing_source_id` to find converts; internal accounts included.

*ROI (6c), continued:* an after-buyer counted as a convert; the endpoint re-deriving anything `HeadshotHostRoi` already computes; the endpoint reachable by any role but owner; the panel with an NgRx slice, or hiding the no-host row.

*All:* a spec whose deliberate-break red output was not shown; two "v10" commits.

### Decisions taken (Dan, 2026-10-06)

The draft put these eleven questions with a recommendation each and proceeded on the recommendations while Dan was offline. Dan answered them on 2026-10-06. Eight confirm the recommendation; **OQ1, OQ5 and OQ7 differ** and are folded through the sections the table names.

1. **OQ1 — How is a headshot-event order dated? Keep `Order.shoot_date_sql`, as §5.5 says.** The draft recommended the event's `scheduled_at` with a fallback chain. That alternative was measured (M7f, S2) and is not adopted. Consequences, all folded in:
   - G9 follows the contract's text, and an event order with a NULL shoot date (event 1333's one order) is excluded.
   - The spec plan drops the "fast convert" canary and the fallback examples, and pins the S2 shape as not credited.
   - Spot check 1467 expects NULL. Credited accounts fall 203 → 200, and the first write falls 83 → 81 (91 with event 29 under NSDCR, OQ11).
   - v10 does not rewrite §5.5 step 2.
   - Out of scope 2 (stamping `scheduled_at` on new headshot orders) returns as a recorded gap, because without it the delivery-date distortion continues for every new attendee.
2. **OQ2 — Hosts are typed by a new `association: 9`**, in both repos and in the same release pair (API event 1, ops 9.65.0). The only existing candidate is `brokerage`, and the slice 4 `agent` tier and `User#update_broker` both read `type_of = 2`.
3. **OQ3 — NSDCAR and NSDCR are one organization, "NSDCR", sourced `nsdcr_event`.** NSDCAR is the association's old name.
4. **OQ4 — Sources for PSAR, NSDCR and SDAR only; no new `marketing_sources` rows in this slice.** The other hosts keep `marketing_source_id` NULL, which §3.5 allows. 107 credited accounts stay NULL with a host that has no source; the memo lists them and the ROI read-out counts them.
5. **OQ5 — Build the endpoint and panel now**, not as a follow-on. That means an API commit (an action in `kpis_controller.rb`'s owner-only shape, a jbuilder and a request spec) and an ops commit (a standalone OnPush component beside `kpis/components/marketing-source/`, with Cypress). ESTIMATE +1–2 days. 6c becomes its own deploy pair (events 6 and 7). The ops release is 9.66.0, or it rides 9.65.0 if timed together (G20).
6. **OQ6 — The nightly hook is its own commit and push, strictly after `APPLY`** (G15; the 4b → 4e pattern).
7. **OQ7 — `organizations.marketing_source_id` gets a wire field: two helper lines in `organizations_helper.rb`, admin and scheduler only.** The organization payload is embedded widely, including the session's broker block, so the audience is gated (G19). There is no ops form field and no write path (Out of scope 5).
8. **OQ8 — The backfill raises only for events created before `MAP_CUTOFF`** (G5). `MAP_CUTOFF` is the production read-out's timestamp. The read-out's post-backfill section lists events "unmapped since the cutoff", and Dan sets those hosts from the ops edit page after 9.65.0.
9. **OQ9 — The API does not require the `organizationId` key.** An absent key or a present `null` is stored as NULL. A present id must resolve to an active organization or the API returns 422 (G6). Ops is the only client, and the form enforces the choice.
10. **OQ10 — The ROI attendee, convert and already-customer rules as pinned** (G17). Every active, non-internal account with an event order lands under exactly one host:
    - the host of its last event order before its first paid listing shoot, or
    - when no event order precedes that shoot, the host of its latest event order.

    Converts are attendees whose first paid listing shoot is after the crediting event. Already customers are attendees whose first paid listing shoot is before any event they attended. They get a separate column, are never counted as converts and are never dropped from attendees. The totals check (hosts + no host = distinct attendees) and the after-buyer spec with its deliberate break stay. v10 words §5.5's last paragraph to state the three rules.
11. **OQ11 — Hosts for the 66 non-association events are as recommended.** Events map to existing organizations where M5f found one, and the migration creates `brokerage` (2) or `lender` (3) rows for the rest. Insight's own rows get `nil`: 14 Marketing, 31 Aerial Marketing, 35 Glen Oaks Escrow Booth, 2 Test Marketing Event and 73 Misc. **Settled 2026-10-06: 29 "Expo 2016-06-16" is hosted by NSDCR, and 147 "Maha Staging / Scripps Ranch Caravan" was hosted by Insight Photos (`nil`).** Event 29 is the last touch for 10 credited accounts, which raises the first write from 81 to 91. Event 147 is the last touch for 2, which stay NULL as "latest event unhosted" (M15). `nil` on a brokerage-hosted event would mean "no outside host", which §3.5 defines otherwise.

| # | Decision | Taken | Where it lands | Reversibility |
| :-- | :-- | :-- | :-- | :-- |
| 1 | Event orders dated by `Order.shoot_date_sql`; NULL-dated orders excluded | Contract's text (**changed** from the draft) | G9, G13's memo line, spec plan, spot check 1467, Out of scope 2, v10 §5.5 | Code until the first `APPLY`; after it, the batch stamp reverses the writes in one statement |
| 2 | Hosts typed `association: 9` in both repos | Yes | G2, commits 1 and 6, approach table | Moderate: rows carry the value and ops displays it; undoing is a migration plus an ops release |
| 3 | NSDCAR and NSDCR are one organization, "NSDCR", sourced `nsdcr_event` | Yes | G4's map, the 91, spot checks 77 / 214 | **Hard after `APPLY`**: 42 accounts sourced; before it, a map edit |
| 4 | Sources for PSAR, NSDCR, SDAR only; no new sources | Yes | G4's `SOURCE_BY_HOST`, the 107 unsourced credits, Out of scope 6 | Easy: a host given a source later is picked up by the next nightly run |
| 5 | 6c builds the read-out, the owner-only endpoint and the ops panel | Endpoint and panel now (**changed**) | G17, G20, slice cut 6c-api / 6c-ops, commits 11, 11a, 13, 14, events 6 and 7 | Easy: additive |
| 6 | The nightly hook as its own push after `APPLY` | Yes | G15, commit 12, event 5 | Easy |
| 7 | `organizations.marketing_source_id` on the wire, read-only, admin/scheduler only | Wire field (**changed**) | G19, Scope 4, Out of scope 5, commit 5a, event 2 invariant 10 | Easy |
| 8 | The migration raises for pre-cutoff events only | Yes | G5, the migration's green path | Easy |
| 9 | An absent `organizationId` is NULL at the API | Yes | G6, request spec | Easy |
| 10 | ROI attendee, convert and already-customer rules as pinned | Yes | G17, spec plan, v10 §5.5 last paragraph | Easy: a read-out |
| 11 | Existing organizations mapped, brokerage/lender rows created for the rest, `nil` for Insight's own (147 among them); 29 → NSDCR | Yes | G4's `HOSTS` and map, the read-out STOP | **Moderate to hard**: created organizations are soft-delete only and events repointed by hand |

### Smaller ambiguities pinned in passing

| # | Question | Answer | Status | If the answer changes |
| :-- | :-- | :-- | :-- | :-- |
| Q12 | Where does the plan live? | `docs/plans/account-classification-slice-6.md` | Done 2026-10-06 | — |
| Q13 | Which endpoint feeds the host picker? | `GET /organizations/autocomplete?term=`, because the event routes admit the owner role and `GET /organizations` would 403 it (G7). Soft-deleted organizations can appear in the panel, with the API's 422 as the backstop | Confirmed | — |
| Q14 | Is any active organization a valid host at the API? | Yes. Brokerage-hosted events are current practice (2024–2026 rows), and the picker searches all organizations (G6, G7) | Confirmed | — |
| Q15 | Does the derivation filter the event's own `status_type`? | No. A soft-deleted event still happened; the order's and the account's status are filtered. 0 soft-deleted events exist today (G10, with a spec example) | Confirmed | One `AND marketing_events.status_type = 1`, and the spec example flips |
| Q16 | Does the backfill's `down` remove the organizations it created? | No. `down` NULLs both columns and leaves the rows (G4) | Confirmed | `down` soft-deletes rows with `created_by_id = 1`, a name in `HOSTS` and no `accounts_organizations` edge. That reversal can still strand an edited row |
| Q17 | Does 6c-api ride event 4's push or its own? | Its own event 6, folded into event 4's push if ready in time | Confirmed | Only the runbook's event list changes |
| Q18 | Does the write clear `marketing_source_other`, and does the derivation refuse a source keyed `other`? | Both (G12) | Confirmed | If the column is left alone: drop it from the UPDATE, drop the spec's fixture example, and accept a known 422 on affected accounts' next edit. The dry-run memo prints how many credited accounts carry the text |

Settled by the standing instruction, not asked: the session leaves the tree uncommitted, one concern per unit, and Dan commits.

### Next phase

Carve four slice prompts from this document in `slice-implementation`'s template:
- **6a-api**, events 1 and 2;
- **6a-ops**, event 3;
- **6b with 6c-api**, events 4–6;
- **6c-ops**, event 7.

The implementation sessions then run in this order:
1. Phase 0 re-baselines Appendix A against the day's sync, including the 91 / 107 / 2 split under the shoot date and the attendee total less the NULL-dated order. It also re-checks the ops version.
2. **6a-i loop:** the type, then the two reference migrations with `migrate`/`rollback`/`migrate` pasted, then the read-out red/green/break. STOP before event 1. Then the production read-out and the map STOP.
3. **6a-ii loop:** the backfill migration with its three breaks and the cutoff green path, then the models and the event API with the preload, then the organization payload's role-gated fields. STOP before event 2.
4. **Ops:** the type, the picker with Vitest, the two forms, Cypress, build, bump. STOP before event 3.
5. **Attribution branch:**
   - the service, red on the S2-shape example, the NULL-date break, the no-fallback break, the NULL-trap break and the tiebreak break;
   - the memo task; the contract block;
   - the ROI service with the after-buyer break, and its endpoint;
   - the dry run on the sync as verification, then two review rounds.

   STOP before event 4, then the production dry run, the `APPLY` STOP, the hook push, and event 6.
6. **6c-ops:** the panel with Cypress. STOP before event 7.
7. The write-back.

---

## Appendix A — the queries behind every number (dev DB, production restore, 2026-10-02)

Every script ran as `cd apps/insgt-api && bin/rails runner <file>` opening with `ActiveRecord::Base.connection.execute("SET default_transaction_read_only = on")`. `<SD>` is `Order.shoot_date_sql` and `<PAID>` is `Order.qualifying_parents.where.not(paid_at: nil).select(…).to_sql`, each printed once by the script and pasted verbatim; the predicates are the app's, never re-derived.

| Id | Query | Output |
| :-- | :-- | :-- |
| M1 | `SELECT status_type, count(*) FROM marketing_events GROUP BY 1`; by year of `created_at` / `scheduled_at`; `order_id IS NULL`; events with 0 (active) orders | 196 active, 0 deleted; 2015 13 … 2026 21; `order_id` NULL 147 / set 49; 4 with no orders, 5 with no active orders; 3 with `scheduled_at` NULL |
| M2 | every event with id, name, dates, `order_id`, active orders, order-type keys (`LEFT JOIN orders … GROUP BY me.id ORDER BY created_at`) | 196 rows (in the host audit document); event orders are `free_web_portrait` throughout; typos 144 "2012-12-10" (2021), 73 "2017-02-12" (2018), 173 "2-24-02-09" |
| M3 | Ruby token parse (dates and "Headshots"/"WebPortraits" stripped, leading acronym from PSAR NSDCAR NSDCR SDAR SDREA YPN) | PSAR 55, NSDCAR 41, SDAR 21, NSDCR 11, SDREA 1, YPN 1; 66 non-acronym names listed |
| M4 | `SELECT ms.id, ms.key, …, count(a.id) FILTER (WHERE a.status_type = 1) FROM marketing_sources ms LEFT JOIN accounts a ON a.marketing_source_id = ms.id GROUP BY ms.id` | 17 active rows; 2 `nsdcr_event` 6, 3 `psar_event` 20, 4 `sdar_event` 7, 100 `nahrep` 2, 67 `narpm` 1, 1 `google_search` 61, 11 `realtor_referral` 40 … |
| M5a–e | `organizations` by `~* '(PSAR|NSDCA?R|SDAR|SDREA|NAHREP|NARPM|YPN|…)'`; `%association%`/`%realtors%`; `type_of, status_type` counts; types 1 and 7 listed; word-bounded acronyms | no host organization exists (the only hits are "Broad…" substrings and 2017 ROA California Inc.); `%association%` 0; active types 1→8, 2→643, 5→33, 6→27, 7→1 |
| M5f | `organizations.name ILIKE '%' || token || '%'` per non-acronym token | the matches in Measurements; 17 tokens with none |
| M6 | `count(*) FILTER (…)` over `accounts`: active; source NULL; internal; `account_type` NULL; the universe | 4144 · 3965 · 11 · 2682 · **3955** |
| M7a | the CTE chain (universe → `ev` with `<SD>` → `paid` → `first_paid` `DISTINCT ON` → `credit` `DISTINCT ON … WHERE (ev.sd, ev.created_at, ev.id) < (fp.sd, fp.created_at, fp.id) ORDER BY … DESC`) | with event order 2306; with a paid listing 349; **credited 200**; last event overall before first paid 155; attended only after 149; credited and also after 45; same-timestamp ties 0; same calendar day 1; NULL-dated event orders among paid accounts 0 |
| M7b | `SELECT token, count(*) FROM credit GROUP BY 1` | NSDCAR 42, NSDCR 18, PSAR 13, SDAR 8, SDREA 4, YPN 1, Expo 10, Windermere / RB 9, New Palace 8 … |
| M7c | attended-after-buying by the last event's token | NSDCR 36, NSDCAR 29, SDAR 12, PSAR 11, … |
| M7d | gap crediting event → first paid listing | < 30 d 31 · 30–180 d 54 · 180–365 d 29 · 1–3 y 46 · 3 y+ 40 |
| M7e | credited by year of first paid listing | 2015 6 · 2016 23 · 2017 30 · 2018 28 · 2019 19 · 2020 11 · 2021 11 · 2022 10 · 2023 12 · 2024 14 · 2025 22 · 2026 14 |
| M7f | the same with `ev.evd = me.scheduled_at` in place of `<SD>` | by shoot date 200 · by event date 203 · only shoot date 0 · only event date 3 |
| M8a–d | event orders by type and status; `scheduled_at` NULL / fallback / `<SD>` NULL / `paid_at` set; the NULL-dated order; lag `<SD> − me.scheduled_at` | 2654 active + 9 deleted type 3, 2 deleted type 2; **2654 / 2653 / 1 / 81**; event 1333's one order; lag: before 1, < 1 d 62, 1–7 d 1983, 7–30 d 597, 30 d+ 10, NULL 1 |
| M9a–d | account `created_at` vs order `created_at` buckets; the container-order subset; accounts with an event order by status / source / internal; their sources | matched 376 (480 orders) · created 2157 · anomaly 13; 2024-08+ 141 / 712; source NULL 2306 active, sourced 26, internal 1; `psar_event` 16, `sdar_event` 7, `nsdcr_event` 2, `other` 1 |
| M10 | `marketing_event_imports` | 135 rows, max `created_at` 2023-10-27, 132 distinct events |
| M11a–c | events with any non-headshot order type; order types matching headshot/portrait/paparazzi; container orders' types | only event 2 (Test); 3, 12, 19, 23, 73; all 49 containers type 73 |
| M12, M12b | per token: distinct attendees, converts (any paid listing ever), converts' `lifetime_value_cents` (APPROXIMATE); the distinct totals | PSAR 807 / 31 / $84,854; NSDCAR 446 / 91 / $147,554; SDAR 300 / 22 / $43,843; NSDCR 193 / 73 / $159,991; … ; all events 2333 / 354 / $924,229 |
| M13 | `max(version)`, `max(computed_at)`, active accounts | 20260912120001 · 2026-10-01 02:32:43 UTC · 4144 |
| M14 | `SELECT count(*) FROM orders`; `… FROM order_logs`; `… FROM organizations` (= M5c's rows summed) | 29,410 · 386,559 · 719 (712 active, 7 soft-deleted) |
| S1 | the M7 chain with the event date (`me.scheduled_at < fp.sd`, ordered `evd DESC, created_at DESC, id DESC`), association tokens, first 14 by id | 77 (NSDCAR 2020-02-03 → paid 2020-07-25), 214, 513, 572 (SDAR 2016-05-20 → 2018-07-11), 619, 805, 960, 1059, 1137, 1138, 1195, 1204, 1263, 1320; non-association: 10, 12, 17, 18, 21, 37 (Windermere) |
| S2 | credited under the event date and not under `<SD>` | **996** (Coldwell Banker Vista 2017-03-21, delivered 03-28, paid listing 03-22), **1467** (NSDCAR 2018-01-30, delivered 02-07, listing 02-02), **1516** (NSDCAR 2018-03-15, delivered 03-22, listing 03-20) |
| S3 | internal accounts with an event order; already-sourced accounts with one (first 8); active event orders with no completed log; deleted events / containers | 1534; 823 `nsdcr_event` (first event 2016-10-10), 3076, 8906, 11230 `psar_event`, 11650–11653 `sdar_event`; 1; 0 / 0 |
| S4 | distinct container-order accounts; attended only after buying (first 5) | 2 InsightPhotos 42, 2275 "NSDCR NSDCR" 3, 11058 2, 2836 "PSAR" 1, 11649 1; 47 (paid 2015-08-27, attended 2016-06-16), 50, 51, 64, 76 |
| S5 | credit by token under the event date with summed lifetime value; credited accounts with more than one hosted event before buying; `MarketingSourceMetricsService.call` | other 115 ($286,096) · NSDCAR 44 · NSDCR 18 · PSAR 13 · SDAR 8 · SDREA 4 · YPN 1; 32; `total_accounts` 4133, `attributed_accounts` 178, 4.3%, gross 372,928,500; NSDCR event 6 / PSAR event 20 / SDAR event 7 |
| M15 | events 29 and 147 by id; the M7a credit chain (shoot date) counted by crediting event: 29, 147, and the `nil` set {14, 31, 35, 2, 73, 147} (2026-10-06) | 29 "Expo 2016-06-16" (79 active orders), 147 "Maha Staging / Scripps Ranch Caravan" (14); credited 200 (M7a reproduced) · via 29: 10 · via 147: 2 · via the `nil` set: 2 |
