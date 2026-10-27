# Runbook: Rails Upgrade Slice 1 — 7.2.4, the deprecation gate, routes off, deprecation reporting

**Last updated:** 2026-10-26
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~30 min on the morning; S7 one hour after the push; S9 at the first hourly
import; SH 24 h later
**Status:** Draft — reviewed (two rounds); waiting on the Prerequisites

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.2 (v3; v4 amends it after verification). Branch
`chore/rails-upgrade-slice-1`, eight commits on `master` 02dbb78a:

1. `5c9446da` build: upgrade rails to 7.2.4 — the 13 Rails gems 7.2.3 → 7.2.4, minitest 6.0.1 →
   5.27.0, and two `activesupport` constraint lines (`connection_pool < 3`, `minitest < 6`). Nothing
   else in the lock moves.
2. `a59df0b0` fix: stop forcing the pre-Ruby 2.4 to_time behavior — deletes
   `ActiveSupport.to_time_preserves_timezone = false`; creates `spec/architecture/rails_upgrade_spec.rb`.
3. `f5b30e12` test: raise on deprecations in the test environment.
4. `3a6b8e2e` chore: stop drawing the unused Active Storage routes — `draw_routes = false`; 592 → 583
   routes.
5. `e54247cb` feat: report production deprecations to honeybadger once per message — `:notify`, the
   `deprecation.*` subscriber (wired in `to_prepare`), `DeprecationReporter`.
6. `c5d47db7` fix: stop a failing deprecation reporter from failing the caller.
7. `20149490` feat: expose whether a deprecation was received, for the deploy probe.
8. `a5d9b001` fix: tell deprecations from different gems apart in honeybadger — the dedupe key and the
   fingerprint are the deprecator's gem name plus the message.

**No migration, no ENV change, no client release.** The reporter uses slice 0's Honeybadger key.

**Production is v661** (`d37ae0df`, 2026-10-26 16:42:03 -0400), an emergency fix on `master`:
`bb732fd7` fix: drop the second agent when its account has been deactivated, and `4b840dca` fix: render
the tour agent when the account's owner row is deleted. Before it, v660 (`02dbb78a`, 11:41:37) carried
`b51d97ba`. The branch is cut from `02dbb78a`, so `d37ae0df` is **not** in it. The two sides share no
file (v661 touches only `app/models/listing.rb` and `spec/requests/listing_virtual_agent_spec.rb`), and
`git merge-tree --write-tree master chore/rails-upgrade-slice-1` is clean. Merging the branch into
`master` runs v661's code under 7.2.4 and `:raise` for the first time, so the suite runs on the merge
before the push (Prerequisites). The push then adds the eight commits and the merge; v661's commits are
live already.

**What moves for a human.**
- `to_time` on a zoned value now keeps the receiver's offset (§5 R3). No `.to_time` in `app/` or
  `lib/`; the four boundary specs pass. Symptom if a gem path disagrees: an order on the wrong day in
  insgt-ops, with no exception. S4, S6 and S8 are the reads.
- The nine Active Storage routes are gone: `POST /rails/active_storage/direct_uploads` answers `404`
  (it reached the controller and answered `400` before). Nothing calls them (Pre-deploy, below).
- A malformed HTTP verb answers `405`, not `500` (7.2.4 changelog, Action Pack). S7's `status=5`
  count can only go down.
- Deprecations in production reach Honeybadger as `RailsDeprecation`, once per deprecator and call
  site per process.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. The
production-config probe (Pre-deploy, step 2) runs in `apps/insgt-api` on the branch, wherever Dan runs
it. The Honeybadger dashboard is the web UI.

## Deploy window

Mon–Wed, 09:00–11:30 Pacific, outside the 08:00 and 12:00 delivery windows (§2.4). Planned for
Wed 2026-10-28, 09:30 Pacific.

## Prerequisites

- [x] **The slice 0 baseline is written** into `deploy-rails-upgrade-0.md` (its step 5, due about
      2026-10-27 10:00 ET). SH below compares against it; without it SH has nothing to compare.
