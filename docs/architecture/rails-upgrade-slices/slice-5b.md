# Rails upgrade — slice 5b: the 8.1 framework defaults, then `config.load_defaults 8.1`

**Repo:** `insgt-api`. Platform repo for the runbook, the v9 amendment and the write-back. No changes elsewhere.
**Contract:** `docs/architecture/rails-upgrade.md` **v8** §4.6 (rows 4–10, the 5b scope and gaps, "v8, as built — 5a"), §4.0, §2, §5, §6, §7 (the slice 5 plan gate, A–D), §8 items 31–33. Read them; they are the rules.
**Plan:** `docs/plans/rails-upgrade-slice-5.md`, approved 2026-11-06 and plan-reviewed 2026-11-05. Its Phase 1 is this session's plan: Gaps pinned 2, 4 and 5 (the 5b halves), Decisions 2 and 5–11, per-commit plan 2–5, Production, Post-deploy verification, the runbook outline, Risks, Traps. "Implementation record — 5a" says what moved. This session re-surveys and amends that plan; it does not write a new one.
**Brief:** `docs/architecture/rails-upgrade-slices/slice-5.md` (both deploys). This prompt is its 5b half plus what changed since.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

1. Per-commit plan 2: the six 8.1 shim lines (`new_framework_defaults_8_1.rb:28, 36, 46, 61, 66, 74`); the contract block's commit-2 set (Gaps pinned 5); `spec/requests/json_escaping_spec.rb` (Gaps pinned 2, four examples — the JBuilder separator half stays red until commit 3 by design, fact 16).
2. Per-commit plan 3: `config/application.rb:12` → `config.load_defaults 8.1`; `git rm` the five shim files; the applied-value, shim-glob and no-`active_support.`-initializer examples (Approval 7).
3. Per-commit plan 4: the two `ActiveSupport::JSON.encode` pins and the header's slice 5b clause.
4. Per-commit plan 5 (Approval D): `Honeybadger.notify` in `Crmls#login`'s rescue (`lib/crmls.rb:442–447`) and the second example in `spec/lib/crmls_login_timeout_spec.rb`.
5. §4.0's kit per Decisions 5 (P1 twice at each HEAD, plain and `CI=1`; P1 wall time before and after commit 3), then P2–P8, P-PROD with 5b's values, **P-S17** (Approval 8); `docs/runbooks/deploy-rails-upgrade-5b.md` per the plan's outline, `Draft` until reviewed; two review rounds; the write-back — v9 before the push (Approval 5; Dan, 2026-11-09), the codebase notes, `docs/architecture/reviews/<date>-slice-5b-insgt-api.md`, and "Implementation record — 5b" in the plan.

## Out of scope — do not touch

1. The brief's three (anything `belongs_to`; `rails/all`, every other §8 item, any gem; a flag flipped by any route other than the shim lines before the bump) and the plan's additions (its Scope section): `escape_html_entities_in_json`, `belongs_to_required_validates_foreign_key`, the `to_time` key, the WARN line, rubocop, `Crmls#login`'s rescue beyond commit 5's two lines, AB 723 manifest request coverage (§8 item 31).
2. 5a's work: `new_framework_defaults_8_0.rb` is deleted whole in commit 3 and never edited; `rails_upgrade_spec.rb` outside the block at `:119–146` except the header clause.
3. What rode with v672 and is not 5a's: `config/initializers/client_ip_header.rb`, `config/environments/production.rb:36`, `spec/requests/forwarded_header_spec.rb`.
4. Runbook 5a's steps 5–7 records and its `Deployed` status, the platform repo's uncommitted 5a edits, and `docs/plans/secrets-hardening-plan.md`: Dan's. Read them; write and commit none of them.

## Prerequisites

5a is deployed: v672 = `master` `808d383f`, pushed 2026-11-10 14:48:26 UTC (runbook 5a step 4). The loop may start on it now. **The merge and the push wait on the gate:** runbook 5a step 6's four signals on the watched import, the 15:30 UTC run (S9; S9b with a start after 14:48:26 UTC; S16; the ops@ inbox against its 2021-08-31 baseline), SH at step 7 at about 14:48 UTC Wednesday, and the S15 and S17 "before" captures on v672 (plan, Production). The pre-push runner reads `8.1.4.1`, `7.2`, `1.0`, `false`. Production reads are Dan's on the Mac; the session runs none. Phase 0 pastes `git diff --stat 316fa0e1 808d383f -- config/application.rb config/initializers/new_framework_defaults_8_1.rb lib/crmls.rb spec/architecture/rails_upgrade_spec.rb` and states whether fact 16's boot check needs a re-run (Approval 1's rule is for a conflicting shim; the 8.1 shim is unchanged since `316fa0e1`).

## Model spend

None — no model call is added or changed (plan, Model spend).

## Gaps the plan must pin

The brief's five are pinned in the plan. What moved since it was written, each pinned in a "5b — amendments" section of the plan with its evidence:

