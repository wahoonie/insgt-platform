# NgRx Patterns

Complete boilerplate reference for the target NgRx pattern used in new features.
The SKILL.md covers actions (`createActionGroup`) and facades — this file covers state, reducer, effects, selectors, and provider wiring.

Read this file when scaffolding a new feature's `data-access/state/` directory or migrating a legacy feature from the old `ReducerService` / action-factory pattern.

---

## State

```ts
// data-access/state/things.state.ts

// ── Angular & NgRx ────────────────────
import { EntityState, EntityAdapter, createEntityAdapter } from '@ngrx/entity';

// ── Models ────────────────────────────
import { Thing } from '../thing.model';
import { Meta, ApiError } from '@app/shared/models';

// ────────────────────────────────────────────────────────────────────────────

export interface ThingsState extends EntityState<Thing> {
  selectedId: number | null;
  selectedIds: number[];
  loadingAll: boolean;
  loadingOne: boolean;
  error: ApiError | null;
  meta: Meta | null;
}

export const adapter: EntityAdapter<Thing> = createEntityAdapter<Thing>({
  selectId: (thing: Thing) => thing.id,
  // sortComparer is optional — omit for insertion-order, or provide one:
  // sortComparer: (a, b) => (a.position ?? 0) - (b.position ?? 0),
});

export const initialState: ThingsState = adapter.getInitialState({
  selectedId: null,
  selectedIds: [],
  loadingAll: false,
  loadingOne: false,
  error: null,
  meta: null,
});

export const featureKey = 'things';
```

### Checklist — every field in initialState must have a value

| Field | Type | Initial | Purpose |
|---|---|---|---|
| `ids` / `entities` | (from EntityState) | `[]` / `{}` | Entity adapter manages these |
| `selectedId` | `number \| null` | `null` | Currently selected resource |
| `selectedIds` | `number[]` | `[]` | Multi-select (batch operations) |
| `loadingAll` | `boolean` | `false` | Collection load in progress |
| `loadingOne` | `boolean` | `false` | Single-resource CRUD in progress |
| `error` | `ApiError \| null` | `null` | Last error, cleared on next request |
| `meta` | `Meta \| null` | `null` | Pagination from API response |

If you add a field to the interface, add it to `initialState`. If you forget, the store slice will have `undefined` values that break selectors.

---

## Reducer

```ts
// data-access/state/things.reducer.ts

// ── NgRx ──────────────────────────────
import { createReducer, on } from '@ngrx/store';
import { Update } from '@ngrx/entity';

// ── State ─────────────────────────────
import { adapter, initialState } from './things.state';
import { ThingActions } from './things.actions';

// ── Models ────────────────────────────
import { Thing } from '../thing.model';

// ────────────────────────────────────────────────────────────────────────────

export const thingsReducer = createReducer(
  initialState,

  // ── Selection ───────────────────────────────────────────────────────────
  on(ThingActions.setCurrentId, (state, { id }) => ({
    ...state,
    selectedId: id,
  })),

  // ── Load All (collection) ──────────────────────────────────────────────
  on(ThingActions.loadAll, (state) => ({
    ...state,
    loadingAll: true,
    error: null,
  })),

  on(ThingActions.loadAllSuccess, (state, { collection }) =>
    adapter.setAll(collection.data, {
      ...state,
      loadingAll: false,
      error: null,
      meta: collection.metadata,
    })
  ),

  on(ThingActions.loadAllError, (state, { error }) => ({
    ...state,
    loadingAll: false,
    error,
  })),

  // ── Load One ───────────────────────────────────────────────────────────
  on(ThingActions.loadOne, (state) => ({
    ...state,
    loadingOne: true,
    error: null,
  })),

  on(ThingActions.loadOneSuccess, (state, { resource }) =>
    adapter.upsertOne(resource, {
      ...state,
      loadingOne: false,
      error: null,
    })
  ),

  on(ThingActions.loadOneError, (state, { error }) => ({
    ...state,
    loadingOne: false,
    error,
  })),

  // ── Add ────────────────────────────────────────────────────────────────
  on(ThingActions.add, (state) => ({
    ...state,
    loadingOne: true,
    error: null,
  })),

  on(ThingActions.addSuccess, (state, { resource }) =>
    adapter.setOne(resource, {
      ...state,
      loadingOne: false,
      error: null,
    })
  ),

  on(ThingActions.addError, (state, { error }) => ({
    ...state,
    loadingOne: false,
    error,
  })),

  // ── Update ─────────────────────────────────────────────────────────────
  on(ThingActions.update, (state) => ({
    ...state,
    loadingOne: true,
    error: null,
  })),

  on(ThingActions.updateSuccess, (state, { resource }) => {
    const update: Update<Thing> = {
      id: resource.id,
      changes: resource,
    };
    return adapter.updateOne(update, {
      ...state,
      loadingOne: false,
      error: null,
    });
  }),

  on(ThingActions.updateError, (state, { error }) => ({
    ...state,
    loadingOne: false,
    error,
  })),

  // ── Delete ─────────────────────────────────────────────────────────────
  on(ThingActions.delete, (state) => ({
    ...state,
    loadingOne: true,
    error: null,
  })),

  on(ThingActions.deleteSuccess, (state, { resource }) =>
    adapter.removeOne(resource.id, {
      ...state,
      loadingOne: false,
      error: null,
    })
  ),

  on(ThingActions.deleteError, (state, { error }) => ({
    ...state,
    loadingOne: false,
    error,
  })),
);
```

