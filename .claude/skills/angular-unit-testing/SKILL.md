---
name: angular-unit-testing
description: Use this skill whenever writing, reviewing, or requesting unit tests in any InsightPhotos Angular app (insgt-ops, insgt-app). Invoke for any task touching reducers, selectors, pure mappers, formatters, validators, or NgRx state-layer helper factories. Also invoke proactively when generating or modifying a data-access/state/ file — new state logic ships with tests. Do NOT use for component, template, routing, or user-flow testing; those are Cypress-only and covered by angular-core §8.
---

# Angular Unit Testing — InsightPhotos Shared Conventions

Unit tests exist for one reason: to make verification fast enough that it happens
on every change. Cypress covers user flows and takes minutes. Unit tests cover
pure logic and take milliseconds. They are not substitutes and neither replaces
the other.

**Runner: Vitest.** Both apps converge on it, with the same Jest-compatible
assertion API.

| Repo | Angular | Setup |
|---|---|---|
| `insgt-app` | 21 | First-party `@angular/build:unit-test` builder |
| `insgt-ops` | 19 | Plain Vitest via `vitest.config.mts` — pure logic only, no TestBed |

Never introduce Karma or Jasmine. Karma has been deprecated since 2023 and is
removed from the Angular 21 CLI defaults.

**Do not install AnalogJS in insgt-ops.** Plain Vitest was chosen deliberately:
the scope below is pure functions and newable classes, TestBed is out of scope,
and the Angular test builder would couple the setup to Angular 19 immediately
before a major version jump. Two things in `vitest.config.mts` are load-bearing
and easy to delete by accident:

- `resolve.alias` for `@app` / `@env` — Vite does not read tsconfig `paths`, and
  every selector in the repo imports `@app/store/app.interfaces`.
- `setupFiles: ['@angular/compiler']` — NgRx 19 ships partially-compiled bundles
  whose `@Injectable()` classes compile in a static initializer at import time.
  Without the compiler loaded, importing *any* reducer or selector throws
  "needs to be compiled using the JIT compiler". insgt-app gets this free from
  its builder's injected `init-testbed.js`; plain Vitest does not.

`passWithNoTests: true` is bootstrap scaffolding — delete it when the first real
spec lands, or a broken `include` glob will report green forever.

---

## 1. Scope — what gets a unit test

Coverage here is deliberately narrow. Broad coverage is not the goal; fast
coverage of the logic that fails silently is.

**In scope:**

| Target | Why |
|---|---|
| Reducers | Pure `(state, action) => state`. No TestBed, no DI, sub-millisecond. |
| Selectors | Derived state is where silent wrongness lives — Cypress only catches it if a flow happens to render that exact value. |
| Pure mappers and formatters | Cents→currency, date normalization, API response shaping. |
| Form validators | Small, pure, cheap. |
| NgRx state-layer helper factories | Tested **once** — see §5. |

**Out of scope — do not write these:**

- Component tests, TestBed setup, `ComponentFixture`, DOM queries
- Template rendering, `@if` / `@for` behavior
- Routing, guards-as-navigation, route resolvers
- Facades (thin delegation to the store — testing them tests NgRx, not us)
- HTTP services (thin adapters — the mapper inside is in scope, the transport is not)
- Anything you would reach for a `data-cy` attribute to assert

If a test needs a browser, a fixture, or a rendered template, it belongs in
Cypress. Stop and write it there instead.

**The disqualifier is machinery, not collaborators.** A file drops out of scope
when testing it requires TestBed, Angular DI, `jasmine-marbles`, a
`TestScheduler`, or fake timers. It does *not* drop out merely because you have
to hand it a stand-in collaborator. An object literal supplying the two or three
methods the code calls, and `of()` / `Subject` / `throwError` supplying the
streams, are **fixtures** — the same category as a hand-written state object.

The line matters because the duck-typed helpers in both repos take an `object`
with `actions$` and `resourceService` rather than injecting anything. Reading
that as "needs a mocked service" would exclude `state-effects.helper`, whose
error-recovery contract (§5) is the single highest-value assertion in either
codebase's state layer.

If an assertion turns out to need real machinery, drop that assertion and report
it — do not install the machinery.

---

## 2. The load-bearing rule — assert through selectors

**Never assert on raw state shape. Always read through a selector.**

