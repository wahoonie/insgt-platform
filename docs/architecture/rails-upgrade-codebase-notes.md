# Rails upgrade — codebase notes

The `file:line` map for `docs/architecture/rails-upgrade.md`. Read at Phase 0 of every slice; verify the entries the slice depends on before surveying fresh. Flat and factual: file, line, what it is, which slice or survey put it there. Paths are `apps/insgt-api` unless prefixed.

Established by the Phase 0 survey of 2026-10-23 against insgt-api `master` at eda99450 (clean tree) and the platform repo `main`; extended the same day for document v2 (the `belongs_to` classification, the recurring tasks, the Honeybadger and branch facts — sections marked "v2"); extended on 2026-10-26 by slice 0 (insgt-api `chore/rails-upgrade-slice-0`, `d4dd6d9e`, `a641c52b` — rows marked "slice 0" and the Honeybadger gem-source section); extended the same day by slice 1 (insgt-api `chore/rails-upgrade-slice-1`, `5c9446da`…`a5d9b001` — rows marked "slice 1" and the "Slice 1" section; every row a slice 1 commit moved was re-verified at `a5d9b001`). Line numbers are as of the latest marked commit; a moved line is a reason to update this file, not to distrust it. Rails-source citations name the branch (`7-2-stable`, `8-0-stable`, `8-1-stable`) and the file; they were read on 2026-10-23 and are stable for released versions.

## Gemfile and lockfile

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `Gemfile` | 4 | `ruby '3.4.10'` — unchanged by every slice (§2) | survey |
| `Gemfile` | 29 | `gem 'rails', '~> 7.2.4'` (was `~> 7.2.0` at 28 before slice 0 inserted line 15) — the only line the three version slices edit (`~> 7.2.4` done; `~> 8.0.5`, `~> 8.1.4` next) | survey; slice 1 `5c9446da` |
| `Gemfile` | 34 | `gem 'sidekiq', '~> 7.0'` — stays on 7.3.x (§3, OD5) | survey; +1 since slice 0 |
| `Gemfile` | 36 | `gem 'string_utils'` — 2012 gem, `urlify` only (see "Gems with Rails coupling") | survey; +1 since slice 0 |
| `Gemfile` | 38 | `gem 'strong_migrations'` | survey; +1 since slice 0 |
| `Gemfile` | 40, 42 | the `zip_tricks` TODO and `gem 'zipline'` — zipline caps actionpack `< 8.2` (§3) | survey; +1 since slice 0 |
| `Gemfile.lock` | 380 | `rails (7.2.4)`; the thirteen components at `7.2.4` with their `(= 7.2.4)` pins; `DEPENDENCIES` `rails (~> 7.2.4)` at 618 | slice 1 `5c9446da` |
| `Gemfile.lock` | 298 | `minitest (5.27.0)` — downgraded from 6.0.1 because 7.2.4's activesupport pins `minitest < 6`; its `prism (~> 1.5)` sub-dependency line went with it (`prism (1.9.0)` stays at 357) | slice 1 `5c9446da` |
| `Gemfile.lock` | 70, 74 | under `activesupport`: `connection_pool (>= 2.2.5, < 3)` and `minitest (>= 5.1, < 6)` — 7.2.4's gemspec constraints; `connection_pool (2.5.5)` at 126 is inside the cap | slice 1 `5c9446da` |
| `Gemfile.lock` | 369 | `rack (3.2.4)`; 7.2.x keeps the `rack < 3.3` cap, 8.x drops it | survey; re-verified slice 1 |
| `Gemfile.lock` | 461 | `rspec-rails (8.0.4)` (`actionpack >= 7.2`) | survey; re-verified slice 1 |
| `Gemfile.lock` | 510 | `shoulda-matchers (7.0.1)` (`activesupport >= 7.1`; 7.0.0 added Rails 8.1 support) | survey; re-verified slice 1 |
| `Gemfile.lock` | 512, 518 | `sidekiq (7.3.10)` (`rack >= 2.2.4, < 3.3`), `sidekiq-status (4.0.0)` (`sidekiq >= 7, < 9`) | survey; re-verified slice 1 |
| `Gemfile.lock` | 530 | `string_utils (1.0.8)` (`activesupport >= 2.3.5`) | survey; re-verified slice 1 |
| `Gemfile.lock` | 535 | `strong_migrations (2.8.0)` (`activerecord >= 7.2`) | survey; re-verified slice 1 |
| `Gemfile.lock` | 570 | `zipline (2.2.0)` (`actionpack >= 6.0, < 8.2`) | survey; re-verified slice 1 |
| `Gemfile.lock` | 868, 871 | `RUBY VERSION ruby 3.4.10`, `BUNDLED WITH 4.0.4` | survey; re-verified slice 1 |
| `Gemfile` | 15 | `gem 'honeybadger', '~> 6.10'` (locked 6.10.0; runtime deps `logger`, `ostruct`, both already locked; Ruby `>= 3.0.0`; docs: Rails `>= 5.2`, Sidekiq "any") — the one gem added outside `rails` (§2.6); `~> 6.10` blocks a major bump | v2; slice 0 `d4dd6d9e` |

