# Rails Upgrade — insgt-virtual-tour 8.0.2 → 8.1.4

**Repo:** `insgt-virtual-tour` · **Platform:** Render.com web service `insgt-virtual-tour`, auto-deploy on push to `main`
**Status:** v5 — survey done 2026-10-31; the plan review of the same day settled the seven decisions (§7) and added
two checks to slice 1 (§4.0 P4b, §3.1 platforms); OD7 reversed the same day, Honeybadger live by 2026-11-01 (§1.1);
the §3.4 account-page, footer and redirect failures fixed on tour `main` (§3.4). **Slice 1 implemented 2026-11-02** on
tour branch `chore/rails-upgrade-slice-1` (§4.2 "Implementation record"), not pushed; slices 0 and 2 not started
**Version:** 5 · **Last updated:** 2026-11-02
**Supersedes:** v4 (2026-11-01). See §9.
**Companion file:** `rails-upgrade-virtual-tour-codebase-notes.md` — the `file:line` map, the survey record with every
command and its output, and the three verification scripts. Every repo claim below is sourced there.
**Pattern:** `rails-upgrade.md` (insgt-api 7.2.3 → 8.1.4). This document reuses its vocabulary — P-checks before the
push, S-checks after it, OD numbers for decisions, `slice-implementation` gates — and departs from it where this app
differs: no database, no test suite, one minor version to cross. (v1–v2 also said "no error tracker"; v3 adds
Honeybadger ahead of the slices, OD7.)