```ts
// ❌ Couples the test to internal representation. Breaks the moment the slice
//    adopts an entity adapter, and tells you nothing about behavior.
expect(state.things.length).toBe(2);
expect(state.entities['abc'].name).toBe('Kitchen');

// ✅ Asserts the contract the rest of the app actually consumes.
expect(selectAll.projector(state)).toHaveLength(2);
expect(selectCurrent.projector(entities, 'abc')?.name).toBe('Kitchen');
```

The selector is the public contract of a state slice; `EntityState`'s
`{ ids, entities }` is an implementation detail. Tests written this way survive
folder moves, entity-adapter adoption, and the `store/` → `data-access/state/`
convergence untouched — which means they *verify* those refactors instead of
becoming casualties of them.

Use `.projector()` to test selector logic in isolation. It calls the selector's
final projection function directly with the inputs you supply, skipping the
store and memoization entirely.

**Where a file produces no state, compose its output through a minimal in-spec
reducer rather than asserting action shape.** Action-creator factories and effect
factories emit actions, not state. Asserting the literal type string or the props
key pins the thing most likely to be rewritten — the `createActionGroup`
migration churns every one — while telling you nothing about behaviour.

Wire the creators into a `createReducer`/`on` pair written **in the spec file**,
dispatch, and assert the resulting state. That survives a rename, because the
creator is referenced by identity and never by name, and it still catches the two
failures that are otherwise silent: a factory returning its tuple in the wrong
order, and two factories in one feature colliding onto the same action.

The in-spec qualifier is the whole point. Import a real feature reducer and the
spec stops testing the factory and starts testing that slice — it will then break
for reasons that have nothing to do with the file under test. For the same reason
the handlers should be plain inline functions, not calls into a shared reducer
helper.

Emission *count* is the exception: it is a property of the stream, not of any
action's shape, so assert it directly (`expect(emitted).toHaveLength(2)` is how
you prove an effect survived an error).

---

## 3. Three tests per slice

Mirrors the Cypress convention in `angular-core` §8. Same shape, different layer.

1. **Happy path** — the success action applies data correctly and clears loading
2. **Empty state** — an empty collection produces empty derived state, and any
   rate or ratio is `null`, not `0` (see §6)
3. **Error state** — the error action stores the error, clears loading, and does
   not corrupt existing data

Three per slice is the floor, not a cap. Add a fourth when a reducer case has
genuinely branching logic.

**Regression rule:** when a bug is found in state logic, write the failing unit
test first, then fix it. Faster loop than the Cypress equivalent and it pins the
exact case.

**Boy scout rule:** when you modify a `data-access/state/` file, leave it with a
test that didn't exist before. Never open a dedicated test-backfill task.

---

## 4. File layout and naming

Colocate specs beside the file under test. No parallel test tree.

```
feature/
└── data-access/
    ├── feature.mapper.ts
    ├── feature.mapper.spec.ts
    └── state/
        ├── feature.reducer.ts
        ├── feature.reducer.spec.ts
        ├── feature.selectors.ts
        └── feature.selectors.spec.ts
```

- Vitest specs: `*.spec.ts`, colocated under `src/`
- Cypress specs: `*.cy.ts`, under `cypress/e2e/`

These globs must never overlap. If a `.spec.ts` file appears under `cypress/`,
that is a bug — fix the location, not the config.

---

## 5. Test the factory once, not every feature

Both repos generate state boilerplate from shared helpers
(`state-effects.helper`, and historically `state-actions.helper`). Effects
produced by `createLoadCollectionEffect`, `createCreateEffect`, and friends are
the *same code* across every feature that uses them.

**Test the helper factory thoroughly, in one place:**

- Dispatches the success action with the mapped payload
- Dispatches the error action on failure
- Does not swallow or terminate the effect stream on error

**Then do not write per-feature effect specs.** They add maintenance and no
information. Write an effect spec only when a feature's effect does something the
factory doesn't — a custom `switchMap`, a chained dispatch, a non-standard
endpoint.

The same applies to any shared mapper or base facade: one thorough spec at the
definition site, none at the call sites.

---

## 6. Domain rules the tests must pin

These are business conventions, not framework behavior. They are exactly what
regresses unnoticed, so assert them explicitly.

**Null-not-zero for metrics.** A rate with an empty denominator is `null`, never
`0`. A test that asserts an empty collection yields `null` — not `0`, not `NaN`,
not `'0%'` — is mandatory on any selector producing a rate.

```ts
it('returns null for a rate when the denominator is empty', () => {
  const state = { ...initialState, delivered: 0, total: 0 };
  expect(selectDeliveryRate.projector(state)).toBeNull();
});
```

