# Runbook: Rails Upgrade Slice 4 — `belongs_to` optionality follows column nullability

**Last updated:** 2026-11-03
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~45 min of read-only production reports at Thursday's review and again on the
morning; ~30 min for the push and step 5's checks; S7 one hour after the push; S9 at the first hourly
import; SH and S13 24 h later
**Status:** Draft — implemented and verified in development 2026-11-03; two review rounds done
2026-11-03; round 2's open finding fixed as commit 5 on Dan's decision

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.5 (v6; v7 amends it after verification — see
`docs/plans/rails-upgrade-slice-4.md` for every deviation and why). Branch
`chore/rails-upgrade-slice-4`, five commits off `master` **`8b726308`** — not the survey's `05e3fd42`:
the orders-CSV hotfix (`bead424b`…`0ec0b0fa`, merged as `8b726308`) landed on `master` after the plan
was approved. It touches `orders_controller.rb`, `lib/order_param.rb`, `application_controller.rb`'s
`render_bad` and one new spec file (21 examples); no model, so the plan's reflection table stands.

1. `39b213f3` test: pin belongs_to optionality to column nullability — five structural examples
   appended to `spec/architecture/rails_upgrade_spec.rb`; red on three by design until commit 4
   (decision 6).
2. `1b4be3c8` fix: drop the dead Area#state association — `areas` has no `state_id`;
   `spec/models/area_spec.rb`.
3. `0baa6b4b` refactor: mark the nullable belongs_to associations optional — `Area#area_type`,
   `Listing#property_type`, `OrderUrlGroup#order`. Behaviour unchanged.
4. `c055b8ed` fix: validate presence of belongs_to on NOT NULL columns —
   `config/initializers/new_framework_defaults.rb:14–16` deleted (the file now ends at the second CSRF
   line); `TagsResource` validates that its `resource_id` names a row of the class its
   `resource_type` picks (OD10); `spec/models/tags_resource_spec.rb` (9) and
   `spec/requests/areas_properties_create_spec.rb` (3).
5. `bd0859b8` fix: refuse a floorplan bulk create whose order token resolves nothing —
   `FloorplansController#create_bulk` answers `422` `["Order must exist"]` before creating anything
   when the batch's `order_token` resolves no active order; `spec/requests/floorplans_create_bulk_spec.rb`
   (1). Review round 2's finding, fixed in the slice on Dan's decision (2026-11-03).

**No migration, no DDL, no ENV change, no gem change, no client release.** `config.load_defaults`
stays `7.2`.

**Production is v668** (Dan, `heroku releases`, 2026-11-03): v667 `Deploy 8b726308` (the hotfix,
2026-11-02 14:07:20 -0500), then v668 `Set WEB_CONCURRENCY, RAILS_MAX_THREADS config vars`
(15:29:33 -0500), on v666 (`05e3fd42`, slice 3). So production's code is this branch's base, and
**v668 is the rollback target**. If `master` moves again before the push, merge `master` into the
branch, rerun the suite on the merge, and move the "before" captures and the rollback target to the
new release.

**Where this sits.** The fourth of six deploy mornings: 5a (Tue 11-10), 5b (Wed 11-11), the quiet
week to Wed 11-18, then the Render rehearsal (§6).

**What moves for a human.**
- **17 associations answer 422 where they answered 500.** A create, or a key reassignment, that omits
  a `NOT NULL` key with no column validator used to reach the `INSERT` and raise
  `ActiveRecord::NotNullViolation`; it now fails validation, which every controller create among
  them renders as `422` with `{"errors":["<Association> must exist"]}`. The 17:
  `AccountMetric#account`, `AreasProperty#area` and `#property`, `Floorplan#order`,
  `ListingDescription#listing`, `ListingPhoto#listing` and `#photo`, `MarketingEventImport#marketing_event`
  and `#order_type`, `MlsImport#mls`, `MlsListing#listing` and `#mls`, `MlsMetadataCache#mls`,
  `OrderTypesService#order_type` (already a 422 through `order_types_service.rb:12`; gains the line),
  `RawPhoto#order`, `Schedule#user`, `UnalteredPhoto#photo`. S12 is the direct read. **`POST
  /floorplans/create_bulk`** ignores `save`'s result, and `create_bulk_params` sets `order_id: nil`
  when the batch's `order_token` resolves no active order — a soft-deleted order's token included,
  since `find_by_token` answers active orders only (`token.rb:23–25`). Commit 4 alone would have
  turned that request's `500` into a `200` listing unsaved floorplans; commit 5 makes it a `422`
  `["Order must exist"]` before anything is created.
