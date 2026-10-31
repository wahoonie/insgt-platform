# Rails upgrade (insgt-virtual-tour) — codebase notes

The `file:line` map, the survey record and the verification scripts for `docs/architecture/rails-upgrade-virtual-tour.md`.
Read at Phase 0 of every slice; verify the entries the slice depends on before surveying fresh. Paths are
`apps/insgt-virtual-tour` unless prefixed. Established by the Phase 0 survey of 2026-10-31 against `main` at `eee78cf`
(clean tree, `main` == `origin/main`). Line numbers are as of that commit; a moved line is a reason to update this
file, not to distrust it. Gem-source citations name the gem version and file; they were read from the installed gems
on 2026-10-31. Extended the same day by the Honeybadger change (v3, tour `chore/honeybadger` at `93f7d30`, off `main`
`06ae511`) — the "Honeybadger (v3)" section and the render-pages.rb fix.

## Gemfile and lockfile

| File | Line | What it is |
| :-- | :-- | :-- |
| `Gemfile` | 4 | `ruby "3.4.12"` — unchanged by every slice |
| `Gemfile` | 7 | `gem 'rails', '~> 8.0.2'` → `'~> 8.1.4'` (slice 1) |
| `Gemfile` | 10 | `gem "sprockets-rails"` (unconstrained; sprockets itself is transitive) |
| `Gemfile` | 13 | `gem "puma", "~> 6.0"` |
| `Gemfile` | 27 | `gem "bootsnap", require: false` |
| `Gemfile` | 35, 40 | `dotenv-rails` (development, test), `web-console` (development) |
| `Gemfile` | 51–53 | `capybara`, `selenium-webdriver`, `webdrivers` (test) |
| `Gemfile` | 56–58 | `tailwindcss-rails "~> 3.3"`, `tailwindcss-ruby "~> 3.4"`, `font-awesome-rails` |
| `Gemfile.lock` | 125 | `font-awesome-rails (4.7.0.9)` — `railties (>= 3.2, < 9.0)` |
| `Gemfile.lock` | 150 | `minitest (5.25.5)` |
| `Gemfile.lock` | 188, 191 | `puma (6.6.0)`, `rack (3.1.15)` |
| `Gemfile.lock` | 199 | `rails (8.0.2)` |
| `Gemfile.lock` | 217 | `rails-html-sanitizer (1.6.2)` |
| `Gemfile.lock` | 238, 271 | `selenium-webdriver (4.10.0)`; `webdrivers (5.3.1)` pins `selenium-webdriver (~> 4.0, < 4.11)` |
| `Gemfile.lock` | 246, 251 | `sprockets-rails (3.5.2)`; `tailwindcss-rails (3.3.2)` — `railties (>= 7.0.0)`. `sprockets (4.2.2)` is the entry just above sprockets-rails |
| `Gemfile.lock` | 266 | `web-console (4.2.1)` |
| `Gemfile.lock` | 315–319 | `RUBY VERSION ruby 3.4.12p148`; `BUNDLED WITH 2.6.9` |
| `Gemfile.lock` | — | **no `json` line**: the app runs Ruby's default json 2.9.1 (`bundle exec ruby -e 'require "json"; puts JSON::VERSION'`) |
| `Gemfile.lock` | `PLATFORMS` | `aarch64-linux`, `aarch64-linux-gnu`, `aarch64-linux-musl`, `arm-linux`, `arm-linux-gnu`, `arm-linux-musl`, `arm64-darwin`, `ruby`, `x86_64-darwin`, `x86_64-linux`, `x86_64-linux-gnu`, `x86_64-linux-musl` — `bin/render-build.sh:6` adds nothing |

## Application configuration

| File | Line | What it is |
| :-- | :-- | :-- |
| `config/application.rb` | 3, 5, 9, 13 | `require "rails"`, `active_model/railtie`, `action_controller/railtie`, `action_view/railtie` — the only frameworks loaded; `:6–8, 10–12, 14–15` commented (Active Job, Active Record, Active Storage, Action Mailer, Action Mailbox, Action Text, Action Cable, `rails/test_unit`) |
| `config/application.rb` | 24 | `config.load_defaults 7.0` — slice 2 sets `8.1`; unchanged since `6f53980` (2022-07-18) |
| `config/application.rb` | 29 | `config.autoload_lib(ignore: %w[assets tasks])` |
| `config/application.rb` | 40 | `config.generators.system_tests = nil` |
| `config/environments/production.rb` | 10, 16 | `eager_load = true`; `perform_caching = true` (no `cache` helper call exists) |
| `config/environments/production.rb` | 19 | `public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present? \|\| ENV['RENDER'].present?` — the 8.1 template drops this line (rejected) |
| `config/environments/production.rb` | 26, 29 | `assume_ssl = true`, `force_ssl = true` — the 8.1 template comments both out (rejected) |
| `config/environments/production.rb` | 36, 39 | `config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)`; `log_level` from `RAILS_LOG_LEVEL` |
| `config/environments/production.rb` | 42 | `silence_healthcheck_path = "/up"` (no `/up` route exists; the health route is `/heartbeat`) |
| `config/environments/production.rb` | 45 | `active_support.report_deprecations = false` — OD2 flips it |
| `config/environments/production.rb` | 55 | `# config.hosts = [` — host authorization off |
| `config/environments/development.rb` | 32, 41 | `deprecation = :log`; `raise_on_missing_callback_actions = true` |
| `config/environments/test.rb` | 16, 26, 32, 41 | `eager_load = ENV["CI"].present?`; `show_exceptions = :rescuable`; `deprecation = :stderr`; `raise_on_missing_callback_actions = true` |
| `config/initializers/new_framework_defaults_8_0.rb` | 12–18, 20–25, 27–30 | the three 8.0 settings, all commented: `to_time_preserves_timezone = :zone` (gone on 8.1 — never uncomment), `strict_freshness`, `Regexp.timeout = 1` |
| `config/initializers/permissions_policy.rb`, `content_security_policy.rb`, `inflections.rb` | — | all comments |
| `config/initializers/assets.rb` | 4 | `assets.version = "1.0"` |
| `config/initializers/filter_parameter_logging.rb` | 6–8 | the stock list |
| `config/routes.rb` | 1–27 | 15 routes: `:address/b/:id`, `:address/ub/:id`, `/s/:id`, `/su/:id` (redirect: true), `/r/:account_slug`, two pano routes (`api_subdomain: 'insgtapi'`), `/qb/:id`, `/qu/:id`, `/404`, `/500`, `/heartbeat`, `/` (all `via: :all`), and `root` under `constraints CustomDomainConstraint` |
| `config/puma.rb` | 31–35 | threads from `RAILS_MAX_THREADS` (3), port from `PORT`, `plugin :tmp_restart`; **no `workers` line** (`WEB_CONCURRENCY` only in the comment at `:8`) → one Puma process |
| `config/boot.rb` | 3–4 | bundler/setup, bootsnap/setup |

