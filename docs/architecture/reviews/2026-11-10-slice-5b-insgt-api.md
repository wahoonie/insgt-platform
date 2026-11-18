# Review record — Rails upgrade slice 5b, insgt-api (2026-11-10)

**Diff:** insgt-api `git diff master...chore/rails-upgrade-slice-5b`, four commits off `master`
`808d383f` (v672, live since 2026-11-10 14:48:26 UTC): `4d5eef28 chore: enable the rails 8.1
framework defaults`, `72dfaa73 chore: load the rails 8.1 defaults and remove the shim files`,
`1671c9c3 test: pin the rails upgrade invariants in the contract spec`, `27e45f1b fix: report a
swallowed CRMLS login failure to Honeybadger`. `master` = `origin/master` = `heroku/master`, so nothing
else ships with the merge (`git log origin/master..master` → empty). Ten files: `config/application.rb`
(one line), the five `config/initializers/new_framework_defaults*.rb` (deleted), `lib/crmls.rb` (the
login rescue), `spec/architecture/rails_upgrade_spec.rb`, `spec/lib/crmls_login_timeout_spec.rb`,
`spec/requests/json_escaping_spec.rb` (new).
**Contract:** `docs/architecture/rails-upgrade.md` §4.6 rows 4–10 (v8 at review, v9 after). **Plan:**
`docs/plans/rails-upgrade-slice-5.md`, with its "5b — amendments". **Runbook:**
`docs/runbooks/deploy-rails-upgrade-5b.md`. **Skill:** `predeploy-review-rails`, its Codex step run per
`codex-review`.
**Result:** two rounds on the same HEAD. Neither round raised a finding, and Claude's own pass raised
none. No finding is open; no commit changed between the rounds.

## Run configuration