**How to read this document.** Facts carry their source (a `file:line`, a lockfile line, a gem source line, a dated
page, or a command in the notes' survey record). Assumptions and estimates are labelled. `UNVERIFIED` marks a claim no
source settled. Decisions are recorded in §7 with the date they were settled and the v1 recommendation beside them; slice prompts
are written from this version.

---

## 0. Purpose, non-goals, vocabulary

**The problem.** The tour app runs Rails 8.0.2, a series whose security support ends on **Sat 2026-11-07** (§1.3), on
a lockfile that already misses two 8.0 security releases (§1.4). It also still runs the Rails **7.0** framework
defaults (`config/application.rb:24`), untouched since the first commit in 2022, through two major upgrades. The
beneficiary is the business: these are the public MLS-facing pages, and an unpatched framework behind them is the
exposure; nothing changes for an agent or a buyer when the upgrade lands.

**Non-goals.** Tailwind 4 (`tailwindcss-rails` 3.3 stays), Propshaft (sprockets stays), Puma 7/8, the `webdrivers`
removal, any gem bump beyond the two §3 names, a Ruby change, any change to Honeybadger (OD7 — its own branch), fixing the pre-existing failures the
survey found (§3.4 — own branches), insgt-galleries (same shape, Rails 7.1.5.2 — OD6).

**Axes.** Two, and they move separately: (1) the Rails *version* (8.0.2 → 8.1.4, with the one gem it drags along),
and (2) the *framework defaults* (`load_defaults 7.0` → `8.1`). The insgt-api document kept these apart as slices 1–3
versus 5; this document does the same as slices 1 and 2.

**Vocabulary.** *Tour page* — `ListingsController#show`, `/<address>/b/<token>` (branded) or `/ub/` (unbranded).
*Account page* — `ListingsController#account`, `/r/<slug>`. *Short URLs* — `/s/`, `/su/`, `/qb/`, `/qu/`, which 301 to
the canonical tour URL the API supplies. *The render diff* — the P5 check: the same pages fetched through the Rack
stack against the local API on both Rails versions and compared byte for byte. *Shim* — a
`config/initializers/new_framework_defaults_X_Y.rb` file.

**Schema changes:** none. The app has no database (`CLAUDE.md`, `config/application.rb:5–13`).

---

## 1. Target and path

### 1.1 Where the app is

| Fact | Value | Source |
| :-- | :-- | :-- |
| Rails | **8.0.2** | `Gemfile:7` `'~> 8.0.2'`; `Gemfile.lock:199` |
| Framework defaults | `config.load_defaults 7.0` | `config/application.rb:24`; unchanged since `6f53980` (2022-07-18, initial commit) through the 7.0.3 → 8.0.2 bump (`89ca86e`/`1ed6f91`, 2025-06-02), which added `new_framework_defaults_8_0.rb` (all three lines commented) and nothing else |
| Frameworks loaded | Active Model, Action Controller, Action View only | `config/application.rb:5, 9, 13`; Active Record, Active Job, Active Storage, Action Mailer, Action Cable, `rails/test_unit` all commented out |
| Ruby / Bundler | 3.4.12 / 2.6.9 | `Gemfile:4`, `.ruby-version`, `.tool-versions`, `Gemfile.lock:316, 319` |
| `json` | 2.9.1, Ruby's default gem — **not in the lock** | `bundle exec ruby -e 'require "json"; puts JSON::VERSION'` → `2.9.1`; `gem list -e json` → `default: 2.9.1` |
| Assets | sprockets 4.2.2 via sprockets-rails 3.5.2; Tailwind 3 via tailwindcss-rails 3.3.2 | `Gemfile.lock:246, 251`; `app/assets/config/manifest.js` |
| Deploy | Render, `bin/render-build.sh` (`bundle lock --add-platform x86_64-linux`, `bundle install`, Tailwind 3.3.4 binary download, `tailwindcss:build`, `assets:precompile`, `assets:clean`), start `bundle exec puma -C config/puma.rb` | `render.yaml:3–6`; `bin/render-build.sh:6, 15, 21–23` (`set -o errexit`) |
| Deploy branch | `main` == `origin/main` at `eee78cf` (2026-10-29, "Ruby 3.4.12"); nothing unpushed. **v5:** `fc42d7a` (2026-11-01), which adds `b0ba43f` (merges `fix/cross-host-redirects`), `5e1d381` (whitespace in listing tokens) and `fc42d7a` (every request rendered as HTML) on top of `ad04756`; slice 1 branches from it | `git rev-list --left-right --count origin/main...main` → `0 0`; v5: `main` == `origin/main` by the last fetch |
| Test suite | Minitest scaffolding, **0 tests**, and the scaffolding cannot run one: `test/test_helper.rb:10` `fixtures :all` has no Active Record to come from | a one-file integration test fails to load with `NoMethodError: undefined method 'fixtures' for class ActiveSupport::TestCase` on 8.0.2 and 8.1.4 (notes, survey record) |
| Error tracking | **v3:** honeybadger 6.10.1 (`'~> 6.10'`), errors only, production only; a project of its own (not the api's), plus a Honeybadger uptime check on `/heartbeat`. Branch `chore/honeybadger` (`7b8dd80`, `93f7d30`), deployed on its own ahead of slice 1 (OD7). **v4: live** — merged into tour `main` at `ad04756`; the first production notice (`UnsafeRedirectError`, the `es.` tour, `listings_controller.rb:43`) arrived 2026-11-01 11:31 −05:00 from honeybadger-ruby 6.10.1. The key comes only from `HONEYBADGER_API_KEY` in the Render environment. Before v3: none | `Gemfile:17–18`; `config/honeybadger.yml`; `render.yaml:10–11`; notes, "Honeybadger (v3)" |
| Deprecation baseline | **2** `DEPRECATION WARNING: to_time …` lines at every test-environment boot; silenced in production | `config/environments/production.rb:45` `report_deprecations = false`; the 7.0 defaults chain leaves `to_time_preserves_timezone` at `:offset`, which 8.0 warns about |
| Autoloading | `bin/rails zeitwerk:check` → "All is good!" | 2026-10-31, both versions |

### 1.2 The path

| Stop | Version | Released | What it is | Source |
| :-- | :-- | :-- | :-- | :-- |
| Slice 1 | **8.1.4** | 2026-09-24 | newest Rails release of any series; one minor above 8.0 — the guide's one-minor-at-a-time rule is met in a single hop | rubygems.org/gems/rails/versions (read 2026-10-31) |
| Slice 2 | — | — | `config.load_defaults 8.1`, both shims deleted | §4.3 |

Rails **8.2 does not exist** as a release (rubygems lists 8.1.4 first, no prerelease). Rails 8.1 requires Ruby
≥ 3.2.0 (upgrading guide, "Ruby versions"); 3.4.12 satisfies it. **The Ruby version does not change in any slice.**

An 8.0.5.1 waypoint was considered and rejected: the two 8.0 security releases fix Active Storage (not loaded) and
`SafeBuffer#%` (not used, §1.4), the series dies in a week, and 8.0 → 8.1 is one minor.

### 1.3 Support dates

Verbatim from rubyonrails.org/maintenance (read 2026-10-31):

| Series | Bug fixes | Security fixes |
| :-- | :-- | :-- |
| 8.1.x | "Supported until October 10, 2026" | "Supported until October 10, 2027" |
| 8.0.x | "Supported until May 7, 2026" | "Supported until November 7, 2026" |

Implications:
- Slice 1 should be live before **Sat 2026-11-07**. The deadline is real but soft (plan review, 2026-10-31): on 11-08
  nothing new is exposed — the two 8.0 security releases the lock already misses do not reach this app (§1.4) — the
  risk is the *next* CVE, for which no 8.0 patch will come. A good deploy morning is worth more than the date (§6).
- On 8.1.4 the app is on the only series with security support after that date. 8.1.x is already security-only, so
  later 8.1.x bumps are patch releases.
- **Forward anchor:** 8.1.x security support ends **2027-10-10**. Rails 8.2 is unreleased; the next upgrade must be
  planned by mid-2027, and this document is its starting point.

### 1.4 What 8.0.2 is missing today

| Release | Date | Content | Reaches this app? |
| :-- | :-- | :-- | :-- |
| 8.0.3, 8.0.4 | 2025-09-22, 2025-10-28 | bug fixes | — |
| **8.0.4.1** | 2026-03-23 | CVE-2026-33195, -33202, -33174, -33173 (Active Storage disk service, proxy, direct uploads); **CVE-2026-33170** `SafeBuffer#%` loses the html-unsafe flag (Action View) | Active Storage is not loaded (`config/application.rb:8`). `SafeBuffer#%`: no `%` formatting on a safe buffer anywhere in `app/` or `lib/` (grep in the notes, empty) — **not exploitable as far as the grep reaches** |
| 8.0.5 | 2026-03-24 | bug fixes | — |
| **8.0.5.1** | 2026-07-29 | CVE-2026-66066 (Active Storage variants) | engine not loaded |

Sources: rubygems dates; the CVE descriptions as indexed on 2026-10-31 (NVD/Tenable via search — the Rails blog post
itself was not fetched; UNVERIFIED beyond those summaries). The point stands without them: §1.3 ends the series.

---

## 2. Sequencing

1. **Deploy = merge the slice branch into `main` and `git push origin main` from the Mac** (Dan's merge; nothing is
   pushed from a session). Render builds and swaps the service. **Rollback = Render dashboard → Events → previous
   successful deploy → "Rollback to this deploy"** (prior image, no rebuild). No database, no migration, no data to
   undo. Same as the Ruby 3.4.12 bump of 2026-10-29 (`ruby-version-bump` skill, Render handoff).
2. **Deploy mornings:** Monday–Wednesday, 09:00–11:30 Pacific, as `rails-upgrade.md` §2.4 — not because this app
   has delivery windows, but so a regression is seen in working hours with Dan at the dashboard. Not on the same
   morning as an insgt-api slice (§6): two services changing at once muddies the API-vs-tour attribution when the tour
   404s ("if the API is down, everything 404s", `CLAUDE.md`).
3. **Constants across every slice:** Ruby 3.4.12, Tailwind 3 and the 3.3.4 binary, sprockets (bumped once, §3.2, then
   constant), Puma 6, `load_defaults 7.0` until slice 2, and **no gem other than `rails` and `sprockets` moves**. The
   resolver command is `bundle lock --update rails sprockets --conservative`; a plain `--update rails` moved forty-odd
   transitive gems (rack 3.2.8, nokogiri 1.19.4, minitest 6.0.6, rails-html-sanitizer 1.7.1 …) and is rejected as
   scope (notes, survey record, "non-conservative lock").
4. **Independent of the insgt-api upgrade.** Different repo, different host, and the tour reads one JSON contract
   over HTTP (`lib/insight_photo.rb:54, 73, 89`) that neither upgrade changes. The two calendars interleave (§6) but
   nothing in either gates the other.
5. **Throwaway runs happen on rsync copies in the session scratchpad**, never on a branch in the real tree (memory
   `throwaway-experiments-use-rsync-copies`); the survey's copies are listed in the notes.
6. **The documents live in the platform repo** (`insgt-platform/docs/architecture/`), on a branch
   `docs/rails-upgrade-virtual-tour` cut from `main`, merged by Dan before slice 1 starts so the slice session reads
   the approved contract at `/workspace/docs/architecture/`. The app repo never carries them.

---

## 3. Blockers and resolutions

### 3.1 Dependency audit

Every gem in `Gemfile.lock`, with its Rails constraint, against 8.1.4. "OK" means the locked version resolves without
a bump. Verified by the resolver on 2026-10-31 (`bundle lock --update rails --conservative` on a scratchpad copy —
resolved first try, no `minitest` argument needed).

| Gem (locked) | Rails constraint | 8.1.4 | Resolution |
| :-- | :-- | :-- | :-- |
| sprockets-rails 3.5.2 | actionpack, activesupport `>= 6.1` | OK | none — but see **sprockets 4.2.2** below |
| **sprockets 4.2.2** | rack `>= 2.2.4, < 4` | resolves, **breaks at runtime** | **bump to 4.4.1** (§3.2) — the one non-rails gem this upgrade moves |
| tailwindcss-rails 3.3.2, tailwindcss-ruby 3.4.17 | railties `>= 7.0.0` | OK | none; Tailwind 4 is §8 |
| font-awesome-rails 4.7.0.9 | railties `>= 3.2, < 9.0` | OK | none (`fa_icon` at nine view sites) |
| web-console 4.2.1, dotenv-rails 3.1.8 | railties `>= 6.0` / `>= 6.1` | OK | none (development only) |
| bootsnap 1.18.6, debug 1.10.0, puma 6.6.0, aws-sdk-s3 1.189.0, tzinfo-data | none | OK | none |
| capybara 3.40.0, selenium-webdriver 4.10.0, webdrivers 5.3.1 | none; webdrivers pins selenium `< 4.11` | OK | none now; webdrivers is abandoned (§8) — test group only |
| minitest 5.25.5 | activesupport `>= 5.1` (8.1.4 drops the `< 6` cap) | OK | stays 5.25.5 under `--conservative` |
| `json` | **new**: activesupport 8.1.4 depends on `json` (unconstrained); activesupport 8.0.2 did not | **lock gains `json (3.1.0)`** | the trigger for §3.2 |
| benchmark 0.4.1 | activesupport 8.0.2 `>= 0.3`; 8.1.4 drops it | leaves the lock | expected |
| tsort | railties 8.1.4 adds `tsort >= 0.2` | `tsort (0.2.0)` enters | expected |

**Expected lock diff for slice 1** (byte-identical to the survey's `sprockets-bump` copy): the 13 rails-family gems
and their `(= 8.1.4)` pins; under `activesupport`, `benchmark (>= 0.3)` → `json`; `benchmark (0.4.1)` removed;
`json (3.1.0)` and `tsort (0.2.0)` added; under `railties`, `tsort (>= 0.2)` added; `sprockets (4.2.2)` →
`sprockets (4.4.1)` with `concurrent-ruby (~> 1.0)` → `(~> 1.1)` (1.3.5 is locked and satisfies it);
`DEPENDENCIES` `rails (~> 8.0.2)` → `(~> 8.1.4)`. Bundler 2.6.9 writes no `CHECKSUMS` block. Anything else that moves
is explained in the slice plan or reverted.

**v3 correction:** the diff also adds **`action_text-trix (2.1.19)`**, because `actiontext (8.1.4)` depends on
`action_text-trix (~> 2.1.15)`. Every 8.1.4 lock carries it; the survey's prose for the conservative recipe left it
out. Checked on the Honeybadger branch's lock (2026-10-31, rsync copy, `--update rails sprockets --conservative`): the
diff names exactly the 13 rails gems, `action_text-trix`, `benchmark`, `concurrent-ruby`, `json`, `sprockets` and
`tsort`. `honeybadger (6.10.1)` and `ostruct (0.6.3)` are unchanged, and `ruby` stays in `PLATFORMS`. The copy boots on
8.1.4 with the same four Honeybadger middleware entries. Bundler trap (notes, "Honeybadger (v3)"): adding a *new* gem
with Bundler 2.6.9 drops the `ruby` platform and the generic `nokogiri`; `bundle _2.6.9_ lock --add-platform ruby`
restores them. A rails requirement change does not trigger it.

**Platforms (plan review point 2).** `Gemfile.lock` `PLATFORMS` already lists `x86_64-linux`, `x86_64-linux-gnu` and
`x86_64-linux-musl` (with the aarch64, arm and darwin variants), so `bin/render-build.sh:6` is a no-op and Render
installs the lock as tested — the expected lock diff above is the whole truth. **`json` 3.1.0 ships no precompiled
platform gem** (rubygems lists `ruby` and `java` only): its C extension compiles on Render at `bundle install`, as
`bigdecimal` already does, and the S1 build log is the proof (R1).

### 3.2 The blocker: `json` 3 versus sprockets 4.2.2

**Facts.**
- json **3.0.0** (2026-09-07; rc1 2026-08-11): "Removed the insecure `create_additions` option" and "All unknown
  options will now cause an `ArgumentError` rather than to be ignored" (ruby/json `CHANGES.md`).
- sprockets 4.2.2 passes it: `lib/sprockets/manifest.rb:318` `JSON.parse(obj, create_additions: false)` (also
  `npm.rb:40`, `bower.rb:49`). The manifest is parsed whenever `public/assets/.sprockets-manifest-*.json` exists —
  at `assets:clean`, and at **every production boot after a precompile**.
- activesupport 8.1.4 adds `json` as a dependency; the resolver takes the newest, **3.1.0**. Today the app runs
  Ruby's default json 2.9.1 and the lock has no `json` line (§1.1).
- sprockets **4.3.0** (2026-08-12): "Fixed compatibility with `json` 3+" (rails/sprockets `CHANGELOG.md`); 4.4.1
  (2026-08-25) is the newest; no version newer than 4.4.1 is listed (rubygems, 2026-10-31).

**Observed on 2026-10-31 (notes, survey record).** On the 8.1.4 copy with sprockets 4.2.2: `tailwindcss:build` and
`assets:precompile` exit 0, then `assets:clean` exits 1 with `ArgumentError: unknown keyword: create_additions
(json-3.1.0/lib/json/common.rb:297)`; a production boot with the manifest present fails with the same error, as does
a `/heartbeat` request through the production stack — and so does a **test-environment** boot on the same copy: once
`public/assets/` holds a manifest, `Sprockets::Railtie.build_manifest` (sprockets-rails 3.5.2 `railtie.rb:216`, run
from the finisher) parses it in every environment. On the 8.0.2 copy all three tasks and the boot pass. **Every
earlier probe on 8.1.4 had passed** (test and production eager load, routes, middleware, nine rendered pages) because
no manifest existed yet — which is why §4.0 orders P3 (the build) before P4 (the production boot).

**What it would have meant on Render.** `bin/render-build.sh:23` runs `assets:clean` under `set -o errexit`, so the
build fails and the live service is untouched; had the script not run `assets:clean`, the build would have succeeded
and **the new instance would have crashed at boot**.

**Resolution (decided by evidence, recorded here; no open question):** `bundle lock --update rails sprockets
--conservative`. Verified on the `sprockets-bump` copy: sprockets 4.4.1; the three build tasks exit 0; production boot
with the manifest prints `boot ok 8.1.4 sprockets=4.4.1 json=3.1.0`; `/heartbeat` through the production stack 200;
test-environment eager load 0 deprecation lines. Alternatives rejected: pinning `json < 3` in the Gemfile (pins
against Rails's own dependency and against the line the json gem now maintains); Propshaft (a real migration, §8).

### 3.3 What 8.1.4 changes for this codebase

From the 8.1.x CHANGELOG sections of actionpack, actionview, activesupport and railties (v8.1.4 tags, read
2026-10-31) and the 8.1 release notes. Everything that touches a file in this app; the rest is silent here.

| Change | Where it lands here | Effect |
| :-- | :-- | :-- |
| AS 8.1.0 "Remove deprecated support for `to_time` to preserve the system local time"; "Deprecate `config.active_support.to_time_preserves_timezone`" | nothing sets it; the only time call is `Time.now.year` (`listings/_footer.html.erb:13, 16`) | the two boot deprecations disappear (0 on 8.1.4). The `to_time` block in `new_framework_defaults_8_0.rb:12–18` must never be uncommented on 8.1 — slice 2 deletes the file |
| AP 8.1.0 `raise_on_open_redirects` → `action_on_open_redirect` | `load_defaults 7.0` sets `action_on_open_redirect = :raise` on 8.1.4 (railties `configuration.rb:266`, the 7.0 block); the actionpack railtie deprecates the old key only when an app sets it (`railtie.rb:114–124`) — this app never did | behaviour identical: the probe shows `raise_on_open_redirects=true` on 8.0.2, `nil` on 8.1.4, and the same cross-host redirect raises on both (`UnsafeRedirectError` → its new subclass `OpenRedirectError`). §3.4 item 2 |
| AP 8.1.0 "The JSON renderer doesn't escape HTML entities …" | `heartbeat_controller.rb:3` `render json: { lub: 'dub' }` | only under `escape_json_responses = false` (slice 2); the body has no `<>&` — unchanged bytes either way |
| AP 8.1.0 "Raise `DoubleRenderError` if `head` is called after rendering" | `heartbeat_controller.rb:3` passes `head: :ok` as a *render option* (ignored), not a `head` call; no controller calls `head` | none |
| AP 8.1.0 removals: multiple paths per route, `;` query separator, leading-bracket params | `config/routes.rb` has one path per `get`/`match`; routes table identical on 8.1.4 (15 lines) | none |
| AP 8.1.0 "Add `action_dispatch.verbose_redirect_logs`" | the 8.1 `development.rb` template adds it | accepted in slice 1 (dev only) |
| AP 8.1.4 "Parse all three HTTP-date formats in `If-Modified-Since`"; AP 8.1.0 RFC 9111 request directives | `Rack::ConditionalGet`/`Rack::ETag` are in the stack; no `fresh_when`/`stale?` in `app/` | conditional GETs on the weak ETag keep working; no app code |
| AP 8.1.x `ActionDispatch::PermissionsPolicy::Middleware` no longer in the production stack | `config/initializers/permissions_policy.rb` is all comments | the only middleware difference between versions (23 → 22 lines; 28 → 27 with Honeybadger). No `permissions-policy` header is emitted on either version (heartbeat headers identical). **v5, verified in source:** railties 8.1.4 `default_middleware_stack.rb:86` inserts it only `if config.permissions_policy`; 8.0.2 inserts it unconditionally |
| AV 8.1.x — no `simple_format`, `sanitize`, `truncate`, `raw`, asset-helper or `csrf_meta_tags` entries | `_property.html.erb:2`, `_agent_details.html.erb:22`, `layouts/listings.html.erb:26`, `application_helper.rb:187` | none in slice 1; the sanitizer *vendor* changes in slice 2 (§4.3) |
| AV 8.1.2.1 "Fix possible XSS in DebugExceptions middleware" | DebugExceptions renders only for local requests; production `consider_all_requests_local = false` | closed by the bump regardless |
| AS 8.1.0 deprecations: `String#mb_chars`, `ActiveSupport::Configurable`, `Benchmark.ms` | none in `app/`, `lib/`, `config/` (grep empty) | none; a gem's use would show as a deprecation line — 0 seen on every exercised path |
| Railties 8.1.0 "Don't enable YJIT in development and test"; `bin/ci`; `rails/console/methods` and `bin/rake stats` removed | `app:update` offers `bin/ci`/`config/ci.rb` (rejected, §4.2); nothing uses the removed files | none |

### 3.4 Pre-existing failures the survey found (not regressions — identical on both versions)

Recorded so that nobody mistakes them for slice fallout, and so the S-checks avoid them. Each is a §8 item with a
one-line fix; **none is in scope for a slice** (OD5). Items 1 and 2 are **live production 500s as of 2026-10-31**
(read through a fetch tool, which reported the HTTP status; `/heartbeat` answered `{"lub":"dub"}` in the same minute
as the control). OD5 puts their fix branch in the same week as slice 1, on its own morning.

1. **The account page crashes for every account tried.** `ListingsController#account` never sets `@listing`
   (`listings_controller.rb:4` excludes it from `find_listing`), yet `components/_broker_logo.html.erb:1` reads
   `@listing[:showBrokerageLogo]` and `_team_logo.html.erb:1` reads `@listing[:showAgentTeamLogo]` → `NoMethodError`
   for any account with a brokerage or team (since `9cb56d2`, 2022-07-22); and `_agent_detail.html.erb:5` reads
   `account[:headshot][:s3Key]` → `NoMethodError` for any account without a headshot. `/r/colleen-crane`,
   `/r/nora-nido`, `/r/logan-banta` all raise `ActionView::Template::Error` on 8.0.2 and 8.1.4 (2026-10-31, dev
   restore). **Production: confirmed 2026-10-31** — `https://insightlistings.com/r/nora-nido` and `/r/logan-banta` both answer
   **HTTP 500**. Every agent's own listings page is down for any agent with a brokerage, a team, or no headshot, which
   the three samples suggest is every agent. Monday's `curl -sS -o /dev/null -w "%{http_code}\n"
   https://insightlistings.com/r/<slug>` from the Mac re-confirms it with a status line (§6).
   **v4: fixed** on tour `main` `ad04756` (pushed):
   - `9dbf6d1` (Dan) guards `_broker_logo.html.erb` (it renders when `@listing` is blank); `06ae511` (Dan) fixes the
     account thumbnails.
   - `79d5f11` reads `account.dig(:headshot, :s3Key)` at `_agent_detail.html.erb:5`. The account endpoint omits
     `headshot` when there is none (insgt-api `accounts_helper.rb:33–34`); `virtual.json` always sends one with a nil
     `s3Key` (`listing.rb:614–617`), so only `/r/` pages raised. Dev restore: 21 of 83 accounts with visible listings
     and a slug have no headshot.
   - `fc28ea9` reads `Array(@account[:organizations])` at `listings_controller.rb:22`. The endpoint also omits
     `organizations` when there are none (`accounts_helper.rb:166–167`) — a third crash the v1 survey missed; the tour
     pages already guard it (`lib/insight_photo.rb:108, 128`).
   - **Correction to v3:** `_team_logo.html.erb:1` never raised on the account page. Its only render site,
     `_agent_details.html.erb:14`, renders it only `if @listing && @listing[:showAgentTeamLogo]`. Unchanged.

   Request evidence (test env, dev API): `/r/gregory-butler` (no headshot) raised at `_agent_detail.html.erb:5` and
   `/r/deb-burton-bushell`, `/r/yager-realty-of-california` (no organizations) at `listings_controller.rb:22` before
   the fix; all three render 200 after, and `/r/greg-timms`, `/r/colleen-crane` and four tour pages are byte-identical.
   Production, 2026-11-01: `/r/gregory-butler` and `/r/deb-burton-bushell` render with the agent's name (fetch tool;
   it reported no status line, and `public/500.html` names no agent).
2. **The Spanish-subdomain redirect raises.** `listings_controller.rb:42` redirects to
   `ENV['LISTING_DOMAIN'] + request.original_fullpath` for a listing without `spanishListings`; from
   `es.insightlistings.com` that target is another host, and the 7.0 defaults raise on cross-host redirects →
   `UnsafeRedirectError` (8.0.2) / `OpenRedirectError` (8.1.4) → 500. Reproduced with `HTTP_HOST=es.insightlistings.com`
   on both versions. The same guard reaches `/s/`, `/su/`, `/qb/`, `/qu/` (`:9, :49`) whenever the canonical URL is a
   custom domain (`customDomainUrlBranded`) — UNVERIFIED, no custom-domain listing was tried. The short URLs for an
   ordinary listing 301 correctly on both versions when the request host matches the target host (dev:
   `http://localhost:3002/…`). **Production: confirmed 2026-10-31 for the Spanish shape** —
   `https://es.insightlistings.com/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV` answers **HTTP 500**. The
   custom-domain short-URL shape stays UNVERIFIED until Monday's curl.
   **v4: fixed on tour branch `fix/cross-host-redirects`** (`156b7d4`, off `main` `ad04756`; not merged):
   `allow_other_host: true` at `listings_controller.rb:9, 43, 50` (lines moved by `fc28ea9`). Honeybadger recorded the
   `es.` shape in production (2026-11-01 11:31 −05:00, `:43`). The short-URL mechanism is now reproduced: `/s/`,
   `/su/`, `/qb/`, `/qu/` requested on a host other than the canonical URL's raised `UnsafeRedirectError` at `:50` and
   `:9` on `ad04756`, and answer 301 to the canonical URL on the branch; a real custom-domain listing has still not
   been requested. On the branch the `es.` tour answers **302** → `https://insightlistings.com/…` in test and in
   production mode (`Completed 302 Found`, no notice). The targets come from `LISTING_DOMAIN` and the API, never the
   request; `original_fullpath` always starts with `/`, so only the path can vary.
   **v5: merged** into tour `main` at `b0ba43f`, on `origin/main` (`fc42d7a`). Whether Render has deployed it is not
   read from a session (UNVERIFIED). In slice 1's P5 the `es.` tour answers 302 and `/s/`, `/su/` on the `www` host
   301 to the canonical URL, on `main` and on the branch alike.
3. **`panos_controller.rb:19` renders `action: :error`**, and `app/views/panos/` holds only `show.html.erb` →
   `ActionView::MissingTemplate` → 500 whenever the API returns no pano. Read, not exercised (no pano order URL was
   requested).
4. **`test/test_helper.rb:10` `fixtures :all`** — the first test file ever added fails to load (§1.1).
5. `Procfile.dev:1` and `bin/dev:9` default to port 3000, which insgt-api owns; `CLAUDE.md` says 3002. Cosmetic.
6. **The `/404` and `/500` routes are shadowed.** `ActionDispatch::Static` answers those paths from `public/404.html`
   (4,836 bytes) and `public/500.html` (7,918 bytes) with status **200** before routing reaches
   `ErrorsController` (`config/routes.rb` `match "/404"`, `match "/500"`), wherever the public file server is on —
   test, and production on Render (`production.rb:19`). Identical on both versions; the branded `errors/*` templates
   render only through `listings_controller.rb:11, 56` (`:11, 57` from v4).
7. **v4: the tour footer raised for a listing whose agent has no MLS organization.** `display_mls_name`
   (`application_helper.rb:6`) read `listing[:account][:mls][:name]`, so the tour page raised at
   `_footer.html.erb:16` (dev: `/1120-hunter-san-diego-92123/b/4erZP12X`, branded and unbranded). Fixed by `23f1b0e`
   on `main` (`listing.dig(:account, :mls, :name).to_s`); production renders that page, 2026-11-01. For such a listing
   the IDX sentence now reads "…provided by . …" and "Compilation ©2026 ." — the wording for this case is undecided
   (§8 item 15). `_property_table.html.erb:59` already hid its MLS row. How many listings hit it is unknown.

---

## 4. Slices

Each slice is one `slice-implementation` session on a branch off `main`, ends with P1–P7 green, and deploys alone.
Gates: slice 0 and slice 1 "after plan; after verification"; slice 2 "all" (it changes behaviour).

### 4.0 Shared verification kit

There is no suite (§1.1), so the gate is a boot, a build, and a byte comparison of rendered pages. The scripts are in
the notes' appendix; `rails middleware` and `rails runner -e` quirks are noted there too.

**v5: run the checks on rsync copies, not in the real tree.** Each check runs on a scratchpad copy of the commit under
test, with `public/assets` and `tmp` excluded (`pchecks.sh` in the notes runs the whole set). The reason: in development
and test, sprockets-rails resolves asset paths from a `public/assets` manifest first (sprockets-rails 3.5.2
`railtie.rb:233`; neither environment overrides it). A P3 run in the real tree leaves one behind, so P5 would render
against a stale manifest and `bin/dev` would serve the stale build. One from 2026-10-31 21:26 was still in the tour
tree on 2026-11-02.

**Pre-deploy, on the slice branch (dev container; the API must be up on port 3000 for P5):**

| # | Command | Expected |
| :-- | :-- | :-- |
| P1 | `mise exec -- bundle _2.6.9_ exec rails runner -e test 'Rails.application.eager_load!; puts :ok' 2>&1 \| grep -c DEPRECATION` | `0` (baseline on 8.0.2: `2`) |
| P2 | `bin/rails zeitwerk:check` | "All is good!" |
| P3 | `RAILS_ENV=production SECRET_KEY_BASE=dummy bundle exec rake tailwindcss:build assets:precompile assets:clean` — the three steps of `bin/render-build.sh:21–23` | each exits 0 (**this is the check that caught §3.2**). Writes `public/assets/` and `tmp/cache/` (both gitignored); `git status` stays clean |
| P4 | after P3: `RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy bundle exec rails runner '<probe>'` (the probe script prints `Rails.version`, `loaded_config_version`, the effective flag values, then eager loads and calls `/heartbeat` through the Rack stack) | `boot ok`, `heartbeat=200`, the slice's expected values (§4.2, §4.3) |
| P4b | after P3, with the API up: `RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy INSIGHT_API_ENDPOINT=http://localhost:3000 LISTING_DOMAIN=https://insightlistings.com bundle exec rails runner render-production-tour.rb` — the branded tour rendered **in production mode against the compiled manifest** (plan review point 1: `/heartbeat` never touches `stylesheet_link_tag`, and P5 runs in development, where assets resolve without the manifest) | 200; every `/assets/…` the `<link>`/`<script>` tags reference exists in `public/assets/` (`missing=[]`); the tag set equals the pre-bump capture modulo digests. **Survey, 2026-10-31:** 8.0.2/sprockets 4.2.2 and 8.1.4/sprockets 4.4.1 both 194,295 bytes, the same four digests (`application`, `tailwind`, `fancybox`, `lozad`), eight tags, body diff 0 |
| P5 | the render script on the pre-bump tree and on the branch: branded tour, unbranded tour, `/heartbeat`, `/404` and `/500` (the static pages, 200 — §3.4 item 6), `/` (root 404), and `/s/<token>` with `HTTP_HOST=localhost`; `diff` each pair with the csrf token stripped | 0 diff lines for every page except where the slice names a change; `/s/` 301 with the same `Location`. Token on the dev restore: `1qY5VLqV` (`/30290-red-lure-pl-canyon-lake-92587/b/1qY5VLqV`, 205,673 bytes branded, 78 `carousel__slide`, title ends `MLS #OC26233239`, disclosure link present) — any listing `Listing.select_virtual(token)` answers works |
| P6 | `bin/rails routes` and `RAILS_ENV=production RENDER=1 SECRET_KEY_BASE=dummy bin/rails middleware` (no `-e` flag exists) against the pre-bump capture | routes identical (15 lines); middleware identical except the slice's named difference |
| P7 | `git diff main --stat` | only the files the slice names |

**Production checks, from the Mac, within 30 minutes of the push** (capture S4's answers on the live release *before*
the push so "unchanged" is provable). From the `ruby-version-bump` skill's Render handoff:

| # | Where | Expected |
| :-- | :-- | :-- |
| S1 | dashboard → service → Events → the build log | `Ruby version: ruby 3.4.12 …`; `assets:clean` runs without error; build succeeds |
| S2 | service Shell tab: `bundle exec rails runner 'puts Rails.version; puts Rails.application.config.loaded_config_version'` | the slice's version and defaults |
| S3 | status Live; Logs show one Puma boot, no repeated boots | — |
| S4 | `curl -sS https://insightlistings.com/heartbeat` → `{"lub":"dub"}`; a real branded tour URL: `<title>` ends `MLS #<number>`, `#carousel` holds the same N `carousel__slide` divs as before the push, the disclosure link present iff it was before; `curl -sI https://insightlistings.com/s/<token>` → `301` with the same `Location` | identical to the pre-push capture |
| S5 | Logs tab for ten minutes, then a Logs search for `Completed 5` over the first hour | no 5xx that was not there before the push (v4: the account page and the footer are fixed; v5: the `es.` redirect fix is on `main` `b0ba43f` — if the live release predates it, the `es.` 500s are pre-existing; capture before, and do not count what was already there) |
| S-DEP | Logs search for `DEPRECATION` over the first day (only meaningful after OD2) | none |
| SH (v3) | the tour's Honeybadger project → Errors, `environment:"production"` since the push, compared **by error** with the first day after the Honeybadger deploy (the baseline); and the `/heartbeat` uptime check | no new error. A new error whose backtrace touches what the slice changed is a finding; an old bug seen for the first time is recorded and fixed on its own branch. The uptime check stays green |

**v3, P6 baseline:** since the Honeybadger deploy, the production middleware list has **28** lines (24 before,
counting the `run` line). The additions are `Honeybadger::Rack::UserInformer`, `UserFeedback` and `ErrorNotifier`
first, and `Honeybadger::Rack::RequestId` right after `ActionDispatch::RequestId`. Slice 1 captures its "before" list
on that `main`. The P1 baseline is unchanged at **2**.

**Rollback:** Events → previous successful deploy → "Rollback to this deploy". Then check that the service's
**Auto-Deploy setting is still on** (plan review: a manual rollback may switch it off — UNVERIFIED; if it does, the next
`git push origin main` deploys nothing). Read the setting in the dashboard before the first push so the answer is known.

### 4.1 Slice 0 — a test harness (optional, OD3)

Not required by slices 1 and 2; recommended because it turns P5 from a hand-run script into `bin/rails test` for this
and every later bump (Tailwind 4, Puma, Ruby).

**Scope.** `test/test_helper.rb`: drop `fixtures :all` (`:10`) and `parallelize` (`:7` — nothing to parallelise);
integration tests for `/heartbeat` (`{"lub":"dub"}`), `/404` and `/500` (the static pages, 200 — §3.4 item 6), `/`
(404 with the "Real Estate Listings with Insight" page), and the branded and unbranded tour rendered from a recorded `virtual.json` payload with
`InsightPhoto.find_listing` stubbed (Minitest `stub`; the fixture is the dev restore's `1qY5VLqV` payload with the
agent's contact fields replaced); a contract test file `test/architecture/rails_upgrade_test.rb` for the invariants
the later slices pin (version floor, `loaded_config_version`, `Regexp.timeout`, sanitizer vendor). **Out of scope:**
the account page (crashes, §3.4), panos, system tests, Capybara/Selenium (left as is).

**Commit sketch.** 1. `test: make the test helper runnable without Active Record` [1]; 2. `test: cover the public
pages with integration tests` [2: the stubbing approach and why the payload is recorded].

**Effort (estimate):** 3 h. **Deploy:** none (tests only). **Timing (decided, OD3):** not on Monday — slice 1 owns
Monday; slice 0 lands in the Wed 11-04 – Fri 11-06 window and earns its keep in slice 2, whose contract test pins the
sanitizer vendor and `Regexp.timeout`. If it slips, slice 2 runs on the render script alone.

### 4.2 Slice 1 — 8.1.4 on the 7.0 defaults

**Scope.**
1. `Gemfile:7` → `gem 'rails', '~> 8.1.4'`; `mise exec -- bundle _2.6.9_ lock --update rails sprockets
   --conservative`; `bundle install`. Expected lock diff: §3.1. Order of commits: the sprockets bump **first**, on
   8.0.2 (P3 and P4 prove 4.4.1 works there before the Rails bump lands — UNVERIFIED as of the survey; the slice
   verifies it, and if 4.4.1 fails on 8.0.2 the two bumps become one commit with that fact in the body), then Rails.
2. `bin/rails app:update --force` on an rsync copy to capture the diff as plan evidence (the survey's run is in the
   notes), then applied selectively:

   | Generated file | Survey result (2026-10-31) | Decision | Why |
   | :-- | :-- | :-- | :-- |
   | `config/boot.rb`, `application.rb`, `environment.rb`, `environments/test.rb`, `initializers/{assets,filter_parameter_logging,inflections}.rb`, `bin/rails`, `bin/rake`, `bin/setup`, `public/robots.txt` | identical | — | nothing to apply |
   | `config/initializers/new_framework_defaults_8_1.rb` | created, six settings all commented (v5 correction; v1–v4 said seven) | **accept** as generated | the slice 2 shim |
   | `config/puma.rb` | one comment line (`auto` workers) | **accept** | comment-only |
   | `config/initializers/content_security_policy.rb` | comment block for `content_security_policy_nonce_auto` | **accept** | comment-only |
   | `config/environments/development.rb` | adds `config.action_dispatch.verbose_redirect_logs = true` | **accept** | dev only; 8.1.0 feature |
   | `config/environments/production.rb` | drops `public_file_server.enabled` (`:19`, the `RENDER` switch), comments out `assume_ssl` (`:26`) and `force_ssl` (`:29`), rewords one comment | **reject** | the post-update tree's production middleware loses `ActionDispatch::AssumeSSL` and `ActionDispatch::SSL` (verified by `rails middleware`) |
   | `bin/dev` | replaced by `exec "./bin/rails", "server", *ARGV` | **reject** | drops foreman and `Procfile.dev`'s `tailwindcss:watch`; `CLAUDE.md` documents `./bin/dev` as both processes |
   | `config/ci.rb`, `bin/ci` | created | **reject** | 8.1's local CI runner; its `bin/importmap audit` step names a gem this app lacks; no suite |
   | `public/{400,404,406-unsupported-browser,422,500}.html` | 36–44 diff lines each: `100dvh`, dark-mode colours, a straight apostrophe | **accept** (OD4) | the current files are the untouched stock 8.0 pages (`1ed6f91`); staying stock costs nothing; no icon references |
   | `public/icon.png`, `public/icon.svg` | created | **reject** | referenced by no layout or page; `favicon.ico` and `apple-touch-icon*.png` serve today |
   | `config/initializers/cors.rb` | created and removed in the same run | — | no file results |
   | `tmp/local_secret.txt` | written by the first 8.1 test boot | — | gitignored |

   A generated file not in this table is a STOP with the diff pasted.
3. **Production deprecation logging on** (OD2, decided yes): `config/environments/production.rb:45`
   `report_deprecations = false` → `true`, plus `config.active_support.deprecation = :log`. The api document routed
   production deprecations to Honeybadger; here the Render log stays the deprecation channel even after the v3
   Honeybadger deploy (OD7 is errors only), and S-DEP reads it. Zero deprecations were
   seen on every exercised path, so the expected volume is zero lines; the one thing it buys is the untested path
   (panos, custom domains, the Spanish locale).
4. `config.load_defaults` stays `7.0`. Both shims stay as generated (all commented).

**Out of scope.** Any shim line; `config.load_defaults`; any gem beyond the two named; the §3.4 fixes; `bin/dev`;
`Procfile.dev`; the error-page content.

**Prerequisites.** This document merged into the platform repo's `main` (§2.6); the Monday curls done (§6); the API
running on port 3000 for P4b and P5; `git -C apps/insgt-virtual-tour status` clean on `main` at `eee78cf` or a descendant.

**Gaps pinned.**
- *Does sprockets 4.4.1 work on 8.0.2 (for the two-commit order)?* Rule: P3 + P4 after commit 1; if red, one commit.
- *The `app:update` diff shape.* Rule: the table is the contract.

**Spec plan.** None unless slice 0 shipped; then the contract test's version floor moves to `8.1.4` and
`loaded_config_version` stays pinned at `7.0`. Otherwise P1–P7 with the pre-bump captures.

**Commit sketch.**
1. `build: upgrade sprockets to 4.4.1 for json 3` [2: json 3 removed `create_additions`; the manifest parse fails at
   boot once Rails 8.1 pulls json 3 in]
2. `build: upgrade rails to 8.1.4` [2: the lock movement by name; "last 8.0 security support ends 2026-11-07"]
3. `chore: apply the rails 8.1 app:update files` [2: what was rejected and why — production.rb, bin/dev, ci]
4. `chore: log deprecations in production` [2] (OD2)

**Post-deploy verification.** P1–P7 (P4b included) with `8.1.4` and `loaded_config_version` `7.0`; S1–S5; S-DEP.
Expected P6 difference: `ActionDispatch::PermissionsPolicy::Middleware` absent. Expected P4b difference: none (the
asset digests did not change in the survey; if they do on the branch, every referenced file must still exist).
Expected P5 difference (v5 correction; v1–v4 said none): the `/404` and `/500` bodies, which are the regenerated
`public/404.html` and `public/500.html` (OD4; §3.4 item 6); every other page byte-identical.

**Rollback.** Render rollback to the previous deploy. Nothing else to undo.

**Gates.** After plan; after verification. **Effort (estimate):** 3 h plus the deploy morning.
**Deadline (fact):** live before Sat 2026-11-07.

**Implementation record (v5, 2026-11-02).** Tour branch `chore/rails-upgrade-slice-1` off `main` `fc42d7a`, not
pushed:

| Commit | Subject | Files |
| :-- | :-- | :-- |
| `65e341b` | build: upgrade sprockets to 4.4.1 for json 3 | `Gemfile.lock` (two lines) |
| `747b033` | build: upgrade rails to 8.1.4 | `Gemfile`, `Gemfile.lock` — byte-identical to the survey recipe's lock (§3.1 plus the v3 `action_text-trix` line) |
| `8ef2d8b` | chore: apply the rails 8.1 app:update files | the shim, `puma.rb`, `content_security_policy.rb`, `development.rb`, the five public pages — the table's "accept" rows; `app:update` re-run on `747b033` produced exactly the table's file set |
| `1f1ab0c` | chore: log deprecations in production | `production.rb:44–46` — `report_deprecations = true`, `deprecation = :log` |

Both gaps resolved as follows:
- *sprockets 4.4.1 on 8.0.2:* works. After `65e341b`: P1 2, P3 green, P4 `boot ok 8.0.2 sprockets=4.4.1 json=2.9.1
  heartbeat=200`, P4b and P5 identical to `main` → two commits.
- *The `app:update` diff shape:* matched the table.

Results, `main` → branch tip (each check run on an rsync copy, §4.0 v5):
- **P1:** 2 → 0.
- **P2:** clean.
- **P3:** green at every commit.
- **P4:** `rails=8.1.4 defaults=7.0`, `to_time_preserves_timezone` `:offset` → `nil`, `path_relative_redirect`
  `nil` → `:log`, every other flag unchanged, `boot ok 8.1.4 sprockets=4.4.1 json=3.1.0 heartbeat=200`.
- **P4b:** 200, 194,295 bytes, the same four digests, `missing=[]`, body diff 0.
- **P5:** 14 requests on three hosts. Byte-identical except `/404` and `/500` (the new public pages); 0 `DEPRECATION`
  lines on stderr.
- **P6:** routes identical (15); production middleware 28 → 27, only `PermissionsPolicy::Middleware`.
- **P7:** the 12 named files.

**Deliberate break:** a copy of `747b033` with sprockets put back to 4.2.2 fails P3 at `assets:clean` (exit 1,
`ArgumentError: unknown keyword: create_additions`).

**OD2 proof:** in production mode, `Rails.deprecator.warn` printed nothing before `1f1ab0c` (`silenced=true`). After
it, the warning reached STDOUT as `DEPRECATION WARNING: …` and nothing reached stderr. The production boot, build and
tour render log none. The one production deprecation P4 now prints comes from the probe script itself
(`ActiveSupport.to_time_preserves_timezone`, deprecated in 8.1; the notes' probe now silences it).

**Review:** `codex-review`, high effort (production configuration and the Render build path), on an rsync copy of the
branch tip given the diff, the commits and this document: **no actionable findings**. The read-only sandbox cannot start
in the dev container (`bwrap: No permissions to create a new namespace`), so it ran with full access on the copy; the
copy was unchanged afterwards. Claude's own pass against the out-of-scope list found nothing either: the shim has 0 live
lines, `load_defaults` is still `7.0`, no file falls outside the 12, only the rails family, its new dependencies and
sprockets moved in the lock, and no `icon.*` is referenced.

### 4.3 Slice 2 — framework defaults, then `config.load_defaults 8.1`

The flags that `load_defaults 8.1` turns on beyond 7.0 (railties `configuration.rb`, `load_defaults` branches 7.1,
7.2, 8.0, 8.1 at v8.1.4), restricted to the frameworks this app loads. Values "today" and "after" are from the probe
on 2026-10-31. Rows marked *inert* have no caller in `app/`, `lib/` or `config/` (the greps are in the notes).

| # | Flag (version) | Today → after | Blast radius here | Verdict |
| :-- | :-- | :-- | :-- | :-- |
| 1 | `add_autoload_paths_to_load_path = false` (7.1) | `true` → `false` | the only `require` of app code is `require 'net/http'` (`lib/insight_photo.rb:1`, stdlib); `lib/` is autoloaded by `autoload_lib` (`application.rb:29`) | inert |
| 2 | `action_dispatch.default_headers` (7.1) | drops `X-Download-Options: noopen` | one response header fewer on every page (an Internet Explorer header) | harmless, visible in P5's header capture |
| 3 | `action_view.sanitizer_vendor = Rails::HTML5::Sanitizer` (7.1) | `Rails::HTML4::Sanitizer` → HTML5 | `simple_format` sanitizes by default (actionview `text_helper.rb:386`): `listings/_property.html.erb:2` (listing description), `_agent_details.html.erb:22` (agent bio). **Population, dev restore, 2026-10-31:** 8,900 listings, 8,790 with a description, **3,348** whose `description`/`description_es` contain `<` or `&`; 4,551 accounts, 7 with a description, 1 with markup. All 3,349 rows (3,352 non-blank values) run through both sanitizers: **54 differ — 30 only in `&nbsp;` serialisation (entity versus U+00A0), 24 only in `\r\n` → `\n`**, which `simple_format` normalises itself. Query and script in the notes | no visible change; the one real behaviour flip in this slice, and it is measured |
| 4 | `active_support.cache_format_version = 7.1`, `raise_on_invalid_cache_expiration_time` (7.1) | — | no `Rails.cache`, no `cache` helper (grep empty); production `cache_store` is the unused default file store | inert |
| 5 | `message_serializer = :json_allow_marshal`, `use_message_serializer_for_metadata` (7.1) | Marshal → JSON for signed/encrypted payloads | the session cookie (`ActionDispatch::Session::CookieStore` in the stack) carries only the CSRF token (`application_controller.rb:3`, `layouts/application.html.erb:6`). Old cookies stay readable; after a rollback, JSON-written cookies are unreadable → a fresh CSRF token. Every route is `GET` except the four `via: :all` routes, where a POST already fails CSRF today | harmless |
| 6 | `precompile_filter_parameters`, `dom_testing_default_html_version`, `log_file_size`, `debug_exception_log_level` (7.1) | — | logging/test-only | inert |
| 7 | `yjit = true` (7.2), then `yjit = !Rails.env.local?` (8.1) | `false` → production `true` | Ruby 3.4.12 here enables YJIT (`RubyVM::YJIT.enabled?` → `true` after `enable`); Render's build of 3.4.12 UNVERIFIED → S-YJIT. Rails guards the call, so an interpreter without YJIT boots unchanged | safe; memory compared against a baseline captured **before** the push (S-MEM) |
| 8 | `action_dispatch.strict_freshness = true` (8.0) | `false` → `true` | no `fresh_when`/`stale?` (grep empty) | inert |
| 9 | `Regexp.timeout \|\|= 1` (8.0) | `nil` → `1` | no regex literal or `Regexp.new` in `app/`/`lib/` as of the survey; the eight `gsub`/`include?` sites take string arguments. **v5:** `5e1d381` adds one, `lib/insight_photo.rb:110` `token.to_s.gsub(/\s+/, '')` on a listing or pano token from the URL — a single character class with no nesting, linear in the token length, so the verdict stands. Gems: the sanitizer (Loofah/Nokogiri), I18n, Rack, URI, Net::HTTP. An overrun raises `Regexp::TimeoutError` → 500 on that page | low; S5 watches |
| 10 | `action_controller.escape_json_responses = false` (8.1) | `nil` → `false` | `heartbeat_controller.rb:3` — body has no `<>&`, no U+2028/9 | inert |
| 11 | **`action_controller.action_on_path_relative_redirect = :raise`** (8.1) | `:log` → `:raise` | the four `redirect_to` sites (v4 lines: `listings_controller.rb:9, 50, 43`; v4's `allow_other_host: true` does not touch this check — actionpack 8.1.4 `redirecting.rb:158` handles path-relative URLs inside `_compute_redirect_to_location`, before the open-redirect check at `:161`): `panos_controller.rb:8` (`'/'`, absolute path, fine); `listings_controller.rb:9, 49` (canonical URL from the API: `PROPERTY_WEBSITE_HOST`-prefixed, insgt-api `listing.rb:524`; dev value carries a scheme, seen as `http://localhost:3002/…`; production UNVERIFIED); `listings_controller.rb:42` (`LISTING_DOMAIN` + path; dev value carries a scheme — boolean probe, value not printed; production UNVERIFIED). A scheme-less value becomes `PathRelativeRedirectError` → 500 where today the browser resolves it | **gated by S-ENV before the flip** |
| 12 | `active_support.escape_js_separators_in_json = false` (8.1) | — | `image_handler.rb:74` `to_json` of bucket/key/edits; no U+2028/9 in S3 keys | inert |
| 13 | `action_view.render_tracker = :ruby`, `remove_hidden_field_autocomplete` (8.1) | — | no fragment caching, no forms | inert |
| 14 | `active_support.to_time_preserves_timezone` | gone on 8.1 | nothing to flip | n/a |

**Approaches (OD1 — A decided 2026-10-31).**
- **A — one deploy, straight to `load_defaults 8.1`**: set `config/application.rb:24`, delete
  `new_framework_defaults_8_0.rb` and `_8_1.rb`, nothing else. Every row above is inert, measured (row 3) or gated
  (row 11). Cost: about 2 h plus one deploy morning. Forecloses nothing: a rollback is one click.
- **B — two deploys, `7.2` then `8.1`**: isolates YJIT and the sanitizer (rows 3, 7) from `Regexp.timeout` and the
  redirect raise (rows 9, 11). Cost: about 3 h plus two mornings. Worth it only if S-ENV fails or Dan wants the YJIT
  memory reading alone.
- **C — flag by flag through the shims**, the insgt-api pattern: five or more deploys for fourteen rows of which
  eleven are inert. Not proportionate here.

**Scope (A).** The one-line change plus the two deletions. **S-ENV first**, from the Mac, before the branch is cut:
`curl -sI https://insightlistings.com/s/<token>` → `Location: https://…` (row 11, the API's host value), and in the
Render Shell `bundle exec rails runner 'puts ENV["LISTING_DOMAIN"].to_s.match?(%r{\Ahttps?://})'` → `true` (row 11,
the tour's own value). Either `false` is a STOP: fix the variable in the Render dashboard first.

**Breaking changes affecting this codebase:** rows 2, 3, 7, 9, 11 above; nothing else.

**Out of scope.** `rails/all`-style changes (none apply); any gem; the §3.4 fixes; `config/environments/*` beyond
nothing (the 8.1 template was already applied in slice 1).

**Prerequisites.** Slice 1 deployed and quiet for at least two weekdays (S5 clean; S-DEP empty);
S-ENV passed; `Rails.version` → `8.1.4` and `loaded_config_version` → `7.0` in the Render Shell.

**Gaps pinned.**
- *Proof for row 3 without a visible change to show.* Rule: the sanitizer comparison script (notes) re-run on the
  branch against the dev restore must report the same 54/3,352 split, and P5's branded tour page diff must be empty
  (the `1qY5VLqV` description is in the 3,348). If slice 0 shipped, the contract test pins
  `ActionView::Base.sanitizer_vendor == Rails::HTML5::Sanitizer`.
- *Row 9's detection window.* Rule: S5 over the first hour plus a Logs search for `Regexp::TimeoutError` after 24 h.

**Spec plan.** Contract test (if slice 0 shipped): `loaded_config_version == "8.1"`, `Regexp.timeout == 1`,
`ActionView::Base.sanitizer_vendor == Rails::HTML5::Sanitizer`, `action_on_path_relative_redirect == :raise`,
the response to `/heartbeat` lacks `x-download-options`. Deliberate break: re-add the `_8_1.rb` shim with one line
uncommented and `load_defaults 7.0` — the version example goes red.

**Commit sketch.** 1. `chore: load the rails 8.1 framework defaults` [2: names the two measured rows and the S-ENV
result]. 2. (`test: pin the rails 8.1 defaults in the contract test` [1] — only with slice 0.)

**Post-deploy verification.** P1–P7 with `loaded_config_version` `8.1`; P4's probe prints `Regexp.timeout=1`,
`sanitizer_vendor=Rails::HTML5::Sanitizer`, `path_relative_redirect=:raise`, `default_headers` without
`X-Download-Options`; P5 identical bodies, headers minus `x-download-options`; S1–S5; S-YJIT in the Render Shell:
`bundle exec rails runner 'puts RubyVM::YJIT.enabled?'` → `true` (or `false` with a note — not a failure, row 7);
S-MEM: Render → Metrics, the memory of the hour **before** the push (captured before pushing) against the hour after.
The process count is **one Puma process with three threads** — `config/puma.rb` sets no `workers` line and
`WEB_CONCURRENCY` appears only in its comment at `:8` — so YJIT's per-process overhead counts once against the
instance plan's limit; the plan size is UNVERIFIED and is read off the dashboard with the baseline;
S-redirect: `curl -sI https://insightlistings.com/s/<token>` → 301, same `Location` as before the push.

**Rollback.** Render rollback to the slice 1 deploy. Cookies written under the JSON serializer become unreadable
(row 5) — a new CSRF token on the next page, no user-visible effect.

**Gates.** All. **Effort (estimate):** 2 h plus the deploy morning.

---

## 5. Risk register

Ranked by likelihood × cost. The signals are the Render build log, the Logs tab and the public URLs, and from v3
Honeybadger: production errors and the `/heartbeat` uptime check (SH, §4.0).

| Rank | Failure | Where | Detection |
| :-- | :-- | :-- | :-- |
| R1 | The Render build fails or the new instance does not boot — the §3.2 class of failure, or a gem that breaks only in the Render environment (x86_64 native gems: `json` 3.1.0 compiles from source on Render, no platform gem exists; nokogiri and tailwindcss-ruby come precompiled; the lock already carries `x86_64-linux`) | slice 1, at build or first boot | S1 build log (`assets:clean` is the last build step; a boot failure shows in Events as a failed deploy and the old instance keeps serving); S3; `/heartbeat`; the Honeybadger uptime check (v3) |
| R2 | A deprecation-turned-removal on a path the survey never exercised: the pano page (§3.4 item 3 — not rendered), a custom-domain listing (root route through `CustomDomainConstraint`), the Spanish locale (500 in production until `fix/cross-host-redirects` deploys, §3.4 item 2) | slice 1 | S5's 5xx search; SH (v3: a removed API surfaces as a new error class at the line that calls it); S-DEP (OD2); the pano and custom-domain URLs added to S4 once Dan names one of each (the dev restore's `Listing.select_virtual` can find them — §8) |
| R3 | Row 11: a scheme-less `LISTING_DOMAIN` or `PROPERTY_WEBSITE_HOST` in production turns every short-URL or language redirect into a 500 | slice 2 | prevented by S-ENV; detected by S-redirect |
| R4 | Row 7: YJIT on Render raises the instance's memory past its plan | slice 2 | Render Metrics after the push; S5 for restarts |
| R5 | Row 9: `Regexp::TimeoutError` from a gem on a long description | slice 2 | S5; 24-hour Logs search |
| R6 | A §3.4 failure is counted as slice fallout | every slice | the pre-push S4/S5 captures name them first |

---

## 6. Calendar

Estimates for a solo engineer; dates respect §2.2 and avoid the insgt-api mornings in `rails-upgrade.md` §6 (its
slice 3 is pencilled for Mon 11-02, slices 4, 5a, 5b for 11-09, 11-10, 11-11). Today is Sat 2026-10-31.

| When | What | Hours (estimate) |
| :-- | :-- | :-- |
| Sat 10-31 – Sun 11-01 (v3–v4) | **Honeybadger deployed** (`chore/honeybadger`, OD7) — live by 11-01 on tour `main` `ad04756`, which also carries the account-page and footer fixes; the first day's inbox becomes SH's baseline | 0.5 |
| **Mon 11-02, first thing** | the §3.4 production curls from the Mac — `/r/<slug>` ×2, the `es.` tour, `/s/<token>` for a custom-domain listing; their status lines set the fix branch's priority (OD5) | 0.25 |
| **Mon 11-02** | merge `docs/rails-upgrade-virtual-tour`; implement slice 1 (afternoon, after the api's morning deploy). **v5: implemented**, branch `chore/rails-upgrade-slice-1` (§4.2 implementation record) | 3 |
| **Tue 11-03, 09:30 PT** | **deploy slice 1 (8.1.4)** — four days before 8.0's security end | 1 |
| Wed 11-04, 09:30 PT | **deploy the §3.4 fix branch** (OD5) — its own branch and morning, if slice 1's S5 was clean. **v4: mostly done early** — items 1 and 7 live on `main` `ad04756`; item 2 on `fix/cross-host-redirects`, Dan's push; item 3 (pano) remains | 1 (+2 to build it Tue) |
| Wed 11-04 – Fri 11-06 | slice 0 (OD3); S-ENV from the Mac; implement slice 2 (no deploy); start the insgt-galleries survey (OD6) | 3 + 2 + 2 |
| **Mon 11-16, 09:30 PT** | **deploy slice 2 (`load_defaults 8.1`)** — after the api's defaults week, so the two defaults flips are a week apart | 1 |

**Slippage rule:** a slice that misses its morning moves to the next Mon–Wed morning that is not an insgt-api
morning. For slice 1: Tue 11-03, else Wed 11-04 (the fix branch then moves to Mon 11-09). Thursday is **not** taken to
make the date — the deadline is soft (§1.3) and a bad deploy morning costs more than a week on 8.0.2; a slip past 11-07
puts slice 1 on Mon 11-09 and moves slice 2 a week.

Total ≈ 13 h (slice 1, the fix branch, slice 0, slice 2) plus three deploy mornings.

---

## 7. Decisions and open questions

Settled 2026-10-31 by the plan review Dan pasted. ASSUMPTION: the review's calls are his; if they were a reviewer's
recommendations he has not endorsed, every row reverts to open. The v1 recommendation and the argument against it are
kept beside each decision.

| ID | Question | Decision (2026-10-31) | v1 recommendation / against | Carried by |
| :-- | :-- | :-- | :-- | :-- |
| OD1 | Defaults approach: A (one deploy to 8.1), B (7.2 then 8.1), C (flag by flag) | **A.** Eleven inert rows, one measured, one gated; B buys only a cleaner YJIT reading, and the before/after memory baseline (S-MEM) gets that anyway | A recommended; B for the YJIT reading; C is the api pattern | §4.3 |
| OD2 | Log deprecations in production (`report_deprecations = true`, `:log`) | **Yes.** Costs nothing; the only signal on panos and custom domains | yes recommended; log noise if a gem deprecation fires per request | §4.2 item 3, S-DEP |
| OD3 | Slice 0, a runnable test harness with six integration tests | **Yes, timed:** not competing with slice 1 for Monday; lands Wed–Fri; earns its keep in slice 2's contract test | yes recommended; the render script is already the gate | §4.1, §6 |
| OD4 | Accept the regenerated public error pages | **Accept the pages, reject `icon.*`** | accept recommended | §4.2 table |
| OD5 | The §3.4 pre-existing failures | **Own branches, curls first** — the Monday status lines set the priority. The 2026-10-31 fetches already show `/r/<slug>` and the `es.` tour at HTTP 500, so the fix branch (`@listing&.[]` / `dig` guards in the three partials, `allow_other_host: true` at the three redirect sites, the pano template) ships the same week as slice 1, on its own branch and its own morning (§6). **v4:** items 1 and 7 fixed on `main` `ad04756`, item 2 on `fix/cross-host-redirects`, ahead of slice 1; item 3 open | own branches after slice 1 | §3.4, §6, §8 |
| OD6 | insgt-galleries (Rails 7.1.5.2) | **Pulled forward to right after slice 1.** By the maintenance rule (two years of security fixes from 7.1.0, 2023-10-05) its support ended about **2025-10-05**, thirteen months ago — computed, not read from the page (UNVERIFIED). Its lock has `sprockets (4.2.2)`, `sprockets-rails (3.5.2)`, `rails (7.1.5.2)`, Ruby 3.4.12 and `config.load_defaults 7.0` (read 2026-10-31): the §3.2 trap applies to it verbatim. Its survey's first question: are its pages public enough to make it the bigger exposure of the two (password-gated galleries)? | a follow-up line | §8 item 13 |
| OD7 | An error tracker for the tour | **v3, reversed the same day: yes, now, on its own deploy ahead of slice 1.** Honeybadger 6.10.1; errors only (Insights off); production only (the gem's `development_environments` default, not restated); revision from `RENDER_GIT_COMMIT`; log breadcrumbs left on (the app logs nothing of its own); a Honeybadger project separate from the api's, so the api's SH comparisons stay clean; an uptime check on `/heartbeat`. No deploy notifications, check-ins or JS reporting (§8 item 14). v2 decision: not now — the Render log was the signal | not now | §1.1, §4.0 SH, §5 |

---

## 8. Follow-up list

Not in any slice. Candidates for their own small changes.

1. **§3.4 item 1** — the account page: guard `@listing` in `_broker_logo.html.erb:1` and `_team_logo.html.erb:1`
   (or pass the flags in), guard `account[:headshot]` in `_agent_detail.html.erb:5`; one request test per case.
   Production answers HTTP 500 today (§3.4); the fix ships this week (OD5, §6). **v4: done** — `9dbf6d1`,
   `79d5f11`, `fc28ea9` on `main` `ad04756`; `_team_logo` needed nothing (§3.4 item 1). No request test exists yet
   (slice 0, OD3, is where they belong).
2. **§3.4 item 2** — `allow_other_host: true` at `listings_controller.rb:9, 42, 49` (the targets are the API's
   own canonical URLs and the tour's own domain); the `es.` shape answers HTTP 500 in production today (§3.4); the custom-domain `/s/<token>` shape is still
   to be requested on Monday. **v4: on `fix/cross-host-redirects` (`156b7d4`, `:9, 43, 50`), awaiting Dan's push.**
   **v5: done** — merged at `b0ba43f`, on `origin/main`.
3. **§3.4 item 3** — `panos_controller.rb:19`: render `errors/not_found` like `listings_controller.rb:57` does, or
   add the template.
4. `webdrivers` 5.3.1 (abandoned; pins selenium-webdriver `< 4.11`): remove it and let selenium-webdriver 4.x
   manage drivers — test group only.
5. Puma 6.6 → 7.x/8.x (`Gemfile:13` `~> 6.0`); its own change with a Render boot check.
6. Tailwind 4: tailwindcss-rails 4.7 + tailwindcss-ruby 4.3, `config/tailwind.config.js` migration, and
   `bin/render-build.sh:15`'s hard-pinned 3.3.4 binary (a 2025-06 Render workaround that duplicates what
   tailwindcss-ruby ships).
7. Propshaft in place of sprockets — removes the §3.2 class of trap and the manifest parse; a real migration
   (`manifest.js`, `vendor/assets/javascripts` link tree, `font-awesome` require in `application.css`).
8. `Procfile.dev:1` / `bin/dev:9` port 3000 → 3002 to match `CLAUDE.md` and the platform table.
9. After slice 1, the version strings: `insgt-platform/CLAUDE.md:33` ("Rails 8.0"), `apps/insgt-virtual-tour/CLAUDE.md:3`,
   `docs/services/insgt-virtual-tour.md:12`.
10. Dead config for frameworks not loaded: `config/cable.yml`, `config/storage.yml`; `config/initializers/content_security_policy.rb`
    and `permissions_policy.rb` are all comments.
11. `ImageHandler#s3_resource` dead code and the unsigned floor-plan URLs (already in `docs/services/insgt-virtual-tour.md`).
12. A pano URL and a custom-domain listing for S4 (R2): find them on the dev restore
    (`OrderUrl` with `type_of` 7; `Listing.where.not(custom_domain: nil)` — model names UNVERIFIED) and add both to
    the P5 path list.
13. insgt-galleries (OD6, pulled forward): survey right after slice 1 deploys, starting from its lock (`sprockets
    (4.2.2)` — the §3.2 trap; `rails (7.1.5.2)`; `load_defaults 7.0`) and from whether its pages are public.
14. Honeybadger beyond errors (OD7 v3 non-goals): `honeybadger deploy` from `bin/render-build.sh`, Insights, and
    production deprecations to Honeybadger the way the api routes them (OD2 keeps the Render log).
15. The IDX sentence in `_footer.html.erb:16` for a listing with no MLS name (§3.4 item 7): it reads "provided by ."
    and "Compilation ©2026 ." today. Decide the wording, or drop the two clauses when the name is blank.

---

## 9. Change log

| Version | Date | Change |
| :-- | :-- | :-- |
| 1 | 2026-10-31 | Initial document from the Phase 0 survey (insgt-virtual-tour `main` `eee78cf`; Rails 8.1.4 newest, 8.2 unreleased; 8.0 security support ends 2026-11-07). Path 8.0.2 → 8.1.4 in one hop; two slices plus an optional test-harness slice. Dependency audit: every gem resolves; the one blocker is `json` 3.1.0 (pulled in by activesupport 8.1.4) against sprockets 4.2.2's `create_additions`, which fails `assets:clean` and every production boot with a manifest — resolved by sprockets 4.4.1, verified through the full Render build sequence and a production boot. 8.1.4 on the 7.0 defaults verified: 0 deprecations, routes identical, middleware identical but for PermissionsPolicy, nine pages byte-identical against the live dev API. The 7.1–8.1 defaults mapped to this app: eleven inert rows, the sanitizer vendor measured on 3,352 description values (54 differ, all invisible), the path-relative redirect gated by S-ENV. Four pre-existing failures recorded (account page, Spanish-subdomain redirect, pano error template, the test helper). Seven open decisions. |
| 2 | 2026-10-31 | The plan review's calls recorded as decisions (§7, OD1 A, OD2 yes, OD3 yes timed Wed–Fri, OD4 accept pages / reject icons, OD5 own branch this week, OD6 pulled forward, OD7 not now). Review point 1 closed with evidence: P4b, a production-mode render of the branded tour against the compiled manifest — identical on 8.0.2/sprockets 4.2.2 and 8.1.4/sprockets 4.4.1 (194,295 bytes, the same four digests, no missing asset). Point 2: `x86_64-linux` already in `PLATFORMS`; `json` 3.1.0 has no platform gem and compiles on Render (§3.1, R1). Point 3 answered early: production fetches show `/r/nora-nido`, `/r/logan-banta` and the `es.` tour at HTTP 500 with `/heartbeat` as the control (§3.4); the fix branch joins the calendar (§6). Calibration: the deadline marked soft, the slippage rule reworded without the Thursday exception, the 2027-10-10 forward anchor added (§1.3). Smaller points: S-MEM memory baseline before the slice 2 push with the one-process Puma fact (§4.3), the Auto-Deploy check after a rollback (§4.0), slice 0 timed off Monday (§4.1), OD6's garbled clause replaced by the galleries lock facts. |
| 3 | 2026-10-31 | OD7 reversed: Honeybadger 6.10.1, errors only, on its own tour branch `chore/honeybadger` (`7b8dd80`, `93f7d30`), deployed ahead of slice 1 (§1.1, §6, §7). Verified on the branch: P1 2 (unchanged), zeitwerk clean, the build green, routes identical, middleware +4 Honeybadger entries (§4.0 v3 note), P5 byte-identical on nine pages. Production boots without a key; with a key from the environment it reports through a stubbed backend. SH added to §4.0; §5's detection gains Honeybadger. §3.1 corrected: the slice 1 lock diff also adds `action_text-trix`; the Bundler 2.6.9 `ruby`-platform trap recorded. §3.4 item 1 marked partly fixed (`9dbf6d1`, `06ae511`; two partials remain). §8 item 14 added. |
| 4 | 2026-11-01 | Honeybadger live (tour `main` `ad04756`; first production notice 11:31 −05:00, the `es.` redirect) (§1.1, §6). §3.4 item 1 fixed (`9dbf6d1`, `06ae511`, `79d5f11`, `fc28ea9`), including a third crash the survey missed (no `organizations` in the account JSON); **v3's `_team_logo` claim corrected** — its caller guards it. §3.4 item 2 fixed on `fix/cross-host-redirects` (`156b7d4`, all three sites), the short-URL raise reproduced. §3.4 item 7 added and fixed (`23f1b0e`, the footer's MLS name). Slice 2 row 11: `allow_other_host` does not affect the path-relative check (actionpack source). §4.0 S5, §5 R2, §6, OD5, §8 items 1–3 brought up to date; §8 item 15 added. |
| 5 | 2026-11-02 | Slice 1 implemented on tour `chore/rails-upgrade-slice-1` (`65e341b`, `747b033`, `8ef2d8b`, `1f1ab0c`), off `main` `fc42d7a`; §4.2 implementation record. Gap pins: sprockets 4.4.1 works on 8.0.2 (two commits); the `app:update` set matched the table. Corrections: the 8.1 shim holds six settings, not seven; P5's `/404` and `/500` change with the accepted public pages (§4.2 had said no P5 difference). §4.0: P-checks run on rsync copies because a `public/assets` manifest left in the real tree is read first in development and test. §3.3: the `PermissionsPolicy` cause verified in railties source. Three tour commits since v4 recorded (§1.1); `fix/cross-host-redirects` merged (§3.4 item 2, §4.0 S5, §8 item 2); `5e1d381` adds the first regex literal in app code (§4.3 row 9, verdict unchanged). Codex review at high effort: no actionable findings. The notes' P4 probe silences its own 8.1 deprecation; `pchecks.sh`, `compare.sh` and `deprecation-probe.rb` added to the notes' appendix. |
