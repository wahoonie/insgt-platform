# Rails upgrade — slice 2: 8.0.5.1, transit only

**Repo:** `insgt-api`. Platform repo for the runbook and the write-back only.
**Contract:** `docs/architecture/rails-upgrade.md` v4 — §4.3 (the slice), §4.0 (the verification kit; S4, S7 and SH as slice 1's runbook amended them), §2 (sequencing), §3 (dependency audit), §5 R1 (a gem fails at a major bump) and R3 (`to_time`). Prompt: `docs/architecture/rails-upgrade-slices/slice-2.md`.
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Status:** **Approved 2026-10-27** by Dan — all six open questions as recommended, with the decisions and modifications A–G recorded in the next section. **Implemented and verified 2026-10-27** on insgt-api `chore/rails-upgrade-slice-2` off `master` 473e2747: five commits `671c3c6b` (routes), `df0e12ec` (`:zone`), `df7826c5` (8.0.5.1), `f1b2af6e` (binstubs), `4b464230` (shim); P1 `2045 examples, 0 failures`, 0 deprecation lines, plain and `CI=1`; P2–P8 and P-PROD pass (runbook Deploy log). Review round 1 done: no blocker; one spec strengthening folded into commit 1 and commit 3's body corrected by rebuilding the branch (the pre-review hashes `84543d51`…`df6759e3` no longer exist). Review round 2 done the same evening: no blocker, no should-fix; the runbook `docs/runbooks/deploy-rails-upgrade-2.md` is `Ready` on the platform branch `docs/rails-upgrade-slice-2`. **At the verification STOP.** Write-back done 2026-10-27 on the platform branch: `rails-upgrade.md` v5 (slice 1's deploy and owed amendments, §4.3 as built, §4.4 reworded per modification F, §6–§9), the codebase notes, the slice 2 and 3 prompts, slice 1's runbook marked `Deployed`. Neither branch is pushed (Dan reviews before the window). Left: slice 1's SH line (closes 2026-10-28 05:15 PT) and the deploy record. Deploy target: **Wed 2026-10-28, 09:00–11:30 Pacific**, after slice 1's SH closes at 08:15 -0400 (§6 had Mon 11-02; Wednesday is inside §2.4 and frees Mon 11-02 for slice 3, ahead of 8.0's EOS on Sat 11-07).
**Survey date:** 2026-10-27, against insgt-api `master` 473e2747 (production v662, 2026-10-27 08:15:19 -0400; `git diff --stat 7e62c6b3 473e2747` is empty, so the 2,040-example run slice 1 recorded on `7e62c6b3` is this tree's baseline) and the platform repo `main` 77af458. Every 8.0.5.1 fact below comes from two rsync copies of the tree in this session's scratchpad — `/tmp/claude-1000/-workspace/f1b58c72-2c0c-4943-b132-747d037f5b2e/scratchpad/api-8-0` (the `app:update --force` run, diffed against the pristine copy `api-7-2`) and `/tmp/claude-1000/-workspace/f1b58c72-2c0c-4943-b132-747d037f5b2e/scratchpad/api-8-0-probe` (the `:zone` placement, the routes change, the suite, the probes) — with Rails 8.0.5.1 installed into the Ruby 3.4.10 gem set by `bundle update rails --conservative` in the copy. Rails-source citations are the installed `activesupport-8.0.5.1`, `railties-8.0.5.1`, `actionpack-8.0.5.1`, `activerecord-8.0.5.1`, and the `-7.2.4` gems for the before. The throwaway *branch* the prompt describes was declined by the session's command classifier (it rewrote and reset the real working tree); the copies give the same evidence without touching the repo.

Facts are stated with their source. ASSUMPTION, ESTIMATE and UNVERIFIED are labelled. Nothing below "should work": it ran, or it is under Unverified.

## Approval — decisions and modifications (Dan, 2026-10-27)

All six open questions answered as recommended:

1. `:zone` lives in `config/application.rb`, one line directly under `config.load_defaults 7.2`, with the why-comment. The shim is committed verbatim with all three lines commented. §4.3 item 2's table and the prompt's out-of-scope item 2 are amended in v5 to match.
2. The routes change is in scope and is commit 1.
3. `bin/setup` is rejected; `bin/rails` and `bin/rake` accepted.
4. The three Active Storage migrations stay. v5 corrects §4.3's row, the prompt's trap 1 and the notes row.
5. Slice 1's owed write-back is folded into v5, with a one-line slot for slice 1's SH result (it closes at 05:15 PT on 2026-10-28, before the window) to be filled before the push.
6. The branch is built tonight. The runbook's Deploy window section states the §6 slippage rule: if review and merge are not complete by 09:00 PT, the deploy moves to Mon 11-02 and slice 3 loses that slot; nobody pushes after 11:30 to make the window.

Modifications folded in before the first commit:

- **A. Commit 3, break (c).** Before it is pasted as evidence, confirm on 8.0.5.1 that `DateAndTime::Compatibility.preserve_timezone = :offset` inside the `around` produces a failed expectation, not a `DeprecationException`. If the reader or `to_time` warns for a non-`:zone` value, the break becomes a stub (`allow(DateAndTime::Compatibility).to receive(:preserve_timezone).and_return(:offset)`) so the red is the expectation, not the deprecator. The commit body records which one was used.
- **B. P-PROD** runs with Honeybadger reporting disabled (`HONEYBADGER_REPORT_DATA=false`, or whatever the gem honours here — `config/honeybadger.yml` and the initializer checked first); the boot output is grepped for `DEPRECATION` and the count pasted. A deprecation fired from the container with a live key would land in production's Honeybadger and contaminate the SH baseline. If reporting cannot be disabled cleanly, the probe runs as before and the exact timestamp goes in the runbook so SH excludes it.
- **C. The routes contract example** stays in `spec/architecture/rails_upgrade_spec.rb` (the one-file rule); commit 1's body says in one sentence why it is not a `spec/routing/` example, so the review does not flag it.
- **D. S-RT covers both removed symbols.** The pre-push Mac capture and the production spot check run both `curl`s (`POST /carts/0/request_shoot`, `GET /headshots/0/upload_url`) and record the status *and the first line of the response body* on v662. `404` after the push means the route is gone; a status match alone does not separate the auth layer from a generic rescue.
- **E. §2.5, the first 8.x slug.** If a scratch Heroku app or review-app pipeline exists for `insgtapi`, the branch is pushed to it tonight and the build result recorded. If none exists, skip and leave §2.5 as is; a failed build never becomes a release.
- **F. Slice 3 and the application.rb line.** v5 does not state that slice 3 deletes the line; it says slice 3's survey decides whether the line is deleted, kept or replaced — how 8.1 treats the config is slice 3's finding, not this slice's.
- **G. P1 count.** The actual example count is reported; the 2,045 estimate is not a pass criterion. `0 failures` and `0` deprecation lines in both the plain and the `CI=1` run are.

**Corrections from review round 1 (2026-10-27, Codex, verified against the installed gems):** the autosave narrowing (AR 8.0.2 in §4.3) and the `#merge` with `#or` fix (AR 8.0.3) were **backported to 7.2.3** (activerecord 7.2.4 `CHANGELOG.md`, 7.2.3 section, lines 275 and 124), so neither is a change of this slice — the "CHANGELOG checks" paragraph below and the Risks entry overstate them, and v5 removes them from §4.3's list. `racc (1.8.1)` stays in the lock (only actionpack's dependency edge goes); `cgi (0.5.1)` does leave. The two route examples also pin the carts `format: 'json'` default and the two URL helpers. `config/sidekiq_status.rb` is never loaded (pre-existing, §8 item 10; not touched here). `StringUtils.urlify` is identical on both versions.

