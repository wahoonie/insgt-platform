---
name: predeploy-review-rails
description: Pre-deploy review for insgt-api (Rails 7.2 / Ruby 3.4). Reviews the diff about to ship for correctness, migration & Sidekiq deploy-safety, API-contract breaks, and InsightPhotos compliance/conventions. Read-only — surfaces findings, never edits or commits.
argument-hint: [prod-ref]
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git status:*), Read, Grep, Glob
---

# Pre-deploy review — insgt-api (Rails)

Reviewing the changes about to ship. Read only — do not edit, stage, or commit.

## 1. Scope
- `<prod-ref>` is `$ARGUMENTS` (the ref live in prod). If empty or unclear, ask.
- Run and read in full: `git diff <prod-ref>...HEAD`,
  `git diff --stat <prod-ref>...HEAD`, `git log --oneline <prod-ref>..HEAD`.
- Read `insgt-api/SKILL.md` first so you review against our actual conventions.

## 2. The changed code (Rails lens)
- **N+1**: new queries or serializer associations without `includes`/`preload`/
  `eager_load`; any DB call inside a loop. Serializer N+1 is the usual culprit.
- **Callbacks**: `after_commit` recompute (the metric pattern) — check ordering,
  re-entrancy / infinite-loop risk, and that no slow work runs inline in the
  request. Fat callbacks that should be service objects or jobs.
- **`ai_*` immutability**: no path may UPDATE an `ai_*` column. Regeneration must
  append a new record. Flag any mutation. `edited.presence || ai_*` resolver
  should be intact.
- **Metric tables**: null (not zero) on empty denominator; numerators/
  denominators stored alongside rates; integer-cents; per-dimension status flags
  computed at read time in the serializer, not persisted.
- **Strong params / authz**: new params permitted explicitly (no mass
  assignment); new endpoints/actions authorized.
- **Compliance (blockers)**: Fair Housing enforcement intact in any feature/
  description generation path; AB 723 disclosure intact in Prawn output. A path
  that could emit listing copy or altered-media output without the guardrail is
  a blocker.
- **Anthropic API**: timeouts, retries, error handling present; the call is in a
  job, not blocking a request thread.

## 3. Deploy-readiness
- **Migrations**:
  - Reversible (`change`-safe or an explicit `down`).
  - Destructive / rename / NOT-NULL-without-default → needs a two-phase deploy
    (ship code tolerating both states → migrate → ship code requiring the new).
    Spell out the ordering.
  - Index on a large table → `algorithm: :concurrently` + `disable_ddl_transaction!`.
  - Backfills belong in a Sidekiq job, not the migration.
  - New FK column gets an index.
  - `db/schema.rb` regenerated and committed — `schema_format` is unset, so Rails
    dumps Ruby and there is no `db/structure.sql`. Asking for structure.sql is
    wrong for this repo as it stands; schema.rb dumps check constraints and
    concurrent/unique indexes fine.
  - REVISIT AT THE RENDER CUTOVER. PostGIS is on the roadmap to land before it,
    but is not installed yet — no extension in the database, no spatial columns,
    no adapter gem. The "PostgreSQL/PostGIS" in both CLAUDE.md files describes
    the target, not today; do not "correct" it. When PostGIS lands the dump
    format becomes a real decision — an adapter that teaches the Ruby dumper the
    spatial types, or a move to structure.sql — so re-derive this item then
    rather than trusting it. Same revisit list as
    `StrongMigrations.target_version`, already flagged in its initializer.
- **Sidekiq**: job-arg signature changes must stay back-compat across a rolling
  deploy (jobs already enqueued with old args). Renamed/removed worker classes
  leave orphaned jobs in Redis. Idempotency. New queue declared in config + the
  Render worker.
- **API contract**: added/removed/renamed/retyped serializer fields that
  insgt-ops or insgt-app consume → breaking. Flag and name the affected app.
- **Env/secrets**: new ENV vars must exist in Render/AWS (SSM) before deploy.

## 4. Tests (RSpec)
- Three-tests pattern (happy / empty / error). factory_bot factories updated for
  new columns. webmock/vcr for any new Anthropic call — no live HTTP in specs.
  shoulda-matchers for validations/associations. Request specs cover any
  endpoint contract change.
- Changed behavior with no spec change → flag.

## Output
Group by severity — **Blockers** (do not deploy) / **Should-fix** / **Nits**.
Each: `file:line`, what's wrong, suggested fix (described, not applied).
End with **Open questions** (need my decision) and a **Pre-deploy checklist**
(migrations to run, env vars to set, etc.).

## Non-goals
No refactoring unrelated to this diff. No RuboCop fixes the tooling handles.
No git-state changes, no file writes.