- [x] Dan has merged `chore/rails-upgrade-slice-1` into `master` (`d37ae0df`, v661) and
      `bundle exec rspec` is green **on the merge**: expected 2,040 examples (the branch's 2,034 plus
      the 6 that `d37ae0df` adds to `listing_virtual_agent_spec.rb`, 4 → 10), 0 failures,
      0 `DEPRECATION WARNING` lines. A different count is sourced before the push, not recomputed.
      **Verified 2026-10-26 on `7e62c6b3`** (`master` merged into the branch): 2,040 examples,
      0 failures, 0 deprecation lines. Merging the branch into an unmoved `master` gives that tree;
      if `master` moves again, rerun
- [x] `b51d97ba` deployed on its own (v660, 11:41:37 -0400); `bb732fd7` and `4b840dca` deployed on their
      own (v661, 16:42:03 -0400)
- [x] The production-config probe (step 2) printed the expected four lines
- [x] Pre-push captures (step 3) recorded below

## Pre-deploy

### 1. Log history for the Active Storage routes — done 2026-10-26

Heroku buffer: 1,500 lines back to 2026-10-26 13:32:53 UTC, 0 hits. Papertrail (fixa): no matching
events, searched back to 2026-10-12 08:00 PM (UI time), about fourteen days. OD2 is decided; the routes
go off whatever the count.

Audit on 2026-10-26 (the routes going off must not break a link anything holds):

- **Code**, every repo under `apps/`, `lib/`, `functions/`: no `rails_blob_*`, `rails_representation_*`,
  `rails_storage_*`, `rails_disk_service`, `rails_direct_uploads`, `DirectUpload`/`@rails/activestorage`,
  `/rails/active_storage`, or attachment API. Every `url_for` hit is an app method of the same name
  (`Cloudfare.url_for_resource`, `ListingPdf#url_for_image`, `OrderUrlExport#url_for`).
  insgt-galleries and insgt-virtual-tour do not load the engine (`config/application.rb:8` commented).
- **Database** (dev restore, latest order 2026-10-24): no `active_storage_*` table; 229
  text/varchar/json columns in 52 tables, **0** containing `rails/active_storage`, no timeouts.
- **Where media URLs point**: photos are not stored as URLs; `S3ImageHandler` builds them at read time
  through the image handler (`IMAGE_HANDLER_ENDPOINT`, `d2e08hhdrjhri.cloudfront.net`) or as S3 object
  URLs (`s3_image_handler.rb:271`), and uploads are presigned S3 (`lib/image_handler.rb`). Stored URLs
  in the 50 URL-like columns resolve to S3 buckets (`insight-public`, `insgt-video`, `insgt-youtube`,
  `insgt360`, `insgt360stock`, `insgt-misc`, `insgt-site-data`), third-party video and tour hosts
  (Matterport, YouTube, Vimeo, Zillow), the tour domains, and customers' own sites. None is the API
  host.

### 2. The production-config probe (Dan, on the branch, before the push)

```bash
RAILS_ENV=production HONEYBADGER_REPORT_DATA=false bundle exec dotenv sh -c '
  DATABASE_URL="postgresql://${DATABASE_HOST:-localhost}:${DEVELOPMENT_DATABASE_PORT:-5432}/$DEVELOPMENT_DATABASE" \
  PGUSER="$DEVELOPMENT_DATABASE_USERNAME" PGPASSWORD="$DEVELOPMENT_DATABASE_PASS" \
  exec bin/rails runner "$1"' _ '
  p ActiveSupport::Notifications.notifier.listening?("deprecation.rails")
  p Rails.application.config.active_support.report_deprecations
  p Rails.application.deprecators.each.map { |deprecator| [deprecator.gem_name, deprecator.behavior.map { |behavior| ActiveSupport::Deprecation::DEFAULT_BEHAVIORS.key(behavior) }] }.uniq
  Rails.application.deprecators[:railties].warn("deploy probe")
  p DeprecationReporter.received?("deploy probe")
'
```

