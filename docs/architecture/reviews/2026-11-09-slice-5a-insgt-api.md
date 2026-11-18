# Review record — Rails upgrade slice 5a, insgt-api (2026-11-09)

**Diff:** insgt-api `git diff master...chore/rails-upgrade-slice-5a`, one commit:
`c966bb6e chore: enable the rails 8.0 request freshness and regexp timeout defaults` (pre-review
`3ca24647`). `master` = `origin/master` = `heroku/master` = `316fa0e1` (v671), so nothing else ships
with the merge (`git log origin/master..master` → empty). Three files: `new_framework_defaults_8_0.rb`
(`:25`, `:30` uncommented), `spec/architecture/rails_upgrade_spec.rb` (the 8.0/8.1 block, 3 examples),
`spec/lib/crmls_login_timeout_spec.rb` (new, 1 example).
**Contract:** `docs/architecture/rails-upgrade.md` §4.6 rows 2–3 (v7 at review, v8 after). **Plan:**
`docs/plans/rails-upgrade-slice-5.md`. **Runbook:** `docs/runbooks/deploy-rails-upgrade-5a.md`.
**Skill:** `predeploy-review-rails`, its Codex step run per `codex-review`.
**Result:** two rounds. Round 1 raised one finding, fixed by amending the commit. Round 2 raised
nothing. No finding is open.

## Run configuration

