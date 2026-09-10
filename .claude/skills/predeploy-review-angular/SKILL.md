---
name: predeploy-review-angular
description: Pre-deploy review for the Angular apps (insgt-ops / insgt-app). Reviews the diff about to ship for NgRx correctness, change-detection & leak safety, API-contract consumption, Vitest unit coverage, Cypress e2e coverage, and InsightPhotos compliance/conventions, then runs an independent Codex review over the same diff and triages it against Claude's findings. Read-only — surfaces findings, never edits or commits.
argument-hint: [prod-ref]
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git status:*), Bash(git rev-parse:*), Bash(codex exec:*), Read, Grep, Glob
---

# Pre-deploy review — Angular (insgt-ops / insgt-app)

Reviewing the changes about to ship. Read only — do not edit, stage, or commit.

## 1. Scope
- `<prod-ref>` is `$ARGUMENTS` (the ref live in prod). If empty or unclear, ask.
- Run and read in full: `git diff <prod-ref>...HEAD`,
  `git diff --stat <prod-ref>...HEAD`, `git log --oneline <prod-ref>..HEAD`.
- Detect the repo (package.json / path). Read `clean-typescript`, `angular-core`,
  and the app skill — `insgt-ops-angular-developer` OR
  `insgt-app-angular-developer` — before reviewing. The legacy-vs-modern rule
  below depends on which app this is.
- Set `REPO` to the detected repo name and `REPO_DIR` to
  `git rev-parse --show-toplevel`. Both are used by the Codex step in §6.

## 2. The changed code (Angular lens)
- **NgRx**: entity-adapter pattern per `ngrx-patterns.md`. Uses the action/effect
  helper factories (`state-actions.helper`, `state-effects.helper`) rather than
  hand-rolled `switchMap`/`catchError`. `createActionGroup` (modern), not the old
  custom helper. Effects catch errors into the `*Error` action — an uncaught
  effect error kills the stream. Selectors memoized via `createSelector`. Meta
  total uses null-not-zero (`?? 0`). `ThingCollection` response typing. Components
  go through the facade, not the store directly.
- **Change detection & reactivity**: `OnPush` / signals / `computed`.
  - insgt-ops: a NEW file should be standalone + signals + `inject()`. The legacy
    NgModule pattern in a new file is drift — flag it.
  - insgt-app: it's fully modern — ANY NgModule / constructor-DI / untyped-form
    pattern is drift, flag it.
- **Leaks**: manual subscriptions without `takeUntilDestroyed` or the async pipe;
  timers/effects not cleaned up.
- **API-contract consumption**: do the response models /
  `ResourceApiService.createClient()` typings still match the current API shape?
  If the API changed, these must too — flag mismatches (this is the other half of
  the Rails contract check).
- **Tailwind v3→v4**: deprecated/renamed utilities, config drift on touched files.

## 3. Deploy-readiness
- **Build & bundle**: lazy-loaded routes wired to the `*.provider.ts` bundle
  (`provideState`/`provideEffects` per feature) so the slice loads with the route,
  not eagerly. Standalone providers present. No barrel-import bloat defeating
  tree-shaking.
- **Static hosting**: served via S3/CloudFront. Hashed filenames self-bust, but
  `index.html` / non-hashed assets need a CloudFront invalidation on deploy.
  Build-time env (Angular `environments`) points at the prod API base URL
  (Render/AWS, not Heroku).
- **PWA (insgt-app only)**: `ngsw-config` updated for new assets/routes; cache
  version bumped so users get the new shell; offline behavior for any changed
  flow; manifest.
- **Feature gates**: unlock-flag-driven UI (`description_unlocked`,
  `marketing_kit_unlocked`) — anything user-visible shipping unguarded that
  should be gated.

## 4. Unit tests (Vitest)
- Vitest specs are `*.spec.ts` colocated under `src/`; Cypress specs are
  `*.cy.ts`. Never Karma or Jasmine — a Jasmine-style spec is the wrong pattern
  in both apps. A `.spec.ts` under `cypress/` is a bug in the file's location,
  not in the config.
- Scope is pure logic only — reducers, selectors, mappers, formatters,
  validators. A component/TestBed spec is the wrong layer; it belongs in
  Cypress. See the `angular-unit-testing` skill.
