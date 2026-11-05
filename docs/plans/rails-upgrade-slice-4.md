# Rails upgrade — slice 4: `belongs_to` optionality follows column nullability

**Repo:** `insgt-api`. Platform repo for this plan, the runbook and the write-back (decision 1).
**Contract:** `docs/architecture/rails-upgrade.md` **v6** (2026-10-30; read from the platform repo's branch `docs/rails-upgrade-slice-3` at `14a9ef8`, five commits ahead of `main`, which is where the v6 amendment sits) — §4.5 (the slice), §4.0 (the kit), §2 (sequencing), §5 R2, §7 OD10, §8 item 15. Brief: `docs/architecture/rails-upgrade-slices/slice-4.md`.
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails` (reference only in this session; the review runs in the implementation session).
**Status:** **Implemented and verified in development 2026-11-03; two review rounds done; round 2's open finding fixed as commit 5 on Dan's decision; `master` at v669 (Rails 8.1.4.1) merged in 2026-11-05 as `3f67af13`** — see "Implementation record" at the end; the rest of this file is the plan as approved. **Approved 2026-11-02 by Dan** — the nine open questions as recommended, with modifications A–H, recorded in the next section and folded in below. Moved to the platform repo on `docs/rails-upgrade-slice-4` off `main` (decision 1); insgt-api's `chore/rails-upgrade-slice-4` re-created from `master` with no commit. Implementation starts Tue 2026-11-03 once slice 3's SH reads clean. Nothing from the implementation loop has run: no contract spec committed, no model or config edit, no gem or lock change. Every probe below ran either in a throwaway rsync copy of the tree (`/tmp/claude-1000/-workspace-apps-insgt-api/fbba7498-22e5-4bc2-a3b7-860881119ded/scratchpad/probe/`, no `.git`) or as a spec file in that scratchpad run against the real tree; `git status` is clean in both repos at the STOP.
**Survey date:** 2026-11-02, against insgt-api `master` **`05e3fd42`** — the merge of slice 3, deployed this morning as **v666** (05:12:27 PST; `deploy-rails-upgrade-3.md`, Deploy log). **Base SHA for the branch: `05e3fd42`.**
**Expected production versions at the push:** Rails `8.1.4.1` (v669, the 2026-11-05 security bump; `8.1.4` when this was written), `loaded_config_version` `7.2`, Ruby 3.4.12, PostgreSQL 15, `StrongMigrations.target_version = 15` (§2 item 6); release v669 (v666 when this was written), or whatever `master` carries on Mon 2026-11-09 — if `master` moves, the suite runs on the merge first and the rollback target moves with it (slices 1–3's practice).
**The prompt's three pre-survey checks:** (1) `Gemfile.lock:380` `rails (8.1.4)`; `config/application.rb:12` `config.load_defaults 7.2`; `bin/rails runner` printed `8.1.4` and `loaded_config_version` `7.2`. (2) §4.5 exists in v6 with the four commits, scopes 1–5, S12, S13 and OD10's recommendation (quoted verbatim under "Gaps pinned" 1). (3) `app/models/area.rb:7` is `belongs_to :state, optional: true`. **The shim block has moved:** `config/initializers/new_framework_defaults.rb:15–16` is the comment and `Rails.application.config.active_record.belongs_to_required_by_default = false`, not 18–20 — slice 1's `a59df0b0` (2026-10-26, "stop forcing the pre-Ruby 2.4 to_time behavior") deleted the three lines above it, and the codebase notes' row for the file already reads 15–16 ("was 19–20"). Every "18–20" in the brief and "`:20`" in §4.5 means **15–16** below. The file is 16 lines; after the deletion, 14 (lines 9–13, the two CSRF lines, stay — out of scope).

Facts are stated with their source. ASSUMPTION, ESTIMATE and UNVERIFIED are labelled. Nothing below "should work": it ran, or it is under Unverified.

## Approval — decisions and modifications (Dan, 2026-11-02)

All nine open questions answered as recommended; the Open questions section carries each answer in place. Decisions that changed the plan's text are folded in below and marked.

1. **Plan location — moved.** This file lives in the platform repo on `docs/rails-upgrade-slice-4` off `main` (`c55807c`), beside slices 1–3's plans; insgt-api's `chore/rails-upgrade-slice-4` was deleted and re-created from `master` with no commit. `master` had not moved: `origin/master` = `05e3fd42` on 2026-11-02, so the base checks and the reflection table stand.
2. **OD10 — confirmed, two conditions, both met.** (a) The contract block finds the shared column structurally — the reflections grouped by `[model, foreign_key]`, groups of size > 1 — and names no model: the canonical-fixture example moved out of the contract file into `spec/models/tags_resource_spec.rb`, so the block is **five** examples, re-run through all four commit states and the deliberate breaks (the per-commit plan pastes the new outputs). (b) The validation runs under `new_record? || will_save_change_to_resource_id? || will_save_change_to_resource_type?` — the condition `builder/belongs_to.rb:148–163` gives a required `belongs_to` — proven by the model spec's fourth example (a row whose user was hard-deleted still soft-deletes) and by the `sql_for` runs (no SELECT on a save that does not touch the key).
3. **Commit 4 — confirmed, with a premise corrected.** The pair's `optional: true` on `TagsResource#user` and `#property` already exists on `master` (`tags_resource.rb:7–8`; fact 1's two explicit options on `NOT NULL` columns), so no commit adds or moves it: commit 3 stays the three nullable associations, no HEAD has the pair required, and commit 4 is the shim deletion, the validation and the two spec files. Commit 4's Tier 3 body names the shared-column exception as the non-obvious decision.
4. **S12 on `POST /areas_properties` — yes; no deliberate 500 against production before the push — yes.** The runbook carries the exact curl with its auth, the expected `422` and `{"errors":["Property must exist"]}`; a `500` there after the push is the rollback signal.
5. **Dangling keys — record and proceed if production matches the restore**, with the rule made exact in Gaps pinned 3: (a) the restore's timestamp recorded (C below); (b) STOP if production shows rows on any column outside the three predicted, or if any of the three counts exceeds the restore's — a higher count is a live writer; counts at or below are recorded, not stopped on; (c) S13 pins the three observed counts; (d) the three sets become one §8 cleanup item. Why the 27 zeros exist is answered under C.
6. **Red HEADs at commits 1–3 — accepted.** Each carries a Tier 2 body naming its red count — now **3, 2, 1** (decision 2a moved one example out of the contract file) — and that it is §4.5's spec-first design; the suite minus the contract file is green at each HEAD; and each of commits 1–3 shows a deliberate break on an example that is green at that HEAD (commit 1: the traversal floor raised; commit 2: `Area#state` restored re-reddens the columnless example; commit 3: `Area#area_type`'s option removed re-reddens the nullability example).
7. **Doubled message on 30 models — accepted and recorded.** The redundant column validators come out on their own branch after slice 5 closes, as a §8 item, not inside the upgrade sequence.
8. **`sql_for` stays in the plan.**
9. **Timing — confirmed:** build Tue 11-03 once slice 3's SH reads clean, review Thu 11-05, push Mon 11-09 09:00–11:30 PT; the push gated on two quiet weekdays, satisfied Thursday morning. Estimate 7 h accepted; the extra hour is OD10's photo type (write-back item).

Modifications, with their results:

- **A. Shim lines.** `config/initializers/new_framework_defaults.rb` is 16 lines; lines 13–16 with `cat -A` (`$` marks each line end; there is no line 17):

  ```
  13  Rails.application.config.action_controller.forgery_protection_origin_check = false$
  14  $
  15  # Require `belongs_to` associations by default. Previous versions had false.$
  16  Rails.application.config.active_record.belongs_to_required_by_default = false$
  ```

  **Lines 14–16 go.** Line 15 is the comment that belongs to line 16 and to nothing else; line 14 is the blank separator after the CSRF setting, deleted so the file does not end on a blank line. Line 13, the second CSRF line, is untouched and becomes the last line: the file ends at 13 lines (probe copy after the deletion: `wc -l` → 13, last line the `forgery_protection_origin_check` setting). No orphan comment, no line from a neighbouring setting.
- **B. Column defaults.** No `NOT NULL` FK column behind a `belongs_to` has a default: the runner's `column_default` is `nil` for all 49, and `grep -n -E 't\.(integer|bigint) "[a-z_]+_id".*default' db/schema.rb` prints one line, `:435` `listings.property_type_id` — nullable, `default: 1`, already optional after commit 3. So no required `belongs_to` can be bypassed by a default-populated key, the 17 count stands, and §8 item 15 gets no "drop the default" entry.
- **C. Dangling sets — provenance.** The restore: `tmp/latest-2026-10-30.dump`, written 2026-10-30 16:17 UTC; its latest `order_logs` row is 2026-10-30 16:12:26 UTC, the latest `orders.updated_at` 16:06:44, the latest `photos.created_at` 14:21:40. Per set:
  - `orders.account_id` (2 rows): order 2827 — status 2, created 2016-11-02 23:14 UTC, updated 2016-12-09 by user 2, account 873; order 4302 — status 1, created 2017-07-05 13:56 UTC, updated the same minute by user 1, account 1190. Accounts 873 and 1190 are absent while their neighbours exist (4 of ids 870–876, 6 of 1187–1193; max account id 12,435): two accounts hard-deleted in 2016–2017. No `Account` hard-delete path exists in `app/` or `lib/` today (`grep -rn -E "\.(delete_all|destroy_all)\b" app lib`: only `tags_resources`, `order_services` and `roles`). Historical; no live writer.
  - `orders_users.user_id = 0` (27 rows): **all `role_id` 3, `system_processor`**; created 2017-07-07 … 2019-05-02 UTC by users 1, 2, 4 and 295; 24 active, 3 soft-deleted (last touched 2019-03-15); **none after 2019-06-01**. Not a column default (B: `orders_users.user_id` has none). Not a code literal: `grep -rn -E "user_id: 0\b|user_id = 0\b|\.user_id = 0\b" app lib config` → empty, and `git log -S"user_id: 0"` / `-S"user_id = 0"` over `app lib` → no commit, ever. The writer was the pre-2019 processor-assignment path — `orders_user.rb`'s first changes after 2016 are `01b36ec9` (2019-06-21, "Added catch for order user creation not working with new ui") and `1906190e` (2019-06-27), and the last zero was written 2019-05-02 — a nil processor coerced to `0` by the old UI's payload. Historical import; no live writer.
  - photo-typed `tags_resources.resource_id` (32 rows): one contiguous block, photo ids 549637–549668; one tag (`tags` 69, name `91942`, category 9 — the zip-code tag `tag_with_zip` writes, `photo.rb:230–256`, `after_create` at `:65`); created by user 1 between 2025-06-17 22:21:18 and 22:21:41 UTC; all active, never updated. The 100 photos within ±50 of the block exist; the 32 do not. Consistent with one order's 32 photos created (so `tag_with_zip` wrote the tags with `created_by_id: 1`) and then removed outside the soft-delete convention: no photo hard-delete path exists in `app/` or `lib/` (the grep above), and no commit touched `photo.rb`, `photo_tag_sync_service.rb` or `tags_resource.rb` between 2025-06-14 and 2025-06-20. Historical; no live writer.
  - So decision 5(b)'s STOP — a count above the restore's — is not expected on Thursday; a higher count would contradict all three provenances and is found before the window.
- **D. Production reads twice.** The three read-only queries run on the Mac at Thursday's review (2026-11-05) and again the morning of the push (Mon 11-09); both pasted under Production, and the runbook carries both slots.
- **E. Honeybadger baseline for the 17.** Not reachable from the container; the search is under Production with its slot for Dan, to be read before Thursday's review: every hit is a production path that becomes `RecordInvalid`/422 after the slice, zero hits means the 17 are unexercised in production, and SH's "must exist" watch is read against the result.
- **F. `TagsResource` creation cost.** Every path creates one row at a time, through validations: `TagsResource.create` (`photo.rb:251`, `:300`), `TagsResource.new(…).save(current_user)` (`create_photo_tag` `:22–28`, `create_user_tag` `:37–44`, `tags_resources_controller.rb:14–15`); no `insert_all`, `upsert_all` or `has_many <<` anywhere (`grep -rn -E "TagsResource\.(create|create!|insert_all|upsert_all|new)|tags_resources\s*<<" app lib`). Measured with `sql_for` on `create_photo_tag` and `create_user_tag`, before on `master` and after in the probe copy: **1 → 3 SELECTs per row**. The pre-existing statement is the `tag_id` uniqueness check; the two new ones are `SELECT "tags".* … WHERE "tags"."id" = $1 … LIMIT $2` from the framework's now-required `belongs_to :tag` (the row is built by id) and `SELECT 1 AS one FROM "photos"|"users" WHERE "id" = $1 LIMIT $2` from the OD10 validation. So bulk tagging — `photo.rb:300`'s loop, and `tag_with_zip` on every photo create — costs two SELECTs more per tagged photo. No change in this slice; the `tag` load could go by assigning the tag by object, a §8 note.
- **G. Frontend string matching.** `grep -rl -F "can't be blank"` and `grep -rl -F "must exist"` over `insgt-app/src`, `insgt-ops/src` and `insgt-photographers/src` → 0 files each in all three. No client matches either string; the extra message line changes display only.
- **H. Write-back list for v7** — recorded under "Decisions beyond the gaps" (the write-back bullet) and applied at the write-back phase, not now.

## Scope (the brief's five items, by §4.5 number)

1. §4.5 scope 1 — the contract spec first, red. **As found:** 89 non-polymorphic reflections over 43 models (the runner, fact 1): the document's 2026-10-23 counts hold exactly (49 / 39 / 1 / 1). Encoded as five structural examples under "Gaps pinned" 1 (decision 2a: the one shared-column model is named only in its own spec); three of the five are red on `master`.
2. §4.5 scopes 2–3. **As found:** `Area#state` has no caller (fact 2); the three implicit nullable-column associations are exactly `Area#area_type` (`area.rb:9`), `Listing#property_type` (`listing.rb:37`), `OrderUrlGroup#order` (`order_url_group.rb:6`); there is no fourth (fact 1).
3. §4.5 scope 4. **As found:** the full suite with the two shim lines deleted is **green — 2,059 examples, 0 failures** (fact 4). There is no hand-built record to supply an association to, and no assertion that changes from a DB error to "must exist". The commit is the deletion, the OD10 validation and its model spec.
4. §4.5 scope 5. **As found:** every production query executes locally — 219 `_id` columns with 0 nullability mismatches, 39 null-count rows, 51 dangling-key rows (facts 5, 9). The local restore shows **three non-zero dangling columns** (`orders.account_id` 2, `orders_users.user_id` 27, photo-typed `tags_resources.resource_id` 32): local, not the observation, but the prediction for the gate. `sql_for` exists (`spec/support/sql_helpers.rb:11–21`); an `Order` save by id goes 12 → 15 SELECTs, by object 10 → 11 (fact 8).
5. §4.5's post-deploy verification and `docs/runbooks/deploy-rails-upgrade-4.md`. **As found:** `OrdersUser` is the wrong S12 path — it already answers 422 (`orders_user.rb:13`); `POST /areas_properties` without `property_id` is the path: 500 on `master`, 422 "Property must exist" after (fact 7).

## Out of scope — do not touch

The brief's three: any framework-default flag or shim file (slice 5) and the CSRF lines of the 5.0 shim (`new_framework_defaults.rb:9–13` stay); converting `TagsResource` to Rails polymorphism and any migration (the `NOT NULL` candidates go to §8 item 15); any model validation beyond what OD10's rule requires, `rails/all`, any gem. Added by this plan: the 30 column presence validators that will duplicate the framework's message (decision 7); the `delete_all` call sites that can create dangling rows; `belongs_to_required_validates_foreign_key` (a 7.1 default that stays `false` through slice 5 — fact 6).

## Phase 0 — survey

### Done

Read: §4.5, §4.0, §2, §5, §7, §8, §9 of v6; the codebase notes' `belongs_to` section and every row this slice depends on; `docs/plans/rails-upgrade-slice-3.md` (the shape of this file); `deploy-rails-upgrade-3.md` and `deploy-account-classification-4-backfill.md` (the query / expected / observed format); `spec/architecture/rails_upgrade_spec.rb` and `account_classification_spec.rb`; the Active Record 8.1.4 and Railties 8.1.4 source for how a `belongs_to` becomes required. Ran, all throwaway: the reflection runner; the full suite with the shim lines deleted; the nullability comparison; the 39 null-count and 51 dangling-key queries; the 422-for-500 probe before and after; the `sql_for` probe before and after; the draft contract block against each of the four commit states and five deliberate breaks; a probe of the error-message shape and of what a dangling key does on update.

### Prerequisites — landed and pending (facts)