### Loading flag lifecycle — the rule that prevents stuck spinners

Every action that sets a loading flag to `true` **must** have both a success handler and an error handler that reset it to `false`. Missing the error handler is the #1 NgRx bug — the user sees an infinite spinner when the API returns a 500.

```
loadAll         → loadingAll: true
loadAllSuccess  → loadingAll: false   ← must exist
loadAllError    → loadingAll: false   ← must exist — this is the one that gets missed

add / update / delete       → loadingOne: true
addSuccess / updateSuccess  → loadingOne: false
addError / updateError      → loadingOne: false   ← must exist
```

When reviewing a reducer, verify the flag lifecycle by scanning for every `on()` that sets `true` and confirming the matching `Success` and `Error` handlers both set `false`.

### Entity adapter method reference

| Method | Use when |
|---|---|
| `adapter.setAll(items, state)` | Replacing the entire collection (Load All) |
| `adapter.setOne(item, state)` | Adding or replacing a single entity (Add) |
| `adapter.upsertOne(item, state)` | Insert-or-update a single entity (Load One) |
| `adapter.updateOne({ id, changes }, state)` | Partial update of an existing entity (Update) |
| `adapter.removeOne(id, state)` | Removing a single entity (Delete) |
| `adapter.upsertMany(items, state)` | Merging a batch of entities |

---

## Effects

```ts
// data-access/state/things.effects.ts

// ── Angular ───────────────────────────
import { inject, Injectable } from '@angular/core';

// ── NgRx ──────────────────────────────
import { Actions, createEffect, ofType } from '@ngrx/effects';

// ── RxJS ──────────────────────────────
import { of } from 'rxjs';
import { catchError, map, switchMap } from 'rxjs/operators';

// ── State ─────────────────────────────
import { ThingActions } from './things.actions';

// ── Application ───────────────────────
import { ThingsService } from '../things.service';

// ────────────────────────────────────────────────────────────────────────────

@Injectable()
export class ThingsEffects {
  private readonly actions$ = inject(Actions);
  private readonly resourceService = inject(ThingsService);

  loadAll$ = createEffect(() =>
    this.actions$.pipe(
      ofType(ThingActions.loadAll),
      switchMap(({ params }) =>
        this.resourceService.all(params).pipe(
          map(collection => ThingActions.loadAllSuccess({ collection })),
          catchError(error => of(ThingActions.loadAllError({ error })))
        )
      )
    )
  );

  loadOne$ = createEffect(() =>
    this.actions$.pipe(
      ofType(ThingActions.loadOne),
      switchMap(({ resource }) =>
        this.resourceService.one(resource.id).pipe(
          map(resource => ThingActions.loadOneSuccess({ resource })),
          catchError(error => of(ThingActions.loadOneError({ error })))
        )
      )
    )
  );

  add$ = createEffect(() =>
    this.actions$.pipe(
      ofType(ThingActions.add),
      switchMap(({ resource }) =>
        this.resourceService.create(resource).pipe(
          map(resource => ThingActions.addSuccess({ resource })),
          catchError(error => of(ThingActions.addError({ error })))
        )
      )
    )
  );

  update$ = createEffect(() =>
    this.actions$.pipe(
      ofType(ThingActions.update),
      switchMap(({ resource }) =>
        this.resourceService.update(resource).pipe(
          map(resource => ThingActions.updateSuccess({ resource })),
          catchError(error => of(ThingActions.updateError({ error })))
        )
      )
    )
  );

  delete$ = createEffect(() =>
    this.actions$.pipe(
      ofType(ThingActions.delete),
      switchMap(({ resource }) =>
        this.resourceService.destroy(resource).pipe(
          map(() => ThingActions.deleteSuccess({ resource })),
          catchError(error => of(ThingActions.deleteError({ error })))
        )
      )
    )
  );
}
```

### Effect rules

- **`catchError` inside `switchMap`, not outside.** If `catchError` wraps the outer pipe, a single API failure kills the effect permanently — no future actions of that type will be handled.
- **`switchMap` for reads, `switchMap` for writes.** The codebase uses `switchMap` consistently. For write operations where you need to guarantee every request completes, `concatMap` or `exhaustMap` are alternatives — but match the existing pattern unless there's a specific concurrency bug to fix.
- **Use `inject()` for DI**, not constructor parameters.
- **Delete effects return the original resource** (not the API response) so the reducer can call `removeOne(resource.id)`.

---

## Selectors

