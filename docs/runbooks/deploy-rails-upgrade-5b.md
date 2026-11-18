# Runbook: Rails Upgrade Slice 5b — the 8.1 framework defaults, then `config.load_defaults 8.1`

**Last updated:** 2026-11-18
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~25 min of prerequisite reads and captures; ~35 min for the push and step 5's
checks (S15, S15b and S17 included); S7 one hour after the push; S9, S9b, S16 and the ops@ inbox at
the first import that starts after the release; SH and S18 24 h later
**Status:** Deployed — **v675**, `24309546`, pushed 2026-11-11 16:26:27 UTC (08:26 PST). Step 5
passes; the watched 16:30 UTC import passes (step 6); SH passes at seven days, which closes the
quiet week (step 7, read 2026-11-18). S7 and S18 pass, both also read on 11-18. Nothing is open;
the one observation is the `backgroundworker` cycle of 11-17 (S18). Implemented, verified and reviewed
2026-11-10 (step 1; Known; record `docs/architecture/reviews/2026-11-10-slice-5b-insgt-api.md`).

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.6 rows 4–10 and the `config.load_defaults 8.1` bump
(v8; v9 after the review). `docs/plans/rails-upgrade-slice-5.md` holds every decision, with what moved
since the plan in its "5b — amendments" section. Branch `chore/rails-upgrade-slice-5b`, four commits
off `master` **`808d383f`** — 5a merged and deployed as v672 — as the plan's commit sequence:

1. `4d5eef28` chore: enable the rails 8.1 framework defaults — the six lines of
   `config/initializers/new_framework_defaults_8_1.rb` uncommented (`:28, 36, 46, 61, 66, 74`; rows
   5–10). The contract block `the 8.0 and 8.1 framework defaults (§4.6)` gains the value pins, and
   `spec/requests/json_escaping_spec.rb` (4) is new: the row 5 proof on `PUT /order_types/:id`.
2. `72dfaa73` chore: load the rails 8.1 defaults and remove the shim files — `config/application.rb:12`
   `config.load_defaults 8.1`, the only change to that file; `git rm` of all five
   `new_framework_defaults*.rb` (the 5.0 shim's two CSRF lines, the all-comment 6.0 and 7.2 files,
   the 8.0 and 8.1 shims now fully applied). The contract pins `loaded_config_version` `8.1`, the
   applied freshness and separator values, no shim file, the CSRF pair at the framework's `true`,
   and no uncommented `active_support.` line under `config/initializers`.
3. `1671c9c3` test: pin the rails upgrade invariants in the contract spec — the two encoder-level
   `ActiveSupport::JSON.encode` pins and the file header's 5b clause.
4. `27e45f1b` fix: report a swallowed CRMLS login failure to Honeybadger — `lib/crmls.rb`'s login
   rescue gains `Honeybadger.notify(error, context: { import_errors: @import_errors })` before the
   email (§8 item 32; plan Approval D). The swallow, the email and `extract_listings`' early return
   are unchanged. `spec/lib/crmls_login_timeout_spec.rb` gains its second example.

**No migration, no DDL, no ENV change, no gem change, no client release.** `rails/all` stays. Nothing
`belongs_to` is touched: slice 4 already emptied that part of the 5.0 shim.

**What changes in production:**