## Controllers, helpers, views, lib

| File | Line | What it is |
| :-- | :-- | :-- |
| `app/controllers/application_controller.rb` | 1, 3 | `< ActionController::Base`; `protect_from_forgery with: :exception` |
| `app/controllers/application_controller.rb` | 5–6, 10–21 | `before_action :set_locale` (subdomain → `I18n.locale`), `after_action :set_response_locale` (`Content-Language`) |
| `app/controllers/listings_controller.rb` | 4–5 | `before_action :find_listing, except: [:account, :redirect]`; `:ensure_correct_language, except: [:redirect]` — `@listing` is never set for `account` |
| `app/controllers/listings_controller.rb` | 9, 49 | `redirect_to canonical_uri, status: :moved_permanently` — the API's `propertyWebsiteUrl*`/`customDomainUrl*` (insgt-api `app/models/listing.rb:524` builds it from `PROPERTY_WEBSITE_HOST`) |
| `app/controllers/listings_controller.rb` | 42 | `redirect_to "#{ENV['LISTING_DOMAIN']}#{request.original_fullpath}"` — cross-host from `es.`; raises under the 7.0 defaults (§3.4 item 2) |
| `app/controllers/listings_controller.rb` | 11, 56 | `render 'errors/not_found', layout: 'application'` |
| `app/controllers/listings_controller.rb` | 17–28 | `account`: `InsightPhoto.find_for_account`, `@brokerage`/`@team` from `organizations`, `render layout: 'account'` |
| `app/controllers/listings_controller.rb` | 33, 37 | `params.permit(:account_slug)`, `params.permit(:page)` |
| `app/controllers/panos_controller.rb` | 2, 5, 8, 19 | `content_security_policy false, only: :show`; `before_action :find_pano, except: [:account]` (no `account` action); `redirect_to '/'`; `render action: :error` — no `panos/error` template (§3.4 item 3) |
| `app/controllers/heartbeat_controller.rb` | 3 | `render json: { 'lub': 'dub' }, head: :ok` — the only `render json:` |
| `app/controllers/errors_controller.rb` | 3, 7 | `render status: 404` / `500` |
| `app/helpers/application_helper.rb` | 27, 58, 83, 192, 267 | `gsub` with string arguments — no regex literal anywhere in `app/`, `lib/`, `config/` |
| `app/helpers/application_helper.rb` | 131–138 | `description_for_locale` → `object[:description]` or `[:descriptionEs]` |
| `app/helpers/application_helper.rb` | 181–188 | `account_url_link` builds HTML by string and returns `raw html` — the one `raw`; no `html_safe`, no `SafeBuffer#%` |
| `app/helpers/application_helper.rb` | 204–210 | `branded?` — `params[:branded] == true` (route default) or `params[:ub] != 'true'` on a custom domain |
| `app/views/listings/_property.html.erb` | 2 | `simple_format description_for_locale(@listing)` — sanitizer vendor row |
| `app/views/listings/_agent_details.html.erb` | 22 | `simple_format description_for_locale(account)` — sanitizer vendor row |
| `app/views/layouts/listings.html.erb` | 26 | `truncate(description_for_locale(@listing), length: 200, …)` (escaped; vendor-independent) |
| `app/views/layouts/listings.html.erb` | 60–61, 69, 71 | `stylesheet_link_tag "tailwind"`, `"application"`; `javascript_include_tag 'fancybox'`, `'lozad'` |
| `app/views/layouts/application.html.erb` | 6, 8–11 | `csrf_meta_tags`; the stylesheet tags (`"inter-font"` is in the sprockets manifest) |
| `app/views/layouts/panos.html.erb` | 31, 105 | `pannellum` stylesheet and script |
| `app/views/listings/_footer.html.erb` | 13, 16 | `Time.now.year` — the only time calls |
| `app/views/components/_broker_logo.html.erb` | 1 | `account[:brokerage] && @listing[:showBrokerageLogo] && …` — `@listing` nil on the account page (§3.4 item 1) |
| `app/views/components/_team_logo.html.erb` | 1 | same shape with `showAgentTeamLogo` |
| `app/views/components/_agent_detail.html.erb` | 5 | `account[:headshot][:s3Key]` — nil headshot crashes (§3.4 item 1) |
| `app/views/listings/account.html.erb` | 5, 18, 68 | renders `agent_detail`; iterates `@response[:data]`; `@response[:metadata][:pageCount]` |
| `app/views/components/_photo_grid.html.erb` | 5 | the AB 723 disclosure link (present on the `1qY5VLqV` render) |
| `lib/insight_photo.rb` | 1 | `require 'net/http'` — the only `require` in app code |
| `lib/insight_photo.rb` | 54, 73, 89, 99 | `Net::HTTP.get_response(URI.parse(url))` to `INSIGHT_API_ENDPOINT` |
| `lib/insight_photo.rb` | 57, 76, 91 | `ActiveSupport::HashWithIndifferentAccess.new(JSON.parse(data))` |
| `lib/image_handler.rb` | 74 | `Base64.strict_encode64(cloudfront_options.to_json)` — the only `to_json` |
| `lib/custom_domain_constraint.rb` | 2–8 | `InsightPhoto.listing_exists?(request.host)` during routing (root only) |
| `app/assets/config/manifest.js` | 1–4 | `link_tree ../images`, `link_directory ../stylesheets .css`, `link_tree ../../../vendor/assets/javascripts .js`, `link_tree ../builds` |
| `app/assets/stylesheets/application.css` | 13–15 | `require_tree .`, `require font-awesome`, `require_self` |