- **30 associations' 422 bodies gain a line.** Where the key column already has a presence validator,
  the omission answers `["User must exist", "User can't be blank"]` where it answered
  `["User can't be blank"]` (decision 7). No client matches either string (modification G: 0 files in
  insgt-app, insgt-ops and insgt-photographers).
- **`TagsResource` refuses a row whose target does not exist** — a user, property or photo id that
  names nothing, or a `resource_type` other than 1, 3 or 7. Through `POST /tags_resources` that is a
  `422` with `Resource must exist`; at `photo.rb:251` and `:300` it is silent, since both sites ignore
  `create`'s return value. `:251` (`tag_with_zip`) tags the photo itself, so it cannot fire. `:300`
  (`Photo.tag`) tags the ids its caller passes — `photos#tag` from an insgt-ops selection, and
  `StockPhotoImportWorker` with a photo it has just imported — so an id that names no photo, which
  used to leave a dangling tag, is now skipped without a word.
- **An existing row with a dangling key keeps saving.** Under `load_defaults 7.1`+ the framework's
  validator runs only on a new row or a changed key (`belongs_to_required_validates_foreign_key =
  false`), so the rows the dangling-key report names save, update and soft-delete as before unless
  their key is moved to another missing row (plan, fact 6).
- **More SELECTs per write**, all primary-key lookups: each child built by id reloads its parents,
  because the child's own `INSERT` clears the query cache. Measured on `POST /orders` as insgt-ops
  sends it (three contractors, one requested service; uncached SELECTs, a throwaway request spec on
  the branch and on `master`): **51 → 62**, +11 — `orders` +3, `users` +3, `roles` +3, `services` +2.
  The plan's +3 (fact 8) was a bare `Order` save with no children. A `TagsResource` create +2
  (modification F); an `AccountMetric` first computed +1; an update whose keys do not change +0.
  ESTIMATE under 5 ms per order create.
- Nothing else: the route table is identical (583 routes), no existing spec changed, and no success
  response changes shape.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. `tmp/` is
insgt-api's gitignored scratch directory: the three report files below are saved there and never
committed. The production-config probe (step 1, P-PROD) runs in `apps/insgt-api` on the merge,
wherever Dan runs it. The Honeybadger dashboard is the web UI.

## Deploy window

**Mon 2026-11-09, 09:00–11:30 Pacific** (17:00–19:30 UTC; Pacific is UTC-8 and `heroku releases`
prints -0500). Mon–Wed only, outside the 08:00 and 12:00 delivery windows (§2.4). The push is gated
on two quiet weekdays after slice 3's (Tue 11-03 and Wed 11-04), read Thu 11-05.

**Slippage rule (§6, OD1):** if review and merge are not complete by 09:00 PT, the deploy moves to
**Tue 11-10**, then **Wed 11-11**, each moving 5a and 5b by a day. **Nobody pushes after 11:30 to
make the window.**

## Prerequisites

- [x] **Slice 3's SH result** (`deploy-rails-upgrade-3.md` step 7): **passes** — no new error since
      v666's push (Dan, 2026-11-03, about 22½ h)
- [x] **Two quiet weekdays** after v666 (Tue 11-03, Wed 11-04), read Thu 11-05 — Honeybadger →
      Errors:

      ```
      environment:"production" created.after:"2026-11-02 05:12 UTC-8"
      environment:"production" class:"RailsDeprecation" occurred.after:"2026-11-02 05:12 UTC-8"
      environment:"production" class:"AbstractController::DoubleRenderError" occurred.after:"2026-11-02 05:12 UTC-8"
      ```

      Expected: no new error, compared by error (§4.0 SH's triage); no `RailsDeprecation` beyond
      S-DEP's; no `DoubleRenderError`. The window also holds v667 (the orders-CSV hotfix, 14:07
      -0500) and v668 (`WEB_CONCURRENCY`, `RAILS_MAX_THREADS`, 15:29 -0500): an error first seen
      after either is triaged against that release before slice 3 — an orders-CSV backtrace against
      v667, a pool, timeout or memory error against v668. Observed (Dan, Thu 2026-11-05):
      **passes**. All three searches return No Results, each run twice, once with `-is:resolved`
      and once with `is:resolved`, both with `-is:ignored`. Nothing new from v666, v667 or v668,
      and S-DEP's `RailsDeprecation` has no new occurrence.