## Scope (the prompt's five items, by §4.3 number)

1. `Gemfile:29` → `gem 'rails', '~> 8.0.5'`; the lock diff §4.3 expects (resolved below; two kinds of line more than §4.3 names).
2. `app:update --force`, the complete diff captured as evidence (below) and §4.3's table applied file by file. **As found:** `active_storage:update` copies nothing — the three migrations §4.3 says to delete have been tracked since 2026-01-29 and are in production's `schema_migrations`; there is nothing to delete.
3. §4.3 items 3–6 recorded with their evidence: Solid Queue/Cache/Cable, Kamal/Thruster and connection handling need no action; `config.load_defaults` stays `7.2`.
4. §4.3 gap 1, the one default flip to `:zone`. **As found:** the flip cannot live in the generated shim under `:raise`; it goes in `config/application.rb` (open question 1).
5. §4.3's spec plan (floor `8.0.5.1`; the zone examples — `Time#zone` is a `TimeZone` object on 8.0, not `"PST"`), P1–P8 and S0–S10 with `8.0.5.1`, `docs/runbooks/deploy-rails-upgrade-2.md`.

**Added by the survey, needs approval (open question 2):** `config/routes.rb:6` and `:19` — Rails 8.0 raises `ArgumentError` at route load for the custom actions in the two `only:` arrays. Without the change production does not boot and no request spec runs.

## Out of scope — do not touch

The prompt's three: every other line of the 8.0 shim and `config.load_defaults`; `config/application.rb` *as regenerated*, `config/environment.rb`, `config/environments/*`, `cors.rb`, `filter_parameter_logging.rb` (each rejected below, with the diff that says why); the ~25 `Model.connection` sites, `rails/all`, any gem beyond `rails`, `config/ci.rb`. Plus, found in the survey and left alone: the three Active Storage migrations (pre-existing, see above); `config/puma.rb` and `bin/setup` (rejected, below); `GET /rails/info/notes` (an internal, development-only route 8.0 adds; the printed route table is identical); the 24 `:unprocessable_entity` rack warnings (§8 item 1); the `upsert_all` at `lib/tasks/marketing_source.rake:41`, which has no spec — §4.3's spec plan names `spec/lib/tasks/marketing_source*`, and no such file exists (grep); none is added here.

---

## Phase 0 — survey

### Done

Read §4.3, §4.0, §4.2 (v4), §2, §3 and §5–§9 of the design document, the slice 1 and 2 prompts, the slice 1 plan and runbook, the slice 0 runbook's baseline, and the codebase notes; re-verified every notes row this slice depends on against 473e2747; resolved the 8.0.5.1 lock on a scratch copy and installed it; ran `bin/rails app:update --force` on a copy of the tree and diffed it against a pristine copy; read the 8.0.5.1 generator, railtie, `to_time`, key-transform, autosave and connection sources and the five framework CHANGELOGs; booted the copy in development and in test; ran the full suite twice on 8.0.5.1 (plain and `CI=1`); diffed the route tables; ran a Sidekiq job end to end on 8.0.5.1; ran the key-collision and `to_time` probes on both versions.

### Prerequisites — landed (facts)

| Prerequisite (§4.3, prompt) | Evidence |
| :-- | :-- |
| Slice 1 deployed; `Rails.version` → `7.2.4` in a production runner | `docs/runbooks/deploy-rails-upgrade-1.md` Deploy log: **v662** `473e2747`, 2026-10-27 08:15:19 -0400; S3 printed `7.2.4` and `true`; `Booted Rails 7.2.4 application in production environment` on `backgroundworker.1`; S0 notice `470ed91b-d622-40d3-a2fb-bc5adb644454`; S7 and S9 pass |
| §4.2's commits on `master` | `git log`: `5c9446da` … `a5d9b001` (eight) merged by `473e2747`; `master` equals `origin/master` |
| The suite green with `:raise` | 2,040 examples, 0 failures, 0 `DEPRECATION WARNING` lines on `7e62c6b3` (runbook), whose tree is identical to `473e2747` |
| SH shows no `RailsDeprecation` since slice 1 | **Due 2026-10-28 08:15 -0400** (runbook step 7); the one `RailsDeprecation` so far is S-DEP's, by design. Not a blocker for implementing; a blocker for the push |
| Slice 1's write-back to the design document | **Owed.** `rails-upgrade.md` is v4 and its status line still says "deploy planned Wed 10-28"; the amended S7 and SH criteria live only in the runbook. This plan's v5 folds them in (open question 5) |

### Codebase notes — rows this slice depends on, re-verified

| Notes row | Today | Drift |
| :-- | :-- | :-- |
| `Gemfile:29` `'~> 7.2.4'` | same | none |
| `Gemfile.lock:380` rails 7.2.4; `:298` minitest 5.27.0; `:369` rack 3.2.4 | same | none |
| `application.rb:12` `load_defaults 7.2`; `:17, 20–21` autoload lines; `:24–25` hosts; `:38–41` `draw_routes` | same | none |
| `environment.rb:7, 9` Jbuilder / Phoner | same | none |
| `production.rb:84–85` `report_deprecations = true` / `:notify`; `:48, :101` the `/up` exclusions; `:51–56` logger; `:103–113` SMTP | same | none |
| `test.rb:57–58` `:raise`; `:18` `eager_load = ENV["CI"].present?` | same | none |
| `cors.rb:8–55`; `filter_parameter_logging.rb:4–8` | `cors.rb:8–57` (origins at `:10–43`); `:4–8` | cosmetic |
| `puma.rb` "identical to the 8.x template minus comments" | **no**: the 8.0 template adds `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` | row corrected in the write-back |
| `new_framework_defaults_8_0.rb` "generated by slice 2 … only `to_time … = :zone` uncommented" | the flip cannot be in the shim (below) | row rewritten |
| `db/migrate/` "no Active Storage migration has ever been added or deleted" | **wrong**: `20260122184539_add_service_name_to_active_storage_blobs.active_storage.rb`, `…40_create_active_storage_variant_records…`, `…41_remove_not_null_on_active_storage_blobs_checksum…` are tracked since `e66411cf` (2026-01-29, "Updated rails. Added flyers…"); each is `Migration[6.0]` guarded by `return unless table_exists?(:active_storage_blobs)`; the dev restore's `schema_migrations` holds all three versions; no `active_storage_*` table | row corrected |
| `json_param_key_transform.rb:2–6` `deep_transform_keys!`; `lib/app_param.rb` `deep_underscore_params` | same; `app_param.rb:3–19` deletes each key and reinserts it underscored, on `Hash` and on `ActionController::Parameters` | none |
| `account_metric.rb:42–44`, `account.rb:91`, `order_type.rb:87` positional `enum` | same | none |
| the `.or(` sites, "9 in concerns" | 10: `phone_number.rb:209`, `notification_query.rb:29, 35`, `user_query.rb:314`, `property_query.rb:61, 70, 79, 80, 81`, `account_query.rb:378` | none |
| `CrudAttribution` "app/models/* validations" | the module is **`lib/crud_attribution.rb:4–12`** (`validates :created_by_id, presence: true, on: :create`; `:updated_by_id` on update), included by 52 models | path added |
| `Procfile:2` `sidekiq -c 4`; `cache_store` `:null_store` in test and dev | same (runner) | none |
| `8-0-stable railtie.rb:99–103, 125–130` "after_initialize and `set_configs` both forward" | 8.0.5.1 `railtie.rb:99–103` and `:125–130` — confirmed, and **the order of the two is what breaks the shim** (below) | consequence added |
| `date +%z` → `+0000` | same | none |

