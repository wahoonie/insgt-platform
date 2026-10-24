# Rails upgrade — slice 0: Honeybadger

**Repo:** `insgt-api`. No changes elsewhere (the Honeybadger project and Heroku config are set from the Mac).
**Contract:** `docs/architecture/rails-upgrade.md` (platform repo, `/workspace/docs/architecture/`) §4.1, §4.0, §2, §3.1, §5. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

1. §4.1 items 1–3: the `honeybadger` gem, the API key from `HONEYBADGER_API_KEY` only, `config/honeybadger.yml` without a key (production-only reporting explicit, Insights off, `sidekiq.attempt_threshold: 0`).
2. §4.1 item 4: the parameter-filtering review on a real test notice, with the `Authorization` header and Stripe fields named in the plan's evidence.
3. §4.1 item 5: the check-in at the end of `import_listings` (`lib/tasks/scheduler.rake:17`), guarded on its ENV id.
4. §4.1 items 6–7: the uptime monitor on `/up`, and the 24-hour error-class baseline written into `docs/runbooks/deploy-rails-upgrade-0.md` (runbooks README shape).
5. §4.1's post-deploy verification: `honeybadger test`, the dev-reported `NameError` job, S0, S1–S2, S9.

## Out of scope — do not touch

1. Anything under `config/environments/` or any Rails setting (`report_deprecations` is slice 1, §4.2).
2. Honeybadger Insights, deploy hooks, `honeybadger install`, Honeybadger context for users.
3. Any other gem, any other rake task, the Sidekiq configuration.

## Prerequisites

§2.7: `git -C /workspace log --oneline main -3` shows the three `docs:` commits of `docs/rails-upgrade` merged into `main`. A Honeybadger project exists; its key is in the Mac's shell and in `heroku config --app insgtapi`; the check-in and uptime monitor ids exist in the dashboard.

## Gaps the plan must pin

1. Precedence of `HONEYBADGER_REPORT_DATA=true` over `config/honeybadger.yml` for the one development verification run (§4.1 gaps) — test it, record the answer.
2. OD11: the plan assumes the `import_listings` check-in unless the engineer says otherwise at the plan gate.
3. Whether the gem filters `HTTP_AUTHORIZATION` by default; if not, the `request.filter_keys` addition and its proof on a second notice.
4. The exact Sidekiq log lines and the `Sidekiq::Status` result for the §4.1 dev-reported failure, pasted.

## Traps for the review

1. The API key, or any Honeybadger id that is a secret, in a tracked file.
2. A notice sent from the test suite, or `report_data` true outside production.
3. `insights.enabled` left at its default.
4. A `rails` or any other gem change riding along; a gem major bump not named in §3.
5. A `config.load_defaults` change; any edit to `StrongMigrations.target_version`; a Ruby version change; a Postgres version change; an opportunistic refactor in either commit.

## Commit sketch

1. `build: add honeybadger for error tracking`
2. `feat: check in from the listings import`

## Gates

After plan; after verification.

## Reference pattern

`config/initializers/strong_migrations.rb` — an initializer whose comments say why each setting is set; `config/honeybadger.yml` is written in that voice. Runbook: `docs/runbooks/deploy-headshot-event-date.md`.