## Tests, bin, deploy, docs

| File | Line | What it is |
| :-- | :-- | :-- |
| `test/test_helper.rb` | 7, 10 | `parallelize(workers: :number_of_processors)`; `fixtures :all` — `NoMethodError` once any test file loads |
| `test/application_system_test_case.rb` | 3–4 | `driven_by :selenium, using: :chrome` — unused |
| `test/**` | — | `.keep` files only; `bin/rails test` → `0 runs` |
| `bin/dev` | 1–16 | sh script: installs foreman, `PORT` default 3000, `foreman start -f Procfile.dev` — the 8.1 template replaces it (rejected) |
| `Procfile.dev` | 1–2 | `web: bin/rails server -p 3000`; `css: bin/rails tailwindcss:watch` |
| `bin/render-build.sh` | 6, 15, 21–23 | `bundle lock --add-platform x86_64-linux`; the Tailwind 3.3.4 binary download; `tailwindcss:build`, `assets:precompile`, `assets:clean` under `set -o errexit` (`:3`) |
| `render.yaml` | 3, 5, 6 | service `insgt-virtual-tour`; `buildCommand: "./bin/render-build.sh"`; `startCommand: "bundle exec puma -C config/puma.rb"` |
| `public/400.html, 404.html, 406-unsupported-browser.html, 422.html, 500.html` | — | stock Rails 8.0 pages, last touched by `1ed6f91` (2025-06-02); never customised |
| `public/favicon.ico`, `apple-touch-icon*.png` | — | the icons that serve; no layout references `icon.svg`/`icon.png` |
| `CLAUDE.md` | 3 | "Stateless Rails 8.0 app" — update after slice 1 |
| `insgt-platform/CLAUDE.md` | 33 | the table row "Rails 8.0, Tailwind — 3002" — update after slice 1 |
| `insgt-platform/docs/services/insgt-virtual-tour.md` | 12 | "Framework: Rails 8.0" — update after slice 1 |

## insgt-api (the JSON contract the tour reads)

| File | Line | What it is |
| :-- | :-- | :-- |
| `apps/insgt-api/app/models/listing.rb` | 524, 532 | `"#{ENV['PROPERTY_WEBSITE_HOST']}/#{address}/#{…}b/#{order_token}"`; the account URL — the redirect targets' host |
| `apps/insgt-api/app/models/listing.rb` | 461–462 | `listing[:description] = virtual_listing['description']`; `[:descriptionEs]` — from `listings.description` (`db/schema.rb:418`, string) and `listings.description_es` (`:453`, text) |
| `apps/insgt-api/app/models/listing.rb` | 610–611 | the agent's `description`/`descriptionEs` from `accounts.description` (`db/schema.rb:81`, string 2056) and `description_es` (`:88`) |
| `apps/insgt-api/app/models/listing.rb` | 687–701 | `Listing.select_virtual(order_token)` — the virtual payload builder; `nil` when the listing is not publishable |
| `apps/insgt-api/app/models/listing.rb` | 212–214 | `Listing#order` is a method (`find_order`), not an association |

## Gem and Rails sources cited

| Where | What |
| :-- | :-- |
| railties 8.1.4 `lib/rails/application/configuration.rb` | `load_defaults` branches: `"7.0"` at `:219` sets `action_controller.action_on_open_redirect = :raise` at `:266`; `"7.1"` at `:269`; the 7.1/7.2/8.0/8.1 blocks as quoted in the document's §4.3 (fetched from the v8.1.4 tag) |
| actionpack 8.1.4 `lib/action_controller/railtie.rb` | `:15` default `action_on_open_redirect = :log`; `:114–124` deprecates `raise_on_open_redirects` only when an app sets it |
| actionpack 8.1.4 `lib/action_controller/metal/redirecting.rb` | `:14` `OpenRedirectError < UnsafeRedirectError`; `:20` `PathRelativeRedirectError`; `:277–288` the guard |
| actionpack 8.0.2 `lib/action_controller/metal/redirecting.rb` | `:17` `raise_on_open_redirects`; `:227` raises `UnsafeRedirectError` |
| actionview 8.1.4 `lib/action_view/helpers/text_helper.rb` | `:383–386` `simple_format` calls `sanitize(text, …)` unless `sanitize: false` |
| actionview 8.1.4 `lib/action_view/helpers/sanitize_helper.rb` | `:12` `sanitizer_vendor` default `Rails::HTML4::Sanitizer`; `:102–113` the 7.1 HTML5 default note |
| sprockets 4.2.2 `lib/sprockets/manifest.rb` | `:318` `JSON.parse(obj, create_additions: false)` (also `npm.rb:40`, `bower.rb:49`) |
| json 3.1.0 `lib/json/common.rb` | `:297` `Parser.parse(source, options)` — raises `ArgumentError: unknown keyword: create_additions` |
| ruby/json `CHANGES.md` | 3.0.0.rc1 (2026-08-11): "Removed the insecure `create_additions` option"; "All unknown options will now cause an `ArgumentError`"; 3.0.0 released 2026-09-07 |
| rails/sprockets `CHANGELOG.md` | 4.3.0: "Fixed compatibility with `json` 3+"; rubygems dates 4.3.0 2026-08-12, 4.4.0 2026-08-18, 4.4.1 2026-08-25, 4.2.2 2025-04-19 |
| rubygems.org/gems/rails/versions | 8.1.4 2026-09-24; 8.1.3.1 and 8.0.5.1 2026-07-29; 8.1.3 and 8.0.5 2026-03-24; 8.1.2.1 and 8.0.4.1 2026-03-23; 8.1.2 2026-01-08; 8.1.1 and 8.0.4 2025-10-28; 8.1.0 2025-10-22; 8.0.3 2025-09-22; 8.0.2 2025-03-12; nothing newer than 8.1.4 |
| rubyonrails.org/maintenance | 8.1.x security until 2027-10-10 (bug fixes until 2026-10-10); 8.0.x security until 2026-11-07 (bug fixes until 2026-05-07); "security fixes for two years after the first release in its series" |
| guides.rubyonrails.org/upgrading_ruby_on_rails.html | `app:update`, the shim mechanism, `load_defaults` stays until changed; Rails 8.0 and 8.1 need Ruby ≥ 3.2.0 |
| railties 8.1.4 `new_framework_defaults_8_1.rb.tt` | the seven commented settings (`escape_json_responses`, `escape_js_separators_in_json`, `raise_on_missing_required_finder_order_columns`, `action_on_path_relative_redirect`, `render_tracker`, `remove_hidden_field_autocomplete`) |

