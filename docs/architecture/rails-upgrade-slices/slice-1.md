# Rails upgrade — slice 1: 7.2.4, the deprecation gate, routes off, production deprecation reporting

**Repo:** `insgt-api`. No changes elsewhere.
**Contract:** `docs/architecture/rails-upgrade.md` (platform repo, `/workspace/docs/architecture/`) §4.2, §4.0, §2, §3, §5 R3. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

1. §4.2 item 1: `rails` `'~> 7.2.4'` and the lock diff exactly as §4.2 expects (the minitest downgrade included).
2. §4.2 item 2: delete `config/initializers/new_framework_defaults.rb:15–17`.
3. §4.2 item 3: `config/environments/test.rb:58` → `:raise`.
4. §4.2 item 4: `config.active_storage.draw_routes = false`, the routes assertion, the 404 request spec, and the pre-deploy log-history grep with its stated reach (Heroku buffer, then Papertrail if `heroku addons` shows it).
5. §4.2 item 5: `production.rb:83` → `report_deprecations = true`, `deprecation = :notify`, the production-only subscriber and `DeprecationReporter`.
6. §4.2 item 6: `spec/architecture/rails_upgrade_spec.rb` with the slice 1 invariants; `docs/runbooks/deploy-rails-upgrade-1.md`.

## Out of scope — do not touch

1. The 24 `:unprocessable_entity` spec symbols (§8 item 1) — rack warnings, not deprecations.
2. Any other initializer line, including the CSRF and `belongs_to` lines of the same shim file (slices 4 and 5).
3. The OD8 callable deprecation behaviour — only if an exemption is needed, and none is.
4. `rails/all`, `config.load_defaults`, any other gem.

## Prerequisites

Slice 0 deployed: S0 produces an `UpgradeMarker` occurrence; the Honeybadger project shows the test notice. `Rails.version` → `7.2.3` in a production runner; `master` at eda99450 or a descendant with a green suite.

## Gaps the plan must pin

1. `date +%z` in the container (the deliberate break for the `to_time` offset example depends on it being `+0000`, §4.2 spec plan).
2. The oldest searchable timestamp of the log history the Active Storage grep covered (§4.2 item 4) — a date, not "the buffer".
3. The first-non-gem-frame rule the reporter uses for `callstack` context, and its spec.
4. Whether `bundle update rails --conservative` needs `minitest` named (§4.2 item 1).

## Traps for the review

1. A `to_time` value other than the one §4.2 names (the effective `true`); any `config.active_support.to_time_preserves_timezone` line added.
2. A regenerated or hand-edited `config/environments/*` beyond the two production lines and the one test line.
3. The reporter notifying more than once per message per process, or notifying outside production.
4. An opportunistic refactor in an upgrade commit; a gem major bump not named in §3; a `config.load_defaults` change outside slice 5; any edit to `StrongMigrations.target_version`; a Ruby version change; a Postgres version change.

## Commit sketch

§4.2's five commits, in order: `build: upgrade rails to 7.2.4` · `fix: stop forcing the pre-Ruby 2.4 to_time behavior` · `test: raise on deprecations in the test environment` · `chore: stop drawing the unused Active Storage routes` · `feat: report production deprecations to honeybadger once per message`.

## Gates

After plan; after verification.

## Reference pattern

`spec/architecture/account_classification_spec.rb` for the contract spec's shape (one `describe` per document section, canonical fixtures, pinned integers). Runbook: `docs/runbooks/deploy-headshot-event-date.md`.
