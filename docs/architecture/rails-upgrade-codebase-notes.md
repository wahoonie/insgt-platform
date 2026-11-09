# Rails upgrade — codebase notes

The `file:line` map for `docs/architecture/rails-upgrade.md`. Read at Phase 0 of every slice; verify the entries the slice depends on before surveying fresh. Flat and factual: file, line, what it is, which slice or survey put it there. Paths are `apps/insgt-api` unless prefixed.

Established by the Phase 0 survey of 2026-10-23 against insgt-api `master` at eda99450 (clean tree) and the platform repo `main`; extended the same day for document v2 (the `belongs_to` classification, the recurring tasks, the Honeybadger and branch facts — sections marked "v2"); extended on 2026-10-26 by slice 0 (insgt-api `chore/rails-upgrade-slice-0`, `d4dd6d9e`, `a641c52b` — rows marked "slice 0" and the Honeybadger gem-source section); extended the same day by slice 1 (insgt-api `chore/rails-upgrade-slice-1`, `5c9446da`…`a5d9b001` — rows marked "slice 1" and the "Slice 1" section; every row a slice 1 commit moved was re-verified at `a5d9b001`); extended on 2026-10-27 by slice 2 (insgt-api `chore/rails-upgrade-slice-2`, `671c3c6b`…`4b464230` — rows marked "slice 2" and the "Slice 2" section; rows the slice 2 survey found wrong are marked "corrected slice 2"); extended on 2026-10-30 by slice 3 (insgt-api `chore/rails-upgrade-slice-3`, `a5bfab70`…`5ffe92c4` off `master` f86877f5 — rows marked "slice 3" and the "Slice 3" section; every row whose line a slice 3 commit moved was re-verified at `5ffe92c4`); extended on 2026-11-09 by slice 4 (insgt-api `chore/rails-upgrade-slice-4`, `39b213f3`…`bd0859b8` off `master` 8b726308, merged into `master` as `316fa0e1` — rows marked "slice 4", the "`belongs_to` and column nullability" section rewritten as built, and the "Slice 4" section; every row whose line a slice 4 commit moved was re-verified at `316fa0e1`); extended on 2026-11-09 by slice 5a (insgt-api `chore/rails-upgrade-slice-5a`, `c966bb6e` off `master` `316fa0e1` — rows marked "slice 5a" and the "Slice 5a" section; every row whose line the commit moved was re-verified at `c966bb6e`). Line numbers are as of the latest marked commit; a moved line is a reason to update this file, not to distrust it. Rails-source citations name the branch (`7-2-stable`, `8-0-stable`, `8-1-stable`) and the file; they were read on 2026-10-23 and are stable for released versions.

