# Rails upgrade — codebase notes

The `file:line` map for `docs/architecture/rails-upgrade.md`. Read at Phase 0 of every slice; verify the entries the slice depends on before surveying fresh. Flat and factual: file, line, what it is, which slice or survey put it there. Paths are `apps/insgt-api` unless prefixed.

Established by the Phase 0 survey of 2026-10-23 against insgt-api `master` at eda99450 (clean tree) and the platform repo `main`; extended the same day for document v2 (the `belongs_to` classification, the recurring tasks, the Honeybadger and branch facts — sections marked "v2"). Line numbers are as of that commit; a moved line is a reason to update this file, not to distrust it. Rails-source citations name the branch (`7-2-stable`, `8-0-stable`, `8-1-stable`) and the file; they were read on 2026-10-23 and are stable for released versions.

## Gemfile and lockfile

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `Gemfile` | 4 | `ruby '3.4.10'` — unchanged by every slice (§2) | survey |
| `Gemfile` | 28 | `gem 'rails', '~> 7.2.0'` — the only line the three version slices edit (`~> 7.2.4`, `~> 8.0.5`, `~> 8.1.4`) | survey; slices 1–3 |
| `Gemfile` | 33 | `gem 'sidekiq', '~> 7.0'` — stays on 7.3.x (§3, OD5) | survey |
| `Gemfile` | 35 | `gem 'string_utils'` — 2012 gem, `urlify` only (see "Gems with Rails coupling") | survey |
| `Gemfile` | 37 | `gem 'strong_migrations'` | survey |
| `Gemfile` | 39, 41 | the `zip_tricks` TODO and `gem 'zipline'` — zipline caps actionpack `< 8.2` (§3) | survey |
| `Gemfile.lock` | 378 | `rails (7.2.3)`; the thirteen `= 7.2.3` component pins sit at 4–65 and 379–391 | survey |
| `Gemfile.lock` | 295–296 | `minitest (6.0.1)` — 7.2.4's activesupport pins `minitest < 6`, so slice 1's lock downgrades it | survey |
| `Gemfile.lock` | 367 | `rack (3.2.4)`; 7.2.x keeps the `rack < 3.3` cap, 8.x drops it | survey |
| `Gemfile.lock` | 459–466 | `rspec-rails (8.0.4)` (`actionpack >= 7.2`) | survey |
| `Gemfile.lock` | 508–509 | `shoulda-matchers (7.0.1)` (`activesupport >= 7.1`; 7.0.0 added Rails 8.1 support) | survey |
| `Gemfile.lock` | 510–520 | `sidekiq (7.3.10)` (`rack >= 2.2.4, < 3.3`), `sidekiq-status (4.0.0)` (`sidekiq >= 7, < 9`) | survey |
| `Gemfile.lock` | 528–530 | `string_utils (1.0.8)` (`activesupport >= 2.3.5`) | survey |
| `Gemfile.lock` | 533–534 | `strong_migrations (2.8.0)` (`activerecord >= 7.2`) | survey |
| `Gemfile.lock` | 568–571 | `zipline (2.2.0)` (`actionpack >= 6.0, < 8.2`) | survey |
| `Gemfile.lock` | 864–868 | `RUBY VERSION ruby 3.4.10`, `BUNDLED WITH 4.0.4` | survey |
| `Gemfile` | — | `gem 'honeybadger'` — does not exist yet; added by slice 0 (6.10.0, 2026-10-21; runtime deps `logger`, `ostruct`; Ruby `>= 3.0.0`; docs: Rails `>= 5.2`, Sidekiq "any") — the one gem added outside `rails` (§2.6) | v2; slice 0 |

Absent from `Gemfile.lock` (greps on 2026-10-23, empty): `activerecord-postgis-adapter`, `rgeo`, `honeybadger` (until slice 0), `sentry`, `rollbar`, `newrelic`, `image_processing`, `ruby-vips`, `mini_magick`, `bootsnap`, `brakeman`, `thruster`, `kamal`, `solid_queue`, `solid_cache`, `solid_cable`.

