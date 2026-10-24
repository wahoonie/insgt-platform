# Rails upgrade — slice 3: 8.1.4, the landing target

**Repo:** `insgt-api`. No changes elsewhere.
**Contract:** `docs/architecture/rails-upgrade.md` (platform repo, `/workspace/docs/architecture/`) §4.4, §4.0, §2, §3, §1.3. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

1. §4.4 item 1: `rails` `'~> 8.1.4'` (8.1.4 is the floor; never 8.1.0–8.1.3) and the lock diff §4.4 expects.
2. §4.4 item 2: `app:update --force` on a throwaway branch, §4.3's table with the 8.1 deltas (accept the 8.1 shim; reject `config/ci.rb` and `bin/ci`).
3. §4.4 item 3: delete the `:zone` line from the 8.0 shim.
4. §4.4 item 4: the `db/schema.rb` re-dump from a clean test database loaded from the committed file (OD7); header-only → commit, else STOP.
5. §4.4's breaking-change list traced with `file:line` — the two `head` sites, the `.or` merges, `remote_ip`, `/up.json`; the spec plan and post-deploy verification (S11); `docs/runbooks/deploy-rails-upgrade-3.md`. Deadline: deployed before Sat 2026-11-07 (§1.3).

## Out of scope — do not touch

1. Every flag in `new_framework_defaults_8_1.rb`; `config.load_defaults`.
2. The `.or` sites' SQL (observe and explain changed counts; do not rewrite); `belongs_to` (slice 4).
3. `config/ci.rb`, `bin/ci`, `rails/all`, any gem beyond `rails`, the rejected environment files.
4. A dump taken from the development database.

## Prerequisites

Slice 2 deployed: `Rails.version` → `8.0.5.1` and `loaded_config_version` → `7.2` in a production runner; §4.3's commits on `master`; SH clean since slice 2.

## Gaps the plan must pin

1. The schema diff outcome: header-only is the only commit; a `limit:` on any `t.float` column (`db/schema.rb:903, 970, 972`) is a STOP (§4.4 gap 1).
2. The two `head`-after-render traces (`application_controller.rb:303`, `orders_controller.rb:597`): reachable after a `render_*` or not, with the spec that proves each (§4.4 gap 2).
3. The deliberate-break evidence for the removed `:zone` line: the boot-time deprecation raise, pasted.
4. The `.or` search request specs' before/after counts, if any changed.

## Traps for the review

1. A `to_time` config line of any value surviving on 8.1; a `config.active_support.to_time_preserves_timezone` reference anywhere.
2. `config/ci.rb` or `bin/ci` committed; a copied Active Storage migration; a regenerated `config/environments/*`.
3. A `db/schema.rb` diff beyond the header, or one produced from the development database.
4. An opportunistic refactor in an upgrade commit; a gem major bump not named in §3; a `config.load_defaults` change outside slice 5; any edit to `StrongMigrations.target_version`; a Ruby version change; a Postgres version change.

## Commit sketch

§4.4's commits: `build: upgrade rails to 8.1.4` · `chore: apply the rails 8.1 app:update binstubs` · `chore: add the rails 8.1 framework defaults shim` · `chore: drop the to_time config rails 8.1 ignores` · (`fix: return before head on …` if found) · (`chore: re-dump schema.rb under rails 8.1` if header-only).

## Gates

After plan; after verification.

## Reference pattern

`spec/architecture/rails_upgrade_spec.rb` as slice 2 left it. Runbook: `docs/runbooks/deploy-rails-upgrade-2.md`.