---

## Survey record, 2026-10-31

All runs on rsync copies under the session scratchpad (`rsync -a --exclude .git --exclude node_modules --exclude tmp
--exclude log --exclude coverage --exclude .ruby-lsp`), each with `BUNDLE_GEMFILE=<copy>/Gemfile`, commands prefixed
`mise exec -- bundle _2.6.9_`. `.env` rides along, so the copies reach the dev API on `localhost:3000` (it was up;
`bash -c 'echo > /dev/tcp/127.0.0.1/3000'`). The real tree was read and probed only; `git status` stayed clean. Copies:
`pristine` (baseline), `working` (non-conservative lock + `app:update --force`), `conservative`, `lockonly` (pristine
config + the non-conservative lock), `sprockets-bump` (the slice 1 recipe), `testcheck-802`/`-814`/`-814c`.

### Baseline on the real tree (8.0.2)

- `rails runner -e test 'Rails.application.eager_load!'` → `ok rails=8.0.2 defaults=7.0`, preceded by **2**
  `DEPRECATION WARNING: to_time will always preserve the full timezone … (called from <main> at config/environment.rb:5)`.
- `/heartbeat` via `Rack::MockRequest` (test env) → 200, `{"lub":"dub"}`; headers: `x-frame-options`,
  `x-xss-protection`, `x-content-type-options`, `x-download-options`, `x-permitted-cross-domain-policies`,
  `referrer-policy`, `content-type`, `content-language: en`, weak `etag`, `cache-control`, `x-request-id`, `x-runtime`.
- `bin/rails test` → `0 runs, 0 assertions`.
- `bin/rails routes` → 15 lines. `RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy bin/rails middleware` → 23 lines
  (`rails middleware` rejects `-e`).
- `zeitwerk:check` → All is good!

### Lock resolutions (Gemfile `'~> 8.1.4'`)

- `bundle lock --update rails` (non-conservative, `working`): resolved; moved the 13 rails gems **and** `action_text-trix`
  (new), bigdecimal 4.1.3, concurrent-ruby 1.3.8, connection_pool 3.0.2, crass, date, erb 6.0.7, globalid, i18n 1.15.2,
  io-console, irb 1.18.0, json 3.1.0 (new), loofah 2.25.2, mail 2.9.1, marcel 2.1.0, minitest 6.0.6, net-imap, nio4r,
  nokogiri 1.19.4, pp, prettyprint, prism (new), rack 3.2.8, rack-session, rack-test, rackup, rails-html-sanitizer 1.7.1,
  rake 13.4.2, rbs (new), rdoc 8.1.0, reline, thor 1.5.0, timeout 0.6.1, tsort (new), uri 1.1.2, websocket-driver,
  zeitwerk 2.8.3; `benchmark`, `psych`, `stringio` left. Rejected as scope.
- `bundle lock --update rails --conservative` (`conservative`): the 13 rails gems; `benchmark (>= 0.3)` → `json` under
  activesupport; `benchmark (0.4.1)` out; `json (3.1.0)` in; `tsort (>= 0.2)` under railties; `tsort (0.2.0)` in;
  `DEPENDENCIES rails (~> 8.1.4)`. rack 3.1.15, rails-html-sanitizer 1.6.2, nokogiri 1.18.8, minitest 5.25.5 unchanged.
- `bundle lock --update rails sprockets --conservative` (`sprockets-bump`): the conservative diff plus
  `sprockets (4.2.2)` → `(4.4.1)`, `concurrent-ruby (~> 1.0)` → `(~> 1.1)`. **The slice 1 recipe.**

### 8.1.4 with the unchanged config (`lockonly`, `conservative`, `sprockets-bump`)

- Test-env eager load: `ok rails=8.1.4 defaults=7.0`, **0** deprecation lines (all three copies).
- Production eager load (`RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy`, no manifest yet): `prod ok rails=8.1.4`.
- `zeitwerk:check` → All is good!; routes identical to the baseline; production middleware identical except
  `use ActionDispatch::PermissionsPolicy::Middleware` absent (23 → 22 lines).
- Probe (production env) — 8.0.2 → 8.1.4: `to_time_preserves_timezone` `:offset` → `nil`; `Regexp.timeout` `nil` → `nil`;
  `yjit_config` `false` → `false`; `default_headers` identical (six headers incl. `X-Download-Options`); `sanitizer_vendor`
  `nil` → `nil` (resolved vendor `Rails::HTML4::Sanitizer`, via `ActionView::Base.sanitizer_vendor`); `strict_freshness`
  `false` → `false`; `escape_json` `nil` → `nil`; `path_relative_redirect` `nil` → `:log`; `add_autoload_paths_to_load_path`
  `true` → `true`; `cache_store` `[:file_store, "<root>/tmp/cache/"]` both; `session_store` CookieStore both;
  `message_serializer` `nil` both; `cookies_serializer` `:json` both; `raise_on_open_redirects` `true` → `nil`.
