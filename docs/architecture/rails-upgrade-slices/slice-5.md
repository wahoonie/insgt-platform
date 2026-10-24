# Rails upgrade — slice 5: framework defaults, then `config.load_defaults 8.1`

**Repo:** `insgt-api`. No changes elsewhere.
**Contract:** `docs/architecture/rails-upgrade.md` (platform repo, `/workspace/docs/architecture/`) §4.6, §4.0, §2, §5, §6. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

Two deploys, §4.6: **5a** rows 2–3 of the flag table (`strict_freshness`, `Regexp.timeout`) in the 8.0 shim, deployed alone and watched across one full `import_listings` cycle; **5b** rows 4–10 in the 8.1 shim, the five shim files deleted, `config.load_defaults 8.1`, the contract spec pinning `loaded_config_version`, `Regexp.timeout` and the JSON escaping behaviour. Each deploy gets its own runbook (`deploy-rails-upgrade-5a.md`, `-5b.md`) and §4.6's post-deploy checks (S10, S14–S16).

## Out of scope — do not touch

1. Anything `belongs_to` (slice 4 did it; 5b touches no association).
2. `rails/all` (§8 item 7), every other §8 item, any gem.
3. Flipping a flag by any route other than the generated shim lines, before the `load_defaults` bump.

## Prerequisites

Slice 4 deployed and quiet (§2.2) for one weekday: `Rails.version` → `8.1.4`, `loaded_config_version` → `7.2` in a production runner; both 8.x shim files present with every line commented except none; SH clean since slice 4. For 5b: 5a deployed and one import cycle observed with no `Regexp::TimeoutError` (§4.6 gap 2).

## Gaps the plan must pin

1. The import cadence, from `lib/tasks/scheduler.rake` and the `import_listings` check-in history (§4.6, §6): if less than daily, 5b and the rehearsal each slip a week — say so at the plan gate.
2. The row 5 proof: the `render_errors` request spec with a `<b>` message and the JBuilder spec that stays escaped (§4.6 gap 1), with the deliberate-break output.
3. The exact `Regexp.timeout` value the runner prints after 5a (`1.0` expected, §4.6).
4. The final content of `config/application.rb` after the bump: only `load_defaults 8.1`, `draw_routes = false` (slice 1) and what was there before.

## Traps for the review

1. A flag flipped in the wrong deploy (any 8.1 row in 5a; `Regexp.timeout` in 5b).
2. A shim file surviving 5b, or `belongs_to_required_by_default` reappearing when `new_framework_defaults.rb` is deleted.
3. A client-facing byte change asserted as "identical" without the parsed-value spec.
4. An opportunistic refactor; a gem major bump not named in §3; a `config.load_defaults` value other than `8.1`, or bumped before 5b; any edit to `StrongMigrations.target_version`; a Ruby version change; a Postgres version change.

## Commit sketch

§4.6's four commits: `chore: enable the rails 8.0 request freshness and regexp timeout defaults` (5a) · `chore: enable the rails 8.1 framework defaults` · `chore: load the rails 8.1 defaults and remove the shim files` · `test: pin the rails upgrade invariants in the contract spec` (5b).

## Gates

All.

## Reference pattern

`spec/architecture/rails_upgrade_spec.rb` as slice 4 left it; `docs/runbooks/deploy-rails-upgrade-4.md` for the two runbooks.