| Prerequisite | State |
| :-- | :-- |
| Slice 3 on `master` | **Landed**: `05e3fd42` merges `chore/rails-upgrade-slice-3`; `Gemfile.lock:380` `rails (8.1.4)`; `config/application.rb:12` `load_defaults 7.2`; the runner prints `8.1.4` / `7.2` |
| Slice 3 deployed | **v666, 2026-11-02 05:12:27 PST** (runbook 3, Deploy log): S0–S6, S8, S10, S-404 pass; S7, S9 and SH pending at survey time |
| Quiet for two weekdays (§2.2, §4.5) | **Pending**: Tue 11-03 and Wed 11-04; slice 3's SH reads Tue 11-03 at about 05:12 PST. The Mac-side checks are under "Production" |
| OD10 decided | **Decided at the plan gate (decision 2)** on §4.5's recommendation, with the one correction the data forces |
| `sql_for` | **Exists**: `spec/support/sql_helpers.rb:11–21`, included for `type: :model` and `:request` (`:30–33`); a second inline copy at `spec/requests/metadata_contract_spec.rb:35` is not used here |
| The reference pattern | `spec/architecture/account_classification_spec.rb` (canonical fixtures, one `describe` per section); `rails_upgrade_spec.rb:117–131` is the block the new one follows |

### Codebase notes — rows this slice depends on, re-verified at `05e3fd42`

| Row | Claim | Verified |
| :-- | :-- | :-- |
| `config/initializers/new_framework_defaults.rb` 15–16 | the comment and the global `false` (was 19–20) | **holds** — `:15` the comment, `:16` the line |
| `spec/support/sql_helpers.rb` 11–21 | `sql_for` subscribes to `sql.active_record`, skipping `SCHEMA`/`TRANSACTION` | holds |
| the `belongs_to` section (v2) | 89 / 49 / 39 / 1 / 1; implicit at `area.rb:9`, `listing.rb:37`, `order_url_group.rb:6`; `Area#state` at `area.rb:7`; the `TagsResource` pair at `tags_resource.rb:7–8`, validations `:10–12` with nothing asserting that a target resolves | **holds, every number and every line** (fact 1) |
| `tags_resources` | `resource_id` and `resource_type` `NOT NULL` | holds (`db/schema.rb`, the `tags_resources` table: `t.integer "resource_id", null: false`, `t.integer "resource_type", limit: 2, null: false`) |

### Fresh facts the plan rests on

**1. The reflection table.** Produced by a throwaway runner (scratchpad `belongs_to_survey.rb`: `Rails.application.eager_load!`, then `ActiveRecord::Base.descendants` skipping abstract classes and classes without a table, `reflect_on_all_associations(:belongs_to)` on each; the column from `columns_hash[reflection.foreign_key]`, nullability from `column.null`, validators from `validators_on`) — not by grep. At boot it printed `belongs_to_required_by_default=false` and `belongs_to_required_validates_foreign_key=false`. **89 reflections, 43 models, 0 polymorphic, 0 outside `ApplicationRecord`** — `Rails.application.eager_load!` loads the application's own paths, so the Active Storage and Action Text engine models never enter the traversal and `ActiveRecord::Base.descendants` equals `ApplicationRecord.descendants` here; the contract spec traverses `ApplicationRecord.descendants`, §4.5's wording, so an engine model loaded by an earlier example can never enter it. Counts: **NOT NULL 49** (explicit `optional: true` on two, the `TagsResource` pair); **nullable 39** (36 explicit, 3 implicit); **no column 1**; **shared column 1** (`TagsResource`, `resource_id`). No `optional: false` or `required:` anywhere; no unresolved target class. Exactly one association carries a presence validator on the association name today (`OrderTypesService#order_type`, `order_types_service.rb:12`). Of the **47** that become required, **30** already validate presence of the key column ("fk presence validated" in the Action column) and **17** do not — those 17 are the true 500 → 422 set, listed after the table. There is no polymorphic reflection to mark out of scope; there is no fourth nullable-column reflection the brief does not name.

| Model | Association | Polymorphic? | FK column | Column nullability | `optional:` today | After the slice | Action |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `Account` | `marketing_source` | no | `accounts.marketing_source_id` | NULL | `true` | optional | none |
| `AccountMetric` | `account` | no | `account_metrics.account_id` | NOT NULL | — | required | presence validation (via the default) |
| `AccountsOrganization` | `account` | no | `accounts_organizations.account_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `AccountsOrganization` | `organization` | no | `accounts_organizations.organization_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `AccountsUser` | `account` | no | `accounts_users.account_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `AccountsUser` | `user` | no | `accounts_users.user_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `AccountsUser` | `role` | no | `accounts_users.role_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Area` | `state` | no | `areas.state_id` | NO COLUMN | `true` | deleted | delete |
| `Area` | `city` | no | `areas.city_id` | NULL | `true` | optional | none |
| `Area` | `area_type` | no | `areas.area_type_id` | NULL | — | optional | optional: true |
| `AreasProperty` | `area` | no | `areas_properties.area_id` | NOT NULL | — | required | presence validation (via the default) |
| `AreasProperty` | `property` | no | `areas_properties.property_id` | NOT NULL | — | required | presence validation (via the default) |
| `Cart` | `user` | no | `carts.user_id` | NULL | `true` | optional | none |
| `Cart` | `account` | no | `carts.account_id` | NULL | `true` | optional | none |
| `City` | `state` | no | `cities.state_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Floorplan` | `order` | no | `floorplans.order_id` | NOT NULL | — | required | presence validation (via the default) |
| `Flyer` | `listing` | no | `flyers.listing_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `FlyersPhoto` | `flyer` | no | `flyers_photos.flyer_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `FlyersPhoto` | `photo` | no | `flyers_photos.photo_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Headshot` | `user` | no | `headshots.user_id` | NULL | `true` | optional | none |
| `Listing` | `user` | no | `listings.user_id` | NULL | `true` | optional | none |
| `Listing` | `second_account` | no | `listings.second_account_id` | NULL | `true` | optional | none |
| `Listing` | `second_user` | no | `listings.second_user_id` | NULL | `true` | optional | none |
| `Listing` | `property_type` | no | `listings.property_type_id` | NULL (default 1) | — | optional | optional: true |
| `ListingDescription` | `listing` | no | `listing_descriptions.listing_id` | NOT NULL | — | required | presence validation (via the default) |
| `ListingPhoto` | `listing` | no | `listing_photos.listing_id` | NOT NULL | — | required | presence validation (via the default) |
| `ListingPhoto` | `photo` | no | `listing_photos.photo_id` | NOT NULL | — | required | presence validation (via the default) |
| `ListingPropertyFeature` | `listing` | no | `listing_property_features.listing_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `ListingPropertyFeature` | `property_feature` | no | `listing_property_features.property_feature_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `ListingRoom` | `listing` | no | `listing_rooms.listing_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `ListingRoom` | `room_type` | no | `listing_rooms.room_type_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `MarketingEvent` | `order` | no | `marketing_events.order_id` | NULL | `true` | optional | none |
| `MarketingEvent` | `organization` | no | `marketing_events.organization_id` | NULL | `true` | optional | none |
| `MarketingEventImport` | `marketing_event` | no | `marketing_event_imports.marketing_event_id` | NOT NULL | — | required | presence validation (via the default) |
| `MarketingEventImport` | `order_type` | no | `marketing_event_imports.order_type_id` | NOT NULL | — | required | presence validation (via the default) |
| `MlsImport` | `mls` | no | `mls_imports.organization_id` | NOT NULL | — | required | presence validation (via the default) |
| `MlsListing` | `listing` | no | `mls_listings.listing_id` | NOT NULL | — | required | presence validation (via the default) |
| `MlsListing` | `mls` | no | `mls_listings.organization_id` | NOT NULL | — | required | presence validation (via the default) |
| `MlsMetadataCache` | `mls` | no | `mls_metadata_caches.organization_id` | NOT NULL | — | required | presence validation (via the default) |
| `Notification` | `order_event` | no | `notifications.order_event_id` | NULL | `true` | optional | none |
| `NotificationAudience` | `notification` | no | `notification_audiences.notification_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `NotificationAudience` | `role` | no | `notification_audiences.role_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Order` | `parent` | no | `orders.parent_id` | NULL | `true` | optional | none |
| `Order` | `property` | no | `orders.property_id` | NULL | `true` | optional | none |
| `Order` | `account` | no | `orders.account_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Order` | `sales_type` | no | `orders.sales_type_id` | NULL | `true` | optional | none |
| `Order` | `order_event` | no | `orders.order_event_id` | NULL | `true` | optional | none |
| `Order` | `order_type` | no | `orders.order_type_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Order` | `marketing_event` | no | `orders.marketing_event_id` | NULL | `true` | optional | none |
| `Order` | `listing` | no | `orders.listing_id` | NULL | `true` | optional | none |
| `OrderLog` | `order` | no | `order_logs.order_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrderLog` | `order_event` | no | `order_logs.order_event_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrderLog` | `notification` | no | `order_logs.notification_id` | NULL | `true` | optional | none |
| `OrderService` | `order` | no | `order_services.order_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrderService` | `service` | no | `order_services.service_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrderService` | `discount` | no | `order_services.discount_id` | NULL | `true` | optional | none |
| `OrderTypesService` | `order_type` | no | `order_types_services.order_type_id` | NOT NULL | — | required | presence validation (via the default) |
| `OrderTypesService` | `service` | no | `order_types_services.service_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrderUrl` | `order` | no | `order_urls.order_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrderUrl` | `order_url_group` | no | `order_urls.order_url_group_id` | NULL | `true` | optional | none |
| `OrderUrlGroup` | `order` | no | `order_url_groups.order_id` | NULL | — | optional | optional: true · fk presence validated |
| `OrdersUser` | `order` | no | `orders_users.order_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrdersUser` | `user` | no | `orders_users.user_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `OrdersUser` | `role` | no | `orders_users.role_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Organization` | `property` | no | `organizations.property_id` | NULL | `true` | optional | none |
| `Organization` | `parent` | no | `organizations.parent_id` | NULL | `true` | optional | none |
| `Organization` | `marketing_source` | no | `organizations.marketing_source_id` | NULL | `true` | optional | none |
| `Photo` | `order` | no | `photos.order_id` | NULL | `true` | optional | none |
| `Photo` | `property` | no | `photos.property_id` | NULL | `true` | optional | none |
| `Photo` | `photographer` | no | `photos.photographer_id` | NULL | `true` | optional | none |
| `Photo` | `processor` | no | `photos.processor_id` | NULL | `true` | optional | none |
| `Photo` | `photo_scene_type` | no | `photos.photo_scene_type_id` | NULL | `true` | optional | none |
| `PostalCodeAssociation` | `postal_code` | no | `postal_code_associations.postal_code_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Property` | `postal_code` | no | `properties.postal_code_id` | NULL | `true` | optional | none |
| `Property` | `city` | no | `properties.city_id` | NULL | `true` | optional | none |
| `Property` | `ai_property_type` | no | `properties.ai_property_type_id` | NULL | `true` | optional | none |
| `Property` | `edited_property_type` | no | `properties.edited_property_type_id` | NULL | `true` | optional | none |
| `RawPhoto` | `order` | no | `raw_photos.order_id` | NOT NULL | — | required | presence validation (via the default) |
| `RawPhoto` | `photo` | no | `raw_photos.photo_id` | NULL | `true` | optional | none |
| `Schedule` | `user` | no | `schedules.user_id` | NOT NULL | — | required | presence validation (via the default) |
| `Service` | `order_type` | no | `services.order_type_id` | NULL | `true` | optional | none |
| `State` | `country` | no | `states.country_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `Tag` | `tag_category` | no | `tags.tag_category_id` | NULL | `true` | optional | none |
| `Tag` | `parent` | no | `tags.parent_id` | NULL | `true` | optional | none |
| `TagsResource` | `tag` | no | `tags_resources.tag_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `TagsResource` | `user` | no | `tags_resources.resource_id` | NOT NULL | `true` | optional (shared column, OD10) | none (exactly-one validation on the model) · fk presence validated |
| `TagsResource` | `property` | no | `tags_resources.resource_id` | NOT NULL | `true` | optional (shared column, OD10) | none (exactly-one validation on the model) · fk presence validated |
| `Transaction` | `order` | no | `transactions.order_id` | NOT NULL | — | required | presence validation (via the default) · fk presence validated |
| `UnalteredPhoto` | `photo` | no | `unaltered_photos.photo_id` | NOT NULL | — | required | presence validation (via the default) |

