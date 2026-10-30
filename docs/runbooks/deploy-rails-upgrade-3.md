# Runbook: Rails Upgrade Slice 3 — 8.1.4, the landing target

**Last updated:** 2026-10-30
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~30 min on the morning; S7 one hour after the push; S9 at the first hourly
import; SH 24 h later
**Status:** Ready — implemented and verified in development 2026-10-30 (step 1); two review rounds of
`predeploy-review-rails` done 2026-10-30 (no blocker, no open should-fix; the record is under Known).
Awaiting Dan's review and merge.

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.4 (v5; v6 amends it after verification — see
`docs/plans/rails-upgrade-slice-3.md` for every deviation and why). Branch
`chore/rails-upgrade-slice-3`, five commits off `master` f86877f5 (production v665). The branch was
rebuilt once after review round 1 to fold a spec-comment clarification into commit 1; the pre-review
hashes `934abe6b`…`41b8a546` are gone and the tree differs from them only by that comment:

1. `a5bfab70` fix: stop heading twice when a guarded record is missing — `return if performed?`
   after `find_instance` in five setters (`orders_controller.rb:700`, `transactions_controller.rb:75`,
   `raw_photos_controller.rb:55`, `listing_rooms_controller.rb:31`,
   `listing_property_features_controller.rb:31`); raw photos' two branch guards become
   `return render_no_content if …`. On 8.0.5.1 no response changes; on 8.1.4 each of these misses
   would otherwise raise `AbstractController::DoubleRenderError` (a 500). Eleven request examples in
   `spec/requests/missing_record_guards_spec.rb`.
2. `3b7780d4` build: upgrade rails to 8.1.4 — the 13 Rails gems 8.0.5.1 → 8.1.4;
   `action_text-trix (2.1.19)` enters the lock (Action Text 8.1's runtime dependency, through
   `rails/all`; inert without an asset pipeline); Active Support's `benchmark` edge becomes `json`;
   nothing else moves. `config/application.rb`'s `to_time_preserves_timezone = :zone` line and its
   comment are deleted in the same commit — on 8.1 any value deprecates at boot, on 8.0 its absence
   does. The contract spec's floor is `8.1.4` and its `to_time` example pins the key's absence.
3. `218b0844` chore: apply the rails 8.1 app:update binstubs — `bin/rubocop`, one comment line.
4. `847a85d6` chore: add the rails 8.1 framework defaults shim —
   `config/initializers/new_framework_defaults_8_1.rb`, all six flags commented.
5. `5ffe92c4` chore: re-dump schema.rb under rails 8.1 — `[7.2]` → `[8.1]` and
   `enable_extension "plpgsql"` → `"pg_catalog.plpgsql"` (8.0's dumper; the control dump on 8.0.5.1
   showed the same hunk). A comment line and a no-op load; no DDL.

**No migration, no DDL, no ENV change, no client release.** `config.load_defaults` stays `7.2`.

**Production is v665** (`f86877f5`, 2026-10-29 08:02:41 -0400, the Ruby 3.4.12 bump). The branch is
cut from it. If `master` moves before the push, merge `master` into the branch, rerun the suite on the
merge, and move the "before" captures and the rollback target to the new release.

**Where this sits.** This is the third of six deploy mornings, not the end: slice 4 (Mon 11-09), 5a
(Tue 11-10), 5b (Wed 11-11), the quiet week to Wed 11-18, then the Render rehearsal (§6).

**What moves for a human.**
- **Nothing visible on the five guarded paths** — a missing or inaccessible order, order
  transactions, raw photos, listing room or listing property feature keeps answering `204`. Without
  commit 1, 8.1.4 answers every `GET /orders/<missing id>` from a logged-in insgt-ops or insgt-app user
  with a `500`. S-404 is the direct read.
- **`/up.json` answers JSON**: `{"status":"up","timestamp":"…"}`, `application/json` (on 8.0.5.1 it
  rendered the HTML page). `/up` is unchanged. The one visible change of this slice (S1).