```ts
// data-access/state/things.selectors.ts

// ── NgRx ──────────────────────────────
import { createFeatureSelector, createSelector } from '@ngrx/store';

// ── State ─────────────────────────────
import { ThingsState, adapter, featureKey } from './things.state';

// ────────────────────────────────────────────────────────────────────────────

const featureSelector = createFeatureSelector<ThingsState>(featureKey);

// Entity adapter auto-selectors
export const {
  selectIds,       // number[]
  selectEntities,  // Record<number, Thing>
  selectAll,       // Thing[]
  selectTotal,     // number
} = adapter.getSelectors(featureSelector);

// Single-field selectors
export const selectCurrentId   = createSelector(featureSelector, state => state.selectedId);
export const selectSelectedIds = createSelector(featureSelector, state => state.selectedIds);
export const selectLoadingAll  = createSelector(featureSelector, state => state.loadingAll);
export const selectLoadingOne  = createSelector(featureSelector, state => state.loadingOne);
export const selectError       = createSelector(featureSelector, state => state.error);
export const selectMeta        = createSelector(featureSelector, state => state.meta);
export const selectMetaTotal   = createSelector(featureSelector, state => state.meta?.totalCount ?? 0);

// Composed selectors
export const selectCurrent = createSelector(
  selectEntities,
  selectCurrentId,
  (entities, selectedId) => (selectedId != null ? entities[selectedId] ?? null : null)
);

export const selectCollection = createSelector(
  selectAll,
  selectMeta,
  (data, metadata) => ({ data, metadata })
);
```

### Selector naming

| Selector | Returns | Facade property |
|---|---|---|
| `selectAll` | `Thing[]` (denormalized array) | `all$` |
| `selectEntities` | `Record<id, Thing>` (lookup map) | (rarely exposed) |
| `selectCurrent` | `Thing \| null` | `current$` |
| `selectLoadingAll` | `boolean` | `loadingAll$` |
| `selectLoadingOne` | `boolean` | `loadingOne$` |
| `selectMeta` | `Meta \| null` | `meta$` |
| `selectMetaTotal` | `number` | `metaTotal$` |
| `selectCollection` | `{ data, metadata }` | `collection$` |

---

## Provider

```ts
// data-access/things.provider.ts

// ── NgRx ──────────────────────────────
import { provideState } from '@ngrx/store';
import { provideEffects } from '@ngrx/effects';

// ── State ─────────────────────────────
import { thingsReducer } from './state/things.reducer';
import { ThingsEffects } from './state/things.effects';
import { featureKey } from './state/things.state';

// ── Application ───────────────────────
import { ThingsService } from './things.service';

// ────────────────────────────────────────────────────────────────────────────

export const ThingsProvider = [
  provideState({ name: featureKey, reducer: thingsReducer }),
  provideEffects(ThingsEffects),
  ThingsService,
];
```

Register in the feature's route file:

```ts
// things.routes.ts
export default [
  {
    path: '',
    providers: [...ThingsProvider],
    children: [
      { path: '', component: ThingsListPage },
    ],
  },
] satisfies Route[];
```

State is registered when the route is lazy-loaded and torn down when the user navigates away. No `StoreModule` needed.

---

## Legacy pattern reference

Older features use a different set of helpers. When editing legacy code, match the existing pattern — don't partially migrate a file.

| Layer | Legacy | Target |
|---|---|---|
| Actions | `createAction()` + factories from `state-actions.helper` | `createActionGroup()` |
| State | Plain class, manual fields | `EntityState<T>` with adapter |
| Loading flags | `loading`, `resourceLoading`, custom per-sub-resource | `loadingAll`, `loadingOne` |
| Reducer | `ReducerService` helpers (`crudResource`, `crudResourceError`) | Direct entity adapter calls |
| Selectors | `get<Field>` one-to-one per state property | `select<Field>` + adapter auto-selectors |
| Effects | Constructor DI, same `switchMap`/`catchError` pattern | `inject()` DI, same Rx pattern |
| Registration | `StoreModule` NgModule class | `provideState()` + `provideEffects()` in route providers |
| Facade dispatch | `this.facade.dispatch(this.facade.actions.LoadAll, { params })` | `this.facade.dispatch(this.facade.actions.loadAll({ params }))` |

Legacy `ReducerService` methods and what they do — useful when reading old reducers:

| Method | Sets loading to | Sets error to |
|---|---|---|
| `crudResource(state, payload, keys)` | `true` | `undefined` |
| `crudResourceError(state, payload, keys)` | `false` | `payload.error` |
| `createResourceSuccess(state, payload, keys)` | `false` | `undefined` |
| `updateResourceSuccess(state, payload, keys)` | `false` | `undefined` |
| `deleteResourceSuccess(state, payload, keys)` | `false` | `undefined` |
| `readCollection(state, payload, keys)` | `true` | `undefined` |
| `readCollectionSuccess(state, payload, keys)` | `false` | `undefined` |
| `readCollectionError(state, payload, keys)` | `false` | `payload.error` |