- `bin/rails test` → `0 runs` on every copy.

### `app:update --force` (`working`, 8.1.4)

Output: `identical` config/boot.rb, application.rb, environment.rb, environments/test.rb, initializers/assets.rb,
filter_parameter_logging.rb, inflections.rb, bin/rails, bin/rake, bin/setup, public/robots.txt; `create` config/ci.rb,
initializers/new_framework_defaults_8_1.rb, bin/ci, public/icon.png, public/icon.svg; `force` config/puma.rb,
environments/development.rb, environments/production.rb, initializers/content_security_policy.rb, bin/dev, the five
public error pages; `create` then `remove` initializers/cors.rb. Diffs: see the document's §4.2 table. Post-update
production middleware: `ActionDispatch::AssumeSSL` and `ActionDispatch::SSL` gone, `ActionDispatch::Static` present only
because the template dropped the `RENDER` switch — the reason `production.rb` is rejected. Post-update test eager load
still `defaults=7.0`, 0 deprecations.

### The test scaffolding

A one-file integration test (`get "/heartbeat"`, assert 200 and the JSON) added to copies of 8.0.2 and 8.1.4 (both
locks): `bin/rails test` fails at `test/test_helper.rb:10` with `undefined method 'fixtures' for class
ActiveSupport::TestCase (NoMethodError)` on every copy.

### The Render build sequence and the json 3 blocker

| Copy | json | sprockets | `tailwindcss:build` | `assets:precompile` | `assets:clean` | production boot with manifest | `/heartbeat` via production stack |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `testcheck-802` (8.0.2) | 2.9.1 (default gem) | 4.2.2 | 0 | 0 | 0 | `boot ok 8.0.2` | — |
| `lockonly` (8.1.4) | 3.1.0 | 4.2.2 | 0 | 0 (42 files written) | **1** — `ArgumentError: unknown keyword: create_additions` at `json-3.1.0/lib/json/common.rb:297` | **fails**, same error — and so does a `rails runner -e test` boot on the same copy afterwards: `Sprockets::Railtie.build_manifest` (`sprockets-rails-3.5.2/lib/sprockets/railtie.rb:216`, from the finisher) parses the manifest in every environment once it exists | **fails**, same error |
| `sprockets-bump` (8.1.4) | 3.1.0 | 4.4.1 | 0 | 0 | 0 | `boot ok 8.1.4 sprockets=4.4.1 json=3.1.0` | 200 |

### Rendered pages (test env, `Rack::MockRequest`/`ActionDispatch::Integration::Session`, `HTTP_HOST=www.insightlistings.com`)

| Path | 8.0.2 | 8.1.4 (`lockonly`) | Diff (csrf token stripped) |
| :-- | :-- | :-- | :-- |
| `/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV` | 200, 205,673 bytes | 200, 205,673 bytes | 0 lines; title `30290 Red Lure Pl Canyon Lake, CA 92587 MLS #OC26233239`; 78 `carousel__slide`; 1 disclosure link |
| `…/ub/1qY5VLqV` | 200, 202,944 | 200, 202,944 | 0 |
| `/heartbeat` | 200, 13 | 200, 13 | 0 |
| `/404` | 200, 4,836 | 200, 4,836 | 0 — `ActionDispatch::Static` serves `public/404.html` (4,836 bytes, `wc -c`) before routing; `ErrorsController#not_found` never runs (document §3.4 item 6) |
| `/500` | 200, 7,918 | 200, 7,918 | 0 — `public/500.html` (7,918 bytes), same shadowing |
| `/` | 404, 1,790 ("Real Estate Listings with Insight") | same | 0 |
| `/nonexistent-path` | 404, debug page 37,530 | 404, debug page 48,916 | the DebugExceptions page changed in 8.1 (test env only; production serves `public/404.html`) |
| `/s/1qY5VLqV`, `/su/…`, `/qb/…` with `HTTP_HOST=localhost` | 301 → `http://localhost:3002/30290-…/b/1qY5VLqV` (`ub` for `/su/`) | same | identical `Location` |
| `/s/…` with `HTTP_HOST=www.insightlistings.com` | `UnsafeRedirectError` (target host `localhost:3002` ≠ request host — a dev-only mismatch) | `OpenRedirectError` | same guard |
| `…/b/1qY5VLqV` with `HTTP_HOST=es.insightlistings.com` | `UnsafeRedirectError: Unsafe redirect to "https://insightlistings.com/30290-…"` | `OpenRedirectError`, same message | §3.4 item 2 |
| `…/b/1qY5VLqV` with `HTTP_HOST=es.localhost` | 200, `content-language: en` | same | the locale falls back (no `es` subdomain match) |
| `/r/colleen-crane`, `/r/nora-nido` (brokerage), `/r/logan-banta` (no brokerage, no headshot) | `ActionView::Template::Error` at `_broker_logo.html.erb:1` / `_agent_detail.html.erb:5` | same | §3.4 item 1 |
| `/123-main-st/b/pano/1/2` | 404 in 1 ms, no `Processing by` line (routing miss — the probe path, not the pano action) | same | panos not exercised |

### Sanitizer population (dev restore, read-only, insgt-api `rails runner`)

Queries: `Listing.count` → 8,900; `Listing.where.not(description: [nil, ""]).count` → 8,790;
`Listing.where("description LIKE '%<%' OR description LIKE '%&%' OR description_es LIKE '%<%' OR description_es LIKE '%&%'").count`
→ 3,348; `Account.count` → 4,551; with description → 7; with markup → 1. Exported 3,349 rows (`id`, `description`,
`description_es`); 3,352 non-blank values run through `Rails::HTML4::SafeListSanitizer.new.sanitize` and
`Rails::HTML5::SafeListSanitizer.new.sanitize` on the 8.1.4 copy: **54 differ** — 30 where the only difference is
U+00A0 versus `&nbsp;`, 24 where the only difference is `\r\n` versus `\n` (HTML5 parsers normalise CRLF).
`simple_format` normalises `\r\n` before splitting paragraphs, so neither class changes the rendered page. The script
is in the appendix.