1. **The base.** `chore/rails-upgrade-slice-5b` off `master` `808d383f` (v672), not 5a's branch tip as Decisions 1 wrote it. Every line per-commit plan 2–5 cites, re-verified there: the contract block is `:119–146` (the plan's `:118–132` is the pre-5a block); `application.rb:12`; the six shim lines; `crmls.rb:442–447`.
2. **Counts.** `master` runs 2,104 (runbook 5a), two above the base the plan's 5b ESTIMATEs rest on, and the plan's contract-file counts (24, 25, 27) read one high against the file's 18 examples. Source each HEAD from `rspec --dry-run --format json`; recompute nothing.
3. **P-PROD's route count** is `582` in production mode since `073ebe2f` set `config.action_cable.mount_path = nil`; the plan's 5b line says `583`. Development `bin/rails routes` stays 583.
4. **S17's token runner** names `properties.address_1`, which does not exist: `street1` or `full_address` (`db/schema.rb`, the `properties` table); `orders.compliance_mode` (`:778`) and `orders.locked` (`:741`) exist. Pin the runner for P-S17 and the runbook.
5. **The initializer example's glob** now holds `client_ip_header.rb` and `forwarded_priority.rb`. Expected matches today: three comments (`_8_0.rb:18`, `_8_1.rb:36`, `deprecation_reporting.rb:3`); after commit 3, the last alone. `grep -rn -E '^\s*[^#[:space:]].*active_support\.' config/initializers` → empty, pasted.
6. **Runbook values from 5a as deployed:** rollback to v672; S9b 654–659 listings and 270–420 s; the inbox baseline 2021-08-31; the window Wed 11-11 09:30 PT, fallback Mon 11-16 (§6). The plan's Unverified items 5b settles: U+2028 surviving `cleanup_attributes` (the loop's first run) and the P1 wall-time delta with YJIT off in test (recorded, not a criterion).

## Traps for the review

1. The brief's four as the plan audits them: `Regexp.timeout` touched in 5b; `:18` uncommented, or any `to_time_preserves_timezone` reference beyond the contract's `key?` example; a shim file surviving; `belongs_to_required_by_default` or either CSRF line reappearing; "identical" said of bytes rather than parsed values; any refactor, gem, `StrongMigrations.target_version`, Ruby or Postgres change; `load_defaults` other than `8.1`, or moved before commit 3.
2. The JSON flag re-set through the class writer instead of the shim line, in a spec or a break: `renderers.rb:31–39` deprecates it and slice 1's gate raises at boot (Gaps pinned 2, Rejected).
3. A `config/application.rb` diff other than the one `load_defaults` line (Gaps pinned 4); an uncommented `active_support.` assignment under `config/initializers` (Approval 7).
4. `lib/crmls.rb` changed beyond `rescue => error`, the message and the one `notify` line: the swallow, the email and the early return stay (Decisions 10).
5. Any file of Out of scope 3 or 4 in the diff. A review worktree holding `.env` or `config/master.key` (Decisions 6). A suite worktree without `tmp/` and a copied `.env` read as a code failure (5a deviation 8).

## Commit sketch

insgt-api, on `chore/rails-upgrade-slice-5b` off `master` `808d383f`, as the plan's Commit sequence: 2. `chore: enable the rails 8.1 framework defaults` [2] · 3. `chore: load the rails 8.1 defaults and remove the shim files` [3] · 4. `test: pin the rails upgrade invariants in the contract spec` [1] · 5. `fix: report a swallowed CRMLS login failure to Honeybadger` [2].
Platform, on `docs/rails-upgrade-slice-5` after Dan's 5a deploy-log commits: `docs: add the rails upgrade slice 5b runbook` before the review; then, cut as 5a's were, the plan's implementation record, the review record and the runbook's review section, `docs: amend the rails upgrade design to v9 for slice 5b`, `docs: update the rails upgrade notes for slice 5b`, `docs: mark the slice 5b runbook ready`.

## Gates

**Slice character:** Foundation — `config.load_defaults` and the JSON renderer reach every response and every model.
**Pause at:** All. The plan review ran 2026-11-05 on this plan (nine findings, each dispositioned); do not re-run it unless the survey changes the commit sequence (the skill's second-round rule). The survey gate presents Gaps 1–6 as amendments for approval; the plan gate presents the amended plan.
At other phase boundaries, report progress and continue automatically through implementation, verification, adversarial review, fixes, and write-back. Exception stops in the skill always apply.
**Finish:** Complete the required checks, reviews, fixes, and write-back; produce the handoff (branch, commits, the push command block; no PR — insgt-api merges locally, runbook 5a Prerequisites) and the final report. The push is the engineer's, and the merge waits on the gate above. Do not merge or deploy.

## Reference pattern

`spec/requests/order_types_update_spec.rb` (the same endpoint and `jwt_headers_for`) for the request spec; `app/services/deprecation_reporter.rb:82` for the notify; `spec/lib/crmls_login_timeout_spec.rb` for its second example; `docs/runbooks/deploy-rails-upgrade-5a.md` for the runbook and `docs/architecture/reviews/2026-11-09-slice-5a-insgt-api.md` for the review record.
