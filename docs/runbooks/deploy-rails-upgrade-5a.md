# Runbook: Rails Upgrade Slice 5a — the 8.0 request-freshness and regexp-timeout defaults

**Last updated:** 2026-11-11
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~25 min of prerequisite reads and captures; ~30 min for the push and step 5's
checks; S7 one hour after the push; S9, S9b, S16 and the ops@ inbox at the first import that starts
after the release; SH 24 h later
**Status:** Deployed — v672, `808d383f`, 2026-11-10 09:48:26 -0500 (14:48:26 UTC). Step 5 passes; S7
and the watched 15:30 UTC import pass on all four signals (step 6). SH passes at about 25 h
(2026-11-11, step 7). Implemented and verified in development 2026-11-09 (step 1); two review rounds of
`predeploy-review-rails` done the same day (Known; record `docs/architecture/reviews/2026-11-09-slice-5a-insgt-api.md`),
with round 1's finding fixed by amending commit 1 and no finding open after round 2. The
verification gate passed (Dan, 2026-11-09), and the v8 write-back is done. Slice 4's SH and S13
and the check-in history pass (2026-11-10). Merged 2026-11-10; on the merge, now `808d383f`, the suite
and the probe pass. The release also carries `073ebe2f` (`/cable`, added after review) and the
Client-IP fix, both on Dan's decision (Summary). Step 3's captures are recorded (v671).

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.6 rows 2 and 3 (v7). `docs/plans/rails-upgrade-slice-5.md`
holds every decision and deviation. Branch `chore/rails-upgrade-slice-5a`, two commits off `master`
**`316fa0e1`** — slice 4 merged (v671) — not the plan's `3f67af13`. The second commit came after
review. Slice 4 merged and deployed
before 5a was cut, so Decisions 1's rebase never arose. Fact 16's boot check was re-run on the new
base and reproduced line for line (step 1).

1. `c966bb6e` (pre-review `3ca24647`) chore: enable the rails 8.0 request freshness and regexp timeout defaults —
   `config/initializers/new_framework_defaults_8_0.rb:25` and `:30` uncommented. `:18`, the `to_time`
   line, stays a comment (v6). The contract block `the 8.0 defaults are on; the 8.1 defaults stay off
   until slice 5b` replaces slice 3's one example with three. `spec/lib/crmls_login_timeout_spec.rb`
   (1) is new.
2. `073ebe2f` chore: remove action cable mount path — `config/environments/production.rb:36`
   uncommented, `config.action_cable.mount_path = nil` (`rails-upgrade.md` §8 item 33). Added
   2026-11-10 after both review rounds and not reviewed; it ships with 5a on Dan's decision
   (2026-11-10). There is no spec, because test and development do not load `production.rb`. The
   probe pins it (step 2).

**No migration, no DDL, no ENV change, no gem change, no client release.** `config.load_defaults`
stays `7.2`, and no 8.1 flag moves.

**The release also carries the Client-IP header fix** (`3d94d41d`, merged into `master` as
`ec68ccf1`), which was never deployed: on 2026-11-10 `git ls-remote heroku` still printed
`316fa0e1`, v671. It ships with 5a on Dan's decision (2026-11-10), so v671 stays the "before" and the
rollback target. It touches no file 5a touches, and the merge was rehearsed (step 2).

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
- **`/cable` is no longer mounted** (`073ebe2f`). A request to it now answers `404` with
  `ActionController::RoutingError`, as any unknown path does; before, Action Cable's server answered.
  No app connects to it (step 2). Production's route count goes from 583 to 582.
- **The `Client-IP` request header is dropped before `ActionDispatch::RemoteIp` reads it**
  (`3d94d41d`, `config/initializers/client_ip_header.rb`). Heroku's router sets no such header, so
  it was client input. A `Client-IP` missing from `X-Forwarded-For` raised `IpSpoofAttackError`,
  answering `500` at `TransactionsController#transaction_params`; that request is now served.