### Other facts

- `RubyVM::YJIT.enable; RubyVM::YJIT.enabled?` → `true` on the container's Ruby 3.4.12 (`mise exec -- ruby`).
- `gem list -e json` → `json (3.1.0, 2.18.0, default: 2.9.1)` — 3.1.0 was installed by the survey's `bundle install`.
- `LISTING_DOMAIN` and `INSIGHT_API_ENDPOINT` in the dev `.env`: `LISTING_DOMAIN has scheme: true`, `INSIGHT_API_ENDPOINT
  is localhost: true` (boolean probe; values not printed; the `.env` file itself is deny-listed for reads).
- `grep -rnE 'html_safe|raw\(|raw ' app --include='*.rb' --include='*.erb' | grep -F '%'` → empty (no `SafeBuffer#%`).
- `grep -rnE 'fresh_when|stale\?|etag|last_modified|expires_in|Rails\.cache|<% cache|cache do|cache\(' app lib config`
  → only `config/environments/*` `cache_store` lines and the GTM script URL.
- `grep -rnE 'mb_chars|ActiveSupport::Configurable|Benchmark\.ms|\.since\(' app lib config` → empty.
- `grep -rnE 'form_tag|form_with|form_for|button_to|token_tag|method_tag|hidden_field' app` → empty.
- Slugs with at least one listing on the dev restore: `nora-nido` (brokerage), `logan-banta` (none) — both crash.

### Plan review follow-ups (2026-10-31, same day)

- **Production-mode render against the manifest (P4b).** `render-production-tour.rb` (appendix) with
  `RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy INSIGHT_API_ENDPOINT=http://localhost:3000
  LISTING_DOMAIN=https://insightlistings.com` (dotenv-rails is a development/test gem, so production reads nothing from
  `.env`), request `https://www.insightlistings.com/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV` (https, because
  `force_ssl`), on `testcheck-802` (8.0.2, sprockets 4.2.2, manifest present) and `sprockets-bump` (8.1.4, sprockets
  4.4.1, manifest present): both `status=200 bytes=194295 tags=8 assets=4 missing=[]`; the four referenced files are
  `application-c69f77d9…css`, `tailwind-86379b23…css`, `fancybox-9107b68e…js`, `lozad-69f205f6…js` with identical
  digests on both; tag diff 0 lines; body diff 0 lines (csrf stripped).
- **Production reads** (a fetch tool that reports the HTTP status; not a curl — Monday's curls are the status-line
  record): `https://insightlistings.com/r/nora-nido` → **HTTP 500**; `https://insightlistings.com/r/logan-banta` →
  **HTTP 500**; `https://es.insightlistings.com/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV` → **HTTP 500**;
  `https://insightlistings.com/heartbeat` → `{"lub":"dub"}` (control, same minute).
- **`json` packaging:** rubygems lists json 3.1.0 for platforms `ruby` and `java` only — no precompiled Linux gem; the
  installed gem here is `json-3.1.0` built from source.
- **insgt-galleries** (`apps/insgt-galleries`, read-only): `Gemfile.lock:193` `rails (7.1.5.2)`, `:229` `sprockets
  (4.2.2)`, `:233` `sprockets-rails (3.5.2)`, `:282` `ruby 3.4.12p148`; `config/application.rb:24`
  `config.load_defaults 7.0`. The §3.2 trap applies to any bump of it that pulls `json` ≥ 3.

---

## Honeybadger (v3, 2026-10-31)