- [x] **Honeybadger baseline for the 17** (modification E; Dan, before Thursday's review):

      ```
      environment:"production" class:"ActiveRecord::NotNullViolation" occurred.after:"2026-10-26 00:00 UTC-7"
      ```

      Each hit is a production path that answers 422 (or raises `RecordInvalid` at a `save!`) after
      this slice: record its controller, action and the column the message names. Zero hits means the
      17 are unexercised in production, and SH's "must exist" watch expects nothing. Observed (Dan,
      Thu 2026-11-05): **zero hits**. No Results with `-is:resolved` and with `is:resolved`, both
      with `-is:ignored`. Nothing can hide a hit: insgt-api has no `rescue_from` and no rescue of
      `ActiveRecord::StatementInvalid` or `PG::` errors in `app/` or `lib/`. The only controller
      `rescue StandardError` is `OrdersController#temp_credentials` (`orders_controller.rb:43`),
      which writes nothing. `config/honeybadger.yml` ignores no exceptions. So the 17 are unexercised in production, and
      SH's "must exist" watch expects nothing.
- [ ] **The nullability STOP reads `OK`**, and the null-count and dangling-key reports are pasted,
      **twice** — Thursday's review and the morning of the push (step 2; modification D).
      Thursday: done, `OK`; Monday: ___
- [ ] **The dangling-key rule** (step 2) applied to both reads: no STOP, or the STOP resolved.
      Thursday: no STOP; Monday: ___
- [ ] Review rounds complete (two rounds of `predeploy-review-rails`, Codex second opinion included);
      this runbook's Status is `Ready`
- [ ] Dan has merged `chore/rails-upgrade-slice-4` into `master` and `bundle exec rspec` is green
      **on the merge**: expected `2099 examples, 0 failures`, 0 `DEPRECATION WARNING` lines if `master`
      is still `8b726308`; a different count is sourced before the push, not recomputed
- [ ] The production-config probe (step 1, P-PROD) printed the expected lines on the merge
- [ ] Pre-push captures (step 3) recorded below, on the release that is live at that moment

## Pre-deploy

### 1. Development verification — done 2026-11-03

On the branch at `bd0859b8` (P1, P2, P-PROD and routes) and `c055b8ed` (the rest — commit 5 changes
only `create_bulk` and adds its spec); the dev container; Ruby 3.4.12; Rails 8.1.4; the development
database is the production restore `tmp/latest-2026-10-30.dump`:

| # | Result |
| :-- | :-- |
| P1 | `2099 examples, 0 failures` (70.7 s); `CI=1`: `2099 examples, 0 failures` (67.9 s); `0` `DEPRECATION WARNING` lines in each; the 24 rspec-rails `:unprocessable_entity` warnings unchanged. Baseline on `master` `8b726308`: 2,080 (2,059 at the survey's `05e3fd42` plus the hotfix's 21 in `orders_csv_date_range_spec.rb`), so +19: 5 contract, 1 area, 9 tags-resource, 3 areas-properties, 1 floorplans. Earlier states, both modes: 2,093 / 0 at `1c2b0e97` (before review round 1), 2,098 / 0 at `c055b8ed` |
| P2 | `zeitwerk:check` → "all is good" (the `lib/` notice as on `master`) |
| P3 | `slice4_p3` queue: `Booted Rails 8.1.4 application in development environment`, `start`, `[PropertyDataLookupWorker] Property#1964 already has property data, skipping`, `done` (`elapsed=0.229`); `Sidekiq::Status::status(jid)` → `nil` (§8 item 10) |
| P4 | `4 examples, 0 failures` |
| P5 | `86 examples, 0 failures` |
| P6 | `ActionMailer::MessageDelivery`; `SystemError::rails upgrade` |
| P7 | `122 examples, 0 failures` |
| P8 | photo 661326 → `d2e08hhdrjhri.cloudfront.net`, `200`, `image/jpeg` (`Net::HTTP`) |
| P-PROD | below |
| Routes | `bin/rails routes` byte-identical to `master`'s (583 lines); `active_storage` `0` |
| Lint | `ruby -c` on every touched file; `rails_best_practices -e "db/migrate,vendor" .` 326 warnings before and after each commit (no `.rubocop.yml`, so `bin/rubocop` cannot run) |
| S12 rehearsal | `bin/rails server` on the branch, S12's curl verbatim against `localhost:3000` with a development system-admin JWT and area 1: `{"errors":["Property must exist"]}` and `422`; `AreasProperty.unscoped.count` 17,082 before and after |
| Reports | step 2's three, against the development restore: nullability `OK` (219/219); D29 `2`, D39 `27`, D50 `32`, D52 `1:4652, 7:717874`, every other row `0` — the plan's prediction exactly |

