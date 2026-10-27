# Runbook: Rails Upgrade Slice 2 — 8.0.5.1, transit only

**Last updated:** 2026-10-27
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~30 min on the morning; S7 one hour after the push; S9 at the first hourly
import; SH 24 h later
**Status:** Ready — implemented and verified in development; reviewed (two rounds); waiting on the
Prerequisites

## Summary

Ships `docs/architecture/rails-upgrade.md` §4.3 (v4; v5 amends it after verification — see
`docs/plans/rails-upgrade-slice-2.md` for every deviation and why). Branch
`chore/rails-upgrade-slice-2`, five commits off `master` 473e2747 (production v662):

1. `671c3c6b` fix: drop the custom actions from the carts and headshots route filters —
   `config/routes.rb:6, :19` lose `request_shoot` and `upload_url` from their `only:` lists. Rails 8.0
   raises `ArgumentError` at route load for them; the actions are declared in the member blocks, so
   the route table is unchanged (583 routes, byte-identical to `master`). The contract examples pin
   recognition, the carts `format: 'json'` default and the two URL helpers (review round 1).
2. `df0e12ec` fix: preserve the receiver zone in to_time —
   `config.active_support.to_time_preserves_timezone = :zone` in `config/application.rb`, directly
   under `load_defaults 7.2`. Inert on 7.2.4 (reads as `true`); the behaviour arrives with commit 3.
3. `df7826c5` build: upgrade rails to 8.0.5.1 — the 13 Rails gems 7.2.4 → 8.0.5.1; `cgi (0.5.1)`
   leaves the lock and actionpack's `racc` edge goes (`racc (1.8.1)` stays through other gems);
   actionpack's `rack < 3.3` cap and activesupport's `connection_pool`/`minitest` caps lifted; a
   `uri (>= 0.13.1)` constraint added; nothing else moves (`minitest` stays 5.27.0).
4. `f1b2af6e` chore: apply the rails 8.0 app:update binstubs — `bin/rails`, `bin/rake` (quotes only).
5. `4b464230` chore: add the rails 8.0 framework defaults shim —
   `config/initializers/new_framework_defaults_8_0.rb`, all three lines commented.

(The branch was rebuilt once after review round 1 to fold a spec strengthening into commit 1 and
correct commit 3's body; the pre-review hashes `84543d51`…`df6759e3` are gone. The tree is identical.)

**No migration, no ENV change, no client release.** `config.load_defaults` stays `7.2`. The three
Active Storage migrations in `db/migrate/` predate this slice (tracked since 2026-01-29, run in
production) and are untouched; `app:update` copied nothing.

**Production is v662** (`473e2747`, 2026-10-27 08:15:19 -0400, slice 1). The branch is cut from it.
If `master` moves before the push, merge `master` into the branch, rerun the suite on the merge, and
move the "before" captures and the rollback target to the new release.

**What moves for a human.**
- `to_time` on a zoned value now carries the receiver's time zone instead of a fixed offset (§5 R3,
  step two): `Time#zone` is the `ActiveSupport::TimeZone`, `strftime('%Z')` reads `PST`/`PDT`, and
  arithmetic across 2026-11-01 keeps the wall clock (`2026-10-31 10:00 -0700 + 2.days` →
  `2026-11-02 10:00 -0800`; before the change `-0700`). No `.to_time` in `app/` or `lib/`; the four
  boundary specs pass. Symptom if a gem path disagrees: an order on the wrong day in insgt-ops, with no
  exception. S4, S6 and S8 are the reads.