The wrapper is what lets a production boot run in the dev container. `dotenv-rails` is in the
`:development, :test` group, so a production boot never reads `.env`, and the production section of
`database.yml` reads only `DATABASE_URL`. `bundle exec dotenv` loads `.env` before Rails starts, and
the dev restore is reached through `DATABASE_URL` plus `PGUSER`/`PGPASSWORD`, which libpq reads, so the
password stays out of the URL. Run as plain `bin/rails runner`, the boot fails with
`AdapterNotSpecified`; the `[Honeybadger] ... API key is missing` line above it is only the gem's
at-exit report of that crash (2026-10-27).

Expected, in order:

| Line | Expected | What it proves |
| :-- | :-- | :-- |
| 1 | `true` | something listens for `deprecation.rails`. The weakest line: no `ServerTiming` in production to fake it (that subscriber is development-only, `development.rb:19`), but line 4 is the proof that the listener is the reporter |
| 2 | `true` (`nil` would also report; **`false` is a STOP** — it silences every deprecator, `railtie.rb:66–70`) | `production.rb:84` survived any merge |
| 3 | `[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]` | **The load-bearing line.** Every registered deprecator (15; the 13 Rails frameworks report as `Rails`, and dotenv's is absent because production never loads `dotenv-rails`) is on `:notify` and so emits a `deprecation.<gem>` event. Any other pair — a behaviour other than `[:notify]` for any gem, `[]`, or `:notify` alongside something else — **is a finding, not a pass** |
| 4 | `true` | one deprecation went through the event and the subscriber and reached the reporter: the wiring end to end, for `Rails.deprecator`. It does not prove delivery: the reporter claims a message before calling Honeybadger, and this probe runs with reporting off. S-DEP proves delivery |

`HONEYBADGER_REPORT_DATA=false` overrides `honeybadger.yml` (checked in development: `report_data`
reads `false` with it), so the probe sends nothing. Line 4's deprecation logs `[Honeybadger] Reporting
error` just before it prints; with `report_data` false the gem's backend is `Backend::Null`, which
drops the notice. Verified in development 2026-10-26: verbatim it
prints `true`, `nil`, `[:log]` ×3, `false` (development logs deprecations and the subscription is
production-only; line 1 is `true` there because of `ServerTiming`); with the guard on and the
deprecators set to `:notify` it prints `true`, `nil`, `[:notify]` ×3, `true`.

Differences from the probe as first written, all checked against 7.2.4: `Deprecators` is not
`Enumerable` (`each` without a block returns an enumerator, hence `each.map`); `behavior` holds lambdas,
mapped back to their names through `DEFAULT_BEHAVIORS`; there is no `:rails` key — `:railties` is
`Rails.deprecator`; the accessor is `received?`, named for what it proves (review round 1).

RESULTS:
```
true
true
[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]
I, [2026-10-27T12:06:58.002986 #6486]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=9ccc74d8-4bd7-4e19-9caa-78579049d1c5 level=1 pid=6486
true
```

### 3. Pre-push captures (on the host, on v661)

```bash
heroku config --app insgtapi | grep -o '^HONEYBADGER_[A-Z_]*'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-10-28 10:00").to_time'
curl -sS -o /dev/null -w "%{http_code}\n" -X POST https://api.insightphotos.net/rails/active_storage/direct_uploads
```

S4 uses `map`, not `pluck`: `nearby_cities` defines `distance_in_miles` in its `select` and orders by
it (`postal_code.rb:131–132`), and `pluck` replaces the select, so the `ORDER BY` raises
`PG::UndefinedColumn`. It did on v661 (2026-10-27), and that run's Honeybadger notice
(`aaa55945-42a2-40ac-a792-d7e9a97b220e`) is the probe, not the upgrade. Every app caller uses `map`.

Expected: both `HONEYBADGER_` names; S4's three names (record them — S4 after the push must match);
S8 before: `2026-10-28 17:00:00 UTC`; S-AS before: `400`. Also send S6 on v661 (step 5's command with
`v661`) so the email path is known good before the change. If another release lands before the push,
these captures move to it.

RECORDED (before):

```
heroku config --app insgtapi | grep -o '^HONEYBADGER_[A-Z_]*'
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
HONEYBADGER_API_KEY
HONEYBADGER_CHECKIN_IMPORT_LISTINGS

["Carlsbad", "Oceanside", "Leucadia"]

2026-10-28 17:00:00 +0000

400
```

## Deploy

### 4. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

RECORDED:
 v      description       user                    created_at
 ────────────────────────────────────────────────────────────────────────────────────────
  v662   Deploy 473e2747   ops@insightphotos.net   2026/10/27 08:15:19 -0400 (~ 24s ago)

### 5. Within 30 minutes

```bash
heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
heroku run --no-tty --exit-code --app insgtapi rails runner '
  puts Honeybadger.notify("rails upgrade slice 1 marker", error_class: "UpgradeMarker",
    fingerprint: "rails-upgrade-marker", tags: "upgrade",
    context: { rails: Rails.version, release: "<vNNN>" }, sync: true).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; puts ActiveSupport.to_time_preserves_timezone.inspect'
heroku run --no-tty --app insgtapi rails runner 'puts ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-10-28 10:00").to_time'
curl -sS -o /dev/null -w "%{http_code}\n" -X POST https://api.insightphotos.net/rails/active_storage/direct_uploads
heroku run --no-tty --app insgtapi rails runner 'ActiveSupport.deprecator.warn("rails upgrade reporter check"); Honeybadger.flush'
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 1', 'release <vNNN>').deliver_now"
```

Expected, reasoned before the push:

| # | Check | Expected |
| :-- | :-- | :-- |
| S2 | `heroku ps`, `grep Booted` | `web.1`, `web.2`, `backgroundworker.1` up; `Booted Rails 7.2.4 application in production environment` |
| S1 | `curl /up` | `200`; the uptime check green |
| S0 | marker | a notice id; `UpgradeMarker` gains an occurrence with context `rails: 7.2.4` and the release |
| S3 | version, `to_time` setting | `7.2.4`, `true` |
| S8 | `to_time` of a Pacific value | `2026-10-28 10:00:00 -0700` (before: `2026-10-28 17:00:00 UTC`) |
| S-AS | direct-upload POST | `404` (before: `400`) |
| S-DEP | deprecation through the reporter | exactly one new `RailsDeprecation` error, tag `deprecation`, message `DEPRECATION WARNING: rails upgrade reporter check (called from <main> at …bin/rails:4)`, context `gem_name: Rails`, `deprecation_horizon: 8.0`, `callstack` railties' `runner_command.rb:49:in 'Kernel#eval'` (a runner has no app frame, so the first frame); a backtrace on the page. Running it again in a **new** one-off dyno adds an occurrence to the same error (same gem and message, so the same fingerprint), not a second error |
| S4 | nearby cities | identical to the pre-push capture |
| S5 | Stripe | `true` |
| S6 | email | `SystemError::rails upgrade slice 1` arrives at ops@insightphotos.net |

A missing `RailsDeprecation` from S-DEP means the subscription or `:notify` did not take in production:
stop and look (step 2's probe narrows it). A boot failure on any dyno is a rollback.

Recorded:
```
insgt-api git:(master) heroku ps --app insgtapi
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
=== backgroundworker (Standard-2X): bundle exec sidekiq -c 4 (1)

backgroundworker.1: up 2026/10/27 08:15:25 -0400 (~ 1m ago)

=== web (Standard-2X): bundle exec puma -C config/puma.rb (2)

web.1: up 2026/10/27 08:15:26 -0400 (~ 1m ago)
web.2: up 2026/10/27 08:15:24 -0400 (~ 1m ago)

➜  insgt-api git:(master) heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
2026-10-27T12:15:32.326288+00:00 app[backgroundworker.1]: pid=2 tid=1eq INFO: Booted Rails 7.2.4 application in production environment
➜  insgt-api git:(master) heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
=== backgroundworker (Standard-2X): bundle exec sidekiq -c 4 (1)

backgroundworker.1: up 2026/10/27 08:15:25 -0400 (~ 2m ago)

=== web (Standard-2X): bundle exec puma -C config/puma.rb (2)

web.1: up 2026/10/27 08:15:26 -0400 (~ 2m ago)
web.2: up 2026/10/27 08:15:24 -0400 (~ 2m ago)

 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
2026-10-27T12:15:32.326288+00:00 app[backgroundworker.1]: pid=2 tid=1eq INFO: Booted Rails 7.2.4 application in production environment
200
➜  insgt-api git:(master) heroku run --no-tty --exit-code --app insgtapi rails runner '
  puts Honeybadger.notify("rails upgrade slice 1 marker", error_class: "UpgradeMarker",
    fingerprint: "rails-upgrade-marker", tags: "upgrade",
    context: { rails: Rails.version, release: "<vNNN>" }, sync: true).inspect'
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rails runner "
  puts Honeybadger.notify(\"rails upgrade slice 1 marker\", error_class: \"UpgradeMarker\",
    fingerprint: \"rails-upgrade-marker\", tags: \"upgrade\",
    context: { rails: Rails.version, release: \"<vNNN>\" }, sync: true).inspect" on ⬢ insgtapi... up, run.2551
I, [2026-10-27T12:17:57.635039 #4]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=470ed91b-d622-40d3-a2fb-bc5adb644454 level=1 pid=4
I, [2026-10-27T12:17:57.694719 #4]  INFO -- honeybadger: ** [Honeybadger] Success ⚡ https://app.honeybadger.io/notice/470ed91b-d622-40d3-a2fb-bc5adb644454 id=470ed91b-d622-40d3-a2fb-bc5adb644454 code=201 level=1 pid=4
"470ed91b-d622-40d3-a2fb-bc5adb644454"
➜  insgt-api git:(master) heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; puts ActiveSupport.to_time_preserves_timezone.inspect'
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rails runner "puts Rails.version; puts ActiveSupport.to_time_preserves_timezone.inspect" on ⬢ insgtapi... up, run.7804
7.2.4
true
➜  insgt-api git:(master) heroku run --no-tty --app insgtapi rails runner 'puts ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-10-28 10:00").to_time'
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rails runner "puts ActiveSupport::TimeZone[\"Pacific Time (US & Canada)\"].parse(\"2026-10-28 10:00\").to_time" on ⬢ insgtapi... up, run.2157
2026-10-28 10:00:00 -0700
➜  insgt-api git:(master) curl -sS -o /dev/null -w "%{http_code}\n" -X POST https://api.insightphotos.net/rails/active_storage/direct_uploads
404
➜  insgt-api git:(master) heroku run --no-tty --app insgtapi rails runner 'ActiveSupport.deprecator.warn("rails upgrade reporter check"); Honeybadger.flush'
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rails runner "ActiveSupport.deprecator.warn(\"rails upgrade reporter check\"); Honeybadger.flush" on ⬢ insgtapi... up, run.3615
I, [2026-10-27T12:19:29.580669 #2]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=55c54cf0-415c-4bdd-9c07-ba1f2b934ac6 level=1 pid=2
I, [2026-10-27T12:19:29.665672 #2]  INFO -- honeybadger: ** [Honeybadger] Success ⚡ https://app.honeybadger.io/notice/55c54cf0-415c-4bdd-9c07-ba1f2b934ac6 id=55c54cf0-415c-4bdd-9c07-ba1f2b934ac6 code=201 level=1 pid=2
➜  insgt-api git:(master) heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rails runner "puts PostalCode.find_by(zip: \"92008\").nearby_cities.limit(3).map(&:name).inspect" on ⬢ insgtapi... up, run.9285
["Carlsbad", "Oceanside", "Leucadia"]
➜  insgt-api git:(master) heroku run --no-tty --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rails runner "puts Stripe::Balance.retrieve.livemode" on ⬢ insgtapi... up, run.1932
true
➜  insgt-api git:(master) heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 1', 'release <vNNN>').deliver_now"
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rails runner "Notifier.send_error_email('rails upgrade slice 1', 'release <vNNN>').deliver_now" on ⬢ insgtapi... up, run.3297
```

Confirmed in Honeybadger (Dan, 2026-10-27):

- **S0**: `UpgradeMarker` has a second occurrence, "rails upgrade slice 1 marker", 2026-10-27 08:17
  -0400, in the same error as slice 0's (one fingerprint). Its `release` context reads `<vNNN>`: the
  placeholder went out unreplaced, in S6 too.
- **S-DEP**: notice `55c54cf0-415c-4bdd-9c07-ba1f2b934ac6` reads `DEPRECATION WARNING: rails upgrade
  reporter check (called from <main> at /app/bin/rails:4)` and carries a backtrace: the app frame
  `bin/rails:4`, the first frame railties-7.2.4 `runner_command.rb:49` in `Kernel#eval`. Its context
  is as expected: `gem_name` `"Rails"`, `deprecation_horizon` `"8.0"`, and `callstack`
  `/app/vendor/bundle/ruby/3.4.0/gems/railties-7.2.4/lib/rails/commands/runner/runner_command.rb:49:in
  'Kernel#eval'` (a runner has no app frame, so the first frame). The search `class:"RailsDeprecation"
  tag:"deprecation" context.gem_name:"Rails" environment:"production"` (unresolved, unignored) returns
  exactly this error: class `RailsDeprecation`, tag `deprecation`, count 1, about 34 min after it was
  sent. Rerun in a new one-off dyno: the same search still returns one error, now count 2, so the
  fingerprint groups across dynos.
- **S6**: the first send (run.3297) was blocked at SendGrid, not in Rails (Dan). With the block
  removed, a resend, `SystemError::rails upgrade slice 1 -test`, reached ops@insightphotos.net at
  2026-10-27 12:43:27 UTC (08:43 -0400) through SendGrid, with DKIM, SPF and DMARC passing; body
  `release <vNNN>`.

### 6. One hour after the push (S7) and the first import (S9)

```bash
heroku logs -n 1500 --app insgtapi > /tmp/s7.log
head -1 /tmp/s7.log | cut -c1-32; tail -1 /tmp/s7.log | cut -c1-32
grep -c "status=5" /tmp/s7.log
grep -oE '\] [A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)* \(' /tmp/s7.log | sort | uniq -c | sort -rn
```

Then Papertrail: `status=5` from the push to one hour after it.

Expected: no `status=5` line in the hour (Papertrail), and no exception class in the buffer other than
`ActionController::RoutingError`; any other class is a finding, triaged before S7 passes. S9: the first
`import_listings` check-in after the push arrives on time (about :36–:45 UTC).

Amended 2026-10-27, after the run. As first written, S7 was `grep -c "status=5"` and
`grep -ciE "error|exception"` on the live buffer, the second "not above the same window on v661".
Three things broke it. The buffer is 1,500 lines, not an hour (24 min on the morning), so the hour
comes from Papertrail. No v661 count was captured to compare against. And the error count is set by
scanner traffic, two lines per `RoutingError`, so it says nothing about the release; the exception
classes do. Saving the buffer once makes the window, the count and the classes describe the same lines.

Recorded 2026-10-27. **S7 and S9 pass.**

- First run, with the commands as first written: `status=5` → `0`; `error|exception` → `530`.
- A second snapshot, saved to a file and broken down: 1,500 lines span 12:34:53–12:58:42 UTC, 24 min,
  from 19 to 43 min after the push. All of it is v662, and it covers neither the first 19 min nor the
  full hour. 484 lines match `error|exception`:
  - 480 from `web.1` (246) and `web.2` (234): 240 rescued exceptions, two lines each. With
    `log_tags = [:request_id]`, Rails logs a bare `ERROR -- : [request-id]` line, then
    `[request-id] Class (message):` (actionpack 7.2.4 `debug_exceptions.rb:146–147`). The class grep
    returns one row, `240 ] ActionController::RoutingError (`: a scanner probing for `.env` and
    `phpinfo.php` paths, answered `404`.
  - 4 from `scheduler.5568`: `Rets::Client: Failed with message: Got error code N (No Records Found)`,
    a `WARN` logged during the scheduled import run.
- Papertrail, `status=5`, 08:15–09:15 -0400 (12:15–13:15 UTC): 0 results.
- S9: `import_listings` checked in at 2026-10-27 08:36 -0400 (12:36 UTC), state `reporting`.

### 7. 24 hours after the push (SH)

Honeybadger → Errors, environment **production**, since the push, against the slice 0 baseline.
Expected: no class absent from the baseline except `RailsDeprecation` from S-DEP. **Any other
`RailsDeprecation` is a finding**: a deprecation on a path the suite does not reach. Record its message
and call site here; under OD8 one that `:raise` would trip in the suite is a STOP for slice 2. A
`DeprecationReporter` failure notice (a `StandardError` with `deprecation_message` in its context) is
also a finding: the reporter is broken, and the log line `[DeprecationReporter] Failed to report …` has
the detail.

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to v661. Nothing to undo in data: no migration, the reporter's dedupe is per process and dies
with it, the routes return with the old slug. `RailsDeprecation` errors already in Honeybadger stay
and can be resolved by hand.

## Known, kept by decision

- **What the reporter sees, and what it does not.** Every deprecator registered with
  `Rails.application.deprecators` is reported: it inherits the `:notify` behaviour and emits
  `deprecation.<gem_name>` (`deprecation.rails`, `deprecation.global_id`, `deprecation.lograge` today),
  and the subscription is `/\Adeprecation\./`. Gem deprecations are reported on purpose — the early
  warning ahead of the 8.0 slice. Not seen: a gem that creates its own `ActiveSupport::Deprecation`
  instance without registering it with the app (it keeps its own default behaviour and emits no event),
  and plain Ruby `warn` / `Kernel#warn` calls, such as rack's `:unprocessable_entity` warning in the
  specs (§8 item 1).
- **Once per deprecator and call site, not per deprecation.** The payload's `message` ends with
  `(called from … at file:line)` but does not name the deprecator, so the dedupe key — and the
  fingerprint, which is all Honeybadger groups on — is `"<gem_name>: <message>"`: every offending site
  surfaces once per process per deprecator, and the same wording from two gems is two errors. The set
  is bounded by call sites, unless a deprecation's text embeds a runtime value, which adds an entry per
  value. `Concurrent::Map#put_if_absent` claims the key atomically, so two Puma threads cannot both
  report it (Codex: 3,000 calls across 30 threads, one notice). At most four notices per key per
  release (two web dynos, one worker, one-off dynos), grouped into one error by fingerprint.
- **A reporter failure is logged and reported, never raised.** The deprecated call carries on. The log
  line and the failure notice are rescued separately, so a broken logger cannot stop the notice.
- **The boot window.** A deprecation warned after the railtie applies `:notify` but before the
  `to_prepare` subscription (config and engine initializers) emits an event nobody hears. Before this
  slice those were silenced anyway. The same initializers boot under `:raise` in test, and none branches
  on production (`grep -n production config/initializers/*.rb`: comments only), so only production-only
  code inside a gem could warn there unseen.
- **The flaky specs.** `account_classification_rake_spec.rb:156` and `calculator_spec.rb:965` fail
  when a clock second ticks between two `N.days.ago` calls; each failed once on this branch and passed
  on rerun, independent of `to_time` (a forced one-second delay fails both with the setting either way).
  Fixed on their own branch after this push.
- **`Sidekiq::Status::status(jid)` is `nil`** in development (§8 item 10); P3 asserts the Sidekiq log
  lines instead.
- **`Naming/RescuedExceptionsVariableName`** flags `rescue StandardError => error` in the reporter; the
  name follows CLAUDE.md (no shortened names) over the cop's `e`.

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed <date>`, the release, steps 3–7's results.
- `rails-upgrade.md` v4: §4.2 marked deployed; the amendments listed in the slice 1 plan's write-back.
- `rails-upgrade.md` §4.0 S7: step 6's amended criterion, which every later slice reuses.

## Deploy log

- 2026-10-26: **verified in development** (dev restore). Branch head `78b580cf` for P2–P8; P1 rerun
  on `20149490` after review round 1 and on `a5d9b001` after commit 8.
  - P1: `2030 examples, 0 failures` (78 s) at `78b580cf`; `2033` (83 s) at `20149490`; `2034` (71 s)
    at `a5d9b001`; `grep -c "DEPRECATION WARNING"` → `0` every time. Baseline was 2,013 on `master`
    02dbb78a (2,009 at the survey plus `listing_virtual_agent_spec.rb`'s four).
  - P2: `zeitwerk:check` → "Otherwise, all is good!" (the `lib/` eager-load notice is printed on
    `master` too).
  - P3: own queue `slice1_p3` (a `bin/dev` Sidekiq on `default` was running);
    `Booted Rails 7.2.4 application in development environment`; property 1964 →
    `start` → `[PropertyDataLookupWorker] Property#1964 already has property data, skipping` →
    `done` (0.284 s); `Sidekiq::Status::status(jid)` → `nil` (recorded, §8 item 10).
  - P4: **4** examples, 0 failures. §4.0 says 3: its range `:110–141` stops before the fourth example
    (`:142`, "excludes cities without coordinates"); the file last changed 2026-05-17. A document
    miscount, corrected in v4.
  - P5: 86 examples, 0 failures. P6: `SystemError::rails upgrade`. P7: 122 examples, 0 failures.
  - P8: photo 659058 → `d2e08hhdrjhri.cloudfront.net`, `200`, `image/jpeg` (`Net::HTTP`).
  - Routes: `bin/rails routes | grep -c active_storage` → `0`; total 583.
  - Production-like boot (test environment, `CI=1`: eager load on, reloading off) with the guard
    forced on: boots, `DeprecationReporter` loaded, one listener — still one after 5
    `reloader.wrap` and 5 `executor.wrap` (with reloading off `reloader.check` is `false`,
    `finisher.rb:201`, so Sidekiq's job wrapper never re-runs `to_prepare`). The bare
    `DeprecationReporter.subscribe` the plan named fails that boot with
    `uninitialized constant DeprecationReporter (NameError)`.
  - `predeploy-review-rails`, two rounds, Codex on an rsync copy without `.git` or `.env` (both copies
    stayed identical to the tree). Round 1 [codex, one also claude]: `reported?` overstated delivery
    (renamed `received?`); the gate example checked config only (behavioural example added — red with
    `report_deprecations = false` in test while the config example stayed green); the boot window
    between `:notify` and `to_prepare` (documented); a raising logger skipped the failure notice
    (rescued separately, spec red without it); "never raises" narrowed to Notifications payloads.
    Declined: a production-boot spec (step 2's probe and S-DEP cover it). Fixes folded into commits
    3, 5, 6 and 7 with `--autosquash`; the final tree is identical to the reviewed one. Round 2: no new
    findings.
  - Commit 8 (`a5d9b001`, after both review rounds, at Dan's request): Honeybadger groups on the
    fingerprint alone (docs, "Customizing error grouping": `:fingerprint` overrides the computed one;
    same fingerprint, same error), so `gem_name` in the context never separated groups. The key is now
    `"<gem_name>: <message>"` for both the dedupe and the fingerprint. Red first (one notice for two
    gems; the old fingerprint), and each half breaks on its own: fingerprint from the message alone →
    two examples red; dedupe on the message alone → the two-gem example red.
- 2026-10-26 16:42:03 -0400: **v661** `d37ae0df` (emergency fix, `bb732fd7` and `4b840dca`) deployed from
  `master` outside this slice. Checked from the container: the two sides share no file;
  `git merge-tree --write-tree master chore/rails-upgrade-slice-1` is clean. The suite was **not** run on
  the merge here (that would merge `master` into a working tree); it is the merge prerequisite, expected
  2,040 examples. "Before" captures and the rollback target moved to v661.
- 2026-10-26: Dan merged `master` into the branch (`7e62c6b3`, "Merge branch 'master' into
  chore/rails-upgrade-slice-1"); relative to `a5d9b001` it changes only v661's two files. Full suite:
  **2,040 examples, 0 failures** (72 s), `grep -c "DEPRECATION WARNING"` → `0`, the 24
  `:unprocessable_entity` warnings unchanged; `listing_virtual_agent_spec.rb` 10 examples, 0 failures
  under `:raise` on 7.2.4; `zeitwerk:check` → "Otherwise, all is good!".
- Heroku Deploy:
  v662   Deploy 473e2747   ops@insightphotos.net   2026/10/27 08:15:19 -0400 (~ 24s ago)