# Runbook: Rails Upgrade Slice 5a — the 8.0 request-freshness and regexp-timeout defaults

**Last updated:** 2026-11-09
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~25 min of prerequisite reads and captures; ~30 min for the push and step 5's
checks; S7 one hour after the push; S9, S9b, S16 and the ops@ inbox at the first import that starts
after the release; SH 24 h later
**Status:** Draft — implemented and verified in development 2026-11-09 (step 1). Review rounds
pending.

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.6 rows 2 and 3 (v7). `docs/plans/rails-upgrade-slice-5.md`
holds every decision and deviation. Branch `chore/rails-upgrade-slice-5a`, one commit off `master`
**`316fa0e1`** — slice 4 merged (v671) — not the plan's `3f67af13`. Slice 4 merged and deployed
before 5a was cut, so Decisions 1's rebase never arose. Fact 16's boot check was re-run on the new
base and reproduced line for line (step 1).

1. `3ca24647` chore: enable the rails 8.0 request freshness and regexp timeout defaults —
   `config/initializers/new_framework_defaults_8_0.rb:25` and `:30` uncommented. `:18`, the `to_time`
   line, stays a comment (v6). The contract block `the 8.0 defaults are on; the 8.1 defaults stay off
   until slice 5b` replaces slice 3's one example with three. `spec/lib/crmls_login_timeout_spec.rb`
   (1) is new.

**No migration, no DDL, no ENV change, no gem change, no client release.** `config.load_defaults`
stays `7.2`, and no 8.1 flag moves.

**What changes in production:**

- **`Regexp.timeout` `nil` → `1.0`**, process-wide: web, worker and every Scheduler one-off. A match
  that runs past one second raises `Regexp::TimeoutError`. Ruby 3.4.12's engine memoises the classic
  catastrophic patterns (plan fact 8), and the app's own regex work over MLS data is sparse. The
  exposure is the `rets` gem's twelve response-parser sites, reachable only through a live CRMLS
  login, which is why this flag deploys alone and is watched across an import.
- **`config.action_dispatch.strict_freshness` `false` → `true`, with the applied value still
  `false`.** The action_dispatch railtie copies the config to `ActionDispatch::Http::Cache::Request`
  before `config/initializers` run (plan fact 16), so the shim line reaches only the config. The
  applied value arrives with `load_defaults 8.1` in 5b. Nothing reads it either way: there is no
  `fresh_when` or `stale?` in the app (plan fact 10).

**What moves for a human: nothing.** No response byte changes, the route table is identical (583),
and no visible value moves.

**How a `Regexp::TimeoutError` would show** (plan fact 7):

- **During extraction or loading:** it propagates out of the rake task. The check-in is skipped (S9),
  and Honeybadger's rake handler reports it (SH).
- **In a web request or a Sidekiq job:** Honeybadger reports it (SH).
- **During the CRMLS login, it is swallowed.** `Crmls#login`'s bare `rescue` (`lib/crmls.rb:444`)
  records it and emails `SystemError::Crmls Login Failure` to ops@. `extract_listings` then returns
  before it writes an `mls_imports` row, `load_listings` runs anyway, and **the check-in still
  arrives**. S9 and SH both pass on that path. The only signals are the missing `mls_imports` row
  (S9b) and the ops@ email (S16). The new spec documents the swallow; 5b's commit 5 adds the
  Honeybadger notice (plan, Approval D).

**Where this sits.** The fifth of six deploy mornings: 5b (Wed 11-11) once this deploy's import read
passes, then the quiet week to Wed 11-18, then the Render rehearsal (§6).

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. `tmp/` is
insgt-api's gitignored scratch directory. The production-config probe (step 2) runs in `apps/insgt-api`
on the merge, wherever Dan runs it. Honeybadger and Papertrail are the web UIs. Put each command on
its own line (slice 2's zsh url-quote-magic lesson).

## Deploy window

**Tue 2026-11-10, 09:00–11:30 Pacific** (17:00–19:30 UTC). Mon–Wed only, outside the 08:00 and 12:00
delivery windows (§2.4). The push waits for slice 4's SH read at about 24 h (v671, 2026-11-09 13:27:45
UTC).