| | Round 1 | Round 2 |
| :-- | :-- | :-- |
| Reviewed commit | `27e45f1ba7edf83e8aa70daaf5075082e867e2b6` | same |
| Model / effort | `gpt-6-astra` / `max` | `gpt-6-astra` / `max` |
| Why `max` | production configuration with a process-wide blast radius: `config.load_defaults 8.1` reaches every response and every model, and the JSON renderer change touches a public contract consumed by four Angular apps, two Rails apps and five Lambdas (`codex-review`'s escalation list) | same |
| Sandbox | probe `codex sandbox true` failed (no bwrap) → worktree mode, `danger-full-access` | same |
| Run directory | `/tmp/codex-review-wt-insgt-api-27e45f1b…`, detached at the reviewed commit; tracked files only, so no `.env` and no `config/master.key` | the same worktree, reused |
| Session | `01a1c64b-af1a-7aa0-800f-e584afd39724` | `01a1c6b0-7106-7481-b88a-002cbb6621d0` |
| Header matches the command | yes (model, `reasoning effort: max`, sandbox) | yes |
| Times (UTC) | 16:30:11 → 16:38:24 | 18:20:14 → 18:28:16 |
| Commands / tokens | 48 / 185,570 | 49 / 190,223 |
| Brief | `codex-review`'s adversarial brief, plus `predeploy-review-rails`' Rails list, the slice context (the four commits), seven questions worth an independent look (byte-sensitive consumers, the notify's failure mode, the CSRF deletion, where row 7 could fire, what else `load_defaults 8.1` changes, the finder probe's leakage, whether the request spec proves what it claims), and the prompt's five traps; the design doc, plan, runbook, 5a's record and the consumer repos passed by absolute path; told there is no `AGENTS.md` | round 1's, plus a "Round 2" section: round 1's result, and five places where a wrong assumption would be shared by the author and the tests (the contract's new examples, the request spec's failure modes, the notify's context and its delivery from a Scheduler one-off, the runbook's production claims, readers of the two CSRF flags) |
| Read-only verification | worktree status empty, its HEAD the reviewed SHA; real HEAD and status unchanged (clean before and after) | same |
| Worktree removed | reused for round 2 | yes |

## Claude's pass (before Codex)

- **Scope and target.** Heroku from `master` (`git remote -v`; `Procfile`: `web` puma, `backgroundworker`
  sidekiq, no release phase). No `AGENTS.md` in the repo. `git log origin/master..master` → empty.
- **Traps.** `git diff master...HEAD` on `strong_migrations.rb`, `Gemfile`, `Gemfile.lock`,
  `.ruby-version`, `client_ip_header.rb`, `production.rb` and `forwarded_header_spec.rb` → 0 lines;
  `config/application.rb` differs by the one `load_defaults` pair; `lib/crmls.rb` by `rescue => error`,
  the message, one why-comment and the `notify` line; no shim file survives; `grep -rn -E
  '^\s*[^#[:space:]].*active_support\.' config/initializers` → empty; `belongs_to_required_by_default`
  nowhere in `config` or `app`; `to_time_preserves_timezone` only in the contract's `key?` example and
  its comment; no `escape_json_responses =` writer call anywhere (the deprecating writer);
  `Regexp.timeout` untouched (the 8.0 shim is deleted whole; `load_defaults 8.0` sets `||= 1`).
- **The notify cannot change the import's continuation.** `honeybadger-6.10.0 agent.rb:128–175`:
  with an Exception argument `validate_notify_opts!` returns at once, before-notify hooks run under
  `with_error_handling` (`:698–701`), and the only raise on the path is the dev-mode `ArgumentError`
  for a call with neither exception nor message (`:658–664`). Under test (`report_data: false`) it
  returns a notice id and sends nothing. The email, the swallow and `extract_listings`' early return
  are unchanged (Decisions 10, Approval D). Considered and not raised: wrapping the call in a rescue
  as `deprecation_reporter.rb:82` does — the plan's two-line design is explicit, and the gem's own
  error handling covers the path.
- **Row 7 cannot fire on app code.** No `self.primary_key`, `primary_key =`, `implicit_order_column`
  or `query_constraints` in `app/` or `lib/`; no `id: false` table in `db/schema.rb`; the probe is the
  only model without an order column.
- **The finder probe does not leak.** It subclasses `ActiveRecord::Base`, and the only descendants
  traversal in the suite is the contract's own `ApplicationRecord.descendants` block
  (`rails_upgrade_spec.rb:240`).
- **CSRF.** `protect_from_forgery with: :null_session` and `skip_before_action
  :verify_authenticity_token` (`application_controller.rb:2–3`) are the only CSRF references in `app`,
  `lib` and `config`; no `form_authenticity_token` caller. `redirect_to` and `redirect_back` in `app`
  and `lib`: 0.
- **Tests.** Each new example was seen red before its change (or against `master`'s tree in a
  worktree, for commit 3's encoder pins) and under a deliberate break: each shim line re-commented,
  `load_defaults` moved to `8.0`, a deleted shim restored, the notify line removed. One deviation from
  the plan: the initializer example is red at commit 1's tree (the uncommented `_8_1.rb:36` is itself a
  match), not green.
- **Production proofs.** P-S17 (the gallery `yqly4v2J`: `jq -S` diff empty, raw files byte-identical),
  the S15b rehearsal (the escaped bytes on `master`, raw on the branch, parsed errors identical, no
  write) and the S15 rehearsal (four messages, byte-identical) ran against a `master` worktree server
  and the branch server.
- No N+1, callback, migration, Sidekiq-argument, params, serializer, ENV, Anthropic, Fair Housing or
  AB 723 logic surface in the diff; the disclosure gallery's bytes change and its decoded payload does
  not (P-S17, S17).

## Findings and dispositions

| # | Round | Source | Severity | Finding | Disposition |
| :-- | :-- | :-- | :-- | :-- | :-- |
| — | 1 | Claude | — | none | — |
| — | 1 | Codex | — | "No actionable findings survived this review." | — |
| — | 2 | Codex | — | "No actionable findings survived the independent review of `master...HEAD` at `27e45f1b`." | — |

**Disagreed with:** none. **Already-intentional:** none raised.

**Codex's stated uncertainty.** Round 1: "live Heroku execution, actual CRMLS login failures, and
successful Honeybadger delivery were not exercised. Verification used local code, installed gems,
consumer inspection, and focused runtime probes." Round 2: "actual Honeybadger receipt from a Heroku
Scheduler one-off and the live S15/S15b/S17 production checks." Runbook 5b's production reads (S14,
S15, S15b, S17, the watched import, SH) are the probes for those.

## After the review

No commit changed. Full suite at `27e45f1b`: `2117 examples, 0 failures` plain (83.4 s) and with
`CI=1` (82.6 s); 0 `DEPRECATION WARNING`; the 24 rack warnings unchanged; `rails_best_practices` 326.

## Open questions

None from the review.

## Pre-deploy checklist (from the review)

- No migration, no ENV change, no gem change, no Sidekiq argument change, no client change.
- Gate the push on 5a's watched import (all four signals) and 5a's SH (runbook 5b Prerequisites).
- P-PROD on the merge, with `8.1`, `582`, the applied freshness `true` and the exit status (runbook 5b
  step 2).
- Before the push, on v672: the S15, S15b and S17 "before" captures (step 3).
- After the push: S3 → `8.1` and `escape_json_responses` `false`; S14 → `1.0`, `true`; S15 parsed
  identical; S15b bytes raw, parsed identical; S17 `jq -S` diff empty. Then the watched run's four-part
  read, and SH with `Regexp::TimeoutError`, `MissingRequiredOrderError` and `UnsafeRedirectError`, plus
  S18's memory band.