## Application and environments

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `config/application.rb` | 3 | `require 'rails/all'` — loads Active Storage, Action Cable, Action Text, Action Mailbox and the test-unit railtie even though none is used; drives `app:update`'s `skip_*` derivation (§4.2) | survey |
| `config/application.rb` | 12 | `config.load_defaults 7.2` — bumped to `8.1` only in slice 5b | survey; slice 5 |
| `config/application.rb` | — | `config.active_storage.draw_routes = false` — does not exist yet; added by slice 1 (OD2) | v2; slice 1 |
| `config/application.rb` | 17, 20–21 | `config.autoload_lib(ignore: %w[assets tasks])` plus the older `autoload_paths += Dir["lib/**/"]` / `eager_load_paths << lib` (redundant; §8) | survey |
| `config/application.rb` | 24–25 | `config.hosts << 'api.insightphotos.net'`, `'insgtapi.herokuapp.com'` | fb2e1924 |
| `config/application.rb` | 36 | `config.api_only = true` | survey |
| `config/environments/development.rb` | 33 | `config.active_storage.service = :local` | survey |
| `config/environments/development.rb` | 45, 48 | `deprecation = :log`, `disallowed_deprecation = :raise` | survey |
| `config/environments/production.rb` | 33 | `config.active_storage.service = :local` | survey |
| `config/environments/production.rb` | 45, 48 | `config.force_ssl = true`; `ssl_options` excludes `/up` from the redirect | 7fe510d1 |
| `config/environments/production.rb` | 51–56 | `config.logger` = `ActiveSupport::Logger.new(STDOUT)` wrapped in `TaggedLogging`; `log_tags = [:request_id]` — the 8.x template would replace this with `TaggedLogging.logger(STDOUT)` (§4.2 reject) | survey |
| `config/environments/production.rb` | 36–38 | the commented `config.action_cable.mount_path` / `url` / `allowed_request_origins` lines — removed by §8 item 7 (OD6) together with `development.rb:69` and `config/cable.yml` | v2 |
| `config/environments/production.rb` | 83 | `config.active_support.report_deprecations = false` — silences every deprecator (`7-2-stable activesupport/lib/active_support/railtie.rb:66–70`); slice 1 flips it to `true` and adds `config.active_support.deprecation = :notify` (OD8) | survey; slice 1 |
| `config/environments/production.rb` | 86 | `dump_schema_after_migration = false` | survey |
| `config/environments/production.rb` | 99 | `host_authorization` excludes `/up` | 7fe510d1 |
| `config/environments/production.rb` | 101–111 | SendGrid SMTP: `delivery_method = :smtp`, `default_url_options` from `MAILER_URL`, `ActionMailer::Base.smtp_settings` with `SENDGRID_API_KEY` — the reason `app:update`'s production template is rejected (§4.2) | survey |
| `config/environments/test.rb` | 29 | `show_exceptions = :rescuable` | survey |
| `config/environments/test.rb` | 39 | `host_authorization = { exclude: ->(_request) { true } }` | survey |
| `config/environments/test.rb` | 42 | `config.active_storage.service = :test` | survey |
| `config/environments/test.rb` | 58 | `config.active_support.deprecation = :stderr` — slice 1 changes this to `:raise` | survey; slice 1 |
| `config/honeybadger.yml` | — | does not exist yet; slice 0 adds it without the API key (ENV `HONEYBADGER_API_KEY`), with `report_data` explicit per environment, `insights: enabled: false`, `sidekiq: attempt_threshold: 0` | v2; slice 0 |
| `README.md` | 140–144 | the 2015 add-on list: `newrelic:wayne`, `papertrail:choklad` (the log drain slice 1's Active Storage history grep looks for), `sendgrid:starter`, `scheduler:standard` | v2 |
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
| `config/sidekiq_status.rb` | 1–15 | configures the sidekiq-status middleware; nothing requires this file (grep empty) and `config/sidekiq.yml` is absent — UNVERIFIED whether it loads in production (§8) | survey |
| `Procfile` | 1–2 | `web: bundle exec puma -C config/puma.rb`; `backgroundworker: bundle exec sidekiq -c 4`; no release phase | survey |
| `.env` | — | sets `SECRET_KEY_BASE` (8.0.2+/8.1 use it in dev/test instead of `tmp/local_secret.txt`; no cookies or verifiers in app code, so inert) | survey |

## Initializers — the five framework-defaults shims and the rest

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `config/initializers/new_framework_defaults.rb` | 10 | `action_controller.per_form_csrf_tokens = false` — inert: CSRF verification is skipped (see `application_controller.rb:2–3`); deleted with the file in slice 5b | Rails 5.0 shim, 2bfb1f01 |
| `config/initializers/new_framework_defaults.rb` | 13 | `action_controller.forgery_protection_origin_check = false` — inert, same reason; deleted with the file in slice 5b | Rails 5.0 shim |
| `config/initializers/new_framework_defaults.rb` | 17 | `ActiveSupport.to_time_preserves_timezone = false` — the **only** Rails deprecation in the baseline; removed in slice 1 (§4.1) | Rails 5.0 shim; slice 1 |
| `config/initializers/new_framework_defaults.rb` | 18–20 | the comment and `active_record.belongs_to_required_by_default = false` — **removed, not relocated, in slice 4** (rule D′, §4.5, OD4); see "`belongs_to` and column nullability" below for what depends on it | Rails 5.0 shim; slice 4 |
| `config/initializers/new_framework_defaults_6_0.rb` | 1–45 | entirely commented out — dead; deleted in slice 5b | survey |
| `config/initializers/new_framework_defaults_7_2.rb` | 1–70 | entirely commented out — dead (`load_defaults 7.2` already applies all of it); deleted in slice 5b | survey |
| `config/initializers/new_framework_defaults_8_0.rb` | — | does not exist; generated by slice 2's `app:update`, with only `to_time_preserves_timezone = :zone` uncommented (§4.3); that line is deleted in slice 3; rows 2–3 of §4.6 flipped in 5a; the file deleted in 5b | slices 2, 3, 5 |
| `config/initializers/new_framework_defaults_8_1.rb` | — | does not exist; generated by slice 3's `app:update`, all commented; flipped and deleted in slice 5b | slices 3, 5 |
| `config/initializers/deprecation_reporting.rb`, `app/services/deprecation_reporter.rb` | — | do not exist; slice 1 adds the production-only `/\Adeprecation\./` subscriber and the once-per-message Honeybadger reporter (§4.2, OD8) | v2; slice 1 |
| `config/initializers/strong_migrations.rb` | 7 | `start_after = 20260806120000` | pre-survey |
| `config/initializers/strong_migrations.rb` | 11–12, 14 | Heroku Postgres essential-1 reports PG 15.17 (2026-08-07); "REVISIT AT THE RENDER.COM CUTOVER" | pre-survey |
| `config/initializers/strong_migrations.rb` | 18 | `target_version = 15` — never edited by this upgrade (§2 trap) | pre-survey |
| `config/initializers/json_param_key_transform.rb` | 2–6 | replaces `ActionDispatch::Request.parameter_parsers[:json]` with a deep-underscoring parser (`deep_transform_keys!`) | survey |
| `config/initializers/wrap_parameters.rb` | 7–9 | `wrap_parameters format: [:json]` — untouched by 8.0/8.1 | survey |
| `config/initializers/cors.rb` | 8–55 | customised `Rack::Cors` allow-list (`:41` names the Lambda photo resizer) — why the template `cors.rb` is rejected | survey |
| `config/initializers/filter_parameter_logging.rb` | 4–8 | customised filter list (`password password_confirmation code token passw email secret key crypt salt certificate otp ssn phone phone_number phone_number_formatted`, partial-matched) — template rejected; **reused by Honeybadger** ("In Rails, this also includes existing params filters", configuration reference) and reviewed in slice 0 against the `Authorization` header and Stripe fields | survey; slice 0 |
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
| `bin/rails routes` | — | 592 routes; **9** are Active Storage (`/rails/active_storage/{blobs,representations,disk,direct_uploads}`), drawn because `rails/all` loads the engine and `draw_routes` is unset (grep `draw_routes` in `config/`: empty); **turned off in slice 1** (OD2) | survey; slice 1 |
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
| `spec/models/postal_code_spec.rb` | 110–141 | `#nearby_cities` (ordered by distance, excludes deleted, excludes no-coordinates) — the haversine check | survey |
| `spec/lib/stripe_card_spec.rb`, `spec/models/account_stripe_spec.rb`, `spec/models/order_issue_refund_spec.rb`, `spec/models/transaction_charge_failure_spec.rb` | — | the Stripe paths; the last two also assert `ActionMailer::Base.deliveries` | survey |
| `spec/requests/users_directory_spec.rb` | 11 | `GET /users/directory` — JWT request spec with the pagination `metadata` contract | survey |
| `spec/requests/orders_processing_parent_pays_spec.rb` | 12 | raw `select_all` path through `OrderSql` | survey |
| `spec/requests/orders_processing_release_on_spec.rb`, `spec/requests/accounts_most_recent_shoot_spec.rb` | — | the `search_time_params` / time-zone request specs | survey |
| `spec/workers/property_data_lookup_worker_spec.rb` | 3 | worker `#perform` example | survey |
| `spec/architecture/account_classification_spec.rb` | — | the existing contract spec and the shape to copy; `spec/architecture/rails_upgrade_spec.rb` is created by slice 1 and extended by every later slice (§4.2–§4.6); `spec/services/deprecation_reporter_spec.rb` is slice 1's | slice 1 |
| `spec/support/sql_helpers.rb` | 11–21 | `sql_for` — slice 4 measures the extra association loads on an `Order` save with it (§4.5) | survey; slice 4 |

## Recurring work and workers (v2 — slices 0, 1 and 5)

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `lib/tasks/scheduler.rake` | 1–18 | the four Heroku Scheduler tasks: `import_order_photos` (`Order.import_processed_photos`), `send_delayed_notifications`, `cleanup_unused_watermarks`, `import_listings` (`Crmls.import` at 17; `Sandicor.import` commented at 16). **No recurring Sidekiq job exists** — workers are enqueued by user activity (`app/models/order.rb` ×4, `transaction.rb` ×2, `property.rb`, `postal_code.rb`, `site_export.rb`, `concerns/order_zip.rb`, `app/services/photo_classifier_service.rb`, `lib/order_image_handler_import.rb`, four rake tasks) | v2 |
| `lib/tasks/scheduler.rake` | 17 | where slice 0's `Honeybadger.check_in(ENV['HONEYBADGER_CHECKIN_IMPORT_LISTINGS'])` goes, after `Crmls.import` (OD11) | v2; slice 0 |
| `lib/crmls.rb` | 63–106, 342, 372, 444–494 | `Crmls.import` and its `rescue`/`ensure` blocks — the regex-dense path 5a watches | v2 |
| `app/workers/property_data_lookup_worker.rb` | 30–38 | `perform(property_id, force)` → `PropertyFactsService.call`; `rescue StandardError` logs and `update_all`s — the P3 candidate (`perform_async(0)` completes with no external call; ASSUMPTION, the slice plan confirms by reading the service) | v2 |
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
| gem-reference/configuration | `api_key` ← `HONEYBADGER_API_KEY`; `env` ← `HONEYBADGER_ENV` (Rails uses `Rails.env`); `report_data` ← `HONEYBADGER_REPORT_DATA`, "Defaults to false for "test", "development", and "cucumber" environments"; `development_environments` default `["development", "test", "cucumber"]`; `exceptions.ignore` adds to a built-in list that includes `ActiveRecord::RecordNotFound`; `request.filter_keys` default `['password', 'password_confirmation']` — "In Rails, this also includes existing params filters"; `sidekiq.attempt_threshold` default `0`; `sidekiq.use_component` default `true`; `insights.enabled` default `true` (v6+); no check-in keys in the config file |
| getting-started/performing-check-ins | `Honeybadger.check_in('1MqIo1')` with the id from the project; "Now your task will check in when it's executed periodically by cron, Heroku Scheduler, etc."; "If it ever stops checking in, Honeybadger will notify you." |
| gem-reference/cli | `honeybadger test` — "Send a test notification from Honeybadger"; `honeybadger install` sets up a new project (writes `config/honeybadger.yml` and sends a test exception, per the Rails guide) — **not used**, the key stays in ENV; `honeybadger deploy` notifies a deployment |
| integration-guides/rails-exception-tracking | errors reported automatically in web requests, background jobs, rake tasks and `at_exit`; `Rails.error.handle` reported, `Rails.error.record` not |
| gem-reference/supported-versions | Ruby `>= 2.7.0`, Rails `>= 5.2`, Sidekiq "any" |
| guides/uptime | monitors are created in the dashboard; success = any 20x by default; "every few minutes"; "Your Honeybadger account comes with uptime monitoring" (trial coverage UNVERIFIED) |
| getting-started/reporting-errors | `Honeybadger.notify(exception_or_string, error_class:, error_message:, fingerprint:, tags:, context:, force:, sync:, component:, action:)`; `fingerprint` — "The `String` grouping fingerprint of the exception"; `sync: true` "skips the worker" |
| insights/automatic-instrumentation | instruments Rails, ActiveJob, Sidekiq, Net::HTTP, Puma events; nothing about deprecations — hence slice 1's own subscriber |
| Rails source | `:notify` behaviour instruments `deprecation.<gem_name>` with `message`, `callstack`, `gem_name`, `deprecation_horizon` (`activesupport/lib/active_support/deprecation/behaviors.rb:37–45`, identical on 7-2 and 8-1); `report_deprecations == false` sets `deprecators.silenced = true` (`activesupport/lib/active_support/railtie.rb:66–70`, 7-2) |

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
| `insgt-platform/docs/runbooks/deploy-headshot-event-date.md` | the newest runbook, the shape to copy (`deploy-rails-upgrade-<N>.md`, one per slice; slice 0's also records the Honeybadger baseline, §4.1) |
| `insgt-platform/docs/plans/order-processing-note.md` | the decided OrderProcessingNote design (D2 at line 19 keeps Active Storage) |
| `insgt-platform/docs/architecture/account-classification-codebase-notes.md` | `db/schema.rb` line ranges cited there are unaffected unless slice 3's re-dump changes more than the header (OD7) |
