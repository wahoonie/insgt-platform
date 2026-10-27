# Rails Upgrade — insgt-api 7.2.3 → 8.1.4

**Repo:** `insgt-api` · **Platform:** Heroku app `insgtapi` (Render.com cutover follows, §2)
**Status:** v5 — slice 0 deployed (v659, 2026-10-26); slice 1 deployed (v662, 2026-10-27 08:15 -0400;
S7 and S9 pass, SH closes 2026-10-28 05:15 PT); slice 2 implemented, verified and reviewed (two rounds)
on 2026-10-27, deploy planned Wed 2026-10-28 09:00–11:30 PT; OD10 open
**Version:** 5 · **Last updated:** 2026-10-27
**Supersedes:** v4 (2026-10-26). See §9.
**Companion files:** `rails-upgrade-codebase-notes.md` (the `file:line` map; every repo claim below
is sourced there), `rails-upgrade-slices/slice-{0,1,2,3,4,5}.md` (the slice prompts), and the
contract spec `insgt-api/spec/architecture/rails_upgrade_spec.rb` (created by slice 1; later slices
append to it).

**How to read this document.** Facts are stated with their source (a `file:line`, a rubygems
dependency line, a Rails branch file, a dated page). Assumptions and estimates are labelled as
such. `UNVERIFIED` marks a claim no source settled. Decided questions are recorded in §7 with the
section that carries them; the two still-open ones are marked. Slice prompts cite section numbers;
they do not restate rules.

---

## 1. Target and path

### 1.1 Where the app is

| Fact | Value | Source |
| :-- | :-- | :-- |
| Rails | **7.2.3** | `Gemfile.lock:378`; `Gemfile:28` `'~> 7.2.0'` |
| Framework defaults | `config.load_defaults 7.2` | `config/application.rb:12` |
| Ruby | 3.4.10 | `.ruby-version`, `Gemfile:4`, `Gemfile.lock:865` |
| Bundler | 4.0.4 | `Gemfile.lock:868` |
| App shape | `config.api_only = true`; `require 'rails/all'` | `config/application.rb:36, 3` |
| Database | PostgreSQL 15 (dev 15.18, Heroku essential-1 15.17); extensions `plpgsql`, `pg_stat_statements`; **no PostGIS** | `bin/rails runner` on 2026-10-23; `config/initializers/strong_migrations.rb:11–12`; `db/schema.rb:15–16` |
| Error tracking | none in the repo (a `config/newrelic.yml` without a gem); README names Papertrail and New Relic add-ons from 2015 | `Gemfile.lock`; `README.md:140–141` |
| Deprecation baseline | 1997 examples, 0 failures, 66.1 s; **one** Rails deprecation (`new_framework_defaults.rb:17`); 24 rack `:unprocessable_entity` warnings from rspec-rails | full suite 2026-10-23 15:50 UTC (notes, "Specs and support files") |
| Autoloading | `bin/rails zeitwerk:check` clean | 2026-10-23 |

### 1.2 The path

| Stop | Version | Released | What it is | Source |
| :-- | :-- | :-- | :-- | :-- |
| Slice 0 | — | — | the `honeybadger` gem, 6.10.0 (2026-10-21), the one gem added outside `rails` (§2.6, §3.1) | rubygems compact index |
| Slice 1 | **7.2.4** | 2026-09-24 | "this is the last release of the 7.2.x series" | rubygems; rubyonrails.org/2026/9/24/Rails-Version-7-2-4-has-been-released |
| Slice 2 (transit) | **8.0.5.1** | 2026-07-29 | newest 8.0; the CVE-2026-66066 patch release | rubygems; rubyonrails.org/2026/7/29 ("7.2.3.2, 8.0.5.1, and 8.1.3.1") |
| Slice 3 (landing) | **8.1.4** | 2026-09-24 | newest Rails release of any series | rubygems; rubyonrails.org/2026/9/24/Rails-Version-8-1-4-has-been-released |
| Slice 4 | — | — | `belongs_to` optionality follows column nullability; the Rails 5.0 shim's global `false` goes | §4.5 |
| Slice 5 | — | — | the 8.0 and 8.1 framework defaults, then `config.load_defaults 8.1` | §4.6 |

Rails **8.2 does not exist** as a release (rubygems lists no 8.2.x; only edge guides mention it), so
8.1.4 is the landing target and 8.0 is the single intermediate minor.

**Ruby requirements** (rubygems compact index): 7.2.4 `>= 3.1.0`; 8.0.5.1 and 8.1.4 `>= 3.2.0`;
honeybadger 6.10.0 `>= 3.0.0`. 3.4.10 satisfies all. **The Ruby version does not change** (§2.6).

**Dependency lines that force lockfile movement** (compact index, read 2026-10-23):
activesupport 7.2.4 pins `minitest >= 5.1, < 6` (the lock has 6.0.1 — slice 1 downgrades it, which
is harmless: the suite is RSpec and minitest is only rails-dom-testing's dependency); 7.2.x keeps
actionpack `rack >= 2.2.4, < 3.3`, 8.0.5.1 and 8.1.4 drop the cap (rack stays 3.2.4 unless
updated); 8.1.4's activesupport adds `json` and drops `benchmark` (the Gemfile lists `benchmark`
explicitly, so the lock keeps it); 8.x no longer depends on `cgi`/`racc`. honeybadger 6.10.0 adds
only `logger` and `ostruct`, both already locked.

### 1.3 Support dates and what they imply

Verbatim from rubyonrails.org/maintenance (read 2026-10-23):

| Series | Bug fixes | Security fixes |
| :-- | :-- | :-- |
| 8.1.x | "Supported until October 10, 2026" | "Supported until October 10, 2027" |
| 8.0.x | "Supported until May 7, 2026" | "Supported until November 7, 2026" |

Rules on the same page: "Minor releases will receive bug fixes for one year after the first release
in its series" / "security fixes for two years after the first release in its series"; and "In the
rare case where no release was made in one year, we will extend the support period for the previous
release." (8.1.0 shipped 2025-10-22 and 8.2 has not shipped; the page's 8.1 dates do not equal
8.1.0 + 1y/2y — quoted as published, not reconciled. Fact: the dates above; UNVERIFIED: how they
were computed.)

Implications:
- 7.2.x has had no security support since 2026-08-09 (the October 2025 release post); 7.2.4 is a
  courtesy final release, not a return to support. Slice 1 is a stepping stone, not a resting place.
- 8.0.x loses security support on **Sat 2026-11-07**. Slice 3 (8.1.4) must be in production before
  that; §6 places it on Wed 2026-11-04.
- On 8.1.4 the app is on the only series with security support beyond 2026-11-07. As of today 8.1 is
  already past its stated bug-fix window, so future 8.1.x releases will be security-only.
- **The next bump is 8.2**, when it ships. Two things gate it now: zipline's `actionpack < 8.2` cap
  (§3) and rspec-rails' unreleased 8.2 fixes. Both are §8 items, not part of this upgrade.

---

## 2. Sequencing

These rules are settled; slice prompts cite this section.

1. **The entire upgrade executes now, on Heroku, before any Render infrastructure work begins.**
   It is code-only and reverts in seconds (`heroku rollback`, or `git revert` + push); the Render
   cutover needs a maintenance window and a database restore. The reversible change goes first, on
   known infrastructure, so any regression is unambiguously attributable.
2. **The upgraded app must be deployed and quiet in production for at least one week before the
   Render database-restore rehearsal.** The rehearsal exercises the code that will cut over, so
   that code must be final by then. **"Quiet" means: no Honeybadger error that was not in the slice 0
   baseline** — compared by error, not by class (v5, from slice 1's SH: the baseline holds
   `NoMethodError`, and a removed API surfaces as exactly that; Honeybadger groups by file, method,
   line, class and component, or by a supplied fingerprint; §4.0 SH states the triage), plus no
   Sidekiq crash loop and no missed `import_listings` check-in.
3. **8.1.4 is the landing target; 8.0.5.1 is a waypoint.** Slice 2's exit criterion is a green
   build and a clean deploy; no soak, no feature work, no deploy freeze.
4. **Deploy each slice on a weekday morning** — Monday, Tuesday or Wednesday, 09:00–11:30 Pacific —
   never inside the delivery windows (08:00, 12:00, 17:00, 20:00 Pacific) and never Thursday or
   Friday.
5. **Deploy = `git push heroku master` from the Mac** (the Heroku CLI is not in the dev container;
   `git remote heroku` → `https://git.heroku.com/insgtapi.git`; insgt-api's deploy branch is
   `master`, the default of both `origin` and `heroku`). **Revert = `heroku rollback`**. No slice
   carries a migration (§4), so there is no schema to roll back, no release phase, and no
   maintenance window — the README's deploy recipe (`README.md:160–167`, `heroku maintenance:on`,
   `db:migrate`) is for migrating deploys and does not apply here. UNVERIFIED: that the Heroku Ruby
   buildpack builds a Rails 8.x slug exactly as it builds the 7.2 one for an app with no
   `assets:precompile` task (expected: the task does not exist on either version, so the buildpack
   skips it); the slice 2 release is the proof.
6. **Constants across every slice:** Ruby 3.4.10, PostgreSQL 15, `StrongMigrations.target_version = 15`
   (`config/initializers/strong_migrations.rb:18`), `config.load_defaults 7.2` until slice 5b, and
   **no gem added or major-bumped other than `rails` itself and `honeybadger`** (added once, in
   slice 0). A survey finding that genuinely breaks this ordering is recorded in §7, never silently
   reordered.
7. **The documents reach the slices through the platform repo.** This document, its notes and the
   slice prompts live in `insgt-platform/docs/architecture/` (where every design document lives —
   `insgt-platform/CLAUDE.md:11`, "it tracks only `.claude/`, `.devcontainer/`, `docs/`"), on branch
   `docs/rails-upgrade`, cut from and based on the platform repo's `main` (its `origin/HEAD`). After
   Phase 2's three commits and the engineer's review, `docs/rails-upgrade` merges into `main`
   **before slice 0 starts on Mon 2026-10-26**, so every slice session reads the approved contract
   at `/workspace/docs/architecture/`. insgt-api's `master` never carries these files; a slice
   branch in insgt-api cites them by path.

---

## 3. Blockers and resolutions

### 3.1 Dependency audit

Every gem that constrains or hooks Rails, from `Gemfile.lock` and the rubygems compact index
(2026-10-23). "OK" means the locked version resolves at that Rails version without a bump.

| Gem (locked) | Rails constraint | 7.2.4 | 8.0.5.1 | 8.1.4 | Resolution |
| :-- | :-- | :-- | :-- | :-- | :-- |
| **honeybadger 6.10.0** (added, slice 0) | none; runtime deps `logger`, `ostruct`; docs: Ruby `>= 2.7.0`, Rails `>= 5.2`, Sidekiq "any" | OK | OK | OK | The one gem added outside `rails` (§2.6). Its railtie must survive every later slice (§5 R1); §4.0's S0 marker proves it after each deploy |
| zipline 2.2.0 | actionpack `>= 6.0, < 8.2` | OK | OK | OK | None now. Caps the **next** bump: zipline has bumped its cap one minor at a time (2.1.0 `< 8.1` 2025-10-03, 2.2.0 `< 8.2` 2025-10-25); either a new release or the `zip_tricks` replacement noted at `Gemfile:39` precedes 8.2 (§8) |
| sidekiq 7.3.10 (`~> 7.0`) | none; rack `>= 2.2.4, < 3.3`, redis-client | OK | OK | OK | **Keep through the upgrade** (decided, OD5): prior Heroku Redis host issues; Sidekiq 8 waits for the Render cutover (§8). The gemspec is unconstrained; Changes.md names Rails only in 7.3.3 ("Take over support for ActiveJob's `:sidekiq` adapter") and 7.3.9 ("Only require activejob if necessary"); v7.3.10's own Gemfile tests `~> 7.1`. **UNVERIFIED by changelog; verified by P3 (a job runs end to end) in slices 1–3.** The app does not use Active Job |
| sidekiq-status 4.0.0 | sidekiq `>= 7, < 9` | OK | OK | OK | None; no Rails hooks in its `lib/`. Its status record is what P3 asserts |
| rspec-rails 8.0.4 | actionpack/railties `>= 7.2` | OK | OK | OK | None; its unreleased changelog already targets 8.2 |
| shoulda-matchers 7.0.1 | activesupport `>= 7.1` | OK | OK | OK | None; 7.0.0 (2025-10-31): "Add support for Rails 8", "Add Rails 8.1 support" |
| strong_migrations 2.8.0 | activerecord `>= 7.2` | OK | OK | OK | None; 2.0.2: "Fixed migrations not running with Active Record 8 rc2". `target_version` stays 15 |
| jbuilder 2.14.1 | actionview `>= 7.0` | OK | OK | OK | None (UNVERIFIED: its CHANGELOG could not be fetched; 2.15.1 exists; the gem is maintained in the rails org) |
| lograge 0.14.0 | `>= 4` | OK | OK | OK | None required; 0.15.0 "Test and support Rails 7.2, 8.0, and 8.1" is an optional minor bump (§8) |
| factory_bot_rails 6.5.1, database_cleaner-active_record 2.2.2, dotenv-rails 3.2.0 | `>= 6.1` / `>= 5.a` / `>= 6.1` | OK | OK | OK | None |
| string_utils 1.0.8 (2012; abandoned) | activesupport `>= 2.3.5` | OK | OK | OK | None now. Requires `active_support/core_ext/string/multibyte` (still present in 8.1); uses `mb_chars` only at `lib/string_utils.rb:169–170`, off the app's path (`urlify`, `:57–64`, is `gsub` only; used at `app/models/order.rb:433`, `lib/order_export.rb:133`). Replace with `String#parameterize` later (§8) |
| geocoder 1.8.6 | none | OK | OK | OK | None (UNVERIFIED: changelog silent on Rails 8; `geocoded_by` at `app/models/area.rb:16` is exercised by specs with `spec/support/geocoder.rb`) |
| oj 3.16.13, multi_json 1.19.1 | none | OK | OK | OK | None; the only coupling is `MultiJson.use(:oj)` (`config/initializers/multijson.rb`) |
| puma 7.2.0, rack 3.2.4, rack-cors 3.0.0, pg 1.6.3, redis 5.4.1, connection_pool 2.5.5 | — | OK | OK | OK | None |
| minitest 6.0.1 | — | **downgrade** | — | — | Forced by 7.2.4's `minitest < 6`; expected lock movement in slice 1 |
| stripe 18.3.0, aws-sdk-s3/ssm/sts, twilio-ruby 5.76.0, rets 0.11.2, prawn, rqrcode, rubyzip, bcrypt, jwt 2.10.2, hashids, shortuuid, coupon_code, phone | no Rails dependency | OK | OK | OK | None |