Absent from `Gemfile.lock` (greps on 2026-10-23, empty): `activerecord-postgis-adapter`, `rgeo`, `sentry`, `rollbar`, `newrelic`, `image_processing`, `ruby-vips`, `mini_magick`, `bootsnap`, `brakeman`, `thruster`, `kamal`, `solid_queue`, `solid_cache`, `solid_cable`.

## Application and environments

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `config/application.rb` | 3 | `require 'rails/all'` — loads Active Storage, Action Cable, Action Text, Action Mailbox and the test-unit railtie even though none is used; drives `app:update`'s `skip_*` derivation (§4.2) | survey |
| `config/application.rb` | 12 | `config.load_defaults 7.2` — bumped to `8.1` only in slice 5b | survey; slice 5 |
| `config/application.rb` | 38–41 | the why-comment and `config.active_storage.draw_routes = false` (OD2) — the line OrderProcessingNote's design revisits (§8 item 7) | slice 1 `3a6b8e2e` |
| `config/application.rb` | 17, 20–21 | `config.autoload_lib(ignore: %w[assets tasks])` plus the older `autoload_paths += Dir["lib/**/"]` / `eager_load_paths << lib` (redundant; §8) | survey |
| `config/application.rb` | 24–25 | `config.hosts << 'api.insightphotos.net'`, `'insgtapi.herokuapp.com'` | fb2e1924 |
| `config/application.rb` | 36 | `config.api_only = true` | survey |
| `config/environments/development.rb` | 33 | `config.active_storage.service = :local` | survey |
| `config/environments/development.rb` | 45, 48 | `deprecation = :log`, `disallowed_deprecation = :raise` | survey |
| `config/environments/production.rb` | 33 | `config.active_storage.service = :local` | survey |
| `config/environments/production.rb` | 45, 48 | `config.force_ssl = true`; `ssl_options` excludes `/up` from the redirect | 7fe510d1 |
| `config/environments/production.rb` | 51–56 | `config.logger` = `ActiveSupport::Logger.new(STDOUT)` wrapped in `TaggedLogging`; `log_tags = [:request_id]` — the 8.x template would replace this with `TaggedLogging.logger(STDOUT)` (§4.2 reject) | survey |
| `config/environments/production.rb` | 36–38 | the commented `config.action_cable.mount_path` / `url` / `allowed_request_origins` lines — removed by §8 item 7 (OD6) together with `development.rb:69` and `config/cable.yml` | v2 |
| `config/environments/production.rb` | 82–85 | the comment, `config.active_support.report_deprecations = true` (84; was `false` at 83, which silenced every deprecator — `railtie.rb:66–70`) and `config.active_support.deprecation = :notify` (85) — every registered deprecator emits `deprecation.<gem>` (OD8). `report_deprecations` is set nowhere else (grep) | survey; slice 1 `e54247cb` |
| `config/environments/production.rb` | 88 | `dump_schema_after_migration = false` | survey; +2 since slice 1 |
| `config/environments/production.rb` | 101 | `host_authorization` excludes `/up` | 7fe510d1; +2 since slice 1 |
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
| `config/boot.rb`, `config.ru` | — | stock; `app:update` does not regenerate either (`app_generator.rb` update tasks touch only `bin/` and `config/`) | survey |
| `config/puma.rb` | 23–24, 27, 30, 34 | threads from `RAILS_MAX_THREADS` (3), port, `plugin :tmp_restart`, pidfile — identical to the 8.x template minus comments | survey |
| `config/database.yml` | 4, 24 | `pool:` — still read by 8.1 (`8-1-stable activerecord/.../database_configurations/hash_config.rb:73–85`, `fetch(:pool, 5)`); only the Ruby method `pool` is deprecated | survey |
| `config/storage.yml` | 1–7 | `test` and `local` Disk services only | survey |
| `config/cable.yml` | 7–10 | production `redis` adapter on `REDIS_URL` — unused (no Action Cable code) | survey |
| `config/secrets.yml`, `config/secrets.yml.rb` | 13, 16, 21 | tracked, dead since 7.2 removed `Rails.application.secrets`; carry literal dev/test `secret_key_base` values (§8) | survey |
| `config/newrelic.yml`, `config/elasticsearch.yml`, `config/spring.rb`, `bin/spring`, `bin/update` | — | orphaned (no matching gem); `bin/dev` does not exist in this repo — the platform's `bin/dev` drives `Procfile.dev` (§8) | survey |
| `config/sidekiq_status.rb` | 1–15 | configures the sidekiq-status middleware; nothing requires this file (grep empty) and `config/sidekiq.yml` is absent — UNVERIFIED whether it loads in production (§8). Slice 0 observed `Sidekiq::Status::status(jid) => nil` and `get_all => {}` in development for a job that ran — the middleware is not installed there (§4.0 P3, v3) | survey; slice 0 |
| `Procfile` | 1–2 | `web: bundle exec puma -C config/puma.rb`; `backgroundworker: bundle exec sidekiq -c 4`; no release phase | survey |
| `.env` | — | sets `SECRET_KEY_BASE` (8.0.2+/8.1 use it in dev/test instead of `tmp/local_secret.txt`; no cookies or verifiers in app code, so inert) | survey |

