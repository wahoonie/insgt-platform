# Rails upgrade — slice 4: `belongs_to` optionality follows column nullability

**Repo:** `insgt-api`. No changes elsewhere.
**Contract:** `docs/architecture/rails-upgrade.md` (platform repo, `/workspace/docs/architecture/`) §4.5, §4.0, §2, §5 R2, §7 OD10, §8 item 15. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

1. §4.5 scope 1: the contract spec first, red — every non-polymorphic `belongs_to` reflection against its column's nullability, the shared-column rule per OD10's decision, a columnless reflection failing.
2. §4.5 scope 2–3: delete `Area#state` (`app/models/area.rb:7`); `optional: true` on `Area#area_type`, `Listing#property_type`, `OrderUrlGroup#order`.
3. §4.5 scope 4: delete `new_framework_defaults.rb:18–20`; fix hand-built spec records by supplying their association (never by converting them to a factory — `CLAUDE.md`).
4. §4.5 scope 5: the production nullability STOP, the null-count report, and the dangling-key report, all read-only, written into the plan; the `sql_for` measurement on an `Order` save.
5. §4.5's post-deploy verification (S12, S13, SH's "must exist" watch); `docs/runbooks/deploy-rails-upgrade-4.md`.

## Out of scope — do not touch

1. Any framework-default flag or shim file (slice 5); the CSRF lines of the 5.0 shim.
2. Converting `TagsResource` to Rails polymorphism; any migration (no slice carries one — the `NOT NULL` candidates go to §8 item 15).
3. Any model validation beyond what OD10's rule requires; `rails/all`; any gem.

## Prerequisites

Slice 3 deployed and quiet (§2.2) for two weekdays: `Rails.version` → `8.1.4`, `loaded_config_version` → `7.2` in a production runner; SH clean since slice 3 (v6: including no `AbstractController::DoubleRenderError`). On 8.1.4 every production runner prints Active Storage's `image_processing` WARN line first (§4.0 S3, §8 item 7) — expected, not a failure. OD10 decided by the engineer (the plan proceeds on §4.5's recommendation unless told otherwise at the plan gate).

## Gaps the plan must pin

1. OD10 as decided: the exact spec encoding of the shared-column rule and the `TagsResource` exactly-one validation (`tags_resource.rb:10–12` has none today).
2. The create endpoint that proves the 422-for-500 change (candidate: an `OrdersUser` create without `user_id`) and its pre-deploy 500, captured.
3. The dangling-key query per `NOT NULL` FK column — all zero, or a STOP naming the rows.
4. The measured extra `SELECT`s on an `Order` save, before and after.

## Traps for the review

1. An allowlist of association names anywhere in the spec (the rule is structural: column nullability, shared column).
2. The global `belongs_to_required_by_default` reappearing in any file, or an `optional: true` on a `NOT NULL` column outside the shared-column rule.
3. A spec fixed by swapping a hand-built record for a factory; a validation message changed to pass a spec.
4. An opportunistic refactor; a gem major bump not named in §3; a `config.load_defaults` change outside slice 5; any edit to `StrongMigrations.target_version`; a Ruby version change; a Postgres version change.
5. (v6) A call to `ActiveSupport.to_time_preserves_timezone` anywhere — spec, probe or runbook: the reader deprecates on 8.1 (§4.4 as built).

## Commit sketch

§4.5's four commits: `test: pin belongs_to optionality to column nullability` · `fix: drop the dead Area#state association` · `refactor: mark the nullable belongs_to associations optional` · `fix: validate presence of belongs_to on NOT NULL columns`.

## Gates

All.

## Reference pattern

`spec/architecture/account_classification_spec.rb` (the invariant-over-all-models shape, §5.1 block); for the read-only production queries, `docs/runbooks/deploy-account-classification-4-backfill.md` (query, expected, observed, pasted).