**Integer cents.** Money crosses the API as integer cents. Any formatter or
selector converting to display currency gets a spec covering zero, a value under
one dollar, and a value requiring thousands separators.

**Suppressed and unpublished listings.** Any selector filtering listing
visibility gets an explicit case proving suppressed records are excluded.

---

## 7. Templates

Import dividers follow `angular-import-organization`. Both templates below sit
under the threshold rule (fewer than 3 populated categories / 6 total imports),
so dividers are correctly omitted.

### Reducer

```ts
import { describe, expect, it } from 'vitest';

import { ThingActions } from './thing.actions';
import { thingReducers } from './thing.reducer';
import { initialState } from './thing.state';
import { selectAll, selectError, selectLoadingAll } from './thing.selectors';

describe('thingReducers', () => {
  const thing = { id: '1', name: 'Kitchen', position: 0 };

  it('sets loading and clears error on load all', () => {
    const state = thingReducers(
      { ...initialState, error: { message: 'stale' } },
      ThingActions.loadAll({ params: {} }),
    );

    expect(selectLoadingAll.projector(state)).toBe(true);
    expect(selectError.projector(state)).toBeNull();
  });

  it('stores the collection and clears loading on success', () => {
    const state = thingReducers(
      initialState,
      ThingActions.loadAllSuccess({
        collection: { data: [thing], metadata: { totalCount: 1 } },
      }),
    );

    expect(selectAll.projector(state)).toEqual([thing]);
    expect(selectLoadingAll.projector(state)).toBe(false);
  });

  it('yields an empty collection when the API returns no data', () => {
    const state = thingReducers(
      initialState,
      ThingActions.loadAllSuccess({ collection: { data: [], metadata: null } }),
    );

    expect(selectAll.projector(state)).toEqual([]);
    expect(selectLoadingAll.projector(state)).toBe(false);
  });

  it('stores the error and preserves existing data on failure', () => {
    const loaded = thingReducers(
      initialState,
      ThingActions.loadAllSuccess({ collection: { data: [thing], metadata: null } }),
    );
    const state = thingReducers(
      loaded,
      ThingActions.loadAllError({ error: { message: 'Server error' } }),
    );

    expect(selectError.projector(state)).toEqual({ message: 'Server error' });
    expect(selectLoadingAll.projector(state)).toBe(false);
    expect(selectAll.projector(state)).toEqual([thing]);
  });
});
```

### Selectors

Test projection logic directly with `.projector()`. No store, no TestBed.

```ts
import { describe, expect, it } from 'vitest';

import { selectCollection, selectCurrent, selectMetaTotal } from './thing.selectors';

describe('thing selectors', () => {
  const entities = { '1': { id: '1', name: 'Kitchen', position: 0 } };

  describe('selectCurrent', () => {
    it('returns the entity matching the selected id', () => {
      expect(selectCurrent.projector(entities, '1')?.name).toBe('Kitchen');
    });

    it('returns null when no id is selected', () => {
      expect(selectCurrent.projector(entities, null)).toBeNull();
    });

    it('returns undefined when the selected id is not loaded', () => {
      expect(selectCurrent.projector(entities, '404')).toBeUndefined();
    });
  });

  describe('selectMetaTotal', () => {
    it('falls back to zero when metadata is absent', () => {
      expect(selectMetaTotal.projector({ meta: null })).toBe(0);
    });
  });
});
```

---

## 8. Verifying a test is load-bearing

**Break the code and confirm the test fails.** Ten seconds, and it is the only
reliable way to know a spec asserts anything.

Do this on every generated test you did not read line by line. The dominant
failure mode of generated tests is not incorrectness — it is tautology: mocking
everything the code touches, then asserting the mocks were called, which passes
regardless of whether the logic works.

Second failure mode, equally important: **a generated test encodes current
behavior, not correct behavior.** Point a generator at a buggy reducer and it
will faithfully assert the bug. For any logic where correctness is non-obvious,
write the first assertion by hand and delegate the variations.

---

## 9. Explicit non-goals

- **No coverage thresholds.** They optimize for testing whatever is easiest to
  test, which inverts the priority in §1.
- **No snapshot tests.** They pass until they don't and nobody reads the diff.
- **No test-only production code.** No exported internals, no injected seams
  that exist purely to be mocked. If something is hard to test, that is
  information about the design.
- **No dedicated backfill sprints.** Boy scout rule only — same discipline as
  tech debt reduction across the platform.