**Which import is watched.** The Scheduler starts `import_listings` at about :30 past each UTC hour.
The restore's last run started 11:30:19 and finished 11:35:07 UTC, and production's runs since
2026-10-30 finish at :34–:37. A one-off dyno already running keeps the slug it started with (plan P8),
so **the watched run is the first one that starts after the release**. Push by 10:25 PT (18:25 UTC) and
that hour's :30 run is the watched one; a later push moves the reads an hour, not the slice.

**Slippage rule (§6):** if review and merge are not complete by 09:00 PT, the deploy moves to **Wed
11-11**, and 5b moves to **Mon 11-16**. **Nobody pushes after 11:30 to make the window.**

## Prerequisites

- [ ] **Slice 4's SH passes** (`deploy-rails-upgrade-4.md` step 7, at about 24 h): no new error
      since v671; no `RecordInvalid` with `must exist` from a `save!` path; no
      `ActiveRecord::NotNullViolation`; no new `RailsDeprecation`. A slice 4 finding blocks 5a (§4.5's
      SH rule).
- [ ] **Slice 4's S13** recorded (runbook 4 step 7).
- [ ] **`import_listings` check-in history** (Honeybadger → Check-Ins): hourly arrivals since v671.
      Record the last three arrival times; each is expected at about :35–:45 UTC.
- [ ] Review rounds complete (two rounds of `predeploy-review-rails`, Codex included); this runbook's
      Status is `Ready`.
- [ ] Dan has merged `chore/rails-upgrade-slice-5a` into `master`, and `bundle exec rspec` is green
      **on the merge**: expected `2103 examples, 0 failures` and 0 `DEPRECATION WARNING` lines if
      `master` is still `316fa0e1`. A different count is sourced before the push, not recomputed.
- [ ] The production-config probe (step 2) printed the expected lines on the merge.
- [ ] Pre-push captures (step 3) recorded, on the release that is live at that moment.

## Pre-deploy

### 1. Development verification — done 2026-11-09

On the branch at `3ca24647`, in the dev container with Ruby 3.4.12 and Rails 8.1.4.1. **The
development database is a production restore newer than the plan's**: its data runs to about
2026-11-09 12:31 UTC (the latest `mls_imports` row is 11:35:07 UTC; `mls_listings` were updated to
12:31:37 UTC), and it was loaded after Postgres started at 10:55 UTC that day. The dump is not
`tmp/latest-2026-10-30.dump`, the one the plan's facts 6 and 13 were counted on. No importer runs in
the container: there is no cron, and the `bin/dev` processes started at 13:03 UTC, after the last
import row.