- Assert through selectors (`.projector()`), never on raw state shape.
- Null-not-zero: a selector producing a rate returns `null` on an empty
  denominator, never `0`.
- State-layer change (`data-access/state/`, `store/`) with no spec change → flag.
- Confirm `npm test` (`vitest run`) is green before deploying. Report it as its
  own result, separate from Cypress — a red unit run and a Cypress coverage gap
  are different findings, and Cypress is slow enough that it should not gate a
  fast unit run.

## 5. E2E tests (Cypress)
- Three-tests (happy / empty / error). `data-cy` selectors, not CSS/text. Every
  API call stubbed with `cy.intercept()` — no real network.
- **Compliance display (blockers)**: AB 723 altered-photo disclosure renders
  wherever altered media is shown; Fair Housing copy is displayed as-is with no
  UI that could strip or alter it.
- Changed behavior with no Cypress change → flag.

## 6. Second-opinion review (Codex)
An independent model reviewing the same diff. Run it **after** finishing §2–§5 so
Codex's findings don't anchor yours — the value is in the disagreement.

- Run exactly one invocation, non-interactively (`codex exec`, never the TUI —
  it will hang the bash call). Write to a file with `-o`, not stdout, so the
  review doesn't flood the context:

  ```bash
  codex exec -C "$REPO_DIR" -s danger-full-access \
    -o "/tmp/codex-review-$REPO.md" \
    "Pre-deploy review of \`git diff <prod-ref>...HEAD\` in this Angular repo.
     Do not modify files. Review for: NgRx correctness (effects must catch into
     an *Error action, selectors memoized, components use the facade not the
     store), OnPush/signals change detection, subscription and timer leaks,
     API response typing drift, lazy-route provider wiring, PWA/ngsw config,
     Vitest coverage on state-layer changes, Cypress coverage on behavior
     changes, and AB 723 / Fair Housing display. Flag violations of AGENTS.md.
     For each finding: file:line, severity (blocker/should-fix/nit), the issue,
     and a suggested fix. Finish with anything you are unsure about."
  ```

- `exec` is already non-interactive; there is no `--ask-for-approval` flag on it
  (that is the TUI's), and passing it exits on a usage error without reviewing.
- `-s danger-full-access` is not laziness. Codex's `read-only` and
  `workspace-write` sandboxes shell out to bubblewrap, which cannot create a
  namespace inside this devcontainer — the run dies on `bwrap: No permissions to
  create a new namespace` and produces no findings. Commit the repo first so any
  stray write is recoverable, and check `git status` afterwards.
- If `codex` is not installed or the run fails, report that under **Codex
  review** and continue — Codex is additive, never a gate.
- Read `/tmp/codex-review-$REPO.md`. Triage **every** finding, verifying each
  against the actual code before accepting it. Codex reviews without the skill
  files loaded, so expect some findings that are already-intentional
  (e.g. legacy NgModule patterns in existing insgt-ops files):
  - **agree** — merge into the severity groups below, attributed `[codex]`
  - **both** — you had it too; attribute `[claude+codex]`. Consensus findings
    are the highest-confidence items in the report.
  - **disagree** — list separately with the reason (cite `file:line`)
  - **already-intentional** — list with the convention or skill rule it follows
  - **needs-my-decision** — promote to **Open questions**
- Do not accept a Codex severity uncritically; re-grade against the blocker
  definitions in §3 and §5.

## Output
Group by severity — **Blockers** (do not deploy) / **Should-fix** / **Nits**.
Each: `file:line`, what's wrong, suggested fix (described, not applied), and
source — `[claude]`, `[codex]`, or `[claude+codex]`.
Then a **Codex review** section: run status, findings disagreed with (and why),
findings marked already-intentional. Findings Claude alone caught that Codex
missed need no callout — that's expected.
End with **Open questions** (need my decision) and a **Pre-deploy checklist**
(CloudFront invalidation, env config, etc.).

## Non-goals
No refactoring unrelated to this diff. No lint/format fixes the tooling handles.
No git-state changes, no file writes in the repo (the Codex output file in
`/tmp` is the only write). Do not run Codex more than once per review or
against a different ref than the one under review.