## Initializers — the five framework-defaults shims and the rest

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `config/initializers/new_framework_defaults.rb` | 10 | `action_controller.per_form_csrf_tokens = false` — inert: CSRF verification is skipped (see `application_controller.rb:2–3`); deleted with the file in slice 5b | Rails 5.0 shim, 2bfb1f01 |
| `config/initializers/new_framework_defaults.rb` | 13 | `action_controller.forgery_protection_origin_check = false` — inert, same reason; deleted with the file in slice 5b | Rails 5.0 shim |
| `config/initializers/new_framework_defaults.rb` | (15–18) | the `to_time` comment pair, `ActiveSupport.to_time_preserves_timezone = false` (was 17, the **only** Rails deprecation in the baseline) and the blank line after it — **deleted**; `load_defaults 7.2`'s value `true` now stands. Restoring line 17 under `:raise` fails the suite at boot (`ActiveSupport::DeprecationException`, 139 load errors) | Rails 5.0 shim; slice 1 `a59df0b0` |
| `config/initializers/new_framework_defaults.rb` | 15–16 | the comment and `active_record.belongs_to_required_by_default = false` (was 19–20) — **removed, not relocated, in slice 4** (rule D′, §4.5, OD4); see "`belongs_to` and column nullability" below for what depends on it | Rails 5.0 shim; slice 4 |
| `config/initializers/new_framework_defaults_6_0.rb` | 1–45 | entirely commented out — dead; deleted in slice 5b | survey |
| `config/initializers/new_framework_defaults_7_2.rb` | 1–70 | entirely commented out — dead (`load_defaults 7.2` already applies all of it); deleted in slice 5b | survey |
| `config/initializers/new_framework_defaults_8_0.rb` | — | does not exist; generated by slice 2's `app:update`, with only `to_time_preserves_timezone = :zone` uncommented (§4.3); that line is deleted in slice 3; rows 2–3 of §4.6 flipped in 5a; the file deleted in 5b | slices 2, 3, 5 |
| `config/initializers/new_framework_defaults_8_1.rb` | — | does not exist; generated by slice 3's `app:update`, all commented; flipped and deleted in slice 5b | slices 3, 5 |
| `config/initializers/deprecation_reporting.rb` | 17 | `Rails.application.config.to_prepare { DeprecationReporter.subscribe } if Rails.env.production?` — see the "Slice 1" section for why `to_prepare` | slice 1 `e54247cb` |
| `config/initializers/strong_migrations.rb` | 7 | `start_after = 20260806120000` | pre-survey |
| `config/initializers/strong_migrations.rb` | 11–12, 14 | Heroku Postgres essential-1 reports PG 15.17 (2026-08-07); "REVISIT AT THE RENDER.COM CUTOVER" | pre-survey |
| `config/initializers/strong_migrations.rb` | 18 | `target_version = 15` — never edited by this upgrade (§2 trap) | pre-survey |
| `config/initializers/json_param_key_transform.rb` | 2–6 | replaces `ActionDispatch::Request.parameter_parsers[:json]` with a deep-underscoring parser (`deep_transform_keys!`) | survey |
| `config/initializers/wrap_parameters.rb` | 7–9 | `wrap_parameters format: [:json]` — untouched by 8.0/8.1 | survey |
| `config/initializers/cors.rb` | 8–55 | customised `Rack::Cors` allow-list (`:41` names the Lambda photo resizer) — why the template `cors.rb` is rejected | survey |
| `config/initializers/filter_parameter_logging.rb` | 4–8 | customised filter list (`password password_confirmation code token passw email secret key crypt salt certificate otp ssn phone phone_number phone_number_formatted`, partial-matched) — template rejected; **reused by Honeybadger for request notices only** (read from the request's `action_dispatch.parameter_filter`, gem `notice.rb:576–582`; Sidekiq job args never pass through it). Partial match filters `area_code` (via `code`) and `access_token` (via `token`); a bare `number` param goes in clear. Reviewed in slice 0 on a real notice | survey; slice 0 |
| `config/initializers/inflections.rb` | — | identical to the stock template (no acronyms) | survey |
| `config/initializers/content_security_policy.rb`, `cookies_serializer.rb:5`, `session_store.rb:1` | — | stock files meaningless in an API-only app; `app:update` keeps CSP because it exists; all three are §8 cleanups | survey |
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
| `config/initializers/cors.rb` | 41 | the Lambda photo resizer origin — derivatives are produced outside Rails (`app/workers/photo_resize_worker.rb`, `photo_resize_batch_worker.rb`, `lib/image_handler.rb`, the `S3ImageHandler` concern) | survey |

## Time zones and `to_time`

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/app_param.rb` | 28–34 | `search_time_params` swaps `Time.zone` to `current_user.time_zone` around parsing | survey |
| `app/`, `lib/` | — | `.to_time` appears nowhere (grep empty); `in_time_zone` 25 sites, `Time.zone` 14, `Time.now` 135, `.to_date` 26, `strftime` 54 | survey |
| `app/helpers/orders_helper.rb` | 93 | `time_ago_in_words(timestamp)` — the one indirect `to_time` caller found (slice 1 review); an elapsed time, unchanged by the offset step | slice 1 |
| `spec/architecture/rails_upgrade_spec.rb` | — | pins `ActiveSupport.to_time_preserves_timezone == true` and the Pacific `to_time.utc_offset == -25_200` (2026-10-23 10:00); restoring the old line gives `false` and `0` in the container (`date +%z` → `+0000`) | slice 1 `a59df0b0` |
| `7-2-stable railties/lib/rails/application/configuration.rb` | 117 | `load_defaults "5.0"` sets `ActiveSupport.to_time_preserves_timezone = true` directly | source |
| `7-2-stable activesupport/lib/active_support.rb` | 117–125 | writer warns `unless value` ("pre-Ruby 2.4 behavior … removed in Rails 8.0") | source |
| `8-0-stable railties/.../configuration.rb` | 119, 337–348 | `5.0` sets the config key to `:offset`; `8.0` sets `:zone`, `strict_freshness = true`, `Regexp.timeout ||= 1` | source |
| `8-0-stable activesupport/lib/active_support.rb` | 118–132 | writer warns for `false` and for any value other than `:zone` | source |
| `8-0-stable activesupport/lib/active_support/railtie.rb` | 99–103, 125–130 | after_initialize and `set_configs` both forward the config key to the writer | source |
| `8-1-stable railties/.../configuration.rb` | 335–342, 343–367 | `8.0` block has no `to_time` line; `8.1` block = yjit, `escape_json_responses`, `action_on_path_relative_redirect`, `raise_on_missing_required_finder_order_columns`, `escape_js_separators_in_json`, `render_tracker`, `remove_hidden_field_autocomplete` | source |
| `8-1-stable activesupport/lib/active_support.rb` | 131–137 | writer always warns ("deprecated and will be removed in Rails 8.2") | source |
| `8-1-stable activesupport/lib/active_support/railtie.rb` | 142–147 | `set_configs` still forwards any set key to the writer — a `:zone` line present on 8.1 warns at boot | source |
| `8-1-stable activesupport/lib/active_support/core_ext/date_and_time/compatibility.rb` | — | no `preserve_timezone`; `to_time` always keeps the receiver's zone | source |

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
| `app/models/concerns/{account_query,property_query}.rb`, `app/models/phone_number.rb` | 378; 61, 70, 79; 209 | the `.or(` sites (9 in concerns) that 8.0.3/8.1.0's "`#merge` with `#or` … mixture of attributes and SQL strings" fix can change | survey |

## Controllers, rendering, params

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/controllers/application_controller.rb` | 1 | `ApplicationController < ActionController::Base` (not `ActionController::API`) | survey |
| `app/controllers/application_controller.rb` | 2–3 | `protect_from_forgery with: :null_session`; `skip_before_action :verify_authenticity_token` — the only CSRF references in `app/controllers` | survey |
| `app/controllers/application_controller.rb` | 206–208 | `deep_underscore_params` → `AppParam.deep_underscore_params` | survey |
| `app/controllers/application_controller.rb` | 303 | `head :no_content` — 8.1 raises `DoubleRenderError` if `head` follows a render | survey |
| `app/controllers/application_controller.rb` | 219–234, 308–334 | the `render json:` guard renderers (401/404/400/422), incl. `:unprocessable_entity` at 329, 334 | survey |
| `app/controllers/orders_controller.rb` | 597 | `head :ok` | survey |
| `app/controllers/orders_controller.rb` | 257 | a `render json:` path using `deep_camelize` (per `CLAUDE.md`) | survey |
| `app/controllers/site_exports_controller.rb` | 6, 10 | `render json:` bypassing JBuilder | survey |
| `app/controllers/sessions_controller.rb`, `app/controllers/headshots_controller.rb` | 36; 24, 35 | the other `:unprocessable_entity` sites (Rails converts the symbol; no warning) | survey |
| `app/controllers/transactions_controller.rb` | 55 | `request.remote_ip` → Stripe `client_ip` (8.1 `remote_ip` change) | survey |
| `app/views/**/*.jbuilder` | — | 140 templates; `JbuilderTemplate#target!` is `@attributes.to_json` (jbuilder-2.14.1 `lib/jbuilder.rb:271–273`), so 8.1's `escape_json_responses` (renderer-level, `8-1-stable actionpack/lib/action_controller/metal/renderers.rb:169–172`) does not touch JBuilder output; `escape_js_separators_in_json` (AS-level, `8-1-stable activesupport/lib/active_support/json/encoding.rb:92–98`) does | survey |
| `config/routes.rb` | 4 | `get 'up' => 'rails/health#show'`; 360 lines, 592 routes, no `mount`, no multi-path routes, no Sidekiq web | 7fe510d1 |

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
| `lib/crmls.rb`, `lib/sandicor.rb`, `app/models/listing.rb` | 560, 473, 1083 lines | the regex-dense MLS import code `Regexp.timeout = 1` (slice 4a) can affect | survey |
| `lib/tasks/marketing_source.rake` | 41 | the one production `upsert_all` | survey |

## Schema facts

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `db/schema.rb` | 13 | `ActiveRecord::Schema[7.2].define(version: 2026_10_07_120001)` — the header a slice 3 re-dump would change to `[8.1]` (OD7) | survey |
| `db/schema.rb` | 15–16 | `enable_extension "pg_stat_statements"`, `"plpgsql"` — no PostGIS | survey |
| `db/schema.rb` | 903, 970, 972 | the three `t.float` columns (UNVERIFIED whether any is PG `real`, which would add `limit:` on an 8.x dump) | survey |
| `db/schema.rb` | — | no `id: false` table (grep empty) — 8.1's `MissingRequiredOrderError` default is inert | survey |
| `db/migrate/` | — | newest `20261007120001`; no Active Storage migration has ever been added or deleted (`git log --diff-filter=D`) | survey |

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
| `spec/architecture/rails_upgrade_spec.rb` | 1–65 | the contract spec, one `describe` per document section; slice 1's 6 examples: the version floor (`>= 7.2.4`, bumped per slice), the `to_time` pair, the gate's config value and its behaviour (every registered deprecator raises), no Active Storage route. Extended by every later slice (§4.2–§4.6) | slice 1 |
| `spec/requests/active_storage_routes_spec.rb` | 1–14 | `POST /rails/active_storage/direct_uploads` → 404 | slice 1 `3a6b8e2e` |
| `spec/services/deprecation_reporter_spec.rb` | 1–188 | 14 examples: the notify call, dedupe (`have_received(...).once`), a different message, the same message from another gem, first app frame and fallback, `.subscribe`, `.received?` ×3, the failure path through a real `:notify` deprecator ×4 | slice 1 |
| slice 1 runs | — | 2026-10-26 on `chore/rails-upgrade-slice-1`: 2,013 at `master` 02dbb78a → **2,034 examples, 0 failures, 0 `DEPRECATION WARNING`** at `a5d9b001`; the 24 rspec-rails `:unprocessable_entity` warnings unchanged (they do not trip `:raise`). Two pre-existing one-second flakes, `spec/lib/tasks/account_classification_rake_spec.rb:156` and `spec/services/account_metrics/calculator_spec.rb:965`, independent of `to_time`; fixed on their own branch after the push | slice 1 |
| `spec/support/sql_helpers.rb` | 11–21 | `sql_for` — slice 4 measures the extra association loads on an `Order` save with it (§4.5) | survey; slice 4 |

## Recurring work and workers (v2 — slices 0, 1 and 5)

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/tasks/scheduler.rake` | 1–18 | the four Heroku Scheduler tasks: `import_order_photos` (`Order.import_processed_photos`), `send_delayed_notifications`, `cleanup_unused_watermarks`, `import_listings` (`Crmls.import` at 17; `Sandicor.import` commented at 16). **No recurring Sidekiq job exists** — workers are enqueued by user activity (`app/models/order.rb` ×4, `transaction.rb` ×2, `property.rb`, `postal_code.rb`, `site_export.rb`, `concerns/order_zip.rb`, `app/services/photo_classifier_service.rb`, `lib/order_image_handler_import.rb`, four rake tasks) | v2 |
| `lib/tasks/scheduler.rake` | 19–23 | slice 0's check-in: `ENV.fetch('HONEYBADGER_CHECKIN_IMPORT_LISTINGS', nil)` then `Honeybadger.check_in(check_in_id) if check_in_id.present?`, after `Crmls.import` (17) so a raise skips it (OD11). Cadence hourly, finishing about :35 UTC (`mls_imports`, dev restore) | slice 0 `a641c52b` |
| `lib/crmls.rb` | 94–95 | `extract_listings` returns early, without raising, when `mls.import_errors` is non-empty (failed login) — so the check-in means the task finished, not that listings arrived | slice 0 |
| `lib/crmls.rb` | 63–106, 342, 372, 444–494 | `Crmls.import` and its `rescue`/`ensure` blocks — the regex-dense path 5a watches | v2 |
| `app/workers/property_data_lookup_worker.rb` | 30–39 | `perform(property_id, force)` → `PropertyFactsService.call`. `:32–33` rescues `PropertyDataAlreadyFetchedError` and logs "…already has property data, skipping" — **P3's path** (an already-fetched property, `property_data_status: 2`; 174 on the dev restore, ids 1964 … 66237). `:34–39` rescues `StandardError`, logs, `update_all`s and **re-raises** — so v2's `perform_async(0)` ends in `fail`, not `done` (the ASSUMPTION was false) | v2; corrected slice 1 |
| `app/workers/generate_coordinates_worker.rb` | 24–25 | `klass_name.constantize.find(id)` — `perform_async('NoSuchClass', 1)` raises `NameError` before any geocoding: slice 0's deliberately failing job (a `RecordNotFound` would be ignored by Honeybadger's default list) | v2; slice 0 |
| sidekiq 7.3.10 `lib/sidekiq/cli.rb` | — | logs `Booted Rails <version> application in <env> environment` at start — the P3/S2 line | v2 |

## `belongs_to` and column nullability (v2 — slice 4, rule D′)

Runner over every eager-loaded `ApplicationRecord` descendant, 2026-10-23 (the script is in §4.5's spec plan; re-run it at slice 4's survey):

| Fact | Value |
| :-- | :-- |
| non-polymorphic `belongs_to` reflections | 89 |
| on `NOT NULL` foreign-key columns | 49 — all currently optional (47 via the global `false`, 2 via explicit `optional: true`: the `TagsResource` pair) |
| on nullable columns | 39 — 36 explicit `optional: true`; **3 implicit** (gain the option in slice 4): `Area#area_type` (`app/models/area.rb:9`), `Listing#property_type` (`app/models/listing.rb:37`), `OrderUrlGroup#order` (`app/models/order_url_group.rb:6`) |
| with no column | 1 — `Area#state` (`app/models/area.rb:7`, `belongs_to :state, optional: true`; the `areas` table in `db/schema.rb` has `city_id`, `area_type_id`, `parent_area_id` and no `state_id`) |
| two `belongs_to` on one column | `TagsResource#user` and `#property`, both `foreign_key: :resource_id` (`app/models/tags_resource.rb:7–8`); `tags_resources.resource_id` and `resource_type` are `NOT NULL` (`db/schema.rb`, the `tags_resources` table); validations at `tags_resource.rb:10–12` require `resource_id`, `resource_type`, `tag_id` — nothing asserts that exactly one target resolves (OD10) |
| explicit `optional: false` / `required:` | 0 / 0 |

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

## Platform repo and documentation

Branch facts (OD9, verified 2026-10-23): the platform repo's `origin/HEAD` is `main`; `docs/rails-upgrade` is based on `main` (merge-base dff7500 = `main`'s tip). insgt-api's `origin/HEAD` and `heroku/HEAD` are both `master`; `apps/insgt-api/docs/` holds only `ops/` and `plans/` — every design document lives here, in `insgt-platform/docs/architecture/` (`insgt-platform/CLAUDE.md:11`). §2.7 is the merge step.

| File | What it is |
| :-- | :-- |
| `insgt-platform/docs/architecture/rails-upgrade.md` | the design document this file maps |
| `insgt-platform/docs/architecture/rails-upgrade-slices/slice-N.md` | the slice prompts (Phase 2) |
| `insgt-platform/docs/runbooks/README.md` | runbook conventions (`Status:` header, `## Deploy log`); each slice writes `deploy-rails-upgrade-N.md` in that shape |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-0.md` | slice 0's runbook: deploy steps, S0–S2/S9, the dev verification log (notice ids), and — after 24 h — the Honeybadger baseline every later slice's SH check compares against (its window spans v659 and v660) |
| `insgt-platform/docs/runbooks/deploy-rails-upgrade-1.md` | slice 1's runbook: the eight commits, the Active Storage audit, the pre-push production-config probe, the v660 "before" captures, S-DEP, and the development verification and review log |
| `insgt-platform/docs/plans/rails-upgrade-slice-1.md` | slice 1's Phase 0–1 plan (untracked) |
| `insgt-platform/docs/runbooks/deploy-headshot-event-date.md` | the newest runbook, the shape to copy (`deploy-rails-upgrade-<N>.md`, one per slice; slice 0's also records the Honeybadger baseline, §4.1) |
| `insgt-platform/docs/plans/order-processing-note.md` | the decided OrderProcessingNote design (D2 at line 19 keeps Active Storage) |
| `insgt-platform/docs/architecture/account-classification-codebase-notes.md` | `db/schema.rb` line ranges cited there are unaffected unless slice 3's re-dump changes more than the header (OD7) |