| # | Result |
| :-- | :-- |
| P1 | `2103 examples, 0 failures` (63.8 s); `CI=1`: `2103 examples, 0 failures` (63.7 s); `0` `DEPRECATION WARNING` lines in each; the 24 rspec-rails `:unprocessable_entity` warnings unchanged. Baseline on `master` `316fa0e1`: 2,100 (runbook 4), so +3 — contract 16 → 18 (one example became three) and the login spec 1. The plan's ESTIMATE of 2,102 counted from `3f67af13` (2,099); the extra one is `spec/requests/forwarded_header_spec.rb` (`77fcef70`, on `master` since 2026-11-06), sourced from a `--dry-run --format json` grouped by file |
| P2 | `zeitwerk:check` → "all is good" (the `lib/` notice as on `master`) |
| P3 | `slice5a_p3` queue: `Booted Rails 8.1.4.1 application in development environment`, `start`, `[PropertyDataLookupWorker] Property#1964 already has property data, skipping`, `done` (`elapsed=0.24`); `Sidekiq::Status::status(jid)` → `nil` (§8 item 10) |
| P4 | `4 examples, 0 failures` |
| P5 | `86 examples, 0 failures` |
| P6 | `ActionMailer::MessageDelivery`; `SystemError::rails upgrade` |
| P7 | `122 examples, 0 failures` |
| P8 | photo 663241 → `d2e08hhdrjhri.cloudfront.net`, `200`, `image/jpeg` (`Net::HTTP`) |
| Named specs | `spec/lib/tasks/scheduler_rake_spec.rb` (the check-in the watch rests on), `spec/lib/crmls_login_timeout_spec.rb`, `spec/requests/order_types_update_spec.rb`: `17 examples, 0 failures` |
| Routes | `bin/rails routes` byte-identical with the 8.0 shim as on `master` (583 lines); `active_storage` `0` |
| Lint | `ruby -c` on the three touched files; `rails_best_practices -e "db/migrate,vendor" .` 326 warnings (slice 4's baseline). No `.rubocop.yml`, so `bin/rubocop` cannot run |
| Fact 16 re-run | On `3ca24647`: `strict_freshness config=true applied=false`, `Regexp.timeout=1.0`, every 8.1 flag at its 7.2 value, `yjit config=true enabled=true`. With the six 8.1 lines also uncommented (restored afterwards; `git status` clean): the plan's fact 16 output line for line — `strict_freshness` config `true` / applied `false`, `escape_js_separators` config `false` / applied `true`, the other six applied |
| P-PROD | step 2 |
| P-5a | below |

**P-5a — the CRMLS load path replayed under the timeout** (plan, Decisions 3). A scratchpad runner,
not committed. It asserts `Regexp.timeout == 1.0` first, then fakes Sidekiq, blocks the network with
WebMock, sets mail to `:test` and stubs the geocoder as `spec/support/geocoder.rb` does. Inside one
transaction that it rolls back, it sends every `Listing.find_active_imports_for(Crmls::MLS_ID)` row
through `Crmls.load_listing`, each in its own savepoint with `mls_signature` cleared in memory. It
counts `Regexp::TimeoutError` and every other error. RESULTS (2026-11-09 15:47 UTC, `3ca24647`):

```
Regexp.timeout=1.0
listings=655 replayed=655 paths={payload: 646, no_payload: 9}
timeouts=0
other_errors=0
emails=0 subjects={}
sidekiq_jobs=0 {}
elapsed=17.2 s
rolled_back=true before={mls_listings: 8379, mls_listings_updated: "2026-11-09T12:31:37.537987Z", listings_synced: "2026-11-09T11:35:40.484367Z", properties_updated: "2026-11-09T04:55:44.705478Z"}
```

**0 timeouts and 0 other errors**, as expected. The listing count differs from the plan: 655 (646
with a stored payload, 9 without) where the plan expected 659 (650 + 9). That 659 was counted on the
2026-10-30 restore. 655 is this restore's active set, and it equals `total_listings` on production's
last import before the restore (11:35:07 UTC, `655`). The difference is three weeks' listings, not the
code. The write-back fingerprint is identical before and after, so nothing was written. The plan's
ESTIMATE was under five minutes; the run took 17.2 s. What P-5a does not cover is the `rets` gem's
parsing of a live login and search response. This deploy's watched import is the only probe of that.

**The import's production profile, re-sourced.** The newer restore holds production's
`mls_imports` from 2026-10-30 17:35 to 2026-11-09 11:35 UTC: 234 hourly runs and 7 single-listing
syncs. In those runs, `total_listings` was 654–659 (median 656) and `duration` 272–417 s (p5 282,
median 328, p95 391). Runs finished at :34–:37 past the hour, and there was one missing hour: 10-31
21:35 → 23:36 UTC, a gap of 2.02 h. S9b's bands below come from these runs. The plan's 650–700 and
300–450 s came from runbook 0's 40 rows, and its 300 s floor would have flagged a normal run: the
restore's last run took 288 s. The missing hour is the kind of cycle S9b exists to catch. Before
this slice it would have been a login failure, emailed to ops@ (plan fact 7), or a Scheduler skip.
Its cause is UNVERIFIED and is not this slice's to chase.

### 2. The production-config probe (on the merge, before the push)

`deploy-rails-upgrade-3.md` step 2's wrapper with eight lines appended after `p
ActionController::Base.escape_json_responses` (plan, Post-deploy verification). The last line reads the
`ActiveRecord` module: `ActiveRecord::Base` has no such reader and raises `NoMethodError` (plan review
P2). Record the exit status with the output.

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
the gem's `Reporting error` line; `true`; `false` (no `to_time` key); `7.2`; `583`; `false` (reporting
off); `true` (`escape_json_responses`, 5b's); then the new eight — **`1.0`** (the timeout), **`true`**
(the freshness config), **`false`** (the applied freshness — fact 16), `true` (`yjit`), `true`
(`escape_js_separators_in_json`), `false` (the finder flag), `:log` (the redirect flag), `false`
(`belongs_to_required_validates_foreign_key`, a 7.1 default no slice moves); and a `DEPRECATION`
count of `0`.

RESULTS (2026-11-09 15:45:14 UTC, branch `3ca24647`, dev container — the merge with `master`
`316fa0e1` carries the same tree). Every line as expected:

```
exit 0
W, [2026-11-09T15:45:16.449902 #59172]  WARN -- : Generating image variants require the image_processing gem. Please add `gem "image_processing", "~> 1.2"` to your Gemfile or set `config.active_storage.variant_processor = :disabled`.
"8.1.4.1"
true
true
[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]
I, [2026-11-09T15:45:16.499348 #59172]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=590a0b03-9a28-473a-bf87-782008d49a5a level=1 pid=59172
true
false
7.2
583
false
true
1.0
true
false
true
true
false
:log
false
--- DEPRECATION lines: 0
```

RESULTS (on the merge, before the push): ___

### 3. Pre-push captures (on the host, on the release that is live)

```bash
heroku releases -n 3 --app insgtapi
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; p Rails.application.config.loaded_config_version; p Regexp.timeout; p ActionDispatch::Http::Cache::Request.strict_freshness'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'r = MlsImport.order(:created_at).last; p r.slice("created_at", "total_listings", "total_updated", "duration"); p r.created_at - r.duration'
heroku logs -n 1500 --app insgtapi > tmp/s16-before.log
grep -c "Regexp::TimeoutError" tmp/s16-before.log
head -1 tmp/s16-before.log | cut -c1-32
tail -1 tmp/s16-before.log | cut -c1-32
RELEASE=v671   # or the newer one `heroku releases -n 3` printed, if master moved
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 5a', 'release $RELEASE').deliver_now"
```

Then three reads in the web UIs:

- **Papertrail**, `Regexp::TimeoutError` over the last seven days.
- **Honeybadger**, `environment:"production" class:"Regexp::TimeoutError"`, with `-is:resolved` and
  then `is:resolved`, both with `-is:ignored`.
- **The ops@ inbox:** the most recent `SystemError::` email from the import (`Crmls Login Failure`, or
  any `Import Error::…`), with its date. This is the baseline for S16's inbox read.

Expected before:

- The release runner: `8.1.4.1`, `7.2`, `nil`, `false` (the WARN line first).
- S4: `["Carlsbad", "Oceanside", "Leucadia"]`.
- The import row: the last hour's run, finished at :34–:37 UTC, `total_listings` 654–659,
  `duration` 270–420 s, its start (the second line) at about :30. This is S9b's "before".
- `Regexp::TimeoutError` `0` in the buffer, `0` in Papertrail and No Results in Honeybadger: no timeout
  is set yet, so any hit is a different bug, recorded here before the push.
- The buffer's span, and the inbox's last import email with its date (recorded, not criteria).
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

Set `RELEASE` first. Every `heroku run … rails runner` prints the Active Storage WARN line before its
own output (Known); it is not a failure.

```bash
RELEASE=vNNN   # the release `heroku releases -n 1` printed
heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
heroku run --no-tty --exit-code --app insgtapi rails runner "puts Honeybadger.notify('rails upgrade slice 5a marker', error_class: 'UpgradeMarker', fingerprint: 'rails-upgrade-marker', tags: 'upgrade', context: { rails: Rails.version, release: '$RELEASE' }, sync: true).inspect"
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; p Rails.application.config.active_support.key?(:to_time_preserves_timezone); p Rails.application.config.loaded_config_version; p Rails.application.config.yjit; p RubyVM::YJIT.enabled?'
heroku run --no-tty --app insgtapi rails runner 'puts Regexp.timeout.inspect; p ActionDispatch::Http::Cache::Request.strict_freshness'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 5a', 'release $RELEASE').deliver_now"
```

S3 replaces `deploy-rails-upgrade-3.md` step 5's runner with the plan's five lines (Approval B): the
version, the `to_time` key, `loaded_config_version`, and YJIT's config and runtime state. No command
here calls the 8.1-deprecated time-zone reader.

Expected, reasoned before the push:

| # | Check | Expected |
| :-- | :-- | :-- |
| S2 | `heroku ps`, `grep Booted` | all dynos up; `Booted Rails 8.1.4.1 application in production environment`. A boot failure is a rollback |
| S1 | `/up` | `200`; the Honeybadger uptime check green |
| S0 | marker | a notice id; `UpgradeMarker` gains an occurrence with context `rails: 8.1.4.1` and the real release |
| S3 | the five-line runner | `8.1.4.1`, `false`, `7.2`, `true`, `true` (YJIT is already on under 7.2's `self.yjit = true`; neither 5a nor 5b changes it in production — a `false` is a finding) |
| **S14** | the timeout and the applied freshness | **`1.0`**, **`false`** (fact 16: the applied value waits for 5b). `nil` is the rollback signal — the shim line did not take effect |
| S4 | nearby cities | identical to step 3's capture |
| S5 | Stripe | `true` |
| S6 | email | `SystemError::rails upgrade slice 5a` arrives at ops@insightphotos.net |

Then Honeybadger over the 30 minutes: Errors with `-is:resolved -is:ignored` lists the marker and
nothing new. A `Regexp::TimeoutError` here, from a web request or a job, is read at once (Rollback).

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

Then Papertrail: `status=5` and `Regexp::TimeoutError` from the push to one hour after it (the buffer
spans less than the hour at business-hours traffic). Expected: no `status=5` in the hour; no exception
class other than `ActionController::RoutingError` (scanner traffic); `0` `Regexp::TimeoutError`.

**The watched import** is the first `import_listings` run that **starts** after the release time
(Deploy window). Read all four once it has finished, at about :35–:45 UTC:

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
| **S9b** | the `MlsImport` runner | **a new row for the watched hour**: its start (second line) after the release time, `created_at` at about :34–:37; `total_listings` 654–659; `duration` 270–420 s (the restore's 234 production runs, step 1 — the plan's 650–700 and 300–450 s were from 40 rows). **No new row while S9 passed is the login-swallow path** (Summary): read the ops@ email at once |
| **S16** | the buffer grep; Papertrail `Regexp::TimeoutError` since the push; the ops@ inbox | `0`; `0`; **no `SystemError::` email from the import since the push** (step 3's baseline is the last one before it) |
| (S7 again) | if the watched run finished more than an hour after the push | the buffer read once more over the run's window, `status=5` `0` |

**5b's prerequisite is all four passing on the watched run** (plan, Gaps pinned 1). Pass on S9 alone,
or on S9 and SH, is not a pass: the login path passes both. If the watched run's row is missing, or
a `Crmls Login Failure` email arrives, read the email body. `Failed to login: regexp match timeout`
is this slice's finding (Rollback). Any other cause is an ordinary login failure: record it, and the
next hour's run becomes the watched one.

RECORDED: ___

### 7. 24 hours after the push (SH)

Honeybadger → Errors, compared with the slice 0 baseline **by error** (replace the time with the push),
each search with `-is:resolved` and then `is:resolved`, both with `-is:ignored`:

```
environment:"production" created.after:"<push>"
environment:"production" class:"Regexp::TimeoutError" occurred.after:"<push>"
environment:"production" class:"RailsDeprecation" occurred.after:"<push>"
```

**Pass condition:**
- **No `Regexp::TimeoutError` at all.**
- No new error whose backtrace touches `config/initializers/new_framework_defaults_8_0.rb`,
  `lib/crmls.rb`, `lib/sandicor.rb`, `app/models/listing.rb`, `app/models/crmls_transform.rb`, the
  `rets` gem, or actionpack's `http/cache.rb`.
- No new `RailsDeprecation`.
- The ops@ inbox still holds no `SystemError::` email from the import since the push (S16 extended
  to 24 h).

Anything else is an old bug seen for the first time: record it here and fix it on its own branch; it
does not block 5b.

RECORDED: ___

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to v671 (slice 4), or to the release step 3 recorded if `master` moved. Nothing to undo: no
migration, no ENV change, no data written by the slice.

**A Scheduler one-off started under this release keeps its slug** — and `Regexp.timeout = 1` — until
it exits, up to about seven minutes (plan P8). Verify the rollback after it has gone: `heroku ps
--app insgtapi` lists no `scheduler.*` dyno, then S14 → `nil`, `false`.

**When to roll back:** a boot failure (S2); S14 `nil` (the line did not apply); any
`Regexp::TimeoutError` in production, from any path, including a `Crmls Login Failure` email whose
body names `regexp match timeout`. Then name the pattern from the backtrace (or, on the login path,
from the email's message). Choosing between a per-regexp `timeout:` on that call and keeping the
global off is a §7 decision, not an in-window fix (plan, Risks).

## Known, kept by decision

- **One Active Storage WARN line per process boot on 8.1.4** (slice 3's Known; §8 item 7). Not raised,
  not a deprecation, not reported.
- **`new_framework_defaults_8_0.rb:18`, the `to_time` line, stays a comment** (v6): on 8.1 any value
  deprecates. It leaves with the file in 5b.
- **`:25` reaches only the config** (plan fact 16; Approval 7): config `true`, applied `false` until
  5b's `load_defaults 8.1`. Nothing reads it (plan fact 10). The contract example pins both halves and
  says why. Upstream: rails/rails#59146, whose fix (PR #59147) is open.
- **A timeout during the CRMLS login is swallowed** (plan fact 7; Decisions 10). The new spec
  documents that behaviour and does not change it. The Honeybadger notice is 5b's commit 5 (Approval
  D). Until then, S9b and the ops@ inbox are the signal.
- **One-off dynos overlap a release** (plan P8): an import in flight at the push finishes on slice 4's
  slug, which is why the watched run is the first one that starts after the release.
- **The 24 rspec-rails `:unprocessable_entity` warnings** (rack 3.2 renamed the status), unchanged.
- **Review rounds:** ___

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed`, the release, and steps 3–7's results.
- **5b's prerequisite:** step 6's four-part read passing on the watched run, and SH the next morning.
  The S15 and S17 "before" captures are taken on this release (plan, "Production"; runbook 5b).
- `rails-upgrade.md` §4.6: 5a's "as deployed" line, and §6's calendar as it went. The v8 amendment
  itself is written before the push (plan, Open questions 5).

## Deploy log

- **2026-11-09 — implemented and verified in development** (branch `chore/rails-upgrade-slice-5a`,
  `3ca24647` off `master` `316fa0e1`, which is production's code as v671): step 1's table, fact 16
  re-run on the new base, P-5a (655 replayed, 0 timeouts), and P-PROD as step 2's RESULTS.
