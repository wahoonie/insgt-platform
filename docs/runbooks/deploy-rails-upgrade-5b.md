# Runbook: Rails Upgrade Slice 5b — the 8.1 framework defaults, then `config.load_defaults 8.1`

**Last updated:** 2026-11-10
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~25 min of prerequisite reads and captures; ~35 min for the push and step 5's
checks (S15, S15b and S17 included); S7 one hour after the push; S9, S9b, S16 and the ops@ inbox at
the first import that starts after the release; SH and S18 24 h later
**Status:** Draft — implemented and verified in development 2026-11-10 (step 1); review rounds pending.

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

- [ ] **5a's watched import passed on all four signals** (`deploy-rails-upgrade-5a.md` step 6): the
      15:30 UTC run of 2026-11-10 — S9 (the check-in), S9b (a new `mls_imports` row whose start follows
      14:48:26 UTC, `total_listings` 654–659, `duration` 270–420 s), S16 (`0` `Regexp::TimeoutError` in
      the buffer and in Papertrail) and the ops@ inbox (no `SystemError::` from the import since the
      push; the baseline is the 2021-08-31 `Crmls Login Failure`). Pass on S9 alone, or on S9 and SH,
      is not a pass (the login-swallow path passes both).
- [ ] **5a's SH passes** (runbook 5a step 7, at about 14:48 UTC on 2026-11-11, before this window
      opens): no `Regexp::TimeoutError`; no new error touching the 8.0 shim, the import files, the
      `rets` gem or `http/cache.rb`; no new `RailsDeprecation`; the inbox still quiet. An
      `IpSpoofAttackError` is the Client-IP fix's finding, not 5a's, and does not block 5b.
- [ ] Review rounds complete (two rounds of `predeploy-review-rails`, Codex included; Known)
- [ ] This runbook's Status is `Ready` (after the v9 write-back)
- [ ] Dan has merged `chore/rails-upgrade-slice-5b` into `master`, and `bundle exec rspec` is green
      **on the merge**. Expected with `master` still at `808d383f`: `2117 examples, 0 failures`, 0
      `DEPRECATION WARNING` lines, the 24 rack warnings — the branch's own count, since the branch is
      four commits on top of `master` and the merge tree is the branch tree. If `master` has moved, the
      count is sourced on the merge from `rspec --dry-run --format json`, not recomputed, and
      `git log origin/master..master` is read for what else ships.
- [ ] The production-config probe (step 2) printed the expected lines on the merge, `582` among them.
- [ ] Pre-push captures (step 3) recorded on v672: the release runner, S4, S6, the S9b and S16
      baselines, **S15, S15b and S17 "before"**.

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

RESULTS (on the merge, before the push): ___

### 3. Pre-push captures (on the host, on the release that is live)

```bash
heroku releases -n 3 --app insgtapi
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; p Rails.application.config.loaded_config_version; p Regexp.timeout; p ActionDispatch::Http::Cache::Request.strict_freshness; p ActionController::Base.escape_json_responses'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'r = MlsImport.order(:created_at).last; p r.slice("created_at", "total_listings", "total_updated", "duration"); p r.created_at - r.duration'
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

RECORDED (before): ___

## Deploy

### 4. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

No gem change, so the build installs nothing new. A failed build is not a release; the live one stays.

RECORDED: ___

### 5. Within 30 minutes

Set `RELEASE` and `JWT` first. Every `heroku run … rails runner` prints the Active Storage WARN line
before its own output (Known); it is not a failure.

```bash
RELEASE=vNNN   # the release `heroku releases -n 1` printed
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

RECORDED: ___

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
heroku run --no-tty --app insgtapi rails runner 'r = MlsImport.order(:created_at).last; p r.slice("created_at", "total_listings", "total_updated", "duration"); p r.created_at - r.duration'
heroku logs -n 1500 --app insgtapi > tmp/s16.log
head -1 tmp/s16.log | cut -c1-32
tail -1 tmp/s16.log | cut -c1-32
grep -c "Regexp::TimeoutError" tmp/s16.log
```

| # | Check | Expected |
| :-- | :-- | :-- |
| S9 | Honeybadger → Check-Ins, `import_listings` | checked in at about :35–:45 UTC for the watched hour, judged in UTC |
| S9b | the `MlsImport` runner | a new row for the watched hour: its start after the release time, `created_at` at about :34–:37; `total_listings` 654–659; `duration` 270–420 s. **No new row while S9 passed is the login path:** from this release a login failure is also a Honeybadger error (commit 4), so read SH and the ops@ email together |
| S16 | the buffer grep; Papertrail `Regexp::TimeoutError` since the push; the ops@ inbox | `0`; `0`; no `SystemError::` email from the import since the push |

RECORDED: ___

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

RECORDED: ___

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to **v672** (5a), or to the release step 3 recorded if `master` moved. Nothing to undo: no
migration, no ENV change, no data written by the slice. In git, revert the four commits (the bump
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