**What moves for a human: nothing.** No success response changes, and no visible value moves. Two
error paths change: `/cable` answers `404`, and a request with a forged `Client-IP` is served instead
of answering `500`. `bin/rails routes` is unchanged (583 lines, development).

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

- [x] **Slice 4's SH passes** (`deploy-rails-upgrade-4.md` step 7, at about 24 h): no new error
      since v671; no `RecordInvalid` with `must exist` from a `save!` path; no
      `ActiveRecord::NotNullViolation`; no new `RailsDeprecation`. A slice 4 finding blocks 5a (§4.5's
      SH rule). **Passes** (Dan, 2026-11-10): all four searches return No Results, resolved and
      unresolved, from 2026-11-09 08:30 -0500.
- [x] **Slice 4's S13** recorded (runbook 4 step 7). **Passes** (Dan, 2026-11-10 14:09 UTC): D29,
      D39 and D50 are unchanged at `2`, `27` and `32`; the only diff line is D52's type-7 count
      (+439, live tagging).
- [x] **`import_listings` check-in history** (Honeybadger → Check-Ins): hourly arrivals since v671.
      Record the last three arrival times; each is expected at about :35–:45 UTC. **Passes** (Dan,
      2026-11-10, read at about 14:20 UTC): the last three arrived at 13:37, 12:37 and 11:35 UTC,
      each inside the slot. "Most Recent 25 Checks" runs hourly from 11-09 13:36 UTC (S9's arrival,
      the first after v671) to 11-10 13:37 UTC: 25 arrivals with no gap, all `reporting`, each at
      :35–:38 past the hour.
- [x] Review rounds complete (two rounds of `predeploy-review-rails`, Codex included; 2026-11-09,
      Known)
- [x] This runbook's Status is `Ready` (2026-11-09, after the v8 write-back)
- [x] Dan has merged `chore/rails-upgrade-slice-5a` into `master`, and `bundle exec rspec` is green
      **on the merge**. **`master` moved on 2026-11-09** to `ec68ccf1` (`Merge branch
      'fix/ip-spoof-attack'`, 16:32 UTC, local and not pushed then), whose one commit `3d94d41d` adds
      `config/initializers/client_ip_header.rb` and one example in `spec/requests/forwarded_header_spec.rb`.
      Expected on the merge with `master` at `ec68ccf1`: `2104 examples, 0 failures`, 0
      `DEPRECATION WARNING` lines. That was sourced 2026-11-09 by Claude on a scratch merge in a
      detached worktree (`a12699c8`, not kept): plain `2104 examples, 1 failure` — the known
      one-second flake `calculator_spec.rb:965` (expected `16:42:42`, got `16:42:41`), green alone —
      then `2104 examples, 0 failures` on the rerun; `CI=1` `2104 examples, 0 failures`; the 24 rack
      warnings. If `master` is still `316fa0e1`, the expected count is `2103`. Any other count is
      sourced before the push, not recomputed. **Merged** 2026-11-10 as `808d383f` (`--no-ff`, on
      `master` `ec68ccf1`; local, with `origin/master` and `heroku/master` still at `316fa0e1`). The
      branch had gained a second commit since review: `073ebe2f` (2026-11-10 09:20 -0500), `chore:
      remove action cable mount path`. It changes `production.rb:36` and adds no spec (step 2). On
      the merge (Claude, 14:24–14:25 UTC, 67.6 s): `2104 examples, 0 failures`, 0 `DEPRECATION
      WARNING` lines, the 24 rack warnings unchanged. **Reworded before any push** (Dan, 2026-11-10):
      the Client-IP commit's subject read `fix: render a listing with no mls number`, which is not
      what it does. It was rebuilt as `3d94d41d` (`fix: drop the client-supplied client-ip header`)
      with the same tree, parent, author and dates, and the two merges above it were rebuilt the
      same way. The old hashes are `cd1e3737`, `3b35d11b` and `e6fbe0c6`. The suite and the probe
      ran on `e6fbe0c6`, whose tree `808d383f` carries byte for byte.