**P-PROD** is `deploy-rails-upgrade-3.md` step 2's wrapper, unchanged, and its expected lines are
that step's (cited, not reproduced — trap 5): the WARN line, `"8.1.4"`, `true`, `true`, the three
`[:notify]` pairs, the `Reporting error` line, `true`, `false`, `7.2`, `583`, `false`, `true`, and a
`DEPRECATION` count of `0`. This slice changes none of them.

RESULTS (2026-11-03 12:17:25 UTC, branch `1c2b0e97`, dev container — the same application tree as
`c055b8ed`; round 1's amend changed only `spec/models/tags_resource_spec.rb`). Re-run at 13:02:30
UTC on `bd0859b8`: the same lines (`"8.1.4"` … `583`, `false`, `true`) and a `DEPRECATION` count of
`0`:

```
W, [2026-11-03T12:17:25.844598 #18536]  WARN -- : Generating image variants require the image_processing gem. Please add `gem "image_processing", "~> 1.2"` to your Gemfile or set `config.active_storage.variant_processor = :disabled`.
"8.1.4"
true
true
[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]
I, [2026-11-03T12:17:25.906627 #18536]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=91c254f3-91fa-4584-9265-861f4e40c9b4 level=1 pid=18536
true
false
7.2
583
false
true
0
```

RESULTS (on the merge, before the push): ___

Per-commit loop records (red, green, deliberate break) are in the plan's implementation record. No
scratch Heroku app exists for `insgtapi`, so the build is proved by the release itself (§2.5).

### 2. The three production reports (read-only; Thursday's review, then the morning of the push)

All three are read-only. Each runs twice — Thu 2026-11-05 at the review and Mon 2026-11-09 before the
merge — and both outputs are pasted below (modification D). A STOP found Thursday costs nothing.

**(a) The nullability STOP (§4.5 scope 5).** Save as `tmp/nullability_diff.rb`:

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

```bash
heroku pg:psql --app insgtapi -c "COPY (SELECT table_name, column_name, is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND column_name LIKE '%\_id' ORDER BY 1, 2) TO STDOUT CSV HEADER" > tmp/prod-columns-2026-11-05.csv
wc -l tmp/prod-columns-2026-11-05.csv
ruby tmp/nullability_diff.rb db/schema.rb tmp/prod-columns-2026-11-05.csv
```

(Monday: the same three lines with `2026-11-09`.) `\_` inside a double-quoted bash string reaches psql
unchanged, and `COPY … TO STDOUT` needs no file privilege; if `-c` is refused, put the statement in
`tmp/columns.sql` and run `heroku pg:psql --app insgtapi < tmp/columns.sql`.

Expected: `220`; then `schema.rb columns=219 database columns=219` and `OK: no nullability mismatch`
(exit 0). **Any mismatch line is a STOP** — the classification the contract spec enforces is read
from `db/schema.rb`'s nullability, so a production column that differs makes it wrong.

**(b) The null-count report (§8 item 15's candidates).** Save as `tmp/null-counts.sql` — one query per
nullable foreign-key column behind a `belongs_to`, N1–N39:

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
heroku pg:psql --app insgtapi --file tmp/null-counts.sql > tmp/null-counts-2026-11-05.txt     # or: heroku pg:psql --app insgtapi < tmp/null-counts.sql
```

Expected: a count per row — no pass or fail. `nulls` = 0 **on a table with rows** marks a §8 item 15
candidate (a nullable column that could become `NOT NULL`); an empty table's `0` says nothing. The
development restore has five: `areas.city_id`, `areas.area_type_id`, `notifications.order_event_id`,
`order_url_groups.order_id`, `photos.order_id` (`headshots` is empty there, so `headshots.user_id`'s
`0` is not a sixth).
The rule stays nullability, so these stay optional in this slice whatever production shows.

**(c) The dangling-key report (S13 re-runs it).** Save as `tmp/dangling.sql` — one query per `NOT NULL`
foreign-key column behind a required association, D1–D47; `tags_resources.resource_id` by type,
D48–D50; the type guard, D51; the type distribution, D52:

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
heroku pg:psql --app insgtapi --file tmp/dangling.sql > tmp/dangling-2026-11-05.txt     # or: heroku pg:psql --app insgtapi < tmp/dangling.sql
```

(Monday: `tmp/dangling-2026-11-09.txt`, the file S13 diffs against.)

Expected: `0` on every row D1–D51 except the three the restore predicts — **D29
`orders.account_id` ≤ 2, D39 `orders_users.user_id` ≤ 27, D50 `tags_resources.resource_id (resource_type
7 → photos)` ≤ 32** — and D52 listing only `1:`, `3:` and `7:` entries.

**Decision rule (decision 5):**
- **STOP** if any row other than D29, D39 and D50 is non-zero, or if any of those three exceeds the
  restore's count (2, 27, 32) — a higher count is a live writer, and a live writer keeps producing
  422s after the push.
- At or below: record the counts and the named rows here (queries below) and proceed. S13 pins the
  Monday counts; the three sets become one §8 cleanup item. No migration either way (§8 item 15).
- The restore's provenance, so the comparison means something: `tmp/latest-2026-10-30.dump`, written
  2026-10-30 16:17 UTC, its latest `order_logs` row 16:12:26 UTC. All three sets are historical —
  orders 2827 and 4302 (2016–2017, two accounts hard-deleted then); 27 `orders_users` rows with
  `user_id = 0`, `system_processor`, 2017-07-07 … 2019-05-02 (the pre-2019 processor assignment); 32
  photo tags created 2025-06-17 for photo ids 549637–549668 that no longer exist (plan,
  modification C).

Naming the rows when a count is non-zero:

```sql
SELECT o.id, o.account_id, o.status_type, o.created_at::date FROM orders o LEFT JOIN accounts a ON a.id = o.account_id WHERE a.id IS NULL ORDER BY o.id;
SELECT ou.user_id, COUNT(*) AS rows, MIN(ou.created_at)::date AS first, MAX(ou.created_at)::date AS last, COUNT(*) FILTER (WHERE ou.status_type = 1) AS active FROM orders_users ou LEFT JOIN users u ON u.id = ou.user_id WHERE u.id IS NULL GROUP BY 1 ORDER BY 1;
SELECT t.id, t.resource_id, t.tag_id, t.status_type, t.created_at::date FROM tags_resources t LEFT JOIN photos p ON p.id = t.resource_id WHERE t.resource_type = 7 AND p.id IS NULL ORDER BY t.id;
```

RESULTS — Thursday 2026-11-05 (nullability; null counts; dangling and the named rows): read at
16:59 UTC (08:59 PT), files `tmp/{prod-columns,null-counts,dangling,dangling-rows}-2026-11-05.*`. The
reports gave 39, 52 and 3 result sets, 0 errors. **No STOP.**

- **(a) Nullability:** `wc -l` → `220`; `schema.rb columns=219 database columns=219`,
  `OK: no nullability mismatch`, exit 0.
- **(b) Null counts:** `nulls = 0` on a table with rows for exactly the restore's five:
  `areas.city_id` (3,525), `areas.area_type_id` (3,525), `notifications.order_event_id` (622),
  `order_url_groups.order_id` (212), `photos.order_id` (639,326). `headshots` is empty in
  production too, so `headshots.user_id`'s `0` is not a sixth. Every other column has nulls.
- **(c) Dangling:** D1–D51 are 0 except **D29 = 2, D39 = 27, D50 = 32**, each exactly at the
  restore's ceiling. D52 `1:4660, 7:724591` lists only `1:` and `7:` (restore `1:4652, 7:717874`;
  the growth is live tagging, all on supported types).
- **Named rows,** identical to the restore's: orders `2827` (account 873, status 2, 2016-11-02) and
  `4302` (account 1190, status 1, 2017-07-05); `orders_users` `user_id = 0`, 27 rows,
  2017-07-07 … 2019-05-02, 24 active; 32 `tags_resources` rows `434522`…`434553`, tag 69, photo
  ids `549637`…`549668`, all active, all 2025-06-17. No new writer since the restore.

RESULTS — Monday 2026-11-09 (the same): ___

Disposition (Dan): ___

### 3. Pre-push captures (on the host, on the release that is live)

```bash
heroku releases -n 3 --app insgtapi
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
heroku run --no-tty --app insgtapi rails runner 'puts Area.unscoped.order(:id).first.id; puts AreasProperty.unscoped.count'
heroku logs -n 1500 --app insgtapi > /tmp/s7-before.log
grep -c "status=422" /tmp/s7-before.log
head -1 /tmp/s7-before.log | cut -c1-32
tail -1 /tmp/s7-before.log | cut -c1-32
RELEASE=v668   # or the newer one `heroku releases -n 3` printed, if master moved
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 4', 'release $RELEASE').deliver_now"
```

Each command on its own line (slice 2's zsh url-quote-magic lesson). **Do not send the S12 request
before the push**: on the current release it answers `500` and files an `ActiveRecord::NotNullViolation`
in Honeybadger that SH would then have to exclude (decision 4). The "before" is the plan's fact 7, a
local capture: `PG::NotNullViolation: … null value in column "property_id" of relation
"areas_properties" violates not-null constraint`, `500` as production renders it.

Expected before: S4 `["Carlsbad", "Oceanside", "Leucadia"]`; S10 `7.2`; an area id and a count
(whatever they print is S12's "before"); a `status=422` count and the buffer's span (S7's comparison,
not a criterion); S6 the email arrives.

RECORDED (before): ___

## Deploy

### 4. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

No gem changes, so the build installs nothing new. A failed build is not a release; v668 stays.

RECORDED: ___

### 5. Within 30 minutes

Set `RELEASE` and `JWT` first. Every `heroku run … rails runner` prints the Active Storage WARN line
before its own output (Known); it is not a failure.

```bash
RELEASE=vNNN   # the release `heroku releases -n 1` printed
JWT='<a real JWT, copied from an insgt-ops session>'
heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
heroku run --no-tty --exit-code --app insgtapi rails runner "puts Honeybadger.notify('rails upgrade slice 4 marker', error_class: 'UpgradeMarker', fingerprint: 'rails-upgrade-marker', tags: 'upgrade', context: { rails: Rails.version, release: '$RELEASE' }, sync: true).inspect"
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 4', 'release $RELEASE').deliver_now"
curl -sS -w "\n%{http_code}\n" -X POST -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"areasProperty":{"areaId":<the area id from step 3>}}' https://api.insightphotos.net/areas_properties
heroku run --no-tty --app insgtapi rails runner 'puts AreasProperty.unscoped.count'
```

**S3** is `deploy-rails-upgrade-3.md` step 5's version-and-config-key runner, unchanged — run it from
there (trap 5: this runbook does not reproduce it, and no command here calls the 8.1-deprecated
time-zone reader). `areaId` reaches the controller as `area_id` through `json_param_key_transform.rb`.

Expected, reasoned before the push:

| # | Check | Expected |
| :-- | :-- | :-- |
| S2 | `heroku ps`, `grep Booted` | all dynos up; `Booted Rails 8.1.4 application in production environment` |
| S1 | `/up` | `200`; the Honeybadger uptime check green |
| S0 | marker | a notice id; `UpgradeMarker` gains an occurrence with context `rails: 8.1.4` and the real release |
| S3 | runbook 3 step 5's runner | `8.1.4`, `false` |
| S10 | `loaded_config_version` | `7.2` |
| S4 | nearby cities | identical to step 3's capture |
| S5 | Stripe | `true` |
| S6 | email | `SystemError::rails upgrade slice 4` arrives at ops@insightphotos.net |
| **S12** | `POST /areas_properties` without `propertyId` | `{"errors":["Property must exist"]}` and `422`; then `AreasProperty.unscoped.count` equal to step 3's (nothing written). **A `500` is the rollback signal** — the shim deletion did not take effect |

A boot failure on any dyno is a rollback. An `ActiveRecord::NotNullViolation` in Honeybadger within
these 30 minutes is a path the slice should have turned into a 422: record it, and roll back if it is
a daily path.

RECORDED: ___

### 6. One hour after the push (S7) and the first import (S9)

```bash
heroku logs -n 1500 --app insgtapi > /tmp/s7.log
head -1 /tmp/s7.log | cut -c1-32
tail -1 /tmp/s7.log | cut -c1-32
grep -c "status=5" /tmp/s7.log
grep -oE '\] [A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)* \(' /tmp/s7.log | sort | uniq -c | sort -rn
grep -c "status=422" /tmp/s7.log
grep -c "NotNullViolation" /tmp/s7.log
```

Then Papertrail: `status=5` and `NotNullViolation` from the push to one hour after it (the buffer spans
less than the hour at business-hours traffic).

Expected: no `status=5` line in the hour; no exception class other than
`ActionController::RoutingError` (scanner traffic); **`0` `NotNullViolation`**; the `status=422` count
recorded beside step 3's (R2's lograge reading; not a criterion — a rise is a path the 17 cover, and
is read against modification E's baseline). S9: the first `import_listings` check-in after the push
arrives on time, **judged in UTC** (about :36–:45 past each UTC hour).

RECORDED: ___

### 7. 24 hours after the push (SH, S13)

**SH** — Honeybadger → Errors, compared with the slice 0 baseline **by error** (replace the time with
the push):

```
environment:"production" created.after:"<push>"
environment:"production" class:"ActiveRecord::RecordInvalid" occurred.after:"<push>"
environment:"production" class:"ActiveRecord::NotNullViolation" occurred.after:"<push>"
environment:"production" class:"RailsDeprecation" occurred.after:"<push>"
```

**Pass condition:**
- No `RecordInvalid` whose message contains `must exist` from a path that calls `save!`.
  `app/services/account_metrics/calculator.rb:25` is the one `save!` site among the 17 models: a
  missing account there was a `NotNullViolation` before and is a `RecordInvalid` after — both a failed
  job, neither expected.
- **No `ActiveRecord::NotNullViolation` at all.**
- No new error whose backtrace touches `tags_resource.rb`, `area.rb`, `listing.rb`,
  `order_url_group.rb`, `floorplans_controller.rb`, `config/initializers/new_framework_defaults.rb`
  or activerecord's `associations/builder/belongs_to.rb`.
- No new `RailsDeprecation`.

Anything else is an old bug seen for the first time: record it here and fix it on its own branch; it
does not block the slice.

**S13** — the dangling-key report again, diffed against Monday's pre-push read:

```bash
heroku pg:psql --app insgtapi --file tmp/dangling.sql > tmp/dangling-after.txt
diff tmp/dangling-2026-11-09.txt tmp/dangling-after.txt
```

Expected: empty — D29, D39 and D50 equal to the pre-push counts (decision 5c), every other row `0`.
A new non-zero row, or a higher count, is a finding: a writer the slice should have refused.

RECORDED: ___

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to v668 (the hotfix's code with its `WEB_CONCURRENCY` and `RAILS_MAX_THREADS`), or to the
release step 3 recorded if `master` moved. Nothing to undo: no migration, no ENV change, no data
written by the slice, and the dangling rows are exactly as they were.

## Known, kept by decision

- **One Active Storage WARN line per process boot on 8.1.4** (slice 3's Known; §8 item 7). Not raised,
  not a deprecation, not reported.
- **The doubled message on 30 models** (decision 7): `["User must exist", "User can't be blank"]`. The
  column presence validators are now redundant with the framework's; they come out on their own branch
  after slice 5 closes (a §8 item), not inside the upgrade.
- **The dangling rows stay** (decision 5): they save, update and soft-delete unless their key is moved
  to another missing row — the one save this slice exists to refuse. `OrdersUser.add_user`'s update
  paths (`orders_user.rb:38–47`) reassigning a `user_id = 0` row to a real user is allowed. Cleanup is
  one §8 item.
- **`TagsResource#user` and `#property` keep `optional: true` on a `NOT NULL` column** (OD10, decision
  3): both read `resource_id`, which a `ResourceType` integer types, and 99.4% of the rows are
  photo-typed with no association at all. The model validates by `resource_type` under the
  framework's own new-or-changed condition. Real polymorphism is a data migration (§4.5).
- **Call sites that ignore `save`'s result now skip a write silently** where the key names nothing
  (review round 1, Claude and Codex). Before this slice the same input wrote a dangling row, which
  was not reported to the caller either, and none of these sites is reached by today's inputs (D39
  and D45–D50, step 2). The one site where a `500` would have become a `200`,
  `FloorplansController#create_bulk`, is commit 5's guard, not this list.
  - `OrdersUser`'s contractor helpers (`orders_user.rb:102–114`): a contractor id that names no user
    (no foreign key on `orders_users.user_id`) — a dangling assignment before, the assignment left as
    it was after; `POST`/`PATCH /orders` answer `200` either way.
  - `TagsResource.update_user_tags` (`tags_resource.rb:68–74`): a tag id that names no tag (no foreign
    key on `tags_resources.tag_id`) — a dangling row before, no row after. The delete-then-insert,
    with no transaction, predates the slice.
  - `Photo.tag` (`photo.rb:300`): a photo id that names no photo — a dangling tag before (D50's kind),
    no tag after. `tag_with_zip` (`:251`) tags the photo itself and cannot be refused.

  Reporting these failures to the caller changes the call sites, outside the slice (trap 4); one §8
  item.
- **The `tag` load on every `TagsResource` create** (modification F): the now-required `belongs_to :tag`
  reads the tag the row names by id. Assigning the tag by object would save the SELECT — a §8 note.
- **The `account` association's `eager_load` scope** (`order.rb:90`) makes the presence check two
  statements on a bare `Order` save by id (plan, fact 8) — a §8 note. `POST /orders` does not pay it:
  the account is already loaded there (`accounts` 4 → 4 SELECTs in the round 1 measurement).
- **The §8 item 15 candidates** (step 2b): decided by the production null counts, not here.
- **`belongs_to_required_validates_foreign_key` stays `false`** through slice 5 (a 7.1 default; not
  among 5a's or 5b's flags).
- **The 24 rspec-rails `:unprocessable_entity` warnings** (rack 3.2 renamed the status). The new
  request spec uses `:unprocessable_content`; the existing sites are untouched.
- **Review rounds** (2026-11-03, `predeploy-review-rails`; Codex `gpt-6.1-sol` on a copy built from
  `git ls-files`, so no `.git`, `.env` or `config/master.key`; both rounds left their copy untouched).
  Round 1: Codex's first start refused a directory that is not a git repository and reviewed
  nothing; the rerun with `--skip-git-repo-check` returned four should-fix findings. The
  `TagsResource` spec did not pin either dirty-field half of the condition, the photo and property
  mappings, or the unsupported-type rule. Fixed in commit 4 by five examples, each seen red under a
  deliberate break. The contractor helpers and `update_user_tags` ignoring `save` were regraded to
  the Known item above (no foreign key, so the old behaviour was a dangling row, not an error). Bulk
  per-row lookups were agreed and recorded (modification F; the `POST /orders` measurement).
  Claude's own findings: `create_bulk`, and the two Summary corrections (the save-and-ignore
  exception, the measured SELECT cost). Round 2: Codex agreed the fix is sufficient and agreed with
  the other dispositions, except that `create_bulk` should be fixed in this slice ("converting an
  exception into apparent success is introduced here"). Dan (2026-11-03): fix it in the slice —
  commit 5 `bd0859b8`, its example red (`200`) before the guard, green after, and red again with the
  guard removed; an active order's batch still creates every floorplan (a throwaway probe: `200`,
  two rows). No third review round.

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed`, the release, steps 3–7's results.
- `docs/plans/rails-upgrade-slice-4.md`: Status `Deployed`.
- `rails-upgrade.md`: §4.5's "as deployed" line, §6's calendar as it went (the v7 amendment itself is
  written before the push).

## Deploy log

- **2026-11-03 — implemented and verified in development** (branch `chore/rails-upgrade-slice-4`,
  `39b213f3`…`bd0859b8` off `master` `8b726308`, which is production's code as v667/v668): step 1's
  table; P-PROD as step 1's RESULTS; step 2's reports against the development restore matched the
  plan's prediction.