Tour branch `chore/honeybadger`: `7b8dd80` build: add the honeybadger gem; `93f7d30` chore: report production errors
to honeybadger. Off `main` `06ae511` (which carries Dan's account-page fixes `9dbf6d1`, `06ae511`).

| File | Line | What it is |
| :-- | :-- | :-- |
| `Gemfile` | 17–18 | comment, then `gem 'honeybadger', '~> 6.10'` (locked 6.10.1; brings `ostruct (0.6.3)`; `logger` was already locked) |
| `config/honeybadger.yml` | 1–18 | header comments: no key in the file, no `env`/`root`/`report_data`, `request.filter_keys` unset, log breadcrumbs left on |
| `config/honeybadger.yml` | 22–23 | `insights.enabled: false` |
| `config/honeybadger.yml` | 25–28 | `production.revision: "<%= ENV['RENDER_GIT_COMMIT'] %>"` — quoted (an all-digit SHA would load as an Integer; `0123456` as octal 42798); `""` when unset |
| `render.yaml` | 10–11 | `HONEYBADGER_API_KEY`, `sync: false` — documentation only: Render ignores new `sync: false` vars on an existing Blueprint (Blueprint spec, read 2026-10-31); the dashboard holds the value |
| `config/puma.rb` | 34 | `plugin :tmp_restart` only — no `plugin :honeybadger`, so no Puma stats |
| `lib/insight_photo.rb` | 54, 73, 89, 99 | `Net::HTTP` calls — would each be a `request.net_http` event with Insights on |
| `app/controllers/*` | — | no `rescue_from` (grep `rescue\|rescue_from` → only `render 'errors/not_found'` at `listings_controller.rb:11, 56`): every raise reaches Honeybadger |

Gem source, honeybadger 6.10.1 (rubygems 2026-10-30, sha256 `481a797b…` matches the fetched `.gem`; paths under
`lib/honeybadger/`). 6.10.0 → 6.10.1 changes only the bundled CA certificates (CHANGELOG).

| File | Line | What it is |
| :-- | :-- | :-- |
| `config/defaults.rb` | 9–33 | `IGNORE_DEFAULT`, 22 classes (`RoutingError`, `UnknownFormat`, `InvalidAuthenticityToken`, `BadRequest`, `ParameterMissing`, …). Not ignored: `ActionView::Template::Error`, `ActionView::MissingTemplate`, `UnsafeRedirectError` |
| `config/defaults.rb` | 56, 101–104 | `development_environments` `["development", "test", "cucumber"]` |
| `config/defaults.rb` | 261–284 | `request.filter_keys` `["password", "password_confirmation", "HTTP_AUTHORIZATION"]`; all four `request.disable_*` false |
| `config/defaults.rb` | 451–496, 529–537 | `rails.insights.*`, `net_http.insights.*` events on, metrics off; `breadcrumbs.logging.enabled` true; `insights.enabled` true |
| `config.rb` | 175–179, 294–296, 309–313 | `public?` (`report_data`, else not `dev?`); `insights_enabled?` = `public? && insights.enabled`; `load_plugin_insights?` |
| `config.rb` | 68, 354–357; `util/revision.rb` 5–43 | revision: `HEROKU_SLUG_COMMIT` → `REVISION` file → `git rev-parse HEAD` if `.git` exists; nothing reads `RENDER_GIT_COMMIT` |
| `config.rb` | 411–420 | `default_backend`: `Server` when `public?`, else `Null`; `HONEYBADGER_BACKEND=null` forces the stub |
| `config/yaml.rb` | 22, 33 | ERB-processed (`ERB.new(path.read).result`, then `YAML.unsafe_load`); the env section is merged over the top level |
| `init/rails.rb` | 15–28, 32–38 | middleware inserted whenever `exceptions.enabled` (any env): `ErrorNotifier` at 0, `UserInformer`/`UserFeedback` before it, `RequestId` after `ActionDispatch::RequestId`; `init!` passes `Rails.env`, `Rails.root` |
| `agent.rb` | 168–170, 182 | no key → `Unable to send error report: API key is missing` (ERROR), notice dropped; with a key → `Reporting error id=…` (INFO) |
| `notice.rb` | 200, 576–582 | sanitizer filters = `filter_keys` + the request's `action_dispatch.parameter_filter` (railties 8.0.2 `lib/rails/application.rb:319`, from `filter_parameter_logging.rb:6–8`) |
| `util/request_hash.rb` | 10–25, 64–70 | `cgi_data`: every `HTTP_*` header plus the CGI whitelist (`REMOTE_ADDR` …) — client IPs and User-Agent are sent |
| `util/request_payload.rb` | 23–38 | sanitizes params, session, `cgi_data`, the URL query string and cookies by name; URL paths are sent as is |
| `backend/null.rb` | 20–22 | `notify` returns a `StubbedResponse`; no network |

Verification on the branch (dev container, insgt-api up on 3000):

- P1 **2** (unchanged); zeitwerk "All is good!"; P3 three steps exit 0, `git status` clean; routes identical (15);
  production middleware 24 → 28 lines, the four Honeybadger entries only; P7 the four files.
- P5 (test env, `render-pages.rb`): branded 205,673 bytes, unbranded 202,944, `/heartbeat` 13, `/404` 4,836, `/500`
  7,918, `/` 404 1,790, `/r/colleen-crane` 200 7,892, `/s/` and `/su/` 301 to `localhost:3002` — bodies and headers
  (less `x-request-id`, `x-runtime`) identical to `main`.
- No key (`env -u HONEYBADGER_API_KEY`, production): `api_key=nil`, `public=true`, `backend=Server`, `insights=false`,
  `revision=""`, heartbeat 200; `https://es.insightlistings.com/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV` → 500,
  body == `public/500.html`, log `** [Honeybadger] Unable to send error report: API key is missing.`
- Dummy key (`HONEYBADGER_API_KEY=dummy-not-a-key HONEYBADGER_BACKEND=null RENDER_GIT_COMMIT=0123456`): the key
  printed back, `backend=Null`, `revision="0123456"` (String), the same 500 → `Reporting error id=…`, delivery stubbed.
- Development and test: `public=false`, `backend=Null`, `report_data=nil` — the gem default, not restated.
- `git grep -nE 'api_key|HONEYBADGER_API_KEY'` → `render.yaml:10` only. With `api_key: hbp_fake123` added on an rsync
  copy (no `.env`), the grep shows the line.
- 8.1.4 (rsync copy, `--update rails sprockets --conservative`): honeybadger and ostruct unchanged; boots; same four
  middleware entries. See design doc §3.1 v3 for the `action_text-trix` correction.

**Bundler 2.6.9 trap.** Adding a new gem to a lock that lists `ruby` beside specific platforms drops `ruby` from
`PLATFORMS` and the generic `nokogiri (1.18.8)` / `mini_portile2 (2.8.9)`. On a dependency change,
`remove_invalid_platforms!` (`bundler/definition.rb:1168–1180`) skips every platform but `ruby` and checks it against
the *old* lock, which lacks the new gem (`incomplete_specs_for_platform` → `["honeybadger-"]`). `bundle _2.6.9_ lock
--add-platform ruby` restores both; the lock diff is then the new gem alone. `bundle exec` on a copy re-resolves and
rewrites that copy's lock — diagnose with plain `ruby`, not `bundle exec`.

---

## Appendix — verification scripts

Run each with `mise exec -- bundle _2.6.9_ exec rails runner [-e test] <file>` from the repo (or a copy with
`BUNDLE_GEMFILE` set). They read ENV and write only where `OUTDIR`/`OUT` point.

### probe.rb (P4)

```ruby
require "rack/mock"
configuration = Rails.application.config
puts "rails=#{Rails.version} defaults=#{configuration.loaded_config_version.inspect}"
puts "to_time_preserves_timezone=#{ActiveSupport.to_time_preserves_timezone.inspect}"
puts "Regexp.timeout=#{Regexp.timeout.inspect}"
puts "yjit_config=#{configuration.yjit.inspect} yjit_enabled=#{defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : :undefined}"
puts "default_headers=#{configuration.action_dispatch.default_headers.inspect}"
puts "sanitizer_vendor=#{ActionView::Base.sanitizer_vendor.inspect}"
puts "strict_freshness=#{configuration.action_dispatch.strict_freshness.inspect}"
puts "escape_json=#{configuration.action_controller.respond_to?(:escape_json_responses) ? configuration.action_controller.escape_json_responses.inspect : :n_a}"
puts "path_relative_redirect=#{configuration.action_controller.respond_to?(:action_on_path_relative_redirect) ? configuration.action_controller.action_on_path_relative_redirect.inspect : :n_a}"
puts "add_autoload_paths_to_load_path=#{configuration.add_autoload_paths_to_load_path.inspect}"
puts "cache_store=#{configuration.cache_store.inspect} session_store=#{configuration.session_store.inspect}"
puts "message_serializer=#{configuration.active_support.message_serializer.inspect} cookies_serializer=#{configuration.action_dispatch.cookies_serializer.inspect}"
Rails.application.eager_load!
status, _headers, body = Rails.application.call(Rack::MockRequest.env_for("https://www.insightlistings.com/heartbeat"))
body.close if body.respond_to?(:close)
puts "boot ok #{Rails.version} sprockets=#{Sprockets::VERSION} json=#{JSON::VERSION} heartbeat=#{status}"
```

Production form: `RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy … rails runner probe.rb`, **after** P3 so the
manifest exists.

### render-pages.rb (P5)

```ruby
require "rack/mock"
paths = ENV.fetch("PATHS").split(",")            # e.g. "/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV,/heartbeat,/404,/500,/"
host = ENV.fetch("HOST", "www.insightlistings.com") # "localhost" for the /s/ redirects in development
output_directory = ENV.fetch("OUTDIR")
paths.each_with_index do |path, index|
  begin
    status, headers, body = Rails.application.call(Rack::MockRequest.env_for(path, "HTTP_HOST" => host))
    content = "".b
    body.each { |chunk| content << chunk.b }
    body.close if body.respond_to?(:close)
    File.binwrite(File.join(output_directory, "page-#{index}.html"), content)
    File.write(File.join(output_directory, "page-#{index}.headers"), headers.sort.map { |key, value| "#{key}: #{value}" }.join("\n"))
    puts "#{path} status=#{status} bytes=#{content.bytesize} location=#{headers['location'].inspect}"
  rescue => error
    puts "#{path} RAISED #{error.class}: #{error.message.lines.first.to_s.strip[0, 120]}"
  end
end
```

Compare: `diff <(sed -E 's/name="csrf-token" content="[^"]*"/X/' before/page-0.html) <(… after/page-0.html) | wc -l`
→ `0`; `diff before/page-0.headers after/page-0.headers` → empty (slice 1) or `x-download-options` only (slice 2).

### render-production-tour.rb (P4b)

```ruby
require "rack/mock"
path = ENV.fetch("TOUR_PATH")                      # e.g. "/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV"
output = ENV.fetch("OUT")                           # e.g. "<capture dir>/prod-tour.html"
status, _headers, body = Rails.application.call(Rack::MockRequest.env_for("https://www.insightlistings.com#{path}"))
content = +""
body.each { |chunk| content << chunk.b }
body.close if body.respond_to?(:close)
File.binwrite(output, content)
tags = content.scan(/<(?:link|script)\b[^>]*>/).sort
assets = tags.flat_map { |tag| tag.scan(/(?:href|src)="(\/assets\/[^"]+)"/).flatten }.uniq.sort
missing = assets.reject { |asset| File.exist?(Rails.root.join("public", asset.sub(%r{\A/}, ""))) }
puts "status=#{status} bytes=#{content.bytesize} sprockets=#{Sprockets::VERSION} tags=#{tags.size} assets=#{assets.size} missing=#{missing.inspect}"
assets.each { |asset| puts "  #{asset}" }
File.write(output.sub(/\.html\z/, ".tags"), tags.join("\n"))
```

Run after P3 (the manifest must exist) with `RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy
INSIGHT_API_ENDPOINT=http://localhost:3000 LISTING_DOMAIN=https://insightlistings.com`. Compare the `.tags` files with
the digests stripped: `diff <(sed -E 's/-[0-9a-f]{64}\././g' before.tags) <(sed -E 's/-[0-9a-f]{64}\././g' after.tags)`
→ empty; `missing=[]` on the branch.

### sanitizer-compare.rb (slice 2, row 3)

Export from insgt-api (`OUT=<file> rails runner`):

```ruby
html_where = "description LIKE '%<%' OR description LIKE '%&%' OR description_es LIKE '%<%' OR description_es LIKE '%&%'"
rows = [Listing, Account].flat_map do |model|
  model.where(html_where).pluck(:id, :description, :description_es).map do |id, description, description_es|
    { model: model.name, id: id, description: description, description_es: description_es }
  end
end
File.write(ENV.fetch("OUT"), JSON.generate(rows))
```

Compare in the tour (`IN=<file> rails runner -e test`):

```ruby
rows = JSON.parse(File.read(ENV.fetch("IN")))
html4 = Rails::HTML4::SafeListSanitizer.new
html5 = Rails::HTML5::SafeListSanitizer.new
categories = Hash.new(0)
checked = 0
rows.each do |row|
  %w[description description_es].each do |key|
    text = row[key]
    next if text.blank?
    checked += 1
    old_output = html4.sanitize(text)
    new_output = html5.sanitize(text)
    next if old_output == new_output
    categories[if old_output.gsub("&nbsp;", " ") == new_output.gsub("&nbsp;", " ") then "nbsp-serialization-only"
               elsif old_output.gsub(/\s+/, " ") == new_output.gsub(/\s+/, " ") then "whitespace-only"
               else "text-or-tags-differ" end] += 1
  end
end
puts "CHECKED=#{checked} CATEGORIES=#{categories.inspect}"   # 2026-10-31: CHECKED=3352 {"nbsp-serialization-only"=>30, "whitespace-only"=>24}
```