- **`request.remote_ip` keeps a forwarded entry that carries a port** (8.0 discarded the whole entry
  and fell back to the next hop). The only consumer is Stripe's `client_ip`
  (`transactions_controller.rb:55`); ASSUMPTION: Heroku's router writes bare addresses, so nothing
  changes. Informational.
- **One new WARN line in production logs at every boot**, and at the top of every
  `heroku run … rails runner` output in this runbook (see Known). Not an error, not a deprecation, not
  reported to Honeybadger.
- Nothing else: `to_time` behaves exactly as on v665 (S8), JSON bytes do not change (the 8.1 flags are
  commented), the route table is identical (583 routes), and no existing spec changed.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. The
production-config probe (Pre-deploy, step 2) runs in `apps/insgt-api` on the merge, wherever Dan runs
it. The Honeybadger dashboard is the web UI.

## Deploy window

**Mon 2026-11-02, 09:00–11:30 Pacific** (17:00–19:30 UTC — DST ended Sun 11-01, so Pacific is UTC-8
and Eastern -0500; `heroku releases` on the host prints -0500 from this morning). Mon–Wed only,
outside the 08:00 and 12:00 delivery windows (§2.4). Slice 2's SH closed Thu 2026-10-29; Thursday and
Friday are not deploy days.

**Slippage rule (§6, OD1):** if review and merge are not complete by 09:00 PT, the deploy moves to
**Tue 11-03**, then **Wed 11-04**. **Wed 11-04 is the last morning before 8.0's security end date
(Sat 11-07, §1.3)**; a slip past it is a §7 decision, not a slot change. **Nobody pushes after 11:30
to make the window.**

## Prerequisites

- [x] **Slice 2's SH result** (`deploy-rails-upgrade-2.md` step 7): **passes** — no unresolved error
      since v663's push, no `RailsDeprecation`; the one resolved error (`orders#show` with no
      credential) is pre-existing and fixed by `55c86f1d` (v664)
- [x] **The OD7 dump** (Dan): control dump on `master` 03e270c6 (2026-10-28) → `[8.0]` plus the
      `pg_catalog.plpgsql` hunk, discarded; the 8.1 dump after commit 4 (2026-10-30) → the same two
      hunks with `[8.1]`, committed as commit 5; the round-trip load after commit 5 (2026-10-30) →
      `git diff db/schema.rb` empty
- [x] Review rounds complete (two rounds of `predeploy-review-rails`, Codex second opinion included,
      2026-10-30); this runbook's Status is `Ready`
- [ ] Dan has merged `chore/rails-upgrade-slice-3` into `master` and `bundle exec rspec` is green
      **on the merge**: expected 2,059 examples, 0 failures, 0 `DEPRECATION WARNING` lines if `master`
      is still f86877f5; a different count is sourced before the push, not recomputed
- [ ] The production-config probe (step 2) printed the expected lines on the merge
- [ ] Pre-push captures (step 3) recorded below, on the release that is live at that moment (v665)

## Pre-deploy

### 1. Development verification — done 2026-10-30

On the branch at `5ffe92c4` (the dev container; Ruby 3.4.12; the test database freshly loaded from
the committed `[8.1]` file by the round trip):

| # | Result |
| :-- | :-- |
| P1 | `2059 examples, 0 failures` (62.2 s); `CI=1`: `2059 examples, 0 failures` (62.2 s); `0` `DEPRECATION WARNING` lines in each; the 24 rspec-rails `:unprocessable_entity` warnings unchanged. Baseline on `master` f86877f5: 2,048, so +11, the new request spec. After the round 1 rebuild: one run hit the `calculator_spec.rb:965` one-second flake (`02:39:14` expected, `02:39:13` got), the example passed alone, and the rerun gave `2059 examples, 0 failures` |
| P2 | `zeitwerk:check` → "all is good" (the `lib/` notice as on `master`) |
| P3 | `slice3_p3` queue: `Booted Rails 8.1.4 application in development environment`, `start`, `[PropertyDataLookupWorker] Property#1964 already has property data, skipping`, `done` (`elapsed=0.223`); `Sidekiq::Status::status(jid)` → `nil` (§8 item 10) |
| P4 | `4 examples, 0 failures` |
| P5 | `86 examples, 0 failures` |
| P6 | `ActionMailer::MessageDelivery`; `SystemError::rails upgrade` |
| P7 | `122 examples, 0 failures` |
| P8 | photo 661071 → `d2e08hhdrjhri.cloudfront.net`, `200`, `image/jpeg` (`Net::HTTP`) |
| P-PROD | step 2's RESULTS below |
| Routes | `bin/rails routes` byte-identical to `master`'s (583 lines); `active_storage` `0` |