Collision greps: `config/initializers/new_framework_defaults_8_0.rb` and `bin/dev` do not exist; `grep -rn "to_time_preserves_timezone" app config lib spec` → only `spec/architecture/rails_upgrade_spec.rb:20` (slice 1's example).

### Fresh facts the plan rests on

**Lock resolution** (`bundle lock --update rails --conservative` on a scratch copy of `Gemfile` + `Gemfile.lock` with only line 29 changed; `bundle update rails --conservative` in the working copy produced a byte-identical lock):

- the 13 gems and their `(= …)` pins `7.2.4` → `8.0.5.1`; `DEPENDENCIES` `rails (~> 8.0.5)`; the 13 checksums;
- constraint lines the 8.0.5.1 gemspecs changed: actionpack `rack (>= 2.2.4, < 3.3)` → `rack (>= 2.2.4)` (§4.3's "cap disappears"; `rack (3.2.4)` stays); actionpack, actionview and railties drop `cgi`, actionpack drops `racc` (§1.2), so **`cgi (0.5.1)` leaves the lock** (spec and checksum lines); activesupport `connection_pool (>= 2.2.5, < 3)` → `(>= 2.2.5)`, `minitest (>= 5.1, < 6)` → `(>= 5.1)`, and **adds `uri (>= 0.13.1)`** (no `uri` entry moves; it is already locked);
- `minitest (5.27.0)` does **not** move (the cap is gone; `--conservative` holds it); `useragent`, `rack-session`, `rails-dom-testing`, `rails-html-sanitizer` unchanged, as §4.3 expects.

§4.3 item 1 is amended in v5 to name the `cgi`/`racc` removals and the `uri` line.

**`app:update --force`** is accepted: `UpdateCommand` has `add_runtime_options!` (`railties-8.0.5.1 commands/app/update_command.rb:11`) and merges `options` into the generator options (`:82`); the file is identical on 8.0.2 and 8.0.5.1. `perform` sets `Rails.application.deprecators.silenced = true` (`:16`), so the run cannot trip `:raise`. Output, verbatim, with §4.3's decision per file (the full diff: `/tmp/claude-1000/-workspace/f1b58c72-2c0c-4943-b132-747d037f5b2e/scratchpad/app-update/app-update.diff`, 600 lines; the run log and file list beside it):

| Generated file | `app:update` said | What the template would do (from the diff) | Decision |
| :-- | :-- | :-- | :-- |
| `config/boot.rb` | identical | — (regenerated by `configs`, identical: no bootsnap) | — |
| `config/application.rb` | force | **keeps `load_defaults 7.2`** (§4.3 says the template writes `8.0`; it targets `loaded_config_version`), drops the autoload lines (`:20–21`), both `config.hosts` (`:24–25`) and slice 1's `draw_routes` block (`:38–41`); double quotes | **reject** |
| `config/environment.rb` | force | drops `Jbuilder.key_format` and `Phoner` (`:7, :9`) | **reject** |
| `config/puma.rb` | force | adds `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]`; quotes; comment edits | **reject** — §4.3's rule was "accept if comment-only", and it is not |
| `config/environments/development.rb` | force | drops the ngrok host, `disallowed_deprecation*`, the `:null_store` branch (`cache_store = :memory_store` always); adds `query_log_tags_enabled` | **reject** |
| `config/environments/production.rb` | force | **`report_deprecations = false` and no `:notify`** (undoes slice 1), drops the SendGrid block (`:103–113`), the logger chain (`:51–56`) for `TaggedLogging.logger`, `perform_caching`, `raise_on_missing_callback_actions`; comments out both `/up` exclusions (`:48, :101`); adds `assume_ssl = true`, `silence_healthcheck_path = "/up"`, `public_file_server.headers`, `default_url_options = { host: "example.com" }` | **reject** |
| `config/environments/test.rb` | force | **`:raise` → `:stderr`** (undoes slice 1's gate), drops the `host_authorization` exclude, `disallowed_deprecation*`, `perform_caching`, the `integer/time` require; `default_url_options` → `example.com` | **reject** |
| `config/initializers/assets.rb` | create, then remove | net: no file (written, then removed by `config_when_updating` for an app without an asset pipeline) | — (not in §4.3's table; no file results, so no STOP) |
| `content_security_policy.rb`, `inflections.rb` | identical | — | — |
| `config/initializers/cors.rb` | force | replaces the allow-list (`:10–43`) with the commented example | **reject** |
| `config/initializers/filter_parameter_logging.rb` | force | replaces the list with the 8.0 default (`passw email secret token _key crypt salt certificate otp ssn cvv cvc`): loses `code`, `phone`, `phone_number`, `phone_number_formatted`; narrows `key` to `_key` | **reject** |
| `config/initializers/new_framework_defaults_8_0.rb` | create | the three commented lines — `to_time_preserves_timezone = :zone`, `strict_freshness = true`, `Regexp.timeout = 1`; no ERB | **accept, all three lines commented** (the flip lives elsewhere, below) |
| `bin/dev` | create | `exec "./bin/rails", "server", *ARGV` | **reject** (§4.3) |
| `bin/rails`, `bin/rake` | force | double quotes only | **accept** |
| `bin/rubocop` | identical | `rubocop` is in the Gemfile (`:53`); `brakeman` and `thruster` are not, so `bin/brakeman` and `bin/thrust` are not offered | — |
| `bin/setup` | force | drops `APP_NAME`, `gem install bundler`, `bin/rails restart`; keeps `db:prepare` (already there); adds `exec "bin/dev"` unless `--skip-server` | **reject** (recommended; §4.3 says accept — open question 3). Its tail execs the rejected `bin/dev`; nothing in `.devcontainer/`, the README or the platform's `bin/dev` calls `bin/setup` (grep) |
| `rails active_storage:update` | ran | **copied nothing**: `db/migrate` identical to the pristine copy — `railties:install:migrations` skips a migration whose name already exists | nothing to delete; §4.3's delete row and the prompt's trap 1 are moot |
| `public/` | skipped | `public_directory` returns early for `update && api` (`app_generator.rb:220–221`) | — |
| `config/ci.rb`, `bin/ci`, Dockerfile, `config/deploy.yml`, any solid file | not generated | — | — |

No generated file is absent from §4.3's table except the created-and-removed `assets.rb`. Gap 2: no STOP.

**Where `:zone` must be set.** With the shim's line uncommented (§4.3's mechanism) the development runner reports `config=:zone` after boot, but the **test environment fails to boot**:

```
activesupport-8.0.5.1/lib/active_support/railtie.rb:128:in 'Kernel#public_send': DEPRECATION WARNING: `to_time` will always preserve the full timezone rather than offset of the receiver in Rails 8.1. To opt in to the new behavior, set `config.active_support.to_time_preserves_timezone = :zone`. (called from <top (required)> at …/config/environment.rb:5) (ActiveSupport::DeprecationException)
```

and `bundle exec rspec` reports `0 examples, 0 failures, 141 errors occurred outside of examples` — one `DeprecationException`, then 140 `FrozenError`s from re-requiring a half-initialized application (a symptom of the first, not a second problem). Why: `load_defaults 7.2` sets the config key to `:offset` (`railties configuration.rb:119`, the `"5.0"` block); the `active_support.set_configs` initializer (`railtie.rb:125–130`) forwards every `config.active_support` key to the writer; the writer warns for any value but `:zone` (`active_support.rb:124–128`); and railtie initializers run before the application's `load_config_initializers` (`application.rb:609` puts the application last in `ordered_railties`; `engine.rb:644`), so the shim's `:zone` arrives only at `after_initialize` (`railtie.rb:99–103`), after the warning. In production (`:notify`) the same early forward would send a `RailsDeprecation` to Honeybadger on every process boot. The 8.0.2 fix §4.3 cites ("Fix setting `to_time_preserves_timezone` from `new_framework_defaults_8_0.rb`") added the late forward; it did not stop the early one.

The line in **`config/application.rb`, directly under `config.load_defaults 7.2`**, is evaluated before any initializer. Test boot then prints `8.0.5.1`, `:zone`, `:zone`; with the shim's line uncommented as well it still boots (redundant); with the application.rb line set to `:offset` the boot raises exactly as above (the deliberate break; pasted again at implementation). The environment files would also be early enough (`load_environment_config` runs before `load_environment_hook`, `engine.rb:565`) but are three rejected files.

**What `:zone` does on 8.0.5.1** (probe copy, development runner):

```
S8 2026-11-02 10:00: to_s=2026-11-02 10:00:00 -0800 class=Time zone=#<ActiveSupport::TimeZone … @name="Pacific Time (US & Canada)" …> zone.class=ActiveSupport::TimeZone strftime_Z="PST" utc_offset=-28800 dst=false
slice 1 example 2026-10-23 10:00: to_s=2026-10-23 10:00:00 -0700 … strftime_Z="PDT" utc_offset=-25200 dst=true
arith across DST end: 2026-10-31 10:00:00 -0700 + 2.days => 2026-11-02 10:00:00 -0800 utc_offset=-28800
```

`TimeWithZone#to_time` is `getlocal(time_zone)` under `:zone` (`time_with_zone.rb:493–495`), so **`Time#zone` returns the `ActiveSupport::TimeZone` object, not `"PST"`**; the abbreviation is `strftime('%Z')`. §4.3's spec plan and its S8 second line (`t.zone.inspect` → `"PST"`) are corrected below. On 7.2.4 today (`master`, the `:offset` semantics): `2026-11-02 10:00:00 -0800`, `zone=nil`, `strftime('%Z')` → `""`, and `2026-10-31 10:00 -0700 + 2.days` → `2026-11-02 10:00:00 -0700` (a fixed offset, one hour off the wall clock after DST ends). Slice 1's offset example (`-25_200` for 2026-10-23) stays green under `:zone`.

**On 7.2.4 a `:zone` value is inert**: the writer warns only `unless value` (`activesupport-7.2.4 active_support.rb:117–122`) and every `to_time` branches on truthiness (`time_with_zone.rb:485–491`, `date_time/compatibility.rb:16`, `time/compatibility.rb:14`). Runner on `master` with the deprecator on `:stderr`: set `:zone`, `to_time` → `-0800`, `zone=nil`, no warning printed. So the config commit can land before the bump and leave 7.2.4 unchanged.

**Routes.** On 8.0.5.1 the route set raises at load:

```
Route `resources :carts` - :only and :except must include only [:index, :create, :new, :show, :update, :destroy, :edit], but also included [:request_shoot] (ArgumentError)
```

`actionpack-8.0.5.1 routing/mapper.rb:1182–1186` (absent on 7.2.4; CHANGELOG 8.0.0.rc1 "Raise an `ArgumentError` when invalid `:only` or `:except` options are passed into `#resource` and `#resources`"; 8.0.2 adds the resource name to the message). Two sites: `config/routes.rb:6` `only: %i[show update destroy create request_shoot]` and `:19` `only: %i[create update destroy upload_url]`. Both custom actions are declared in the `member do` blocks (`:11` `post 'request_shoot'`, `:21` `get 'upload_url'`), so the symbols were ignored on 7.2. With the two symbols removed, `bin/rails routes` prints **583 lines on both versions, byte-identical** (`routes-7-2.txt` and `routes-8-0.txt` in the scratchpad); the full route set, internal routes included, differs only by `GET /rails/info/notes` (internal, development-only, added by 8.0). `recognize_path` on 8.0.5.1: `/carts/1/request_shoot` POST → `{format: "json", controller: "carts", action: "request_shoot", id: "1"}`; `/headshots/1/upload_url` GET → `{controller: "headshots", action: "upload_url", id: "1"}`. No request or routing spec touches either path (grep: `request_shoot` appears in three model specs only). Production eager-loads routes at boot, so without this change the slice 2 release would not boot; in test the routes load lazily, so every request spec would fail instead.

**The suite on 8.0.5.1** (probe copy: Gemfile and lock at 8.0.5.1, the `:zone` line in application.rb, the shim all commented, the two route symbols removed; nothing else changed):

```
2040 examples, 1 failure      (55.6 s)        CI=1: 2040 examples, 1 failure      (59.2 s)

rspec ./spec/architecture/rails_upgrade_spec.rb:19 # Rails upgrade contract to_time preserves the receiver offset (§4.2 item 2) leaves the load_defaults value in place
     expected true
          got #<Symbol:5513484> => :zone
```

`grep -c "DEPRECATION WARNING"` → `0` in both runs; the 24 rack `:unprocessable_entity` warnings unchanged. The one failure is slice 1's example pinning `true`, which this slice rewrites to `:zone`. So no autosave-narrowing, `.or`-merge, HWIA, enum or `has_secure_password` change reaches a spec; the four R3 boundary specs and P4, P5 and P7 are inside the run. `bin/rails zeitwerk:check` on 8.0.5.1 → "all is good" (the `lib/` notice as on `master`). The two one-second flakes (`account_classification_rake_spec.rb:156`, `calculator_spec.rb:965`) did not fire in either run.

**P3 on 8.0.5.1** (probe copy, `bundle exec sidekiq -c 1 -q slice2_p3 -e development`, Redis `redis:6379`): `Booted Rails 8.0.5.1 application in development environment`; property 1964 enqueued with `.set(queue: "slice2_p3")` → `start` → `[PropertyDataLookupWorker] Property#1964 already has property data, skipping` → `done` (0.228 s). `Sidekiq::Status::status(jid)` → `nil` (§8 item 10, recorded). Sidekiq 7.3.10's railtie boots on 8.0.5.1 — §3.1's UNVERIFIED, now verified in development; production is S2.

**Key collisions (§4.3's `transform_keys` item).** Neither app path calls `HashWithIndifferentAccess#transform_keys!`, the method 8.0.3 changed: `lib/app_param.rb:8–16` deletes and reinserts keys; `json_param_key_transform.rb:5` calls `Hash#deep_transform_keys!` on the plain `Hash` that `ActiveSupport::JSON.decode` returns. `core_ext/hash/keys.rb` is identical on 7.2.4 and 8.0.5.1 (`diff`). Probes, identical on both versions: `{"fooBar"=>1, "foo_bar"=>2}` and the reverse order both give `{"foo_bar"=>1}` through `deep_transform_keys!`, `AppParam.deep_underscore_params` and the JSON parser (the camelCase value wins in either order, because the delete-and-reinsert clobbers the snake-case entry); only a direct `HWIA#transform_keys!` shows a precedence (`2` camel-first, `1` snake-first), and it shows the same on 7.2.4 because `transform_keys!` is `replace(transform_keys)` on both (`hash_with_indifferent_access.rb:354–364` / `:350–362`). No app behaviour changes; §4.3's "resolves to the later key" sentence is corrected in v5.

**CHANGELOG checks against the installed 8.0.5.1** (first sentences): Active Record 8.0.2 "Fix autosave associations to no longer validated unmodified associated records." (`autosave_association.rb:332, 346, 377` guard on `changed_for_autosave?`) — the 52 `CrudAttribution` models are the exposure; the suite is the detector and is green. AR 8.0.3 "Fix `#merge` with `#or` or `#and` and a mixture of attributes and SQL strings resulting in an incorrect query." — the 10 `.or(` sites; green. AR 8.0.4 "Fix invalid records being autosaved when distantly associated records are marked for deletion." AR 8.0.1 "Fix `insert_all` to not update existing records." — the one `upsert_all` is not `insert_all`. AR 8.0.0.rc1 enum keyword removal — positional here. Action Pack 8.0.3 "Address `rack 3.2` deprecations warnings." — the 24 warnings are rspec-rails' own and stay. Railties 8.0.2 "Use `secret_key_base` from ENV or credentials when present locally." — no `secret_key_base`, `message_verifier` or `cookies` use in `app/`, `lib/`, `config/` (grep; comments only). Active Storage 8.0.5.1 "Disable libvips's unfuzzed image loaders and savers." (CVE-2026-66066; raises at boot only when `ruby-vips` is installed — it is not) and 8.0.4.1's `DirectUploadController`/`DiskService` fixes (unreachable, routes off). `ActiveRecord::Base.connection` → `PostgreSQLAdapter`, silent: the deprecation fires only when `permanent_connection_checkout` is `:deprecated` (`connection_handling.rb:275–282`); it is `true`. Under `load_defaults 7.2` on 8.0.5.1: `action_dispatch.strict_freshness` → `false`, `Regexp.timeout` → `nil`, `loaded_config_version` → `7.2` — the values the contract spec pins until slice 5.

**§4.3 items 3–5, evidence:** no `solid_*`, `kamal` or `thruster` in the lock (notes) and none offered by the update (table above); `cache_store` `:null_store` in dev and test (runner), unset in production (`production.rb:64` commented); `Procfile:2` Sidekiq on Redis; `permanent_connection_checkout=true` (runner, both versions).

### What the survey changes

1. **`:zone` is set in `config/application.rb`, not in the shim.** The shim cannot do it under `:raise` (boot evidence above) and would send a `RailsDeprecation` per boot in production. The prompt's out-of-scope item 2 names `config/application.rb`, but that item is about the regenerated template, which stays rejected. Open question 1.
2. **A routes change joins the slice** (`config/routes.rb:6, :19`), as its own first commit; not in §4.3's breaking-change list. Open question 2.
3. **The three Active Storage migrations are neither copied nor deleted.** They predate the slice; deleting tracked, already-run migrations is a `db/migrate` change no slice carries. §4.3's row, the prompt's trap 1 and the notes row are corrected. Open question 4 confirms.
4. **`Time#zone` is a `TimeZone` object on 8.0.5.1**; `"PST"` is `strftime('%Z')`. The spec plan and S8 are rewritten below.
5. **`config/puma.rb` is not comment-only** → rejected by §4.3's own rule. **`bin/setup`** → reject recommended (open question 3).
6. **The commit order changes**: the `:zone` line must precede the bump (the bump alone cannot boot in test), it is inert on 7.2.4, so it is commit 2 and the bump is commit 3; §4.3 had the flip last.
7. Cosmetic corrections for v5: the application.rb template keeps `load_defaults 7.2`; `assets.rb` is created and removed; the lock drops `cgi`/`racc` and adds a `uri` line; `CrudAttribution` lives in `lib/`; `spec/lib/tasks/marketing_source*` does not exist; the `transform_keys` precedence claim.
8. The deploy moves from Mon 11-02 (§6) to Wed 10-28; slice 1's design-document write-back is still owed and rides in v5 (open question 5).

No STOP on the prompt's four gaps. Items 1 and 2 are the decisions that need Dan before implementation starts.

---

## Phase 1 — plan

### Gaps pinned (the prompt's four)

1. **The `app:update` diff shape** — pinned by the table above. Nothing outside §4.3's table except `assets.rb`, created and removed inside the run. No STOP.
2. **The `Time#zone` string** — there is none. `to_time.zone` is `ActiveSupport::TimeZone['Pacific Time (US & Canada)']`; the spec pins the zone object, `strftime('%Z') == 'PST'`, `utc_offset == -28_800` and `dst? == false` for 2026-11-02 10:00, plus the DST-crossing arithmetic. S8 prints `t`, `t.strftime("%Z")` and `t.zone.class`.
3. **Which `transform_keys` variant** — neither app path uses `HWIA#transform_keys!`; `keys.rb` is identical across the versions; the probes are identical on both. Rule: no code change and no new spec; the `spec/requests/accounts_*` specs run inside P1 as the boundary (all passed on 8.0.5.1).
4. **`--force`** — accepted (`add_runtime_options!`). The interactive `a` route is not needed.

### Decisions beyond the gaps

- **Where the flip lives.** `config/application.rb:13`, one line directly under `config.load_defaults 7.2`, with a why-comment: 8.0 forwards the `load_defaults` value before `config/initializers` run, so under `:raise` the shim's line is too late (§4.3 gap 1 as amended in v5). The shim is committed exactly as generated, all three lines commented, so slices 5a and 5b keep their file. **Slice 3's survey decides whether the application.rb line is deleted, kept or replaced** (modification F; §4.4 item 3 and its trap 1 are reworded in v5 — how 8.1 treats the config is slice 3's finding). Alternatives rejected: the shim (does not boot); the three environment files (three rejected files for one value); an app initializer ordered `before: "active_support.set_configs"` (more code than one line, and `set_configs` is an implementation detail).
- **Routes commit first**, on 7.2.4, where it is a no-op (route table identical before and after); the body names 8.0.0.rc1's validation and quotes the 8.0 error. Alternative rejected: folding it into the bump (mixes a code fix with a gem bump, and the bump commit should show the 8.0 raise as its own evidence).
- **`bin/setup` and `config/puma.rb` rejected**, as above. **`bin/rails`, `bin/rake` accepted** (quotes only).
- **Contract spec additions** (`extend, do not restructure`; one `describe` per section): slice 1's `be(true)` example becomes `eq(:zone)` with its comment rewritten for 8.0; the version floor moves to `8.0.5.1`; new examples below. The "other 8.0 defaults still off" example pins `strict_freshness` `false`, `Regexp.timeout` `nil` and `loaded_config_version` `7.2` — slices 5a and 5b rewrite it when they flip them; until then it is the prompt's trap 2 and trap 4 as a spec.
- **P1 runs twice**: plain (the count of record, comparable with slice 1's 2,040) and `CI=1` (eager load on; §8 item 19's candidate, adopted from this slice on because a class-body deprecation in an untouched class is exactly what a major bump produces). Both recorded; both must be `0 failures`, `0` deprecation lines.
- **P3** on its own queue (`slice2_p3`), exactly as run in the survey: a `bin/dev` Sidekiq on `default` may be running.
- **P-PROD**: slice 1's production-config probe (runbook step 2's `dotenv` wrapper) rerun on the branch with two lines added — `p ActiveSupport.to_time_preserves_timezone` and `p Rails.application.config.loaded_config_version`. It is also the only production-mode boot of 8.0.5.1 before the push: eager load on, routes drawn, the deprecators still `[:notify]`.
- **Runbook** `docs/runbooks/deploy-rails-upgrade-2.md` in slice 1's shape (Summary, Where the commands run, Deploy window, Prerequisites, Pre-deploy, Deploy, Within 30 minutes, One hour, 24 hours, Rollback, Known, After the deploy, Deploy log); S7 and SH as slice 1's runbook amended them (saved buffer and Papertrail hour; compare by Honeybadger error). `Draft` in this session, `Ready` after the review. Its Deploy window section states the §6 slippage rule (decision 6): review and merge not complete by 09:00 PT → the deploy moves to Mon 11-02 and slice 3 loses that slot; nobody pushes after 11:30 to make the window. Its Prerequisites carry the one-line slot for slice 1's SH result (closes 05:15 PT).
- **Branches**: insgt-api `chore/rails-upgrade-slice-2` off `master` 473e2747; platform `docs/rails-upgrade-slice-2`. Dan merges both. If `master` moves before the push, the suite runs on the merge first (slice 1's practice).
- **Codex review** on an rsync copy without `.git` and `.env` (slice 0/1 practice), two rounds; findings folded into the commit they belong to on the unpushed branch with `--autosquash`.

### Approach, one unit of work per commit

**1. `fix: drop the custom actions from the carts and headshots route filters`** — contract example first: "the two member routes are drawn" (`recognize_path` for both paths; green on 7.2.4 already — it guards the routes, which the change must not lose, not the symbols). Remove `request_shoot` from `routes.rb:6` and `upload_url` from `:19`. `bin/rails routes > after.txt`; `diff` against the before → empty. Deliberate break: comment out `post 'request_shoot'` (`:11`) → `ActionController::RoutingError`, red; restore. Body: the 8.0.0.rc1 validation, the error message 8.0 prints, and one sentence on why the example lives in the architecture spec rather than `spec/routing/` (modification C). The 8.0 red itself is commit 3's evidence.

**2. `fix: preserve the receiver zone in to_time`** — contract example first: `ActiveSupport.to_time_preserves_timezone` `eq(:zone)` (red on 7.2.4: `true`). Add `config.active_support.to_time_preserves_timezone = :zone` under `load_defaults 7.2` with the why-comment; green. Behaviour on 7.2.4 is unchanged (source and probe above); the body says the behaviour arrives with the next commit, and why the line must precede it (8.0's early forward; `:raise`). Deliberate break: delete the line → red (`true`). `bundle exec rspec` → 2,040 plus the new examples, 0 failures, 0 deprecation lines, still on 7.2.4. [§4.3's tier 3, trigger 4: a default flipped before slice 5, and why the alternatives were worse.]

**3. `build: upgrade rails to 8.0.5.1`** — contract examples first: the floor `>= 8.0.5.1` (red on 7.2.4), the zone examples (red on 7.2.4: `zone` `nil`, `%Z` `""`, `+ 2.days` → `-25_200`). `Gemfile:29` → `'~> 8.0.5'`; `bundle update rails --conservative`; `git diff Gemfile.lock` must equal the scratch diff line for line (a difference is a STOP); green. Evidence pasted in the commit's loop: (a) with `request_shoot` temporarily restored in `routes.rb:6`, `bundle exec rspec` → the `ArgumentError` at route load; (b) with the application.rb line temporarily `:offset`, the boot raise; (c) the deliberate break for the zone examples without touching boot: `DateAndTime::Compatibility.preserve_timezone = :offset` inside an `around` → red, restored by the `ensure` — **first confirmed on 8.0.5.1 to fail the expectation and not raise a `DeprecationException`** (modification A; otherwise the stub variant), with the commit body recording which was used. Floor break: `8.0.6` → red. Then `bundle exec rspec` (0 failures, 0 deprecation lines), `CI=1 bundle exec rspec`, `bin/rails zeitwerk:check`, `bin/rails routes` diff against the 7.2.4 capture (empty).

**4. `chore: apply the rails 8.0 app:update binstubs`** — `bin/rails` and `bin/rake` from the captured diff (quotes only); `bin/rails --version` → `Rails 8.0.5.1`; `bin/rake -T | head -1`. No spec.

**5. `chore: add the rails 8.0 framework defaults shim`** — the "other 8.0 defaults stay off" contract example first (green already; its break: uncomment `strict_freshness = true` in the shim → red; restore). Add the generated file verbatim; green. Body (tier 2): all three lines stay commented; the `to_time` flip is the application.rb line and why; the three Active Storage migrations predate this slice and were not re-copied; the rejected files in one line each, pointing at this plan's table.

Then once for the slice: P1 (twice) to P8 and P-PROD with `8.0.5.1`; the runbook as `Draft`; `predeploy-review-rails` twice; the verification STOP with the spot-check table filled from development and the pre-push captures listed for the Mac.

### Spec plan — boundary cases by name

`spec/architecture/rails_upgrade_spec.rb` (extended; `type: :model`):

| Section | Example | Pinned value | Deliberate break |
| :-- | :-- | :-- | :-- |
| §1.2 | the framework runs at least the version the document names for the latest slice | `Rails.gem_version >= Gem::Version.new('8.0.5.1')` | floor to `8.0.6` → red |
| §4.3 gap 1 | the `to_time` setting (rewrites slice 1's `be(true)`) | `ActiveSupport.to_time_preserves_timezone == :zone` | delete the application.rb line → `true` (7.2.4) / boot raise (8.0.5.1) |
| §4.2 item 2 | the Pacific offset (slice 1's example, unchanged) | `utc_offset == -25_200` for 2026-10-23 10:00 | — (stays green) |
| §4.3 | `to_time` keeps the receiver's zone | for `pacific.parse('2026-11-02 10:00').to_time`: `zone == ActiveSupport::TimeZone['Pacific Time (US & Canada)']`, `strftime('%Z') == 'PST'`, `utc_offset == -28_800`, `dst?` false | `DateAndTime::Compatibility.preserve_timezone = :offset` in an `around` → `zone` `nil`, `%Z` `""` |
| §4.3, §5 R3 | arithmetic on the result follows DST | `(pacific.parse('2026-10-31 10:00').to_time + 2.days).utc_offset == -28_800` | same break → `-25_200` |
| §4.3 as built (routes) | the carts and headshots member routes are drawn | `recognize_path('/carts/1/request_shoot', method: :post)` → `carts#request_shoot`; `recognize_path('/headshots/1/upload_url', method: :get)` → `headshots#upload_url` | comment out `post 'request_shoot'` → `RoutingError` |
| §4.3 items 6 and gap 1; §4.6 | the other 8.0 defaults stay off until slice 5 | `config.action_dispatch.strict_freshness` `false`; `Regexp.timeout` `nil`; `config.loaded_config_version` `7.2` | uncomment `strict_freshness = true` in the shim → red |

Existing coverage, run by name inside P1 and reported: `spec/requests/accounts_*` (parameter key handling — 11 files), `spec/models/order_spec.rb` and `spec/models/order_log_spec.rb` (autosave narrowing), the four R3 boundary specs (`orders_processing_release_on_spec.rb`, `accounts_most_recent_shoot_spec.rb`, `marketing_events_rake_spec.rb`, `account_csv_export_service_spec.rb`), P4 `postal_code_spec.rb -e nearby_cities` (4 examples), P5's four Stripe files, P7's three. All green on 8.0.5.1 in the survey run.

### Commit sequence

insgt-api, branch `chore/rails-upgrade-slice-2` (tiers per `git-commit-messages` in brackets):

1. `fix: drop the custom actions from the carts and headshots route filters` [2]
2. `fix: preserve the receiver zone in to_time` [3, trigger 4]
3. `build: upgrade rails to 8.0.5.1` [1]
4. `chore: apply the rails 8.0 app:update binstubs` [1]
5. `chore: add the rails 8.0 framework defaults shim` [2]

Platform repo, branch `docs/rails-upgrade-slice-2`: `docs: add the rails upgrade slice 2 runbook` (before the push); after verification `docs: amend the rails upgrade design to v5 for slice 2` (also recording slice 1's deploy and its S7/SH criteria — open question 5) and `docs: update the rails upgrade notes for slice 2`; after the deploy `docs: record the slice 2 deploy in the rails upgrade runbook`.

### Post-deploy verification

**Pre-deploy, on the branch** (§4.0 with `8.0.5.1`; reasoned now):

| # | Expected |
| :-- | :-- |
| P1 | `N examples, 0 failures` with the actual N reported (ESTIMATE 2,045; not a pass criterion — modification G); `grep -c "DEPRECATION WARNING"` → `0`; the 24 rack warnings unchanged. Then `CI=1 bundle exec rspec` → the same N, `0 failures`, `0` deprecation lines. The pass criteria are `0 failures` and `0` deprecation lines in both runs |
| P2 | `bin/rails zeitwerk:check` → "all is good" |
| P3 | own queue: `Booted Rails 8.0.5.1 application in development environment`, `start`, `…already has property data, skipping`, `done`; status `nil` recorded |
| P4 | 4 examples, 0 failures |
| P5 | 0 failures across the four files |
| P6 | `SystemError::rails upgrade` |
| P7 | 0 failures |
| P8 | `200`, `image/jpeg` via `Net::HTTP` |
| P-PROD | run with Honeybadger reporting off (`HONEYBADGER_REPORT_DATA=false` — modification B; `config/honeybadger.yml` and the initializer checked first for what the gem honours): prints `true`, `true`, `[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]`, `true`, then `:zone`, `7.2`; the boot itself (eager load, routes) succeeds; `grep -c DEPRECATION` over the whole output pasted (expected `0`: the probe's own `deploy probe` warning goes through `:notify`, not stderr) |
| Routes | `bin/rails routes` identical to the 7.2.4 capture (583 lines); `grep -c active_storage` → `0` |

**On the Mac, before the push** (on v662, so "unchanged" is provable):

```bash
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 't = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-11-02 10:00").to_time; puts t; puts t.strftime("%Z"); puts t.zone.class'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
curl -sS -o /tmp/s-rt-carts.txt -w "%{http_code}\n" -X POST https://api.insightphotos.net/carts/0/request_shoot; head -1 /tmp/s-rt-carts.txt
curl -sS -o /tmp/s-rt-headshots.txt -w "%{http_code}\n" https://api.insightphotos.net/headshots/0/upload_url; head -1 /tmp/s-rt-headshots.txt
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 2', 'release v662').deliver_now"
```

Expected before: `["Carlsbad", "Oceanside", "Leucadia"]` (slice 1's capture); `2026-11-02 10:00:00 -0800`, an empty line, `NilClass`; `7.2`; for both routes the unauthenticated status and the first body line (modification D; ASSUMPTION `401` with the API's JSON error body; whatever they print is the "before" — a `404` after the push means the route is gone, and the body line separates the auth layer from a generic rescue); the email arrives.

**Production spot checks, within 30 minutes of the push** (replace `<vNNN>` with the real release this time — slice 1's S0 and S6 went out with the placeholder):

| # | Command (from the Mac) | Expected |
| :-- | :-- | :-- |
| S0 | the marker runner with `slice 2` and the release | `UpgradeMarker` gains an occurrence, context `rails: 8.0.5.1` |
| S2 | `heroku ps`; `heroku logs --ps backgroundworker.1 -n 300 \| grep Booted` | `web.1`, `web.2`, `backgroundworker.1` up; `Booted Rails 8.0.5.1 application in production environment` |
| S3 | `rails runner 'puts Rails.version; puts ActiveSupport.to_time_preserves_timezone.inspect'` | `8.0.5.1`, `:zone` |
| S8 | the `to_time` runner above | `2026-11-02 10:00:00 -0800`, `PST`, `ActiveSupport::TimeZone` |
| S10 | `rails runner 'puts Rails.application.config.loaded_config_version'` | `7.2` |
| S-RT | the two `curl`s above (carts and headshots) | for both: the same status and first body line as the v662 captures; not `404` |
| S1, S4, S5, S6 | as §4.0 (S4 with `map`) | `200`; identical to the capture; `true`; `SystemError::rails upgrade slice 2` arrives |
| S7 | one hour after: the saved 1,500-line buffer (window, `status=5` count, exception classes) and Papertrail `status=5` for the hour | `0`; no class other than `ActionController::RoutingError` |
| S9 | the next hourly `import_listings` check-in | on time |
| SH | 24 h later, Honeybadger by error against the slice 0 baseline plus slice 1's S-DEP error | no new error whose backtrace touches the 13 gems, `config/`, the two routes or `to_time`; **no new `RailsDeprecation`** — one mentioning `to_time` would mean the early forward reached production (S3's `:zone` rules it out) |

**Rolling deploy**: no migration, no schema, no ENV change; a Heroku release swaps all dynos at once. **Build**: the first 8.x slug on this buildpack (§2.5 UNVERIFIED); a failed build never becomes a release, so v662 keeps running. **Rollback**: `heroku rollback` to v662; nothing to undo.

### Risks

- **R1, a gem at the major bump** — Sidekiq 7.3.10 boots on 8.0.5.1 (P3, pasted); jbuilder, lograge, oj, strong_migrations, string_utils, shoulda-matchers, rspec-rails and factory_bot all ran inside the green suite; honeybadger loaded in the probe boot (S0 proves it in production). What the container cannot prove: the Heroku build and the SendGrid/Stripe paths on 8.0 (S5, S6).
- **R3, the zone step** — the only behaviour change a human could see: a `Time` derived from a zoned value now carries the zone, so arithmetic across 2026-11-01 keeps the wall clock (`-0800` after the change, `-0700` before). No `.to_time` in `app/` or `lib/`; the four boundary specs pass; S4, S6, S8 are the production reads; the symptom in the wild has no exception (§5).
- **The routes change** — a no-op on 7.2.4 and byte-identical on 8.0.5.1; the contract example and S-RT guard the two member routes. Risk nil beyond a typo, which the route diff catches.
- **Autosave narrowing and the `.or` merge fix** — the suite is green with no SQL-capturing spec changed, but coverage is what it is: a save that *used to fail* because an untouched associated record was invalid now succeeds (8.0.2). The detector in production is SH (fewer `RecordInvalid`, never more).
- **A gem-originated deprecation under `:raise`** (OD8) — none fired in 2,040 examples, eager-loaded or not; a production-only path would surface as `RailsDeprecation` in SH and is a STOP for slice 3.
- **Timing** — the push window is 09:00–11:30 PT; slice 1's SH closes 08:15 ET; the slice 0 and slice 1 Honeybadger lists are the SH baseline. If the branch is not merged and reviewed by the window, the deploy slips to the next Mon–Wed morning (§6 slippage rule), still ahead of 11-07.

### Open questions for the engineer

1. **`:zone` in `config/application.rb`** (one line under `load_defaults 7.2`) rather than in the shim — a deviation from §4.3 item 2's table and the prompt's out-of-scope item 2. The shim does not boot under `:raise` (evidence above). Recommend yes. **Answered: yes** (slice 3's survey decides the line's fate — modification F).
2. **The routes commit** (`routes.rb:6, :19`, two symbols removed; route table identical). Not in §4.3. Recommend yes, first in the sequence. **Answered: yes.**
3. **`bin/setup`**: reject (recommended — its tail execs the rejected `bin/dev`) or accept the template as §4.3's table says, knowing `bin/setup` without `--skip-server` ends in `Errno::ENOENT`. **Answered: reject.**
4. **The three pre-existing Active Storage migrations stay** in `db/migrate/` (tracked since 2026-01-29, run in production). Recommend yes; the review must not flag them under the prompt's trap 1. **Answered: yes.**
5. **v5 of the design document**: fold slice 1's owed write-back (deployed as v662; the S7/SH criteria; §4.0 S4 `map`) into this slice's amendment after verification, or write a separate v5 for slice 1 before the push and v6 for slice 2. Recommend the fold: one version, written once, before the deploy morning. **Answered: fold, with a one-line slot for slice 1's SH result (closes 05:15 PT), filled before the push.**
6. **Tonight?** With the survey done and the suite already green on the probe copy, implementation is ESTIMATE 3–4 h plus the review rounds and the runbook. Confirm the branch is to be built tonight so the review is done before the 09:00 PT window. **Answered: tonight; the slippage rule goes in the runbook's Deploy window section.**

### Unverified

- Heroku's Ruby buildpack building an 8.0.5.1 slug (§2.5); the release is the proof. Modification E: the branch is pushed to a scratch Heroku app or review app tonight if one exists for `insgtapi`; the survey of the README and docs decides whether one does (recorded in the runbook).
- `.env` and `SECRET_KEY_BASE`: the anchored grep for `^SECRET_KEY_BASE=` found 0 lines; the notes row says `.env` sets it; the file was not re-read. Inert either way (no `secret_key_base`, verifier or cookie use in app code).
- The unauthenticated production status of `POST /carts/:id/request_shoot` (in the container the integration session is stopped by host authorization, `403`); captured on v662 before the push.
- `Sidekiq::Status` middleware in production (§8 item 10).
- Honeybadger on 8.0.5.1 beyond loading without error in the probe boot; S0 is the proof.
- Slice 1's SH result (due 2026-10-28 08:15 -0400).
- Which account the Papertrail UI's times are in (slice 1's open item; the S7 hour uses the UI as is).

### Next phase, if approved

The implementation loop, commits 1 → 5 as above, each red → green → deliberate break → lint → area suite → commit; then P1 (twice) to P8 and P-PROD, the runbook as `Draft`, the two-round `predeploy-review-rails`, and the verification STOP with the spot-check table filled in from development and the pre-push captures listed for the Mac. The scratchpad copies (`api-7-2`, `api-8-0`, `api-8-0-probe`, the route tables and logs) stay for the session as the reference diffs.
