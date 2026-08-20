---
name: angular-ngrx-state
description: NgRx state-layer conventions for InsightPhotos Angular apps (insgt-ops, insgt-app) — actions, reducers, selectors, effects, facades, collection metadata, and count semantics. Use whenever creating or editing anything under data-access/state/ or store/, any facade, or any file performing arithmetic on collection counts. Load alongside angular-core and the relevant app-specific skill.
---

# Angular NgRx State — InsightPhotos Shared Conventions

State-layer conventions shared across all InsightPhotos Angular apps. Load alongside `angular-core` (component and naming conventions) and the app-specific skill for the repo you're in.

For unit testing this layer, see `angular-unit-testing`.

---

## 1. The Pipeline

```
Component → Facade → NgRx Store (actions / reducers / selectors / effects)
               ↕
           API Service (ResourceApiService)
```

The facade is the only entry point into the store from the component layer. Components never import selectors or dispatch actions directly — this keeps components testable and the state layer swappable.

---

## 2. Feature File Layout

```
feature/
├── data-access/
│   ├── feature.model.ts            # Interface, collection, search, fields
│   ├── feature.service.ts          # HTTP (ResourceApiService)
│   ├── feature-facade.service.ts   # Facade extending BaseFacade
│   ├── feature.provider.ts         # provideState + provideEffects + Service
│   └── state/
│       ├── feature.state.ts
│       ├── feature.actions.ts
│       ├── feature.reducer.ts
│       ├── feature.selectors.ts
│       └── feature.effects.ts
├── pages/feature-list/
├── dialogs/feature-upsert/
├── components/feature-card/
└── feature.routes.ts
```

Two state directory conventions coexist mid-migration: `data-access/state/` (target) and `store/` (legacy). New features use `data-access/state/`.

---

## 3. Actions — Two Generations

### Target: `createActionGroup` (first-party NgRx, no custom helper library)

```ts
export const ThingActions = createActionGroup({
  source: 'Things',
  events: {
    'Load All':         props<{ params: ThingSearch }>(),
    'Load All Success': props<{ collection: ThingCollection }>(),
    'Load All Error':   props<{ error: ApiError }>(),
    'Add':              props<{ resource: Thing }>(),
    'Add Success':      props<{ resource: Thing }>(),
    'Add Error':        props<{ error: ApiError }>(),
    'Update':           props<{ resource: Thing }>(),
    'Update Success':   props<{ resource: Thing }>(),
    'Update Error':     props<{ error: ApiError }>(),
    'Delete':           props<{ resource: Thing }>(),
    'Delete Success':   props<{ resource: Thing }>(),
    'Delete Error':     props<{ error: ApiError }>(),
    'Set Current Id':   props<{ id: string }>(),
  },
});
```

Event names are space-separated strings — NgRx auto-generates camelCase creators (`ThingActions.loadAll`, `ThingActions.loadAllSuccess`, etc.). Use `emptyProps()` for actions with no payload.

### Legacy: helper factory pattern

Existing features use `createLoadAllActions`, `createAddActions` etc. from `@app/core/services/state-actions.helper`. When editing a legacy actions file, match the existing pattern. When creating a new feature or migrating an existing one, use `createActionGroup`.

**Factory returns are positional.** `createCrudResourceActions` returns a fixed-order tuple. Destructuring in the wrong order type-checks — the creators are structurally similar enough that TypeScript accepts a swap. The symptom is a slice where failures populate the collection and successes set the error flag. Verify order against the factory definition when wiring a new slice.

---

## 4. `ReducerService` is Forked, Not Shared

Both apps have a `ReducerService` — `insgt-ops/src/app/core/reducer.service.ts` and
`insgt-app/src/app/core/services/reducer.service.ts`. Same class name, same method names,
**independent copies that have drifted.** There is no shared package; nothing keeps them in
sync.

The divergence that bites:

| | insgt-ops | insgt-app |
|---|---|---|
| `updateResourceSuccess` on a collection record | **replaces** it wholesale | **merges** the payload into it |
| `ReducerHelperOptions` | no `resourceId` | has `resourceId`, so it can match on a key other than `id` |

So the same action against the same-shaped state produces different results per app. A partial
payload — the three-key body a `PUT /orders/:id/order_event` returns, say — leaves the other
fields intact in insgt-app and wipes them in insgt-ops.

**Never port a fix between the two by copying the method.** Read the target app's version first
and re-derive the change. A patch that is correct in one is silently wrong in the other, and
neither app's tests will catch it, because each spec only exercises its own copy.

The same applies to `state-actions.helper` and `state-effects.helper`, which are also duplicated
rather than shared. Treat any `core/` helper with a twin in the sibling repo as forked until you
have diffed them.