| | Round 1 | Round 2 |
| :-- | :-- | :-- |
| Reviewed commit | `3ca2464720e98632f7ea61495fb7dfdca1fe4976` | `c966bb6e15f63472b415207b9f69333a1d2c5f1e` |
| Model / effort | `gpt-6-astra` / `max` | `gpt-6-astra` / `max` |
| Why `max` | production configuration with a process-wide blast radius: `Regexp.timeout` caps every match in every process and gem (`codex-review`'s escalation list) | same |
| Sandbox | probe `codex sandbox true` failed (no bwrap) → worktree mode, `danger-full-access` | same |
| Run directory | `/tmp/codex-review-wt-insgt-api-3ca24647…`, detached at the reviewed commit; tracked files only, so no `.env` and no `config/master.key` | `/tmp/codex-review-wt-insgt-api-c966bb6e…` |
| Session | `01a1c104-253c-7b22-8c1b-0075806be28e` | `01a1c112-87f7-7083-ae45-22f3ba0c1a2b` |
| Header matches the command | yes (model, `reasoning effort: max`, sandbox) | yes |
| Times (UTC) | 15:53:56 → 16:03:24 | 16:09:39 → 16:17:12 |
| Commands / tokens | 41 / 151,125 | 46 / 147,386 |
| Brief | `codex-review`'s adversarial brief, plus `predeploy-review-rails`' Rails list and the slice context; the design doc, plan and runbook passed by absolute path | round 1's, plus round 1's finding and its disposition |
| Read-only verification | worktree status empty, its HEAD the reviewed SHA; real HEAD and status unchanged | same |
| Worktree removed | yes | yes |

The real tree carried two files from another session at both runs: an untracked
`config/initializers/client_ip_header.rb` and an edit to `spec/requests/forwarded_header_spec.rb`,
appearing at 15:52 UTC. They were unchanged across each run. The worktrees did not contain them, and
they were never staged on this branch.

## Claude's pass (before Codex)

- **Scope and target.** Heroku from `master` (`git remote -v`, `Procfile`: `web` puma,
  `backgroundworker` sidekiq, no release phase). `docs/services/insgt-api.md` exists.
- **The railtie cite in the spec comment holds:** `actionpack-8.1.4.1 action_dispatch/railtie.rb:92`.
- **Nothing masks a timeout in app code.** `grep -rn -E
  'rescue[[:space:]]+(RegexpError|Regexp::TimeoutError)|Regexp\.new|Regexp\.timeout|timeout:[[:space:]]*[0-9]'
  app lib config --include=*.rb` finds only `receive_timeout: 0` (RETS) and the geocoder's
  `timeout: 5`. The one swallow is `Crmls#login`'s bare `rescue`, which the new spec documents.
- **Every process boots through `config/initializers`:** puma, sidekiq and the Scheduler's rake
  one-offs. The timeout is a direct global, so forked puma workers inherit it.
- **Traps.** `git diff master...HEAD -- config/initializers/new_framework_defaults_8_1.rb
  config/application.rb config/initializers/strong_migrations.rb lib/crmls.rb Gemfile Gemfile.lock
  .ruby-version` → 0 lines; `_8_0.rb:18` still commented.
- **Tests.** Each new example was seen red: the two value pins before the change and under a
  re-commented line, and the login example under a login that raises nothing.
- **Finding (nit):** `crmls_login_timeout_spec.rb:30` read `ActionMailer::Base.deliveries.last`,
  relying on a suite that never clears deliveries (`grep -rn -E 'deliveries\.clear' spec` → empty).
- No N+1, callback, migration, Sidekiq-argument, params, serializer, ENV, Anthropic, Fair Housing or
  AB 723 surface in the diff.

## Findings and dispositions

| # | Round | Source | Severity (Codex → triaged) | Finding | Disposition |
| :-- | :-- | :-- | :-- | :-- | :-- |
| 1 | 1 | Claude | nit | `crmls_login_timeout_spec.rb:30` reads `deliveries.last` from an array the suite never clears | **fixed** by #2's change; the assertion is gone |
| 2 | 1 | Codex | should-fix → **nit** | `crmls_login_timeout_spec.rb:20`: `and_call_original` renders the real mail, whose sender is `ENV['ZONE_EMAIL_SENDER']` (`notifier.rb:2`); with it blank, delivery raises `ArgumentError: SMTP From address may not be blank` inside the rescue and the no-exception assertion fails | **Confirmed** by reproduction (`ZONE_EMAIL_SENDER= bundle exec rspec …` → 71 examples, 17 failures). **Regraded:** the test database's name, user and password also come from `.env` (`database.yml:17–20`), so no spec runs without dotenv, and 16 of those failures are existing examples (`transaction_spec.rb` 2, `account_stripe_spec.rb` 14) with the same dependency. **Fixed anyway**, by returning to the plan's delivery double (Decisions 10): `send_error_email` returns `instance_double(ActionMailer::MessageDelivery, deliver_now: nil)` and the spec asserts `deliver_now`. Green with and without the sender; the deliberate break still fails on the `send_error_email` expectation. Commit amended `3ca24647` → `c966bb6e` (unpushed) |
| — | 2 | Codex | — | "The round 1 fix is sufficient. All 23 targeted examples pass with the sender blank, both normally and with `CI=1`. No actionable findings survived the full-diff review under your reporting standard." | — |

**Disagreed with:** none. **Already-intentional:** none raised.

**Codex's stated uncertainty (both rounds):** "live CRMLS payload timing on Heroku remains unverified.
No realistic production input causing a regex timeout was established." It agrees with the plan's
Unverified list. The watched import (runbook 5a step 6) is the probe, and its four-part read exists
because the login path hides a timeout from the check-in and from Honeybadger.

## After the fix

Full suite at `c966bb6e`, in a clean worktree with `.env` copied in and then removed, and with `tmp/`
created: `2103 examples, 0 failures` plain (54.0 s) and with `CI=1` (55.3 s); 0 `DEPRECATION WARNING`;
the 24 rack warnings unchanged. `rails_best_practices` 326. The first worktree run, without `tmp/`,
failed 33 examples with `Errno::ENOENT` on report files. That is a worktree artifact, recorded in the
plan's deviation 8.

## Open questions

None from the review.

## Pre-deploy checklist (from the review)

- No migration, no ENV change, no gem change, no Sidekiq argument change, no client change.
- Gate the push on slice 4's SH at about 24 h (runbook 5a Prerequisites).
- P-PROD on the merge, with the eight extra lines and the exit status (runbook 5a step 2).
- After the push: S14 → `1.0`, `false`. Then the watched run's four-part read, and SH with
  `Regexp::TimeoutError`.