- [x] **Which release carries the Client-IP fix.** If `ec68ccf1` is pushed on its own before 5a, its
      release is 5a's "before" and rollback target, and 5a's release carries only 5a. If it ships
      with 5a, the release carries both, and an `IpSpoofAttackError` or `remote_ip` error in SH is
      triaged against `client_ip_header.rb` first. Recommended: push it on its own. **Decided (Dan,
      2026-11-10): it ships with 5a.** It was never deployed: `git ls-remote heroku refs/heads/master`
      → `316fa0e1` (v671). v671 stays the "before" and the rollback target (SH, Rollback).
- [x] The production-config probe (step 2) printed the expected lines on the merge: every line, with
      the route count `582` for `073ebe2f`.
- [x] Pre-push captures (step 3) recorded, on the release that is live at that moment (v671,
      2026-11-10 14:36–14:38 UTC; the S6 email arrived; the inbox baseline is 2021-08-31).

## Pre-deploy

### 1. Development verification — done 2026-11-09

On the branch at `3ca24647`, the same application tree as `c966bb6e`: review round 1's amend changed
only `spec/lib/crmls_login_timeout_spec.rb`, and P1 was re-run on `c966bb6e` in a clean worktree (the
P1 row). The dev container ran Ruby 3.4.12 and Rails 8.1.4.1. **The
development database is a production restore newer than the plan's**: its data runs to about
2026-11-09 12:31 UTC (the latest `mls_imports` row is 11:35:07 UTC; `mls_listings` were updated to
12:31:37 UTC), and it was loaded after Postgres started at 10:55 UTC that day. The dump is not
`tmp/latest-2026-10-30.dump`, the one the plan's facts 6 and 13 were counted on. No importer runs in
the container: there is no cron, and the `bin/dev` processes started at 13:03 UTC, after the last
import row.