Per-commit loop records (red, green, deliberate break) are in the plan. No scratch Heroku app exists
for `insgtapi`, so the build is proved by the release itself (§2.5); a failed build is not a release,
and v665 keeps running.

### 2. The production-config probe (Dan, on the merge, before the push)

Slice 2's wrapper with one line replaced and two added. **`p ActiveSupport.to_time_preserves_timezone`
is gone**: on 8.1.4 the reader itself deprecates, so the probe would raise a `RailsDeprecation` through
`:notify` — the `key?` probe reads the configuration hash instead. `HONEYBADGER_REPORT_DATA=false`
keeps the probe's own deprecation out of production's Honeybadger.

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
' 2>&1 | tee /tmp/p-prod.log; grep -c DEPRECATION /tmp/p-prod.log
```

Expected, in order: the Active Storage `image_processing` WARN line (Known); `"8.1.4"`; `true`;
`true`; `[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]` (**the load-bearing
line** — anything else is a finding); the gem's `Reporting error` log line; `true`; **`false`** (no
`to_time` key — `true` means the deletion did not land); `7.2`; `583`; `false` (reporting off);
`true` (the 8.1 JSON flag still off); and a `DEPRECATION` count of `0`.

RESULTS (2026-10-30 02:25:31 UTC, branch `5ffe92c4`, dev container):

```
W, [2026-10-30T02:25:31.915981 #84322]  WARN -- : Generating image variants require the image_processing gem. Please add `gem "image_processing", "~> 1.2"` to your Gemfile or set `config.active_storage.variant_processor = :disabled`.
"8.1.4"
true
true
[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]
I, [2026-10-30T02:25:31.973237 #84322]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=9c418ece-abae-4182-86aa-4119f2332d19 level=1 pid=84322
true
false
7.2
583
false
true
--- DEPRECATION lines in the whole output: 0 ---
```

### 3. Pre-push captures (on the host, on v665)

```bash
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 't = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-11-02 10:00").to_time; puts t; puts t.strftime("%Z"); puts t.zone.class'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
heroku run --no-tty --app insgtapi rails runner 'metadata, _accounts = Account.search(status_type: StatusType.active, name: "<a term Dan searches daily in insgt-ops>"); puts metadata.inspect'
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
curl -sS -w "\n%{http_code}\n" https://api.insightphotos.net/up.json | head -c 200
JWT='<a real JWT, copied from an insgt-ops session>'
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $JWT" https://api.insightphotos.net/orders/0
RELEASE=v665
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 3', 'release $RELEASE').deliver_now"
```

Each command on its own line (slice 2's zsh url-quote-magic lesson). **Do not run
`ActiveSupport.to_time_preserves_timezone` in any production runner** — harmless on v665, a
`RailsDeprecation` after the push.

Expected before: S4 `["Carlsbad", "Oceanside", "Leucadia"]`; S8 `2026-11-02 10:00:00 -0800`, `PST`,
`ActiveSupport::TimeZone` (slice 2's S8); S10 `7.2`; S11 the metadata hash (whatever it prints is the
"before"; S11 compares the whole hash — the `.or` sites' production read); S1 `200`, then the HTML
health page and `200` for `/up.json`; S-404 `204` (one head on 8.0.5.1); S6 the email arrives.

RECORDED (before), on v665:

```
(pending)
```

## Deploy

### 4. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

The second Rails 8.x slug on this buildpack (v663 built 8.0.5.1). Watch the build output for the gem
install (`action_text-trix` is the one new gem) and for any `assets:precompile` attempt (none
expected). A failed build is not a release; v665 stays live.

RECORDED:

```
(pending)
```

### 5. Within 30 minutes

Set `RELEASE` first. Every `heroku run … rails runner` below prints the Active Storage WARN line
before its own output (Known); it is not a failure.

```bash
RELEASE=vNNN   # the release `heroku releases -n 1` printed
heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
curl -sS -w "\n%{http_code}\n" https://api.insightphotos.net/up.json | head -c 200
heroku run --no-tty --exit-code --app insgtapi rails runner "puts Honeybadger.notify('rails upgrade slice 3 marker', error_class: 'UpgradeMarker', fingerprint: 'rails-upgrade-marker', tags: 'upgrade', context: { rails: Rails.version, release: '$RELEASE' }, sync: true).inspect"
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; p Rails.application.config.active_support.key?(:to_time_preserves_timezone)'
heroku run --no-tty --app insgtapi rails runner 't = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-11-02 10:00").to_time; puts t; puts t.strftime("%Z"); puts t.zone.class'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
heroku run --no-tty --app insgtapi rails runner 'metadata, _accounts = Account.search(status_type: StatusType.active, name: "<the same term as step 3>"); puts metadata.inspect'
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $JWT" https://api.insightphotos.net/orders/0
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 3', 'release $RELEASE').deliver_now"
```

Expected, reasoned before the push:

| # | Check | Expected |
| :-- | :-- | :-- |
| S2 | `heroku ps`, `grep Booted` | all dynos up; `Booted Rails 8.1.4 application in production environment` |
| S1 | `/up`, `/up.json` | `200`; `{"status":"up","timestamp":"…"}` and `200`; the Honeybadger uptime check green |
| S0 | marker | a notice id; `UpgradeMarker` gains an occurrence with context `rails: 8.1.4` and the real release |
| S3 | version, `to_time` key | `8.1.4`, `false` — never the reader |
| S8 | `to_time` of a Pacific value after DST ends | unchanged from step 3: `2026-11-02 10:00:00 -0800`, `PST`, `ActiveSupport::TimeZone` |
| S10 | `loaded_config_version` | `7.2` |
| S11 | `Account.search` | the same metadata hash as step 3's capture |
| S-404 | `GET /orders/0` with a real JWT | `204` — **a `500` is commit 1 not having landed** (and a `DoubleRenderError` in Honeybadger) |
| S4 | nearby cities | identical to the pre-push capture |
| S5 | Stripe | `true` |
| S6 | email | `SystemError::rails upgrade slice 3` arrives at ops@insightphotos.net |

A boot failure on any dyno is a rollback. A `RailsDeprecation` in Honeybadger within these 30 minutes
naming `to_time_preserves_timezone` means a reader call or a config line survived somewhere: rollback,
then look.

RECORDED:

```
(pending)
```

### 6. One hour after the push (S7) and the first import (S9)

```bash
heroku logs -n 1500 --app insgtapi > /tmp/s7.log
head -1 /tmp/s7.log | cut -c1-32
tail -1 /tmp/s7.log | cut -c1-32
grep -c "status=5" /tmp/s7.log
grep -oE '\] [A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)* \(' /tmp/s7.log | sort | uniq -c | sort -rn
grep -c "DoubleRenderError" /tmp/s7.log
```

Then Papertrail: `status=5` and `DoubleRenderError` from the push to one hour after it (the buffer
spans less than the hour at business-hours traffic).

Expected: no `status=5` line in the hour; no exception class other than
`ActionController::RoutingError` (scanner traffic); **`DoubleRenderError` anywhere is a finding** — a
site the enumeration missed, fixed on its own branch with the same one line, not blocking unless it is
a daily path. This watch only sees a site someone hits in the hour, which is why commit 1's enumeration
covered every head-producing method rather than relying on it. S9: the first `import_listings`
check-in after the push arrives on time — **judged in UTC** (about :36–:45 past each UTC hour; DST
ended the day before, so the local clock moved and the schedule did not).

RECORDED:

```
(pending)
```

### 7. 24 hours after the push (SH)

Honeybadger → Errors, compared with the slice 0 baseline **by error**, plus slice 1's S-DEP
`RailsDeprecation`, which is expected to be there with no new occurrence. Searches (replace the time
with the push):

```
environment:"production" created.after:"2026-11-02 09:00 UTC-8"
environment:"production" class:"RailsDeprecation" occurred.after:"2026-11-02 09:00 UTC-8"
environment:"production" class:"AbstractController::DoubleRenderError" occurred.after:"2026-11-02 09:00 UTC-8"
```

Expected: nothing new from any of the three. The 24 h before the push ran on v665 (Ruby 3.4.12), so an
error class first seen after v665's release and before this push is the Ruby bump's, not this
slice's.

- A `RailsDeprecation` naming `to_time_preserves_timezone` means a reader call survived somewhere.
  One naming `mb_chars`, `update_all`, `insert_all` or `Configurable` is an 8.1 deprecation on a path
  the suite does not reach: record its message and call site here; it is a STOP for slice 5 (OD8).
- A `DoubleRenderError` is a sixth site the enumeration did not see: fixed on its own branch, not
  blocking unless it is a daily path.
- A time-zone-shaped error is a DST suspect (Sun 11-01) before it is an 8.1 suspect.

Triage every other error the first search returns: does its backtrace touch what this slice changed —
the 13 Rails gems, `action_text-trix`, `config/`, the five setters, `head`, `/up`, `remote_ip`? Yes is
a finding. No is an old bug seen for the first time or an old error regrouped because a line moved:
record it here and fix it on its own branch; it does not block the slice.

RECORDED:

```
(pending)
```

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to v665. Nothing to undo: no migration, no ENV change, and commit 1 is a no-op on 8.0.5.1, so the
rollback needs no revert of it. The `[8.1]` header in `db/schema.rb` is a comment to the loader; v665
never reads it.

## Known, kept by decision

- **One Active Storage WARN line per process boot on 8.1.4**:
  `Generating image variants require the image_processing gem. Please add gem "image_processing" … or
  set config.active_storage.variant_processor = :disabled.` Active Storage 8.1 resolves its variant
  transformer at boot (`activestorage-8.1.4/lib/active_storage/engine.rb:94–129`) where 8.0.5.1
  loaded it only when a variant was generated; the app has no `image_processing` gem, so the
  `LoadError` is logged at `warn` once per boot. Production logs to STDOUT, so it appears on every
  dyno boot and at the top of every `heroku run … rails runner` output. Not raised, not a deprecation,
  not reported. Confirmed absent on 8.0.5.1 (production-mode boot of the pristine copy). Silencing it
  is one line (`config.active_storage.variant_processor = :disabled`) in a config file this slice does
  not otherwise touch; left for §8 item 7 (the Active Storage / `rails/all` follow-up).
- **The `to_time` line is deleted, not kept or replaced.** Rails 8.1 deprecates the setting for every
  value (reader and writer) and makes the zone behaviour unconditional; 8.2 removes the key. On 8.0 the
  deletion alone failed the boot, so it rides in the bump commit. **Slice 5a must not uncomment
  `new_framework_defaults_8_0.rb:18`** for the same reason.
- **No command may call `ActiveSupport.to_time_preserves_timezone`** on 8.1.4 — the reader
  deprecates, which in production is a `RailsDeprecation` notice. S3 and P-PROD use
  `Rails.application.config.active_support.key?(:to_time_preserves_timezone)`.
- **The trailing guards in the five setters keep their `blank?` half** although it can no longer fire
  after the new `return if performed?`; the `can_access?` half still needs the guard, and narrowing the
  condition is a refactor this upgrade does not need.
- **Two pre-existing render-after-head cases are left alone** (each a §8 item in v6):
  `OrdersController#download_files` (`orders_controller.rb:476–477`, a `DoubleRenderError` on a
  missing order on every version — the Lambda's path) and
  `NotificationAudiencesController#set_notification_audience` (`notification_audiences_controller.rb:39–40`,
  a `NoMethodError` before any second head; its fix must also guard with `performed?`).
- **`RawPhotosController#set_order` exceeds rubocop's default complexity limits** (cyclomatic 8/7,
  perceived 9/8) after commit 1's two returns. The repo has no `.rubocop.yml`, so the defaults are not
  a repo standard; `TransactionsController#set_order` was already over them.
- **`bin/rubocop` cannot run** (`.rubocop.yml` is absent; it exits 2 before and after commit 3); lint
  in the loop was `bundle exec rubocop <files>`, offence counts compared with the pristine copy.
- **Rejected from `app:update`** (the full table is in the plan): `config/ci.rb`, `bin/ci`, `bin/dev`,
  `bin/setup`, `config/puma.rb`, `config/application.rb`, `config/environment.rb`,
  `config/environments/*` (the production and test templates would undo slice 1's `:notify` and
  `:raise`), `cors.rb`, `filter_parameter_logging.rb`, and the four comment lines added to
  `content_security_policy.rb` (a file §8 item 2 deletes). `active_storage:update` copied nothing.
- **`action_text-trix` is loaded but inert**: its one initializer registers assets only when the app
  has an asset pipeline. It goes when `rails/all` is narrowed (§8 item 7).
- **`Sidekiq::Status::status(jid)` is `nil`** in development (§8 item 10); P3 asserts the Sidekiq log
  lines instead.
- **The two one-second flakes** (`account_classification_rake_spec.rb:156`, `calculator_spec.rb:965`):
  `calculator_spec.rb:965` fired once in nine full runs (after the round 1 rebuild) and passed on the
  rerun. Not this slice's; the fix is its own branch.
- **`/up` still answers HTML unless the request asks for JSON** (review round 2, Codex, should-fix,
  regraded): `railties-8.1.4/lib/rails/health_controller.rb:46–49` lists `format.html` first, so a
  request with no `Accept` or `*/*` gets the page as on 8.0; only `/up.json` or
  `Accept: application/json` gets `{"status":"up","timestamp":…}`. No client calls `/up` (grep of
  insgt-ops, insgt-app, insgt-photographers, insgt-disclosure-gallery, the Rails apps and `functions/`:
  empty) and the uptime check's condition is Success (`deploy-rails-upgrade-0.md:49`). The intended,
  documented change; S1 reads it. No spec pins railties' own controller.
- **`/up.json` is not exempt from the SSL redirect or host authorization**: `production.rb:48` and
  `:101` match `request.path == '/up'` only. Irrelevant to `https://api.insightphotos.net/up.json`
  (S1), which is HTTPS on a listed host; it matters only to a checker using plain HTTP or another
  host. Revisit with the Render cutover's health check.
- **Review rounds** (2026-10-30; Codex on an rsync copy without `.git` and `.env`, both rounds left the
  copy and the tree untouched). Round 1: the first Codex run died at model capacity before writing
  anything; the rerun on `gpt-6-sol` found no blocker or should-fix, and one nit (the spec header did
  not say which examples are regressions), fixed in commit 1 by the rebuild. Round 2: the `/up`
  should-fix above, regraded; a nit to assert empty bodies on the 204s, declined (a 204's contract is
  its status, and the regression was the 500). Claude's own findings are the Known items above (the
  WARN line, the rubocop complexity, the `/up.json` exemptions).

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed`, the release, steps 3–7's results.
- `docs/plans/rails-upgrade-slice-3.md`: Status `Deployed`.
- `rails-upgrade.md`: §4.4's "as deployed" line, §6's calendar as it went (the v6 amendment itself is
  written before the push).

## Deploy log

- **2026-10-30 — implemented and verified in development** (branch `chore/rails-upgrade-slice-3`,
  `a5bfab70`…`5ffe92c4` off `master` f86877f5): step 1's table; P-PROD as step 2's RESULTS; Dan's 8.1
  dump (two hunks, committed as `5ffe92c4`) and round-trip load (empty diff).