**No blocking gem. No gem major bump is required to reach 8.1.4.** Beyond `rails` and the
`honeybadger` addition, the only lockfile movement the upgrade causes is the minitest downgrade.
Any other gem bump proposed inside a slice is out of scope (§2.6) — the "gem major bump not named
in §3" trap is this sentence.

### 3.2 The two anticipated blockers

- **`activerecord-postgis-adapter` / `rgeo`:** absent from `Gemfile.lock` and source; PostGIS is
  not installed (`pg_extension` = `plpgsql`, `pg_stat_statements`). Distance is haversine SQL in
  `lib/geo_sql.rb:16–24`, called from `app/models/postal_code.rb:108–131`. The "PostGIS-dependent
  query" the prompt asks every slice to verify is therefore `PostalCode#nearby_cities` (§4.0 P4/S4).
- **`honeybadger`:** absent today, as is every other error tracker; `config/newrelic.yml` is
  orphaned. **Decided (OD3): slice 0 adds it** on Honeybadger's 30-day trial, so every later slice
  has an exception-class signal (§5) and "quiet" (§2.2) is measurable.

### 3.3 CVE-2026-66066 (GHSA-xr9x-r78c-5hrm) exposure

Advisory facts: activestorage `< 7.2.3.2`, `>= 8.0.0.beta1, < 8.0.5.1`, `>= 8.1.0.beta1, < 8.1.3.1`
are affected; patched in 7.2.3.2 / 8.0.5.1 / 8.1.3.1; the vector is libvips variant processing of
untrusted uploads; the 8.0.5.1/8.1.3.1 fix raises at boot only "When ruby-vips is installed".

Repo facts: the engine is loaded (`rails/all`) with `variant_processor = :vips` and **nine Active
Storage routes drawn** (`/rails/active_storage/{blobs,representations,disk,direct_uploads}`); but
there are no attachments, no `variant` calls, no `active_storage_*` tables, and no
`image_processing`/`ruby-vips`/`mini_magick` gem. **Derivative generation runs entirely outside
Rails** — the Lambda resizer (`config/initializers/cors.rb:41`) fed by the photo workers and
`S3ImageHandler`, with direct S3 access.

**Conclusion: not exploitable today** (no libvips, no blob table — a `direct_uploads` POST fails
before any processing), but 7.2.3 is inside the affected range and the mounted routes are needless
surface. Slice 1 lands 7.2.4 (≥ 7.2.3.2) **and turns the routes off** (`config.active_storage.draw_routes
= false`, decided OD2). The engine itself stays: the decided OrderProcessingNote design uses
`has_many_attached :attachments` on S3 with an image thumbnail variant
(`insgt-platform/docs/plans/order-processing-note.md:19`); that design revisits the routes-off line
and the libvips posture (§8 item 7, decided OD6).

---

## 4. Slices

Each slice is one `slice-implementation` session on a branch off insgt-api `master`, ends green,
and deploys alone. None carries a migration. Gate calibration per the skill's table: slices 0–3
"after plan; after verification"; slices 4 and 5 "all".

### 4.0 Shared verification kit

Every slice runs the same pre-deploy checks and the same production spot checks; its subsection
adds what is specific and substitutes its version string. Expected values are stated here, before
any code exists.

**Pre-deploy, on the slice branch (dev container):**

