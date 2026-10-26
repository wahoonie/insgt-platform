# Runbook: Rails Upgrade Slice 0 — Honeybadger

**Last updated:** 2026-10-26
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~20 min on the morning; S9 at the first hourly import after the push; the
baseline 24 h later
**Status:** Ready

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.1 (v3). Branch `chore/rails-upgrade-slice-0`, two
commits:

1. `d4dd6d9e` build: add honeybadger for error tracking — `honeybadger` 6.10.0 (`~> 6.10`), the one
   gem this upgrade adds; `config/honeybadger.yml` with no key, reporting from production only,
   Insights off, log breadcrumbs off; `spec/config/honeybadger_spec.rb`.
2. `a641c52b` feat: check in from the listings import — `Honeybadger.check_in` as the last step of
   `import_listings`, guarded on `HONEYBADGER_CHECKIN_IMPORT_LISTINGS`.

**No migration, no client release, no backfill. Rails stays 7.2.3.** Two ENV vars, both set before
the push (Prerequisites).

**What moves for a human.** Nothing in the API's behaviour. From the push on, production errors
(requests, Sidekiq workers, rake tasks) reach the Honeybadger project; the uptime check watches
`/up`; the `import_listings` check-in reports hourly. "Quiet" for every later slice (§2.2) is measured
against the baseline this runbook records in step 5.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. The
Honeybadger dashboard is the web UI.

## Deploy window

Mon–Wed, 09:00–11:30 Pacific, outside the 08:00 and 12:00 delivery windows (§2.4). Planned for
Mon 2026-10-26.

## Prerequisites

- [ ] Dan has merged `chore/rails-upgrade-slice-0` (`d4dd6d9e..a641c52b`) to `master`;
      `bundle exec rspec` green (2,009 examples, 0 failures on 2026-10-26)
- [x] `HONEYBADGER_API_KEY` in `heroku config --app insgtapi` — rotated 2026-10-26, after the
      install-time key had been written into an untracked file and printed into a session transcript
- [x] Check-in `import_listings` created: Simple, report period 1 hour, grace period 30 minutes. The
      cadence comes from `mls_imports`: the last 40 CRMLS imports on the dev restore are exactly 1.0 h
      apart, finishing about :35 UTC, extraction 318–452 s
- [x] `HONEYBADGER_CHECKIN_IMPORT_LISTINGS` in `heroku config --app insgtapi` (the check-in id, or its
      full URL — `Honeybadger.check_in` accepts either)