| # | Result |
| :-- | :-- |
| P1 | `2103 examples, 0 failures` (63.8 s); `CI=1`: `2103 examples, 0 failures` (63.7 s); `0` `DEPRECATION WARNING` lines in each; the 24 rspec-rails `:unprocessable_entity` warnings unchanged. Baseline on `master` `316fa0e1`: 2,100 (runbook 4), so +3 — contract 16 → 18 (one example became three) and the login spec 1. The plan's ESTIMATE of 2,102 counted from `3f67af13` (2,099); the extra one is `spec/requests/forwarded_header_spec.rb` (`77fcef70`, on `master` since 2026-11-06), sourced from a `--dry-run --format json` grouped by file. On `c966bb6e`, in a clean worktree at that commit with `.env` copied in and removed afterwards, and with `tmp/` created (without it, 33 report-writing examples fail with `Errno::ENOENT` — a worktree artifact): `2103 examples, 0 failures` plain (54.0 s) and `CI=1` (55.3 s), the same deprecation and warning counts |
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
the gem's `Reporting error` line; `true`; `false` (no `to_time` key); `7.2`; `582` (corrected
2026-11-10, after the run: `583` until `073ebe2f` unmounted `/cable`); `false` (reporting
off); `true` (`escape_json_responses`, 5b's); then the new eight — **`1.0`** (the timeout), **`true`**
(the freshness config), **`false`** (the applied freshness — fact 16), `true` (`yjit`), `true`
(`escape_js_separators_in_json`), `false` (the finder flag), `:log` (the redirect flag), `false`
(`belongs_to_required_validates_foreign_key`, a 7.1 default no slice moves); and a `DEPRECATION`
count of `0`.

RESULTS (2026-11-09 15:45:14 UTC, branch `3ca24647`, dev container — the same application tree as
`c966bb6e`, and as its merge into `master` `316fa0e1`). Every line as expected:

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

REHEARSED (2026-11-09 16:45:06 UTC, by Claude, on a scratch merge of the branch into `master`
`3b35d11b` (now `ec68ccf1`, the same tree) in a detached worktree, `a12699c8`, not kept — the tree Dan's merge produces while `master`
stays there): `exit 0`; one WARN line; `"8.1.4.1"`, `true`, `true`, the three `[:notify]` pairs, one
`Reporting error` line, `true`, `false`, `7.2`, `583`, `false`, `true`, `1.0`, `true`, `false`, `true`,
`true`, `false`, `:log`, `false`; `DEPRECATION` `0`. Every line as expected; `client_ip_header.rb`
changes none of them.

RESULTS (on the merge, before the push): 2026-11-10 14:24:17 UTC, by Claude in the dev container,
on the merge `e6fbe0c6` (now `808d383f`, the same tree). `exit 0`; one WARN line; `"8.1.4.1"`, `true`,
`true`, the three `[:notify]` pairs, one `Reporting error` line, `true`, `false`, `7.2`, **`582`**,
`false`, `true`, `1.0`, `true`, `false`, `true`, `true`, `false`, `:log`, `false`; `DEPRECATION` `0`.
Every line matched what the runbook expected then, except the route count: **`582`, not `583`**. That
is `073ebe2f`, and Dan shipping it with 5a made `582` the expected value. With `config.action_cable.mount_path =
nil`, Action Cable's engine skips its prepended `/cable` mount (`actioncable-8.1.4.1
lib/action_cable/engine.rb:65–67`). Yesterday's rehearsal of the same merge without that commit
printed `583`. `bin/rails routes` in development is unaffected, because `production.rb` is not
loaded there. No app in the platform is an Action Cable client: there is no `app/channels`, and no
`cable` or `wss://` reference in insgt-app, insgt-ops, insgt-photographers, insgt-disclosure-gallery
or insgt-api's `app/` and `lib/`.

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

RECORDED (before) — Dan, on the host, 2026-11-10 14:36–14:38 UTC (06:36–06:38 PST), on **v671**
(`Deploy 316fa0e1`, 2026/11/09 08:27:45 -0500, current, with v670 and v669 below it), so
`RELEASE=v671`. Each runner printed the Active Storage WARN line first (Known):

- **The release runner:** `8.1.4.1`, `7.2`, `nil`, `false` — as expected.
- **S4:** `["Carlsbad", "Oceanside", "Leucadia"]` — as expected.
- **The import row (S9b's "before"):** `created_at` 14:35:12 UTC, `total_listings` 655,
  `total_updated` 0, `duration` 300 s, start 14:30:12 UTC. That is the 14:30 run, and every value is
  in range.
- **The buffer:** `Regexp::TimeoutError` `0` in 1,500 lines spanning
  `2026-11-10T13:37:18.786898+00:00` … `2026-11-10T14:37:31.341581+00:00` (about 1 h).
- **Papertrail:** `Regexp::TimeoutError` — "No matching events", searched back to Oct 29 at 07:00 PM,
  more than the seven days.
- **Honeybadger:** `environment:"production" class:"Regexp::TimeoutError"` — No Results with
  `-is:resolved` and with `is:resolved`, both with `-is:ignored`, with no time bound.
- **S6:** the runner printed nothing after the WARN line. `SystemError::rails upgrade slice 5a`
  arrived at ops@insightphotos.net at 14:38:12 UTC (`Date:` 14:38:11 UTC), from team@insightphotos.net
  through SendGrid, body `release v671` — as expected.
- **The ops@ inbox baseline** (the last `SystemError::` email from the import, with its date):
  `SystemError::Crmls Login Failure`, `Date:` 2021-08-31 11:41:22 UTC, body `Failed to login:
  execution expired` (Dan, 2026-11-10). No import email in more than five years, so any after the
  push is S16's finding. It also means no login was swallowed on 10-31 (`rails-upgrade.md` §8 item 32).

## Deploy

### 4. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

No gem change, so the build installs nothing new. A failed build is not a release; the live one stays.

RECORDED: **v672**, `git push heroku master` of `808d383f` (Dan, 2026-11-10). `heroku releases -n 1`:
`v672   Deploy 808d383f   ops@insightphotos.net   2026/11/10 09:48:26 -0500` (14:48:26 UTC, 06:48
PST). The dynos restarted 14:48:31–14:48:36 UTC. That is before the 09:00 PT window, as slices 2–4
were, and outside the 08:00 and 12:00 delivery windows. The 14:30 UTC import finished at 14:35:12,
before the release, so **the watched import is the 15:30 UTC run**, the first that starts after it.

### 5. Within 30 minutes

Set `RELEASE` first. Every `heroku run … rails runner` prints the Active Storage WARN line before its
own output (Known); it is not a failure.

```bash
RELEASE=v672   # the release `heroku releases -n 1` printed
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

RECORDED — Dan, on the host, 2026-11-10 14:49–14:52 UTC, `RELEASE=v672`. Every runner printed the
Active Storage WARN line first (Known):

- **S2:** `backgroundworker.1` up 14:48:31 UTC, `web.1` and `web.2` 14:48:36; `Booted Rails 8.1.4.1
  application in production environment` from `backgroundworker.1` at 14:48:35 UTC, one boot.
  **Pass.**
- **S1:** `/up` → `200`. The Honeybadger uptime check reads "Insight API Production is up"
  (`https://api.insightphotos.net/up`, last checked 3 min before the read). **Pass.**
- **S0:** notice `48b83052-5707-47af-92a5-398cb4b9d017` (`code=201`, 14:50:27 UTC). `UpgradeMarker`
  (fault 135218267) gains the occurrence at 09:50 -05:00 with context `{"rails" => "8.1.4.1",
  "release" => "v672"}`. **Pass.**
- **S3:** `8.1.4.1`, `false`, `7.2`, `true`, `true` (14:50:46 UTC). **Pass.**
- **S14:** `1.0`, `false` (14:50:59 UTC). The timeout is on, and the applied freshness waits for 5b.
  **Pass; no rollback signal.**
- **S4:** `["Carlsbad", "Oceanside", "Leucadia"]`, identical to step 3's. **Pass.**
- **S5:** `true`. **Pass.**
- **S6:** the runner printed nothing after the WARN line (14:51:46 UTC).
  `SystemError::rails upgrade slice 5a` arrived at ops@insightphotos.net at 14:51:49 UTC (`Date:`
  14:51:46 UTC), from team@insightphotos.net through SendGrid, body `release v672`. **Pass.**
- **Honeybadger, the 30 minutes** (Dan, read at about 15:41 UTC, so the hour covers the 30 minutes
  and more): Errors with `-is:resolved -is:ignored` lists one fault, `UpgradeMarker` (count 6), and
  "1 error notification received in the past hour", the marker. No `Regexp::TimeoutError`, nothing
  new. **Pass.**

**Step 5 passes, every check.**

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
class other than `ActionController::RoutingError` (scanner traffic, which now includes any request to
`/cable`); `0` `Regexp::TimeoutError`.

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

RECORDED — Dan, on the host, 2026-11-10 15:39–15:41 UTC. The watched run is the 15:30 UTC import:

- **S9b** (15:40:36 UTC): a new row, `created_at` 15:35:25 UTC, `total_listings` 655, `total_updated`
  0, `duration` 308 s, start 15:30:17 UTC, 42 minutes after the release. Every value is in range and
  beside step 3's 655 / 300 s. The CRMLS login and the extraction ran under `Regexp.timeout = 1.0`
  without a timeout, because a swallowed login writes no row. **Pass.**
- **S9** (Honeybadger → Check-Ins, read at about 15:41 UTC): `import_listings` "is reporting", last
  seen "5 minutes ago", about 15:36 UTC, just after the row, inside the :35–:45 slot. Next expected
  "1 hour from now". **Pass.**
- **S16, the buffer:** `Regexp::TimeoutError` `0` in 1,500 lines spanning
  `2026-11-10T14:48:32.216143+00:00` … `2026-11-10T15:40:39.564781+00:00`, which covers the release
  and the whole run. **Pass.** Papertrail `Regexp::TimeoutError` since the push: "No matching
  events", searched back to Oct 29 at 07:00 PM (read at the hour's end, below). **Pass.** **The ops@
  inbox:** no `SystemError::` email since 14:48 UTC (Dan, read at about 15:45 UTC, ten minutes after
  the watched run finished). **Pass.** A Papertrail search for `SystemError::` also finds nothing
  back to Oct 29. That is not evidence about the emails: the two S6 emails (14:38 and 14:51 UTC) do
  not match it either, so the mailer does not log subjects.
- **S7, the buffer** (read 15:39 UTC, 51 minutes after the push): it spans
  `2026-11-10T14:48:28.272849+00:00` … `2026-11-10T15:39:35.973784+00:00`, from 2 s after the release.
  `status=5` `0`; no exception class at all; `Regexp::TimeoutError` `0`. The buffer ends 9 minutes
  short of the hour (15:48:26 UTC), so Papertrail carries the rest: `status=5` and
  `Regexp::TimeoutError` from the push to 15:48:26 UTC. **Papertrail** (Dan, screenshots pasted
  15:48:34 UTC, at the hour's end): `status=5`, scrolled to the end, has as its newest match `Nov 02
  11:54:42 AM`. That is the same H12 request timeout on `web.1` that runbook 4 recorded, a week
  before, so there has been no 5xx since the push. `Regexp::TimeoutError`: "No matching events",
  searched back to Oct 29. **Pass.**
- **(S7 again)** is not needed: the watched run finished at 15:35:25, inside the hour.

**Step 6 passes: S7, and all four on the watched run (S9, S9b, S16, the inbox).** That meets 5b's
prerequisite from this runbook; SH (step 7) remains, at about 24 h.

### 7. 24 hours after the push (SH)

Honeybadger → Errors, compared with the slice 0 baseline **by error** (replace the time with the push),
each search with `-is:resolved` and then `is:resolved`, both with `-is:ignored`:

```
environment:"production" created.after:"2026-11-10 08:00 UTC-5"
environment:"production" class:"Regexp::TimeoutError" occurred.after:"2026-11-10 08:00 UTC-5"
environment:"production" class:"RailsDeprecation" occurred.after:"2026-11-10 08:00 UTC-5"
```

**Pass condition:**
- **No `Regexp::TimeoutError` at all.**
- No new error whose backtrace touches `config/initializers/new_framework_defaults_8_0.rb`,
  `lib/crmls.rb`, `lib/sandicor.rb`, `app/models/listing.rb`, `app/models/crmls_transform.rb`, the
  `rets` gem, or actionpack's `http/cache.rb`.
- No new `RailsDeprecation`.
- The ops@ inbox still holds no `SystemError::` email from the import since the push (S16 extended
  to 24 h).
- **An `ActionDispatch::RemoteIp::IpSpoofAttackError`, or any error whose backtrace touches
  `remote_ip`, is triaged against `config/initializers/client_ip_header.rb` first.** This release
  carries the Client-IP fix (Summary). Such an error is a finding against that fix, not against 5a's
  flags: record it and fix it on its own branch. It does not block 5b.

Anything else is an old bug seen for the first time: record it here and fix it on its own branch; it
does not block 5b.

RECORDED — Dan, 2026-11-11, read by 15:54 UTC, about 25 h after the push. 5b was not deployed, so
the whole window ran `808d383f`: v672, then from 16:41 UTC on 11-10 v673–v674, which only set two
config vars (Dan's canarytoken setup). **SH passes.**

- **SH** (Honeybadger → Errors). The window opens `"2026-11-10 08:00 UTC-5"` (13:00 UTC), 1 h 48 min
  before the push. All three searches return No Results, each run with `-is:resolved` and with
  `is:resolved`, both with `-is:ignored`: no fault created since before the push, no
  `Regexp::TimeoutError`, no `RailsDeprecation`. With no new fault there is no backtrace to triage
  and no `IpSpoofAttackError`. **Pass.**
- **The date filter is proven** (no earlier SH had a control). `class:"UpgradeMarker"` over the same
  window, `-is:resolved`, lists fault 135218267 (count 1, last seen 20 h before the read), step 5's
  S0 occurrence at 14:50:27 UTC: the window parses and opens before the push. A filter Honeybadger
  ignored would only widen a search, so it cannot produce a false No Results. The `created.after`
  search cannot carry its own control, because no fault was created in the window; the window
  without a class covers it, read at about 20.5 h (Dan, pasted with the 11:11 UTC runner below):
  `-is:resolved` lists only the marker and `is:resolved` returns No Results, so no fault of any
  class, old or new, had occurred in production by then.
- **At about 10:45 UTC (20 h)**, the same three searches plus 5b's two classes,
  `ActiveRecord::MissingRequiredOrderError` and `ActionController::Redirecting::UnsafeRedirectError`,
  all returned No Results both ways: the baseline for 5b's SH.
- **A manual import** (Dan, `import_listings` by hand; runner at 11:11:16 UTC): a new row, start
  10:54:11 UTC, `created_at` 10:58:48, `total_listings` 652, `total_updated` 0, `duration` 277 s. A
  row means the CRMLS login succeeded and `extract` returned without raising. 652 is under step 6's
  654–659 and is not a finding: `total_listings` is Insight's own active-import count
  (`lib/crmls.rb:315–316`), taken before the MLS is asked, so three listings left that set after
  the watched run's 655.
- **The ops@ inbox** (Dan, about 15:59 UTC, 25 h): no `SystemError::` email of any kind since the
  push, so no `Crmls Login Failure` and no per-listing import error. **Pass.**

**SH passes. 5b's prerequisite from this runbook is met.**

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to v671 (slice 4), or to the release step 3 recorded if `master` moved. Nothing to undo: no
migration, no ENV change, no data written by the slice. A rollback also removes the Client-IP fix and
mounts `/cable` again, since both were first live in this release.

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
- **`073ebe2f` was not reviewed.** It was added 2026-11-10, after both rounds, and ships with 5a on
  Dan's decision. It is one config line, checked by the probe (`582`) and against Action Cable's
  source (step 2).
- **The release carries three changes, not one:** 5a's flags, `073ebe2f` and the Client-IP fix (Dan,
  2026-11-10). None touches the others' files. SH triages each error against the change its
  backtrace names.
- **Review rounds** (2026-11-09, `predeploy-review-rails`; Codex `gpt-6-astra` at effort `max` — the
  regexp timeout is production configuration with a process-wide blast radius — in detached git
  worktrees at the reviewed commit, so no `.env` or `config/master.key`; both left their worktree and
  the real tree untouched). Round 1, at `3ca24647`: Codex found that the login spec's
  `and_call_original` rendered the real mail, so the example needed `ZONE_EMAIL_SENDER` from `.env`.
  Claude found it read `ActionMailer::Base.deliveries.last` from an array the suite never clears.
  Both were confirmed, and Codex's should-fix was regraded to a nit: no spec runs without `.env` (the
  test database's credentials come from it too), and 16 existing examples need the same sender. Both
  were fixed by returning to the plan's delivery double (Decisions 10), amending commit 1 to
  `c966bb6e`. Round 2: "The round 1 fix is sufficient … No actionable findings survived the full-diff
  review." Neither model found a production input that takes a regexp past one second. The watched
  import is the probe for that (step 6).

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed`, the release, and steps 3–7's results.
- **5b's prerequisite:** step 6's four-part read passing on the watched run, and SH the next morning.
  The S15 and S17 "before" captures are taken on this release (plan, "Production"; runbook 5b).
- `rails-upgrade.md` §4.6: 5a's "as deployed" line, and §6's calendar as it went. The v8 amendment
  itself was written before the push (2026-11-09; plan, Open questions 5). 5b's items go into v9
  before 5b's push (Dan, 2026-11-09).
- The as-deployed line, and the plan's 5a implementation record, name what else the release
  carried: `073ebe2f` and the Client-IP fix. `rails-upgrade.md` §8 item 33 closes.

## Deploy log

- **2026-11-09 — implemented and verified in development** (branch `chore/rails-upgrade-slice-5a`,
  `3ca24647` off `master` `316fa0e1`, which is production's code as v671): step 1's table, fact 16
  re-run on the new base, P-5a (655 replayed, 0 timeouts), and P-PROD as step 2's RESULTS.
- **2026-11-09 — reviewed, two rounds** (Known): round 1's finding was fixed by amending commit 1 to
  `c966bb6e`, a spec-only change, and P1 was re-run there in a clean worktree, `2103 examples,
  0 failures` both ways. Round 2 found nothing.
- **2026-11-09 — verification gate passed; written back** (Dan's approval): `rails-upgrade.md` v8,
  the codebase notes, and the review record `docs/architecture/reviews/2026-11-09-slice-5a-insgt-api.md`.
  Status `Ready`.
- **2026-11-10 — prerequisite reads** (Dan): slice 4's SH and S13 pass; `import_listings` checked in
  25 times, hourly, from 11-09 13:36 to 11-10 13:37 UTC, with no gap.
- **2026-11-10 — merged; reworded; suite and probe on the merge.** Dan merged the branch, now with
  `073ebe2f`, into `master`. The Client-IP commit's subject was reworded before any push, giving
  `3d94d41d`, `ec68ccf1` and `808d383f` with the same trees (Prerequisites). On the merge (Claude):
  `2104 examples, 0 failures`; the probe as expected, with the route count `582` for `073ebe2f`.
  Dan's decisions: `073ebe2f` and the Client-IP fix (never deployed: Heroku's `master` was
  `316fa0e1`) ship with 5a, and v671 stays the "before" and the rollback target.
- **2026-11-10 — step 3 on v671** (Dan, 14:36–14:38 UTC): every capture as expected. S9b's "before"
  is the 14:30 run (655, 300 s). No `Regexp::TimeoutError` anywhere; the S6 email arrived. The
  inbox's last import email is from 2021-08-31.
- **2026-11-10 — pushed as v672** (Dan): `Deploy 808d383f`, 09:48:26 -0500 (14:48:26 UTC, 06:48 PST);
  dynos up 14:48:31–14:48:36 UTC. Step 5 passes, every check: S2 (one boot), S1, S0 (`v672`), S3,
  **S14 (`1.0`, `false`)**, S4, S5, S6, and Honeybadger shows only the marker. Step 6 passes. The
  watched 15:30 UTC import wrote its row (655, 308 s) and checked in at about 15:36. There is no
  `Regexp::TimeoutError` in the buffer, Papertrail or Honeybadger, and no import email in ops@. S7
  has no 5xx since the push. SH is due 2026-11-11.
- **2026-11-11 — SH passes** (Dan, read by 15:54 UTC, about 25 h after the push, all on `808d383f`): no
  new fault, no `Regexp::TimeoutError` and no `RailsDeprecation`, under both resolved states; the
  `UpgradeMarker` search proves the date filter. A manual import at 10:54 UTC wrote its row (652,
  277 s). 5b's prerequisite from this runbook is met.