| # | Command | Expected |
| :-- | :-- | :-- |
| P1 | `bundle exec rspec 2>&1 \| tee /tmp/rspec.log; grep -c "DEPRECATION WARNING" /tmp/rspec.log` | `N examples, 0 failures` with N ≥ the previous slice's count; grep = `0` (slice 1 onward makes this structural with `:raise`). **v5, from slice 2:** P1 runs twice, plain and with `CI=1` (eager load on, so a class-body deprecation in a class no spec loads is caught — §8 item 19 adopted); both `0 failures` and `0` deprecation lines; the count is reported, not a pass criterion |
| P2 | `bin/rails zeitwerk:check` | "All is good!" |
| P3 | **A job runs end to end** (strengthened, OD5): start `bundle exec sidekiq -c 1 -e development` against the container's Redis; in a second shell `bin/rails runner 'jid = PropertyDataLookupWorker.perform_async(0); sleep 5; puts Sidekiq::Status::status(jid).inspect'` | the Sidekiq log shows `Booted Rails <version> application in development environment`, the job's start/done lines, and the runner prints `:complete`. Candidate worker (ASSUMPTION, the plan confirms by reading `PropertyFactsService.call`): with id `0` the service raises a `StandardError` that `property_data_lookup_worker.rb:34–38` rescues, logs and swallows, so the job completes with no external call. What is exercised: Sidekiq boot, the Rails executor/reloader (`sidekiq/rails.rb:20–26, 68–78`), the Redis round-trip, and the sidekiq-status middleware writing the record. **v3, from slice 0:** in development `Sidekiq::Status::status(jid)` returned `nil` and `get_all` `{}` for a job that ran and failed: the status middleware is configured only in `config/sidekiq_status.rb`, which nothing requires (§8 item 10), so the runner will not print `:complete` as written. Slice 1's plan pins what P3 asserts (the Sidekiq log lines alone, or §8 item 10 first); whether production installs the middleware is UNVERIFIED. **v4, from slice 1:** the ASSUMPTION above is false — `property_data_lookup_worker.rb:34–39` rescues `StandardError`, logs and **re-raises**, so id `0` ends in `fail`. P3 now enqueues an already-fetched property on its own queue (`Property.unscoped.where(property_data_status: 2).order(:id).first`, `PropertyDataLookupWorker.set(queue: …)`, `sidekiq -q <that queue>`), which the worker's `PropertyDataAlreadyFetchedError` rescue (`:32–33`) completes with no external call, and asserts the Sidekiq log lines: `Booted Rails <version>`, `start`, `…already has property data, skipping`, `done`. `Sidekiq::Status::status(jid)` is recorded (`nil`), not asserted |
| P4 | `bundle exec rspec spec/models/postal_code_spec.rb -e nearby_cities` | 4 examples, 0 failures (`:110–148`; the haversine query). v4: v1–v3 said 3 examples over `:110–141`, a miscount — the fourth example starts at `:142`, and the file last changed 2026-05-17 |
| P5 | `bundle exec rspec spec/lib/stripe_card_spec.rb spec/models/account_stripe_spec.rb spec/models/order_issue_refund_spec.rb spec/models/transaction_charge_failure_spec.rb` | 0 failures (Stripe paths; the last two assert `ActionMailer::Base.deliveries`) |
| P6 | `bin/rails runner 'puts Notifier.send_error_email("rails upgrade", "render check").message.subject'` | `SystemError::rails upgrade` (both ERB templates render; nothing is delivered) |
| P7 | `bundle exec rspec spec/requests/users_directory_spec.rb spec/requests/orders_processing_parent_pays_spec.rb spec/workers` | 0 failures (JWT request path; raw `select_all` through `OrderSql`; Sidekiq fake queue) |
| P8 | `bin/rails runner 'p = Photo.unscoped.where(status_type: 1).order(:id).last; puts p.thumb_url'` then `curl -sS -o /dev/null -w "%{http_code}\n" "<url>"` | a URL built by `S3ImageHandler`; `200` (an S3/CloudFront read of a real object — ASSUMPTION: `thumb_url` is the generated reader's name per `CLAUDE.md`; the slice plan pins it) |
| P-PROD | **v5.** The production-config probe (slice 1's runbook step 2: `RAILS_ENV=production HONEYBADGER_REPORT_DATA=false bundle exec dotenv sh -c '… exec bin/rails runner "$1"' _ '…'` against the dev restore), from slice 2 extended with `p ActiveSupport.to_time_preserves_timezone`, `p Rails.application.config.loaded_config_version` and `p Rails.application.routes.routes.count`, its whole output grepped for `DEPRECATION` | every registered deprecator maps to `[:notify]`, `report_deprecations` not `false`, `received?` `true`, the slice's expected values, `0` `DEPRECATION` lines — the only production-mode boot (eager load, routes drawn) before the push. `HONEYBADGER_REPORT_DATA=false` keeps the probe's own deprecation out of production's Honeybadger and the SH baseline |

**Production spot checks, from the Mac, within 30 minutes of the push** (capture S4's and S6's
answers *before* the push on the previous release, so "unchanged" is provable):

| # | Command | Expected |
| :-- | :-- | :-- |
| S0 | `heroku run --app insgtapi rails runner 'Honeybadger.notify("rails upgrade slice <N> marker", error_class: "UpgradeMarker", fingerprint: "rails-upgrade-marker", tags: "upgrade", context: { rails: Rails.version, release: "<vNNN>" }, sync: true)'` | the single grouped `UpgradeMarker` error in the Honeybadger project gains a new occurrence whose context shows the slice's `Rails.version` — proof the gem's railtie loaded and reports from this release (from slice 0 on). **v5:** set the release in a shell variable first (`RELEASE=vNNN`, from `heroku releases -n 1`) and interpolate it — slice 1's marker and S6 went out with the literal `<vNNN>` |
| SH | Honeybadger → Errors, filtered to the window since the push, compared with the slice 0 baseline (§4.1) **by error, not by class** (v5, slice 1's amendment). Two searches: `environment:"production" created.after:"<push time>"`, and `environment:"production" class:"NoMethodError" occurred.after:"<push time>"` (the baseline's three `NoMethodError`s were fixed by v661, so a recurrence is a finding even though the error is old) | **no new error**. Triage every error the first search returns: does its backtrace touch what the slice changed? Yes is a finding, resolved before the slice is called deployed; no is an old bug seen for the first time, or an old error regrouped because a line moved — recorded, fixed on its own branch, not blocking. From slice 1 on, also: no new `RailsDeprecation` beyond S-DEP's (§4.2) — one is a deprecation on a path the suite does not reach, a STOP for the next slice under OD8 — and no `DeprecationReporter` failure notice |
| S1 | `curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up` | `200` (from slice 3, `/up.json` → `{"status":"up",...}`); the Honeybadger uptime monitor (slice 0) stays green |
| S2 | `heroku ps --app insgtapi`; `heroku logs --ps backgroundworker.1 -n 300 --app insgtapi \| grep Booted` | `web.1 up`, `backgroundworker.1 up`; `Booted Rails <version> application in production environment` |
| S3 | `heroku run --app insgtapi rails runner 'puts Rails.version'` | the slice's version |
| S4 | `heroku run --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'` | identical to the pre-push capture — `["Carlsbad", "Oceanside", "Leucadia"]` on v661 and v662 (the ASSUMPTION that 92008 has coordinates held). **v5:** `map`, not `pluck`: `nearby_cities` selects and orders by `distance_in_miles` (`postal_code.rb:131–132`) and `pluck` replaces the select, so the `ORDER BY` raises `PG::UndefinedColumn` (slice 1's probe on v661 did; that notice is excluded from the baseline) |
| S5 | `heroku run --app insgtapi rails runner 'puts Stripe::Balance.retrieve.livemode'` | `true` (read-only Stripe API call with the production key) |
| S6 | `heroku run --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice <N>', 'release <vNNN>').deliver_now"` | ops@insightphotos.net receives `SystemError::rails upgrade slice <N>` within minutes (SendGrid path exercised) |
| S7 | one hour after the push (v5, as slice 1's runbook amended it): `heroku logs -n 1500 --app insgtapi > /tmp/s7.log`, then the window (`head -1`/`tail -1 \| cut -c1-32`), `grep -c "status=5" /tmp/s7.log`, and the exception classes (`grep -oE '\] [A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)* \(' /tmp/s7.log \| sort \| uniq -c \| sort -rn`); then Papertrail `status=5` from the push to one hour after it | `0` `status=5` in the hour (Papertrail — the 1,500-line buffer spans about 25 minutes, not the hour); no class in the buffer other than `ActionController::RoutingError` (scanner traffic, two lines per rescue). The earlier `grep -ciE "error\|exception"` count tracked scanner traffic, not the release, and no previous-release count existed to compare against |
| S9 | the next scheduled `import_listings` run | its Honeybadger check-in (slice 0) arrives on time; a missed check-in after a deploy is a finding |

### 4.1 Slice 0 — Honeybadger

Decided 2026-10-23 (OD3). The error-class signal every later slice's "quiet" test (§2.2) and
§5 depend on. Deploys alone, Mon 2026-10-26, on the 30-day trial.

**Scope.**
1. `Gemfile`: `gem 'honeybadger'` (6.10.0; `bundle install`). The only gem this upgrade adds (§2.6).
2. **API key from ENV only**: `heroku config:set HONEYBADGER_API_KEY=… --app insgtapi`; nothing in
   git. Do not run `honeybadger install` (it writes the key into `config/honeybadger.yml` and sends
   a test exception — docs, Rails integration guide); use `bundle exec honeybadger test` instead.
3. **Report from production only.** The gem's default already does this — `report_data` "Defaults
   to false for "test", "development", and "cucumber" environments" (`development_environments`
   default `["development", "test", "cucumber"]`, configuration reference) — and `config/honeybadger.yml`
   (checked in, no key) states it explicitly per environment, plus `insights: enabled: false`
   (RECOMMENDATION: errors only for now; Insights is on by default in v6 and ships request/job/
   Net::HTTP events — revisit after the cutover) and `sidekiq: attempt_threshold: 0` (the default;
   with `sidekiq_options retry: false` every worker failure reports on its only attempt).
4. **Parameter filtering review.** `request.filter_keys` defaults to `['password', 'password_confirmation']`
   and "In Rails, this also includes existing params filters" (configuration reference), i.e. the
   list at `config/initializers/filter_parameter_logging.rb:4–8` (`password password_confirmation
   code token passw email secret key crypt salt certificate otp ssn phone phone_number
   phone_number_formatted`, partial-matched — so `stripe_token`, `api_key`, `jwt_secret` are
   covered). The review confirms, on a real test notice, that (a) the `Authorization` header (the
   JWT) is not sent in clear — UNVERIFIED whether the gem filters `HTTP_AUTHORIZATION` by default;
   if not, add it to `request.filter_keys`; (b) Stripe card data never reaches params (the app
   receives Stripe tokens, not card numbers — `app/controllers/accounts_controller.rb:22, 65`).

   **v3, from the gem source and a real notice (2026-10-26):** the 6.10.0 default is
   `["password", "password_confirmation", "HTTP_AUTHORIZATION"]` (`config/defaults.rb:261–264`; the
   docs page omits the third). A `request.filter_keys` list in `config/honeybadger.yml` **replaces**
   that default (`Config#get` returns the first source holding the key, `config.rb:121–130`), so the
   file leaves it unset and `spec/config/honeybadger_spec.rb` pins `HTTP_AUTHORIZATION` in the
   resolved list; no second notice was needed. The Rails filter list applies to notices with a
   request only (`notice.rb:576–582`); Sidekiq job arguments go unfiltered (ids and order tokens
   today). The Stripe token arrives as `transaction[token]` (`transactions_controller.rb:54`) and is
   filtered by `token`. The real notice and its result are in `docs/runbooks/deploy-rails-upgrade-0.md`
   (Deploy log).

   **v3, from the adversarial review:** log breadcrumbs are **off** (`breadcrumbs.logging.enabled:
   false`). They copy the app's log lines into each notice, the gem filters breadcrumb metadata but
   never the message (`notice.rb:408–415`), and the app logs `params.require(:account).inspect`
   (`accounts_controller.rb:163`) and Twilio verifications (`lib/auth.rb:34`). Request, render and
   SQL breadcrumbs stay (SQL obfuscated, `breadcrumbs/active_support.rb:23`). `HTTP_REFERER` is sent
   unfiltered, kept by decision: the client apps are another origin with no referrer policy, so
   browsers send the origin only; filtering it would mean listing `request.filter_keys` in full,
   replacing the gem's default.
5. **Check-in on the recurring import.** `Honeybadger.check_in(ENV['HONEYBADGER_CHECKIN_IMPORT_LISTINGS'])`
   as the last line of `import_listings` (`lib/tasks/scheduler.rake:15–18`, after `Crmls.import`),
   guarded on the variable being present; the check-in is created in the dashboard and its id set
   with `heroku config:set`. Fact: **no recurring Sidekiq job exists** — recurring work is the four
   Heroku Scheduler rake tasks in `scheduler.rake` (`import_order_photos`, `send_delayed_notifications`,
   `cleanup_unused_watermarks`, `import_listings`); Sidekiq workers are enqueued by user activity
   (`app/models/order.rb` ×4, `transaction.rb` ×2, …). `import_listings` is chosen because it is
   the regex-dense path slice 5a must watch (§4.6) and because its check-in history reveals the
   scheduler cadence the §6 slippage rule needs (OD11 records the deviation from "a Sidekiq job").
   **v3:** OD11 settled at the slice 0 plan gate (2026-10-26) as recommended. The cadence is
   **hourly**, read from `mls_imports` before any check-in history existed: the last 40 CRMLS
   imports on the dev restore are exactly 1.0 h apart, finishing about :35 UTC, extraction 318–452 s.
   The check-in is Simple, 1 hour, 30 minutes' grace. It means the task finished, not that listings
   arrived: `Crmls.extract_listings` returns without raising when the MLS login fails
   (`lib/crmls.rb:94–95`).
6. **Uptime monitor** on `https://api.insightphotos.net/up`, created in the dashboard (success =
   any 20x; "every few minutes"; "Your Honeybadger account comes with uptime monitoring" — uptime
   guide; UNVERIFIED that the trial includes it). **v3:** created 2026-10-26 on the trial.
7. **Baseline.** 24 h after the deploy, the slice's runbook records the list of error classes the
   project has seen; §2.2's "quiet" is measured against it. **v5:** recorded 2026-10-27 in
   `deploy-rails-upgrade-0.md` (window: v659's push to v662's push, 22 h 24 min): `UpgradeMarker` and
   three `NoMethodError` errors, one row per Honeybadger error — the unit §2.2 and §4.0 SH now compare
   by, not the class list this item first named.

**Out of scope.** Any Rails change; `report_deprecations` (slice 1); Insights; deploy hooks beyond
the CLI marker; any other gem.

**Prerequisites.** §2.7 — `docs/rails-upgrade` merged into the platform repo's `main`; a Honeybadger
project created and its API key in the Mac's shell and in Heroku config.

**Gaps pinned.**
- *Precedence between `config/honeybadger.yml` and `HONEYBADGER_*` variables* for the development
  verification (`HONEYBADGER_REPORT_DATA=true` must win for one run). UNVERIFIED from the docs; the
  plan tests it and records the answer. **v3, answered:** an ENV value wins over the file (source
  order Ruby config → ENV → YAML → framework, `config.rb:37, 121–130`), shown on four development
  boots (runbook Deploy log). `HONEYBADGER_ENV` also selects which YAML section applies
  (`config.rb:491`), so a renamed environment such as `development-check` matches no section; the
  file's top-level `report_data: false` is what keeps such a run quiet without
  `HONEYBADGER_REPORT_DATA=true`.
- *What the baseline contains if 24 h show nothing.* Rule: an empty list is a valid baseline; the
  `UpgradeMarker` class (S0) is always in it.

**Spec plan.** A request spec that `Honeybadger.config[:api_key]` is `nil` in test and that
`Honeybadger.config[:report_data]` is false (the gem must never report from the suite); a spec for
the rake task's check-in guard (no id → no call). The deliberate break: set `HONEYBADGER_REPORT_DATA`
in the spec environment and watch the first example fail.

**v3, as built:** a config spec, `spec/config/honeybadger_spec.rb`, not a request spec. The
`api_key`-is-`nil`-in-test assertion is replaced: dotenv loads the real key from `.env` in the dev
container, so in test it is not nil. The spec instead asserts that the file resolves to no
`api_key` (on `nil?`, so a failure never prints a key), that the suite resolves `report_data` false
with the Null backend, that production alone reports (development, test, `development-check`,
`staging` do not), Insights off, log breadcrumbs off, `attempt_threshold` 0 and `HTTP_AUTHORIZATION`
filtered; and it builds and serializes a request notice locally (nothing sent) to show the JWT, the
Stripe token, the guest `access_token`, email, password and a logged line absent from the payload.
`spec/lib/tasks/scheduler_rake_spec.rb` covers the guard (unset, blank), the order (after the
import) and a raising import (no check-in). The ENV deliberate break runs with
`HONEYBADGER_BACKEND=null` too: `.env` holds the real key and `spec/support/stripe.rb:14` allows real
HTTP.

**Commit sketch.**
1. `build: add honeybadger for error tracking` [2: key from ENV, production-only, Insights off and why]
2. `feat: check in from the listings import` [1]

**Post-deploy verification** (slice-specific, replacing the Rails checks):
- `HONEYBADGER_API_KEY=… bundle exec honeybadger test` from the container → a `HoneybadgerTestingException`
  appears in the project ("Send a test notification from Honeybadger", CLI reference).
- A deliberately failing job reported from development: with Sidekiq running locally and
  `HONEYBADGER_REPORT_DATA=true HONEYBADGER_ENV=development-check`, `GenerateCoordinatesWorker.perform_async('NoSuchClass', 1)`
  — `'NoSuchClass'.constantize` raises `NameError` at `generate_coordinates_worker.rb:25` before any
  geocoding → a `NameError` from component `GenerateCoordinatesWorker` appears in the project (an
  `ActiveRecord::RecordNotFound` would not: it is in the gem's default ignore list).
  **v3:** run on its own queue (`.set(queue: 'honeybadger_check')`, `sidekiq -q honeybadger_check`)
  because a dev Sidekiq was already consuming `default`; `Sidekiq::Status::status(jid)` is `nil`
  (see §4.0 P3).
- S0 (the marker) and S1–S2 after the push; the uptime monitor green; the next `import_listings`
  check-in arrives (S9).
- `heroku logs --ps web.1 -n 200 | grep -i honeybadger` → the gem's start-up line, no warnings.
  **v3, corrected:** no line at boot. The start-up line is debug-level (`config.rb:57`) and
  production logs at `info` (`production.rb:61`); `** [Honeybadger] … Success ⚡` lines appear only
  when an error is reported. A Honeybadger warning or error line is the finding.

**Rollback.** `heroku rollback`; `heroku config:unset` the two variables is optional.

**Gates.** After plan; after verification. **Effort (estimate):** 3 h including dashboard setup,
same morning as the deploy.

### 4.2 Slice 1 — 7.2.4, the deprecation gate, the Active Storage routes, production deprecation reporting

**Scope.**
1. `Gemfile:28` → `gem 'rails', '~> 7.2.4'`; `bundle update rails --conservative` (if the resolver
   refuses because of minitest, `bundle update rails minitest --conservative`). Expected lock diff:
   the thirteen `7.2.3` → `7.2.4` lines, `minitest (6.0.1)` → a 5.x, nothing else. Anything else
   that moves is explained in the plan or reverted. **v4, as built:** the line is `Gemfile:29` (slice 0
   inserted `honeybadger` at `:15`). The resolver needed no `minitest` argument. The lock diff is the
   thirteen gems and their `(= 7.2.x)` pins, `minitest (6.0.1)` → `(5.27.0)` with its `prism (~> 1.5)`
   sub-dependency line (prism stays through other dependents), `DEPENDENCIES` `~> 7.2.0` → `~> 7.2.4`,
   the checksums, and two constraint lines under `activesupport` that 7.2.4's gemspec changed:
   `connection_pool (>= 2.2.5, < 3)` and `minitest (>= 5.1, < 6)` (the lock holds `connection_pool`
   2.5.5). Byte-identical to the survey's scratch resolution.
2. Delete `config/initializers/new_framework_defaults.rb:15–17` (the comment and
   `ActiveSupport.to_time_preserves_timezone = false`). On 7.2 the `load_defaults "5.0"` chain sets
   the value to `true` directly (`7-2-stable railties/.../configuration.rb:117`) and nothing resets it,
   so the effective value becomes `true` and the suite's only deprecation disappears.
3. `config/environments/test.rb:58` → `config.active_support.deprecation = :raise`. Keep `:61`
   `disallowed_deprecation = :raise`. From here on a deprecation is a red suite, not a log line.
4. **Active Storage routes off** (decided OD2): `config.active_storage.draw_routes = false` in
   `config/application.rb`, own commit, with the routes assertion and the 404 request spec (spec
   plan). Pre-deploy, grep the available log history for `active_storage` hits and **state how far
   back that history actually reaches**: `heroku logs -n 1500 --app insgtapi | grep -c active_storage`
   (Heroku's buffer is 1,500 lines — minutes to hours, not proof of no traffic), then
   `heroku addons --app insgtapi` for the Papertrail drain the README created
   (`README.md:141`, `papertrail:choklad`) and, if attached, a Papertrail search for
   `rails/active_storage` with the oldest searchable timestamp written into the plan (UNVERIFIED:
   that the add-on is still attached and the plan's retention). **v4, as found:** Heroku buffer 1,500
   lines back to 2026-10-26 13:32:53 UTC, 0 hits; Papertrail **is** attached (`fixa`, not the README's
   `choklad`) and found no matching events back to 2026-10-12 08:00 PM (UI time), about fourteen days.
   A pre-deploy audit added at the plan review: no route helper, `/rails/active_storage` literal,
   `DirectUpload` client or attachment API in any repo under `apps/`, `lib/`, `functions/` (insgt-galleries
   and insgt-virtual-tour do not load the engine); no `active_storage_*` table and 0 of 229
   text/varchar/json columns containing `rails/active_storage` on the dev restore; stored media URLs are
   S3 buckets and third-party video/tour hosts, and photos are built at read time through CloudFront or
   S3, never through Rails routes.
5. **Production deprecation reporting on** (decided OD8): `config/environments/production.rb:83`
   `report_deprecations = false` → `true` (today it silences every deprecator: `7-2-stable
   activesupport/lib/active_support/railtie.rb:66–70`), plus `config.active_support.deprecation = :notify`,
   which instruments `deprecation.rails` with `message`, `callstack`, `gem_name`, `deprecation_horizon`
   (`activesupport/lib/active_support/deprecation/behaviors.rb:37–45`, identical on 8.1). A
   production-only initializer subscribes to `/\Adeprecation\./` (gems with their own deprecator
   instrument `deprecation.<gem>`) and hands each event to a small `DeprecationReporter` that sends
   each **distinct message once per process** to Honeybadger — `Honeybadger.notify(message,
   error_class: 'RailsDeprecation', fingerprint: Digest::SHA256.hexdigest(message), tags: 'deprecation',
   context: { gem_name:, deprecation_horizon:, callstack: first non-gem frame })`; the fingerprint
   groups repeats across processes into one error. This closes the untested-path gap (MLS imports,
   rare admin endpoints, thin-coverage jobs): a deprecation the suite never reaches shows up in
   Honeybadger within a day of real traffic, not at the next major.

   **v4, as built** (`app/services/deprecation_reporter.rb`, `config/initializers/deprecation_reporting.rb`):
   - *Scope.* Every deprecator registered with `Rails.application.deprecators` is reported: it inherits
     the `:notify` behaviour and emits `deprecation.<gem_name>` (`deprecation.rails`,
     `deprecation.global_id`, `deprecation.lograge` on 7.2.4; dotenv's registered deprecator reports as
     `Rails`), and the subscription is `/\Adeprecation\./`. Gem deprecations are wanted: they are the
     early warning ahead of slice 2. **Not seen:** a gem that creates its own `ActiveSupport::Deprecation`
     instance without registering it with the app (it keeps its own default behaviour and emits no
     event), and plain Ruby `warn` / `Kernel#warn` calls (rack's `:unprocessable_entity`, §8 item 1).
   - *Wiring.* `Rails.application.config.to_prepare { DeprecationReporter.subscribe } if
     Rails.env.production?`. A bare `DeprecationReporter.subscribe` in an initializer fails the boot
     with `NameError`: the main autoloader is set up in the Finisher, after `config/initializers`
     (`railties application/finisher.rb:18`). `to_prepare` runs before eager loading (`:73` vs `:77`),
     so a deprecation in a class body that no spec loads is still reported; `after_initialize` (`:93`)
     would be too late for those. With reloading off, `reloader.check` is `false` (`:201`), so neither
     Sidekiq's job wrapper nor the executor re-runs it. Not covered: a deprecation warned after the
     railtie applies `:notify` and before this block (config and engine initializers) — the same
     initializers boot under `:raise` in test, and none branches on production.
   - *Key and grouping.* The dedupe key and the fingerprint's source are both `"<gem_name>: <message>"`.
     The message ends with `(called from <label> at <file:line>)` but does not name the deprecator, and
     Honeybadger groups on a supplied fingerprint alone (its "Customizing error grouping" page), so
     context never separates groups. So: once per deprecator and call site per process, one error per
     deprecator and call site across processes. A deprecation whose text embeds a runtime value adds a key
     per value. `Concurrent::Map#put_if_absent` claims the key atomically — two Puma threads cannot both
     report it.
   - *What the notice carries.* `error_class: 'RailsDeprecation'`, `tags: 'deprecation'`, context
     `gem_name`, `deprecation_horizon` and `callstack` (the first app frame by `Rails.backtrace_cleaner`,
     root-relative, else the first frame), and `backtrace:` the **raw** callstack — Honeybadger marks
     application frames by the absolute project root (`backtrace.rb:79–81`), so a cleaned list would
     show none.
   - *Failure.* The subscriber never raises for a Notifications payload. A subscriber's error would
     otherwise surface in the code that emitted the deprecation (`notifications/fanout.rb`,
     `iterate_guarding_exceptions`), failing that request or job. A failure is logged
     (`[DeprecationReporter] Failed to report …`) and sent as its own Honeybadger notice with
     `deprecation_message` in the context, each rescued separately. The key is claimed before
     `notify`, so a failing reporter tries once per key per process, not on every call.
   - *Deploy probe.* `DeprecationReporter.received?(text)` — whether this process's reporter claimed a
     message containing `text`. It proves the wiring, not delivery.
6. Create `spec/architecture/rails_upgrade_spec.rb` with the slice 1 invariants (spec plan below).

**Out of scope.** Any other gem; any initializer other than the one line; the 24 spec
`:unprocessable_entity` symbols (rack warnings, not Rails deprecations; they do not trip `:raise` —
§8); `rails/all`; `config.load_defaults`; the OD8 callable (introduced only if an exemption is ever
needed — none is today).

**Prerequisites.** Slice 0 deployed (S0 works; the project exists), so the deprecation reporter has
somewhere to send. Proof of the starting point: `Rails.version` → `7.2.3` in a runner;
`git -C apps/insgt-api log -1` → eda99450 or a descendant with a green suite.

**Gaps pinned.**
- *What `to_time` does after line 17 is deleted.* Rule: the Rails ≥ 5.0 default — `to_time` returns
  a `Time` carrying the receiver's UTC offset (`true`, which 8.0 renames `:offset`). Alternative
  rejected: keep `false` until 8.0 forces the change. Why: 8.0's writer warns on `false`, 8.1
  removes it; moving it now isolates the first behaviour step in a one-line, bisectable commit on
  the version the app already runs. (v4: `true` is correct for 7.2 only — 8.0 changes the semantics
  again, `:offset` vs `:zone`; §4.3 revisits it, not this slice.) Blast radius: no `.to_time` in `app/` or `lib/`; dynos and the
  container run UTC, so the only observable difference is the offset carried by `Time` objects that
  gems derive from zoned values (`Time#zone`, `strftime('%z')`, `hour`/`day` of a Pacific receiver).
- *`:raise` versus third-party deprecations.* Rule (decided OD8): a deprecation raised from inside
  a gem during a later slice is a STOP for that slice. If an exemption is ever needed,
  `config.active_support.deprecation` becomes a callable that raises by default and logs only when
  the first non-Rails frame is inside a listed gem path **and** the message matches a listed
  pattern; each (path, pattern) pair is recorded in §7 with the §8 item that removes it. Slice 1
  keeps plain `:raise`.
- *Dedupe scope of the deprecation reporter.* Rule: once per message per process (a `Concurrent::Map`
  keyed by message); Honeybadger's fingerprint groups across processes. Alternative rejected:
  rate-limiting by time — adds state with no benefit. **v4:** keyed by `"<gem_name>: <message>"`, and
  the message carries the call site, so in practice once per deprecator and call site (item 5, as built).

**Spec plan** (`spec/architecture/rails_upgrade_spec.rb`, new, plus `spec/services/deprecation_reporter_spec.rb`):
- "the framework runs the version the document names": `Rails.gem_version >= Gem::Version.new('7.2.4')`
  (bumped per slice).
- "`to_time` preserves the receiver's offset": `ActiveSupport.to_time_preserves_timezone` is `true`
  and `ActiveSupport::TimeZone['Pacific Time (US & Canada)'].parse('2026-10-23 10:00').to_time.utc_offset`
  is `-25200`. Deliberate break: re-add `ActiveSupport.to_time_preserves_timezone = false` → the
  offset becomes the system offset (`0` in the container; confirm `date +%z` prints `+0000` first)
  and the example goes red.
- "the suite boots with no deprecation": implicit in `:raise` — the plan pastes one run with the
  line 17 override restored to show the suite failing at boot, then removed.
- "no Active Storage route is drawn": `Rails.application.routes.routes.none? { |r| r.path.spec.to_s.include?('active_storage') }`
  and a request spec `POST /rails/active_storage/direct_uploads` → 404 (deliberate break: set
  `draw_routes = true`).
- `DeprecationReporter`: notifies once for a repeated message, with the fingerprint and the
  `RailsDeprecation` class; a second process-local call does not notify (Honeybadger stubbed with
  `expect(Honeybadger).to receive(:notify).once`). Deliberate break: remove the dedupe.
- Existing boundary coverage to run by name: `spec/requests/orders_processing_release_on_spec.rb`,
  `spec/requests/accounts_most_recent_shoot_spec.rb` (the `search_time_params` consumers),
  `spec/lib/tasks/marketing_events_rake_spec.rb`, `spec/services/account_csv_export_service_spec.rb`.

**v4, spec plan as built.** The contract spec also asserts the gate's *behaviour*: every registered
deprecator raises `ActiveSupport::DeprecationException` (the config value alone stays `:raise` while
`report_deprecations = false` silences every deprecator — that is the example's deliberate break).
`spec/services/deprecation_reporter_spec.rb` asserts the dedupe with `have_received(:notify).once`,
not `expect(...).to receive(...).once`: with the `before` block's `allow`, a used-up expectation hands
the second call to the stub and passes. It also pins the first-app-frame rule and its fallback, the raw
backtrace, `.subscribe` through a standalone `:notify` deprecator, `received?` (true even when
Honeybadger refuses the notice), the same message from two gems as two fingerprints, and the failure
path through a real deprecator: the caller's return value is unaffected, a failed report is not
retried, the failure notice survives a raising logger. Each was seen red under its own deliberate
break. The four boundary specs: 39 examples, 0 failures.

**Commit sketch** (one concern each; `git-commit-messages` tiers in brackets):
1. `build: upgrade rails to 7.2.4` [1]
2. `fix: stop forcing the pre-Ruby 2.4 to_time behavior` [2: the line was the suite's only
   deprecation and 8.0 removes the behaviour; includes the contract spec]
3. `test: raise on deprecations in the test environment` [1]
4. `chore: stop drawing the unused Active Storage routes` [2: the log-history reach found pre-deploy]
5. `feat: report production deprecations to honeybadger once per message` [3, trigger 2: the
   pattern — `:notify` + subscriber — is what any future deprecator-aware reporting follows]

**Post-deploy verification.** §4.0 P1–P8 with `7.2.4`; S0, SH, S1–S7, S9 with `7.2.4` and `slice 1`.
Slice additions: S3 also prints `ActiveSupport.to_time_preserves_timezone.inspect` → `true`; S8
`heroku run … rails runner 'puts ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-10-28 10:00").to_time'`
→ `2026-10-28 10:00:00 -0700` (the offset survives; on 7.2.3 this printed the instant converted
to the dyno's UTC, `2026-10-28 17:00:00 UTC`);
`curl -sS -o /dev/null -w "%{http_code}" https://api.insightphotos.net/rails/active_storage/direct_uploads -X POST` → `404`;
`heroku run … rails runner 'ActiveSupport.deprecator.warn("rails upgrade reporter check")'` → one
`RailsDeprecation` error in Honeybadger with that message, then no further `RailsDeprecation` within
24 h of real traffic (SH).

**v4, verification as run.** Production is **v661** (`d37ae0df`, 2026-10-26 16:42:03 -0400, an emergency
fix on `master` after v660 `02dbb78a`), so the pre-push "before" captures (S4, S6, S8, S-AS) are taken on
v661. The slice branch is cut from `02dbb78a`; v661's two commits touch only `app/models/listing.rb` and
its request spec, share no file with the slice, and merge cleanly (`git merge-tree`). The suite runs on
the merge into `master` before the push, with an expected count of 2,040. Before the push the
engineer runs a production-config probe from the branch (`RAILS_ENV=production
HONEYBADGER_REPORT_DATA=false bin/rails runner …`, in `docs/runbooks/deploy-rails-upgrade-1.md`): its
load-bearing line maps every registered deprecator to its behaviour by name, and anything but
`[:notify]` for any of them is a finding, not a pass; `report_deprecations` must not be `false`;
`received?` shows the wiring. S-DEP adds `Honeybadger.flush`. The slice 0 baseline SH compares
against spans v659, v660 and v661 (they landed about 1 h 50 min and 6 h 50 min into its window).

**Rollback.** `heroku rollback` (code only), to v661. Nothing else to undo.

**Gates.** After plan; after verification. **Effort (estimate):** 4 h plus the deploy morning.

**v5, deployed.** v662 `473e2747`, 2026-10-27 08:15:19 -0400 — Tuesday, a day before v4's plan,
inside §2.4. The branch merged into `master` on v661 (`7e62c6b3` merged `master` into the branch
first; 2,040 examples, 0 failures, 0 deprecation lines on that tree). S2 `Booted Rails 7.2.4`; S0
notice `470ed91b-d622-40d3-a2fb-bc5adb644454` (the `release` context went out as the literal
`<vNNN>`, as did S6's body — §4.0 S0 now sets a shell variable first); S3 `7.2.4`, `true`; S8
`2026-10-28 10:00:00 -0700`; S-AS `404`; S-DEP notice `55c54cf0-415c-4bdd-9c07-ba1f2b934ac6` with the
expected context, and a rerun in a new one-off dyno grouped into the same error; S4 unchanged (`map`,
not `pluck` — §4.0); S5 `true`; S6 delivered once a SendGrid block was cleared (DKIM, SPF and DMARC
pass). S7 and S9 pass: the 1,500-line buffer spans 24 min, so the hour comes from Papertrail (0
`status=5`); the only class in the buffer is `ActionController::RoutingError` from scanners; the
check-in arrived at 08:36 -0400. **SH closes 2026-10-28 05:15 PT:** ______ (one line, filled before
slice 2's push). Runbook: `docs/runbooks/deploy-rails-upgrade-1.md`. **Effort (actual):** about 8 h on
2026-10-26 (eight commits after two review rounds and a post-review fix) plus the deploy morning.

### 4.3 Slice 2 — 8.0.5.1, transit only

**Scope.**
1. `Gemfile:28` → `gem 'rails', '~> 8.0.5'`; `bundle update rails`. Expected lock diff: the rails
   family to 8.0.5.1; the actionpack `rack < 3.3` cap disappears (rack itself stays 3.2.4);
   `useragent`, `rack-session`, `rails-dom-testing`, `rails-html-sanitizer` unchanged. Any other
   movement is explained or reverted. **v5, as built:** `Gemfile:29`; `bundle update rails
   --conservative`. Beyond the 13 gems: `cgi (0.5.1)` leaves the lock (actionpack, actionview and
   railties drop it) and actionpack's `racc` edge goes (`racc (1.8.1)` stays through other gems);
   activesupport's `connection_pool (… < 3)` and `minitest (… < 6)` caps lift and `uri (>= 0.13.1)` is
   added (`uri (1.1.1)` was already locked); `minitest` stays 5.27.0 under `--conservative`.
   Byte-identical to the survey's scratch resolution.
2. `bin/rails app:update`, run with `--force` on a throwaway branch to capture the complete diff
   as plan evidence, then applied selectively (the session cannot answer Thor's y/n/d prompts
   reliably; if `--force` is rejected, run interactively on the throwaway branch answering `a`):

   | Generated file | Decision | Why |
   | :-- | :-- | :-- |
   | `config/initializers/new_framework_defaults_8_0.rb` | **accept**, then uncomment only `to_time_preserves_timezone = :zone` | the shim is the point of the update; the one flip is forced (gap below) |
   | `bin/rails`, `bin/rake`, `bin/setup`, `bin/rubocop` | **accept** | stock binstubs; `bin/setup` gains `db:prepare`/`--reset`; no app behaviour |
   | `bin/dev` | **reject** | this repo has none; the platform's `bin/dev` drives `Procfile.dev` (`insgt-platform/CLAUDE.md`) |
   | `config/application.rb` | **reject** | the template writes `config.load_defaults 8.0` — slice 5b owns that line (§2.6); it would also drop slice 1's `draw_routes` line |
   | `config/environment.rb` | **reject** | carries `Jbuilder.key_format` and `Phoner` (`:7, :9`) |
   | `config/environments/production.rb` | **reject** | template drops the SendGrid SMTP block (`:101–111`), the `/up` SSL and host exclusions (`:48, :99`), the lograge-era logger (`:51–56`) and slice 1's deprecation reporting; adds `assume_ssl` |
   | `config/environments/development.rb`, `test.rb` | **reject** | `test.rb:58` must stay `:raise`; dev keeps the ngrok host and `:null_store` |
   | `config/initializers/cors.rb`, `filter_parameter_logging.rb` | **reject** | customised (`cors.rb:8–55`, `filter_parameter_logging.rb:4–8`) |
   | `config/initializers/inflections.rb`, `config/puma.rb` | no-op | identical modulo comments; accept if the diff is comment-only |
   | `db/migrate/*_add_service_name_to_active_storage_blobs.rb`, `*_create_active_storage_variant_records.rb`, `*_remove_not_null_on_active_storage_blobs_checksum.rb` | **delete** | copied by `active_storage:update` (`app_generator.rb:395–399` → `databases.rake:604–606`) because `rails/all` defines the engine; they alter tables this database does not have |
   | `config/cable.yml`, `config/storage.yml`, `config/boot.rb`, `config.ru`, `Gemfile`, `config/honeybadger.yml` | untouched | exist / not part of `app:update` |

   **v5, as run (8.0.5.1, on an rsync copy of the tree — the session's command classifier declines a
   throwaway branch that rewrites and resets the real tree):** `--force` is accepted
   (`add_runtime_options!`, merged into the generator options) and `perform` silences the deprecators
   for the run. Against the table: `config/boot.rb` is regenerated and identical; the
   `application.rb` template **keeps `load_defaults 7.2`** (it targets `loaded_config_version`), so
   the reject reason is the dropped `autoload_paths`, `config.hosts` and `draw_routes` lines, not an
   `8.0`; `assets.rb` is created and removed in the same run (no file results, no STOP);
   `config/puma.rb` is **not** comment-only — the template adds `plugin :solid_queue if
   ENV["SOLID_QUEUE_IN_PUMA"]` — so it is **rejected** by this table's own rule; `bin/setup` is
   **rejected** (decided at the slice 2 plan gate): the 8.0 template's tail `exec "bin/dev"`s the
   rejected `bin/dev`, the current file already runs `db:prepare`, and nothing in `.devcontainer/`,
   the README or the platform `bin/dev` calls it; `bin/rubocop` is identical; `active_storage:update`
   **copied nothing** — the three migrations have been in `db/migrate/` since `e66411cf`
   (2026-01-29), ran in production (versions in `schema_migrations`; no tables; each guarded by
   `return unless table_exists?(:active_storage_blobs)`), and `install:migrations` skips a name that
   exists. **They stay** (decided at the plan gate): deleting tracked, run migrations is a
   `db/migrate` change no slice carries, and the review must not flag them. Accepted: the shim (all
   three lines commented — gap 1), `bin/rails`, `bin/rake`. The full diff is in the slice 2 plan.

3. **Solid Queue / Solid Cache / Solid Cable: no action.** Sidekiq 7.3.10 on Redis (`Procfile:2`),
   `cache_store` is `:null_store` in test and dev-without-caching and unset in production
   (`production.rb` has only the commented `:mem_cache_store`), no Action Cable code; the 8.0
   generator defaults for new apps do not apply to an existing app and `app:update` does not add the
   solid gems (`skip_solid?` is true because none is in the Gemfile).
4. **Kamal / Thruster: skip.** The generator derives `skip_kamal` and `skip_thruster` from the
   Gemfile (`update_command.rb:63–84`); neither gem is present, so no `config/deploy.yml`,
   `bin/thrust`, or Dockerfile is offered.
5. **Active Record connection handling: no change.** `ActiveRecord::Base.connection` remains
   defined and silent ("Soft deprecated. Use `#with_connection` or `#lease_connection`",
   `8-0-stable activerecord/lib/active_record/connection_handling.rb`); `permanent_connection_checkout`
   stays `true` (runner), and `load_defaults 8.0` does not touch it. The ~25 raw-SQL sites (notes,
   "Raw SQL and connection handling") are untouched. 8.0.2's two-second verification memo reduces
   per-query `SELECT 1` pings — a benefit, not a change to make.
6. `config.load_defaults` stays `7.2`.

**Breaking changes affecting this codebase** (8-0-stable CHANGELOGs; quotes are first sentences):
- `config/initializers/new_framework_defaults_8_0.rb` (new): Active Support 8.0.0.beta1 "Add a new
  configuration value `:zone` for `ActiveSupport.to_time_preserves_timezone` and rename the previous
  `true` value to `:offset`. The new default value is `:zone`." Under `load_defaults 7.2` the 5.0
  block sets `:offset` (`8-0-stable configuration.rb:119`) and the railtie forwards it to a writer
  that warns for anything but `:zone` (`active_support.rb:118–132`; `railtie.rb:99–103, 125–130`).
  With `:raise`, the suite would fail at boot. Hence the one flip, below. **v5:** the flip cannot
  live in the shim — gap 1, as built.
- `config/routes.rb:6, :19` (**v5; found by slice 2's survey — the one real hit**): Action Pack
  8.0.0.rc1 "Raise an `ArgumentError` when invalid `:only` or `:except` options are passed into
  `#resource` and `#resources`." `request_shoot` and `upload_url` sat in the `only:` lists while
  being declared in their member blocks; 7.2 ignored them, 8.0 refuses to load the route set
  (`mapper.rb:1182–1186`), so production would not have booted. The symbols are removed; the route
  table is byte-identical (583); the contract spec recognizes both routes, the carts `format: 'json'`
  default and their URL helpers.
- `app/models/{account_metric,account,order_type}.rb:42–44, 91, 87`: Active Record 8.0.0.rc1
  "Remove deprecated support for defining `enum` with keyword arguments." — the five declarations
  are positional; no change.
- `config/initializers/json_param_key_transform.rb:2–6`, `lib/app_param.rb` (`deep_underscore_params`):
  Active Support 8.0.3 "Fix `ActiveSupport::HashWithIndifferentAccess#tranform_keys!` to handle
  collisions." ("The later key now overwrites the earlier one"). A body carrying both `fooBar` and
  `foo_bar` resolves to the later key. Plan verifies which `transform_keys` variant each uses.
  **v5:** neither path calls `HashWithIndifferentAccess#transform_keys!` — `AppParam` deletes and
  reinserts keys (`lib/app_param.rb:8–16`), the JSON parser calls `Hash#deep_transform_keys!` on the
  plain `Hash` that `ActiveSupport::JSON.decode` returns, and `core_ext/hash/keys.rb` is identical on
  7.2.4 and 8.0.5.1. Probes identical on both versions: both key orders give `{"foo_bar"=>1}` (the
  camelCase value) through every app path. No change. The "later key" precedence applies only to a
  direct HWIA call, where 7.2.4 already behaved so.
- `app/models/*` with `CrudAttribution` validations: Active Record 8.0.2 "Fix autosave associations
  to no longer validated unmodified associated records." — saves that failed because an
  *unchanged* associated record was invalid now succeed. The suite is the detector. **v5: not a
  change of this slice.** The fix was backported to 7.2.3 (activerecord 7.2.4 `CHANGELOG.md`, the
  7.2.3 section), as was 8.0.3's "`#merge` with `#or`" fix that §4.4 lists for 8.1; both have run in
  production since the app moved to 7.2.3. Found by the Codex review of slice 2.
- `.env` `SECRET_KEY_BASE`: Railties 8.0.2 "Use `secret_key_base` from ENV or credentials when
  present locally." — inert (no cookies, no verifiers in app code).
- `app/controllers/application_controller.rb:329, 334` etc.: Action Pack 8.0.3 "Address `rack 3.2`
  deprecations warnings." — Rails already converts the symbol on 7.2.3 (no app-side warnings in the
  baseline); the 24 rspec-rails warnings are the matcher's own and stay until §8.
- Active Storage 8.0.4.1 (`DirectUploadController`, `DiskService` CVE fixes): unreachable since
  slice 1 turned the routes off; landing on 8.0.5.1 includes them regardless.

**Out of scope.** Flipping anything in `new_framework_defaults_8_0.rb` other than `to_time`;
`config.load_defaults`; `rails/all`; any gem bump beyond `rails`; the environment files;
`config/ci.rb` (an 8.1 artefact; not generated by 8.0).

**Prerequisites.** Slice 1 deployed: `heroku releases -n 1` shows the slice 1 release;
`heroku run … rails runner 'puts Rails.version'` → `7.2.4`; `git log` shows commits 1–5 of §4.2 on
`master`; the suite is green with `:raise`; SH shows no `RailsDeprecation` since slice 1.

**Gaps pinned.**
- *`to_time` on 8.0.* Rule: `config.active_support.to_time_preserves_timezone = :zone`, set by
  uncommenting the generated line (the mechanism 8.0.2 fixed). This is a deliberate exception to
  "no default flips before slice 5", recorded here: the two alternatives (`false`, `:offset`) both
  warn at boot on 8.0 and are removed on 8.1, so `:zone` is the only value under which the suite
  runs with `:raise`. Behaviour step two: `to_time` returns a `Time` carrying the receiver's zone
  object (`Time#zone` → `"PDT"`/`"PST"`, DST-aware arithmetic) instead of a fixed offset. **v4, from
  slice 1:** slice 1 leaves the value at `true` from `load_defaults`, which is correct for 7.2 only.
  8.0 reads `true` as `:offset` and changes the semantics again, so this slice's plan re-derives
  `:offset` versus `:zone` from the installed 8.0.5.1 source rather than from this text. The slice 1
  contract example pins `utc_offset == -25_200` and stays valid under `:zone`; add the zone example as
  planned. Under `:raise`, a stray `true` or `:offset` fails the suite at boot.

  **v5, as built — the shim cannot carry the flip.** `active_support.set_configs`
  (`railtie.rb:125–130`) forwards the `load_defaults 7.2` value (`:offset`, `configuration.rb:119`)
  to the writer before `config/initializers` run (railtie initializers precede the application's
  `load_config_initializers`: `application.rb:609` puts the application last in `ordered_railties`,
  `engine.rb:644`); the writer warns for anything but `:zone` (`active_support.rb:124–128`); under
  `:raise` the test boot fails (`ActiveSupport::DeprecationException` at `railtie.rb:128`, 141 load
  errors), and under `:notify` production would report a `RailsDeprecation` on every process boot.
  The shim's value arrives only at `after_initialize` (`railtie.rb:99–103`) — the 8.0.2 fix added
  that late forward and did not stop the early one. **Rule (decided at the plan gate):**
  `config.active_support.to_time_preserves_timezone = :zone` in `config/application.rb:20`, directly
  under `config.load_defaults 7.2`, with a why-comment; the shim is committed as generated, all three
  lines commented, for slices 5a and 5b. On 7.2.4 the value is inert (the writer warns only on falsy;
  every `to_time` branches on truthiness), so the line is its own commit **before** the bump — the
  bump alone cannot boot in test. Alternatives rejected: the shim (does not boot); the three
  environment files (rejected files, three edits for one value); an initializer ordered before
  `set_configs` (more code than one line). Behaviour step two, verified: **`Time#zone` is the
  `ActiveSupport::TimeZone` object, not `"PST"`** (`TimeWithZone#to_time` is `getlocal(time_zone)`,
  `time_with_zone.rb:493–495`); the abbreviation is `strftime('%Z')`; for 2026-11-02 10:00 Pacific the
  result is `-0800`, `PST`, `utc_offset` `-28_800`, not DST, and `parse('2026-10-31 10:00').to_time +
  2.days` keeps the wall clock (`-0800`; `:offset` gave `-0700`). The contract spec's deliberate break
  assigns `DateAndTime::Compatibility.preserve_timezone = :offset` inside an `around` — silent on
  8.0.5.1, so the red is the expectation, not the deprecator. **Slice 3's survey decides whether the
  `application.rb` line is deleted, kept or replaced on 8.1.4** (§4.4 item 3).
- *The `app:update` diff shape.* Rule: the table above is the contract; a generated file not in the
  table is a STOP with the diff pasted. **v5:** nothing outside the table except `assets.rb`, created
  and removed in the same run; no STOP.

**Spec plan.** `spec/architecture/rails_upgrade_spec.rb`: version floor → `8.0.5.1`; the offset
example from slice 1 stays green; add "`to_time` keeps the receiver's zone":
`ActiveSupport::TimeZone['Pacific Time (US & Canada)'].parse('2026-11-02 10:00').to_time.zone`
is `"PST"` — the value the 8.0 template documents ("use the timezone of their receivers");
the plan confirms the exact string on 8.0.5.1 before pinning it (deliberate break: set the
config to `:offset` — the suite raises at boot on the deprecation, which is itself the evidence;
paste it). Boundary coverage by name: P4–P7 of §4.0;
`spec/requests/accounts_*` search specs (HWIA key precedence); `spec/models/order_spec.rb` and
`spec/models/order_log_spec.rb` (autosave validation narrowing); `spec/lib/tasks/marketing_source*`
(the one `upsert_all`, 8.0.1 "Fix `insert_all` to not update existing records" — `upsert_all` is
meant to update, unchanged).

**v5, spec plan as built** (`spec/architecture/rails_upgrade_spec.rb`, 11 examples): floor
`8.0.5.1`; the setting example pins `:zone` (replacing slice 1's `true`); "carries the Pacific zone
through `to_time`" pins `zone == TimeZone['Pacific Time (US & Canada)']`, `strftime('%Z') == 'PST'`,
`utc_offset == -28_800` and not `dst?` for 2026-11-02 10:00; "follows DST in arithmetic" pins
`(parse('2026-10-31 10:00').to_time + 2.days).utc_offset == -28_800`; slice 1's offset example stays;
the two member routes are recognized (`recognize_path`, the carts `format: 'json'` default) and their
helpers generate the paths (review round 1); "the other 8.0 defaults stay off" pins
`action_dispatch.strict_freshness` false, `Regexp.timeout` nil and `loaded_config_version` 7.2 (slices
5a and 5b rewrite it). Deliberate breaks seen red: the zone examples via the `around` above; the
setting example by deleting the `application.rb` line (`true` on 7.2.4; a boot raise on 8.0.5.1);
the floor at `8.0.6`; the routes with a member route commented out (`RoutingError`); the defaults with
a shim line uncommented. `spec/lib/tasks/marketing_source*` does not exist — the `upsert_all` is
unspecced (§8). The suite: **2,045 examples, 0 failures, 0 deprecation lines**, plain and with
`CI=1`; the 24 rack warnings unchanged.

**Commit sketch.**
1. `build: upgrade rails to 8.0.5.1` [1]
2. `chore: apply the rails 8.0 app:update binstubs` [1]
3. `chore: add the rails 8.0 framework defaults shim` [2: notes the three copied Active Storage
   migrations were discarded and why]
4. `fix: preserve the receiver zone in to_time` [3, trigger 4: a default flipped before slice 5,
   and why the alternatives were worse]

**v5, as built — five commits, in this order** (insgt-api `chore/rails-upgrade-slice-2`,
`671c3c6b`, `df0e12ec`, `df7826c5`, `f1b2af6e`, `4b464230`): `fix: drop the custom actions from the
carts and headshots route filters` [2] · `fix: preserve the receiver zone in to_time` [3, trigger 4
— before the bump, because the bump cannot boot in test without it and the line is inert on 7.2.4] ·
`build: upgrade rails to 8.0.5.1` [1, with the lock explanation and the break mechanism] · `chore:
apply the rails 8.0 app:update binstubs` [1] · `chore: add the rails 8.0 framework defaults shim`
[2]. The branch was rebuilt once after review round 1 (a spec strengthening folded into commit 1,
commit 3's body corrected); the tree was unchanged by the rebuild.

**Post-deploy verification.** §4.0 P1–P8 and S0, SH, S1–S7, S9 with `8.0.5.1` / `slice 2`. Additions:
S8 `heroku run … rails runner 't = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-11-02 10:00").to_time; puts t; puts t.zone.inspect'`
→ `2026-11-02 10:00:00 -0800` and `"PST"` (DST ended 2026-11-01; on slice 1's `:offset` the second
line printed `nil` — a fixed-offset `Time` has no zone name); S10
`heroku run … rails runner 'puts Rails.application.config.loaded_config_version'` → `7.2`.

**v5, as planned for the push:** S8 prints `t`, `t.strftime("%Z")` and `t.zone.class` →
`2026-11-02 10:00:00 -0800`, `PST`, `ActiveSupport::TimeZone` (on v662: the same first line, an
empty line, `NilClass` — `t.zone.inspect` would print the object, not `"PST"`); S3 also prints
`ActiveSupport.to_time_preserves_timezone.inspect` → `:zone`; **S-RT** — both removed symbols'
routes, `POST /carts/0/request_shoot` and `GET /headshots/0/upload_url`, status **and first body
line** captured on v662 and compared after the push (`404` means the route is gone; the body line
separates the auth layer from a generic rescue); S0 and S6 take the release from a shell variable;
P-PROD (§4.0) with reporting off before the push; P1 twice. Development results, the review record
and the pre-push commands: `docs/runbooks/deploy-rails-upgrade-2.md` (`Ready`).

**Rollback.** `heroku rollback` to the slice 1 release. No schema change.

**Gates.** After plan; after verification. **Effort (estimate):** 8 h plus the deploy morning.
**v5, actual:** survey, plan, implementation, verification and two review rounds on 2026-10-27
(about 6 h of session time); the deploy moved up to Wed 2026-10-28 (§6).

### 4.4 Slice 3 — 8.1.4, the landing target

**Scope.**
1. `Gemfile:28` → `gem 'rails', '~> 8.1.4'`; `bundle update rails`. Expected lock diff: the family
   to 8.1.4; `json` appears as an activesupport dependency (already locked at 2.18.0); `benchmark`,
   `cgi`, `racc` drop from the rails lines but stay in the lock through other dependents.
   **8.1.4 is the floor**: 8.1.0–8.1.3 sort `schema.rb` columns (reverted in 8.1.4), return
   deserialised `Column#default`s (reverted), and break `ActionMailer::Base.mail` returning a
   `MessageDelivery` (fixed in 8.1.4) — `deliver_now` at 18 call sites depends on that.
2. `bin/rails app:update --force` on a throwaway branch again. Table as §4.3 with these deltas:
   **accept** `config/initializers/new_framework_defaults_8_1.rb` (all commented); **reject**
   `config/ci.rb` and `bin/ci` (8.1's local-CI runner, created because the file is absent; its
   template runs `bin/rails test` and `db:seed:replant` — this is an RSpec repo with no CI);
   **the Active Storage migrations**: `install:migrations` skips files whose names already exist,
   and the three have been in `db/migrate/` since 2026-01-29 (v5 — slice 2 did not discard them;
   they predate it and ran in production), so expect nothing copied and leave them.
3. Delete the `to_time_preserves_timezone = :zone` line from `new_framework_defaults_8_0.rb`: on
   8.1 the knob is gone, `to_time` always keeps the receiver's zone, and the writer warns on any
   set value (`8-1-stable active_support.rb:131–137`, forwarded by `railtie.rb:142–147`) — with
   `:raise` the suite would fail at boot. Behaviour does not change (it is already `:zone`).
   **v5:** the line is `config/application.rb:20`, not the shim (§4.3 gap 1 as built). **Slice 3's
   survey decides whether it is deleted, kept or replaced** — how 8.1.4 treats the config is slice
   3's finding; the branch-source claims above were read in October and are the survey's starting
   point, not its conclusion.
4. `db/schema.rb` re-dump (decided OD7), **not from the working development database** (unmerged
   feature-branch migrations would pollute the diff). Method, on the slice 3 branch:
   `RAILS_ENV=test bin/rails db:drop db:create db:schema:load` (loads the committed file into a
   clean test database), then `RAILS_ENV=test bin/rails db:schema:dump` on 8.1.4, then
   `git diff db/schema.rb`. Header-only (`ActiveRecord::Schema[7.2]` → `[8.1]`) → commit; anything
   else → STOP with the diff (the three `t.float` columns at `:903, 970, 972` are the candidates —
   UNVERIFIED whether any is PG `real`, which 8.0's float4/float8 distinction would dump with a
   `limit:`). The account-classification codebase notes' `db/schema.rb` line ranges are unaffected
   by a header-only change.
5. `config.load_defaults` stays `7.2`. `strong_migrations`: no migration in this slice;
   `target_version` untouched; no rolling-deploy window exists because old and new code share the
   schema.

**Breaking changes affecting this codebase** (8-1-stable CHANGELOGs):
- `config/application.rb:20` (the `:zone` line; v5 — not the shim): Active Support 8.1.0
  "Remove deprecated support for `to_time` to preserve the system local time. It will now always
  preserve the receiver timezone." and "Deprecate `config.active_support.to_time_preserves_timezone`."
- `app/controllers/application_controller.rb:303`, `app/controllers/orders_controller.rb:597`:
  Action Pack 8.1.0 "Raise `AbstractController::DoubleRenderError` if `head` is called after
  rendering." The guard renderers return `false`, so a `head` after a `render_*` would now raise;
  the plan traces both paths and adds a spec for each.
- `app/models/concerns/{account_query,property_query}.rb`, `app/models/phone_number.rb:209` (the
  `.or(` sites): Active Record 8.1.0 "Fix `#merge` with `#or` or `#and` and a mixture of attributes
  and SQL strings resulting in an incorrect query." Results change only where the old SQL was
  wrong; the accounts/properties search request specs are run and any changed count is explained.
  **v5:** this fix is also in 7.2.3 (backported); the sites have run it since, so no count should
  change at 8.1 on its account.
- `app/controllers/transactions_controller.rb:55`: Action Pack 8.1.0 "`remote_ip` will no longer
  ignore IPs in X-Forwarded-For headers if they are accompanied by port information." — Stripe's
  `client_ip` may change for forwarded entries carrying `:port`; informational.
- `config/routes.rb:4`: Action Pack 8.1.0 "Add JSON support to the built-in health controller."
  — `/up.json` now returns a body (S1).
- 49 `render json:` sites: Action Pack 8.1.0 "The JSON renderer doesn't escape HTML entities or
  Unicode line separators anymore." — **only under `load_defaults 8.1`** (`escape_json_responses`
  defaults `true` until slice 5b; `renderers.rb:44, 169–172`). Nothing changes in this slice.
- `config/database.yml:4, 24` `pool:`: Active Record 8.1.0 "Introduce new database configuration
  options `keepalive`, `max_age`, and `min_connections` -- and rename `pool` to `max_connections`"
  — `hash_config.rb:73–85` still reads `:pool`; no change (the `pool` *method* is deprecated,
  nothing in app code calls it).
- `spec/support/sql_helpers.rb:13–14`, `spec/lib/city_export_spec.rb:137`: Active Record 8.1.0
  "Change the payload name of `sql.active_record` notification for eager loading from "SQL" to
  "#{model.name} Eager Load"." — both filter only `SCHEMA`/`TRANSACTION`; unaffected.
- `app/models/account_metric.rb:42–44` etc.: Active Record 8.1.0 eagerly validates enum values at
  class load (8.1.2 "Restore the ability of enum to be floats" describes it) — integer values, fine.
- `app/models/user.rb:5` `has_secure_password`: 8.0.3 (already in) "perform confirmation validation
  of the password even when blank".

**Out of scope.** Every `new_framework_defaults_8_1.rb` flag; `config.load_defaults`; `config/ci.rb`;
any gem bump; `rails/all`; the `.or` sites' SQL (observe, do not rewrite); `belongs_to` (slice 4).

**Prerequisites.** Slice 2 deployed: `heroku releases -n 1` shows it; `Rails.version` → `8.0.5.1`
in a production runner; `loaded_config_version` → `7.2`; `master` carries §4.3's commits; SH clean
since slice 2.

**Gaps pinned.**
- *Schema dump outcome.* Rule: commit a header-only diff; STOP on anything else (OD7).
- *`head`-after-render paths.* Rule: if the trace shows a path that renders then `head`s, fix by
  returning early (the existing `render_*` guard idiom), one commit, with the spec that proves it.

**Spec plan.** `rails_upgrade_spec.rb`: version floor → `8.1.4`; zone example stays green (now with
no config line — the deliberate break is to re-add the `:zone` line and paste the boot-time
deprecation raise — **v5:** if the survey keeps or replaces the `application.rb` line, the break
changes with it); `loaded_config_version` pinned at `7.2` for this slice. New request specs for the
two `head` sites. P4–P7 by name; `spec/requests/accounts_*` and `spec/requests/properties_spec.rb`
for the `.or` merges; `spec/requests/transactions_*` for `client_ip`.

**Commit sketch.**
1. `build: upgrade rails to 8.1.4` [1]
2. `chore: apply the rails 8.1 app:update binstubs` [1]
3. `chore: add the rails 8.1 framework defaults shim` [2: why `config/ci.rb`/`bin/ci` were rejected]
4. `chore: drop the to_time config rails 8.1 ignores` [2] — **v5:** only if the survey decides to
   delete the `application.rb` line
5. (`fix: return before head on …` — only if the trace finds one) [2]
6. (`chore: re-dump schema.rb under rails 8.1` — header-only) [2: dumped from a clean test
   database loaded from the committed file, not from development]

**Post-deploy verification.** §4.0 with `8.1.4` / `slice 3`; S1 also `curl -sS https://api.insightphotos.net/up.json`
→ `{"status":"up",…}`; S8 (`to_time`) unchanged from slice 2; S10 → `7.2`; S11 one accounts search
the engineer uses daily in insgt-ops returns the same `totalCount` as before the push.

**Rollback.** `heroku rollback` to the slice 2 release. No schema change (the dump, if committed,
changes no DDL).

**Gates.** After plan; after verification. **Effort (estimate):** 6 h plus the deploy morning.
**Deadline (fact):** before Sat 2026-11-07, 8.0's security end date.

### 4.5 Slice 4 — `belongs_to` optionality follows column nullability

Decided 2026-10-23 (OD4, rule D′). Replaces v1's plan to relocate the Rails 5.0 shim's global
`belongs_to_required_by_default = false` (`config/initializers/new_framework_defaults.rb:20`).

**The rule.** Each `belongs_to`'s `optional:` matches its foreign-key column's nullability in
`db/schema.rb`: a `NOT NULL` column → required (no `optional:`); a nullable column → `optional: true`.
The global `false` is **removed, not relocated**; the Rails ≥ 5.0 default (`true`) then applies.

**Facts (runner over every `ApplicationRecord` descendant, eager-loaded, 2026-10-23):**
- 89 non-polymorphic `belongs_to` reflections.
- 49 sit on `NOT NULL` columns; **all 49 are currently optional** — 47 through the global `false`,
  2 through an explicit `optional: true` (below). None is required today.
- 39 sit on nullable columns; 36 carry an explicit `optional: true`; **3 rely on the global `false`**
  and gain `optional: true`: `Area#area_type` (`area_type_id`), `Listing#property_type`
  (`property_type_id`), `OrderUrlGroup#order` (`order_id`).
- 1 has **no column**: `Area#state` (`app/models/area.rb:7`, `belongs_to :state, optional: true`)
  — `areas` has no `state_id` (`db/schema.rb`, the `areas` table). Dead code; `area.state` returns
  `nil` without a query.
- `TagsResource` is the only model with **two `belongs_to` on one column**: `#user` and `#property`
  both `foreign_key: :resource_id` (`app/models/tags_resource.rb:7–8`), `tags_resources.resource_id`
  `NOT NULL` with `resource_type` as the discriminator (hand-rolled polymorphism, the repo's
  `ResourceType` pattern). Under the rule as written both would become required and **every**
  `TagsResource` save would fail, since exactly one of the two targets exists per row.

**Gaps pinned (OD10 — open, with the recommendation):**
- *The shared-column pair.* Recommended rule, structural rather than a name list (honouring "no
  allowlist"): a foreign-key column that more than one `belongs_to` on the same model points at is
  a hand-rolled polymorphic column; each of those associations is `optional: true` and the
  contract spec asserts, for such a column, that it is `NOT NULL` and that the model validates that
  exactly one target resolves (`TagsResource` — the plan reads its validations). Alternative:
  convert the pair to a real polymorphic `belongs_to :resource, polymorphic: true` — rejected here
  because `resource_type` is an integer from `lib/resource_type.rb`, not a class name; that is a
  data migration, not this slice.
- *The columnless association.* Recommended: delete `Area#state` in its own commit; the contract
  spec fails on any reflection without a column, which is the guard against the next one.

**Behaviour change — named here as the slice's risk:**
- 47 associations start validating presence (49 minus the `TagsResource` pair). A save that today
  fails with `PG::NotNullViolation` (a 500 through `ActiveRecord::NotNullViolation`) now fails as a
  validation error: `render_errors` 422 with "`<Association> must exist`". Client-visible shape
  changes from 500 to 422 on those paths — an improvement, but a change.
- Presence validation of a `belongs_to` checks that the **associated record exists**, not merely
  that the key is set. A row whose `NOT NULL` key points at a missing row (hard deletes are not the
  convention — `CLAUDE.md` "Nothing is hard-deleted" — but `db/schema.rb` declares few foreign-key
  constraints, so dangling keys are possible; UNVERIFIED) becomes unsaveable until repaired. The
  pre-deploy report below counts them; any non-zero count is a STOP.
- Each presence validation loads the associated record unless already loaded: about one extra
  `SELECT` per required association per save (ESTIMATE; e.g. `Order` → `account`, `order_type`: +2
  per `Order` save). The plan measures it with `spec/support/sql_helpers.rb#sql_for` on an `Order`
  save before and after.

**Scope.**
1. Contract spec first (red): for every non-polymorphic `belongs_to` reflection on every model,
   `reflection.options[:optional] == true` iff the column is nullable or shared (OD10), no
   `optional:` iff the column is `NOT NULL`; a reflection whose column does not exist fails.
2. Delete `Area#state` (`area.rb:7`).
3. Add `optional: true` to the three nullable-column associations.
4. Delete `new_framework_defaults.rb:18–20` (the comment and the global `false`); fix the specs
   that hand-build records without their required association by supplying it (per `CLAUDE.md`,
   never by converting a hand-built record to a factory).
5. **Pre-deploy STOP, read-only against production** (decided): `heroku pg:psql --app insgtapi`
   `SELECT table_name, column_name, is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND column_name LIKE '%\_id' ORDER BY 1, 2`
   compared with `db/schema.rb` by a script in the plan; **any mismatch is a STOP** before the
   classification is trusted. Then the report (decided, written into the plan): for each nullable
   FK column, `COUNT(*)` and `COUNT(column)` — columns nullable but always populated become §8
   migration candidates (two-phase `NOT NULL` via strong_migrations, after the Render cutover);
   and (ADDED, this document's recommendation) for each `NOT NULL` FK column behind a required
   association, the count of rows whose referenced row does not exist (`LEFT JOIN … WHERE target.id IS NULL`),
   expected `0` for all — any non-zero is a STOP, because those rows fail validation after the deploy.

**Out of scope.** Flipping any framework default (slice 5); the CSRF lines of the 5.0 shim (inert,
deleted with the file in 5b); converting `TagsResource` to Rails polymorphism; adding `NOT NULL`
constraints (no slice carries a migration); `rails/all`.

**Prerequisites.** Slice 3 deployed and quiet (§2.2) for at least two weekdays: `Rails.version` →
`8.1.4`, `loaded_config_version` → `7.2` in a production runner; SH clean since slice 3.

**Spec plan.** The contract spec above (`rails_upgrade_spec.rb`, `belongs_to` block; the deliberate
break is to re-add the global `false` — then the 47 required associations report `optional?` true
and the block goes red); one request spec per visible path: a create that omits a required
association returns 422 with "must exist" (the plan names the endpoint — candidate: an
`OrdersUser` create without `user_id`); the `TagsResource` exactly-one validation; `Area` saves
without `state`; the `sql_for` measurement on an `Order` save.

**Commit sketch.**
1. `test: pin belongs_to optionality to column nullability` [2: the structural rule for shared columns]
2. `fix: drop the dead Area#state association` [1]
3. `refactor: mark the nullable belongs_to associations optional` [1]
4. `fix: validate presence of belongs_to on NOT NULL columns` [3, trigger 1: the file deleted from is
   named "new framework defaults" while the line was a permanent choice; names the 422-for-500
   change and the dangling-key precondition]

**Post-deploy verification.** §4.0 S0, SH, S1–S7, S9 with `slice 4`; S12 the named create path
without its association → 422 and a JSON `errors` array containing "must exist" (before the push
the same request returned 500); S13 the dangling-key query from the pre-deploy report re-run → still
`0` everywhere; SH specifically: no new `ActiveRecord::RecordInvalid` occurrences whose message
contains "must exist" from paths that call `save!`, and no `ActiveRecord::NotNullViolation` at all.

**Rollback.** `heroku rollback` to the slice 3 release. No schema change.

**Gates.** All. **Effort (estimate):** 6 h plus the deploy morning (Mon 2026-11-09).

### 4.6 Slice 5 — framework defaults, then `config.load_defaults 8.1`

Ten flags make up `load_defaults 8.1` beyond 7.2 (`8-0-stable configuration.rb:337–348`,
`8-1-stable configuration.rb:343–367`). One (`to_time`) is already done. Each row: what it
changes, blast radius with `file:line`, whether it can flip alone.

| # | Flag (file where it lives) | What it changes | Blast radius | Safe alone? |
| :-- | :-- | :-- | :-- | :-- |
| 1 | `active_support.to_time_preserves_timezone = :zone` (8.0) | `to_time` keeps the receiver's zone | done in slices 1–3; on 8.1 the config key is removed | n/a |
| 2 | `action_dispatch.strict_freshness = true` (8.0) | `ETag` beats `Last-Modified` when a request carries both | affects `fresh_when`/`stale?` only — none in `app/` (grep empty); `Rack::ConditionalGet`/`Rack::ETag` in the stack have their own logic | yes — inert |
| 3 | `Regexp.timeout = 1` (8.0; applied as `Regexp.timeout \|\|= 1`) | a process-wide 1 s cap on every regex match; overrun raises `Regexp::TimeoutError` | every regex in the process, gems included; the dense sites are `lib/crmls.rb` (560 lines), `lib/sandicor.rb` (473), `app/models/listing.rb` (1083) over MLS payloads, plus `RawSqlSanitizer` and the parameter underscoring. Currently `Regexp.timeout = nil` (runner) | yes, **in its own deploy (5a)** — the one flag with a real, if unlikely, runtime failure mode; §5 |
| 4 | `yjit = !Rails.env.local?` (8.1) | YJIT off in development and test | production unchanged (`yjit=true` today; `RubyVM::YJIT.enabled?` true) | yes |
| 5 | `action_controller.escape_json_responses = false` (8.1) | `render json:` stops escaping `<`, `>`, `&`, U+2028/9 (`renderers.rb:169–172` passes `escape: false`) | the 49 `render json:` sites (error renderers in `application_controller.rb:219–334`, `site_exports_controller.rb:6,10`, `orders_controller.rb:257`); response bytes change (`<` → `<`), parsed values identical. **JBuilder output is unaffected**: `target!` is `@attributes.to_json` without the option, so Active Support's `escape_html_entities_in_json` default still applies | yes — no client parses bytes; Angular `HttpClient` JSON-parses |
| 6 | `action_controller.action_on_path_relative_redirect = :raise` (8.1) | relative `redirect_to` raises `UnsafeRedirectError` | no `redirect_to` in `app/` (grep empty) | yes — inert |
| 7 | `active_record.raise_on_missing_required_finder_order_columns = true` (8.1) | `first`/`last` without order on a model with no PK raise | no `id: false` table in `db/schema.rb`, no `primary_key =` override — every model falls back to `id` | yes — inert; the flag itself is removed in 8.2 |
| 8 | `active_support.escape_js_separators_in_json = false` (8.1) | AS JSON encoding stops escaping U+2028/U+2029 (`encoding.rb:92–98`) | every JSON body including JBuilder, only for content containing those two characters | yes — JSON permits them raw; same clients |
| 9 | `action_view.render_tracker = :ruby` (8.1) | template dependency tracking for cache digests uses a Ruby parser | the two mailer layouts and ten `app/views/notifier/*` ERB templates; no fragment caching (`perform_caching = false`, `:null_store`); 8.1.4 fixed the non-ASCII digest bug | yes — inert |
| 10 | `action_view.remove_hidden_field_autocomplete = true` (8.1) | form helpers drop `autocomplete="off"` on hidden inputs | no forms (API + mailers) | yes — inert |

None needs a coordinated deploy with insgt-ops/insgt-app: the only client-visible change is JSON
bytes whose parsed value is identical (rows 5 and 8).

**Scope** (two deploys, decided: 5a Tue 2026-11-10, 5b Wed 2026-11-11):
- **5a** — uncomment rows 2 and 3 in `new_framework_defaults_8_0.rb`; contract spec pins
  `Regexp.timeout == 1`. Deploy; S7, then `heroku logs | grep -c "Regexp::TimeoutError"` and SH
  across **one full `import_listings` cycle** (the `Crmls.import` path; its Honeybadger check-in
  from slice 0 shows the cadence — `scheduler.rake` names the tasks but the schedule lives in the
  Heroku Scheduler dashboard, UNVERIFIED from the repo). **The slice 5 plan reads
  `lib/tasks/scheduler.rake` and the check-in history; if the cadence is less than daily, 5b and
  the rehearsal each slip a week** (§6). **v3:** the cadence is hourly (§4.1 item 5), so no slip on
  that account; the slice 5 plan confirms it from the check-in history.
- **5b** — uncomment rows 4–10 in `new_framework_defaults_8_1.rb`; delete the five shim files
  (`new_framework_defaults.rb` — by now only its two inert CSRF lines remain, `:10, :13`, inert
  because `application_controller.rb:3` skips verification; `_6_0.rb`, `_7_2.rb` all comments;
  `_8_0.rb`, `_8_1.rb` now fully applied); set `config.load_defaults 8.1`. **5b does not touch
  `belongs_to`** (slice 4 did). Contract spec pins `loaded_config_version == "8.1"`,
  `Regexp.timeout == 1`, and the JSON escaping behaviour (gap below). Deploy.

**Out of scope.** `rails/all`; any cleanup in §8; any gem bump; anything `belongs_to`.

**Prerequisites.** Slice 4 deployed and quiet (§2.2) for at least one weekday: `Rails.version` →
`8.1.4`, `loaded_config_version` → `7.2` in a production runner; the two 8.x shim files exist with
every line commented.

**Gaps pinned.**
- *How to prove row 5 without a `<` in any real error message.* Rule: a request spec that stubs one
  `render_errors` model error message to contain `<b>` and asserts the body contains `<b>` raw
  after the flip (and `<b>` before — the deliberate break is to re-set the flag to
  `true`); and a JBuilder request spec (`spec/requests/transactions_last4_spec.rb` already reads
  raw JSON) asserting its `<` stays escaped. Alternative rejected: no spec, trust the source.
- *5a's detection window for row 3.* Rule: one full import cycle before 5b (one day in §6); if the
  cadence is longer, 5b waits and §6 moves.

**Commit sketch.**
1. `chore: enable the rails 8.0 request freshness and regexp timeout defaults` [2] — 5a
2. `chore: enable the rails 8.1 framework defaults` [2] — 5b
3. `chore: load the rails 8.1 defaults and remove the shim files` [1]
4. `test: pin the rails upgrade invariants in the contract spec` [1]

**Post-deploy verification.** §4.0 S0, SH, S1–S7, S9 after each deploy; S10 → `8.1` after 5b; S14
`heroku run … rails runner 'puts Regexp.timeout.inspect'` → `1.0`; S15 a known 422 (`POST /states`
with an empty body, authenticated) still parses as JSON with the same `errors` array; S16 over the
following import cycle `heroku logs \| grep -c TimeoutError` → `0` and SH shows no `Regexp::TimeoutError`.

**Rollback.** `heroku rollback` per deploy (5b reverts to 5a's release, 5a to slice 4's).

**Gates.** All. **Effort (estimate):** 6 h plus two deploy mornings.

---

## 5. Risk register

Ranked by likelihood × cost. From slice 0 on, every signal has a Honeybadger reading; the log,
endpoint and Sidekiq readings remain as the independent second source. **"Quiet" (§2.2) is: no
Honeybadger error that was not in the slice 0 baseline, compared by error (v5).**

| Rank | Failure | Where | Detection signal |
| :-- | :-- | :-- | :-- |
| R1 | A gem that hooks Rails fails to load or misbehaves at a major bump — `string_utils`' `active_support/core_ext/string/multibyte` require, the sidekiq-status middleware, Oj, sidekiq 7.3.10's railtie (§3, UNVERIFIED by changelog), **or the honeybadger railtie itself** (the signal must survive each slice) | slices 2–3, at boot or first job | Heroku release fails to boot (`heroku releases` state, `heroku logs --tail` showing `NameError`/`LoadError`/`NoMethodError` with a gem path); `/up` → 5xx (S1) and the uptime monitor; `heroku ps` shows `backgroundworker.1 crashed` and the Sidekiq "Booted Rails" line missing (S2); lograge lines with `status=500` (S7); **S0's `UpgradeMarker` fails to arrive** (the gem did not load) — a silent Honeybadger is itself the alarm |
| R2 | Slice 4's presence validation on 47 associations changes a save's outcome: a path that raised `PG::NotNullViolation` now returns 422, or a row with a dangling `NOT NULL` key becomes unsaveable | slice 4 | Honeybadger: new `ActiveRecord::RecordInvalid` occurrences with "must exist" from `save!` paths, or `ActiveRecord::NotNullViolation` disappearing from a path that used to raise it; lograge 422 counts on create endpoints; the pre-deploy dangling-key report (STOP on non-zero) |
| R3 | The two `to_time` steps (offset in slice 1, zone in slice 2) move a date boundary for a Pacific user — `search_time_params` (`lib/app_param.rb:28–34`) consumers, report dates, `strftime` on derived `Time`s | slices 1–2 | pre-deploy: the time-zone request specs by name (§4.2); post-deploy: S8's offset print, and a date-filtered orders count for a Pacific day compared before/after the push; symptom in the wild: an order "missing" from or "extra" on a day's list in insgt-ops (no exception — the one risk Honeybadger cannot see) |

**v4, R3 step one (slice 1), as verified in development:** no `.to_time` in `app/` or `lib/`
(`grep -rn '\.to_time\b' app lib` → empty); the one indirect caller found in review is
`orders_helper.rb:93`, through `time_ago_in_words`, an elapsed time that the offset does not change; the four
boundary specs pass (39 examples). Production reads: S4, S6 and S8 against v661 captures.

Watched, lower: `Regexp.timeout = 1` (slice 5a) raising `Regexp::TimeoutError` in the MLS imports —
Honeybadger error class `Regexp::TimeoutError` from the `import_listings` rake task or a worker,
ops@ `SystemError::` emails from the CRMLS/Sandicor rescues (`lib/crmls.rb:115,343,446`,
`lib/sandicor.rb:66,120,416`), a missed `import_listings` check-in (S9); the 8.1 `.or`-merge SQL
correctness fix changing a search count (slice 3, S11); `remote_ip` → Stripe `client_ip`
(informational); JSON byte changes (slice 5b, S15); a `RailsDeprecation` notice from an untested
path (slice 1's reporter — a finding, not a failure).

---

## 6. Calendar

Decided 2026-10-23. Effort is a solo-developer estimate; dates respect §2.4 (Mon–Wed mornings,
09:00–11:30 Pacific). Today is Fri 2026-10-23.

| When | What | Hours (estimate) |
| :-- | :-- | :-- |
| **Mon 10-26** | approve v2; merge `docs/rails-upgrade` into the platform repo's `main` (§2.7); **implement and deploy slice 0 (Honeybadger)** | 3 |
| Tue 10-27 | implement slice 1 | 4 |
| **Wed 10-28, 09:30 PT** | **deploy slice 1 (7.2.4)** | 1 |
| Wed 10-28 – Fri 10-30 | implement slice 2 | 8 |
| **Mon 11-02, 09:30 PT** | **deploy slice 2 (8.0.5.1)** | 1 |
| Mon 11-02 – Tue 11-03 | implement slice 3 | 6 |
| **Wed 11-04, 09:30 PT** | **deploy slice 3 (8.1.4)** — before 8.0's EOS Sat 11-07 | 1 |
| Thu 11-05 – Fri 11-06 | implement slices 4 and 5 (no deploys on these days) | 12 |
| **Mon 11-09, 09:30 PT** | **deploy slice 4 (`belongs_to` nullability)** | 1 |
| **Tue 11-10, 09:30 PT** | **deploy 5a** (`Regexp.timeout`, `strict_freshness`); watch one import cycle | 1 |
| **Wed 11-11, 09:30 PT** | **deploy 5b** (8.1 flags, `load_defaults 8.1`, shims deleted) | 1 |
| Wed 11-11 → Wed 11-18 | the quiet week (§2.2) | — |
| **Wed 11-18** | earliest Render database-restore rehearsal (decided OD1) | — |

**v5, as it went:** slice 1 deployed **Tue 10-27** (a day early, inside §2.4; its SH closes Wed 05:15
PT); slice 2 implemented and reviewed the same day and deploys **Wed 10-28, 09:00–11:30 PT** (five
days early); slice 3 may take **Mon 11-02**. The slippage rule applies to the moved slot: review and
merge not complete by 09:00 PT → slice 2 moves to Mon 11-02 and slice 3 loses it; nobody pushes after
11:30 to make the window.

Total ≈ 36 h of implementation plus six deploy mornings. 5a gets one day before 5b; the slice 5
plan reads `lib/tasks/scheduler.rake` and the `import_listings` check-in history for the import
cadence — **if it is less than daily, 5b and the rehearsal each slip a week** (§4.6). **v3:** hourly
(§4.1 item 5); no slip on that account.

**Slippage rule (decided OD1):** a slice that misses its morning moves to the next Mon–Wed morning
and everything after it shifts; slice 3 must still precede Sat 11-07. **A slip moves the rehearsal
to the next Monday or Tuesday; Thanksgiving week (Mon 11-23, Tue 11-24) counts as available.**

---

## 7. Decisions and open questions

Nine questions were open in v1; the engineer settled all nine on 2026-10-23. Two new ones arose
from the facts those decisions surfaced (OD10, OD11). OD11 was settled at the slice 0 plan gate on
2026-10-26; OD10 is **open**.

| ID | Question | Decision (2026-10-23) | Carried by |
| :-- | :-- | :-- | :-- |
| OD1 | Render rehearsal date | Wed 2026-11-18 at the earliest; a slip moves it to the next Mon/Tue, Thanksgiving week available | §6 |
| OD2 | Active Storage routes | Off in slice 1 (`draw_routes = false`), own commit, routes assertion + 404 spec, with a pre-deploy log-history grep whose reach is stated | §4.2, §3.3 |
| OD3 | Error tracker | **Reversed**: Honeybadger as slice 0 (30-day trial), key from ENV only, production only, filter review, `honeybadger test`, a dev-reported failing job, an uptime monitor, a check-in; "quiet" redefined on its baseline | §4.1, §2.2, §2.6, §4.0, §5 |
| OD4 | `belongs_to_required_by_default` | **Rejected the relocation**; rule D′ (optionality = column nullability), its own slice 4 with a contract spec, a production nullability STOP and a null-count report | §4.5 |
| OD5 | Sidekiq | Keep 7.3.10 (Heroku Redis host history; Sidekiq 8 after the cutover); P3 strengthened to "a job runs"; a check-in watches the recurring import | §3.1, §4.0, §4.1, §8 |
| OD6 | `rails/all` | §8 item scoped to Action Cable, Action Text, Action Mailbox; Active Storage stays for OrderProcessingNote; OD2's line revisited at that design, presigned `blob.url(expires_in:)` preferred | §8 item 7 |
| OD7 | `db/schema.rb` re-dump | Yes, from a clean test database loaded from the committed file, never from development; header-only → commit, else STOP | §4.4 step 4 |
| OD8 | Gem-originated deprecations | STOP, as written; the fallback is a callable behaviour (raise by default; log only for a listed gem path **and** message pattern, each pair recorded here with its §8 removal item); slice 1 keeps plain `:raise` and turns production deprecation reporting on through Honeybadger | §4.2 |
| OD9 | Documents branch | `docs/rails-upgrade` stays; verified based on the platform repo's `main` (not insgt-api's `master`, which never carries these files); merges into `main` before slice 0 | §2.7 |
| **OD10 (open)** | Rule D′ meets `TagsResource#user`/`#property` (two `belongs_to` on one `NOT NULL` column) and `Area#state` (no column) | **Recommendation:** the structural shared-column rule (both `optional: true`, spec asserts exactly-one) and deleting `Area#state`. **Against:** the structural rule is a rule the spec must encode, not a plain equality; the alternative (real polymorphism) is a data migration | §4.5 — blocks slice 4's plan |
| OD11 | The decided "check-in on one recurring Sidekiq job" has no such job to attach to | **Settled 2026-10-26 at the slice 0 plan gate, as recommended.** Recommendation: check in from the `import_listings` rake task (the regex-dense path 5a watches; reveals the scheduler cadence); Sidekiq liveness stays with S2 and automatic failure reporting. **Against:** a rake check-in says nothing about Sidekiq throughput; the only continuous Sidekiq signal is its error stream | §4.1 (v3: implemented; the cadence is hourly) |

Deprecation exemptions recorded under OD8: none.

**Slice 2 plan gate (2026-10-27), six questions answered as recommended:** `:zone` in
`config/application.rb`, not the shim; the routes change in scope as commit 1; `bin/setup` rejected;
the three Active Storage migrations stay; slice 1's owed write-back folded into this v5; the branch
built the same day with the §6 slippage rule stated in the runbook. The gate's modifications A–G
(the break mechanism confirmed first, P-PROD with reporting off, the routes example's home, S-RT on
both routes, a scratch-app build if one existed — none does, slice 3 decides the `application.rb`
line, the P1 count not a criterion) are recorded in `docs/plans/rails-upgrade-slice-2.md`.

---

## 8. Follow-up list

Not in any slice. Each is a candidate for its own small change after the Render cutover unless noted.

1. Replace `:unprocessable_entity` with `:unprocessable_content` at the 24 spec sites in 12 files
   (the rack 3.2 rename; rspec-rails calls `Rack::Utils` directly). Can ride along with any slice's
   `test:` commit without changing behaviour — but is not required by any slice.
2. Delete dead files: `config/secrets.yml`, `config/secrets.yml.rb` (carry literal dev/test
   `secret_key_base`), `config/newrelic.yml`, `config/elasticsearch.yml`, `config/spring.rb`,
   `bin/spring`, `bin/update`, and for an API-only app `config/initializers/{content_security_policy,
   cookies_serializer,session_store}.rb`.
3. `config.silence_healthcheck_path = "/up"` (8.0 railties) so lograge stops logging the health check.
4. `config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)` in place of the three-line chain
   at `production.rb:51–53` (the 7.1+ idiom the template uses).
5. lograge 0.14.0 → 0.15.1 ("Fully suppress Rails' default Action View logs on Rails 7.1+").
6. `StringUtils.urlify` → `String#parameterize` at `order.rb:433` and `order_export.rb:133`, then
   drop `string_utils` (2012, abandoned, `mb_chars` user).
7. **`rails/all` → explicit framework requires, scoped to Action Cable, Action Text and Action
   Mailbox only** (decided OD6). Includes removing every `config.action_cable.*`/`action_text.*`/
   `action_mailbox.*` line in `config/environments/*` (`production.rb:36–38`, `development.rb:69`,
   all commented today) and deleting `config/cable.yml`. **Active Storage stays**: the decided
   OrderProcessingNote design uses `has_many_attached :attachments` on S3 with an image thumbnail
   variant (`insgt-platform/docs/plans/order-processing-note.md:19`). **OD2's routes-off line is
   revisited at that feature's design**, with presigned `blob.url(expires_in:)` preferred over
   `rails_blob_path` (consistent with `S3ImageHandler`/Lambda bypassing Rails); if presigned URLs
   are chosen the line stays. The thumbnail variant re-opens the §3.3 libvips posture (ruby-vips
   ≥ 2.2.1, libvips ≥ 8.13 or boot fails on 8.1.3.1+).
8. `Model.connection.select_all` / `exec_query` → `with_connection { |connection| … }` at the ~25
   sites (soft-deprecated since 7.2; silent through 8.1).
9. `config/application.rb:20–21` — the `autoload_paths += Dir["lib/**/"]` / `eager_load_paths`
   lines are redundant with `autoload_lib` (`:17`); remove after a `zeitwerk:check`.
10. `config/sidekiq_status.rb` — nothing requires it (UNVERIFIED whether the status middleware is
    installed in production; P3 from slice 1 on answers it for development); either wire it through
    an initializer or delete it. (Codex, slice 2's review: confirmed never loaded by the boot path;
    still out of every slice's scope.)
11. `config/database.yml` `pool:` → `max_connections:` (8.1 naming; the old key still works).
12. **Sidekiq 8, as its own change after the Render cutover** (decided OD5), gated on the Valkey
    version Render provides and on an audit of everything that reads raw job payloads — 8.0
    changes `created_at`/`enqueued_at` from float seconds to integer milliseconds — `sidekiq-status`
    and any `Sidekiq::Queue`/retry-set readers. Other majors held back on purpose: twilio-ruby 7,
    stripe 20, jwt 3 (twilio pins `< 3`).
13. `params.expect` (8.0) for the `params.require(...).permit` sites — a hardening, not a requirement.
14. zipline's `actionpack < 8.2` cap (or the `zip_tricks` TODO at `Gemfile:39`) — before any 8.2 bump.
15. **`NOT NULL` migration candidates from slice 4's null-count report**: nullable FK columns that
    are always populated get the four-step `NOT NULL` sequence (`README.md` §Migrations) after the
    Render cutover — no slice carries a migration.
16. The three `t.float` columns — confirm `double precision` vs `real` so a future dump has no surprise.
17. Honeybadger Insights (off in slice 0) and the uptime/check-in set — decide after the trial
    whether to keep the subscription and what else to check in (the other three scheduler tasks).
18. OD8 deprecation exemptions — none recorded; this item is the placeholder their removal cites.
19. **The `:raise` gate sees only the classes a spec loads.** `config/environments/test.rb:18` eager
    loads only when `CI` is set, so a deprecation in the class body of a class no spec touches never
    fires locally; it surfaces first in production's eager load (slice 1's reporter catches it there).
    Candidate: run the slice gate's P1 with `CI=1` (eager load on) from slice 2, or eager load in test
    always. Found in slice 1; UNVERIFIED whether any CI sets `CI` today. **v5:** adopted from slice 2
    — P1 runs a second time with `CI=1` (§4.0).
20. The inherited route-absence examples (`spec/architecture/rails_upgrade_spec.rb`, "draws none";
    `spec/requests/active_storage_routes_spec.rb`) pass on an empty route set; slice 2's member-route
    examples fail there, so nothing changes now. Assert a known route before the absence when slice 3
    next touches the contract spec (Codex nit, slice 2's review, both rounds).

---

## 9. Change log

| Version | Date | Change |
| :-- | :-- | :-- |
| 1 | 2026-10-23 | Initial document from the Phase 0 survey (insgt-api `master` eda99450; Rails 8.1.4 is the newest release, 8.2 unreleased). Path 7.2.3 → 7.2.4 → 8.0.5.1 → 8.1.4; four slices; no blocking gem; `to_time` handling pinned per slice from the 7-2/8-0/8-1 branch sources; nine open decisions. |
| 2 | 2026-10-23 | The nine decisions settled (§7). Slice 0 (Honeybadger) added: §4.1, §2.2 "quiet", §2.6, §4.0 S0/SH/S9, §5. Slice 1 gains the Active Storage routes-off commit with its log-history check and production deprecation reporting to Honeybadger (§4.2). Slice 4 is now the `belongs_to` nullability slice (§4.5, rule D′, runner facts: 49 `NOT NULL`/39 nullable/1 columnless/1 shared column); the framework-defaults slice becomes slice 5 with deploys 5a/5b and no `belongs_to` work (§4.6). OD7's dump method (clean test database), OD8's callable fallback, OD6's scoping and the Active Storage stay, OD9's branch verification and §2.7, the revised calendar and slippage rule (§6). P3 strengthened to "a job runs". Two new open questions OD10, OD11. Notes file extended with the `belongs_to`, scheduler, Honeybadger and branch facts. |
| 3 | 2026-10-26 | Slice 0 implemented and verified in development (insgt-api `chore/rails-upgrade-slice-0`: `d4dd6d9e`, `a641c52b`). §4.1: the 6.10.0 `filter_keys` default includes `HTTP_AUTHORIZATION` and a YAML list replaces it (left unset); ENV-over-YAML precedence answered, with `HONEYBADGER_ENV` selecting the YAML section; log breadcrumbs off after the adversarial review; `HTTP_REFERER` kept unfiltered by decision; the spec plan as built (a config spec with a serialized-notice example; `api_key` not nil in test because `.env` holds it); the dev job on its own queue; the start-up log check corrected to "no line at boot"; the uptime check created. OD11 settled; the `import_listings` cadence is hourly (§4.1, §4.6, §6). §4.0 P3: `Sidekiq::Status` returns `nil` in development, for slice 1's plan to pin. Runbook `docs/runbooks/deploy-rails-upgrade-0.md`; notes extended. |
| 4 | 2026-10-26 | Slice 1 implemented and verified in development (insgt-api `chore/rails-upgrade-slice-1`, eight commits `5c9446da`…`a5d9b001`, two review rounds); slice 0 deployed as v659; production now v661 (v660 and v661 are listing fixes from `master`, outside the upgrade). §4.0: P3's id-0 assumption falsified (the worker re-raises) — P3 runs an already-fetched property on its own queue and asserts the log lines; P4 is 4 examples (`:110–148`), not 3. §4.2 item 1: `Gemfile:29`; the lock diff's two `activesupport` constraint lines and minitest's `prism` line named. Item 4: the log-history reach (Heroku 1,500 lines; Papertrail `fixa`, about fourteen days, 0 hits) and the code/database URL audit. Item 5 as built: scope stated (every registered deprecator; not unregistered gem deprecators or `Kernel#warn`); `to_prepare` wiring (a bare initializer reference fails the boot); dedupe key and fingerprint `"<gem_name>: <message>"` (Honeybadger groups on the fingerprint alone; the message carries the call site but not the deprecator); raw `backtrace:`; the subscriber never raises (log line and failure notice, rescued separately; key claimed before notify); `received?` for the deploy probe; the boot window it cannot cover. Spec plan as built (the behavioural gate example; `have_received` for the dedupe). Verification: the pre-push production-config probe, v661 as the "before" and rollback release, the suite on the merge into `master` (2,040 expected), the baseline spanning v659, v660 and v661. §4.3: the 8.0 `to_time` semantics revisited there. §5 R3 step one's evidence. §8 item 19 (the gate sees only loaded classes). Runbook `docs/runbooks/deploy-rails-upgrade-1.md`. |
| 5 | 2026-10-27 | Slice 1 deployed as v662 (2026-10-27 08:15 -0400; S7 and S9 pass; SH pending), with its owed amendments: §2.2 and §5 "quiet" by Honeybadger error; §4.0 S4 `map`, S7 (saved buffer, Papertrail hour, exception classes), SH (two searches, triage rule), S0 (release variable), P-PROD, P1 twice; §4.1 item 7. Slice 2 implemented, verified and reviewed (insgt-api `chore/rails-upgrade-slice-2`, five commits `671c3c6b`…`4b464230`; 2,045 examples; two review rounds, no blocker): §4.3 as built — `:zone` in `config/application.rb` because `set_configs` forwards the `load_defaults` value before `config/initializers` (the shim cannot do it under `:raise`); the routes `only:` validation found and fixed; the three Active Storage migrations pre-existing and kept; `puma.rb` and `bin/setup` rejected; `Time#zone` is a `TimeZone` object; the autosave and `#merge`/`#or` fixes are 7.2.3's, not this slice's; `racc` stays in the lock; the `transform_keys` claim corrected; the commit order (routes, `:zone`, bump, binstubs, shim). §4.4 reworded: slice 3's survey decides the `application.rb` line's fate; the migrations are not re-copied. §6 the calendar as it went; §7 the slice 2 plan-gate decisions; §8 items 10, 19, 20. Slice prompts 2 and 3 annotated; notes extended. Runbook `docs/runbooks/deploy-rails-upgrade-2.md` (`Ready`); plan `docs/plans/rails-upgrade-slice-2.md`. |