---

## 5. Collection Metadata and Count Semantics

### Absent counts propagate as null

If a count is null or undefined, arithmetic on it yields **null** — never `0`, never `NaN`.

```ts
const next = totalCount == null ? null : totalCount + 1;
```

`(count ?? 0) + 1` is rejected: it converts "unknown" into "we have one record" and fails
silently, indistinguishable from a genuine single-record collection. Bare arithmetic is worse in
a different way — `undefined + 1` is `NaN`, which then persists through every subsequent
operation until a fresh collection read clears it.

`pageMax` derives from `totalCount`, so `pageMax` is null whenever `totalCount` is. Consumers
render null as an em-dash, a spinner, or nothing — never as a number. Pagination hides rather
than offering one page.

This is the read-side null-not-zero rule running in the write direction. Same principle: **zero
is a measurement claim, null is honest about not having one.**

### Guard absent metadata

`state[collection].metadata` may be absent entirely, not just empty. Reading `.pageMax` off it
unguarded throws. Treat missing metadata as absent counts, not as an error.

### API contract

Index actions always emit real counts. `metadata: {}` is a contract violation, not an empty
result — a genuinely empty collection emits `totalCount: 0`. When a client-side guard is needed
because an endpoint ships `{}`, fix the endpoint too; the guard is defence in depth, not the
solution.

---

## 6. Facade Pattern

```ts
@Injectable({ providedIn: 'root' })
export class ThingFacade extends withSelectOptions(BaseFacade) {
  readonly all$        = this.select(selectAll);
  readonly loadingAll$ = this.select(selectLoadingAll);
  readonly loadingOne$ = this.select(selectLoadingOne);
  readonly current$    = this.select(selectCurrent);
  readonly meta$       = this.select(selectMeta);
  readonly metaTotal$  = this.select(selectMetaTotal);
  readonly collection$ = this.select(selectCollection);
  readonly actions     = ThingActions; // action group — components dispatch through this
}
```

Dispatch from components via the facade — components never import the action group directly:
```ts
this.facade.dispatch(this.facade.actions.loadAll({ params }));
this.facade.dispatch(this.facade.actions.add({ resource: thing }));
this.facade.dispatch(this.facade.actions.update({ resource: thing }));
this.facade.dispatch(this.facade.actions.delete({ resource: thing }));
this.facade.dispatch(this.facade.actions.setCurrentId({ id }));
```

---

## 7. Error Handling in Effects

`catchError` belongs **inside** the `switchMap`, not on the outer stream.

```ts
// ✅ stream survives the error
switchMap(({ params }) =>
  this.service.all(params).pipe(
    map(collection => ThingActions.loadAllSuccess({ collection })),
    catchError(error => of(ThingActions.loadAllError({ error }))),
  ),
)

// ❌ first failure kills the effect permanently
switchMap(({ params }) => this.service.all(params)).pipe(
  catchError(...)
)
```

With `catchError` on the outer stream, the first API failure errors the outer observable, which
completes and unsubscribes from `actions$` for good. The feature stops responding to that action
type until page reload. Nothing throws and nothing logs — it just goes quiet.

**Error actions must clear the loading flag they set.** A collection read that fails must
dispatch the collection-scoped error action, not a generic resource error — a generic one leaves
`collectionLoading` true and the spinner never clears.

---

## 8. Documentation Targets

When writing or reviewing state files, document these specifically if present:

- Why a particular loading flag exists (`loadingAll` vs `loadingOne`) and what triggers each
- Why `selectedId` / `selectedIds` are separate fields
- Non-standard adapter configuration (custom `sortComparer`, non-`id` `selectId`)
- Any reducer case that does something other than set/upsert/remove an entity
- Any count arithmetic, and what it does when the count is absent

See `angular-core` §9 for the `ARCHITECTURE NOTES` block format.

---

## 9. On the Horizon

**`@ngrx/entity` migration.** Hand-rolled collection manipulation — array splicing, count
decrements, metadata guards — is targeted for replacement by entity adapter methods
(`addOne`, `removeOne`, `upsertOne`), which handle these cases correctly. Sequenced after the
Angular 21/22 upgrade, done incrementally rather than as a sweep.

When fixing a defect in hand-rolled collection code, check first whether the entity migration
would delete that code outright. If so, the fix is usually throwaway work — prefer pinning the
current behaviour with a `FLAGGED DEFECT:` spec comment and letting the migration retire it.

> For full NgRx boilerplate — actions, reducer, effects, selectors, provider — see
> `references/ngrx-patterns.md`.