- [x] Uptime check on `https://api.insightphotos.net/up`, condition Success
- [ ] The four development notices (the `honeybadger install` test, and step 6's three) resolved, so
      the Errors list starts empty for production. Step 5 filters on production either way

### 1. Before the push — the two variables are there

```bash
heroku config --app insgtapi | grep -o '^HONEYBADGER_[A-Z_]*'
```

Expected: `HONEYBADGER_API_KEY` and `HONEYBADGER_CHECKIN_IMPORT_LISTINGS`. Names only; the `grep -o`
keeps the values off the screen. Setting them before the push is harmless: the old code reads
neither.

### 2. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

Rollback is `heroku rollback` (below). No maintenance window, no migration.

### 3. Within 30 minutes — the gem loaded and reports (S0–S2)

```bash
heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
heroku run --no-tty --exit-code --app insgtapi rails runner '
  puts Honeybadger.notify("rails upgrade slice 0 marker", error_class: "UpgradeMarker",
    fingerprint: "rails-upgrade-marker", tags: "upgrade",
    context: { rails: Rails.version, release: "<vNNN>" }, sync: true).inspect'
heroku logs --ps web.1 -n 200 --app insgtapi | grep -i honeybadger
```

Expected, reasoned before the push:

| Check | Expected |
| :-- | :-- |
| `heroku ps` | `web.1: up`, `backgroundworker.1: up` |
| `grep Booted` | `Booted Rails 7.2.3 application in production environment` |
| `curl /up` | `200`; the uptime check green in the dashboard |
| S0 marker | prints a notice id (a UUID string; `false` means not sent). Honeybadger → Errors shows `UpgradeMarker` in environment **production**, context `rails: 7.2.3` and the release |
| `grep -i honeybadger` on web.1 | **no line at boot.** The gem's start-up line is debug-level and production logs at `info` (`config/environments/production.rb:61`). `** [Honeybadger] … Success ⚡` lines appear only when an error is reported. A Honeybadger `WARN`/`ERROR` line is a finding |

A missing `UpgradeMarker` means the gem did not load or cannot send: stop and look before calling
the deploy done (§5 R1).

### 4. The first hourly import after the push (S9)

`import_listings` runs hourly and finishes about :35 UTC. Honeybadger → Check-Ins →
`import_listings`: the first report arrives at roughly :36–:45 UTC of the first hour after the push,
then hourly.

A missed check-in means the task raised (its error is in Honeybadger as a rake notice) or did not
run. A check-in means the task **finished**, not that listings arrived: `Crmls.extract_listings`
returns without raising when the MLS login fails (`lib/crmls.rb:94–95`). For an import that ran but
loaded nothing, look at `mls_imports`.

### 5. 24 hours after the push — the baseline

Honeybadger → Errors, environment **production**, since the push. Record every error class with its
first-seen time and occurrence count under **Baseline** in the Deploy log below. Rule (§4.1): an empty
list is a valid baseline, and `UpgradeMarker` is always in it. Every later slice's SH check and the
quiet week (§2.2) compare against this list.

### 6. Development verification (done before the deploy)

Run from the dev container on 2026-10-26 against the same Honeybadger project; results in the Deploy
log. Repeatable with these commands:

```bash
# Precedence: an ENV value wins over config/honeybadger.yml
HONEYBADGER_REPORT_DATA=true bin/rails runner 'p Honeybadger.config.public?'          # true
bin/rails runner 'p Honeybadger.config.public?'                                      # false

bundle exec honeybadger test

# The deliberately failing job, on its own queue so a running dev Sidekiq does not take it
HONEYBADGER_REPORT_DATA=true HONEYBADGER_ENV=development-check \
  bundle exec sidekiq -c 1 -e development -q honeybadger_check
bin/rails runner 'jid = GenerateCoordinatesWorker.set(queue: "honeybadger_check").perform_async("NoSuchClass", 1)
  sleep 5; p Sidekiq::Status::status(jid)'
```

`.env` holds a Honeybadger key in the container, so `HONEYBADGER_REPORT_DATA=true` on any dev command
reports to the production project. Use `HONEYBADGER_ENV=development-check` with it so the notice is
filed outside production.

## Rollback

```bash
heroku rollback --app insgtapi
```

Nothing to undo in data. After a rollback the check-in alerts at its next missed hour and the uptime
check keeps running; pause the check-in in the dashboard if the rollback will last. The two config
vars can stay: old code reads neither.

## Known, kept by decision

- **Sidekiq job arguments reach Honeybadger unfiltered.** The Rails filter list applies only to
  notices with a request (`notice.rb:576–582`), and positional args have no keys to match. Today they
  are ids and order tokens (`app/workers/*`), not the guest `access_token`.
- **Log breadcrumbs are off** (`breadcrumbs.logging.enabled: false`). The gem filters breadcrumb
  metadata, never the message (`notice.rb:408–415`), and the app logs
  `params.require(:account).inspect` (`accounts_controller.rb:163`) and Twilio verifications
  (`lib/auth.rb:34`). Request, render and SQL breadcrumbs stay; SQL is obfuscated
  (`breadcrumbs/active_support.rb:23`).
- **`HTTP_REFERER` is sent unfiltered.** insgt-app puts `?accessToken=` in its own page URLs
  (`order-payment-link.pipe.ts:19`), but the API is another origin and no referrer policy is set,
  so browsers send the origin only (default `strict-origin-when-cross-origin`). Filtering it would
  mean listing `request.filter_keys` in full, replacing the gem's default list.
- **A bare top-level `number` param goes in clear** (`sessions_controller.rb:31` shape); `area_code`
  is filtered because `code` partially matches it. The same as the Rails log filter.
- **The uptime probes add `/up` lines to the production log** until `config.silence_healthcheck_path`
  is available (Rails 8.0, §8 item 3).
- **Insights is off** (§8 item 17).
- **`Sidekiq::Status::status(jid)` is `nil`** in development: `config/sidekiq_status.rb` is not
  required by anything (§8 item 10). Slice 1's P3 expects `:complete` (§4.0, amended in v3).

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed <date>`, the release, steps 3–5's results and the baseline.
- `rails-upgrade.md`: §4.1 slice 0 marked deployed with the release; the baseline's location.

## Deploy log

- 2026-10-26: **verified in development** (dev restore; Honeybadger project, environments
  `development` and `development-check`). Suite 1,997 → 2,009 examples, 0 failures, the one known
  deprecation unchanged; every new spec red first, each deliberate break red on its own example.
  - Precedence, four boots: none → `report_data=false public?=false backend=Null`;
    `HONEYBADGER_REPORT_DATA=true` → `true true Server`; `HONEYBADGER_ENV=development-check` →
    `false false Null`; both → `true true Server`. Insights off in all four.
  - `honeybadger test`: `HoneybadgerTestingException`, notice `32e35042-7118-47cd-9ac8-87b7c8352255`.
  - Filter review, one request through the full middleware stack with a fake `Authorization: Bearer`
    header and the app's param shapes: notice `174ddb53-04a5-48db-83de-3410f7148311`.
    `HTTP_AUTHORIZATION`, `transaction.token`, `access_token` (params and URL, breadcrumbs too),
    `email`, `password`, `area_code` → `[FILTERED]`; `client_ip`, `number` in clear. None of the five
    fake credentials appears anywhere in the sent payload. One notice per request.
  - Failing job: `Booted Rails 7.2.3 application in development environment` → `start` →
    `ERROR: [GenerateCoordinatesWorker] Failed for NoSuchClass#1: NameError — uninitialized constant
    NoSuchClass` → `fail` → `POST /v1/notices code=201`, notice
    `6acbe01d-4cc3-4b40-a140-808c010e2a33` (`NameError in GenerateCoordinatesWorker#perform`,
    `development-check`). `Sidekiq::Status::status(jid) => nil`, `get_all => {}`.
  - Dan confirmed all three notices in the dashboard.
  - The filter-review notice above was sent before log breadcrumbs were turned off, so it carries one
    `log` breadcrumb (the request's own error line). The final config is covered by
    `spec/config/honeybadger_spec.rb`, which serializes a request notice locally and finds no
    credential and no logged line in it.
  - `predeploy-review-rails` with two Codex rounds on a copy of the tree without `.env`. Round 1: log
    breadcrumbs ship unfiltered log lines (fixed: off), the Authorization spec checked config rather
    than a payload (fixed: the serialized-notice example), `api_key` checked in one section (fixed:
    every section), `HTTP_REFERER` unfiltered (kept: Known, above). Round 2: no new findings. The
    fixes were folded into commit 1 on the unpushed branch (`55fc766f` → `d4dd6d9e`).