The 17 associations whose save fails with `PG::NotNullViolation` today and with a 422 after the slice (no presence validator on the key column; the model file, lines from the runner's reflections):

| Model#association | Column → target |
| :-- | :-- |
| `AccountMetric#account` | `account_metrics.account_id` → `accounts` |
| `AreasProperty#area`, `#property` | `areas_properties.area_id` → `areas`; `.property_id` → `properties` |
| `Floorplan#order` | `floorplans.order_id` → `orders` |
| `ListingDescription#listing` | `listing_descriptions.listing_id` → `listings` |
| `ListingPhoto#listing`, `#photo` | `listing_photos.listing_id` → `listings`; `.photo_id` → `photos` |
| `MarketingEventImport#marketing_event`, `#order_type` | `marketing_event_imports.marketing_event_id` → `marketing_events`; `.order_type_id` → `order_types` |
| `MlsImport#mls` | `mls_imports.organization_id` → `organizations` |
| `MlsListing#listing`, `#mls` | `mls_listings.listing_id` → `listings`; `.organization_id` → `organizations` |
| `MlsMetadataCache#mls` | `mls_metadata_caches.organization_id` → `organizations` |
| `OrderTypesService#order_type` | `order_types_services.order_type_id` → `order_types` (validates the association name today, `order_types_service.rb:12`, so already a 422 — the message gains a second line) |
| `RawPhoto#order` | `raw_photos.order_id` → `orders` |
| `Schedule#user` | `schedules.user_id` → `users` |
| `UnalteredPhoto#photo` | `unaltered_photos.photo_id` → `photos` |

**2. Columnless reflections.** One: `Area#state` (`app/models/area.rb:7`, `belongs_to :state, optional: true`; `areas` has `city_id`, `area_type_id`, `parent_area_id` and no `state_id` — `db/schema.rb`, the `areas` table). No other reflection lacks its column (the runner's `NO COLUMN` count is 1). No caller: `grep -rn -E "area(s)?\.state\b|area_state" app lib --include=*.rb --include=*.jbuilder` (minus `city.state`, `property.state`, `postal_code`) → empty; `grep -rn -E "\bstate\b" app/views/areas app/helpers/areas_helper.rb` → empty. `Area#geocode_address` (`area.rb:62–64`) reads `city.state.state_code` through the city, never `self.state`.

**3. Shared-column reflections (OD10).** Enumerated as §4.5 defines them — more than one non-polymorphic `belongs_to` on one model pointing at one foreign-key column: exactly one pair, `TagsResource#user` and `TagsResource#property`, both `foreign_key: :resource_id` (`app/models/tags_resource.rb:7–8`), `tags_resources.resource_id` `NOT NULL`, `resource_type` `NOT NULL` as the discriminator (`lib/resource_type.rb:2–12`: user 1, account 2, property 3, marketing_event 4, order_type 5, organization 6, photo 7). Today's validations (`:10–12`) require `resource_id`, `resource_type` and `tag_id` and assert nothing about a target resolving. **What the data says (local dev restore, `insgt_api_development`, 722,526 rows):** `resource_type` 1 (user) — 4,652 rows; `resource_type` 7 (photo) — **717,874** rows (716,425 active); property-typed rows — **0**; any other type — 0. The model's own code is photo-first: `create_photo_tag` (`:22–28`), `join_on[:photos]` (`:18`), `Photo` creating rows with `ResourceType.photo_resource_id` (`photo.rb:251–256`, `:300–305`), `PhotoTagSyncService` (`:50`), and the API create path permits `resource_type` (`tags_resources_controller.rb:14`, `:41`). So "exactly one of the two targets resolves" (OD10's wording) is false for 99.4% of the table, which has no `belongs_to :photo` at all — the exactly-one rule has to be judged by `resource_type`, over the three classes the model names (user, property, photo). Gaps pinned 1 encodes that.

**4. Hand-built spec records that break under required-by-default.** The full suite in the probe copy with `new_framework_defaults.rb:15–16` deleted (the copy's file ends at line 14; `bin/rails runner -e test` in the copy printed `belongs_to_required_by_default` → `true` and `Order.validators_on(:account)` → one `PresenceValidator` with `message: :required` and the `if:` lambda from `builder/belongs_to.rb:148`):

```
Finished in 55.19 seconds (files took 2.05 seconds to load)
2059 examples, 0 failures
```

(`--format json`: `examples=2059 failures=0 pending=0`; the `master` baseline on the merge is 2,059 — runbook 3, Prerequisites.) **The failure list is empty.** No spec file:line to fix, no association to supply, and no assertion whose text changes from a DB error to "must exist" — the separate trap-3 list is also empty. Why: every hand-built record in the suite that touches a `NOT NULL` key already supplies a row that exists (it had to, or `PG::NotNullViolation` would already fail it), and no spec asserts a `NotNullViolation`. The copy is the probe's "revert": the real tree was never edited (`git status` clean throughout).

**5. The `NOT NULL` FK column list.** From the runner (schema nullability) — the 47 `NOT NULL` columns behind a required association after the slice, one per table.column, are the D1–D47 rows of the dangling-key report under "Production" (plus `tags_resources.resource_id`, D48–D50 by type, and `tags_resources.tag_id`, in D45). §8 item 15's *candidates* are the opposite set: nullable columns that are always populated. On the local restore the null-count report (N1–N39) finds **five** with `nulls = 0`: `areas.city_id`, `areas.area_type_id`, `notifications.order_event_id`, `order_url_groups.order_id`, `photos.order_id` — recorded here for §8 item 15, decided by the production run, not here; the rule stays nullability, so `Area#area_type` and `OrderUrlGroup#order` still gain `optional: true` in commit 3 even though their columns are full.

**6. How a `belongs_to` becomes required on 8.1.4 under `load_defaults 7.2` (the mechanics §4.5 assumes).** `activerecord-8.1.4/lib/active_record/associations/builder/belongs_to.rb:131–166` (`define_validations`): `required:` is folded into `options[:optional]` (`:132–134`); with no `optional:` key the model's `belongs_to_required_by_default` decides (`:136–140`); when required, **and `ActiveRecord.belongs_to_required_validates_foreign_key` is `false`**, the presence validator is added with an `if:` condition — the key is `nil` or `attribute_changed?` (`:148–163`); only when that flag is `true` is the validator unconditional (`:145–146`). The flag's base value is `true` (`active_record.rb:352`, `railtie.rb:40`) and **`load_defaults 7.1` sets it to `false`** (`railties-8.1.4/lib/rails/application/configuration.rb:285`); nothing in 7.2, 8.0 or 8.1 flips it back, so it is `false` today and stays `false` through slice 5b. Consequences, each proven in the probe copy (fact 7's second spec): an existing row whose `NOT NULL` key points at a missing row **saves** when the key is unchanged (`order.update({ title: … })` → `saved=true`), **saves** when the key is reassigned to a row that exists, and **fails** only when the key is reassigned to a row that does not (`saved=false`, `["Account must exist"]` — on `master` the same reassignment saves). §4.5's "becomes unsaveable until repaired" and R2's "a row with a dangling `NOT NULL` key becomes unsaveable" are therefore too wide: the row is unsaveable only through a reassignment to another missing row, which is the exact save the validation exists to refuse. This changes what the dangling-key STOP protects against (decision 5) and is a v7 write-back item. There is no `optional?` on a reflection (`grep -n "def optional?" reflection.rb` → nothing), so §4.5's phrase "report `optional?` true" for the deliberate break reads, in the spec, as `ActiveRecord::Base.belongs_to_required_by_default` → `false` and the presence validators gone.

**7. The 422-for-500 path.** Not `OrdersUser`: `orders_user.rb:12–14` validates `order_id`, `user_id` and `role_id` presence, so `POST /orders_users` without `user_id` answers 422 today ("User can't be blank"). The candidate is **`POST /areas_properties`** — route `config/routes.rb:40` (`resources :areas_properties`), action `areas_properties_controller.rb:13–20` (`AreasProperty.new(areas_property_params)`, `save(current_user)`, `render_errors` on failure), permitted params `:35` `permit(:area_id, :property_id)` with neither required by the controller; the model `areas_property.rb:4–5` has the two `belongs_to` and no validation; auth `:2–3` (JWT; `system_admin`, `system_scheduler`, `system_photographer`, `system_processor`). Captured on `master` with a throwaway request spec (scratchpad `areas_property_create_probe_spec.rb`: a system-admin JWT via `jwt_headers_for`, an `Area` with a city, `post '/areas_properties', params: { areas_property: { area_id: area.id } }, as: :json`), once as the test environment sees it (`show_exceptions = :rescuable`, `config/environments/test.rb:29`) and once with `env_config['action_dispatch.show_exceptions'] = :all`, which is how production renders it:

```
PROBE rescuable: raised ActiveRecord::NotNullViolation — PG::NotNullViolation: ERROR:  null value in column "property_id" of relation "areas_properties" violates not-null constraint
PROBE production-shaped: status=500 body={"status":500,"error":"Internal Server Error","exception":"#<ActiveRecord::NotNullViolation:\"PG::NotNullViolation: ERROR:  null value in column \\\"property_id\\\" of relation \\\"areas_properties\\\" violates not-null constraint\\nDETAIL:  Failing row contains (30, 34, null, 1, 7954, null, 20
```

The same spec in the probe copy at the commit 4 state:

```
PROBE rescuable: status=422 body={"errors":["Property must exist"]}
PROBE production-shaped: status=422 body={"errors":["Property must exist"]}
```

The message shape on the 30 models that already validate the key column (probe copy, commit 4 state; `master` in brackets): `OrdersUser` without `user_id` → `["User must exist", "User can't be blank"]` (`["User can't be blank"]`); `OrderTypesService` without `order_type_id` → `["Order type must exist", "Order type can't be blank"]` (`["Order type can't be blank"]`); `AreasProperty` without either key → `["Area must exist", "Property must exist"]` (`[]` — the save raised instead). The 422 body of every create or update that omits one of those 30 keys gains one line (decision 7).

**8. The `sql_for` measurement** (`spec/support/sql_helpers.rb:11–21`; throwaway `order_save_sql_probe_spec.rb`, `type: :model`; `create(:order_event, name: 'Created', tag: 'created')` first, as `orders_create_spec.rb:33` explains; the account, order type and `User.system` loaded before the block; SELECT = statements starting with `SELECT`, `sql_touching` by table). Two ways, as `OrdersController#create` does it: **by id** — `Order.new(account_id:, order_type_id:, status_type: 1, created_by_id: 1).save(User.system)` (`OrderParam.create_params`, `lib/order_param.rb:230–241`, permits ids); **by object** — `Order.new(account: …, order_type: …)`, the factory's shape.

| | statements | SELECTs | touching `accounts` | touching `order_types` |
| :-- | --: | --: | --: | --: |
| before, by id (`master`) | 15 | 12 | 0 | 2 |
| **after**, by id (probe copy, scopes 2–4 applied) | 18 | **15** | **2** | 2 |
| before, by object | 13 | 10 | 0 | 0 |
| **after**, by object | 14 | **11** | 0 | 0 |

The three new statements by id, pasted from the after run: `SELECT DISTINCT "accounts"."id" FROM "accounts" LEFT OUTER JOIN "accounts_users" ON …` and `SELECT "accounts"."id" AS t0_r0, … FROM "accounts" LEFT OUTER JOIN "accounts_users" …` — the presence validator reading `order.account` through its association scope `-> { eager_load(accounts_users: :user) }` (`order.rb:90`), which costs two statements, not one; and `SELECT "orders".* FROM "orders" WHERE "orders"."id" = $1 LIMIT $2` — `OrderLog#order` (`order_logs.order_id` `NOT NULL`), created by id inside the save's `log_create_event`, validating its own `order` presence. The `order_types` count is unchanged because the validator loads `order_type` where `before_save`'s price sync used to (the two statements move earlier). By object the account and order type are already loaded, so only the `OrderLog` statement is new. **So: +3 SELECTs per `Order` create by id, +1 by object; +0 on an update whose keys do not change (fact 6).** §4.5's ESTIMATE was +2. Every `before` number is from the real tree on `master`; every `after` from the probe copy; nothing was committed.

**9. The dangling-key and null-count queries, executed locally.** All 90 ran against `insgt_api_development` (the production restore of 2026-10-30 — `tmp/latest-2026-10-30.dump`, 16:17 UTC; modification C has the data timestamps) with 0 errors (`run_queries.rb`: `connection.select_all` per line). The nullability comparison also ran: the §4.5 `information_schema` query gave 219 `_id` columns locally and `nullability_diff.rb` against `db/schema.rb` printed `schema.rb columns=219 database columns=219` / `OK: no nullability mismatch`. **Local counts are not the observation** (the prompt's rule) — but three dangling-key rows were non-zero locally and are the gate's prediction: `orders.account_id` **2** (orders 2827, soft-deleted, 2016-11-02, account 873; and 4302, active, 2017-07-05, account 1190 — both accounts absent); `orders_users.user_id` **27** (all `user_id = 0`, 2017-07-07 … 2019-05-02, 24 active — a sentinel value, not a hard-deleted user); `tags_resources.resource_id` for photo-typed rows **32** (all active, all created 2025-06-17, pointing at photo ids that do not exist). Every other dangling count was 0, including `tags_resources` by user, by property, and "any other `resource_type`" (0 rows outside 1, 3, 7).

### What the survey changes

1. **The shim lines are 15–16**, not 18–20 (above). Scope 3 and §4.5 scope 4 read accordingly.
2. **Scope 3's spec-fixing half is empty** (fact 4): commit 4 is the deletion, the OD10 validation, and the two new spec files; no existing spec changes.
3. **OD10's "exactly one of the two targets" cannot be the rule as worded** (fact 3): the exactly-one check is keyed on `resource_type` over user, property and photo; a photo-typed row has no `belongs_to` to resolve through. Decision 2.
4. **`OrdersUser` is replaced by `AreasProperty`** as the S12 path (fact 7). Decision 4.
5. **The dangling-key risk is narrower than §4.5 and R2 state** (fact 6), and the local restore predicts the STOP will fire on three columns (fact 9). The plan keeps the contract's decision rule; decision 5 makes the rule exact (Gaps pinned 3).
6. **The `sql_for` numbers are +3 / +1, not +2** (fact 8).
7. **Where this file lives** (decision 1): slices 1–3's plans are platform-repo files (`/workspace/docs/plans/rails-upgrade-slice-{1,2,3}.md`, commits `13b97e0`, `1b77eed`; §2.7 puts every document there and says insgt-api's `master` never carries them); the prompt put this one in insgt-api's `docs/plans/` on the slice branch, which has only ever held `property-facts-lookup.md`. Answered: moved (decision 1).
8. **The error message doubles on 30 models** (fact 7). Decision 7.

## Phase 1 — plan

### Gaps pinned (the brief's four)

**1. OD10 as decided.** Proceeded on §4.5's recommendation; **confirmed at the gate (decision 2)** with the one correction the data forces. §4.5's recommendation, verbatim:

> - *The shared-column pair.* Recommended rule, structural rather than a name list (honouring "no allowlist"): a foreign-key column that more than one `belongs_to` on the same model points at is a hand-rolled polymorphic column; each of those associations is `optional: true` and the contract spec asserts, for such a column, that it is `NOT NULL` and that the model validates that exactly one target resolves (`TagsResource` — the plan reads its validations). Alternative: convert the pair to a real polymorphic `belongs_to :resource, polymorphic: true` — rejected here because `resource_type` is an integer from `lib/resource_type.rb`, not a class name; that is a data migration, not this slice.
> - *The columnless association.* Recommended: delete `Area#state` in its own commit; the contract spec fails on any reflection without a column, which is the guard against the next one.

And §7's OD10 row: "**Recommendation:** the structural shared-column rule (both `optional: true`, spec asserts exactly-one) and deleting `Area#state`. **Against:** the structural rule is a rule the spec must encode, not a plain equality; the alternative (real polymorphism) is a data migration".

**The spec encoding** — the block appended to `spec/architecture/rails_upgrade_spec.rb` after `:131`, exactly as it ran in the probe copy (five examples, decision 2a; the `describe` title names §4.5, rule D′ and OD10):

```ruby
  describe 'belongs_to optionality follows column nullability (§4.5, rule D′, §7 OD10)' do
    # The rule is structural, so no association and no model is named: a belongs_to is optional
    # exactly when its foreign-key column is nullable, or when more than one belongs_to on the
    # model points at the column — a hand-rolled polymorphic column typed by a ResourceType
    # integer, found by grouping the reflections on [model, foreign_key]. A NOT NULL column that
    # is not shared carries no `optional:` at all and is required through the framework default,
    # which is why the global belongs_to_required_by_default = false had to go rather than move.
    # What a shared column's model must do instead — refuse a row whose key names nothing — is
    # pinned in that model's own spec, not here. Polymorphic reflections are out of scope (§4.5).
    # A model written after this slice is covered the day it gains a belongs_to.
    let(:reflections) do
      Rails.application.eager_load!
      ApplicationRecord.descendants.reject(&:abstract_class?).sort_by(&:name).flat_map do |model|
        model.reflect_on_all_associations(:belongs_to).reject(&:polymorphic?).map { |reflection| [model, reflection] }
      end
    end

    let(:shared_columns) do
      reflections.group_by { |model, reflection| [model, reflection.foreign_key.to_s] }
                 .select { |_column, group| group.size > 1 }
                 .keys
    end

    def shared?(model, reflection)
      shared_columns.include?([model, reflection.foreign_key.to_s])
    end

    def label(model, reflection)
      "#{model.name}##{reflection.name} (#{model.table_name}.#{reflection.foreign_key})"
    end

    # An empty traversal would pass every example below; the document counted 89 before the
    # dead Area#state was deleted (§8 item 20's lesson).
    it 'sees the reflections the document surveyed' do
      expect(reflections.size).to be >= 88
    end

    it 'has a foreign-key column behind every non-polymorphic belongs_to' do
      columnless = reflections.reject { |model, reflection| model.columns_hash.key?(reflection.foreign_key.to_s) }

      expect(columnless.map { |model, reflection| label(model, reflection) }).to be_empty
    end

    it 'marks optional exactly the associations whose column is nullable or shared' do
      mismatches = reflections.filter_map do |model, reflection|
        column = model.columns_hash[reflection.foreign_key.to_s]
        next if column.nil?

        if column.null || shared?(model, reflection)
          next if reflection.options[:optional] == true

          "#{label(model, reflection)}: #{column.null ? 'nullable' : 'shared NOT NULL'} column, optional: #{reflection.options[:optional].inspect}"
        elsif reflection.options.key?(:optional)
          "#{label(model, reflection)}: NOT NULL column, optional: #{reflection.options[:optional].inspect}"
        end
      end

      expect(mismatches).to be_empty
    end

    # `optional:` absent is only "required" when the framework default says so. Re-adding the
    # global false leaves every option untouched and removes every presence validator at once.
    it 'requires every belongs_to on a NOT NULL column through the framework default' do
      expect(ActiveRecord::Base.belongs_to_required_by_default).to be(true)

      unvalidated = reflections.filter_map do |model, reflection|
        column = model.columns_hash[reflection.foreign_key.to_s]
        next if column.nil? || column.null || shared?(model, reflection)
        next if model.validators_on(reflection.name).any? { |validator| validator.kind == :presence }

        label(model, reflection)
      end

      expect(unvalidated).to be_empty
    end

    it 'keeps every shared column NOT NULL' do
      nullable_shared = reflections.filter_map do |model, reflection|
        column = model.columns_hash[reflection.foreign_key.to_s]
        label(model, reflection) if column && column.null && shared?(model, reflection)
      end

      expect(nullable_shared).to be_empty
    end
  end
```

What each example asserts and what its failure names:

| Example | Assertion | The failure text names |
| :-- | :-- | :-- |
| sees the reflections the document surveyed | `belongs_to_reflections.size >= 88` | the count (a guard against an empty traversal passing everything — §8 item 20's lesson) |
| has a foreign-key column behind every non-polymorphic belongs_to | `columnless` empty | `Model#association (table.column)` of each reflection without a column: on `master`, `["Area#state (areas.state_id)"]` |
| marks optional exactly the associations whose column is nullable or shared | `mismatches` empty — nullable or shared → `options[:optional] == true`; NOT NULL and not shared → `options.key?(:optional)` false | each mismatch with the column's state and today's option: on `master`, `Area#area_type … nullable column, optional: nil`, `Listing#property_type …`, `OrderUrlGroup#order …`; with `optional: true` wrongly added to `OrdersUser#user`, `OrdersUser#user (orders_users.user_id): NOT NULL column, optional: true` |
| requires every belongs_to on a NOT NULL column through the framework default | `ActiveRecord::Base.belongs_to_required_by_default` is `true`; then every required reflection has a presence validator on the association name | `expected true / got false` while the global line exists (it short-circuits there); with the line gone, the names of any required association without a validator (`OrdersUser#user (orders_users.user_id)` in the break) |
| keeps every shared column NOT NULL | no shared column is nullable | the pair's labels, if `resource_id` were ever made nullable |

The shared column is found structurally — the reflections grouped by `[model, foreign_key]`, groups of size > 1 (`shared_columns`) — and the file names no model and no association (decision 2a; trap 1). "Exactly one target resolves" cannot be encoded for a discriminator the framework does not know, so that behaviour is pinned in `spec/models/tags_resource_spec.rb` (commit 4; spec plan), the one place `TagsResource` is named; the five structural examples still hold it to the rule (both associations `optional: true`, the column `NOT NULL`). Rejected: a name allowlist (trap 1); asserting a validator *name* on the model (an allowlist by another route); reading `reflection.optional?` (no such method); the fixture inside the contract file (the first draft, moved out by decision 2a). The traversal is `ApplicationRecord.descendants` after `Rails.application.eager_load!` (§4.5's "every `ApplicationRecord` descendant") — the brief's `ActiveRecord::Base.descendants` traverses the same 43 models today (fact 1) but would admit an engine model loaded by an earlier example.

**The `TagsResource` exactly-one validation**, as the model lines it will be. After `tags_resource.rb:12`:

```ruby

  # OD10 (rails-upgrade.md §4.5): resource_id is shared by the two belongs_to above and typed by
  # resource_type — a ResourceType integer, not a class name — so neither association can be
  # required. This does for the shared column what a required belongs_to does for its own
  # (activerecord's builder/belongs_to.rb, define_validations): a new row, or a changed key, must
  # name a row that exists. An existing row whose key is unchanged is not re-checked, exactly as
  # every other belongs_to behaves under belongs_to_required_validates_foreign_key = false.
  RESOURCE_CLASSES = {
    ResourceType.types[:user][:id] => 'User',
    ResourceType.types[:property][:id] => 'Property',
    ResourceType.types[:photo][:id] => 'Photo'
  }.freeze

  validate :resource_must_exist, if: -> { new_record? || will_save_change_to_resource_id? || will_save_change_to_resource_type? }
```

and before the class's final `end` (after the `class << self` block):

```ruby

  private

  def resource_must_exist
    return if resource_id.nil? # the presence validation reports that

    resource_class = RESOURCE_CLASSES[resource_type]&.constantize
    errors.add(:resource_id, :required) unless resource_class&.unscoped&.exists?(resource_id)
  end
```

Why this shape: keyed on `resource_type`, not on "either `user` or `property` resolves", because 717,874 of 722,526 rows are photo-typed and the model has no `belongs_to :photo` (fact 3) — "exactly one" is true by construction once the type picks the class, and an unknown type resolves nothing (invalid, as the rule says). The three classes are the three the model itself names (`:7–8`, `:17–18`, `:22–28`). `errors.add(:resource_id, :required)` is the framework's `must exist`, so a 422 from `tags_resources#create` reads `Resource must exist` next to its siblings. The `if:` condition is `builder/belongs_to.rb:148–163`'s condition spelled for a hand-rolled column, so an existing photo tag whose photo has vanished (32 such rows locally) soft-deletes and updates exactly as every other row with a dangling key does after this slice (fact 6) — the validation refuses new rows and reassignments only. `unscoped.exists?` because the three targets' default scopes are ordering-only (`grep -rn default_scope app/models`: ten models, all `order(…)`) and a `belongs_to` reader would resolve a soft-deleted target too. Rejected: a `belongs_to :photo, foreign_key: :resource_id, optional: true` (a new association, not a validation — outside the brief's "any model validation beyond what OD10's rule requires"); converting to Rails polymorphism (§4.5, a data migration). **Which commit carries it: commit 4** (decision 3) — it is the presence rule for the one `NOT NULL` key the framework cannot validate, so it lands with the framework's own validations, and its model spec goes green in the same commit as the contract's framework-default example. The pair's own `optional: true` (`tags_resource.rb:7–8`) already exists on `master`, so no commit adds or moves it; it is kept, and commit 4's body names the shared-column exception as the non-obvious decision. The `if:` condition is decision 2(b)'s, confirmed.

**2. 422-for-500.** The create endpoint: **`POST /areas_properties`** — `config/routes.rb:40` `resources :areas_properties`; `AreasPropertiesController#create`, `app/controllers/areas_properties_controller.rb:13–20`; `areas_property_params` `:35` `params.require(:areas_property).permit(:area_id, :property_id)` — both keys permitted, neither required by the controller, so `property_id` is omittable; the model `app/models/areas_property.rb:4–5` is two `belongs_to` and nothing else; auth `:2–3`. The pre-deploy 500 captured locally on `master` (fact 7): exception class `ActiveRecord::NotNullViolation` (`PG::NotNullViolation: … null value in column "property_id" of relation "areas_properties" violates not-null constraint`), status **500** when rendered as production renders it; after the slice, **422** with `{"errors":["Property must exist"]}`. `OrdersUser` is not the candidate because `orders_user.rb:13` already validates `user_id` presence — it answers 422 today (`["User can't be blank"]`) and gains only a second line. The committed proof is `spec/requests/areas_properties_create_spec.rb` (spec plan); S12 is the same request against production after the push.

**3. Dangling keys.** One read-only query per `NOT NULL` FK column (D1–D47), the `tags_resources.resource_id` column by type (D48–D50), its type distribution (D52) and "any other type" (D51), plus the null-count query per nullable column (N1–N39) — all under "Production", each in the backfill runbook's format (query, expected, observed), each proven to execute locally (fact 9; 0 errors). Observed is empty here and filled at the gate. **The decision rule (decision 5, exact):** (a) the restore the prediction comes from is `tmp/latest-2026-10-30.dump`, data as of 2026-10-30 16:12 UTC (modification C); (b) **STOP** if production shows rows on any column outside the three predicted (D29 `orders.account_id`, D39 `orders_users.user_id`, D50 photo-typed `tags_resources.resource_id`), or if any of those three counts exceeds the restore's (2, 27, 32) — a higher count is a live writer; counts at or below are recorded in the runbook, not stopped on; (c) S13 pins the three observed counts; (d) the three sets become one §8 cleanup item. No migration is proposed either way (§8 item 15). What the rule protects, given fact 6: not "these rows become unsaveable" (they save unless their key is reassigned to another missing row) but a writer still producing such rows, which would keep producing 422s after the slice.

**4. The `sql_for` measurement.** Fact 8, both ways, before and after: by id **12 → 15** SELECTs (+2 for `account`'s eager-load scope, +1 for `OrderLog#order`), by object **10 → 11** (+1, the `OrderLog`); an update with unchanged keys +0. Not committed as a spec (decision 8): an assertion on the count would pin the thirteen incidental statements of an `Order` create along with the three that matter.

### Decisions beyond the gaps

- **Commit 1 is red by design, and stays partly red through commits 2 and 3.** §4.5 scope 1 says "Contract spec first (red)" and its commit sketch lists the `test:` commit first, so the contract file's state at each HEAD is the record of what the next commit fixes: after commit 1, three examples red; after 2, two; after 3, one; after 4, none (the per-commit plan pastes each). The other 2,059 examples never read the contract file, so the suite's only failures at those HEADs are the contract's. Rejected: folding each example into the commit that greens it (slice 3's practice, right for examples that were one-to-one with a change) — this is one invariant over 43 models, and splitting it would re-derive the rule four times. Decision 6 accepts the three red HEADs: each carries a Tier 2 body naming its red count (3, 2, 1) and the spec-first design, the suite minus the contract file is green at each HEAD, and each of commits 1–3 shows a deliberate break on an example that is green at that HEAD.
- **No existing spec changes.** Fact 4: the suite is green with the global `false` gone, so scope 3's "fix the specs that hand-build records" is empty; nothing is converted to a factory, no message is edited.
- **Two small spec files beyond the contract**, both named in §4.5's spec plan: `spec/models/area_spec.rb` (commit 2 — "`Area` saves without `state`": an `Area` with a name and a city saves, and `Area.reflect_on_association(:state)` is `nil`) and `spec/models/tags_resource_spec.rb` (commit 4 — the validation's four cases, including the unchanged-key rule; it is where `TagsResource` is named, decision 2a; run in the probe copy green, `4 examples, 0 failures`, and red without the validation, `4 examples, 2 failures`). The request spec `spec/requests/areas_properties_create_spec.rb` (commit 4) is §4.5's "one request spec per visible path".
- **The shim deletion takes lines 14–16** — the blank separator, the comment and the line — so the file does not end on a blank line; lines 1–13 (the header comment and the two CSRF lines) stay untouched. §4.5's "18–20" and "`:20`" are these lines.
- **Lint** for each commit: `ruby -c` on every touched Ruby file and `rails_best_practices -e "db/migrate,vendor" .` (`CLAUDE.md`'s quality command); `bin/rubocop` cannot run — there is no `.rubocop.yml` (slice 3's finding 14, still true: `ls -a .rubocop.yml` → no such file).
- **Area suite per commit**: commit 2 — `spec/models/area_spec.rb`, `spec/requests/properties_spec.rb` (areas through properties, 41 examples); commit 3 — `spec/models/listing*`, `spec/requests/listings*`, `spec/requests/order_url_groups*` (whatever exists under those names at implementation); commit 4 — `spec/requests`, `spec/models`, then P1 twice.
- **P1's count is reported, not a criterion** (slice 2's modification G): ESTIMATE **2,072** (2,059 + 5 contract + 4 tags-resource + 1 area + 3 request); the probe's **2,068 / 0** at the commit 4 state (2,059 + the 5 + the 4) is the measured basis.
- **Branches**: insgt-api `chore/rails-upgrade-slice-4` off `05e3fd42`, re-created with no commit (decision 1); platform `docs/rails-upgrade-slice-4` off `main` `c55807c`, carrying this plan, then the runbook and the write-back. Dan merges both.
- **Codex review** on an rsync copy without `.git` and `.env`, two rounds, findings folded into the commit they belong to by cherry-pick rebuild on the unpushed branch (slice 3's practice).
- **Write-back (v7) items (modification H), applied at the write-back phase, so slice 5 reads the document, not this file**: §4.5 "unsaveable until repaired" → the conditional semantics under `belongs_to_required_validates_foreign_key = false` (fact 6); §5 R2 narrowed to match; OD10 reworded to the `resource_type`-keyed rule with the photo type and settled in §7; `sql_for` +3 by id / +1 by object, not +2; the shim lines 15–16; the estimate 7 h (the hour is OD10's photo type); §4.5 as built (the empty spec-fix list, `AreasProperty` for S12, the production observations, decision 5's rule and disposition); §8: the dangling-row cleanup as one item (with B's finding that no default is involved), the 30 redundant column validators (after slice 5 closes), the `account` association's eager-load scope (two statements per by-id `Order` create) and the `tag` load on every `TagsResource` create (F), the five §8 item 15 candidates; the codebase notes gain the `AreasProperty` path, the `OrderLog#order` by-id SELECT, the `belongs_to` section rewritten as built, the probe copy and the 8.1.4 sources; the slice 5 prompt is untouched (`belongs_to_required_validates_foreign_key` is not among 5a's or 5b's flags).

### Approach, one unit of work per commit (the per-commit plan)

Every scope item in the brief maps to exactly one commit: brief scope 1 → commit 1; scope 2 → commits 2 (delete) and 3 (`optional: true`) — two commits because §4.5 names two; scope 3 → commit 4; scope 4 → the Production section of this plan (no commit: read-only runs and a measurement); scope 5 → the Post-deploy section and the runbook (platform-repo commit). The OD10 validation (brief gap 1) → commit 4. No commit carries a scope item the brief does not name; no scope item lacks a home.

**1. `test: pin belongs_to optionality to column nullability`** [tier 2]

- Files: `spec/architecture/rails_upgrade_spec.rb` — the block above, appended after `:131`; nothing else.
- Red state at HEAD (the probe copy on `master`'s tree, `bundle exec rspec spec/architecture/rails_upgrade_spec.rb -e 'belongs_to optionality'`; probe `commit1-v2`):

  ```
  5 examples, 3 failures
  1) … has a foreign-key column behind every non-polymorphic belongs_to
     expected `["Area#state (areas.state_id)"].empty?` to be truthy, got false
  2) … marks optional exactly the associations whose column is nullable or shared
     expected `["Area#area_type (areas.area_type_id): nullable column, optional: nil", "Listing#property_type (listi..., optional: nil", "OrderUrlGroup#order (order_url_groups.order_id): nullable column, optional: nil"].empty?`
  3) … requires every belongs_to on a NOT NULL column through the framework default
     Failure/Error: expect(ActiveRecord::Base.belongs_to_required_by_default).to be(true)
       expected true
            got false
  ```

  Green at this HEAD: "sees the reflections the document surveyed" and "keeps every shared column NOT NULL".
- Green state: none further at this commit, by the contract's design (§4.5 scope 1; decision 6); commits 2, 3 and 4 green the three red examples in that order.
- Deliberate break, on an example that is green at this HEAD (decision 6): the traversal floor raised from 88 to 90 → `5 examples, 4 failures`, the new one `sees the reflections the document surveyed` — `expected: >= 90 / got: 89` (probe `break-floor-v2`). Restore.
- Full suite at HEAD: **2,064 examples, 3 failures** — derived: 2,059 green on `master` plus the five, of which three red; the suite minus the contract file is green (the run at the commit 4 state, which contains every other example, is 2,068 / 0).
- Lint: `ruby -c` on the spec; `rails_best_practices` unchanged.
- Body (tier 2): red by design — three of five examples, named — which commit greens which, and that the rule is structural so no later model needs a line here.

**2. `fix: drop the dead Area#state association`** [tier 1]

- Files: `app/models/area.rb:7` deleted (`belongs_to :city` becomes `:7`, `:area_type` `:8`); `spec/models/area_spec.rb` new, one example — an `Area` with a name and a `create(:city)` saves with `save(User.system)` (the `geocode_address` callback, `area.rb:62–64`, needs the city; the geocoder is stubbed suite-wide by `spec/support/geocoder.rb`) and `Area.reflect_on_association(:state)` is `nil`.
- Red before the change: the contract's columnless example (`["Area#state (areas.state_id)"]`, above) and the new model example (`expected nil, got #<ActiveRecord::Reflection::BelongsToReflection …>`).
- Green after: contract `5 examples, 2 failures` — the nullability and framework-default examples remain red (probe `commit2-v2`); the model example passes.
- Deliberate break, on the example this commit greened (decision 6): re-add the line → `expected `["Area#state (areas.state_id)"].empty?` to be truthy, got false` returns (probe `break-area-state`). Restore.
- Area suite: `spec/models/area_spec.rb`, `spec/requests/properties_spec.rb`. Full suite at HEAD: 2,065 examples, 2 failures (the contract's).
- Lint as above. Body (tier 2, decision 6): the contract file is still red on two examples by design, and which commits green them; the diff itself is one line.

**3. `refactor: mark the nullable belongs_to associations optional`** [tier 1]

- Files: `app/models/area.rb:8` `belongs_to :area_type, optional: true`; `app/models/listing.rb:37` `belongs_to :property_type, optional: true`; `app/models/order_url_group.rb:6` `belongs_to :order, optional: true`. Nothing else: `OrderUrlGroup` keeps its `validates :order_id, presence: true` (`:9`), so its behaviour does not change; `listings.property_type_id` has `default: 1` (`db/schema.rb:435`), so a `Listing` created without it is unchanged too.
- Red before: the nullability example naming the three (the commit 1 text above; identical at the commit 2 state).
- Green after: contract `5 examples, 1 failure` — the framework-default example remains (probe `commit3-v2`).
- Deliberate breaks, on the example this commit greened (decision 6): (a) remove the option from `Area#area_type` → `expected `["Area#area_type (areas.area_type_id): nullable column, optional: nil"].empty?` to be truthy, got false` (probe `break-area-type-optional`); (b) add `optional: true` to `OrdersUser#user` (a `NOT NULL` column outside the shared rule — trap 2's second half) → two examples red: `expected `["OrdersUser#user (orders_users.user_id): NOT NULL column, optional: true"].empty?` to be truthy, got false` and `expected `["OrdersUser#user (orders_users.user_id)"].empty?` to be truthy, got false` (probe `break-orders-user-optional`). Restore both.
- Area suite: the listing and order-url-group specs. Full suite at HEAD: 2,065 examples, 1 failure (the contract's).
- Lint as above. Body (tier 2, decision 6): the contract file is still red on one example by design, and that commit 4 greens it; `OrderUrlGroup`'s own `order_id` validation and `listings.property_type_id`'s default keep behaviour unchanged.

**4. `fix: validate presence of belongs_to on NOT NULL columns`** [tier 3]

- Files: `config/initializers/new_framework_defaults.rb:14–16` deleted (the file ends at `:13`); `app/models/tags_resource.rb` — the constant and the `validate` line after `:12`, the private method before the final `end`; `spec/requests/areas_properties_create_spec.rb` new (three examples); `spec/models/tags_resource_spec.rb` new (four examples).
- Red before the change (at commit 3's HEAD): the contract's framework-default example (`expected true / got false`); the request spec's two 422 examples raise `ActiveRecord::NotNullViolation` (fact 7's `master` capture — the spec's red); the model spec's two invalid cases (probe `model-spec-red`, `4 examples, 2 failures`): `expected #<TagsResource id: nil, resource_id: 0, resource_type: 1, tag_id: 245, …> not to be valid` and `expected #<TagsResource id: nil, resource_id: 7961, resource_type: 7, tag_id: 246, …> not to be valid`.
- Green after: contract `5 examples, 0 failures` (probe `commit4-v2`); the model spec `4 examples, 0 failures` (probe `model-spec-green`); the request spec `422` with `["Property must exist"]` / `["Area must exist"]` (fact 7's after capture).
- Deliberate breaks: (a) re-add the three shim lines → contract `5 examples, 1 failure`: `Failure/Error: expect(ActiveRecord::Base.belongs_to_required_by_default).to be(true) / expected true / got false` (probe `break-global-false`), and the request spec's 422 examples raise `NotNullViolation` again; (b) remove the `TagsResource` validation → the model spec `4 examples, 2 failures` (the two texts above); the contract stays green, as decision 2a intends — it does not know the model. Restore both.
- Full suite at HEAD: **ESTIMATE 2,072 examples, 0 failures** (measured **2,068 / 0** at this state with the contract's five and the model spec's four, without the area and request examples). Then P1 again with `CI=1`, P2–P8, P-PROD (Verification).
- Lint as above; `rails_best_practices` on the model.
- Body (tier 3 — trigger 1 and trigger 3's cousin, a precondition on data): the file is named for *new* framework defaults while the line was a permanent choice from the Rails 5 port (`2bfb1f01`); what changes for a client — the 17 paths that answered 500 (`ActiveRecord::NotNullViolation`) now answer 422 with `must exist`, and 30 paths' 422 bodies gain that line; the mechanism — under `load_defaults 7.1`+ the validator is conditional (`belongs_to_required_validates_foreign_key = false`), so an existing row with a dangling key keeps saving unless the key is reassigned to another missing row; the precondition — the dangling-key report's observed counts (and the rows named, if any were waived at the gate); the shared-column exception (decision 3): why `TagsResource#user` and `#property` keep their `optional: true` on a `NOT NULL` column and why the model validates by `resource_type` rather than through them.

Then once for the slice: P1 (twice) to P8 and P-PROD with `slice 4`; the runbook as `Draft`; `predeploy-review-rails` twice (Codex included); the verification STOP with the spot-check table filled from development and the three production reads listed for the Mac.

### Spec plan — boundary cases by name

`spec/architecture/rails_upgrade_spec.rb` (extended; `type: :model`) — the five examples of Gaps pinned 1, with their pinned values and breaks as pasted in the per-commit plan. Red on `master`: the columnless, nullability and framework-default examples. Breaks shown: the traversal floor raised (the guard example); `Area#state` re-added (columnless); `Area#area_type`'s option removed and `OrdersUser#user` wrongly optional (nullability, and framework-default for the latter); the global `false` re-added (framework-default).

`spec/models/area_spec.rb` (new, commit 2; `type: :model`):

| Example | Pinned | Red |
| :-- | :-- | :-- |
| saves with a name and a city, and has no state association | `area.save(User.system)` → `true`; `Area.reflect_on_association(:state)` → `nil` | while `area.rb:7` exists: the reflection is present |

`spec/requests/areas_properties_create_spec.rb` (new, commit 4; `type: :request`; a system-admin JWT as `orders_create_spec.rb:52–59` builds one; an `Area` with a city; a `create(:property)`):

| Example | Request | Expected | Red (before the shim deletion) |
| :-- | :-- | :-- | :-- |
| answers 422 when the property is omitted | `POST /areas_properties` `{ areas_property: { area_id } }` | `422`, `errors` includes `"Property must exist"`; `AreasProperty` count unchanged | raises `ActiveRecord::NotNullViolation` (fact 7) |
| answers 422 when the area is omitted | `{ areas_property: { property_id } }` | `422`, `"Area must exist"` | raises `ActiveRecord::NotNullViolation` |
| creates the row when both are present | both ids | `200` and one new `AreasProperty` for the pair | — (green on both; guards the path through the change) |

`spec/models/tags_resource_spec.rb` (new, commit 4; `type: :model`; `create(:tag)`, `create(:user)`) — the behavioural pin decision 2a moved out of the contract file; run in the probe copy: green `4 examples, 0 failures`, red on the two invalid cases without the validation:

| Example | Pinned | Red (before the validation) |
| :-- | :-- | :-- |
| is valid when a user-typed row names an existing user | `valid?` → `true` | — (green both; guards the happy path) |
| is invalid when a user-typed row names no user | `errors[:resource_id]` includes `must exist`; `errors.full_messages` includes `Resource must exist` | `expected … not to be valid` |
| is invalid when a photo-typed row carries a user's id | not valid (the type decides which table is asked) | `expected … not to be valid` |
| still soft-deletes an existing row whose user has since been hard-deleted | create the user-typed row, `User.where(id:).delete_all`, reload, `destroy(User.system)` → `true` (the unchanged-key rule, fact 6; the row's `status_type` is 2) | — (green both; exists so nobody "tightens" the condition into a full re-check that would strand the 32 photo tags) |

Existing coverage run by name and reported: `spec/requests/orders_create_spec.rb` (the `OrdersUser` fan-out by id — the paths that gain a second message), `spec/requests/properties_spec.rb` (areas), the P4, P5, P7 sets. All green at the commit 4 state (the 2,068 / 0 run contains them).

### Commit sequence

insgt-api, branch `chore/rails-upgrade-slice-4` off `master` `05e3fd42` (tiers per `git-commit-messages` in brackets):

1. `test: pin belongs_to optionality to column nullability` [2]
2. `fix: drop the dead Area#state association` [2, decision 6]
3. `refactor: mark the nullable belongs_to associations optional` [2, decision 6]
4. `fix: validate presence of belongs_to on NOT NULL columns` [3]

This plan: `docs: plan rails upgrade slice 4` [1] on the platform repo's `docs/rails-upgrade-slice-4` (decision 1); the insgt-api branch carries no commit until the loop starts. Then on the same platform branch: `docs: add the rails upgrade slice 4 runbook` (before the push); after verification `docs: amend the rails upgrade design to v7 for slice 4` and `docs: update the rails upgrade notes for slice 4`; after the deploy `docs: record the slice 4 deploy in the rails upgrade runbook`.

## Production — every runner and query, verbatim, for the Mac

No production command ran in this session. Everything below runs on the host from `apps/insgt-api` inside the platform checkout (the devcontainer has no `heroku` CLI); `tmp/` is insgt-api's gitignored scratch directory. Every `heroku run … rails runner` on 8.1.4 prints Active Storage's `image_processing` WARN line before its own output (§4.0 S3, §8 item 7) — expected, not a failure. Observed values are pasted at the gate. **Each of the three reads runs twice — at Thursday's review (2026-11-05) and again the morning of the push (Mon 11-09) — and both are pasted (modification D); a STOP found Thursday costs nothing.**

### Prerequisite checks (before the branch is reviewed; again the morning of the push)

```bash
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; puts Rails.application.config.loaded_config_version'
```

Expected: the WARN line, then `8.1.4`, then `7.2`. Observed: (gate).

SH clean for two weekdays after slice 3's push (Tue 11-03 and Wed 11-04; read Tue 11-03 and again Thu 11-05) — Honeybadger → Errors:

```
environment:"production" created.after:"2026-11-02 05:12 UTC-8"
environment:"production" class:"RailsDeprecation" occurred.after:"2026-11-02 05:12 UTC-8"
environment:"production" class:"AbstractController::DoubleRenderError" occurred.after:"2026-11-02 05:12 UTC-8"
```

Expected: no new error, compared by error (§4.0 SH's triage); no `RailsDeprecation` beyond S-DEP's; no `DoubleRenderError`. Observed: (gate).

**Honeybadger baseline for the 17 (modification E; Dan, before Thursday's review — not reachable from the container):**

```
environment:"production" class:"ActiveRecord::NotNullViolation" occurred.after:"2026-10-26 00:00 UTC-7"
```

From slice 0's deploy (v659, 2026-10-26) to now. Each hit is a production path that answers `RecordInvalid`/422 after the slice — record its controller, action and the column the message names; zero hits means the 17 are unexercised in production and SH's "must exist" watch expects nothing. Observed: (Dan).

### The nullability STOP (§4.5 scope 5)

Save the comparison script as `tmp/nullability_diff.rb` (throwaway; never committed):

```ruby
# Throwaway: compares db/schema.rb's *_id column nullability with a CSV (table_name,column_name,is_nullable)
# produced by the information_schema query in §4.5 scope 5. Usage: ruby nullability_diff.rb db/schema.rb columns.csv
schema = {}
table = nil
File.foreach(ARGV[0]) do |line|
  if line =~ /create_table "([^"]+)"/
    table = Regexp.last_match(1)
  elsif line =~ /^\s*end\s*$/
    table = nil
  elsif table && line =~ /^\s*t\.\w+ "([^"]+_id)"(.*)$/
    schema[[table, Regexp.last_match(1)]] = Regexp.last_match(2).include?('null: false') ? 'NO' : 'YES'
  end
end
database = {}
File.foreach(ARGV[1]) do |line|
  table_name, column_name, is_nullable = line.strip.split(',')
  next if table_name == 'table_name' || table_name.nil?
  database[[table_name, column_name]] = is_nullable
end
mismatches = (schema.keys | database.keys).sort.filter_map do |key|
  next if schema[key] == database[key]
  "#{key.join('.')}: schema.rb=#{schema[key] || 'absent'} database=#{database[key] || 'absent'}"
end
puts "schema.rb columns=#{schema.size} database columns=#{database.size}"
puts(mismatches.empty? ? 'OK: no nullability mismatch' : mismatches)
exit(mismatches.empty? ? 0 : 1)
```

Then:

```bash
heroku pg:psql --app insgtapi -c "COPY (SELECT table_name, column_name, is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND column_name LIKE '%\_id' ORDER BY 1, 2) TO STDOUT CSV HEADER" > tmp/prod-columns-2026-11-09.csv
wc -l tmp/prod-columns-2026-11-09.csv
ruby tmp/nullability_diff.rb db/schema.rb tmp/prod-columns-2026-11-09.csv
```

Expected: `220` (219 columns and the header); `schema.rb columns=219 database columns=219` then `OK: no nullability mismatch` (exit 0). **Any mismatch line is a STOP** before the classification is trusted (§4.5). Locally: `rows=219`, `schema.rb columns=219 database columns=219`, `OK: no nullability mismatch` (fact 9). Observed: (gate).

(`\_` inside a double-quoted bash string reaches psql unchanged, and `COPY … TO STDOUT` needs no file privilege. If `-c` is refused, put the same statement in `tmp/columns.sql` and run `heroku pg:psql --app insgtapi < tmp/columns.sql`.)

### The null-count report (§4.5 scope 5; §8 item 15's candidates)

Save as `tmp/null-counts.sql` — one query per nullable FK column behind a `belongs_to`, N1–N39; the `FILTER` columns count active rows so that a column full only among deleted rows is not mistaken for a candidate:

```sql
SELECT 'accounts.marketing_source_id' AS col, COUNT(*) AS rows, COUNT(marketing_source_id) AS populated, COUNT(*) - COUNT(marketing_source_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(marketing_source_id) FILTER (WHERE status_type = 1) AS active_populated FROM accounts;
SELECT 'areas.city_id' AS col, COUNT(*) AS rows, COUNT(city_id) AS populated, COUNT(*) - COUNT(city_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(city_id) FILTER (WHERE status_type = 1) AS active_populated FROM areas;
SELECT 'areas.area_type_id' AS col, COUNT(*) AS rows, COUNT(area_type_id) AS populated, COUNT(*) - COUNT(area_type_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(area_type_id) FILTER (WHERE status_type = 1) AS active_populated FROM areas;
SELECT 'carts.user_id' AS col, COUNT(*) AS rows, COUNT(user_id) AS populated, COUNT(*) - COUNT(user_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(user_id) FILTER (WHERE status_type = 1) AS active_populated FROM carts;
SELECT 'carts.account_id' AS col, COUNT(*) AS rows, COUNT(account_id) AS populated, COUNT(*) - COUNT(account_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(account_id) FILTER (WHERE status_type = 1) AS active_populated FROM carts;
SELECT 'headshots.user_id' AS col, COUNT(*) AS rows, COUNT(user_id) AS populated, COUNT(*) - COUNT(user_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(user_id) FILTER (WHERE status_type = 1) AS active_populated FROM headshots;
SELECT 'listings.user_id' AS col, COUNT(*) AS rows, COUNT(user_id) AS populated, COUNT(*) - COUNT(user_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(user_id) FILTER (WHERE status_type = 1) AS active_populated FROM listings;
SELECT 'listings.second_account_id' AS col, COUNT(*) AS rows, COUNT(second_account_id) AS populated, COUNT(*) - COUNT(second_account_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(second_account_id) FILTER (WHERE status_type = 1) AS active_populated FROM listings;
SELECT 'listings.second_user_id' AS col, COUNT(*) AS rows, COUNT(second_user_id) AS populated, COUNT(*) - COUNT(second_user_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(second_user_id) FILTER (WHERE status_type = 1) AS active_populated FROM listings;
SELECT 'listings.property_type_id' AS col, COUNT(*) AS rows, COUNT(property_type_id) AS populated, COUNT(*) - COUNT(property_type_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(property_type_id) FILTER (WHERE status_type = 1) AS active_populated FROM listings;
SELECT 'marketing_events.order_id' AS col, COUNT(*) AS rows, COUNT(order_id) AS populated, COUNT(*) - COUNT(order_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(order_id) FILTER (WHERE status_type = 1) AS active_populated FROM marketing_events;
SELECT 'marketing_events.organization_id' AS col, COUNT(*) AS rows, COUNT(organization_id) AS populated, COUNT(*) - COUNT(organization_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(organization_id) FILTER (WHERE status_type = 1) AS active_populated FROM marketing_events;
SELECT 'notifications.order_event_id' AS col, COUNT(*) AS rows, COUNT(order_event_id) AS populated, COUNT(*) - COUNT(order_event_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(order_event_id) FILTER (WHERE status_type = 1) AS active_populated FROM notifications;
SELECT 'orders.parent_id' AS col, COUNT(*) AS rows, COUNT(parent_id) AS populated, COUNT(*) - COUNT(parent_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(parent_id) FILTER (WHERE status_type = 1) AS active_populated FROM orders;
SELECT 'orders.property_id' AS col, COUNT(*) AS rows, COUNT(property_id) AS populated, COUNT(*) - COUNT(property_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(property_id) FILTER (WHERE status_type = 1) AS active_populated FROM orders;
SELECT 'orders.sales_type_id' AS col, COUNT(*) AS rows, COUNT(sales_type_id) AS populated, COUNT(*) - COUNT(sales_type_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(sales_type_id) FILTER (WHERE status_type = 1) AS active_populated FROM orders;
SELECT 'orders.order_event_id' AS col, COUNT(*) AS rows, COUNT(order_event_id) AS populated, COUNT(*) - COUNT(order_event_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(order_event_id) FILTER (WHERE status_type = 1) AS active_populated FROM orders;
SELECT 'orders.marketing_event_id' AS col, COUNT(*) AS rows, COUNT(marketing_event_id) AS populated, COUNT(*) - COUNT(marketing_event_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(marketing_event_id) FILTER (WHERE status_type = 1) AS active_populated FROM orders;
SELECT 'orders.listing_id' AS col, COUNT(*) AS rows, COUNT(listing_id) AS populated, COUNT(*) - COUNT(listing_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(listing_id) FILTER (WHERE status_type = 1) AS active_populated FROM orders;
SELECT 'order_logs.notification_id' AS col, COUNT(*) AS rows, COUNT(notification_id) AS populated, COUNT(*) - COUNT(notification_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(notification_id) FILTER (WHERE status_type = 1) AS active_populated FROM order_logs;
SELECT 'order_services.discount_id' AS col, COUNT(*) AS rows, COUNT(discount_id) AS populated, COUNT(*) - COUNT(discount_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(discount_id) FILTER (WHERE status_type = 1) AS active_populated FROM order_services;
SELECT 'order_urls.order_url_group_id' AS col, COUNT(*) AS rows, COUNT(order_url_group_id) AS populated, COUNT(*) - COUNT(order_url_group_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(order_url_group_id) FILTER (WHERE status_type = 1) AS active_populated FROM order_urls;
SELECT 'order_url_groups.order_id' AS col, COUNT(*) AS rows, COUNT(order_id) AS populated, COUNT(*) - COUNT(order_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(order_id) FILTER (WHERE status_type = 1) AS active_populated FROM order_url_groups;
SELECT 'organizations.property_id' AS col, COUNT(*) AS rows, COUNT(property_id) AS populated, COUNT(*) - COUNT(property_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(property_id) FILTER (WHERE status_type = 1) AS active_populated FROM organizations;
SELECT 'organizations.parent_id' AS col, COUNT(*) AS rows, COUNT(parent_id) AS populated, COUNT(*) - COUNT(parent_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(parent_id) FILTER (WHERE status_type = 1) AS active_populated FROM organizations;
SELECT 'organizations.marketing_source_id' AS col, COUNT(*) AS rows, COUNT(marketing_source_id) AS populated, COUNT(*) - COUNT(marketing_source_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(marketing_source_id) FILTER (WHERE status_type = 1) AS active_populated FROM organizations;
SELECT 'photos.order_id' AS col, COUNT(*) AS rows, COUNT(order_id) AS populated, COUNT(*) - COUNT(order_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(order_id) FILTER (WHERE status_type = 1) AS active_populated FROM photos;
SELECT 'photos.property_id' AS col, COUNT(*) AS rows, COUNT(property_id) AS populated, COUNT(*) - COUNT(property_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(property_id) FILTER (WHERE status_type = 1) AS active_populated FROM photos;
SELECT 'photos.photographer_id' AS col, COUNT(*) AS rows, COUNT(photographer_id) AS populated, COUNT(*) - COUNT(photographer_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(photographer_id) FILTER (WHERE status_type = 1) AS active_populated FROM photos;
SELECT 'photos.processor_id' AS col, COUNT(*) AS rows, COUNT(processor_id) AS populated, COUNT(*) - COUNT(processor_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(processor_id) FILTER (WHERE status_type = 1) AS active_populated FROM photos;
SELECT 'photos.photo_scene_type_id' AS col, COUNT(*) AS rows, COUNT(photo_scene_type_id) AS populated, COUNT(*) - COUNT(photo_scene_type_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(photo_scene_type_id) FILTER (WHERE status_type = 1) AS active_populated FROM photos;
SELECT 'properties.postal_code_id' AS col, COUNT(*) AS rows, COUNT(postal_code_id) AS populated, COUNT(*) - COUNT(postal_code_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(postal_code_id) FILTER (WHERE status_type = 1) AS active_populated FROM properties;
SELECT 'properties.city_id' AS col, COUNT(*) AS rows, COUNT(city_id) AS populated, COUNT(*) - COUNT(city_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(city_id) FILTER (WHERE status_type = 1) AS active_populated FROM properties;
SELECT 'properties.ai_property_type_id' AS col, COUNT(*) AS rows, COUNT(ai_property_type_id) AS populated, COUNT(*) - COUNT(ai_property_type_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(ai_property_type_id) FILTER (WHERE status_type = 1) AS active_populated FROM properties;
SELECT 'properties.edited_property_type_id' AS col, COUNT(*) AS rows, COUNT(edited_property_type_id) AS populated, COUNT(*) - COUNT(edited_property_type_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(edited_property_type_id) FILTER (WHERE status_type = 1) AS active_populated FROM properties;
SELECT 'raw_photos.photo_id' AS col, COUNT(*) AS rows, COUNT(photo_id) AS populated, COUNT(*) - COUNT(photo_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(photo_id) FILTER (WHERE status_type = 1) AS active_populated FROM raw_photos;
SELECT 'services.order_type_id' AS col, COUNT(*) AS rows, COUNT(order_type_id) AS populated, COUNT(*) - COUNT(order_type_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(order_type_id) FILTER (WHERE status_type = 1) AS active_populated FROM services;
SELECT 'tags.tag_category_id' AS col, COUNT(*) AS rows, COUNT(tag_category_id) AS populated, COUNT(*) - COUNT(tag_category_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(tag_category_id) FILTER (WHERE status_type = 1) AS active_populated FROM tags;
SELECT 'tags.parent_id' AS col, COUNT(*) AS rows, COUNT(parent_id) AS populated, COUNT(*) - COUNT(parent_id) AS nulls, COUNT(*) FILTER (WHERE status_type = 1) AS active_rows, COUNT(parent_id) FILTER (WHERE status_type = 1) AS active_populated FROM tags;
```

```bash
heroku pg:psql --app insgtapi --file tmp/null-counts.sql > tmp/null-counts-2026-11-09.txt     # or: heroku pg:psql --app insgtapi < tmp/null-counts.sql
```

Expected per row: a count — there is no pass or fail; `nulls` = 0 marks a §8 item 15 candidate (locally five: `areas.city_id`, `areas.area_type_id`, `notifications.order_event_id`, `order_url_groups.order_id`, `photos.order_id`). Executed locally: 39 queries, 0 errors. Observed: (gate).

| # | Column | Expected | Observed (gate) |
| :-- | :-- | :-- | :-- |
| N1 | `accounts.marketing_source_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N2 | `areas.city_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N3 | `areas.area_type_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N4 | `carts.user_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N5 | `carts.account_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N6 | `headshots.user_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N7 | `listings.user_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N8 | `listings.second_account_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N9 | `listings.second_user_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N10 | `listings.property_type_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N11 | `marketing_events.order_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N12 | `marketing_events.organization_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N13 | `notifications.order_event_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N14 | `orders.parent_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N15 | `orders.property_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N16 | `orders.sales_type_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N17 | `orders.order_event_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N18 | `orders.marketing_event_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N19 | `orders.listing_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N20 | `order_logs.notification_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N21 | `order_services.discount_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N22 | `order_urls.order_url_group_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N23 | `order_url_groups.order_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N24 | `organizations.property_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N25 | `organizations.parent_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N26 | `organizations.marketing_source_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N27 | `photos.order_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N28 | `photos.property_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N29 | `photos.photographer_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N30 | `photos.processor_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N31 | `photos.photo_scene_type_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N32 | `properties.postal_code_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N33 | `properties.city_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N34 | `properties.ai_property_type_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N35 | `properties.edited_property_type_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N36 | `raw_photos.photo_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N37 | `services.order_type_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N38 | `tags.tag_category_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |
| N39 | `tags.parent_id` | a count per column; `nulls` = 0 marks a §8 item 15 candidate | |

### The dangling-key report (§4.5 scope 5's ADDED recommendation; S13 re-runs it)

Save as `tmp/dangling.sql` — one query per `NOT NULL` FK column behind a required association, D1–D47; `tags_resources.resource_id` by type, D48–D50; the type guard, D51; the type distribution, D52:

```sql
SELECT 'account_metrics.account_id' AS col, COUNT(*) AS dangling FROM account_metrics t LEFT JOIN accounts x ON x.id = t.account_id WHERE x.id IS NULL;
SELECT 'accounts_organizations.account_id' AS col, COUNT(*) AS dangling FROM accounts_organizations t LEFT JOIN accounts x ON x.id = t.account_id WHERE x.id IS NULL;
SELECT 'accounts_organizations.organization_id' AS col, COUNT(*) AS dangling FROM accounts_organizations t LEFT JOIN organizations x ON x.id = t.organization_id WHERE x.id IS NULL;
SELECT 'accounts_users.account_id' AS col, COUNT(*) AS dangling FROM accounts_users t LEFT JOIN accounts x ON x.id = t.account_id WHERE x.id IS NULL;
SELECT 'accounts_users.user_id' AS col, COUNT(*) AS dangling FROM accounts_users t LEFT JOIN users x ON x.id = t.user_id WHERE x.id IS NULL;
SELECT 'accounts_users.role_id' AS col, COUNT(*) AS dangling FROM accounts_users t LEFT JOIN roles x ON x.id = t.role_id WHERE x.id IS NULL;
SELECT 'areas_properties.area_id' AS col, COUNT(*) AS dangling FROM areas_properties t LEFT JOIN areas x ON x.id = t.area_id WHERE x.id IS NULL;
SELECT 'areas_properties.property_id' AS col, COUNT(*) AS dangling FROM areas_properties t LEFT JOIN properties x ON x.id = t.property_id WHERE x.id IS NULL;
SELECT 'cities.state_id' AS col, COUNT(*) AS dangling FROM cities t LEFT JOIN states x ON x.id = t.state_id WHERE x.id IS NULL;
SELECT 'floorplans.order_id' AS col, COUNT(*) AS dangling FROM floorplans t LEFT JOIN orders x ON x.id = t.order_id WHERE x.id IS NULL;
SELECT 'flyers.listing_id' AS col, COUNT(*) AS dangling FROM flyers t LEFT JOIN listings x ON x.id = t.listing_id WHERE x.id IS NULL;
SELECT 'flyers_photos.flyer_id' AS col, COUNT(*) AS dangling FROM flyers_photos t LEFT JOIN flyers x ON x.id = t.flyer_id WHERE x.id IS NULL;
SELECT 'flyers_photos.photo_id' AS col, COUNT(*) AS dangling FROM flyers_photos t LEFT JOIN photos x ON x.id = t.photo_id WHERE x.id IS NULL;
SELECT 'listing_descriptions.listing_id' AS col, COUNT(*) AS dangling FROM listing_descriptions t LEFT JOIN listings x ON x.id = t.listing_id WHERE x.id IS NULL;
SELECT 'listing_photos.listing_id' AS col, COUNT(*) AS dangling FROM listing_photos t LEFT JOIN listings x ON x.id = t.listing_id WHERE x.id IS NULL;
SELECT 'listing_photos.photo_id' AS col, COUNT(*) AS dangling FROM listing_photos t LEFT JOIN photos x ON x.id = t.photo_id WHERE x.id IS NULL;
SELECT 'listing_property_features.listing_id' AS col, COUNT(*) AS dangling FROM listing_property_features t LEFT JOIN listings x ON x.id = t.listing_id WHERE x.id IS NULL;
SELECT 'listing_property_features.property_feature_id' AS col, COUNT(*) AS dangling FROM listing_property_features t LEFT JOIN property_features x ON x.id = t.property_feature_id WHERE x.id IS NULL;
SELECT 'listing_rooms.listing_id' AS col, COUNT(*) AS dangling FROM listing_rooms t LEFT JOIN listings x ON x.id = t.listing_id WHERE x.id IS NULL;
SELECT 'listing_rooms.room_type_id' AS col, COUNT(*) AS dangling FROM listing_rooms t LEFT JOIN room_types x ON x.id = t.room_type_id WHERE x.id IS NULL;
SELECT 'marketing_event_imports.marketing_event_id' AS col, COUNT(*) AS dangling FROM marketing_event_imports t LEFT JOIN marketing_events x ON x.id = t.marketing_event_id WHERE x.id IS NULL;
SELECT 'marketing_event_imports.order_type_id' AS col, COUNT(*) AS dangling FROM marketing_event_imports t LEFT JOIN order_types x ON x.id = t.order_type_id WHERE x.id IS NULL;
SELECT 'mls_imports.organization_id' AS col, COUNT(*) AS dangling FROM mls_imports t LEFT JOIN organizations x ON x.id = t.organization_id WHERE x.id IS NULL;
SELECT 'mls_listings.listing_id' AS col, COUNT(*) AS dangling FROM mls_listings t LEFT JOIN listings x ON x.id = t.listing_id WHERE x.id IS NULL;
SELECT 'mls_listings.organization_id' AS col, COUNT(*) AS dangling FROM mls_listings t LEFT JOIN organizations x ON x.id = t.organization_id WHERE x.id IS NULL;
SELECT 'mls_metadata_caches.organization_id' AS col, COUNT(*) AS dangling FROM mls_metadata_caches t LEFT JOIN organizations x ON x.id = t.organization_id WHERE x.id IS NULL;
SELECT 'notification_audiences.notification_id' AS col, COUNT(*) AS dangling FROM notification_audiences t LEFT JOIN notifications x ON x.id = t.notification_id WHERE x.id IS NULL;
SELECT 'notification_audiences.role_id' AS col, COUNT(*) AS dangling FROM notification_audiences t LEFT JOIN roles x ON x.id = t.role_id WHERE x.id IS NULL;
SELECT 'orders.account_id' AS col, COUNT(*) AS dangling FROM orders t LEFT JOIN accounts x ON x.id = t.account_id WHERE x.id IS NULL;
SELECT 'orders.order_type_id' AS col, COUNT(*) AS dangling FROM orders t LEFT JOIN order_types x ON x.id = t.order_type_id WHERE x.id IS NULL;
SELECT 'order_logs.order_id' AS col, COUNT(*) AS dangling FROM order_logs t LEFT JOIN orders x ON x.id = t.order_id WHERE x.id IS NULL;
SELECT 'order_logs.order_event_id' AS col, COUNT(*) AS dangling FROM order_logs t LEFT JOIN order_events x ON x.id = t.order_event_id WHERE x.id IS NULL;
SELECT 'order_services.order_id' AS col, COUNT(*) AS dangling FROM order_services t LEFT JOIN orders x ON x.id = t.order_id WHERE x.id IS NULL;
SELECT 'order_services.service_id' AS col, COUNT(*) AS dangling FROM order_services t LEFT JOIN services x ON x.id = t.service_id WHERE x.id IS NULL;
SELECT 'order_types_services.order_type_id' AS col, COUNT(*) AS dangling FROM order_types_services t LEFT JOIN order_types x ON x.id = t.order_type_id WHERE x.id IS NULL;
SELECT 'order_types_services.service_id' AS col, COUNT(*) AS dangling FROM order_types_services t LEFT JOIN services x ON x.id = t.service_id WHERE x.id IS NULL;
SELECT 'order_urls.order_id' AS col, COUNT(*) AS dangling FROM order_urls t LEFT JOIN orders x ON x.id = t.order_id WHERE x.id IS NULL;
SELECT 'orders_users.order_id' AS col, COUNT(*) AS dangling FROM orders_users t LEFT JOIN orders x ON x.id = t.order_id WHERE x.id IS NULL;
SELECT 'orders_users.user_id' AS col, COUNT(*) AS dangling FROM orders_users t LEFT JOIN users x ON x.id = t.user_id WHERE x.id IS NULL;
SELECT 'orders_users.role_id' AS col, COUNT(*) AS dangling FROM orders_users t LEFT JOIN roles x ON x.id = t.role_id WHERE x.id IS NULL;
SELECT 'postal_code_associations.postal_code_id' AS col, COUNT(*) AS dangling FROM postal_code_associations t LEFT JOIN postal_codes x ON x.id = t.postal_code_id WHERE x.id IS NULL;
SELECT 'raw_photos.order_id' AS col, COUNT(*) AS dangling FROM raw_photos t LEFT JOIN orders x ON x.id = t.order_id WHERE x.id IS NULL;
SELECT 'schedules.user_id' AS col, COUNT(*) AS dangling FROM schedules t LEFT JOIN users x ON x.id = t.user_id WHERE x.id IS NULL;
SELECT 'states.country_id' AS col, COUNT(*) AS dangling FROM states t LEFT JOIN countries x ON x.id = t.country_id WHERE x.id IS NULL;
SELECT 'tags_resources.tag_id' AS col, COUNT(*) AS dangling FROM tags_resources t LEFT JOIN tags x ON x.id = t.tag_id WHERE x.id IS NULL;
SELECT 'transactions.order_id' AS col, COUNT(*) AS dangling FROM transactions t LEFT JOIN orders x ON x.id = t.order_id WHERE x.id IS NULL;
SELECT 'unaltered_photos.photo_id' AS col, COUNT(*) AS dangling FROM unaltered_photos t LEFT JOIN photos x ON x.id = t.photo_id WHERE x.id IS NULL;
SELECT 'tags_resources.resource_id (resource_type 1 → users)' AS col, COUNT(*) AS dangling FROM tags_resources t LEFT JOIN users x ON x.id = t.resource_id WHERE t.resource_type = 1 AND x.id IS NULL;
SELECT 'tags_resources.resource_id (resource_type 3 → properties)' AS col, COUNT(*) AS dangling FROM tags_resources t LEFT JOIN properties x ON x.id = t.resource_id WHERE t.resource_type = 3 AND x.id IS NULL;
SELECT 'tags_resources.resource_id (resource_type 7 → photos)' AS col, COUNT(*) AS dangling FROM tags_resources t LEFT JOIN photos x ON x.id = t.resource_id WHERE t.resource_type = 7 AND x.id IS NULL;
SELECT 'tags_resources.resource_type (not 1, 3 or 7)' AS col, COUNT(*) AS dangling FROM tags_resources t WHERE t.resource_type NOT IN (1, 3, 7);
SELECT 'tags_resources.resource_type distribution' AS col, string_agg(resource_type::text || ':' || n::text, ', ' ORDER BY resource_type) AS dangling FROM (SELECT resource_type, COUNT(*) AS n FROM tags_resources GROUP BY 1) s;
```

```bash
heroku pg:psql --app insgtapi --file tmp/dangling.sql > tmp/dangling-2026-11-09.txt     # or: heroku pg:psql --app insgtapi < tmp/dangling.sql
```

Expected: `0` on every row D1–D51; D52 lists only types `1`, `3` and `7`. **Decision rule (decision 5):** all zero → proceed; rows on any column other than D29, D39, D50 → STOP; D29, D39 or D50 above 2, 27 or 32 → STOP (a live writer); at or below → recorded in the runbook with the id queries below, and S13 pins the observed counts. No migration either way (§8 item 15). Executed locally: 52 queries, 0 errors. Locally D29 (`orders.account_id`) = 2, D39 (`orders_users.user_id`) = 27, D50 (photo-typed `tags_resources.resource_id`) = 32, every other row 0, D52 = `1:4652, 7:717874` (fact 9) — local, not the observation. Observed: (gate).

Naming the rows when a count is non-zero (read-only; the three the restore predicts):

```sql
SELECT o.id, o.account_id, o.status_type, o.created_at::date FROM orders o LEFT JOIN accounts a ON a.id = o.account_id WHERE a.id IS NULL ORDER BY o.id;
SELECT ou.user_id, COUNT(*) AS rows, MIN(ou.created_at)::date AS first, MAX(ou.created_at)::date AS last, COUNT(*) FILTER (WHERE ou.status_type = 1) AS active FROM orders_users ou LEFT JOIN users u ON u.id = ou.user_id WHERE u.id IS NULL GROUP BY 1 ORDER BY 1;
SELECT t.id, t.resource_id, t.tag_id, t.status_type, t.created_at::date FROM tags_resources t LEFT JOIN photos p ON p.id = t.resource_id WHERE t.resource_type = 7 AND p.id IS NULL ORDER BY t.id;
```

Locally (not the observation): orders `2827` (status 2, 2016-11-02, account 873) and `4302` (status 1, 2017-07-05, account 1190); `orders_users` 27 rows all with `user_id = 0` (2017-07-07 … 2019-05-02, 24 active); 32 photo tags, all active, all 2025-06-17.

| # | Column | Expected | Observed (gate) |
| :-- | :-- | :-- | :-- |
| D1 | `account_metrics.account_id` | `0` | |
| D2 | `accounts_organizations.account_id` | `0` | |
| D3 | `accounts_organizations.organization_id` | `0` | |
| D4 | `accounts_users.account_id` | `0` | |
| D5 | `accounts_users.user_id` | `0` | |
| D6 | `accounts_users.role_id` | `0` | |
| D7 | `areas_properties.area_id` | `0` | |
| D8 | `areas_properties.property_id` | `0` | |
| D9 | `cities.state_id` | `0` | |
| D10 | `floorplans.order_id` | `0` | |
| D11 | `flyers.listing_id` | `0` | |
| D12 | `flyers_photos.flyer_id` | `0` | |
| D13 | `flyers_photos.photo_id` | `0` | |
| D14 | `listing_descriptions.listing_id` | `0` | |
| D15 | `listing_photos.listing_id` | `0` | |
| D16 | `listing_photos.photo_id` | `0` | |
| D17 | `listing_property_features.listing_id` | `0` | |
| D18 | `listing_property_features.property_feature_id` | `0` | |
| D19 | `listing_rooms.listing_id` | `0` | |
| D20 | `listing_rooms.room_type_id` | `0` | |
| D21 | `marketing_event_imports.marketing_event_id` | `0` | |
| D22 | `marketing_event_imports.order_type_id` | `0` | |
| D23 | `mls_imports.organization_id` | `0` | |
| D24 | `mls_listings.listing_id` | `0` | |
| D25 | `mls_listings.organization_id` | `0` | |
| D26 | `mls_metadata_caches.organization_id` | `0` | |
| D27 | `notification_audiences.notification_id` | `0` | |
| D28 | `notification_audiences.role_id` | `0` | |
| D29 | `orders.account_id` | `0` | |
| D30 | `orders.order_type_id` | `0` | |
| D31 | `order_logs.order_id` | `0` | |
| D32 | `order_logs.order_event_id` | `0` | |
| D33 | `order_services.order_id` | `0` | |
| D34 | `order_services.service_id` | `0` | |
| D35 | `order_types_services.order_type_id` | `0` | |
| D36 | `order_types_services.service_id` | `0` | |
| D37 | `order_urls.order_id` | `0` | |
| D38 | `orders_users.order_id` | `0` | |
| D39 | `orders_users.user_id` | `0` | |
| D40 | `orders_users.role_id` | `0` | |
| D41 | `postal_code_associations.postal_code_id` | `0` | |
| D42 | `raw_photos.order_id` | `0` | |
| D43 | `schedules.user_id` | `0` | |
| D44 | `states.country_id` | `0` | |
| D45 | `tags_resources.tag_id` | `0` | |
| D46 | `transactions.order_id` | `0` | |
| D47 | `unaltered_photos.photo_id` | `0` | |
| D48 | `tags_resources.resource_id (resource_type 1 → users)` | `0` | |
| D49 | `tags_resources.resource_id (resource_type 3 → properties)` | `0` | |
| D50 | `tags_resources.resource_id (resource_type 7 → photos)` | `0` | |
| D51 | `tags_resources.resource_type (not 1, 3 or 7)` | `0` | |
| D52 | `tags_resources.resource_type distribution` | only `1:`, `3:` and `7:` entries | |

## Post-deploy verification

**Pre-deploy, on the branch** (§4.0 with `8.1.4`; reasoned now): P1 `N examples, 0 failures` (ESTIMATE 2,072; not a criterion) and `0` `DEPRECATION WARNING` lines, twice (plain and `CI=1`); P2 "All is good!"; P3 on its own queue (`slice4_p3`), the four log lines with `Booted Rails 8.1.4`, status `nil` recorded; P4 4 examples, 0 failures; P5 0 failures; P6 `SystemError::rails upgrade`; P7 0 failures; P8 `200`, `image/jpeg`; **P-PROD exactly as `deploy-rails-upgrade-3.md` step 2 prints it** — the wrapper and its expected lines are cited, not reproduced (trap 5): `"8.1.4"`, the three `[:notify]` pairs, `7.2`, `583`, `0` `DEPRECATION` lines. Routes: `bin/rails routes` identical to `master`'s 583 lines — this slice adds no route.

**On the Mac, before the push** (on v666 or the then-current release): the three reports above with their observed values; the S4 and S6 captures as runbook 3 step 3; and `heroku run --no-tty --app insgtapi rails runner 'puts AreasProperty.unscoped.count'` recorded for S12. **Not** the S12 request itself: on v666 it answers 500 and files an `ActiveRecord::NotNullViolation` that SH would then have to exclude; the "before" is fact 7's local capture (decision 4).

**Production spot checks, within 30 minutes of the push** (`RELEASE` from `heroku releases -n 1` first):

| # | Command (from the Mac) | Expected |
| :-- | :-- | :-- |
| S0 | the marker runner with `slice 4` and `$RELEASE` | `UpgradeMarker` gains an occurrence, context `rails: 8.1.4` |
| S1 | `curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up` | `200`; the uptime monitor stays green |
| S2 | `heroku ps --app insgtapi`; `heroku logs --ps backgroundworker.1 -n 300 --app insgtapi \| grep Booted` | all dynos up; `Booted Rails 8.1.4 application in production environment` |
| S3 | as §4.0 v6 writes it — `Rails.version` and the config-hash `key?` probe; the exact runner is runbook 3 step 5's and is not reproduced here (trap 5) | `8.1.4`, `false` |
| S4, S5, S6 | as §4.0 (S4 with `map`; S6 with `slice 4`) | identical to the capture; `true`; `SystemError::rails upgrade slice 4` arrives |
| S10 | `heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'` | `7.2` |
| **S12** | `curl -sS -w "\n%{http_code}\n" -X POST -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"areasProperty":{"areaId":<an existing area id>}}' https://api.insightphotos.net/areas_properties` — `$JWT` from an insgt-ops session, as S-404 used; `areaId` reaches the controller as `area_id` through `json_param_key_transform.rb`; the id from `heroku run --no-tty --app insgtapi rails runner 'puts Area.unscoped.order(:id).first.id'` | `{"errors":["Property must exist"]}` and `422`; then `AreasProperty.unscoped.count` unchanged from the pre-push capture (nothing written). A `500` after the push is the rollback signal (decision 4) |
| S7 | one hour after: the saved buffer exactly as runbook 3 step 6, plus `grep -c "status=422" /tmp/s7.log` (R2's lograge reading) and `grep -c "NotNullViolation" /tmp/s7.log` | `0` `status=5`; no class other than `ActionController::RoutingError`; the 422 count recorded beside the same count from a pre-push buffer (not a criterion); `0` `NotNullViolation` |
| S9 | the next hourly `import_listings` check-in, judged in UTC | on time |
| **S13** | `heroku pg:psql --app insgtapi --file tmp/dangling.sql > tmp/dangling-after.txt; diff tmp/dangling-2026-11-09.txt tmp/dangling-after.txt` | empty — every row `0`, and D29, D39, D50 equal to the pre-push observation (decision 5c pins the three counts); a new non-zero row, or a higher count, is a finding |
| **SH** | 24 h later, Honeybadger: `environment:"production" created.after:"<push>"` (every error, triaged by backtrace); `environment:"production" class:"ActiveRecord::RecordInvalid" occurred.after:"<push>"`; `environment:"production" class:"ActiveRecord::NotNullViolation" occurred.after:"<push>"`; `environment:"production" class:"RailsDeprecation" occurred.after:"<push>"` | **Pass condition:** no `RecordInvalid` whose message contains `must exist` from a path that calls `save!` (`app/services/account_metrics/calculator.rb:25` is the one `save!` site among the 17 models — a missing account there was a `NotNullViolation` before and is a `RecordInvalid` after, both a failed job, neither expected); **no `ActiveRecord::NotNullViolation` at all**; no new error whose backtrace touches `tags_resource.rb`, `area.rb`, `listing.rb`, `order_url_group.rb`, the shim or `associations/builder/belongs_to.rb`; no new `RailsDeprecation`. Anything else is an old bug seen for the first time — recorded, fixed on its own branch |

**Rolling deploy**: no migration, no DDL, no ENV change; a Heroku release swaps all dynos at once, and the schema is the same on both sides. **Rollback**: `heroku rollback --app insgtapi` to the slice 3 release (v666, or the then-current one). Nothing to undo: the slice writes no data, and the dangling rows are exactly as they were.

### Runbook outline — `docs/runbooks/deploy-rails-upgrade-4.md`

Platform repo, same location as `deploy-rails-upgrade-3.md`, written in the implementation session, `Draft` until the review, in slice 3's sections: **Summary** (the four commits; "what moves for a human": 17 create or key-change paths answer 422 `must exist` instead of 500; 30 paths' 422 bodies gain a `must exist` line beside `can't be blank`; `TagsResource` rows naming a missing user, property or photo are refused — through the API as 422, in `photo.rb:251`/`:300` silently, since those sites ignore `create`'s return value; nothing else visible; the position in the remaining schedule — 5a Tue 11-10, 5b Wed 11-11, the quiet week, the Render rehearsal) · **Where the commands run** · **Deploy window** (Mon 2026-11-09, 09:00–11:30 PT; slippage Tue 11-10 then Wed 11-11, each moving 5a and 5b by a day — §6) · **Prerequisites** (two quiet weekdays with the three Honeybadger searches; the nullability STOP's `OK`; the null-count and dangling-key observations pasted; the gate's disposition of any named rows; two review rounds; the merge suite green) · **Pre-deploy** (step 1 the development table P1–P8 and P-PROD; step 2 the three reports with RESULTS; step 3 the pre-push captures including `AreasProperty.unscoped.count`) · **Deploy** · **Within 30 minutes** (S0–S6, S10, S12) · **One hour** (S7 with the 422 and `NotNullViolation` counts; S9) · **24 hours** (SH's four searches and the pass condition; S13) · **Rollback** · **Known, kept by decision** (the WARN line; the doubled messages; the named dangling rows if waived, with fact 6's explanation of why they still save; the §8 item 15 candidates) · **After the deploy — write-back** · **Deploy log**.

### Risks

- **R2 (§5), narrowed by fact 6** — a create, or a key reassigned to a missing row, that used to raise `NotNullViolation` now answers 422 on 17 paths or raises `RecordInvalid` at the one `save!` site; an existing row with a dangling key keeps saving unless its key is reassigned to another missing row. Detection: S7's `status=5` and `NotNullViolation` counts, SH's `RecordInvalid` search, S13.
- **The three dangling columns the restore predicts** (fact 9) — the STOP fires on the Mac before anything ships; decision 5 makes the rule exact. If at or below the restore's counts, recorded and not stopped on: the 27 `user_id = 0` rows are the `OrdersUser` rows that `OrdersUser.add_user`'s update paths (`orders_user.rb:38–47`) would reassign to a real user, which the validation allows; the two orders save unless their account is reassigned to another missing one; the 32 photo tags soft-delete and update as before.
- **`Rails.application.eager_load!` inside the contract spec** — loads every application class in a plain `rspec` run; the `CI=1` run already does this and is green on 8.1.4 (slice 3's P1), and the deprecation gate is `:raise` in both, so no class-body deprecation can hide behind it.
- **A `TagsResource` create with a `resource_type` other than 1, 3 or 7** now fails; D51 and D52 prove none exists; the API create (`tags_resources_controller.rb:41`) is the only path that accepts a caller-supplied type.
- **The two extra statements for `Order#account` on every create by id** (fact 8) — the association scope's `eager_load` (`order.rb:90`) is the cost, already paid by every read of `order.account`; ESTIMATE under 2 ms per create; nothing is computed differently.
- **Timing** — two quiet weekdays after v666 (Tue, Wed), review Thu 11-05, push Mon 11-09; a slip moves 5a and 5b with it (§6).

### Traps — the brief's five, audited before the STOP

1. **An allowlist of association names in the spec** — excluded: the contract block's five examples name no association and no model; the shared column comes from grouping the reflections on `[model, foreign_key]` (decision 2a); `TagsResource` is named only in `spec/models/tags_resource_spec.rb`, where the structural examples still hold it to the rule like every other model.
2. **The global `belongs_to_required_by_default` reappearing; `optional: true` on a `NOT NULL` column outside the shared rule** — excluded: the contract asserts the flag is `true` (red when the line is re-added — pasted) and names any `optional:` on a `NOT NULL` unshared column (red for `OrdersUser#user` — pasted); before each commit, `grep -rn belongs_to_required_by_default config app` must be empty after commit 4.
3. **A spec fixed by a factory swap; a message changed to pass a spec** — excluded: no existing spec changes (fact 4's empty list), and the new validation uses the framework's `:required` message, which the request spec asserts verbatim.
4. **An opportunistic refactor; a gem major bump; a `load_defaults` change; `StrongMigrations.target_version`; a Ruby or Postgres version change** — excluded: the diff is one deleted association, three options, three shim lines, one validation and three spec files; the 30 duplicate column validators stay (decision 7); `Gemfile`, `Gemfile.lock`, `config/application.rb`, `config/initializers/strong_migrations.rb` and `.ruby-version` are untouched, which the review diffs.
5. **(v6) A call to the 8.1-deprecated time-zone reader anywhere — spec, probe or runbook** — excluded, and grep-verifiable: a `grep -c` of this file for the reader's name (the `ActiveSupport` method §4.0 S3 forbids on 8.1, whose name ends in `preserves_timezone`) prints `0`; the name appears nowhere in this plan, including this line; S3 and P-PROD are cited by pointer to runbook 3, where the config-hash `key?` form lives; the implementation session greps its specs, probes and runbook the same way before each commit.

### Open questions for the engineer (a recommendation for each)

All nine answered 2026-11-02 as recommended (the Approval section at the top records the decisions and the modifications); kept here as asked.

1. **Where this plan file lives.** The prompt put it in insgt-api (`docs/plans/`, on `chore/rails-upgrade-slice-4`, platform repo untouched); slices 1–3's plans are platform-repo files (`/workspace/docs/plans/rails-upgrade-slice-{1,2,3}.md`; platform commits `13b97e0` and `1b77eed`), and §2.7 says every document lives there and insgt-api's `master` never carries them. Recommend **move it to the platform repo** on `docs/rails-upgrade-slice-4` at the start of the implementation session and drop this commit from the insgt-api branch (unpushed: `git reset --hard master` there), keeping the four plans together. Alternative: leave it here and accept the split. **Answered: moved to the platform repo on `docs/rails-upgrade-slice-4` off `main`; the insgt-api branch re-created with no commit.**
2. **OD10 as decided, with the photo type.** Confirm the encoding above and the validation keyed on `resource_type` over user, property and photo — §4.5's "exactly one of the two targets" cannot hold for the 717,874 photo-typed rows. Recommend **confirm as written**; the write-back settles OD10 in §7 with that correction. **Answered: confirmed, with conditions (a) structural grouping and no model named in the contract file, (b) the Rails condition on the validation — both met.**
3. **Which commit carries the `TagsResource` validation** — commit 4 (above) or a fifth commit between 3 and 4. Recommend **commit 4**. **Answered: commit 4; the pair's `optional: true` already exists and stays; the Tier 3 body names the exception.**
4. **`AreasProperty` for S12, and no deliberate 500 against production before the push.** Recommend **yes to both**: fact 7 is the "before"; a pre-push S12 on v666 would file a `NotNullViolation` in Honeybadger that SH then has to exclude. **Answered: yes to both; the runbook carries the curl; a 500 after the push is the rollback signal.**
5. **What the dangling-key STOP means, given fact 6.** The contract's rule stands in this plan (any row → STOP, no migration). If production shows the three columns the restore predicts, recommend **record the rows in the runbook and proceed** — they save unless their key is reassigned to another missing row, which is the save this slice exists to refuse — with a §8 item for the cleanup (the `user_id = 0` sentinel rows, the 32 photo tags, the two orders) rather than a repair inside this slice; S13 then expects the same rows, not zero. Alternative: hold the push until the rows are repaired on their own branch (a data fix, outside every slice's scope). **Answered: record and proceed if production matches the restore, with the exact rule (a)–(d) now in Gaps pinned 3; provenance under modification C.**
6. **Three red HEADs on the branch** (commits 1–3 fail 4, 3 and 2 contract examples respectively). Recommend **accept** — §4.5's design; the per-commit plan records each state. Alternative: fold each example into the commit that greens it (slice 3's practice). **Answered: accepted; Tier 2 bodies naming the red counts (3, 2, 1); a break on a green example at each of 1–3.**
7. **The doubled message on 30 models** (`["User must exist", "User can't be blank"]`). Recommend **accept and record** in the runbook's Known and in §8 (the column validators become redundant and come out on their own branch); dropping them now is the refactor trap 4 names. **Answered: accepted and recorded; the validators come out after slice 5 closes, a §8 item.**
8. **The `sql_for` measurement** — in the plan only, or committed as a spec asserting the SELECT counts. Recommend **plan only**; the numbers go into §4.5's write-back. **Answered: confirmed; plan only.**
9. **When** — build Tue 11-03 after slice 3's SH reads clean (ESTIMATE 7 h, below), review Thu 11-05, push **Mon 2026-11-09, 09:00–11:30 PT**, with the three production reads that morning before the merge. Recommend that; Tue 11-10 is the fallback and moves 5a and 5b by a day. **Answered: confirmed; estimate 7 h accepted.**

### Unverified

- Production's nullability, null-count and dangling-key observations (the Mac, Thursday and the morning of the push); whether the restore's three non-zero columns, at or below 2 / 27 / 32, are production's.
- Modification E's Honeybadger baseline for the 17 (Dan, before Thursday's review).
- Whether the installed Heroku CLI accepts `heroku pg:psql --file` (the `<` form is the fallback; both are read-only).
- The P1 count at commit 4's HEAD with the area and request examples (ESTIMATE 2,072; 2,068 / 0 measured without them).
- The `areas_properties` show template rendering for the happy-path request example (the 422 examples never reach it; the implementation runs it).
- `Sidekiq::Status` in production (§8 item 10); Honeybadger on this release beyond S0.
- Slice 3's S7, S9 and SH (pending at survey time).

### Estimate (hours, in the slice 2/3 form)

ESTIMATE **7 h** of implementation plus the deploy morning: commit 1, 1.0 (the block is drafted; comments, the red paste); commit 2, 0.5; commit 3, 0.5; commit 4, 1.5 (two spec files, the validation, two breaks); P1 twice, P2–P8, P-PROD and lint, 1.0; two review rounds with Codex and the fold-ins, 1.5; the runbook, 1.0. The deploy morning (Mon 11-09): the three production reads and the gate's disposition, about 45 min, then the push and S0–S12 as slice 3's, about 30 min. §4.5's estimate was 6 h plus the morning; the hour over is the two spec files and the OD10 validation the facts added — OD10's photo type, a write-back item. Accepted (decision 9).

### Next phase, if approved

**Approved; the loop starts Tue 2026-11-03 once slice 3's SH reads clean, not in this session.** Done on 2026-11-02 after the gate (decision 1 and modifications A–C, E–G): this plan moved to the platform repo on `docs/rails-upgrade-slice-4` off `main` with the decisions and modifications folded in, one commit; `chore/rails-upgrade-slice-4` re-created from `master` `05e3fd42` with no commit. Then, in order: the loop on `chore/rails-upgrade-slice-4` exactly as the per-commit plan describes, with decisions 3 and 6 applied — commits 1 → 4, each red → green → deliberate break → lint → area suite → commit, the contract file's state pasted at each HEAD → P1 twice through P8 and P-PROD → the runbook as `Draft` on the platform branch with decision 4's curl and modification D's two read slots → two rounds of `predeploy-review-rails` with Codex, the brief's five traps and this plan's audit as the review's trap list → the verification STOP with the spot-check table filled from development and the three production reads listed for the Mac (Thursday's and Monday's observed columns empty until read). Nothing pushed. The scratchpad (`belongs_to_survey.json`, `survey_table.md`, the SQL files and their local outputs, the probe copy at the commit 4 state with the five-example block and the model spec, the contract, break and model-spec outputs, the four probe specs) stays for the session as the reference evidence; nothing in it is committed.

## Implementation record (2026-11-03)

insgt-api `chore/rails-upgrade-slice-4`, on `master` **`8b726308`**, not the survey's `05e3fd42`: the orders-CSV hotfix (`bead424b`…`0ec0b0fa`) merged after the gate. It touches `orders_controller.rb`, `lib/order_param.rb`, `render_bad` and one new spec file, and no model. The traversal still sees 89 reflections (the floor break below prints `got: 89`). Baseline on `8b726308`: **2,080 examples, 0 failures**. That is 2,059 plus the 21 in `spec/requests/orders_csv_date_range_spec.rb`, which is absent at `05e3fd42` (sourced from the JSON run, not by subtraction). Every count in the plan moves by +21. Slice 3's SH pass was recorded on the platform branch (`7c3bd2b`) before the loop started.

| # | Commit | Loop record |
| :-- | :-- | :-- |
| 1 | `39b213f3` test: pin belongs_to optionality to column nullability | the block exactly as Gaps pinned 1 (identical to the probe's `contract_block_v2.rb`), plus slice 4's clause in the file header as slices 1–3 added theirs; red **5 / 3** with the plan's three texts verbatim; break: floor 88 → 90 → `expected: >= 90 / got: 89`, 5 / 4; full suite 2,085 / 3 (the contract's three) |
| 2 | `1b4be3c8` fix: drop the dead Area#state association | `spec/models/area_spec.rb` red first (`expected: nil / got: #<ActiveRecord::Reflection::BelongsToReflection …>`), green after; contract 5 / 2; break: the line re-added → `["Area#state (areas.state_id)"]` and the area example red again; area suite (area + `properties_spec.rb`) 42 / 0; full 2,086 / 2 |
| 3 | `0baa6b4b` refactor: mark the nullable belongs_to associations optional | contract 5 / 1; break (a) `Area#area_type`'s option removed → `["Area#area_type (areas.area_type_id): nullable column, optional: nil"]`; break (b) `optional: true` on `OrdersUser#user` → `["OrdersUser#user (orders_users.user_id): NOT NULL column, optional: true"]`. At this HEAD the framework-default example still stops on the flag, so (b)'s second message appears only at commit 4 (break d). Listing specs + area 64 / 0; no spec references `OrderUrlGroup` (`grep -rln -E "OrderUrlGroup|order_url_group" spec` → empty); full 2,086 / 1 |
| 4 | `c055b8ed` fix: validate presence of belongs_to on NOT NULL columns (pre-review `1c2b0e97`) | red at commit 3's HEAD: the request spec's two 422 examples raise `PG::NotNullViolation … column "property_id"` / `"area_id"`, and the happy path is green (so the `show` template renders, one Unverified item closed); the model spec's two invalid cases red (`expected #<TagsResource … resource_id: 0, resource_type: 1 …> not to be valid`, and the photo-typed one). Green: contract 5 / 0, the four slice files 24 / 0. Breaks: (a) shim lines re-added → framework-default `expected true / got false` plus both 422 examples `NotNullViolation` again (8 / 3); (b) validation disabled → model spec 2 red, contract green (decision 2a); (c) the `if:` dropped → the soft-delete example `expected true / got false`; (d) `OrdersUser#user` optional → `[… NOT NULL column, optional: true]` and `["OrdersUser#user (orders_users.user_id)"]`. After review round 1, five more model examples, each red under its own break: (i) no `resource_id` clause → the reassignment example; (ii) no `resource_type` clause → the retype example; (iii) property mapped to `User` → the property positive; (iv) photo mapped to `Property` → the photo positive; (v) `Account` added to the map → the unsupported-type example. Full suite 2,093 / 0 before round 1, **2,098 / 0** after |
| 5 | `bd0859b8` fix: refuse a floorplan bulk create whose order token resolves nothing (round 2's finding, on Dan's decision) | `spec/requests/floorplans_create_bulk_spec.rb`, one example, red first at `c055b8ed`: `expected … :unprocessable_content (422) but it was :ok (200)`, nothing created. Its first draft built the order with `status_type: deleted` and wrongly went red on `Floorplan.count` 0 → 2: `CrudAttribution`'s `before_create :set_status_type` (`crud_attribution.rb:9`) forces every new row active, so the spec now soft-deletes the order after creating it. Green after the guard; break: guard removed → the same `200` red. A throwaway probe: an active order's batch still answers `200` with both floorplans created. Full suite **2,099 / 0** plain and `CI=1` |

The shim file is 13 lines and ends at the `forgery_protection_origin_check` line (modification A). `grep -rn belongs_to_required_by_default config app` → empty (trap 2). The trap 5 grep returns 0 for every file, spec and runbook this session wrote. Lint: `ruby -c` on each touched file; `rails_best_practices` 326 before and after each commit.

**Deviations from the plan.**

1. **The base** (above): 2,080 / 2,085 / 2,086 / 2,086 / 2,093 → 2,098 / 2,099, not 2,059 / 2,064 / 2,065 / 2,065 / 2,072. Production is **v668** (Dan, 2026-11-03): v667 deployed `8b726308` (2026-11-02 14:07:20 -0500) and v668 set `WEB_CONCURRENCY` and `RAILS_MAX_THREADS` (15:29:33 -0500). So the base is production's code, and v668 is the rollback target. **2026-11-05:** `master` moved again — v669, the Rails 8.1.4.1 security bump (`24cd8180`, 12:30:35 -0500; `Gemfile.lock` only), pushed on a Thursday by Dan's decision as a security release (§2.4 item 4 says Mon–Wed). Merged into the branch as `3f67af13`; `2099 examples, 0 failures`, routes 583 and P-PROD `"8.1.4.1"` on the merge. v669 is the rollback target (runbook, Deploy log).
2. **The request spec shares one city.** Its first run failed the happy path with `Validation failed: Name has already been taken`: `spec/factories/states.rb` fixes `name { 'California' }`, and `State` validates name uniqueness. Two independent `create(:city)` calls therefore collide. The spec builds one `city` for the area and the property.
3. **The request spec posts S12's camelCase body** (`areasProperty`/`areaId`) and asserts `:unprocessable_content`. Rack 3.2.4 warns on `:unprocessable_entity` (`have_http_status.rb:219`), the form the 24 existing sites use.
4. **The model spec has nine examples, not four** (review round 1, below). The photo positive stubs `ensure_listing_photo_exists` exactly as `spec/models/postal_code_spec.rb:49` does, because a photo with no order fails it at `photo.rb:476`.
5. **No `Co-Authored-By` trailer** on the five commits, per `git-commit-messages`, matching slices 1–3.
6. **Commit 4's body** was corrected at the round 1 amend. The pre-review text said every one of the 17 "answers 422"; the save-and-ignore sites do not.
7. **The null-count rule needs "on a table with rows."** Re-run against the development restore, the report shows `nulls = 0` on six columns, not five. The sixth is `headshots.user_id`, and `headshots` has 0 rows there. The plan's five are right and its stated rule ("`nulls` = 0 marks a candidate") is too wide. The runbook carries the corrected rule; a v7 write-back item.
8. **`POST /orders` costs +11 SELECTs, not +3** (fact 8 measured a bare `Order` save). A throwaway request spec copied `orders_create_spec.rb`'s setup (three contractors, one requested service) and counted uncached SELECTs on the branch and on `master`: **51 → 62**, `orders` +3, `users` +3, `roles` +3, `services` +2, `accounts` 4 → 4. Each child is built by id and its own `INSERT` clears the query cache, so each child's required checks re-read their parents. Write-back item for §4.5 and §8.
9. **Save-and-ignore call sites now skip a write silently** where the key names nothing: `FloorplansController#create_bulk` (`floorplans_controller.rb:21–25`, `create_bulk_params` `:118–123`): `500` before, `200` with unsaved rows after. `OrdersUser`'s helpers (`orders_user.rb:102–114`), `TagsResource.update_user_tags` (`:68–74`) and `Photo.tag` (`photo.rb:300`): a dangling row before (no foreign key on `orders_users.user_id` or `tags_resources.tag_id`), no row after. Recorded in the runbook's Summary and Known. `create_bulk` is commit 5, a deviation from the brief's scope taken on Dan's decision: `find_by_token` answers active orders only (`token.rb:23–25`), so a soft-deleted order's token is the realistic way to reach it.
10. **The Codex copies were built from `git ls-files`.** A plain `rsync` minus `.git` and `.env` also carries `config/master.key`, which is gitignored but on disk, as the first copy here showed before it was rebuilt.

**Verification (development, on `c055b8ed`; P-PROD on `1c2b0e97`, the same application tree; P1, P2, P-PROD and routes again on `bd0859b8`).** P1 2,098 / 0 plain (64.7 s) and `CI=1` (63.2 s) at `c055b8ed`, **2,099 / 0** both ways at `bd0859b8`, 0 deprecation lines, 24 rack warnings; P2 all good; P3 on `slice4_p3`: `Booted Rails 8.1.4 …`, start, `Property#1964 already has property data, skipping`, done (`elapsed=0.229`), status `nil`; P4 4 / 0; P5 86 / 0; P6 `ActionMailer::MessageDelivery`, `SystemError::rails upgrade`; P7 122 / 0; P8 photo 661326 → `d2e08hhdrjhri.cloudfront.net`, `200`, `image/jpeg`; P-PROD every line as runbook 3 step 2 expects (pasted in runbook 4 step 1); routes byte-identical to `master` (583). S12 rehearsed against `bin/rails server` on the branch with a development system-admin JWT: `{"errors":["Property must exist"]}`, `422`, `AreasProperty.unscoped.count` 17,082 before and after. The three reports against the development restore, extracted from the runbook's own text and executed (39 + 52 + 3 queries, 0 errors): nullability `OK` (219 / 219); D29 2, D39 27, D50 32, D52 `1:4652, 7:717874`, every other row 0 — fact 9 exactly; the naming queries return 35 rows (2 orders, one `user_id = 0` group, 32 photo tags).

**Review (`predeploy-review-rails`, two rounds, 2026-11-03).** Codex `gpt-6.1-sol`, source-only (no database in the copy); both rounds left their copy untouched (`diff -rq` against `git archive` of the reviewed commit: empty).

| Round | Source | Finding | Disposition |
| :-- | :-- | :-- | :-- |
| 1 | Codex | (first start: "Not inside a trusted directory and --skip-git-repo-check was not specified" — reviewed nothing; rerun once with the flag) | — |
| 1 | Codex, should-fix | `tags_resource_spec.rb` does not pin either dirty-field half of the condition, the photo or property mapping, or the unsupported-type rule | **fixed** in commit 4: five examples, each red under its break (above) |
| 1 | Codex, should-fix | `orders_user.rb:102–114` ignores a failed contractor save | **regraded to Known**: no foreign key, so the old behaviour was a dangling assignment and `200`; now the assignment is unchanged and `200`. D39 shows no writer since 2019 |
| 1 | Codex, should-fix | `update_user_tags` deletes, then ignores a failed insert | **regraded to Known**: a dangling row before, none after; delete-then-insert predates the slice (D45 0) |
| 1 | Claude + Codex, should-fix | per-row lookups on bulk tagging and the order fan-out | **recorded** (modification F; deviation 8); no code change, by the plan |
| 1 | Claude, should-fix | `create_bulk`: `500` → `200` with unsaved rows on an unknown `order_token` | recorded; then **fixed** as commit 5 after round 2 |
| 1 | Claude, should-fix | runbook Summary: "17 answer 422" too wide; the SELECT cost understated | **fixed** in the runbook and in commit 4's body |
| 2 | Codex | the round 1 fix is sufficient; the other dispositions accepted | — |
| 2 | Codex, should-fix | `create_bulk` should be fixed in this slice: "converting an exception into apparent success is introduced here" | **fixed** as commit 5 `bd0859b8` on Dan's decision (2026-11-03); no third round |

Codex also noted, unchanged by this slice: `lib/order_image_handler_import.rb:207–213` ignores the `UnalteredPhoto` save. Its caller runs it only after `photo.save` succeeds (`:91–95`), so the photo always exists and nothing here changes it, but a failed unaltered-original save there is silent. That is AB 723's source of truth; it belongs with the `ab-723-compliance` skill's owner, not this slice.
