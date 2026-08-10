---
name: predeploy-review-angular
description: Pre-deploy review for the Angular apps (insgt-ops / insgt-app). Reviews the diff about to ship for NgRx correctness, change-detection & leak safety, API-contract consumption, Vitest unit coverage, Cypress e2e coverage, and InsightPhotos compliance/conventions. Read-only — surfaces findings, never edits or commits.
argument-hint: [prod-ref]
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git status:*), Read, Grep, Glob
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

## Output
Group by severity — **Blockers** (do not deploy) / **Should-fix** / **Nits**.
Each: `file:line`, what's wrong, suggested fix (described, not applied).
End with **Open questions** (need my decision) and a **Pre-deploy checklist**
(CloudFront invalidation, env config, etc.).

## Non-goals
No refactoring unrelated to this diff. No lint/format fixes the tooling handles.
No git-state changes, no file writes.