- **`config.load_defaults` `7.2` → `8.1`.** Nine settings beyond 7.2 now come from `load_defaults`
  alone (plan fact 1). Two of them only arrive here: the applied `strict_freshness` (`false` → `true`)
  and the applied `escape_js_separators_in_json` (`true` → `false`), because the shim lines reached
  the config alone (plan fact 16; 5a's S14 printed the applied freshness `false`). Nothing reads
  the freshness flag (plan fact 10).
- **Every `render json:` body stops escaping `<`, `>`, `&`, U+2028 and U+2029** (row 5; the 70
  `render` calls with `json:`, plan fact 5): `\u003c` becomes `<`, `\u0026` becomes `&`. JBuilder bodies
  keep their entities escaped and only write U+2028/U+2029 raw (row 8). Every consumer parses JSON —
  Angular's `HttpClient`, insgt-ops's two text reads, the five Lambdas' `axios` — so decoded values
  are identical. S15, S15b and S17 prove it on production data; `json_escaping_spec.rb` proves both
  paths in the suite.
- **A path-relative `redirect_to` raises** (row 6): inert, no `redirect_to` in the app.
- **`first`/`last` without an order on a model with no order column raises
  `ActiveRecord::MissingRequiredOrderError`** (row 7): inert, every table has `id`; SH watches the class.
- **`render_tracker = :ruby`, hidden fields without `autocomplete="off"`** (rows 9–10): inert, the
  mailer templates are the only ERB and there is no form.
- **YJIT** (row 4): `config.yjit = !Rails.env.local?` — production stays `true` (P-PROD, S3); test and
  development boot without it (the suite is about 16 s slower).
- **The 5.0 shim's `per_form_csrf_tokens` and `forgery_protection_origin_check` go from `false` to
  the framework's `true`:** inert, because `application_controller.rb:3` skips
  `verify_authenticity_token` for every action (plan fact 9).
- **A CRMLS login failure now reaches Honeybadger** (commit 4), with the import errors as context.
  The email still goes to ops@; the import still carries on. An ordinary login failure during the
  quiet week is therefore a new Honeybadger error — SH's triage rule applies (Risks).

**What moves for a human: nothing.** No success response changes its decoded value, and no visible
value moves. Error bodies and the data-carrying `render json:` sites change bytes only. The route
table is identical (583 in development; 582 in production since `073ebe2f`).

**Where this sits.** The last of six deploy mornings: then the quiet week to Wed 11-18 (§2.2), then
the Render rehearsal (§6).

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. `tmp/` is
insgt-api's gitignored scratch directory. The production-config probe (step 2) runs in `apps/insgt-api`
on the merge, wherever Dan runs it. Honeybadger and Papertrail are the web UIs. Put each command on
its own line (slice 2's zsh url-quote-magic lesson). `JWT` is a system-admin token, as runbook 4's S12
had it (copied from an insgt-ops session); S15 and S15b use it, S17 needs none.

## Deploy window

**Wed 2026-11-11, 09:00–11:30 Pacific** (17:00–19:30 UTC). Mon–Wed only, outside the 08:00 and 12:00
delivery windows (§2.4). The push waits for 5a's watched import and its SH read (Prerequisites).

**Which import is watched.** The Scheduler starts `import_listings` at about :30 past each UTC hour,
and runs finish at :34–:37. A one-off dyno already running keeps the slug it started with (plan P8),
so **the watched run is the first one that starts after the release**. Push by 10:25 PT (18:25 UTC)
and that hour's :30 run is the watched one; a later push moves the reads an hour, not the slice.

**Slippage rule (§6):** if the prerequisites or the merge are not complete by 09:00 PT, the deploy
moves to **Mon 11-16** (Thu and Fri are never deploy days), and the quiet week moves with it.
**Nobody pushes after 11:30 to make the window.**

## Prerequisites

- [x] **5a's watched import passed on all four signals** (`deploy-rails-upgrade-5a.md` step 6): the
      15:30 UTC run of 2026-11-10 — S9 (the check-in), S9b (a new `mls_imports` row whose start follows
      14:48:26 UTC, `total_listings` 654–659, `duration` 270–420 s), S16 (`0` `Regexp::TimeoutError` in
      the buffer and in Papertrail) and the ops@ inbox (no `SystemError::` from the import since the
      push; the baseline is the 2021-08-31 `Crmls Login Failure`). Pass on S9 alone, or on S9 and SH,
      is not a pass (the login-swallow path passes both). **Passes** (Dan, 2026-11-10 15:39–15:41 UTC):
      S9b a new row, start 15:30:17 UTC, `created_at` 15:35:25, `total_listings` 655, `duration` 308 s;
      S9 "is reporting", last seen about 15:36 UTC; S16 `0` in the buffer (14:48:32 → 15:40:39 UTC) and
      "No matching events" in Papertrail; the inbox quiet since 14:48 UTC; S7 `status=5` `0`.
- [x] **5a's SH passes** (runbook 5a step 7, at about 14:48 UTC on 2026-11-11, before this window
      opens): no `Regexp::TimeoutError`; no new error touching the 8.0 shim, the import files, the
      `rets` gem or `http/cache.rb`; no new `RailsDeprecation`; the inbox still quiet. An
      `IpSpoofAttackError` is the Client-IP fix's finding, not 5a's, and does not block 5b.
      **Passes** (Dan, 2026-11-11, read by 15:54 UTC, about 25 h after the push): every search No
      Results under both resolved states, with the date filter proven by an `UpgradeMarker` search;
      no new fault, so nothing to triage; a manual import at 10:54 UTC wrote its row (652, 277 s);
      no `SystemError::` email of any kind at 25 h.
- [x] Review rounds complete (two rounds of `predeploy-review-rails`, Codex included; 2026-11-10, Known)
- [x] This runbook's Status is `Ready` (2026-11-10, after the v9 write-back)
- [x] Dan has merged `chore/rails-upgrade-slice-5b` into `master`, and `bundle exec rspec` is green
      **on the merge**. Expected with `master` still at `808d383f`: `2117 examples, 0 failures`, 0
      `DEPRECATION WARNING` lines, the 24 rack warnings — the branch's own count, since the branch is
      four commits on top of `master` and the merge tree is the branch tree. If `master` has moved, the
      count is sourced on the merge from `rspec --dry-run --format json`, not recomputed, and
      `git log origin/master..master` is read for what else ships. **Done** (2026-11-11): Dan merged
      as `24309546`, whose tree is `27e45f1b`'s (`git diff` empty), so nothing else ships. Dan's run
      on the merge: `2117 examples, 0 failures` (82.2 s). Claude's run on the same commit, in the dev
      container: `2117 examples, 0 failures` (76.3 s), `0` `DEPRECATION WARNING` lines, the 24
      `:unprocessable_entity` warnings.
- [x] The production-config probe (step 2) printed the expected lines on the merge, `582` among them
      (Dan, 2026-11-11 16:05 UTC, on `24309546`).
- [x] Pre-push captures (step 3) recorded on the live release, **v674** (v673–v674 only set config
      vars; step 3): the release runner, S4, S6, the S9b and S16 baselines, **S15, S15b and S17
      "before"**, and S18's "before" (Dan, 2026-11-11 16:06–16:25 UTC).

## Pre-deploy

### 1. Development verification — done 2026-11-10

On the branch at `27e45f1b`, in the dev container (Ruby 3.4.12, Rails 8.1.4.1). The development
database is the production restore of 2026-11-09 about 12:31 UTC (runbook 5a step 1). The loop ran
every example red before its change and under a deliberate break (plan, "Implementation record — 5b").

| # | Result |
| :-- | :-- |
| P1 | At commit 4 (`4d5eef28`): `2113 examples, 1 failure` plain (66.1 s) and `CI=1` (67.7 s) — the one failure is `json_escaping_spec.rb`'s JBuilder separator example, red by design until the bump (plan fact 16). At commit 3 (`72dfaa73`): `2114 examples, 0 failures` (83.0 s; `CI=1` 82.3 s) — YJIT is off in test from here, about +16 s. At commit 4 (`1671c9c3`): `2116 / 0` (79.4 s; 85.7 s). **At `27e45f1b`: `2117 examples, 0 failures` plain (83.4 s) and `CI=1` (82.6 s)**; `0` `DEPRECATION WARNING` lines in every run; the 24 rspec-rails `:unprocessable_entity` warnings unchanged. Every count sourced from `rspec --dry-run --format json` (contract 18 → 23 → 24 → 26; `json_escaping_spec.rb` 4; the login spec 1 → 2); `master` runs 2,104 |
| P2 | `zeitwerk:check` → "all is good" (at the bump and at `27e45f1b`) |
| P3 | `slice5b_p3` queue: `Booted Rails 8.1.4.1 application in development environment`, `start`, `[PropertyDataLookupWorker] Property#1964 already has property data, skipping`, `done` (`elapsed=0.198`); `Sidekiq::Status::status(jid)` → `nil` (§8 item 10) |
| P4 | `4 examples, 0 failures` |
| P5 | `86 examples, 0 failures` |
| P6 | `ActionMailer::MessageDelivery`; `SystemError::rails upgrade` (the mailer templates render under `render_tracker = :ruby`, row 9's only runtime touch) |
| P7 | `122 examples, 0 failures` |
| P8 | the newest active photo → `d2e08hhdrjhri.cloudfront.net`, `200 image/jpeg` |
| Named specs | `spec/lib` 367 / 0 (incl. the login and scheduler specs); `spec/architecture/rails_upgrade_spec.rb` + `spec/requests` 633 / 1 at commit 2 (the expected one), green from the bump on |
| Routes | `bin/rails routes` byte-identical to `master`'s (583 lines; a `master` worktree against the branch); `active_storage` `0` |
| Lint | `ruby -c` on every touched file; `rails_best_practices -e "db/migrate,vendor" .` 326 warnings before and after each commit (slice 4's baseline). No `.rubocop.yml`, so `bin/rubocop` cannot run |
| Trap greps | `grep -rn -E '^\s*[^#[:space:]].*active_support\.' config/initializers` → empty; the only `active_support.` line left under `config/initializers` is the comment `deprecation_reporting.rb:3`; `grep -rn belongs_to_required_by_default config app` → empty; `to_time_preserves_timezone` appears only in the contract's `key?` example and its comment; `git diff master...HEAD` on `strong_migrations.rb`, `Gemfile`, `Gemfile.lock`, `.ruby-version`, `client_ip_header.rb`, `production.rb` and `forwarded_header_spec.rb` → 0 lines; `config/application.rb` differs by the one `load_defaults` pair; `lib/crmls.rb` by `rescue => error`, the message, one why-comment and the `notify` line |
| Flags runner | development, at `27e45f1b`: `loaded_config_version=8.1` (Float); `strict_freshness config=true applied=true`; `Regexp.timeout=1.0`; `escape_json_responses config=false applied=false`; `escape_js_separators config=false applied=false`; `escape_html_entities applied=true`; `finder config=true applied=true`; `redirect :raise/:raise`; `render_tracker :ruby/:ruby`; `autocomplete true/true`; `yjit config=false enabled=false`; `csrf per_form=true origin_check=true`; `to_time key?=false`; `belongs_to_required_by_default=true validates_foreign_key=false`; `shim files=[]` — plan fact 2's "after 5b" column exactly |
| P-PROD | step 2 |
| P-S17, S15, S15b rehearsals | below |

**P-S17 — the disclosure gallery across the flip, in development** (plan Approval 8; amendment 7).
Two servers against the restore: a detached `master` worktree at `808d383f` (`.env` copied in and
removed afterwards, `tmp/` created) on `:3000`, and the branch on `:3010`. Order 77996, token
`yqly4v2J` — the richest compliant unlocked gallery on the restore (no gallery on it carries an
entity; amendment 7), address `1175 La Tortuga Dr, Vista 92081`, 76 photos:

```
master 200   branch 200
bytes 25501 25501; photos 76 76
jq -S diff: empty
u0026 counts: 0 0
raw files byte-identical
```

**S15b rehearsal — the byte-change control** (amendment 7): `PUT /order_types/1` with
`{"orderType":{"categoryType":"A <b> & B"}}` and a development system-admin JWT, against each server.
`validate_category_type` answers before `update` runs, so nothing is written (order type 1's
`updated_at` stayed 2026-06-09 15:54:21 UTC):

```
master 422 {"errors":["Category type A \u003cb\u003e \u0026 B is not a valid category"]}
branch 422 {"errors":["Category type A <b> & B is not a valid category"]}
parsed errors identical
```

**S15 rehearsal:** `POST /states` with `{"state":{"name":""}}` against each server → `422` and
`{"errors":["Country must exist","Name can't be blank","State code can't be blank","Country can't be blank"]}`
from both, byte-identical (no entity in the messages).

### 2. The production-config probe (on the merge, before the push)

`deploy-rails-upgrade-5a.md` step 2's wrapper, unchanged. Record the exit status with the output.

```bash
RAILS_ENV=production HONEYBADGER_REPORT_DATA=false bundle exec dotenv sh -c '
  DATABASE_URL="postgresql://${DATABASE_HOST:-localhost}:${DEVELOPMENT_DATABASE_PORT:-5432}/$DEVELOPMENT_DATABASE" \
  PGUSER="$DEVELOPMENT_DATABASE_USERNAME" PGPASSWORD="$DEVELOPMENT_DATABASE_PASS" \
  exec bin/rails runner "$1"' _ '
  p Rails.version
  p ActiveSupport::Notifications.notifier.listening?("deprecation.rails")
  p Rails.application.config.active_support.report_deprecations
  p Rails.application.deprecators.each.map { |deprecator| [deprecator.gem_name, deprecator.behavior.map { |behavior| ActiveSupport::Deprecation::DEFAULT_BEHAVIORS.key(behavior) }] }.uniq
  Rails.application.deprecators[:railties].warn("deploy probe")
  p DeprecationReporter.received?("deploy probe")
  p Rails.application.config.active_support.key?(:to_time_preserves_timezone)
  p Rails.application.config.loaded_config_version
  p Rails.application.routes.routes.count
  p Honeybadger.config[:report_data]
  p ActionController::Base.escape_json_responses
  p Regexp.timeout
  p Rails.application.config.action_dispatch.strict_freshness
  p ActionDispatch::Http::Cache::Request.strict_freshness
  p Rails.application.config.yjit
  p ActiveSupport::JSON::Encoding.escape_js_separators_in_json
  p ActiveRecord.raise_on_missing_required_finder_order_columns
  p ActionController::Base.action_on_path_relative_redirect
  p ActiveRecord.belongs_to_required_validates_foreign_key
' > tmp/p-prod.log 2>&1; echo "exit $?"; cat tmp/p-prod.log; grep -c DEPRECATION tmp/p-prod.log
```

Expected, in order: `exit 0`; the Active Storage WARN line (Known); `"8.1.4.1"`; `true`; `true`;
`[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]` (**the load-bearing line**);
the gem's `Reporting error` line; `true`; `false` (no `to_time` key); **`8.1`** (S10, the bump);
`582` (`073ebe2f`); `false` (reporting off); **`false`** (`escape_json_responses`, row 5); `1.0`;
`true`; **`true`** (the applied freshness, from `load_defaults`); `true` (`yjit` in production mode);
**`false`** (`escape_js_separators_in_json`, applied); **`true`** (the finder flag); **`:raise`**;
`false` (`belongs_to_required_validates_foreign_key`, a 7.1 default no slice moves); and a
`DEPRECATION` count of `0`. **This is the only production-mode, eager-loaded boot before the push**: a
deprecation that only `load_defaults 8.1` raises would show here.

RESULTS (2026-11-10 16:23:05 UTC, branch `27e45f1b`, dev container). Every line as expected:

```
exit 0
W, [2026-11-10T16:23:05.543872 #48070]  WARN -- : Generating image variants require the image_processing gem. Please add `gem "image_processing", "~> 1.2"` to your Gemfile or set `config.active_storage.variant_processor = :disabled`.
"8.1.4.1"
true
true
[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]
I, [2026-11-10T16:23:05.592606 #48070]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=92f8b00f-2b61-4818-b33c-3dbe6ee2f9db level=1 pid=48070
true
false
8.1
582
false
false
1.0
true
true
true
false
true
:raise
false
--- DEPRECATION lines: 0
```

RESULTS (on the merge, before the push) — Dan, 2026-11-11 16:05:46 UTC, `master` at `24309546`, the
merge, whose tree is `27e45f1b`'s (`git diff` empty). Every line as expected: `exit 0`; the WARN line;
`"8.1.4.1"`; `true`; `true`; `[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]`;
the `Reporting error` line; `true`; `false`; **`8.1`**; **`582`**; `false`; **`false`**; `1.0`;
`true`; **`true`**; `true`; **`false`**; **`true`**; **`:raise`**; `false`; and a `DEPRECATION`
count of `0`. The terminal garbled the pasted command's echo; the output carries all 18 values, in
order.

### 3. Pre-push captures (on the host, on the release that is live)

```bash
heroku releases -n 3 --app insgtapi
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; p Rails.application.config.loaded_config_version; p Regexp.timeout; p ActionDispatch::Http::Cache::Request.strict_freshness; p ActionController::Base.escape_json_responses'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'mls_import = MlsImport.where("total_listings > 1").order(:created_at).last; p mls_import.slice("created_at", "total_listings", "total_updated", "duration"); p mls_import.created_at - mls_import.duration'
heroku logs -n 1500 --app insgtapi > tmp/s16-before.log
grep -c "Regexp::TimeoutError" tmp/s16-before.log
head -1 tmp/s16-before.log | cut -c1-32
tail -1 tmp/s16-before.log | cut -c1-32
RELEASE=v672   # or the newer one `heroku releases -n 3` printed, if master moved
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 5b', 'release $RELEASE').deliver_now"
```

**S15 "before"** (plan, "Production"; a blank name reaches the model, an empty object answers 400):

```bash
curl -sS -X POST https://api.insightphotos.net/states -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -d '{"state":{"name":""}}' -o tmp/s15-before.json -w '%{http_code}\n'
jq -S . tmp/s15-before.json
```

**S15b "before"** (amendment 7; the byte-change control — a refused update, nothing is written):

```bash
curl -sS -X PUT https://api.insightphotos.net/order_types/1 -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -d '{"orderType":{"categoryType":"A <b> & B"}}' -o tmp/s15b-before.json -w '%{http_code}\n'
cat tmp/s15b-before.json
```

**S17 "before"** (amendment 7). The token runner verifies `yqly4v2J` and falls back to the largest
gallery among the newest 40 compliant unlocked orders:

```bash
heroku run --no-tty --app insgtapi rails runner 'o = Order.active.find_by_token_or_id("yqly4v2J"); o = nil unless o && !o.locked? && !o.legacy_delivery?; o ||= Order.active.where(compliance_mode: 2, locked: false).order(id: :desc).limit(40).max_by { |order| order.photos_for_disclosure_gallery.size }; puts o.token; puts o.photos_for_disclosure_gallery.size'
TOKEN=yqly4v2J   # or the token the runner printed
curl -sS "https://api.insightphotos.net/orders/$TOKEN/disclosure_gallery" -o tmp/s17-raw-before.json -w '%{http_code}\n'
jq -S . tmp/s17-raw-before.json > tmp/s17-before.json
grep -c 'u0026' tmp/s17-raw-before.json
jq '.data | length' tmp/s17-raw-before.json
```

Then three reads in the web UIs: **Papertrail** `Regexp::TimeoutError` over the last seven days;
**Honeybadger** `environment:"production" class:"Regexp::TimeoutError"`, `-is:resolved` then
`is:resolved`, both `-is:ignored`; **the ops@ inbox**, the most recent `SystemError::` email from the
import with its date (expected still the 2021-08-31 `Crmls Login Failure`). And **S18's "before"**:
Heroku Metrics → Memory for `web` and `backgroundworker` over the 24 h before the push (the band,
in MB).

Expected before:

- The release runner: `8.1.4.1`, `7.2`, `1.0`, `false`, `true` (the WARN line first).
- S4: `["Carlsbad", "Oceanside", "Leucadia"]`.
- The import row: the last hour's run, finished at :34–:37 UTC, `total_listings` 654–659, `duration`
  270–420 s, its start at about :30.
- `Regexp::TimeoutError` `0` in the buffer, `0` in Papertrail, No Results in Honeybadger (5a's SH).
- S15: `422`; `{"errors":["Country must exist","Name can't be blank","State code can't be blank","Country can't be blank"]}`.
- S15b: `422`; `{"errors":["Category type A \u003cb\u003e \u0026 B is not a valid category"]}` — the
  escaped bytes are the "before".
- S17: the runner prints `yqly4v2J` and `76` (ASSUMPTION: the order is unchanged since the restore;
  otherwise the fallback's token and count, used for both captures); `200`; `u0026` count `0`; the
  photo count recorded.
- S6: the email arrives.

The import runner skips rows with `total_listings` `1` (amended 2026-11-11, here and in step 6).
`Crmls.extract_and_load_listing` writes one such row whenever a user syncs a single listing
(`lib/crmls.rb:79`), so `.last` alone can return that sync instead of the hourly run, as it did at
the first capture below.

RECORDED (before) — Dan, on the host, 2026-11-11 16:06–16:11 UTC, on **v674**:

- **Releases:** `v674` (Set `AWS_BACKUP_SECRET_ACCESS_KEY`, 2026-11-10 16:41:43 UTC) and `v673` (Set
  `AWS_BACKUP_ACCESS_KEY_ID`, 16:41:22 UTC) are on top of `v672`. Both only set a config var, for
  Dan's canarytoken setup, so the slug is still `808d383f`, and no code in insgt-api reads either
  var. **v674 is the "before" and the rollback target** (Rollback); 5b's push is expected as v675.
- **The release runner:** `8.1.4.1`, `7.2`, `1.0`, `false`, `true` (16:06:32 UTC). As expected.
- **S4:** `["Carlsbad", "Oceanside", "Leucadia"]`. As expected.
- **The import row.** The first runner returned a single-listing sync, not the hourly run:
  `created_at` 15:55:20 UTC, `total_listings` 1, `total_updated` 1, `duration` 6 s (the note
  above). The amended runner (16:18:46 UTC) returned the 15:30 run: start 15:30:17 UTC, `created_at`
  15:35:39, `total_listings` 652, `total_updated` 0, `duration` 322 s. **This is S9b's baseline.**
  652 is under the 654–659 band of 11-10, as in 5a's SH: `total_listings` is Insight's own
  active-import count (`lib/crmls.rb:315–316`), and it drifts as listings leave that set, so
  step 6 compares against 652, not the band.
- **S16's buffer:** `Regexp::TimeoutError` `0` in 1,500 lines, `2026-11-11T14:42:27` …
  `2026-11-11T16:07:00` UTC. Honeybadger: No Results, both resolved states (5a's SH, read by
  15:54 UTC). Papertrail (Dan, about 16:20 UTC): "No matching events", searched back to Oct 29 at
  07:00 PM, more than the seven days.
- **The inbox:** no `SystemError::` email of any kind since 5a's push (Dan, 15:59 UTC), so the last
  import email is still the 2021-08-31 `Crmls Login Failure`.
- **S6:** the runner printed nothing after the WARN line (16:08:00 UTC). `SystemError::rails upgrade
  slice 5b` arrived at ops@insightphotos.net (`Date:` 16:08:00 UTC; Gmail received it 16:08:02
  UTC), from team@insightphotos.net through SendGrid, body `release v674`. As expected.
- **S15:** `422`, and the four-message `errors` array, as expected.
- **S15b:** `422`, and the body is the expected line above byte for byte, entities escaped: the
  "before".
- **S17:** the runner printed `yqly4v2J` and `76` (16:10:49 UTC); `200`; `u0026` count `0`;
  `.data | length` `76`. As expected; `TOKEN=yqly4v2J` for step 5.
- **S18 "before", `web`** (Dan, Heroku Metrics, the 24 h to about 16:20 UTC): max 797.2 MB
  (77.9 % of the 1,024 MB quota), average 665.6 MB, latest 738.3 MB; swap up to 35 MB. The memory
  climbs after each reset and resets about every 12 h: from the 16:41 UTC restart (v673–v674) to a
  peak of about 800 MB, reset at about 04:47 UTC, then to about 700 MB by 15:45. The 12 h reset fits
  `PumaWorkerKiller.enable_rolling_restart(12 * 3600)` (`config/initializers/puma_worker_killer.rb:1`);
  the boot log shows Puma in cluster mode with 2 workers. `web.2` restarted twice more, at
  15:45:55 and 16:01:49 UTC, each "Relocating dyno to a new server": Heroku's, not the app's
  (`tmp/s16-before.log`). So S18 compares the peak each cycle reaches, not the 24 h max, which
  depends on where the resets fall.
- **S18 "before", `backgroundworker`** (Dan, Heroku Metrics, 1 Standard-2X dyno, the 24 h to the
  read): max 713.9 MB (69.7 % of 1,024 MB), average 536.7 MB, latest 689.1 MB; swap up to 18 MB.
  It has not restarted since the 16:41 UTC config change, so the window is one climb: about 250 MB
  at boot, about 500 MB within 2 h, steps to about 690 MB by about 05:30 UTC, then flat at about
  690–714 MB. Sidekiq has no rolling restart. 5b's push restarts it, so S18 compares the climb from
  that boot with this one, hour for hour.

## Deploy

### 4. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

No gem change, so the build installs nothing new. A failed build is not a release; the live one stays.

RECORDED: **v675**, `git push heroku master` of `24309546` (Dan, 2026-11-11). The local reflog has
`heroku/master` updated by push to `24309546` at 11:26:27 -0500 (16:26:27 UTC, 08:26 PST); the
dynos restarted 16:26:26–16:26:38 UTC. That is before the 09:00 PT window, by Dan's decision, and
26 minutes into the 08:00 PT delivery window (Deploy log). `heroku releases -n 1`'s line was not
pasted; the release falls just before 16:26:26 UTC. The 15:30 UTC import finished at 15:35:39, and
the 16:30 run starts after the release, so **the watched import is the 16:30 UTC run**.

### 5. Within 30 minutes

Set `RELEASE` and `JWT` first. Every `heroku run … rails runner` prints the Active Storage WARN line
before its own output (Known); it is not a failure.

```bash
RELEASE=v675   # the release `heroku releases -n 1` printed
heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
heroku run --no-tty --exit-code --app insgtapi rails runner "puts Honeybadger.notify('rails upgrade slice 5b marker', error_class: 'UpgradeMarker', fingerprint: 'rails-upgrade-marker', tags: 'upgrade', context: { rails: Rails.version, release: '$RELEASE' }, sync: true).inspect"
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; p Rails.application.config.active_support.key?(:to_time_preserves_timezone); p Rails.application.config.loaded_config_version; p Rails.application.config.yjit; p RubyVM::YJIT.enabled?; p ActionController::Base.escape_json_responses'
heroku run --no-tty --app insgtapi rails runner 'puts Regexp.timeout.inspect; p ActionDispatch::Http::Cache::Request.strict_freshness'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 5b', 'release $RELEASE').deliver_now"
curl -sS -X POST https://api.insightphotos.net/states -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -d '{"state":{"name":""}}' -o tmp/s15-after.json -w '%{http_code}\n'
diff <(jq -S .errors tmp/s15-before.json) <(jq -S .errors tmp/s15-after.json) && echo S15 identical
cmp tmp/s15-before.json tmp/s15-after.json && echo S15 bytes identical
curl -sS -X PUT https://api.insightphotos.net/order_types/1 -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -d '{"orderType":{"categoryType":"A <b> & B"}}' -o tmp/s15b-after.json -w '%{http_code}\n'
cat tmp/s15b-after.json
diff <(jq -S .errors tmp/s15b-before.json) <(jq -S .errors tmp/s15b-after.json) && echo S15b parsed identical
curl -sS "https://api.insightphotos.net/orders/$TOKEN/disclosure_gallery" -o tmp/s17-raw-after.json -w '%{http_code}\n'
jq -S . tmp/s17-raw-after.json > tmp/s17-after.json
diff tmp/s17-before.json tmp/s17-after.json && echo S17 identical
grep -c 'u0026' tmp/s17-raw-after.json
```

S3 is the five-line runner of runbook 5a plus `escape_json_responses` (amendment 7); S10 is its
`loaded_config_version` line. No command here calls the 8.1-deprecated time-zone reader.

Expected, reasoned before the push:

| # | Check | Expected |
| :-- | :-- | :-- |
| S2 | `heroku ps`, `grep Booted` | all dynos up; `Booted Rails 8.1.4.1 application in production environment`. A boot failure is a rollback |
| S1 | `/up` | `200`; the Honeybadger uptime check green |
| S0 | marker | a notice id; `UpgradeMarker` gains an occurrence with context `rails: 8.1.4.1` and the real release |
| S3 / **S10** | the six-line runner | `8.1.4.1`, `false`, **`8.1`** (S10), `true`, `true` (YJIT stays on in production — Approval B; a `false` is a finding), **`false`** (`escape_json_responses`) |
| **S14** | the timeout and the applied freshness | `1.0`, **`true`** (the applied value arrived with `load_defaults`; `false` means the bump did not take — Rollback) |
| S4 | nearby cities | identical to step 3's capture |
| S5 | Stripe | `true` |
| S6 | email | `SystemError::rails upgrade slice 5b` arrives at ops@insightphotos.net (row 9's mailer path in production) |
| **S15** | `POST /states` | `422`; the parsed `errors` array identical to the "before"; the raw files byte-identical (no entity in the messages) |
| **S15b** | `PUT /order_types/1` | `422`; the body now reads `Category type A <b> & B is not a valid category` — raw `<b> &` where the "before" had `\u003cb\u003e \u0026`; the parsed `errors` array identical. Nothing written |
| **S17** | the disclosure gallery | `200`; `diff` of the `jq -S` files empty; `u0026` `0` → `0` (no entity in any gallery, amendment 7; S15b is the byte control) |

Then Honeybadger over the 30 minutes: Errors with `-is:resolved -is:ignored` lists the marker and
nothing new. A `MissingRequiredOrderError`, an `UnsafeRedirectError` or a `Regexp::TimeoutError` here
is read at once (Rollback).

RECORDED — Dan, on the host, 2026-11-11 16:27–16:30 UTC, `RELEASE=v675`. Every runner printed the
Active Storage WARN line first (Known):

- **S2:** `backgroundworker.1` and `web.1` up 16:26:26 UTC, `web.2` 16:26:38; `Booted Rails 8.1.4.1
  application in production environment` from `backgroundworker.1` at 16:26:37 UTC, one boot.
  **Pass.**
- **S1:** `/up` → `200`. **Pass.** The Honeybadger uptime check was not read.
- **S0:** notice `46a3e669-7ebb-4e25-9340-610e36ebf222` (`code=201`, 16:27:42 UTC). `UpgradeMarker`
  (fault 135218267) gains the occurrence with context `{"rails" => "8.1.4.1", "release" => "v675"}`;
  Honeybadger's notification email arrived at 11:27 -05:00. **Pass.**
- **S3 / S10:** `8.1.4.1`, `false`, **`8.1`**, `true`, `true`, **`false`** (16:27:55 UTC). The bump
  took, YJIT stays on in production, and `render json:` no longer escapes. **Pass.**
- **S14:** `1.0`, **`true`** (16:28:07 UTC). The applied freshness arrived with `load_defaults 8.1`.
  **Pass; no rollback signal.**
- **S4:** `["Carlsbad", "Oceanside", "Leucadia"]`, identical to step 3's. **Pass.**
- **S5:** `true`. **Pass.**
- **S6:** the runner printed nothing after the WARN line (16:28:47 UTC). `SystemError::rails upgrade
  slice 5b` arrived at ops@insightphotos.net (`Date:` 16:28:48 UTC; Gmail received it 16:28:49
  UTC), from team@insightphotos.net through SendGrid, body `release v675`. **Pass: row 9's mailer
  path works in production on 8.1.**
- **S15:** `422`; "S15 identical" and "S15 bytes identical". **Pass.**
- **S15b:** `422`; the body reads `{"errors":["Category type A <b> & B is not a valid category"]}`,
  raw `<b> &` where step 3's "before" had the escaped entities; "S15b parsed identical". Nothing is
  written (the validation answers before `update`). **Pass: the byte control shows row 5 is live,
  and the decoded value is unchanged.**
- **S17:** `200`; "S17 identical" (the `jq -S` diff is empty); `u0026` `0` → `0`. **Pass.**
- **Honeybadger, the 30 minutes:** read late, after 17:27 UTC (the marker shows Last `1h` and `0` in
  the 1 Hour column), so it covers about the first hour. Errors with `-is:resolved -is:ignored`, all
  environments, newest first: `UpgradeMarker` (`rails upgrade slice 5b marker`, production) and
  nothing else. No `MissingRequiredOrderError`, `UnsafeRedirectError` or `Regexp::TimeoutError`,
  and no notice from commit 4's login path. **Pass.**

**Step 5 passes.**

### 6. One hour after the push (S7), and the watched import (S9, S9b, S16, the inbox)

**S7**, one hour after the push:

```bash
heroku logs -n 1500 --app insgtapi > tmp/s7.log
head -1 tmp/s7.log | cut -c1-32
tail -1 tmp/s7.log | cut -c1-32
grep -c "status=5" tmp/s7.log
grep -oE '\] [A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)* \(' tmp/s7.log | sort | uniq -c | sort -rn
grep -c "Regexp::TimeoutError" tmp/s7.log
```

Then Papertrail: `status=5` and `Regexp::TimeoutError` from the push to one hour after it. Expected:
no `status=5` in the hour; no exception class other than `ActionController::RoutingError` (scanner
traffic, `/cable` included); `0` `Regexp::TimeoutError`.

**The watched import** is the first `import_listings` run that **starts** after the release time.
Read all four once it has finished, at about :35–:45 UTC — the same four-part read as runbook 5a
step 6, because `Regexp.timeout` is still live and `load_defaults 8.0` sets it again (`||= 1`):

```bash
heroku run --no-tty --app insgtapi rails runner 'mls_import = MlsImport.where("total_listings > 1").order(:created_at).last; p mls_import.slice("created_at", "total_listings", "total_updated", "duration"); p mls_import.created_at - mls_import.duration'
heroku logs -n 1500 --app insgtapi > tmp/s16.log
head -1 tmp/s16.log | cut -c1-32
tail -1 tmp/s16.log | cut -c1-32
grep -c "Regexp::TimeoutError" tmp/s16.log
```

| # | Check | Expected |
| :-- | :-- | :-- |
| S9 | Honeybadger → Check-Ins, `import_listings` | checked in at about :35–:45 UTC for the watched hour, judged in UTC |
| S9b | the `MlsImport` runner | a new row for the watched hour: its start after the release time, `created_at` at about :34–:37; `total_listings` within a few of step 3's baseline, 652 (the 654–659 band of 11-10 drifted; step 3); `duration` 270–420 s. **No new row while S9 passed is the login path:** from this release a login failure is also a Honeybadger error (commit 4), so read SH and the ops@ email together. The runner skips single-listing syncs (`total_listings` `1`; step 3's note) |
| S16 | the buffer grep; Papertrail `Regexp::TimeoutError` since the push; the ops@ inbox | `0`; `0`; no `SystemError::` email from the import since the push |

RECORDED (Dan, on the host, from 17:42 UTC on 2026-11-11; completed from reads on 2026-11-18):

- **S9b:** the runner ran at 17:42:05 UTC, an hour after the watched run, so `.last` returned the
  **17:30 UTC run**, the second after the release and also on v675: start 17:30:32 UTC,
  `created_at` 17:35:33, `total_listings` 653, `total_updated` 0, `duration` 301 s. Every bound
  holds (start after 16:26:27, `created_at` in :34–:37, 653 against 652, 301 s in 270–420 s).
  **The watched 16:30 run's row** (Dan, 2026-11-18, a console query on `created_at` between 16:30
  and 16:45 UTC of 11-11, which returned one row): id 212491, `organization_id` 70, `created_at`
  16:35:46 UTC, `total_listings` 653, `total_updated` 1, `duration` 331 s, so its start is
  16:30:15 UTC, after the release at 16:26:27. Every bound holds. **Pass.**
- **S16:** `Regexp::TimeoutError` `0` in the buffer's 1,500 lines, `2026-11-11T16:45:00` …
  `2026-11-11T17:42:18` UTC. That covers the 17:30 run but starts after the 16:30 run would have
  finished, so Papertrail since the push carries the watched run: "No matching events", searched
  back to Nov 4 at 07:00 PM (Dan, 2026-11-18). Papertrail keeps seven days: the `status=5` search
  the same morning hit "Oldest event reached … before Nov 11 at 08:49 AM" (its clock is UTC-5, so
  13:49 UTC). The push, at 16:26 UTC, is inside that by about 2½ h, so the search covers the push
  and the whole week after it, not the days before. **Pass.**
- **S9:** read on 2026-11-18 only, as the check-in's state that day: `import_listings` "is
  reporting", report period 1 hour, grace 30 minutes, last seen "1 hour ago". The check-in for the
  watched hour itself was not read at the time; S9b's row for that hour is the evidence that the
  run finished.
- **The inbox:** Gmail search `SystemError:: after:2026/11/11` (Dan, 2026-11-18): "1–1 of 1", the
  thread `SystemError::rails upgrade slice 5b - release v675` of Nov 11, which is steps 3 and 5's
  own S6 emails. No `SystemError::` email from the import since the push. **Pass.**
- **Honeybadger:** at about 1 h, only the marker (step 5), so neither run reported a login failure
  through commit 4's path or raised anything else.
- **S7:** read on 2026-11-18, from Papertrail, because the buffer no longer reaches the hour. The
  `status=5` search, scrolled to "Oldest event reached" (13:49 UTC of 11-11), has its first match
  at **2026-11-13 21:35:36 UTC**, the database-connection burst of step 7. So there is no
  `status=5` from before the push until then, the hour after the push included.
  `Regexp::TimeoutError` is S16's search: none. The exception-class grep was not run for that
  hour; Honeybadger at about 1 h listed only the marker (step 5). The buffer pulled the same day
  (`2026-11-18T12:25:43` … `13:35:11` UTC) is a week late and clean: `status=5` `0`, no exception
  class, `Regexp::TimeoutError` `0`. **Pass.**

**Step 6 passes:** the watched import on S9b, S16 and the inbox, and S7. S9 for the watched hour
stands as recorded above.

### 7. 24 hours after the push (SH, S18)

Honeybadger → Errors, compared with the slice 0 baseline **by error** (replace the time with the push),
each search with `-is:resolved` and then `is:resolved`, both with `-is:ignored`:

```
environment:"production" created.after:"<push>"
environment:"production" class:"Regexp::TimeoutError" occurred.after:"<push>"
environment:"production" class:"ActiveRecord::MissingRequiredOrderError" occurred.after:"<push>"
environment:"production" class:"ActionController::Redirecting::UnsafeRedirectError" occurred.after:"<push>"
environment:"production" class:"RailsDeprecation" occurred.after:"<push>"
```

**Pass condition:**
- No `Regexp::TimeoutError`, no `MissingRequiredOrderError` (row 7 — every model has `id`, so one would
  mean a relation built without the key: a finding), no `UnsafeRedirectError` (row 6 — impossible
  without a `redirect_to`).
- No new error whose backtrace touches `config/application.rb`, the JSON renderer
  (`action_controller/metal/renderers.rb`), `active_support/json/encoding.rb`, `lib/crmls.rb`, the
  `rets` gem, or actionpack's `http/cache.rb`.
- No new `RailsDeprecation`.
- The ops@ inbox still holds no `SystemError::` email from the import since the push.
- **A `Crmls Login Failure` notice from `lib/crmls.rb` is commit 4's new path.** Read its context: a
  `Regexp::TimeoutError` message is this slice's finding (Rollback); any other cause is an ordinary
  login failure seen by Honeybadger for the first time — recorded here, not blocking (plan, Risks).
- **S18:** Heroku Metrics → Memory for `web` and `backgroundworker`, the 24 h after the push against
  the 24 h before: unchanged within the day-to-day band (Approval B; the only runtime delta beyond
  the flags is `config.yjit`, which stays `true` in production). A sustained climb is a finding;
  `config.yjit = false` in `application.rb` is the escape hatch that keeps the rest of 8.1.

Anything else is an old bug seen for the first time: record it here and fix it on its own branch.
**The quiet week (§2.2) runs from this push to Wed 11-18.**

RECORDED — SH (Dan, 2026-11-18, about seven days after the push; no read was taken at 24 h, so
this one read is both SH and the quiet week's closing read). Each search was run once, with the
push time `2026-11-11 16:26:27 UTC` and no `is:resolved` term, sorted newest first. Without that
term a search returns resolved and unresolved faults together (Dan), so one search stands for the
two this step asks for:

- **`created.after`:** five faults, all `ActiveRecord::ConnectionNotEstablished`, message
  `connection to server at "44.223.236.192", port 5432 failed: Connect…` (cut off in the list),
  each "5d old" and last seen "5d", so about 11-13:

  | Where | Count |
  | :-- | --: |
  | `orders#index` | 22 |
  | `listings#virtual` | 6 |
  | `photos#download_info` | 1 |
  | `listings#custom_domain_exists` | 1 |
  | `rake import_listings` | 1 |

  Dan: a network issue on Heroku's side at the time, unrelated to the code. Papertrail dates it:
  `status=500` from **2026-11-13 21:35:36 UTC**, on `web.1` and `web.2`, each `bytes=46` after
  about 105–115 ms in `db` (`orders#index`, `orders#processing`, `listings#virtual` in the lines
  read). Heroku Metrics for `web` has one H12 marker and a response-time spike to about 30 s in
  the same hour. That is a failed connection to the Postgres host, across unrelated actions and
  the Scheduler task, 31 occurrences in one burst and none since. The burst's end and the
  backtraces were not read. **Not this slice's finding**; recorded as the pass condition's
  "anything else". The `rake import_listings` occurrence means one hourly import failed, most
  likely the 21:30 UTC run of 11-13 (an inference from the time; its `mls_imports` row and the
  check-in were not read).
- **`Regexp::TimeoutError`:** No Results. **Pass.**
- **`ActiveRecord::MissingRequiredOrderError`:** No Results. **Pass.**
- **`ActionController::Redirecting::UnsafeRedirectError`:** No Results. **Pass.**
- **`RailsDeprecation`:** No Results. **Pass.**
- **Commit 4's path:** no `Crmls Login Failure` notice among the faults created since the push, so
  no login failure reached Honeybadger in the week.
- **The inbox:** as step 6: `SystemError:: after:2026/11/11` returns only the S6 thread, so no
  `SystemError::` email from the import since the push. **Pass.**

**SH passes; the quiet week is clean on Honeybadger.**

RECORDED — S18 (Dan, Heroku Metrics, 2026-11-18 at about 13:50 UTC: "Past 7 days" for both process
types, and "Past 24hrs" for `backgroundworker`). The seven-day view begins just before the push,
so the 24 h after it are its left edge, at coarse resolution; the levels below are read off the
graphs and are approximate, the MB figures are the page's own:

- **`web`** (2 dynos), seven days: max 880.7 MB (86.0 % of 1,024 MB), average 649.1 MB (63.4 %),
  latest 618.1 MB; swap up to 17 MB. The same sawtooth as before the push, a reset about every
  12 h, each cycle peaking at about 0.75–0.88 GB, with no rise across the week (the lowest
  cycles are Sun–Mon). Against step 3's "before" (peak about 800 MB, average 665.6 MB): the
  average is a little lower, and the highest peak is 83 MB over the "before" day's, taken over
  about fourteen cycles, not two. **Pass: no sustained climb.**
- **`backgroundworker`** (1 dyno), the 24 h after the push: about 0.2 GB from boot for about 19 h,
  then steps to about 0.3–0.45 GB. That is below the "before" climb hour for hour (about 500 MB
  within 2 h, about 690 MB by 13 h). **Pass.**
- **`backgroundworker`, the rest of the week (an observation, outside S18's window).** The dyno
  restarts about daily (seven markers, each at about 17:00–19:00 UTC), so each day is one climb.
  Six cycles peak at about 0.45–0.58 GB. The seventh, booted at about 17:00 UTC on 11-17,
  stepped to about 816 MB between about 21:00 and 22:30 UTC, while the dyno-load graph shows its
  busiest hours of the day, and has held flat since: max 829.5 MB (81.0 %), latest 815.7 MB, the
  week's highest and about 115 MB over the "before" max of 713.9 MB. One cycle of seven, and it
  follows job load, so it is not a climb across cycles. The next daily restart resets it.
- **Events:** a Config marker with a restart on Mon 11-16 at about 17:00 UTC, on both process
  types: a release after v675 (UNVERIFIED which; `heroku releases`). `heroku rollback` with no
  version therefore no longer goes back to v674 (Rollback's last case). `web` also shows two H27
  markers (a client closing its connection), at about 03:00 UTC on 11-14 and 11-15, and App
  Guidance counts 5 request timeouts in the seven days.

**S18 passes.**

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to **v674**, the release step 3 recorded: 5a's slug `808d383f` plus the two config vars set in
v673–v674 (Dan's canarytoken setup). `heroku rollback` with no version goes back one release, which
is v674 while 5b's release is the newest. **Never `heroku rollback v672`.** A rollback copies the
target release's config vars as well as its slug ("This release copies the compiled slug or OCI
image and config vars … of the release you roll back to", Heroku Dev Center, Releases), so v672
would drop `AWS_BACKUP_ACCESS_KEY_ID` and `AWS_BACKUP_SECRET_ACCESS_KEY`. If another release lands
after the push, read `heroku releases` first, because a rollback past it drops its config change
too. Nothing to undo: no migration, no ENV change, no data written by the slice. In git, revert the four commits (the bump
commit alone restores the shims).

**A Scheduler one-off started under this release keeps its slug** until it exits, up to about seven
minutes (plan P8). Verify the rollback after it has gone: `heroku ps --app insgtapi` lists no
`scheduler.*` dyno, then S3 → `7.2` and S14 → `1.0`, `false`.

**When to roll back:** a boot failure (S2); S10 not `8.1` or S14's applied freshness still `false`
(the bump did not take); any `Regexp::TimeoutError`, `MissingRequiredOrderError` or
`UnsafeRedirectError` in production; a consumer failing to parse a response (none is expected: S15,
S15b and S17 are the proof, and every consumer parses JSON). A boot deprecation from
`load_defaults 8.1` would have shown in P-PROD; one in production is a `RailsDeprecation` notice and
a rollback.

## Known, kept by decision

- **One Active Storage WARN line per process boot on 8.1.4** (slice 3's Known; §8 item 7). Not raised,
  not a deprecation, not reported.
- **The two config-only shim lines never applied until this release** (plan fact 16; Approval 7):
  5a's `strict_freshness` and 5b commit 1's `escape_js_separators_in_json` reached the config alone;
  `load_defaults 8.1` applies both. The contract pins the applied values and that no uncommented
  `active_support.` line remains under `config/initializers` (upstream rails/rails#59146, fix PR
  #59147 open: once it ships, such a line would start applying silently).
- **Row 5 masks row 8 on `render json:`** (Approval A): an error body loses `\u003c` and `\u2028`
  together from commit 1; a JBuilder body is row 8's only witness, and its separator went raw only
  with the bump. The request spec splits the two on purpose.
- **S17 has no byte control on the galleries** (amendment 7): on the restore no compliant unlocked
  order's gallery carries an entity or separator (1,365 orders scanned), so S17 is the parsed-value
  diff alone, and S15b — a refused `PUT /order_types/1` — is the control that bytes changed.
- **YJIT is off in test and development from this release's code** (row 4): the suite takes about
  16 s longer; production is unchanged (`config.yjit` `true`, S3).
- **The CSRF defaults are `true` and inert** (plan fact 9): `application_controller.rb:3` skips
  verification; `test.rb:32` turns forgery protection off, so no spec exercises it. S15 is the
  authenticated `POST` that shows nothing changed.
- **A CRMLS login failure is a Honeybadger error from now on** (commit 4). The restore's 234 hourly
  runs had one missing hour and the ops@ inbox no login email since 2021, so the noise is expected
  to be nil; if one fires, SH's triage rule applies.
- **One-off dynos overlap a release** (plan P8): an import in flight at the push finishes on v672's
  slug, which is why the watched run is the first one that starts after the release.
- **The 24 rspec-rails `:unprocessable_entity` warnings** (rack 3.2 renamed the status), unchanged;
  `json_escaping_spec.rb` uses `:unprocessable_content` and adds none.
- **Review rounds** (2026-11-10, `predeploy-review-rails`; Codex `gpt-6-astra` at effort `max` — a
  `load_defaults` bump and a JSON renderer change reach every response — in a detached git worktree at
  `27e45f1b`, so no `.env` or `config/master.key`; both rounds left the worktree and the real tree
  untouched). Round 1 (16:30–16:38 UTC): "No actionable findings survived this review." Round 2, the
  same HEAD with a fresh-eyes brief (18:20–18:28 UTC): "No actionable findings survived the independent
  review." Claude's own pass raised nothing (the review record). Both rounds name the same residue —
  Honeybadger receipt from a Scheduler one-off and the live S15/S15b/S17 reads — which this runbook's
  production steps cover.

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed`, the release, and steps 3–7's results.
- `rails-upgrade.md` §4.6: 5b's "as deployed" line, §6's calendar as it went, §8 items 32 and 33
  closed. The v9 amendment itself is written before the push (plan, Approval 5; Dan, 2026-11-09).
- The quiet week's SH reads (§2.2) gate the Render rehearsal (§6).

## Deploy log

- **2026-11-10 — implemented and verified in development** (branch `chore/rails-upgrade-slice-5b`,
  four commits `4d5eef28`…`27e45f1b` off `master` `808d383f`, production's code as v672): step 1's
  table, P-S17 and the S15/S15b rehearsals, and P-PROD as step 2's RESULTS.
- **2026-11-10 — reviewed, two rounds** (Known): neither round raised a finding, so no commit changed;
  the suite at `27e45f1b` stands at `2117 examples, 0 failures` both ways.
- **2026-11-10 — written back:** `rails-upgrade.md` v9, the codebase notes, the plan's implementation
  record and the review record `docs/architecture/reviews/2026-11-10-slice-5b-insgt-api.md`. Status
  `Ready`; the merge and the push wait on 5a's watched import and SH (Prerequisites).
- **2026-11-11 — prerequisite read** (Dan): 5a's SH passes at about 25 h (runbook 5a step 7).
- **2026-11-11 — merged; suite and probe on the merge; step 3 on v674.** Dan merged as `24309546`
  (the branch's tree). The suite is `2117 examples, 0 failures` both ways, and the probe gave every
  line as expected (step 2). Releases v673–v674 (2026-11-10 16:41 UTC) only set two config vars for
  Dan's canarytoken setup, so v674 is the "before" and the rollback target, never v672 (Rollback).
  Step 3's captures are as expected, except that the import runner caught a single-listing sync; it
  now skips those, here and in step 6. Its baseline is the 15:30 run (652, 322 s). Papertrail has
  no `Regexp::TimeoutError` back to Oct 29. S18 `web` peaks at about 800 MB per 12 h cycle; two
  `web.2` relocations by Heroku at 15:46 and 16:02 UTC. S18 `backgroundworker` climbs from about
  250 MB to about 690–714 MB with no reset since 16:41 UTC. Every prerequisite is done.
- **2026-11-11 — Dan's decision, about 16:25 UTC (08:25 PST): push now**, before the 09:00 PT window
  opens. Slices 2–5a also went out before 09:00, but each before 08:00 PT; this push is the first
  after a delivery window (08:00 PT, §2.4) has begun. §2.4 does not say how long a window lasts.
- **2026-11-11 — pushed as v675** (Dan): `24309546`, 16:26:27 UTC (08:26 PST); dynos up
  16:26:26–16:26:38 UTC. Step 5 so far: S2 (one boot), S1, S0 (`v675`), S3, **S10 (`8.1`)**, **S14
  (`1.0`, `true`)**, S4, S5, S15, **S15b (raw `<b> &`, parsed identical)** and S17 all pass. S6's
  arrival and the 30-minute Honeybadger read remain. The watched import is the 16:30 UTC run.
- **2026-11-11 — step 5 passes** (Dan): S6 arrived 16:28:48 UTC; Honeybadger, read at about 1 h,
  lists only the marker. Step 6 in progress: the 17:30 run is inside S9b's bounds (653, 301 s) and
  the buffer has `0` `Regexp::TimeoutError` (16:45–17:42 UTC). The 16:30 run's row, S9, Papertrail,
  the inbox and S7 remain.
- **2026-11-18 — steps 6 and 7 read, seven days after the push** (Dan). The watched 16:30 run's
  row is in bounds (id 212491, start 16:30:15 UTC, 653, 331 s); Papertrail has no
  `Regexp::TimeoutError` back to Nov 4; the inbox search shows no import email. S9 was read as
  that day's state only, and S7's buffer is from 11-18, not the hour after the push. SH: the four
  class searches return No Results; the only faults created since the push are five
  `ActiveRecord::ConnectionNotEstablished` of about 11-13 (31 occurrences), which Dan attributes
  to a Heroku network issue. **SH passes and the quiet week closes clean.**
- **2026-11-18 — the remaining reads** (Dan). The inbox, searched from 11-11, holds only the S6
  thread. Papertrail's first `status=5` since before the push is the connection burst at
  2026-11-13 21:35:36 UTC, so **S7 passes** and the burst is dated. **S18 passes:** `web` keeps
  its 12 h sawtooth (seven-day max 880.7 MB, average 649.1 MB), and `backgroundworker` ran lower
  in the 24 h after the push than before it. One `backgroundworker` cycle, from 11-17, reached
  829.5 MB after a busy evening; recorded as an observation. A config release landed on 11-16.
  **Every step of this runbook is read.**