## Gemfile and lockfile

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `Gemfile` | 4 | `ruby '3.4.12'` — unchanged by every slice (§2); 3.4.10 → 3.4.12 by the patch bump `1497ad8a` (insgt-api `chore/ruby-3-4-12`, deployed 2026-10-29 as v665 `f86877f5`, outside the slices) | survey; Ruby bump |
| `Gemfile` | 29 | `gem 'rails', '~> 8.1.4'` (was `~> 7.2.0` at 28 before slice 0 inserted line 15; `~> 7.2.4` by slice 1; `~> 8.0.5` by slice 2) — the only line the three version slices edit; final | survey; slice 1 `5c9446da`; slice 2 `df7826c5`; slice 3 `3b7780d4` |
| `Gemfile` | 34 | `gem 'sidekiq', '~> 7.0'` — stays on 7.3.x (§3, OD5) | survey; +1 since slice 0 |
| `Gemfile` | 36 | `gem 'string_utils'` — 2012 gem, `urlify` only (see "Gems with Rails coupling") | survey; +1 since slice 0 |
| `Gemfile` | 38 | `gem 'strong_migrations'` | survey; +1 since slice 0 |
| `Gemfile` | 40, 42 | the `zip_tricks` TODO and `gem 'zipline'` — zipline caps actionpack `< 8.2` (§3) | survey; +1 since slice 0 |
| `Gemfile.lock` | 380 | `rails (8.1.4)`; the thirteen components at `8.1.4` with their `(= 8.1.4)` pins; `DEPENDENCIES` `rails (~> 8.1.4)` at 617 | slice 2 `df7826c5`; slice 3 `3b7780d4` |
| `Gemfile.lock` | 4, 36–37 | `action_text-trix (2.1.19)` (depends on `railties` only) and `actiontext (8.1.4)`'s new edge `action_text-trix (~> 2.1.15)` (`actiontext-8.1.4.gemspec:31`) — the one gem the 8.1 bump adds, through `rails/all`; inert (see "Slice 3") | slice 3 `3b7780d4` |
| `Gemfile.lock` | 298 | `minitest (5.27.0)` — downgraded from 6.0.1 by slice 1 (7.2.4's `minitest < 6`); unchanged by slices 2 and 3 although the cap is gone (`--conservative`) | slice 1 `5c9446da`; re-verified slice 3 |
| `Gemfile.lock` | 69, 72, 74, 77 | under `activesupport (8.1.4)` (65): `connection_pool (>= 2.2.5)`, `json` (added by 8.1, 72; `benchmark (>= 0.3)` dropped — `benchmark` stays locked through `Gemfile:10`), `minitest (>= 5.1)`, `uri (>= 0.13.1)` (`uri (1.1.1)` at 553). `cgi (0.5.1)` left the lock in slice 2; `racc (1.8.1)` at 368 stays through other dependents | slice 2 `df7826c5`; slice 3 `3b7780d4` |
| `Gemfile.lock` | 30, 369 | actionpack `rack (>= 2.2.4)` — the `< 3.3` cap lifted; `rack (3.2.4)` unchanged (sidekiq still caps `< 3.3`) | survey; slice 2 |
| `Gemfile.lock` | 460 | `rspec-rails (8.0.4)` (`actionpack >= 7.2`) | survey; re-verified slice 3 |
| `Gemfile.lock` | 509 | `shoulda-matchers (7.0.1)` (`activesupport >= 7.1`; 7.0.0 added Rails 8.1 support) | survey; re-verified slice 3 |
| `Gemfile.lock` | 511, 517 | `sidekiq (7.3.10)` (`rack >= 2.2.4, < 3.3`), `sidekiq-status (4.0.0)` (`sidekiq >= 7, < 9`) | survey; re-verified slice 3 |
| `Gemfile.lock` | 529 | `string_utils (1.0.8)` (`activesupport >= 2.3.5`) | survey; re-verified slice 3 |
| `Gemfile.lock` | 534 | `strong_migrations (2.8.0)` (`activerecord >= 7.2`) | survey; re-verified slice 3 |
| `Gemfile.lock` | 569 | `zipline (2.2.0)` (`actionpack >= 6.0, < 8.2`) | survey; re-verified slice 3 |
| `Gemfile.lock` | 867–868, 870–871 | `RUBY VERSION ruby 3.4.12`, `BUNDLED WITH 4.0.4` (unchanged by the Rails bumps) | survey; Ruby bump `1497ad8a`; re-verified slice 3 |
| `Gemfile` | 15 | `gem 'honeybadger', '~> 6.10'` (locked 6.10.0; runtime deps `logger`, `ostruct`, both already locked; Ruby `>= 3.0.0`; docs: Rails `>= 5.2`, Sidekiq "any") — the one gem added outside `rails` (§2.6); `~> 6.10` blocks a major bump | v2; slice 0 `d4dd6d9e` |

Absent from `Gemfile.lock` (greps on 2026-10-23, empty): `activerecord-postgis-adapter`, `rgeo`, `sentry`, `rollbar`, `newrelic`, `image_processing`, `ruby-vips`, `mini_magick`, `bootsnap`, `brakeman`, `thruster`, `kamal`, `solid_queue`, `solid_cache`, `solid_cable`.

## Application and environments

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `config/application.rb` | 3 | `require 'rails/all'` — loads Active Storage, Action Cable, Action Text, Action Mailbox and the test-unit railtie even though none is used; drives `app:update`'s `skip_*` derivation (§4.2) | survey |
| `config/application.rb` | 12 | `config.load_defaults 7.2` — bumped to `8.1` only in slice 5b | survey; slice 5 |
| `config/application.rb` | (14–21) | the why-comment, `config.active_support.to_time_preserves_timezone = :zone` (was 20) and the blank line after — **deleted** in the 8.1 bump commit: on 8.1.4 any set value deprecates at boot (the test boot raises at `railtie.rb:145`), on 8.0.5.1 the absence did (§4.4 as built). Nothing replaces it; `to_time` keeps the zone unconditionally. Every later `application.rb` line moved up 8 | slice 2 `df0e12ec`; slice 3 `3b7780d4` |
| `config/application.rb` | 38–41 | the why-comment and `config.active_storage.draw_routes = false` (OD2) — the line OrderProcessingNote's design revisits (§8 item 7) | slice 1 `3a6b8e2e`; −8 since slice 3 |
| `config/application.rb` | 17, 20–21 | `config.autoload_lib(ignore: %w[assets tasks])` plus the older `autoload_paths += Dir["lib/**/"]` / `eager_load_paths << lib` (redundant; §8 item 9, whose line numbers now match) | survey; −8 since slice 3 |
| `config/application.rb` | 24–25 | `config.hosts << 'api.insightphotos.net'`, `'insgtapi.herokuapp.com'` | fb2e1924; −8 since slice 3 |
| `config/application.rb` | 36 | `config.api_only = true` | survey; −8 since slice 3 |
| `config/environments/development.rb` | 33 | `config.active_storage.service = :local` | survey |
| `config/environments/development.rb` | 45, 48 | `deprecation = :log`, `disallowed_deprecation = :raise` | survey |
| `config/environments/production.rb` | 33 | `config.active_storage.service = :local` | survey |
| `config/environments/production.rb` | 45, 48 | `config.force_ssl = true`; `ssl_options` excludes `/up` from the redirect — `request.path == '/up'` only, so the JSON `/up.json` that 8.1 serves is not excluded (§8 item 25) | 7fe510d1; slice 3 |
| `config/environments/production.rb` | 51–56 | `config.logger` = `ActiveSupport::Logger.new(STDOUT)` wrapped in `TaggedLogging`; `log_tags = [:request_id]` — the 8.x template would replace this with `TaggedLogging.logger(STDOUT)` (§4.2 reject). STDOUT is why 8.1's boot-time Active Storage WARN shows on every dyno boot and in every `heroku run … rails runner` (slice 3) | survey; slice 3 |
| `config/environments/production.rb` | 36–38 | the commented `config.action_cable.mount_path` / `url` / `allowed_request_origins` lines — removed by §8 item 7 (OD6) together with `development.rb:69` and `config/cable.yml` | v2 |
| `config/environments/production.rb` | 82–85 | the comment, `config.active_support.report_deprecations = true` (84; was `false` at 83, which silenced every deprecator — `railtie.rb:66–70`) and `config.active_support.deprecation = :notify` (85) — every registered deprecator emits `deprecation.<gem>` (OD8). `report_deprecations` is set nowhere else (grep) | survey; slice 1 `e54247cb` |
| `config/environments/production.rb` | 88 | `dump_schema_after_migration = false` | survey; +2 since slice 1 |
| `config/environments/production.rb` | 101 | `host_authorization` excludes `/up` (not `/up.json`, §8 item 25) | 7fe510d1; +2 since slice 1 |
| `config/environments/production.rb` | 103–113 | SendGrid SMTP: `delivery_method = :smtp`, `default_url_options` from `MAILER_URL`, `ActionMailer::Base.smtp_settings` with `SENDGRID_API_KEY` — the reason `app:update`'s production template is rejected (§4.2) | survey; +2 since slice 1 |
| `config/environments/test.rb` | 29 | `show_exceptions = :rescuable` | survey |
| `config/environments/test.rb` | 39 | `host_authorization = { exclude: ->(_request) { true } }` | survey |
| `config/environments/test.rb` | 42 | `config.active_storage.service = :test` | survey |
| `config/environments/test.rb` | 57–58 | `config.active_support.deprecation = :raise` (was `:stderr`) — the deprecation gate; the contract spec asserts both the value and that every registered deprecator raises | survey; slice 1 `f5b30e12` |
| `config/environments/test.rb` | 18 | `config.eager_load = ENV["CI"].present?` — locally the suite loads only what specs touch, so `:raise` never sees a class-body deprecation in an untouched class (§8 item 19) | slice 1 |
| `config/environments/development.rb` | 19 | `config.server_timing = true` — `ActionDispatch::ServerTiming` subscribes to every event, so `listening?("deprecation.rails")` is `true` in development whatever the reporter does; production leaves it at the default `false` | slice 1 |
| `config/honeybadger.yml` | 23–51 | no `api_key`, `env` or `root` (ENV and the railtie supply them). `report_data: false` top-level (23; covers any name `HONEYBADGER_ENV` supplies, which matches no section) then `development`/`test` false and `production` true (25–32); `insights.enabled: false` (36–37); `breadcrumbs.logging.enabled: false` (43–45); `sidekiq.attempt_threshold: 0` (50–51); `request.filter_keys` deliberately unset (a list replaces the gem default that filters `HTTP_AUTHORIZATION`) | slice 0 `d4dd6d9e` |
| `README.md` | 140–144 | the 2015 add-on list: `newrelic:wayne`, `papertrail:choklad` (the log drain slice 1's Active Storage history grep looks for), `sendgrid:starter`, `scheduler:standard`. **Stale** (`heroku addons --app insgtapi`, Dan, 2026-10-26): `papertrail (giving-idly-5477)` on plan `fixa` (about fourteen days searchable in the UI), `fixie tricycle`, `heroku-postgresql essential-1`, `rediscloud 100`, `scheduler standard`, `sendgrid silver`; no New Relic. A README fix belongs in a later insgt-api `docs:` commit | v2; slice 1 |
| `README.md` | 146–148 | "several cron jobs setup to run under the Heroku Scheduler add on" — the cadence lives in the Heroku dashboard, not the repo (UNVERIFIED) | v2 |
| `README.md` | 162–170 | the migrating-deploy recipe (`pg:backups:capture`, `maintenance:on`, `git push heroku master`, `db:migrate`, `restart`, `maintenance:off`) — the upgrade slices need only the push and `heroku rollback` (§2.5) | v2 |
| `config/environments/test.rb` | 61, 64 | `disallowed_deprecation = :raise`, `disallowed_deprecation_warnings = []` | survey |
| `config/environment.rb` | 7, 9 | `Jbuilder.key_format camelize: :lower`; `Phoner::Phone.default_country_code = '1'` — why `app:update`'s `environment.rb` is rejected | survey |
| `config/boot.rb`, `config.ru` | — | stock. `app:update` regenerates `boot.rb` (`configs` → `create_boot_file`) and found it identical in slice 2 (no bootsnap); `config.ru` is not touched; `public/` is skipped for an API app (`app_generator.rb:220–221`) | survey; corrected slice 2 |
| `config/puma.rb` | 23–24, 27, 30, 34 | threads from `RAILS_MAX_THREADS` (3), port, `plugin :tmp_restart`, pidfile. **Not** identical to the 8.0 template minus comments: the template adds `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` and double quotes, so slice 2 rejected it under §4.3's "comment-only" rule | survey; corrected slice 2 |
| `config/database.yml` | 4, 24 | `pool:` — still read by 8.1 (`8-1-stable activerecord/.../database_configurations/hash_config.rb:73–85`, `fetch(:pool, 5)`); only the Ruby method `pool` is deprecated | survey |
| `config/storage.yml` | 1–7 | `test` and `local` Disk services only | survey |
| `config/cable.yml` | 7–10 | production `redis` adapter on `REDIS_URL` — unused (no Action Cable code) | survey |
| `config/secrets.yml`, `config/secrets.yml.rb` | 13, 16, 21 | tracked, dead since 7.2 removed `Rails.application.secrets`; carry literal dev/test `secret_key_base` values (§8) | survey |
| `config/newrelic.yml`, `config/elasticsearch.yml`, `config/spring.rb`, `bin/spring`, `bin/update` | — | orphaned (no matching gem); `bin/dev` does not exist in this repo — the platform's `bin/dev` drives `Procfile.dev` (§8). The 8.0 `app:update` offers a two-line `bin/dev` and a `bin/setup` whose tail execs it; slice 2 rejected both and took only `bin/rails` and `bin/rake` (double quotes) | survey; slice 2 `f1b2af6e` |
| `config/sidekiq_status.rb` | 1–15 | configures the sidekiq-status middleware; nothing requires this file (grep empty) and `config/sidekiq.yml` is absent — UNVERIFIED whether it loads in production (§8). Slice 0 observed `Sidekiq::Status::status(jid) => nil` and `get_all => {}` in development for a job that ran — the middleware is not installed there (§4.0 P3, v3) | survey; slice 0 |
| `Procfile` | 1–2 | `web: bundle exec puma -C config/puma.rb`; `backgroundworker: bundle exec sidekiq -c 4`; no release phase | survey |
| `.env` | — | the survey said it sets `SECRET_KEY_BASE` (8.0.2+/8.1 use it in dev/test instead of `tmp/local_secret.txt`); slice 2's anchored grep (`^SECRET_KEY_BASE=`) found 0 lines and the file was not re-read (UNVERIFIED which form, if any). Inert either way: no `secret_key_base`, `message_verifier` or cookie use in `app/`, `lib/`, `config/` | survey; slice 2 |

## Initializers — the five framework-defaults shims and the rest

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `config/initializers/new_framework_defaults.rb` | 10 | `action_controller.per_form_csrf_tokens = false` — inert: CSRF verification is skipped (see `application_controller.rb:2–3`); deleted with the file in slice 5b | Rails 5.0 shim, 2bfb1f01 |
| `config/initializers/new_framework_defaults.rb` | 13 | `action_controller.forgery_protection_origin_check = false` — inert, same reason; deleted with the file in slice 5b | Rails 5.0 shim |
| `config/initializers/new_framework_defaults.rb` | (15–18) | the `to_time` comment pair, `ActiveSupport.to_time_preserves_timezone = false` (was 17, the **only** Rails deprecation in the baseline) and the blank line after it — **deleted**; `load_defaults 7.2`'s value `true` now stands. Restoring line 17 under `:raise` fails the suite at boot (`ActiveSupport::DeprecationException`, 139 load errors) | Rails 5.0 shim; slice 1 `a59df0b0` |
| `config/initializers/new_framework_defaults.rb` | (14–16) | the blank separator, the comment and `active_record.belongs_to_required_by_default = false` (was 19–20) — **deleted, not relocated, in slice 4** (rule D′, §4.5, OD4); the file now ends at 13 lines, on the second CSRF line; `grep -rn belongs_to_required_by_default config app` → empty. See "`belongs_to` and column nullability" below for what depends on it | Rails 5.0 shim; slice 4 `c055b8ed` |
| `config/initializers/new_framework_defaults_6_0.rb` | 1–45 | entirely commented out — dead; deleted in slice 5b | survey |
| `config/initializers/new_framework_defaults_7_2.rb` | 1–70 | entirely commented out — dead (`load_defaults 7.2` already applies all of it); deleted in slice 5b | survey |
| `config/initializers/new_framework_defaults_8_0.rb` | 1–30 | the 8.0.5.1 template verbatim, **all three lines commented** (`:18` `to_time_preserves_timezone = :zone`, `:25` `strict_freshness = true`, `:30` `Regexp.timeout = 1`); the `to_time` flip lived in `application.rb:20` (see "Slice 2") until slice 3 deleted it; **`:18` is never uncommented** (on 8.1 any value deprecates); the file deleted in 5b. **Slice 5a uncommented `:25` (`Rails.application.config.action_dispatch.strict_freshness = true`) and `:30` (`Regexp.timeout = 1`)**; the file stays 30 lines. `:30` applies: a direct global, stored as the Float `1.0`. **`:25` reaches only the config.** The action_dispatch railtie copied the value to `ActionDispatch::Http::Cache::Request` before `config/initializers` ran (the "Slice 5a" section), so the applied value stays `false` until 5b's `load_defaults 8.1`. The contract spec pins config `true` / applied `false` and the timeout `1.0` | slice 2 `4b464230`; slice 3; slice 5a `c966bb6e` |
| `config/initializers/new_framework_defaults_8_1.rb` | 1–74 | the `railties-8.1.4` template verbatim (`cmp` with `new_framework_defaults_8_1.rb.tt`; no ERB), **all six flags commented**: `:28` `action_controller.escape_json_responses = false`, `:36` `active_support.escape_js_separators_in_json = false`, `:46` `active_record.raise_on_missing_required_finder_order_columns = true`, `:61` `action_controller.action_on_path_relative_redirect = :raise`, `:66` `action_view.render_tracker = :ruby`, `:74` `action_view.remove_hidden_field_autocomplete = true` — §4.6 rows 5–10; row 4 (`yjit`) has no line here and arrives with `load_defaults 8.1`. Flipped and deleted in 5b; the contract spec pins the four runtime values until then. **`:36` is config-only under `load_defaults 7.2`**, the same mechanism as the 8.0 shim's `:25` through `active_support.set_configs`; the other five apply (plan fact 16, re-run at `316fa0e1`) | slice 3 `847a85d6`; slice 5a |
| `config/initializers/deprecation_reporting.rb` | 17 | `Rails.application.config.to_prepare { DeprecationReporter.subscribe } if Rails.env.production?` — see the "Slice 1" section for why `to_prepare` | slice 1 `e54247cb` |
| `config/initializers/strong_migrations.rb` | 7 | `start_after = 20260806120000` | pre-survey |
| `config/initializers/strong_migrations.rb` | 11–12, 14 | Heroku Postgres essential-1 reports PG 15.17 (2026-08-07); "REVISIT AT THE RENDER.COM CUTOVER" | pre-survey |
| `config/initializers/strong_migrations.rb` | 18 | `target_version = 15` — never edited by this upgrade (§2 trap) | pre-survey |
| `config/initializers/json_param_key_transform.rb` | 2–6 | replaces `ActionDispatch::Request.parameter_parsers[:json]` with a deep-underscoring parser (`deep_transform_keys!`) | survey |
| `config/initializers/wrap_parameters.rb` | 7–9 | `wrap_parameters format: [:json]` — untouched by 8.0/8.1 | survey |
| `config/initializers/cors.rb` | 8–55 | customised `Rack::Cors` allow-list (`:41` names the Lambda photo resizer) — why the template `cors.rb` is rejected | survey |
| `config/initializers/filter_parameter_logging.rb` | 4–8 | customised filter list (`password password_confirmation code token passw email secret key crypt salt certificate otp ssn phone phone_number phone_number_formatted`, partial-matched) — template rejected; **reused by Honeybadger for request notices only** (read from the request's `action_dispatch.parameter_filter`, gem `notice.rb:576–582`; Sidekiq job args never pass through it). Partial match filters `area_code` (via `code`) and `access_token` (via `token`); a bare `number` param goes in clear. Reviewed in slice 0 on a real notice | survey; slice 0 |
| `config/initializers/inflections.rb` | — | identical to the stock template (no acronyms) | survey |
| `config/initializers/content_security_policy.rb`, `cookies_serializer.rb:5`, `session_store.rb:1` | — | stock files meaningless in an API-only app; `app:update` keeps CSP because it exists; all three are §8 cleanups. The 8.1 template adds four comment lines (`content_security_policy_nonce_auto`) to the CSP file — rejected in slice 3 | survey; slice 3 |
| `config/initializers/lograge.rb` | 1–7 | lograge enabled outside development; `custom_options` reads only `event.time` | survey |
| `config/initializers/geocoder.rb` | 2–19 | Google lookup, `cache: Redis.new` at 16 | survey |
| `config/initializers/multijson.rb` | 1–2 | `MultiJson.use(:oj)` — the only Oj coupling | survey |
| `config/initializers/anthropic.rb` | 2 | `Rails.application.credentials.dig(:anthropic, :api_key)` fallback — the only credentials read | survey |
| `config/initializers/redis.rb` | 1–3 | `$redis` from `REDISCLOUD_URL` | survey |
| `config/initializers/puma_worker_killer.rb` | 1 | rolling restart every 12 h | survey |

## Active Storage surface (CVE-2026-66066 exposure)

| File / command | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `bin/rails routes` | — | 592 routes at the survey, **9** of them Active Storage (`/rails/active_storage/{blobs,representations,disk,direct_uploads}`), drawn because `rails/all` loads the engine and `draw_routes` was unset. After slice 1: **583, 0 Active Storage**; `POST /rails/active_storage/direct_uploads` → 404 (was 400, `ParameterMissing`) | survey; slice 1 `3a6b8e2e` |
| every repo under `apps/`, `lib/`, `functions/` | — | slice 1 audit (2026-10-26): no `rails_blob_*`, `rails_representation_*`, `rails_storage_*`, `rails_disk_service`, `rails_direct_uploads`, `DirectUpload`, `@rails/activestorage` or `/rails/active_storage`; every `url_for` hit is an app method of that name. `insgt-galleries` and `insgt-virtual-tour` comment out `require "active_storage/engine"` (`config/application.rb:8`) | slice 1 |
| dev restore (latest order 2026-10-24) | — | slice 1 audit: no `active_storage_*` table; 0 of 229 text/varchar/json columns in 52 tables contain `rails/active_storage`. Hosts in the 50 URL-like columns: S3 buckets (`insight-public`, `insgt-video`, `insgt-youtube`, `insgt360`, `insgt360stock`, `insgt-misc`, `insgt-site-data`), Matterport, YouTube, Vimeo, Zillow, the tour domains, customer sites — never the API host | slice 1 |
| `lib/cloudfare.rb`, `app/models/concerns/s3_image_handler.rb`, `lib/image_handler.rb` | 15; 271; 40–46, 123, 129 | the media URL builders: `"#{ENV['IMAGE_HANDLER_ENDPOINT']}/<base64 edits>"` (the image handler, `d2e08hhdrjhri.cloudfront.net`), `https://<bucket>.s3-us-west-1.amazonaws.com/<key>`, presigned S3 upload/download URLs — no Rails route in any | slice 1 |
| `insgt-platform/docs/plans/order-processing-note.md` | 19 | D2: `has_many_attached :attachments` via Active Storage on S3, an image thumbnail variant for the ops list, signed URLs for video — why the engine stays (OD6) and where the routes-off line is revisited (§8 item 7) | v2 |
| `db/schema.rb` | — | no `active_storage_*` table (grep empty) — a `direct_uploads` POST fails on the missing table | survey |
| `app/`, `lib/`, `config/`, `spec/` | — | no `has_one_attached`, `has_many_attached`, `variant`, `image_processing` (grep empty) | survey |
| `bin/rails runner` | — | `variant_processor=:vips` (default), `image_processing? false`, `ruby-vips? false`, `mini_magick? false` | survey |
| `activestorage-8.1.4/lib/active_storage/engine.rb` | 94–129 | 8.1 resolves `ActiveStorage.variant_transformer` at boot and rescues the `LoadError`: with no `image_processing` gem it logs `Generating image variants require the image_processing gem. Please add gem "image_processing", "~> 1.2" … or set config.active_storage.variant_processor = :disabled.` once per process boot (development: Sidekiq's first log line; production: STDOUT). 8.0.5.1 required the gem only when generating a variant (`transformers/image_processing_transformer.rb:7`); a production-mode boot of 8.0.5.1 prints nothing. §8 item 7 | slice 3 |
| `config/initializers/cors.rb` | 41 | the Lambda photo resizer origin — derivatives are produced outside Rails (`app/workers/photo_resize_worker.rb`, `photo_resize_batch_worker.rb`, `lib/image_handler.rb`, the `S3ImageHandler` concern) | survey |

## Time zones and `to_time`

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/app_param.rb` | 28–34 | `search_time_params` swaps `Time.zone` to `current_user.time_zone` around parsing | survey |
| `app/`, `lib/` | — | `.to_time` appears nowhere (grep empty); `in_time_zone` 25 sites, `Time.zone` 14, `Time.now` 135, `.to_date` 26, `strftime` 54 | survey |
| `app/helpers/orders_helper.rb` | 93 | `time_ago_in_words(timestamp)` — the one indirect `to_time` caller found (slice 1 review); an elapsed time, unchanged by the offset step | slice 1 |
| `spec/architecture/rails_upgrade_spec.rb` | 20–58 | pins **that `Rails.application.config.active_support` has no `:to_time_preserves_timezone` key** (26–28; slice 1 pinned `true`, slice 2 `:zone`; on 8.1 the reader itself deprecates, so the example reads the config hash), the Pacific `to_time.utc_offset == -25_200` (2026-10-23 10:00), the zone object / `%Z` `PST` / `-28_800` / not DST for 2026-11-02 10:00, and `+ 2.days` across DST end → `-28_800`. On 8.1 the behaviour examples have no break (the knob is gone; `DateAndTime::Compatibility.preserve_timezone` no longer exists); the key example's break is the line re-added → a boot raise | slice 1 `a59df0b0`; slice 2 `df0e12ec`, `df7826c5`; slice 3 `3b7780d4` |
| `7-2-stable railties/lib/rails/application/configuration.rb` | 117 | `load_defaults "5.0"` sets `ActiveSupport.to_time_preserves_timezone = true` directly | source |
| `7-2-stable activesupport/lib/active_support.rb` | 117–125 | writer warns `unless value` ("pre-Ruby 2.4 behavior … removed in Rails 8.0") | source |
| `8-0-stable railties/.../configuration.rb` | 119, 337–348 | `5.0` sets the config key to `:offset`; `8.0` sets `:zone`, `strict_freshness = true`, `Regexp.timeout ||= 1` | source |
| `8-0-stable activesupport/lib/active_support.rb` | 118–132 | writer warns for `false` and for any value other than `:zone` | source |
| `8-0-stable activesupport/lib/active_support/railtie.rb` | 99–103, 125–130 | after_initialize and `set_configs` both forward the config key to the writer — **and `set_configs` runs before `config/initializers`** (railtie initializers precede the application's `load_config_initializers`: `railties application.rb:609` puts the app last in `ordered_railties`, `engine.rb:644`), so a shim value arrives after the `load_defaults` value (`:offset`) has already warned; under `:raise` the boot fails at `railtie.rb:128` (slice 2, verified on 8.0.5.1) | source; slice 2 |
| `8-1-stable railties/.../configuration.rb` | 335–342, 343–367 | `8.0` block has no `to_time` line; `8.1` block = yjit, `escape_json_responses`, `action_on_path_relative_redirect`, `raise_on_missing_required_finder_order_columns`, `escape_js_separators_in_json`, `render_tracker`, `remove_hidden_field_autocomplete`. **Installed 8.1.4 (slice 3):** `when "8.1"` at 343–367 as listed, and **no `load_defaults` block sets `to_time_preserves_timezone` at all** (the 5.0 `:offset` line is gone too), so with no app line nothing reaches the writer | source; slice 3 |
| `8-1-stable activesupport/lib/active_support.rb` | 124–129, 131–137 | **the reader warns too** (124–129, installed 8.1.4 — slice 3) and the writer always warns (131–137): "`config.active_support.to_time_preserves_timezone` is deprecated and will be removed in Rails 8.2". Under test's `:raise` a reader call raises; under production's `:notify` it is a `RailsDeprecation` notice — no command on 8.1 may read it | source; slice 3 |
| `8-1-stable activesupport/lib/active_support/railtie.rb` | 142–147 | `set_configs` still forwards any set key to the writer — a `:zone` line present on 8.1 warns at boot; on 8.1.4 the test boot raises at `:145` (`Kernel#public_send`, called from `config/environment.rb:5`), seen in slice 3 | source; slice 3 |
| `8-1-stable activesupport/lib/active_support/core_ext/date_and_time/compatibility.rb` | — | no `preserve_timezone` (only `utc_to_local_returns_utc_offset_times`); `to_time` always keeps the receiver's zone — installed 8.1.4 `time_with_zone.rb:501–503` is `@to_time_with_timezone \|\|= getlocal(time_zone)` | source; slice 3 |
| 8.0.5.1 `activesupport/lib/active_support/time_with_zone.rb` | 493–501 | `to_time`: `:zone` → `getlocal(time_zone)` (a Ruby `Time` carrying the `ActiveSupport::TimeZone` object — `Time#zone` returns the object, `strftime('%Z')` the abbreviation); truthy → `getlocal(utc_offset)`; else `getlocal` | slice 2 |
| 7.2.4 `activesupport/lib/active_support/time_with_zone.rb`, `core_ext/date_time/compatibility.rb`, `core_ext/time/compatibility.rb` | 485–491; 16; 14 | every `to_time` branches on truthiness and the 7.2.4 writer warns only `unless value` (`active_support.rb:117–125`) — a `:zone` value set on 7.2.4 is inert (reads as `true`) | slice 2 |
| `bin/rails runner`, 7.2.4 vs 8.0.5.1 | — | `TimeZone['Pacific Time (US & Canada)'].parse('2026-11-02 10:00').to_time`: both `2026-11-02 10:00:00 -0800`; 7.2.4 `zone` `nil`, `%Z` `""`; 8.0.5.1 `zone` the TimeZone object, `%Z` `"PST"`; `parse('2026-10-31 10:00').to_time + 2.days` → 7.2.4 `-0700`, 8.0.5.1 `-0800` | slice 2 |

## Raw SQL and connection handling

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/account.rb` | 452 | `Account.connection.select_all` | survey |
| `app/models/order_log.rb` | 120 | `OrderLog.connection.select_all` | survey |
| `app/models/photo.rb` | 262 | `Tag.connection.select_values` | survey |
| `app/models/listing.rb` | 293, 850 | `Listing.connection.select_all` | survey |
| `app/models/property.rb` | 109 | `Property.connection.select_all` | survey |
| `app/models/user.rb` | 107 | `User.connection.select_all` | survey |
| `app/models/concerns/account_query.rb` | 55 | `User.connection.select_all` | survey |
| `app/models/concerns/user_query.rb` | 279 | `User.connection.select_all` | survey |
| `app/models/concerns/order_sql.rb` | 273 | `Order.connection.select_all` | survey |
| `app/models/concerns/orders_user_query.rb` | 35 | `User.connection.select_all` | survey |
| `app/controllers/orders_controller.rb` | 303, 313 | `Order.connection.select_all`, `OrderService.connection.select_all` | survey |
| `app/services/headshot_host_roi.rb` | 112 | `MarketingEvent.connection.select_all` | survey |
| `app/services/{marketing_source_metrics_service,account_order_metrics_service,marketing_source_accounts_service}.rb`, `app/services/account_metrics/calculator.rb`, `app/services/system_metrics/calculator.rb` | 85, 87, 54, 330, 183 | `ActiveRecord::Base.connection.exec_query` | survey |
| `app/services/event_attribution.rb` | 147 | `Account.connection.select_all` | survey |
| `lib/listing_export.rb`, `lib/order_url_export.rb` | 114, 140; 97 | `Listing.connection.exec_query`, `Photo.connection.exec_query`, `OrderUrl.connection.exec_query` | survey |
| `spec/support/crud_attribution.rb`, `spec/support/explicit_account_ids.rb` | 18; 13 | `ActiveRecord::Base.connection.execute` | survey |
| `app/`, `lib/`, `spec/` | — | no `lease_connection`, `with_connection`, `permanent_connection_checkout`, `raw_connection` (grep empty); runner: `permanent_connection_checkout=true` | survey |
| 8.0.5.1 `activerecord/lib/active_record/connection_handling.rb` | 275–282 | `connection` "Soft deprecated"; the deprecation fires only when `ActiveRecord.permanent_connection_checkout` is `:deprecated` — it is `true` here, so the ~25 sites are silent on 8.0.5.1 (runner) | slice 2 |
| `app/models/concerns/{account_query,property_query,user_query,notification_query}.rb`, `app/models/phone_number.rb` | 378; 61, 70, 79–81; 314; 29, 35; 209 | the 10 `.or(` sites. The "`#merge` with `#or` … mixture of attributes and SQL strings" fix is in **7.2.3** (activerecord 7.2.4 `CHANGELOG.md`, 7.2.3 section, line 124), not new at 8.0 or 8.1 | survey; corrected slice 2 |

## Controllers, rendering, params

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/controllers/application_controller.rb` | 1 | `ApplicationController < ActionController::Base` (not `ActionController::API`) | survey |
| `app/controllers/application_controller.rb` | 2–3 | `protect_from_forgery with: :null_session`; `skip_before_action :verify_authenticity_token` — the only CSRF references in `app/controllers` | survey |
| `app/controllers/application_controller.rb` | 206–208 | `deep_underscore_params` → `AppParam.deep_underscore_params` | survey |
| `app/controllers/application_controller.rb` | 303 | `head :no_content` — 8.1 raises `DoubleRenderError` if `head` follows a render **or another `head`** (`actionpack-8.1.4 head.rb:28`) | survey; slice 3 |
| `app/controllers/application_controller.rb` | 302–305, 307–310 | `render_no_content` (`head :no_content; false`) — 35 direct call sites outside its definition; `render_ok` is `render json: {}, head: :ok` (a render with an ignored `head:` option, not a `head`) | slice 3 |
| `app/controllers/application_controller.rb` | 181–184, 186–194, 196–204 | `destroy_instance` (destroy, then `render_no_content`; 51 calls), `find_instance` (`find_by(id:, status_type: active)`; on a miss `render_no_content` and returns `false`, else sets `@<table_name.singularize>`; **55 calls**), `find_instance_by_public_id` (1 call) — with the two literals, the five producers of every `head` in the app. The side-effecting contract is §8 item 21 | slice 3 |
| `app/controllers/application_controller.rb` | 219–234, 308–334 | the `render json:` guard renderers (401/404/400/422), incl. `:unprocessable_entity` at 329, 334 | survey |
| `app/controllers/orders_controller.rb` | 597 | `head :ok` — the first statement of `order_event` (594–616) after its before-actions; a before-action that renders halts the chain (`actionpack-8.1.4 callbacks.rb:36`), so nothing can have rendered before it | survey; slice 3 |
| `app/controllers/orders_controller.rb` | 681–696, 698–703 | `set_order` (`access_token` branch: `set_order_with_access_token` + one `render_no_content`; JWT branch: `set_order_for_current_user`; neither: `render_unauthorized` — `55c86f1d`, v664) and `set_order_for_current_user`: `find_instance` (699), **`return if performed?` (700)**, the trailing guard (702) | `55c86f1d`; slice 3 `a5bfab70` |
| `app/controllers/transactions_controller.rb`, `raw_photos_controller.rb`, `listing_rooms_controller.rb`, `listing_property_features_controller.rb` | 74–77; 54–62; 30–33; 30–33 | the other four setters slice 3 guarded: `find_instance`, **`return if performed?`** (75; 55; 31; 31), the trailing `render_no_content if @x.blank? \|\| !@x.can_access?(current_user)` (its `blank?` half now dead; kept). Raw photos also: both branch guards `return render_no_content if …` (57, 60), so the trailing guard (62) answers only a request with neither credential — `RawPhotosController` has no auth before-action | slice 3 `a5bfab70` |
| `app/controllers/orders_controller.rb` | 473–484 | `download_files` (the Lambda's path, exempt from JWT): `find_instance` then `return render_unauthorized if @order.blank?` — a render after a `head` on a missing order, `DoubleRenderError` on 8.0.5.1 and 8.1.4 alike; pre-existing, §8 item 22 | slice 3 |
| `app/controllers/notification_audiences_controller.rb` | 38–41 | `set_notification_audience`: `find_instance`, then `@notification_audience.notification_id` raises `NoMethodError` on a miss before any second `head`; pre-existing, §8 item 23 | slice 3 |
| `app/controllers/accounts_users_controller.rb` | 35–37 | the comment naming `performed?` as what a trailing guard should have checked — before slice 3 the only `performed?` in `app/` (grep) | slice 3 |
| `app/controllers/orders_controller.rb` | 257 | a `render json:` path using `deep_camelize` (per `CLAUDE.md`) | survey |
| `app/controllers/site_exports_controller.rb` | 6, 10 | `render json:` bypassing JBuilder | survey |
| `app/controllers/sessions_controller.rb`, `app/controllers/headshots_controller.rb` | 36; 24, 35 | the other `:unprocessable_entity` sites (Rails converts the symbol; no warning) | survey |
| `app/controllers/transactions_controller.rb` | 55 | `request.remote_ip` → Stripe `client_ip` (8.1 `remote_ip` change: the port is stripped before `IPAddr` validation, `actionpack-8.1.4 remote_ip.rb:179–196`; `X-Forwarded-For: 203.0.113.7:1234` gave `REMOTE_ADDR` on 8.0.5.1 and `203.0.113.7` on 8.1.4 — slice 3's `Rack::MockRequest` probe). No spec exercises `remote_ip` | survey; slice 3 |
| `app/views/**/*.jbuilder` | — | 140 templates; `JbuilderTemplate#target!` is `@attributes.to_json` (jbuilder-2.14.1 `lib/jbuilder.rb:271–273`), so 8.1's `escape_json_responses` (renderer-level, `8-1-stable actionpack/lib/action_controller/metal/renderers.rb:169–172`) does not touch JBuilder output; `escape_js_separators_in_json` (AS-level, `8-1-stable activesupport/lib/active_support/json/encoding.rb:92–98`) does | survey |
| `config/routes.rb` | 4 | `get 'up' => 'rails/health#show'`; 360 lines, 592 routes, no `mount`, no multi-path routes, no Sidekiq web. On 8.1.4 `Rails::HealthController#render_up` (`railties-8.1.4 health_controller.rb:45–50`) responds `format.html` first, then `format.json` → `{"status":"up","timestamp":…}`: `/up` unchanged, `/up.json` JSON (8.0.5.1 rendered the HTML page for both). No client calls `/up` (slice 3 grep of every app); the uptime check is on `/up` (Success) | 7fe510d1; slice 3 |
| `config/routes.rb` | 6, 19; 11, 21 | `resources :carts … only: %i[show update destroy create]` and `resources :headshots, only: %i[create update destroy]` — slice 2 removed `request_shoot` and `upload_url` from the lists (8.0.0.rc1 raises `ArgumentError` for a non-default action in `only:`/`except:`, `actionpack mapper.rb:1182–1186`); the actions are declared in the member blocks at 11 and 21, so the route table is unchanged (583; helpers `request_shoot_cart`, `upload_url_headshot`) | slice 2 `671c3c6b` |

## Models, mailers, workers

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/account_metric.rb`, `app/models/account.rb`, `app/models/order_type.rb` | 42–44; 91; 87 | the five `enum :name, {…}, prefix: true` declarations — positional form, unaffected by 8.0's keyword-argument removal | survey |
| `app/models/order.rb` | 303, 306, 308 | `serialize … coder: HashSerializer` on jsonb columns (`db/schema.rb:776–777`); also `order_url.rb:8`, `order_type.rb:99`, `cart.rb:2` | survey |
| `app/models/order.rb`, `lib/order_export.rb` | 433; 133 | `StringUtils.urlify` — the only `string_utils` use | survey |
| `app/models/area.rb` | 16 | `geocoded_by :geocode_address` — the only geocoder AR integration | survey |
| `app/models/user.rb` | 5 | `has_secure_password` (8.0.3 confirmation-on-blank fix) | survey |
| `app/models/postal_code.rb` | 65–75, 108–131 | `nearby_cities`, `nearby_postal_codes` and their haversine queries | survey |
| `lib/geo_sql.rb` | 1–3, 16–24 | the haversine SQL; "a future move to PostGIS ST_Distance happens in one place" | survey |
| `app/mailers/notifier.rb` | 2, 51–55 | `default from: ENV['ZONE_EMAIL_SENDER']`; `send_error_email(subject, message)` → `ops@insightphotos.net`, subject `SystemError::<subject>` — the production mailer spot check | survey |
| `app/mailers/notifier.rb` | 8 | the documented one-liner `Notifier.send_error_email('TESTING', "This is a test").deliver_now` | survey |
| `app/workers/property_data_lookup_worker.rb` | 26–28 | `include Sidekiq::Worker`, `include Sidekiq::Status::Worker`, `sidekiq_options retry: false` — the worker shape; 14 workers `require 'sidekiq-status'` at line 1 | survey |
| `lib/crmls.rb`, `lib/sandicor.rb`, `app/models/listing.rb` | 560, 473, 1083 lines | the MLS import code `Regexp.timeout = 1` (slice 5a) can affect. **Narrowed in slice 5a:** regex operations by grep are `crmls.rb` 0, `sandicor.rb` 2 (`:392, :457`, the `FIXIE_URL` split), `crmls_transform.rb` 0, `listing.rb` 9 (`:485–540` URL `gsub`s, `:559` the address slug, `:1049`); the payload exposure is the `rets` gem's response parser (12 sites in `rets-0.11.2/lib`, the slice 5 plan's fact 8), reachable only through a live login | survey; slice 5a |
| `lib/tasks/marketing_source.rake` | 41 | the one production `upsert_all` — no spec covers it (`spec/lib/tasks/marketing_source*` does not exist; grep, slice 2) | survey; slice 2 |
| `lib/crud_attribution.rb` | 4–12 | the `CrudAttribution` module (in `lib/`, not `app/models/concerns`): `validates :created_by_id, presence: true, on: :create`, `:updated_by_id` on update; included by 52 models — the exposure of the autosave validation narrowing, which is 7.2.3's, not 8.0's | slice 2 |

## Schema facts

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 13 | `ActiveRecord::Schema[8.1].define(version: 2026_10_07_120001)` — re-dumped from a clean test database (OD7); a round-trip load reproduces it | survey; slice 3 `5ffe92c4` |
| `db/schema.rb` | 15–16 | `enable_extension "pg_catalog.plpgsql"`, `"pg_stat_statements"` — no PostGIS. Was `"pg_stat_statements"`, `"plpgsql"`: Active Record 8.0's dumper names an extension's schema when it differs from the current one and sorts the list (`postgresql/schema_dumper.rb:29`); the control dump on 8.0.5.1 showed the same hunk. Line count unchanged | survey; slice 3 `5ffe92c4` |
| `db/schema.rb` | 903, 970, 972 | the three `t.float` columns — all `double precision` (`photos.classification_confidence`, `properties.ai_community_confidence`, `properties.ai_neighborhood_confidence`; `information_schema.columns`, `numeric_precision` 53); only `float4` dumps `limit: 24` (`postgresql_adapter.rb:696–697`); §8 item 16 closed | survey; slice 3 |
| `db/schema.rb` | — | no `id: false` table (grep empty) — 8.1's `MissingRequiredOrderError` default is inert | survey |
| `db/migrate/` | — | newest `20261007120001`. **Three Active Storage migrations are tracked**: `20260122184539_add_service_name_to_active_storage_blobs.active_storage.rb`, `…40_create_active_storage_variant_records…`, `…41_remove_not_null_on_active_storage_blobs_checksum…` (added by `e66411cf`, 2026-01-29; `Migration[6.0]`, each `return unless table_exists?(:active_storage_blobs)`); their versions are in `schema_migrations` on the dev restore (so in production); no `active_storage_*` table. `active_storage:update` skips them by name, so no slice copies or deletes them. (The survey's "never added" claim was wrong — `--diff-filter=D` saw only deletions.) | survey; corrected slice 2 |

## Specs and support files

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| baseline run | — | `bundle exec rspec` 2026-10-23 15:50 UTC: **1997 examples, 0 failures, 0 pending, 66.1 s**; one Rails deprecation (from `new_framework_defaults.rb:17`); 24 Ruby warnings from `rspec-rails-8.0.4/lib/rspec/rails/matchers/have_http_status.rb:219` (`:unprocessable_entity` → `:unprocessable_content`, 24 sites in 12 spec files); `bin/rails zeitwerk:check` clean | survey |
| `.rspec` | 1 | `--require spec_helper` | survey |
| `spec/rails_helper.rb` | 33–37 | `ActiveRecord::Migration.maintain_test_schema!` | survey |
| `spec/support/auth_helpers.rb` | 6–9 | `jwt_headers_for(user)` — HS256, `sub = api_key`, per-user `jwt_secret` | survey |
| `spec/support/sidekiq.rb` | 6–8 | `require 'sidekiq/testing'`; `Sidekiq::Testing.fake!` | survey |
| `spec/support/sql_helpers.rb` | 11–21 | `sql_for` subscribes to `sql.active_record`, skipping `SCHEMA`/`TRANSACTION` by `payload[:name]` | survey |
| `spec/support/stripe.rb`, `spec/support/geocoder.rb` | — | the Stripe and Geocoder stubs | survey |
| `spec/models/postal_code_spec.rb` | 110–148 | `#nearby_cities`, **4** examples (ordered by distance, empty without coordinates, excludes deleted, excludes cities without coordinates) — the haversine check (P4). The survey's `110–141` and "3 examples" missed the fourth at 142; the file last changed 2026-05-17 | survey; corrected slice 1 |
| `spec/lib/stripe_card_spec.rb`, `spec/models/account_stripe_spec.rb`, `spec/models/order_issue_refund_spec.rb`, `spec/models/transaction_charge_failure_spec.rb` | — | the Stripe paths; the last two also assert `ActionMailer::Base.deliveries` | survey |
| `spec/requests/users_directory_spec.rb` | 11 | `GET /users/directory` — JWT request spec with the pagination `metadata` contract | survey |
| `spec/requests/orders_processing_parent_pays_spec.rb` | 12 | raw `select_all` path through `OrderSql` | survey |
| `spec/requests/orders_processing_release_on_spec.rb`, `spec/requests/accounts_most_recent_shoot_spec.rb` | — | the `search_time_params` / time-zone request specs | survey |
| `spec/workers/property_data_lookup_worker_spec.rb` | 3 | worker `#perform` example | survey |
| `spec/architecture/account_classification_spec.rb` | — | the existing contract spec and the shape to copy | survey |
| `spec/architecture/rails_upgrade_spec.rb` | 1–233 | the contract spec, one `describe` per document section; **18 examples after slice 5a** — the header gains slice 5a's clause (11–13), and the 8.0/8.1 block at 119–146 replaces slice 3's one example with three: the `strict_freshness` config `true` with the applied `false` (129), the timeout `eq(1.0)` (135), the four 8.1 flags and `loaded_config_version` `7.2` (139); slice 4's block moved to 148–232 (the five examples at 181, 185, 191, 210, 224). **16 examples after slice 4** — slice 4's `belongs_to` block at 134–218 (five structural examples: a floor of 88 reflections at 167; a column behind every reflection at 171; `optional: true` exactly where the column is nullable or shared at 177; every `NOT NULL` association required through the framework default at 196; every shared column `NOT NULL` at 210 — the shared column found by grouping reflections on `[model, foreign_key]`, no model named). 11 examples after slice 3 — floor `>= 8.1.4` (15); no `to_time` key (26); the three behaviour examples; the gate ×2; "draws a known route and none of Active Storage's" (88; `recognize_path('/up')` first); the two member routes; "the 8.0 and 8.1 defaults stay off" (122; adds `escape_json_responses` true, `escape_js_separators_in_json` true, `raise_on_missing_required_finder_order_columns` false, `action_on_path_relative_redirect` `:log`). After slice 2 it was: the version floor (`>= 8.0.5.1`), the `to_time` setting (`:zone`) and three behaviour examples, the gate's value and behaviour (every registered deprecator raises), no Active Storage route, the two member routes (recognition, the carts json default, the helpers), the other 8.0 defaults off (`strict_freshness`, `Regexp.timeout`, `loaded_config_version`). Extended by every later slice (§4.2–§4.6) | slice 1; slice 2 |
| `spec/requests/active_storage_routes_spec.rb` | 1–14 | `POST /rails/active_storage/direct_uploads` → 404 | slice 1 `3a6b8e2e` |
| `spec/requests/missing_record_guards_spec.rb` | 1–100 | 11 examples, one invariant (a missing record answers once — 204 or the auth layer's 401). Regressions (red on 8.1.4 without the guards): the five JWT `GET`s of id `0` (`/orders`, `/orders/0/transactions`, `/orders/0/raw_photos`, `/listing_rooms`, `/listing_property_features`) and raw photos with `access_token=bogus`. Adjacent behaviour: no credential → 401 on transactions and the two listing resources, 204 on raw photos; orders with a bogus token → 204 | slice 3 `a5bfab70` |
| `spec/requests/orders_show_authentication_spec.rb` | 1–39 | `GET /orders/:id` with neither credential → 401; a non-decoding JWT → 401; a valid JWT → 200 | `55c86f1d` (v664) |
| `spec/services/deprecation_reporter_spec.rb` | 1–188 | 14 examples: the notify call, dedupe (`have_received(...).once`), a different message, the same message from another gem, first app frame and fallback, `.subscribe`, `.received?` ×3, the failure path through a real `:notify` deprecator ×4 | slice 1 |
| slice 1 runs | — | 2026-10-26 on `chore/rails-upgrade-slice-1`: 2,013 at `master` 02dbb78a → **2,034 examples, 0 failures, 0 `DEPRECATION WARNING`** at `a5d9b001`; the 24 rspec-rails `:unprocessable_entity` warnings unchanged (they do not trip `:raise`). Two pre-existing one-second flakes, `spec/lib/tasks/account_classification_rake_spec.rb:156` and `spec/services/account_metrics/calculator_spec.rb:965`, independent of `to_time`; fixed on their own branch after the push | slice 1 |
| slice 2 runs | — | 2026-10-27 on `chore/rails-upgrade-slice-2`: 2,040 at `master` 473e2747 → **2,045 examples, 0 failures, 0 `DEPRECATION WARNING`** at `4b464230`, plain and with `CI=1` (eager load); the 24 rack warnings unchanged; the two one-second flakes did not fire in six full runs | slice 2 |
| slice 3 runs | — | 2026-10-30 on `chore/rails-upgrade-slice-3`: 2,048 at `master` f86877f5 (v665; 61.1 s) → **2,059 examples, 0 failures, 0 `DEPRECATION WARNING`** at every commit and at `5ffe92c4`, plain and with `CI=1`, the last pair against the test database the round-trip load built; the 24 rack warnings unchanged. `calculator_spec.rb:965` fired once in nine full runs (a one-second mismatch) and passed on the rerun | slice 3 |
| slice 4 runs | — | 2026-11-03 on `chore/rails-upgrade-slice-4`: 2,080 at `master` 8b726308 (v667) → the contract block red by design at commits 1–3 (3, 2, 1 failures) → **2,099 examples, 0 failures, 0 `DEPRECATION WARNING`** at `bd0859b8`, plain and with `CI=1`; **2,100** on `6e0e9953` (`master` at v670 merged in; `forwarded_header_spec.rb` adds one) and on the merge into `master`, `316fa0e1` (2026-11-09, 65.4 s); the 24 rack warnings unchanged | slice 4 |
| slice 5a runs | — | 2026-11-09 on `chore/rails-upgrade-slice-5a`: 2,100 at `master` `316fa0e1` (v671) → **2,103 examples, 0 failures, 0 `DEPRECATION WARNING`** at `3ca24647`, plain (63.8 s) and with `CI=1` (63.7 s), and again at `c966bb6e` in a clean worktree (54.0 s, 55.3 s); the 24 rack warnings unchanged. A fresh worktree needs `tmp/` created and `.env` copied in: without `tmp/`, 33 report-writing examples (the account rake and report specs) fail with `Errno::ENOENT` | slice 5a |
| `spec/support/sql_helpers.rb` | 11–21 | `sql_for` — slice 4 measured the extra association loads with it: an `Order` create by id 12 → 15 SELECTs, by object 10 → 11, a `TagsResource` create 1 → 3 (§4.5; throwaway probe specs, not committed — decision 8) | survey; slice 4 |
| `spec/models/area_spec.rb` | 1–15 | an `Area` with a name and a city saves, and `Area.reflect_on_association(:state)` is `nil` | slice 4 `1b4be3c8` |
| `spec/models/tags_resource_spec.rb` | 1–94 | 9 examples on the OD10 validation: each type's mapping (user, property, photo — the photo positive stubs `ensure_listing_photo_exists` as `postal_code_spec.rb:49` does), an id that names nothing, an unsupported type, each dirty-field half of the condition, a row whose user is gone still soft-deletes | slice 4 `c055b8ed` |
| `spec/requests/areas_properties_create_spec.rb` | 1–54 | 3 examples: the happy path, then `POST /areas_properties` without `propertyId` / `areaId` → `:unprocessable_content`, `["Property must exist"]` / `["Area must exist"]` (S12's camelCase body; one shared city — `spec/factories/states.rb` fixes the state's name and `State` validates its uniqueness) | slice 4 `c055b8ed` |
| `spec/requests/floorplans_create_bulk_spec.rb` | 1–29 | 1 example: a batch whose `order_token` names a soft-deleted order → 422 `["Order must exist"]`, nothing created (the order is soft-deleted after creation: `before_create :set_status_type`, `lib/crud_attribution.rb:9`, forces every new row active) | slice 4 `bd0859b8` |
| `spec/lib/crmls_login_timeout_spec.rb` | 1–35 | 1 example documenting the login swallow (§4.6 gap, §8 item 32): `Rets::Client.new` stubbed to return a double whose `login` raises `Regexp::TimeoutError`; `Crmls.import` does not raise, `Notifier.send_error_email('Crmls Login Failure', 'Failed to login: regexp match timeout')` is called and its delivery double receives `deliver_now`, `MlsImport.count` unchanged. Uses a delivery double, not `and_call_original`, so it needs no `ZONE_EMAIL_SENDER` (16 existing examples in `transaction_spec.rb` and `account_stripe_spec.rb` do). 5b's commit 5 adds a second example | slice 5a `c966bb6e` |

## Recurring work and workers (v2 — slices 0, 1 and 5)

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/tasks/scheduler.rake` | 1–18 | the four Heroku Scheduler tasks: `import_order_photos` (`Order.import_processed_photos`), `send_delayed_notifications`, `cleanup_unused_watermarks`, `import_listings` (`Crmls.import` at 17; `Sandicor.import` commented at 16). **No recurring Sidekiq job exists** — workers are enqueued by user activity (`app/models/order.rb` ×4, `transaction.rb` ×2, `property.rb`, `postal_code.rb`, `site_export.rb`, `concerns/order_zip.rb`, `app/services/photo_classifier_service.rb`, `lib/order_image_handler_import.rb`, four rake tasks) | v2 |
| `lib/tasks/scheduler.rake` | 19–23 | slice 0's check-in: `ENV.fetch('HONEYBADGER_CHECKIN_IMPORT_LISTINGS', nil)` then `Honeybadger.check_in(check_in_id) if check_in_id.present?`, after `Crmls.import` (17) so a raise skips it (OD11). Cadence hourly, finishing about :35 UTC (`mls_imports`, dev restore) | slice 0 `a641c52b` |
| `lib/crmls.rb` | 94–95 | `extract_listings` returns early, without raising, when `mls.import_errors` is non-empty (failed login) — so the check-in means the task finished, not that listings arrived | slice 0 |
| `lib/crmls.rb` | 63–106, 342, 372, 444–494 | `Crmls.import` and its `rescue`/`ensure` blocks — the regex-dense path 5a watches | v2 |
| `lib/crmls.rb` | 92–107 | `extract_listings`: `return unless mls.import_errors.empty?` at 94 — before `Listing.sync_mls_ids` (96) and `MlsImport.new` (98) — so a failed login writes no `mls_imports` row; `begin … ensure` (100–106) with no `rescue`; `import_log.duration` (102) and `save` (103) at the end, so `created_at` is the run's end and `created_at - duration` its start (S9b) | slice 5a |
| `lib/crmls.rb` | 120–143 | `load_listing`: `MlsListing … first_or_create` (121–123), `update_column(:mls_synced_at)` (124), the signature short-circuit (125), `No record found` for a blank payload (127–130), then the transforms — P-5a's replay path | slice 5a |
| `lib/crmls.rb` | 422–448 | `login`: `CrmlsMetadata.new` (423), `Rets::Client.new` with ENV credentials (425–440), then `@client.login` in a bare `rescue` (442–447) that appends `"Failed to login: #{$!}"` and sends `Notifier.send_error_email('Crmls Login Failure', …).deliver_now` — **a `Regexp::TimeoutError` during the login is swallowed here** (`< RegexpError < StandardError`), the check-in still arrives and Honeybadger sees nothing (§4.6 gap, §8 item 32). `Sandicor#login` (`lib/sandicor.rb:414`) has the same shape | slice 5a |
| `app/workers/property_data_lookup_worker.rb` | 30–39 | `perform(property_id, force)` → `PropertyFactsService.call`. `:32–33` rescues `PropertyDataAlreadyFetchedError` and logs "…already has property data, skipping" — **P3's path** (an already-fetched property, `property_data_status: 2`; 174 on the dev restore, ids 1964 … 66237). `:34–39` rescues `StandardError`, logs, `update_all`s and **re-raises** — so v2's `perform_async(0)` ends in `fail`, not `done` (the ASSUMPTION was false) | v2; corrected slice 1 |
| `app/workers/generate_coordinates_worker.rb` | 24–25 | `klass_name.constantize.find(id)` — `perform_async('NoSuchClass', 1)` raises `NameError` before any geocoding: slice 0's deliberately failing job (a `RecordNotFound` would be ignored by Honeybadger's default list) | v2; slice 0 |
| sidekiq 7.3.10 `lib/sidekiq/cli.rb` | — | logs `Booted Rails <version> application in <env> environment` at start — the P3/S2 line | v2 |

## `belongs_to` and column nullability (v2 — slice 4, rule D′; rewritten as built, slice 4)

Runner over every eager-loaded `ApplicationRecord` descendant, 2026-10-23; re-run at slice 4's survey (2026-11-02, `master` 05e3fd42), where the counts held exactly (89 reflections over 43 models: 49 / 39 / 1 / 1). As built at `bd0859b8`, re-verified at `316fa0e1`:

| Fact | Value |
| :-- | :-- |
| non-polymorphic `belongs_to` reflections | 88 — the surveyed 89 less `Area#state` (the contract block's floor) |
| on `NOT NULL` foreign-key columns | 49 — **47 required** through the framework default (no `optional:`); 2 `optional: true`, the `TagsResource` pair (shared column, below). Of the 47, 17 had no column presence validator (a 500 before, a 422 after) and 30 have one (the doubled message, §8 item 27). No `NOT NULL` key behind a `belongs_to` has a column default (`grep -n -E 't\.(integer\|bigint) "[a-z_]+_id".*default' db/schema.rb` → only `listings.property_type_id`, nullable) |
| on nullable columns | 39 — all `optional: true`; the 3 that relied on the global `false` gained it in `0baa6b4b`: `Area#area_type` (`app/models/area.rb:8`), `Listing#property_type` (`app/models/listing.rb:37`), `OrderUrlGroup#order` (`app/models/order_url_group.rb:6`) |
| with no column | 0 — `Area#state` (was `area.rb:7`; `areas` has `city_id`, `area_type_id`, `parent_area_id` and no `state_id`) deleted in `1b4be3c8` |
| two `belongs_to` on one column | `TagsResource#user` and `#property`, both `foreign_key: :resource_id`, `optional: true` (`app/models/tags_resource.rb:6–7`); `tags_resources.resource_id` and `resource_type` `NOT NULL`. OD10's validation (slice 4 `c055b8ed`): `RESOURCE_CLASSES` (`:20–24`; `ResourceType` 1 → `User`, 3 → `Property`, 7 → `Photo`); `validate :resource_must_exist, if:` a new row or a changed `resource_id` or `resource_type` (`:26`); `resource_must_exist` (`:103–108`: `unscoped.exists?`, `errors.add(:resource_id, :required)` → `Resource must exist`). The column validators at `:9–11` are unchanged |
| explicit `optional: false` / `required:` | 0 / 0 |
| `belongs_to_required_by_default` | the framework's `true` — the shim line is gone (`c055b8ed`) |
| `belongs_to_required_validates_foreign_key` | `false` under `load_defaults 7.1`+ — the validator runs only on a new row or a changed key, so an existing row with a dangling key still saves (the "Slice 4" section); not among 5a's or 5b's flags |

## Honeybadger (v2 — docs.honeybadger.io, read 2026-10-23)

| Page | Fact |
| :-- | :-- |
| gem-reference/configuration | `api_key` ← `HONEYBADGER_API_KEY`; `env` ← `HONEYBADGER_ENV` (Rails uses `Rails.env`); `report_data` ← `HONEYBADGER_REPORT_DATA`, "Defaults to false for "test", "development", and "cucumber" environments"; `development_environments` default `["development", "test", "cucumber"]`; `exceptions.ignore` adds to a built-in list that includes `ActiveRecord::RecordNotFound`; `request.filter_keys` default `['password', 'password_confirmation']` — "In Rails, this also includes existing params filters" (the docs page; the 6.10.0 source adds `HTTP_AUTHORIZATION`, see the gem-source table below); `sidekiq.attempt_threshold` default `0`; `sidekiq.use_component` default `true`; `insights.enabled` default `true` (v6+); no check-in keys in the config file |
| getting-started/performing-check-ins | `Honeybadger.check_in('1MqIo1')` with the id from the project; "Now your task will check in when it's executed periodically by cron, Heroku Scheduler, etc."; "If it ever stops checking in, Honeybadger will notify you." |
| gem-reference/cli | `honeybadger test` — "Send a test notification from Honeybadger"; `honeybadger install` sets up a new project (writes `config/honeybadger.yml` and sends a test exception, per the Rails guide) — **not used**, the key stays in ENV; `honeybadger deploy` notifies a deployment |
| integration-guides/rails-exception-tracking | errors reported automatically in web requests, background jobs, rake tasks and `at_exit`; `Rails.error.handle` reported, `Rails.error.record` not |
| gem-reference/supported-versions | Ruby `>= 2.7.0`, Rails `>= 5.2`, Sidekiq "any" |
| guides/uptime | monitors are created in the dashboard; success = any 20x by default; "every few minutes"; "Your Honeybadger account comes with uptime monitoring" (trial coverage UNVERIFIED) |
| getting-started/reporting-errors | `Honeybadger.notify(exception_or_string, error_class:, error_message:, fingerprint:, tags:, context:, force:, sync:, component:, action:)`; `fingerprint` — "The `String` grouping fingerprint of the exception"; `sync: true` "skips the worker" |
| insights/automatic-instrumentation | instruments Rails, ActiveJob, Sidekiq, Net::HTTP, Puma events; nothing about deprecations — hence slice 1's own subscriber |
| lib/ruby/getting-started/customizing-error-grouping (read 2026-10-26) | default grouping is the error's location (file, method, line), class and component; `:fingerprint` on `notify` overrides it; "same fingerprint, same error" — context and tags never separate groups. Why slice 1's fingerprint carries the gem name |
| Rails source | `:notify` behaviour instruments `deprecation.<gem_name>` with `message`, `callstack`, `gem_name`, `deprecation_horizon` (`activesupport/lib/active_support/deprecation/behaviors.rb:37–45`, identical on 7-2 and 8-1); `report_deprecations == false` sets `deprecators.silenced = true` (`activesupport/lib/active_support/railtie.rb:66–70`, 7-2) |

## Honeybadger — gem source and app touchpoints (slice 0, 2026-10-26)

Gem paths are under `honeybadger-6.10.0/lib/honeybadger/` (installed gem, read-only). Where these
disagree with the docs table above, the source wins.

| File | Line | What it is |
| :-- | :-- | :-- |
| `config/defaults.rb` | 261–264 | `request.filter_keys` default `["password", "password_confirmation", "HTTP_AUTHORIZATION"]` — the docs page omits the third |
| `config/defaults.rb` | 321–324 | `exceptions.rescue_rake` default `!$stdout.tty?` — rake exceptions report on a non-TTY dyno (Heroku Scheduler; UNVERIFIED there) |
| `config/defaults.rb` | 529–532 | `breadcrumbs.logging.enabled` default `true` (slice 0 sets it false) |
| `config.rb` | 37, 121–130 | source order Ruby config → ENV → YAML → framework, first source holding a key wins (no merge) — so a YAML `filter_keys` list replaces the default; ENV `HONEYBADGER_REPORT_DATA` beats the YAML |
| `config.rb` | 57 | the start-up line is `logger.debug` — production at `info` logs nothing from the gem at boot |
| `config.rb` | 175–179 | `public?`: `report_data` true/false wins, else `!dev?` (any env name outside `development_environments` reports) |
| `config.rb` | 491 | the YAML section is chosen by `self[:env]`, which `HONEYBADGER_ENV` overrides — `development-check` matches no section |
| `config/env.rb` | — | `HONEYBADGER_*` vars cast by type; booleans match `true|t|1` |
| `util/request_hash.rb` | 62–67 | every `HTTP_*` header goes into `cgi_data` |
| `util/sanitizer.rb` | 28–33 (of `filter_key?`) | key filters are case-insensitive partial regexps |
| `notice.rb` | 246 | the payload carries `api_key` (how the notice authenticates) — never print a serialized notice |
| `notice.rb` | 408–415 | `sanitized_breadcrumbs` filters breadcrumb metadata only, never messages |
| `notice.rb` | 576–582 | `params_filters` = config `filter_keys` + the request's `action_dispatch.parameter_filter`; no request (Sidekiq) → config keys only |
| `plugins/sidekiq.rb` | error handler | notifies with `parameters:` = the job hash (args unfiltered); the `attempt_threshold` check is skipped when the job's `retry` is false |
| `plugins/breadcrumbs.rb` | 54–60 | log wrappers prepended to `ActiveSupport::LogSubscriber`, `BroadcastLogger` and `::Logger` only if `breadcrumbs.logging.enabled` at plugin load |
| `breadcrumbs/active_support.rb` | 23 | SQL breadcrumbs obfuscated |
| `agent.rb` | 207–216 | `check_in(id)` takes the id or the full check-in URL; returns `response.success?` |
| `backend/server.rb` | 44–48 | check-in is a synchronous GET; HTTP errors return a failed response, never raise |
| `backend/null.rb` | 24–26 | the Null backend stubs `check_in` (dev and test) |
| `cli/install.rb` | 51–80, 105 | `honeybadger install` writes the literal key into `config/honeybadger.yml` and sends a test notice — not used |
| `cli/test.rb` | 178–180 | `honeybadger test` sends its exception through `Rails.application.call` with a mock env, no `Authorization` header |

| App file | Line | What it is |
| :-- | :-- | :-- |
| `lib/app_jwt.rb` | 5, 15 | the JWT arrives in the `Authorization` header (`HTTP_AUTHORIZATION`) |
| `app/controllers/transactions_controller.rb` | 54 | the Stripe token arrives as `transaction[token]` — filtered by `token` |
| `app/controllers/accounts_controller.rb` | 163 | logs `params.require(:account).inspect` (unfiltered) — why log breadcrumbs are off |
| `lib/auth.rb` | 34 | logs the Twilio verification object — likewise |
| `spec/support/stripe.rb` | 14 | `WebMock.allow_net_connect!` for the whole suite — real HTTP is possible from specs; `report_data` false is the guard |
| `.env` (gitignored) | — | holds a Honeybadger key in the dev container; dotenv loads it in development and test, so `api_key` is not nil in the suite |
| `spec/config/honeybadger_spec.rb` | — | 8 examples: suite never reports; production alone reports; no `api_key` in any section; Insights off; log breadcrumbs off; threshold 0; `HTTP_AUTHORIZATION` filtered; a locally serialized request notice free of credentials and logged lines |
| `spec/lib/tasks/scheduler_rake_spec.rb` | — | 4 examples: check-in after the import; none when the id is unset or blank; none when the import raises |
| `insgt-app/src/app/shared/pipes/order/order-payment-link.pipe.ts` | 19 | client page URLs carry `?accessToken=` — cross-origin to the API, so browsers send the origin only as `Referer` |

## Slice 1 — the deprecation reporter and what it rests on (2026-10-26, at `a5d9b001`)

| File | Line | What it is |
| :-- | :-- | :-- |
| `app/services/deprecation_reporter.rb` | 1–46 | header and ARCHITECTURE NOTES: scope, the key, the two kinds of frame, why the subscriber rescues |
| `app/services/deprecation_reporter.rb` | 47–49 | `ERROR_CLASS = 'RailsDeprecation'`, `TAGS = 'deprecation'`, `REPORTED_MESSAGES = Concurrent::Map.new` (process-wide; specs `stub_const` it) |
| `app/services/deprecation_reporter.rb` | 57–59 | `.subscribe` — `ActiveSupport::Notifications.subscribe(/\Adeprecation\./) { \|event\| report(event.payload) }`, returns the subscriber |
| `app/services/deprecation_reporter.rb` | 63–67 | `.report` — the subscriber body; rescues `StandardError` into `report_failure` |
| `app/services/deprecation_reporter.rb` | 74–76 | `.received?(text)` — any claimed key includes `text`; the deploy probe's accessor (wiring, not delivery) |
| `app/services/deprecation_reporter.rb` | 80–95 | `report_failure` (Honeybadger notice with `deprecation_message` context) and `log_failure` (`[DeprecationReporter] Failed to report …`), each rescued on its own |
| `app/services/deprecation_reporter.rb` | 108–119 | `#call` — `put_if_absent(identity, true)` before `Honeybadger.notify(message, error_class:, fingerprint: SHA256(identity), tags:, backtrace: raw callstack, context: { gem_name:, deprecation_horizon:, callstack: first_app_frame })` |
| `app/services/deprecation_reporter.rb` | 125–127, 129–131 | `identity` = `"#{gem_name}: #{message}"` (changing its format regroups every `RailsDeprecation` error); `first_app_frame` = `Rails.backtrace_cleaner.clean(callstack).first \|\| callstack.first` |
| `bin/rails runner` (development) | — | `Rails.application.deprecators` holds 16: keys `railties active_support action_dispatch active_model action_controller active_record active_job action_mailer action_view active_storage action_cable action_mailbox action_text global_id lograge dotenv`; `gem_name` is `Rails` for 14 (dotenv's included), `GlobalID`, `Lograge`. There is no `:rails` key — `[:railties]` is `Rails.deprecator`. In test all 16 raise |

Rails 7.2.4 (installed gems, read-only):

| File | Line | What it is |
| :-- | :-- | :-- |
| `railties/lib/rails/application/finisher.rb` | 18 | `setup_main_autoloader` — after `config/initializers`, so an initializer cannot reference `app/services` (`NameError`; probed) |
| `railties/lib/rails/application/finisher.rb` | 65–69, 73–75, 77–90, 93–95 | `to_prepare` blocks registered → run (`prepare!`) → `eager_load!` → `after_initialize` hooks |
| `railties/lib/rails/application/finisher.rb` | 192–201 | reloading off → `app.reloader.check = lambda { false }`, so `reloader.wrap` (Sidekiq, `sidekiq/rails.rb:26`) never re-runs `to_prepare` (probed: one listener after 5 reloader and 5 executor wraps) |
| `activesupport/lib/active_support/notifications/fanout.rb` | 21–43 | `iterate_guarding_exceptions` — a single subscriber's error is re-raised as itself (more than one → `InstrumentationSubscriberError`) into the instrumenting code |
| `activesupport/lib/active_support/deprecation/deprecators.rb` | 41–44 | `each` without a block returns an enumerator; the collection is not `Enumerable` (`map` raises `NoMethodError`) |
| `activesupport/lib/active_support/deprecation/behaviors.rb` | 13, 37–45 | `DEFAULT_BEHAVIORS` (behaviours are lambdas; `DEFAULT_BEHAVIORS.key(b)` names them); `:notify` instruments `deprecation.<gem_name>` with `message`, `callstack`, `gem_name`, `deprecation_horizon` |
| `activesupport/lib/active_support/deprecation/reporting.rb` | 18–29 | `warn` — `caller_locations(2)`; the full message `DEPRECATION WARNING: <text> (called from <label> at <file:line>)` names no deprecator |
| `railties/lib/rails/backtrace_cleaner.rb` | 8, 13–26 | `APP_DIRS_PATTERN` `app\|config\|lib\|test` after stripping `Rails.root/` — `spec/` frames are silenced; on Heroku gems sit under `/app/vendor/bundle`, which the pattern also silences |

Honeybadger 6.10.0 (installed gem, read-only):

| File | Line | What it is |
| :-- | :-- | :-- |
| `agent.rb` | 128–144 | `notify` — a non-Exception, non-Hash first argument becomes `error_message` |
| `notice.rb` | 211, 326–328 | `backtrace` = `opts[:backtrace]` or the exception's or `caller`; an empty array is truthy and would be used |
| `notice.rb` | 167–185 | backtrace filters substitute `[GEM_ROOT]` (each `Gem.path`) and `[PROJECT_ROOT]` (`config.root_regexp`) |
| `backtrace.rb` | 79–81 | `application?` — the frame begins `[PROJECT_ROOT]` and not `[PROJECT_ROOT]/vendor`; why the reporter sends the raw callstack |
| `singleton.rb` | 34 | `Honeybadger.flush` delegates to the agent (S-DEP) |
| `config/env.rb` | 6 | `HONEYBADGER_<KEY>` env vars; `HONEYBADGER_REPORT_DATA=false` reads `false` in a runner (the deploy probe's guard) |

## Gems with Rails coupling (installed sources, read-only)

| Gem | File | Line | What it is |
| :-- | :-- | :-- | :-- |
| string_utils 1.0.8 | `lib/string_utils.rb` | 4, 7 | `require 'active_support/core_ext/string/multibyte'`, `…/string/inflections` |
| string_utils 1.0.8 | `lib/string_utils.rb` | 57–64 | `urlify` — `gsub` only |
| string_utils 1.0.8 | `lib/string_utils.rb` | 169–170 | the only `mb_chars` use (not on the app's path; 8.1 deprecates `mb_chars`) |
| sidekiq 7.3.10 | `lib/sidekiq/rails.rb` | 20–26, 68–78 | `Rails.application.reloader.wrap(source: "job.sidekiq")`; `after_initialize` reloader and logger broadcast |
| sidekiq 7.3.10 | `Gemfile` (upstream, tag v7.3.10) | 6 | tests against `RAILS_VERSION = "~> 7.1"` — no Rails 8 statement (UNVERIFIED compatibility; proved by boot in slices 2–3) |
| jbuilder 2.14.1 | `lib/jbuilder.rb` | 271–273 | `target!` → `@attributes.to_json` |
| geocoder 1.8.6 | `lib/generators/geocoder/migration_version.rb` | 5–10 | the only `Rails::VERSION` reference |

## Slice 2 — the 8.0 boot order, the route validation and what they rest on (2026-10-27, at `4b464230`)

Rails 8.0.5.1 (installed gems, read-only); the 7.2.4 rows are the "before".

| File | Line | What it is |
| :-- | :-- | :-- |
| `railties/lib/rails/application/configuration.rb` | 119, 341 | `load_defaults "5.0"` sets `active_support.to_time_preserves_timezone = :offset`; `"8.0"` sets `:zone` |
| `activesupport/lib/active_support/railtie.rb` | 99–103, 125–130 | the late forward (`after_initialize`) and the early one (`set_configs`, every `config.active_support` key); the early one is what the shim cannot pre-empt |
| `activesupport/lib/active_support.rb` | 118–132 | the writer warns for a falsy value ("preserve the receiver timezone rather than system local time") and for anything but `:zone` ("the full timezone rather than offset of the receiver"); both say "in Rails 8.1" |
| `activesupport/lib/active_support/core_ext/date_and_time/compatibility.rb` | 15–37 | `preserve_timezone` is a plain `mattr_accessor` (the writer does not warn); the reader warns once only when nil — why the contract spec's deliberate break assigns it directly |
| `railties/lib/rails/application.rb`; `railties/lib/rails/engine.rb` | 609; 565, 644 | `ordered_railties` puts the application last; `load_environment_config` runs `before: :load_environment_hook` (Bootstrap); `load_config_initializers` is an application initializer — the ordering behind the `:zone` placement |
| `actionpack/lib/action_dispatch/routing/mapper.rb` | 1177–1186 | `Resource#initialize` validates `:only`/`:except` against `default_actions(false)` and raises "Route `resources :carts` - :only and :except must include only […], but also included [:request_shoot]" — absent on 7.2.4 (CHANGELOG 8.0.0.rc1; 8.0.2 added the resource name) |
| `railties/lib/rails/commands/app/update_command.rb` | 11, 16, 63–83 | `add_runtime_options!` (`--force` accepted), `deprecators.silenced = true` for the run, the `skip_*` derivation merged with the command's options; identical on 8.0.2 and 8.0.5.1 |
| `railties/lib/rails/generators/rails/app/app_generator.rb` | 111–116, 123–137, 220–221, 376–384 | `bin` (excludes `thrust`/`rubocop`/`brakeman` by Gemfile), `config` (`puma.rb` is templated on update; `routes.rb`, `cable.yml`, `storage.yml`, `locales` are not), `public_directory` returns for `update && api`, `update_active_storage` runs `active_storage:update` |
| `activesupport/lib/active_support/hash_with_indifferent_access.rb` | 350–362 | `transform_keys!` = `replace(copy_defaults(transform_keys(&block)))` on 8.0.5.1 and (`:354–364`) on 7.2.4 — a later key wins on both; not on the app's path |
| `activesupport/lib/active_support/core_ext/hash/keys.rb` | — | identical on 7.2.4 and 8.0.5.1 (`diff`); `_deep_transform_keys_in_object!` deletes and reinserts, so on a collision the camelCase value wins in either order |
| `activerecord-7.2.4/CHANGELOG.md` | 124, 275 (the 7.2.3 section, lines 45–356) | "Fix `#merge` with `#or` or `#and` …" and "Fix autosave associations to no longer validated unmodified associated records." — both 7.2.3's, in production since; `autosave_association.rb:320` guards identically on 7.2.3 and 7.2.4 |
| `activestorage-8.0.5.1/CHANGELOG.md` | 1–44 | CVE-2026-66066: libvips's unfuzzed loaders disabled; raises at boot only when `ruby-vips` is installed (it is not) |
| `bin/rails runner` (development, 8.0.5.1) | — | `Rails.application.deprecators` still `Rails`, `GlobalID`, `Lograge`; `cache_store` `:null_store`; `permanent_connection_checkout` `true`; `strict_freshness` `false`; `Regexp.timeout` `nil`; `loaded_config_version` `7.2`; the internal route set gains only `GET /rails/info/notes` (development-only) — `bin/rails routes` is byte-identical to `master` (583) |
| `bundle exec sidekiq` (development, 8.0.5.1) | — | `Booted Rails 8.0.5.1 application in development environment`; property 1964 → `start` → `…already has property data, skipping` → `done` (0.23 s); `Sidekiq::Status::status(jid)` `nil` (§8 item 10 — Codex confirmed `config/sidekiq_status.rb` is never loaded) |
| `RAILS_ENV=production` boot (dev container, `HONEYBADGER_REPORT_DATA=false`) | — | every deprecator `[:notify]`, `report_deprecations` `true`, `received?` `true`, `:zone`, `7.2`, 583 routes, `report_data` `false`, 0 `DEPRECATION` lines (slice 2 runbook step 2) |
| `string_utils-1.0.8/lib/string_utils.rb` | 59 | `urlify` raises `Encoding::CompatibilityError` on a BINARY-tagged string on 7.2.4 and 8.0.5.1 alike (UTF-8 input converts; database strings are UTF-8); the gem strips capital letters — pre-existing |

## Slice 3 — the 8.1.4 sources, the head walk and what they rest on (2026-10-30, at `5ffe92c4`)

Rails 8.1.4 installed into the Ruby 3.4.12 gem set (`/home/vscode/.local/share/mise/installs/ruby/3.4.12/lib/ruby/gems/3.4.0/gems/`, read-only); the 8.0.5.1 rows are the "before". The survey's own probes ran on rsync copies under Ruby 3.4.10 (2026-10-28, the plan's scratchpad); the implementation's on fresh copies under 3.4.12.

| File | Line | What it is |
| :-- | :-- | :-- |
| `actionpack-8.1.4/lib/action_controller/metal/head.rb` | 28, 52 | `raise ::AbstractController::DoubleRenderError if response_body`; `head` ends `self.response_body = ""` — so a second `head` raises (8.0.5.1's `head.rb` has no check; the second silently overwrote the first) |
| `actionpack-8.1.4/lib/action_controller/metal.rb` | 245–247 | `performed?` = `response_body \|\| response.committed?` — true after a `head` (the body is `""`, truthy), false after a successful `find_instance` |
| `actionpack-8.1.4/lib/abstract_controller/callbacks.rb` | 36 | the before-action terminator `controller.performed?` — a setter that renders halts the chain, so no action body runs after a before-action's `head` |
| `actionpack-8.1.4/lib/action_controller/metal/rendering.rb` | 172 | `render` raises `DoubleRenderError` if a body exists — render-after-`head` raised before 8.1 too (why `download_files` is pre-existing) |
| `actionpack-8.1.4/lib/action_controller/metal/renderers.rb` | 31–34, 44 | the `escape_json_responses=` writer deprecates only a `true` assignment ("will have no effect in Rails 8.2"); the default reads `true` under `load_defaults 7.2` |
| `railties-8.1.4/lib/rails/health_controller.rb` | 45–50 | `render_up`: `respond_to` — `format.html` (the green page), then `format.json { render json: { status: "up", timestamp: Time.current.iso8601 } }` |
| `actionpack-8.1.4/lib/action_dispatch/middleware/remote_ip.rb` | 179–196 | the port is stripped from each `X-Forwarded-For` entry before `IPAddr` validation (8.0 discarded the entry) |
| `activesupport-8.1.4/lib/active_support.rb` | 124–129, 131–137 | the `to_time_preserves_timezone` reader and writer, both `ActiveSupport.deprecator.warn` |
| `activesupport-8.1.4/lib/active_support/time_with_zone.rb` | 501–503 | `to_time` → `getlocal(time_zone)`, unconditional |
| `activestorage-8.1.4/lib/active_storage/engine.rb` | 94–129 | the boot-time variant-transformer resolution and its `LoadError` WARNs (the `image_processing` one fires here) |
| `activerecord-8.1.4/lib/active_record/connection_adapters/postgresql_adapter.rb` | 488, 516, 696–697 | `enable_extension` accepts a schema-qualified name (`CREATE EXTENSION IF NOT EXISTS … SCHEMA …`) and the dumper reads the extension's schema; `float4` → `Type::Float.new(limit: 24)`, `float8` → no limit |
| `activerecord-8.1.4/lib/active_record/connection_adapters/postgresql/schema_dumper.rb` | 29–30 | `extensions.sort.each` → `enable_extension …` — why `pg_catalog.plpgsql` sorts ahead of `pg_stat_statements` |
| `actiontext-8.1.4.gemspec`; `action_text-trix-2.1.19/lib/action_text/trix/engine.rb` | 31; 4 | `action_text-trix (~> 2.1.15)`; the engine's one initializer runs only `if app.config.respond_to?(:assets)` — false in this API |
| `railties-8.1.4/lib/rails/generators/rails/app/templates/config/initializers/new_framework_defaults_8_1.rb.tt`, `templates/bin/rubocop.tt` | — | the shim (no ERB; identical to the committed file) and the `# Explicit RuboCop config …` comment |
| head-producer walk (Prism, every `app/controllers/**/*.rb`) | — | 128 methods containing `render_no_content`, a `head` literal, `find_instance`, `find_instance_by_public_id` or `destroy_instance`; 140 call sites; read one by one (survey at 03e270c6: 127 — 55c86f1d split `set_order`). Single head: 95; one `find_by` plus one guard: 10; returned `render_*` before `destroy_instance`: 8; `return render_no_content …`: 3; if/else one-per-branch: 3; `order_event` heads first: 1; the five setters; `download_files` and `set_notification_audience` (pre-existing). No sixth site |
| `bin/rails runner` (development, 8.1.4) | — | `config.active_support.key?(:to_time_preserves_timezone)` `false`; `loaded_config_version` `7.2`; `escape_json_responses` `true`; `escape_js_separators_in_json` `true`; `raise_on_missing_required_finder_order_columns` `false`; `action_on_path_relative_redirect` `:log`; `strict_freshness` `false`; `Regexp.timeout` `nil`; `permanent_connection_checkout` `true`; `bin/rails routes` byte-identical to `master` (583) |
| `bundle exec sidekiq -q slice3_p3` (development, 8.1.4) | — | the WARN line, `Booted Rails 8.1.4 application in development environment`; property 1964 → `start` → `…already has property data, skipping` → `done` (0.22 s); `Sidekiq::Status::status(jid)` `nil` |
| `RAILS_ENV=production` boot (dev container, `HONEYBADGER_REPORT_DATA=false`) | — | the WARN line; `"8.1.4"`; every deprecator `[:notify]`; `report_deprecations` `true`; `received?` `true`; `key?` `false`; `7.2`; 583 routes; `report_data` `false`; `escape_json_responses` `true`; 0 `DEPRECATION` lines (slice 3 runbook step 2). The pristine 8.0.5.1 copy's production boot prints no WARN |
| `Rack::MockRequest` (development, 8.0.5.1 vs 8.1.4) | — | `/up` 200 HTML on both; `/up.json` 200 HTML on 8.0.5.1, 200 `application/json` on 8.1.4; `remote_ip` for XFF with a port: `REMOTE_ADDR` vs the address |

## Slice 4 — the `belongs_to` sources, the 422 paths and what they rest on (2026-11-03, at `bd0859b8`)

Rails 8.1.4 sources as in "Slice 3" (8.1.4.1, v669, changes none of these files). The survey's probes ran in a throwaway rsync copy of the tree with no `.git` (the plan session's scratchpad, `…/fbba7498-…/scratchpad/probe/`; not kept), with the shim lines deleted there first. The Codex review copies were built from `git ls-files`: a plain rsync minus `.git` and `.env` still carries `config/master.key`, gitignored but on disk.

| File | Line | What it is |
| :-- | :-- | :-- |
| `activerecord-8.1.4/lib/active_record/associations/builder/belongs_to.rb` | 131–166 | `define_validations`: `required:` folded into `options[:optional]` (132–134); with no `optional:` key, `belongs_to_required_by_default` decides (136–140); required and `belongs_to_required_validates_foreign_key` `true` → an unconditional presence validator (145–146); `false` → only if the key is `nil` or changed (148–163) |
| `activerecord-8.1.4/lib/active_record.rb`; `…/active_record/railtie.rb` | 352; 40 | `belongs_to_required_validates_foreign_key`'s base value, `true` |
| `railties-8.1.4/lib/rails/application/configuration.rb` | 285 | `load_defaults 7.1` sets it `false`; nothing in 7.2, 8.0 or 8.1 sets it back |
| `activerecord-8.1.4/lib/active_record/reflection.rb` | — | no `optional?` (`grep -n "def optional?"` → nothing); the contract reads `reflection.options[:optional]` |
| `config/routes.rb` | 40 | `resources :areas_properties` — S12's path |
| `app/controllers/areas_properties_controller.rb` | 2–3, 13–17, 35 | JWT and the system roles; `create` (`save(current_user)` → `show`, else `render_errors`); `permit(:area_id, :property_id)` — neither key required, so `propertyId` is omittable |
| `app/models/areas_property.rb` | 4–5 | `belongs_to :area`, `belongs_to :property` and nothing else — the omission raised `PG::NotNullViolation` (500) and now answers `["Property must exist"]` (422) |
| `app/models/orders_user.rb` | 13 | `validates :user_id, presence: true` — why `OrdersUser` was not S12 (it already answered 422) |
| `app/models/order.rb` | 90 | `belongs_to :account, -> { eager_load(accounts_users: :user) }` — the required check costs two statements on an `Order` saved by id (§8 item 28) |
| `app/models/order.rb`; `app/models/order_log.rb` | 291, 1651; 28 | `after_create … :log_create_event` creates an `OrderLog` by id, and its required `belongs_to :order` re-reads the order — the third new SELECT on every `Order` create by id |
| `app/controllers/floorplans_controller.rb` | 21–26, 121–126 | `create_bulk`: the guard at 26 answers 422 `["Order must exist"]` before creating anything when the batch's first `order_token` resolves no active order (slice 4 `bd0859b8`); `create_bulk_params` sets every row's `order_id` from `Order.find_by_token` (124) |
| `app/models/token.rb` | 23–25 | `find_by_token` answers active orders only — a soft-deleted order's token resolves nothing |
| `app/models/orders_user.rb`; `app/models/tags_resource.rb`; `app/models/photo.rb` | 102–114; 68–74; 300 | the save-and-ignore sites: the contractor helpers, `update_user_tags` (delete-then-insert, no transaction) and `Photo.tag` skip a refused write silently (§8 item 30) |
| `app/models/photo.rb` | 65, 230–256 | `after_create :tag_with_zip` — tags the photo itself with its zip-code tag (category 9; the writer of D50's 32 rows); +2 SELECTs per photo create after slice 4 (§8 item 29) |
| insgt-api `tmp/` (gitignored) | — | the three production reports: `nullability_diff.rb`, `null-counts.sql`, `dangling.sql`, `dangling-rows.sql`, and their dated outputs (`-2026-11-05` — the null-count and dangling files overwritten on 11-09 — and `-2026-11-09`); S13 diffs `dangling-2026-11-09.txt` |

## Slice 5a — the 8.0 defaults' sources and the import's profile (2026-11-09, at `c966bb6e`)

Rails 8.1.4.1 installed sources (v669; none of these files changed from 8.1.4). The 8.0-defaults boot check ran in place on the branch, with the 8.1 shim's six lines uncommented and then restored by `git checkout`. The development database was a production restore with data to about 2026-11-09 12:31 UTC, loaded that morning; it is not `tmp/latest-2026-10-30.dump`.

| File | Line | What it is |
| :-- | :-- | :-- |
| `actionpack-8.1.4.1/lib/action_dispatch/railtie.rb` | 92 | `ActionDispatch::Http::Cache::Request.strict_freshness = app.config.action_dispatch.strict_freshness`, inside the `action_dispatch.configure` initializer — why the 8.0 shim's `:25` reaches only the config |
| `activesupport-8.1.4.1/lib/active_support/railtie.rb` | 142–146 | `active_support.set_configs` copies every `config.active_support` key onto `ActiveSupport` once — why the 8.1 shim's `:36` reaches only the config (upstream rails/rails#59146; fix PR #59147 open) |
| `railties-8.1.4.1/lib/rails/application.rb`; `…/rails/engine.rb` | 612–620; 643–646 | `railties_initializers` runs every railtie's initializers before the application's own; `load_config_initializers` is the application's — the ordering behind both config-only lines |
| `railties-8.1.4.1/lib/rails/application/configuration.rb` | 325, 335–342, 372 | `self.yjit = true` in the 7.x defaults (YJIT already on everywhere under 7.2); the `"8.0"` block — `strict_freshness = true` and `Regexp.timeout \|\|= 1 if Regexp.respond_to?(:timeout=)`, no `to_time` line; `@loaded_config_version = target_version` (the literal passed, a Float) |
| `honeybadger-6.10.0/lib/honeybadger/config/defaults.rb`; `…/init/rake.rb` | 321–325; 15–16 | `exceptions.rescue_rake` defaults to `!$stdout.tty?` (true under the Scheduler); the rake handler notifies with `origin: :rake` — how a timeout outside the login reaches SH |
| `lib/tasks/scheduler.rake` | 17, 22–23 | `Crmls.import`, then the check-in — the check-in arrives on the login-swallow path |
| development `mls_imports` (the restore) | — | 234 hourly CRMLS runs 2026-10-30 17:35 → 2026-11-09 11:35 UTC plus 7 single-listing syncs (`total_listings` 1): the Scheduler starts the run at about :30; it finishes at :34–:37; `total_listings` 654–659 (median 656); `duration` 272–417 s (p5 282, median 328, p95 391); one missing hour, 10-31 21:35 → 23:36 UTC (cause UNVERIFIED). S9b's bands in runbook 5a come from here |
| P-5a (scratchpad runner, not committed) | — | every `Listing.find_active_imports_for(Crmls::MLS_ID)` row through `Crmls.load_listing` under the timeout, each in a savepoint with `mls_signature` cleared in memory, inside one rolled-back transaction, with WebMock blocking the network, Sidekiq faked, mail `:test` and the geocoder stubbed: 655 listings (646 with a payload, 9 without), 0 timeouts, 0 other errors, 17.2 s; 655 equals production's last `total_listings` |
| `bin/rails runner` (development, 8.1.4.1, at `3ca24647`) | — | `strict_freshness` config `true` / applied `false`; `Regexp.timeout` `1.0`; `escape_json_responses` `true`; `escape_js_separators_in_json` `true`; finder flag `false`; redirect `:log`; `render_tracker` `nil`; `remove_hidden_field_autocomplete` `false`; `config.yjit` `true`, `RubyVM::YJIT.enabled?` `true`; `loaded_config_version` `7.2` |
| `app/mailers/notifier.rb`; `config/database.yml` | 2; 17–20 | `default from: ENV['ZONE_EMAIL_SENDER']`; the test database's name, user and password are ENV too — no spec runs without `.env`, which is why review round 1's sender finding was regraded to a nit |

## Platform repo and documentation

Branch facts (OD9, verified 2026-10-23): the platform repo's `origin/HEAD` is `main`; `docs/rails-upgrade` is based on `main` (merge-base dff7500 = `main`'s tip). insgt-api's `origin/HEAD` and `heroku/HEAD` are both `master`; `apps/insgt-api/docs/` holds only `ops/` and `plans/` — every design document lives here, in `insgt-platform/docs/architecture/` (`insgt-platform/CLAUDE.md:11`). §2.7 is the merge step.

| File | What it is |
| :-- | :-- |
| `insgt-platform/docs/architecture/rails-upgrade.md` | the design document this file maps |
| `insgt-platform/docs/architecture/rails-upgrade-slices/slice-N.md` | the slice prompts (Phase 2) |
| `insgt-platform/docs/runbooks/README.md` | runbook conventions (`Status:` header, `## Deploy log`); each slice writes `deploy-rails-upgrade-N.md` in that shape |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-0.md` | slice 0's runbook: deploy steps, S0–S2/S9, the dev verification log (notice ids), and — after 24 h — the Honeybadger baseline every later slice's SH check compares against (its window spans v659, v660 and v661) |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-1.md` | slice 1's runbook: the eight commits, the Active Storage audit, the pre-push production-config probe, the merge into `master` (`d37ae0df`, v661; 2,040 examples expected), the v661 "before" captures, S-DEP, and the development verification and review log |
| `insgt-platform/docs/plans/rails-upgrade-slice-1.md` | slice 1's Phase 0–1 plan (committed as `e257052`) |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-2.md` | slice 2's runbook: the five commits, the production-config probe (reporting off, `DEPRECATION` grep), the v662 "before" captures including both S-RT routes, S8/S10, the slippage rule, the development verification and the two review rounds; `Ready` before the push |
| `insgt-platform/docs/plans/rails-upgrade-slice-2.md` | slice 2's Phase 0–1 plan: the `app:update` table as run, the `:zone` boot evidence, the routes finding, the key-collision probes, the approval decisions and modifications A–G, the review corrections |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-3.md` | slice 3's runbook: the five commits, the production-config probe with the `key?` line, the v665 "before" captures including S-404 and S11, the Active Storage WARN in every runner, S9 in UTC, SH's `DoubleRenderError` search, the development verification and the two review rounds; `Ready` before the push |
| `insgt-platform/docs/plans/rails-upgrade-slice-3.md` | slice 3's Phase 0–1 plan and implementation record: the `app:update` table on 8.1.4, the `to_time` boot evidence both ways, the five-setter probe tables, the exhaustive head read, the control dump, the approval decisions and additions A–C, the loop records, the review dispositions |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-4.md` | slice 4's runbook: the five commits, the three production reports (nullability STOP, null counts, dangling keys) read Thursday and Monday with decision 5's rule and disposition, P-PROD on the merge, the v670 "before" captures, S12 on `POST /areas_properties`, S13's diff; `Ready` before the push |
| `insgt-platform/docs/plans/rails-upgrade-slice-4.md` | slice 4's Phase 0–1 plan and implementation record: the reflection table, the OD10 encoding, the `sql_for` tables, the dangling sets' provenance, the approval decisions and modifications A–H, the loop records, the deviations, the review dispositions |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-5a.md` | slice 5a's runbook: the one commit, the development table with P-5a and the import's production profile, P-PROD's eight extra lines, the pre-push captures (the release runner, the S9b and S16 baselines, the ops@ inbox), S14, the watched run's four-part read (S9, S9b, S16, the inbox), SH with `Regexp::TimeoutError`, the one-off-dyno rollback note |
| `insgt-platform/docs/plans/rails-upgrade-slice-5.md` | slice 5's Phase 0–1 plan (5a and 5b), its approval record (eight answers, checks A–C, scope call D), and the 5a implementation record: the loop, the deviations, the review dispositions |
| `insgt-platform/docs/architecture/reviews/` | one review record per deploy and repo (`<date>-slice-<id>-<repo>.md`), from slice 5a on (the slice 5 plan gate, answer 4); slices 1–4 recorded their reviews in their plans and runbooks |
| `insgt-platform/docs/runbooks/deploy-headshot-event-date.md` | the newest runbook, the shape to copy (`deploy-rails-upgrade-<N>.md`, one per slice; slice 0's also records the Honeybadger baseline, §4.1) |
| `insgt-platform/docs/plans/order-processing-note.md` | the decided OrderProcessingNote design (D2 at line 19 keeps Active Storage) |
| `insgt-platform/docs/architecture/account-classification-codebase-notes.md` | `db/schema.rb` line ranges cited there are unaffected unless slice 3's re-dump changes more than the header (OD7) |
