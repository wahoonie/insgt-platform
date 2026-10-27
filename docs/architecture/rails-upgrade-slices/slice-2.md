# Rails upgrade — slice 2: 8.0.5.1, transit only

**Repo:** `insgt-api`. No changes elsewhere.
**Contract:** `docs/architecture/rails-upgrade.md` (platform repo, `/workspace/docs/architecture/`) §4.3, §4.0, §2, §3, §5 R1. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

1. §4.3 item 1: `rails` `'~> 8.0.5'` and the lock diff §4.3 expects.
2. §4.3 item 2: `app:update --force` on a throwaway branch, the full diff captured as plan evidence, then the accept/reject/delete table applied file by file — including deleting the three copied Active Storage migrations. **v5, as built:** run on an rsync copy (the classifier declines a throwaway branch); no migration was copied — the three predate the slice and stay; `puma.rb` and `bin/setup` rejected too (§4.3 "as run").
3. §4.3 items 3–6: the explicit "no action" findings for Solid Queue/Cache/Cable, Kamal/Thruster and connection handling, recorded in the plan with the evidence §4.3 cites; `load_defaults` stays `7.2`.
4. §4.3 gap 1: `to_time_preserves_timezone = :zone` uncommented in the generated 8.0 shim — the one default flip, with the reason §4.3 gives. **v5, as built:** the flip lives in `config/application.rb`, directly under `load_defaults 7.2` (the shim cannot do it under `:raise` — §4.3 gap 1); the shim is committed with every line commented.
5. §4.3's spec plan (version floor `8.0.5.1`, the zone example, the named boundary specs) and post-deploy verification (S8 zone print, S10); `docs/runbooks/deploy-rails-upgrade-2.md`.

## Out of scope — do not touch

1. Every other line of `new_framework_defaults_8_0.rb`; `config.load_defaults`.
2. `config/application.rb`, `config/environment.rb`, `config/environments/*`, `cors.rb`, `filter_parameter_logging.rb` — rejected in §4.3's table. **v5:** the one config line `config.active_support.to_time_preserves_timezone = :zone` in `config/application.rb` is in scope (§4.3 gap 1 as built); the regenerated template stays rejected.
3. The ~25 `Model.connection` sites (§8 item 8); `rails/all`; any gem beyond `rails`; `config/ci.rb` (an 8.1 artefact).

## Prerequisites

Slice 1 deployed: `Rails.version` → `7.2.4` in a production runner; §4.2's five commits on `master`; the suite green with `:raise`; SH shows no `RailsDeprecation` since slice 1.

## Gaps the plan must pin

1. The `app:update` diff shape: a generated file absent from §4.3's table is a STOP with the diff pasted (§4.3 gap 2).
2. The exact `Time#zone` string on 8.0.5.1 for the Pacific example before the spec pins `"PST"` (§4.3 spec plan).
3. Which `transform_keys` variant `json_param_key_transform.rb:2–6` and `AppParam.deep_underscore_params` use, against the 8.0.3 precedence change.
4. Whether `--force` is accepted by `bin/rails app:update`; otherwise the interactive `a` route on the throwaway branch.

## Traps for the review

1. Any file from the reject rows of §4.3's table changed; any copied Active Storage migration surviving in `db/migrate/`. **v5:** the three Active Storage migrations already in `db/migrate/` predate the slice and stay — not a finding.
2. A `to_time` value other than `:zone`; a second flag flipped in the 8.0 shim.
3. A spec whose captured SQL changed without the change being explained (the `.or` sites, the autosave narrowing).
4. An opportunistic refactor in an upgrade commit; a gem major bump not named in §3; a `config.load_defaults` change outside slice 5; any edit to `StrongMigrations.target_version`; a Ruby version change; a Postgres version change.

## Commit sketch

§4.3's four commits: `build: upgrade rails to 8.0.5.1` · `chore: apply the rails 8.0 app:update binstubs` · `chore: add the rails 8.0 framework defaults shim` · `fix: preserve the receiver zone in to_time`. **v5, as built — five, in this order:** `fix: drop the custom actions from the carts and headshots route filters` · `fix: preserve the receiver zone in to_time` · `build: upgrade rails to 8.0.5.1` · `chore: apply the rails 8.0 app:update binstubs` · `chore: add the rails 8.0 framework defaults shim`.

## Gates

After plan; after verification.

## Reference pattern

`spec/architecture/rails_upgrade_spec.rb` as slice 1 left it; extend, do not restructure. Runbook: `docs/runbooks/deploy-rails-upgrade-1.md`.