- **Not** a change of this slice, although §4.3 lists them: the autosave narrowing ("no longer
  validated unmodified associated records") and the `#merge` with `#or` SQL fix were backported to
  **7.2.3** (activerecord 7.2.4 `CHANGELOG.md`, the 7.2.3 section, lines 275 and 124), so production
  has run both since the app moved to 7.2.3. Review round 1 (Codex) caught the plan's claim; v5
  corrects §4.3's breaking-change list.
- Nothing else client-visible: the route table is identical; the camelCase-to-snake_case parameter
  paths do not use the method 8.0.3 changed (`HashWithIndifferentAccess#transform_keys!`); the 24
  rspec-rails `:unprocessable_entity` warnings are the matcher's own and unchanged.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. The
production-config probe (Pre-deploy, step 2) runs in `apps/insgt-api` on the branch, wherever Dan
runs it. The Honeybadger dashboard is the web UI.

## Deploy window

Mon–Wed, 09:00–11:30 Pacific, outside the 08:00 and 12:00 delivery windows (§2.4). Planned for
**Wed 2026-10-28, 09:00–11:30 Pacific**, after slice 1's SH closes at 05:15 PT (08:15 ET).

**Slippage rule (§6, OD1), stated here on purpose:** if review and merge are not complete by 09:00 PT,
the deploy moves to **Mon 2026-11-02** and slice 3 loses that slot (it then takes Tue 11-03 or Wed
11-04, still ahead of 8.0's EOS on Sat 11-07). **Nobody pushes after 11:30 to make the window.**

## Prerequisites

- [ ] **Slice 1's SH result** (`deploy-rails-upgrade-1.md` step 7, closes 2026-10-28 05:15 PT) is
      recorded there and here: ______ (one line: the errors the window showed and their triage; a
      `RailsDeprecation` other than S-DEP's is a STOP for this push under OD8)
- [ ] Review rounds complete (two rounds of `predeploy-review-rails`, Codex second opinion included);
      this runbook's Status is `Ready`
- [ ] Dan has merged `chore/rails-upgrade-slice-2` into `master` and `bundle exec rspec` is green
      **on the merge**: expected 2,045 examples, 0 failures, 0 `DEPRECATION WARNING` lines if `master`
      is still 473e2747; a different count is sourced before the push, not recomputed
- [ ] The production-config probe (step 2) printed the expected lines on the merge
- [ ] Pre-push captures (step 3) recorded below, on the release that is live at that moment

## Pre-deploy

### 1. Development verification — done 2026-10-27 (Deploy log)

P1 (twice), P2–P8, P-PROD, the route diff; all pass. Modification E (a scratch Heroku app for the
first 8.x slug): no scratch app or review-app pipeline is documented for `insgtapi` (the README and
`docs/` name only the production app and the Angular staging hosts), so the build is proved by the
release itself (§2.5). A failed build never becomes a release; v662 keeps running.

### 2. The production-config probe (Dan, on the merge, before the push)

Slice 1's wrapper, extended by two lines. `HONEYBADGER_REPORT_DATA=false` is honoured by the gem
(ENV beats `config/honeybadger.yml`, notes "Honeybadger — gem source"; the output below shows
`report_data` `false`), so the probe's own deprecation reaches the `Backend::Null` and never
production's Honeybadger.

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
  p ActiveSupport.to_time_preserves_timezone
  p Rails.application.config.loaded_config_version
  p Rails.application.routes.routes.count
  p Honeybadger.config[:report_data]
' 2>&1 | tee /tmp/p-prod.log; grep -c DEPRECATION /tmp/p-prod.log
```

Expected, in order: `true`, `true`, `[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]`
(**the load-bearing line** — anything else is a finding), the gem's `Reporting error` log line,
`true`, **`:zone`** (the 8.0 flip took, before any initializer), `7.2` (`load_defaults` untouched),
`583` (the routes drew in a production boot), `false` (reporting off), and a `DEPRECATION` count of
`0` (the probe's own warning goes through `:notify`, not stderr). A `DEPRECATION WARNING` about
`to_time` means the `:zone` line is not where it must be.

RESULTS (2026-10-27 15:39:42–43 UTC, branch `df6759e3`, dev container):

```
true
true
[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]
I, [2026-10-27T15:39:43.875736 #54824]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=cf079727-d976-4db2-89ca-0c49c9c78cd8 level=1 pid=54824
true
:zone
7.2
583
false
--- DEPRECATION lines in the whole output: 0 ---
```

### 3. Pre-push captures (on the host, on v662)

```bash
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 't = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-11-02 10:00").to_time; puts t; puts t.strftime("%Z"); puts t.zone.class'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
curl -sS -o /tmp/s-rt-carts.txt -w "%{http_code}\n" -X POST https://api.insightphotos.net/carts/0/request_shoot; head -1 /tmp/s-rt-carts.txt
curl -sS -o /tmp/s-rt-headshots.txt -w "%{http_code}\n" https://api.insightphotos.net/headshots/0/upload_url; head -1 /tmp/s-rt-headshots.txt
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 2', 'release v662').deliver_now"
```

Expected before: S4 `["Carlsbad", "Oceanside", "Leucadia"]` (slice 1's capture); S8 `2026-11-02
10:00:00 -0800`, an **empty** line (`%Z` of a fixed-offset `Time`), `NilClass` (the development
runner on 7.2.4 printed exactly these); S10 `7.2`; S-RT the unauthenticated status **and the first
body line** of both routes (ASSUMPTION `401` with the API's JSON error body; whatever they print is
the "before"); S6 the email arrives. The two S-RT captures are the proof that the routes survive the
upgrade: after the push a `404` means the route is gone, and the body line separates the auth layer
from a generic rescue.

RECORDED (before):

```
(fill in before the push)
```

## Deploy

### 4. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release (vNNN) and its time
```

The first Rails 8.x slug on this buildpack (§2.5 UNVERIFIED). Watch the build output for the gem
install and for any `assets:precompile` attempt (none expected: the task does not exist). A failed
build is not a release; v662 stays live.

RECORDED:

```
(release and time)
```

### 5. Within 30 minutes

Set `RELEASE` first — slice 1's S0 and S6 went out with the literal `<vNNN>`.

```bash
RELEASE=v663   # the release `heroku releases -n 1` printed
heroku ps --app insgtapi
heroku logs --ps backgroundworker.1 -n 300 --app insgtapi | grep Booted
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
heroku run --no-tty --exit-code --app insgtapi rails runner "puts Honeybadger.notify('rails upgrade slice 2 marker', error_class: 'UpgradeMarker', fingerprint: 'rails-upgrade-marker', tags: 'upgrade', context: { rails: Rails.version, release: '$RELEASE' }, sync: true).inspect"
heroku run --no-tty --app insgtapi rails runner 'puts Rails.version; puts ActiveSupport.to_time_preserves_timezone.inspect'
heroku run --no-tty --app insgtapi rails runner 't = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-11-02 10:00").to_time; puts t; puts t.strftime("%Z"); puts t.zone.class'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
curl -sS -o /tmp/s-rt-carts-after.txt -w "%{http_code}\n" -X POST https://api.insightphotos.net/carts/0/request_shoot; head -1 /tmp/s-rt-carts-after.txt
curl -sS -o /tmp/s-rt-headshots-after.txt -w "%{http_code}\n" https://api.insightphotos.net/headshots/0/upload_url; head -1 /tmp/s-rt-headshots-after.txt
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 2', 'release $RELEASE').deliver_now"
```

Expected, reasoned before the push:

| # | Check | Expected |
| :-- | :-- | :-- |
| S2 | `heroku ps`, `grep Booted` | `web.1`, `web.2`, `backgroundworker.1` up; `Booted Rails 8.0.5.1 application in production environment` |
| S1 | `curl /up` | `200`; the uptime check green |
| S0 | marker | a notice id; `UpgradeMarker` gains an occurrence with context `rails: 8.0.5.1` and the real release |
| S3 | version, `to_time` setting | `8.0.5.1`, `:zone` |
| S8 | `to_time` of a Pacific value after DST ends | `2026-11-02 10:00:00 -0800`, `PST`, `ActiveSupport::TimeZone` (before: the same first line, an empty line, `NilClass`) |
| S10 | `loaded_config_version` | `7.2` |
| S-RT | both routes | the same status and first body line as the v662 captures; **`404` on either is a finding** |
| S4 | nearby cities | identical to the pre-push capture |
| S5 | Stripe | `true` |
| S6 | email | `SystemError::rails upgrade slice 2` arrives at ops@insightphotos.net |

A boot failure on any dyno is a rollback. A `RailsDeprecation` in Honeybadger within these 30 minutes
that mentions `to_time` means the 7.2 value reached the writer in production: rollback, then look.

Recorded:

```
(paste)
```

### 6. One hour after the push (S7) and the first import (S9)

```bash
heroku logs -n 1500 --app insgtapi > /tmp/s7.log
head -1 /tmp/s7.log | cut -c1-32; tail -1 /tmp/s7.log | cut -c1-32
grep -c "status=5" /tmp/s7.log
grep -oE '\] [A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)* \(' /tmp/s7.log | sort | uniq -c | sort -rn
```

Then Papertrail: `status=5` from the push to one hour after it (the 1,500-line buffer spans about
25 minutes, not the hour — slice 1's finding).

Expected: no `status=5` line in the hour; no exception class in the buffer other than
`ActionController::RoutingError` (scanner traffic); any other class is a finding, triaged before S7
passes. S9: the first `import_listings` check-in after the push arrives on time (about :36–:45 UTC).

Recorded:

```
(paste)
```

### 7. 24 hours after the push (SH)

Honeybadger → Errors, compared with the slice 0 baseline **by error** (slice 1's amendment), plus
slice 1's S-DEP `RailsDeprecation`, which is expected to be there with no new occurrence. Two searches
(replace the time with the push):

```
environment:"production" created.after:"2026-10-28 <push time> UTC-7"
environment:"production" class:"RailsDeprecation" occurred.after:"2026-10-28 <push time> UTC-7"
```

Expected: the first returns nothing new (the S0 marker and S-DEP's error carry their own fingerprints
and predate the window as errors). The second returns nothing: a `RailsDeprecation` occurring after the
push is a deprecation on a path the suite does not reach, on 8.0.5.1 — record its message and call
site here; one that `:raise` would trip in the suite is a STOP for slice 3 (OD8).

Triage every other error the first search returns: does its backtrace touch what this slice changed?
That is the 13 Rails gems, `config/application.rb`, `config/routes.rb`, the two binstubs, or a
behaviour under "What moves for a human" above. Yes is a finding. No is an old bug seen for the
first time or an old error regrouped because a line moved: record it here and fix it on its own
branch; it does not block the slice.

## Rollback

```bash
heroku rollback --app insgtapi
```

Back to v662. Nothing to undo in data: no migration, no ENV change. `to_time` reverts to the offset
behaviour with the old slug.

## Known, kept by decision

- **`:zone` is set in `config/application.rb`, not in the 8.0 shim.** Active Support's `set_configs`
  initializer forwards the key to the writer before `config/initializers` run, and the 8.0 writer
  deprecates every value but `:zone`; with the shim's line alone the test environment fails to boot
  under `:raise` and production would report a `RailsDeprecation` on every boot. The shim is committed
  as generated, every line a comment, for slices 5a and 5b. Slice 3's survey decides whether the
  application.rb line is deleted, kept or replaced on 8.1.
- **`Time#zone` is the `TimeZone` object, not `"PST"`.** §4.3's spec plan and S8 said `"PST"`; the
  abbreviation is `strftime('%Z')`. Corrected in v5.
- **The three Active Storage migrations stay** (`db/migrate/20260122184539..41_*.active_storage.rb`,
  tracked since `e66411cf`, versions present in production's `schema_migrations`, no tables). §4.3
  expected `app:update` to copy them fresh; it skipped them by name. Deleting tracked, already-run
  migrations is a `db/migrate` change no slice carries.
- **Rejected from `app:update`** (the full diff is in the plan): `config/application.rb`,
  `config/environment.rb`, `config/environments/*` (the production and test templates would undo slice
  1's `:notify` and `:raise`), `cors.rb`, `filter_parameter_logging.rb`, `config/puma.rb` (adds a
  `solid_queue` plugin line — not comment-only), `bin/dev`, and `bin/setup` (its tail execs the rejected
  `bin/dev`; nothing in `.devcontainer/` or the README calls `bin/setup`).
- **`GET /rails/info/notes`** is the one route 8.0 adds to the internal set; development-only, not in
  `bin/rails routes`, not in a production boot (583 there).
- **`bin/rubocop` has no configuration in this tree** (`.rubocop.yml` is gitignored and absent), so
  the lint step was `ruby -c`-level only; the review rounds cover style.
- **`Sidekiq::Status::status(jid)` is `nil`** in development (§8 item 10); P3 asserts the Sidekiq log
  lines instead.
- **The two one-second flakes** (`account_classification_rake_spec.rb:156`,
  `calculator_spec.rb:965`) did not fire in any of the six full runs today.
- **`config/sidekiq_status.rb` is never loaded** (review round 1, Codex, should-fix): nothing requires
  it, so the sidekiq-status middleware is not installed and `Sidekiq::Status::status` reads `nil`.
  Pre-existing and unchanged by the upgrade — §8 item 10 already carries it; not fixed in an upgrade
  commit.
- **`StringUtils.urlify` behaves identically on 7.2.4 and 8.0.5.1** (review round 1 asked for a smoke
  check of the 2012 gem): UTF-8 input converts, a BINARY-tagged string raises
  `Encoding::CompatibilityError` on both versions, and the address strings it receives from the
  database are UTF-8. The gem also strips capital letters; that is how it has always behaved.
- **The `OrderProcessingNote` named in `config/application.rb`'s Active Storage comment is a decided
  design** (`docs/plans/order-processing-note.md`), not a model; Codex read the comment as stale. It is
  slice 1's comment and is correct.

## After the deploy — write-back (platform repo)

- This runbook: Status `Deployed <date>`, the release, steps 3–7's results, slice 1's SH line.
- `rails-upgrade.md` v5: slice 1 recorded as deployed (v662) with its S7 and SH criteria (§4.0 S7, §2.2
  and the SH row by Honeybadger error, §4.1 item 7, §5's intro, §4.0 S4 `map`); §4.3 as built — the
  `:zone` placement (gap 1 and item 2's table), the routes change in the breaking-change list, the
  Active Storage migrations row, `bin/setup` and `puma.rb` rejected, `Time#zone` as an object and the
  S8 rewrite, the lock diff's `cgi`/`racc`/`uri` lines, the `transform_keys` correction, the
  `application.rb` template keeping `load_defaults 7.2`, the commit order; §4.4 item 3 reworded (slice
  3's survey decides the line's fate — modification F) and its trap 1; §6 the calendar (slice 2 on Wed
  10-28; slice 3 free to take Mon 11-02); the slice 2 prompt's out-of-scope item 2 and trap 1.
- `rails-upgrade-codebase-notes.md`: the rows the plan's "Codebase notes" table corrects, plus the
  slice 2 section (`application.rb:13–20`, the shim, `routes.rb:6, :19`, `lib/crud_attribution.rb`,
  the 8.0.5.1 `railtie.rb:99–103, 125–130` ordering, `mapper.rb:1182–1186`).
- `docs/plans/rails-upgrade-slice-2.md`: Status `Deployed`.

## Deploy log

- 2026-10-27: **implemented and verified in development** (dev restore; branch head `df6759e3` before
  review round 1, `4b464230` after the rebuild — the same tree plus two spec assertions; five commits
  off `master` 473e2747). Each commit red → green → deliberate break → area suite; the evidence is in
  the plan's Approach section as run:
  - Commit 1: the two member-route examples green on 7.2.4 before the change (they guard the routes,
    not the symbols); route table identical (583); break (member route commented out) →
    `ActionController::RoutingError: No route matches "/carts/1/request_shoot"`; area suite
    (`spec/architecture` + `spec/requests`) 654 examples, 0 failures.
  - Commit 2: the setting example red (`expected: :zone, got: true`), green with the line, red again
    with the line commented out; on 7.2.4 `to_time` unchanged (`-0800`, `zone=nil`); full suite 2,042
    examples, 0 failures, 0 deprecation lines.
  - Commit 3: floor, zone and DST examples red on 7.2.4 (`7.2.4`; `zone` `nil`; `-25200`); lock
    byte-identical to the scratch resolution; green on 8.0.5.1 (10 examples). Evidence (a) with
    `request_shoot` restored in the filter: `ArgumentError: Route `resources :carts` - :only and :except
    must include only [:index, :create, :new, :show, :update, :destroy, :edit], but also included
    [:request_shoot]`; (b) with the application.rb line at `:offset`: `railtie.rb:128 … DEPRECATION
    WARNING: `to_time` will always preserve the full timezone rather than offset of the receiver in
    Rails 8.1 … (ActiveSupport::DeprecationException)` at boot; (c) `DateAndTime::Compatibility.preserve_timezone = :offset`
    in an `around` (silent on 8.0.5.1 — modification A, confirmed first): `4 examples, 3 failures`, all
    by expectation (`:zone` setting, `converted.zone`, the DST sum), the offset example still green;
    floor break `8.0.6` → red. Full suite **2,044 examples, 0 failures**, 0 deprecation lines, plain and
    `CI=1`; `zeitwerk:check` clean; route table identical.
  - Commit 4: `bin/rails`/`bin/rake` hunks identical to the `app:update` diff; `bin/rails --version` →
    `Rails 8.0.5.1`.
  - Commit 5: the defaults-off example green before and after the shim (identical to the 8.0.5.1
    template); break (`strict_freshness = true` uncommented) → `expected false, got true`; contract
    spec 11 examples, 0 failures.
  - **P1**: `2045 examples, 0 failures` (68.1 s), `grep -c "DEPRECATION WARNING"` → `0`, 24 rack
    warnings; `CI=1`: `2045 examples, 0 failures` (65.0 s), `0` deprecation lines. (The plan's
    estimate was 2,045; the count is reported, not a criterion — modification G.)
  - **P2**: `zeitwerk:check` → "Otherwise, all is good!" (the `lib/` notice as on `master`).
  - **P3**: own queue `slice2_p3`; `Booted Rails 8.0.5.1 application in development environment`;
    property 1964 → `start` → `[PropertyDataLookupWorker] Property#1964 already has property data,
    skipping` → `done` (0.23 s); `Sidekiq::Status::status(jid)` → `nil` (recorded, §8 item 10).
  - **P4**: 4 examples, 0 failures. **P5**: 86 examples, 0 failures. **P6**: `SystemError::rails
    upgrade`. **P7**: 122 examples, 0 failures. The four R3 boundary specs: 39 examples, 0 failures.
  - **P8**: photo 659058 → `d2e08hhdrjhri.cloudfront.net`, `200`, `image/jpeg` (`Net::HTTP`).
  - **Routes**: `bin/rails routes` identical to `master` (583 lines); `grep -c active_storage` → `0`.
  - **P-PROD**: step 2's RESULTS above (15:39:42–43 UTC; `report_data` `false`; 0 `DEPRECATION`).
  - Development runner on the branch: `8.0.5.1`, `:zone`, `7.2`, `2026-11-02 10:00:00 -0800`, `PST`,
    `ActiveSupport::TimeZone`.
  - **Review round 1** (`predeploy-review-rails`; Codex 0.163.0 on an rsync copy without `.git` or
    `.env`, the diff supplied as a file, read-only orders; the copy stayed identical to the tree).
    Claude: no blocker, no should-fix (no app code, migration, Sidekiq signature, serializer or ENV
    changes; the four slice traps clear). Codex: **no blocker introduced by this slice**; one
    should-fix, `config/sidekiq_status.rb` never loaded [codex] — pre-existing, §8 item 10, out of
    scope; two nits on the contract spec [codex]: the route examples did not cover the carts
    `format: 'json'` default or the URL helpers — **fixed**, folded into commit 1 (red shown again with
    the member route commented out: `RoutingError`); the inherited Active Storage absence example could
    pass on an empty route set — **declined**: the member-route examples already fail on an empty route
    set (the request spec's 404 would not — round 2's correction); noted for slice 3's contract-spec
    touch. Two factual corrections Codex prompted,
    both verified against the installed gems [claude+codex]: `racc (1.8.1)` stays in the lock (commit
    3's body reworded); the autosave and `#merge`/`#or` fixes are in 7.2.3, not new here (this runbook
    and the plan corrected; v5 corrects §4.3). Already-intentional: the `OrderProcessingNote` comment.
    Codex also asked for a `StringUtils.urlify` smoke — run on both versions, identical (Known).
    After the rebuild, on `4b464230`: contract spec 11 examples, 0 failures; P1 plain `2045 examples,
    0 failures` (65.6 s), `CI=1` `2045 examples, 0 failures` (68.0 s), 0 deprecation lines in both,
    24 rack warnings; route table identical to `master`.
  - **Review round 2** (same setup, fresh copy of `4b464230`; copy identical to the tree afterwards).
    Codex: **no blocker or should-fix**; the one nit is round 1's inherited route-absence example
    again, declined for the same reason; it confirms round 1's dispositions — the `:zone` placement,
    the 7.2.3 backports, the `racc` correction, the untouched migrations — and corrects one sentence of
    round 1's record (the request spec's 404 does not detect an empty route set; the member-route
    examples do). Claude: nothing new. Status → `Ready`.
