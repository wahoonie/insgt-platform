---
name: angular-core
description: Shared Angular conventions for all InsightPhotos Angular apps (insgt-ops, insgt-app). Use this skill for any task involving components, state management, NgRx, facades, signals, forms, routing, services, or testing across these repos. Load alongside an app-specific skill when working in a particular repo — this skill defines the target pattern both apps are converging toward.
---

# Angular Core — InsightPhotos Shared Conventions

This skill defines the **target patterns** shared across all InsightPhotos Angular apps. App-specific skills (insgt-ops, insgt-app) handle per-repo constraints and divergences — but those constraints are the exception. When in doubt, follow what's here.

All apps share one backend: **insgt-api** (Rails 7.2, PostgreSQL, Sidekiq/Redis).

---

## Angular Version Notes

Both apps target these conventions. Where versions diverge:

| Feature | Angular 19 (insgt-ops) | Angular 21 (insgt-app) |
|---|---|---|
| Signals maturity | Stable for new features; mixed with RxJS via `toSignal` | Prefer signals-first; minimize `toSignal` bridging |
| `input()` / `output()` | Available, adopt in new components | Prefer over `@Input()` / `@Output()` decorators |
| `@defer` | Available, use selectively | Use freely for route-level lazy loading |
| Legacy code | NgModules and manual reducers still exist | Fully standalone; no legacy to preserve |

When a section below says "new code," this applies to both apps.

---

## 1. The ViewModel Pattern (primary pattern for smart components)

Every container/page component follows this three-step pattern. It keeps templates declarative, eliminates `async` pipe complexity, and makes change detection fully predictable under `OnPush`. Never put raw observables or signals directly in a template — funnel everything through `vm`.

### Step 1 — Convert facade observables to private signals
```ts
private readonly things   = toSignal(this.facade.all$,        { initialValue: [] });
private readonly loading  = toSignal(this.facade.loadingAll$, { initialValue: false });
private readonly error    = toSignal(this.facade.error$,      { initialValue: null });
private readonly selectedId = signal<string | null>(null); // local UI state
```

### Step 2 — Combine into a single public `vm` computed
```ts
readonly vm = computed(() => ({
  things:     this.things(),
  loading:    this.loading(),
  error:      this.error(),
  hasThings:  this.things().length > 0,
  selectedId: this.selectedId(),
}));
```

### Step 3 — Template unwraps with `@if (vm(); as vm)`
```html
@if (vm(); as vm) {
  @if (vm.loading) {
    <app-spinner />
  } @else if (vm.error) {
    <app-error [message]="vm.error" />
  } @else {
    <app-thing-list
      [things]="vm.things"
      [selectedId]="vm.selectedId"
      (selected)="select($event)" />
  }
}
```

**Rules:**
- Template binds **only** to `vm` properties — never to raw signals, observables, or facade methods.
- `@if (vm(); as vm)` ensures one signal read per change detection cycle. Don't inline `vm().things` directly; always unwrap with `as`.
- Local UI state (`selectedId`, `isOpen`, etc.) lives as a `signal()` and is included in `vm` — not as separate template bindings.
- Use `computed()` to derive state. Use `effect()` only for imperative side effects (API calls, navigation, focus management).

### Reactive side effects with `effect()`
```ts
constructor() {
  effect(() => {
    const id = this.id(); // signal-based route input
    if (!id) return;      // guard: effect runs immediately on init
    this.facade.dispatch(this.facade.actions.LoadOne, {
      resource: { id },
      params: { includes: ['photos'] },
    });
  });
}
```
`effect()` must live in the `constructor()` — that's where Angular's injection context is active. Keep each effect focused on exactly one side effect; split them if a second concern creeps in.

---

## 2. Component Conventions

### Standalone components
```ts
@Component({
  standalone: true,
  imports: [CommonModule, MatTableModule, ChildCard],
  selector: 'app-thing-list',
  templateUrl: './thing-list.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
```
Always `OnPush`. The ViewModel pattern depends on it — without `OnPush`, Angular will re-render on every tick and the signal memoization is wasted.

### Dependency injection
Use `inject()`. It's more refactor-friendly than constructor injection and works correctly with `DestroyRef` (needed for `takeUntilDestroyed`).
```ts
private readonly facade     = inject(ThingFacade);
private readonly destroyRef = inject(DestroyRef);
private readonly dialog     = inject(MatDialog);
private readonly router     = inject(Router);
```

### Subscription cleanup
```ts
// In the class body — not the constructor
private readonly things$ = this.facade.all$
  .pipe(takeUntilDestroyed(this.destroyRef))
  .subscribe(...);
```
`takeUntilDestroyed` ties the subscription lifetime to the component's destroy cycle automatically. It's preferable to the older `ngOnDestroy` + `Subject` pattern because it requires no lifecycle hook and is harder to accidentally omit.

### Template control flow
Always use the block control flow syntax (`@if`, `@for`, `@switch`) in new templates. The directive-based syntax (`*ngIf`, `*ngFor`) still works but is the legacy form.
```html
<!-- ✅ modern -->
@for (thing of vm.things; track thing.id) {
  <app-thing-card [thing]="thing" />
} @empty {
  <p>No things yet.</p>
}

<!-- ❌ legacy — don't use in new templates -->
<app-thing-card *ngFor="let thing of vm.things" [thing]="thing" />
```

---

## 3. State Management (NgRx → Facade → Component)

```
Component → Facade → NgRx Store (actions / reducers / selectors / effects)
               ↕
           API Service (ResourceApiService)
```

The facade is the only entry point into the store from the component layer. Components never import selectors or dispatch actions directly — this keeps components testable and the state layer swappable.

### Feature file layout
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

### Facade pattern
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
  readonly actions     = resourceActions; // exposed for component dispatch
}
```

Dispatch from components via the facade:
```ts
this.facade.dispatch(this.facade.actions.LoadAll,   { params });
this.facade.dispatch(this.facade.actions.Add,        { resource: thing });
this.facade.dispatch(this.facade.actions.Update,     { resource: thing });
this.facade.dispatch(this.facade.actions.Delete,     { resource: thing });
this.facade.dispatch(this.facade.actions.SetCurrentId, { id });
```

> For full NgRx boilerplate — actions helpers, effects helpers, entity adapter, selectors, provider — see `references/ngrx-patterns.md`.

---

## 4. Entity Models

New entities use interfaces (not classes). Classes are a legacy pattern.

```ts
export interface Thing {
  id: string;
  name: string;
  position: number;
}

export interface ThingCollection { data: Thing[]; metadata: Meta | null; }
export interface ThingSearch     { id?: string; perPage?: number; page?: number; term?: string; }
```

Fields config is used to drive form construction and validation error display — centralize it in the model file so the form and its error messages stay in sync:
```ts
export const thingFields = {
  name: {
    id: 'name',
    label: 'Name',
    required: true,
    validations: [Validators.required],
    errors: [{ type: 'required', message: 'Name is required' }],
  },
  key: {
    id: 'key',
    label: 'Key',
    required: true,
    validations: [Validators.required, Validators.pattern(/^\S*$/)],
    errors: [
      { type: 'required', message: 'Key is required' },
      { type: 'pattern',  message: 'Key cannot contain whitespace' },
    ],
  },
};
```
Optional field properties: `type` (`'textarea' | 'number' | 'select' | 'toggle' | 'date'`), `maxLength`, `minLength`, `options`, `tip`.

---

## 5. API Services

```ts
@Injectable()
export class ThingService {
  private api = this.resourceApi.createClient({ endpoint: 'things', nameSpace: 'thing' });
  constructor(private resourceApi: ResourceApiService) {}

  all(params?: ThingSearch): Observable<ThingCollection> { return this.api.all(params); }
  one(id: string): Observable<Thing>                     { return this.api.one(id); }
  create(thing: Thing): Observable<Thing>                { return this.api.create(thing); }
  update(thing: Thing): Observable<Thing>                { return this.api.update(thing); }
  destroy(thing: Thing): Observable<any>                 { return this.api.destroy(thing.id); }
}
```

Services are thin HTTP adapters — no business logic, no state. The facade and store own the state; the service just maps to/from the API.

---

## 6. Routing

```ts
// feature.routes.ts
export default [
  {
    path: '',
    canActivate: [AuthGuardService],
    data: { roles: [roles.admin] },
    providers: [...ThingProvider],
    children: [{ path: '', component: ThingListPage }],
  },
] satisfies Route[];
```

Lazy-load feature routes from the root router. The `providers` array on the route (from `ThingProvider`) scopes the state slice to the feature — it's only registered when the route is activated and destroyed when it's left.

App-specific routing constraints (hash routing, module-based router registration) are documented in each app's skill.

---

## 7. Naming Conventions

### Class and file names
| Directory | File | Class |
|---|---|---|
| `pages/thing-list/` | `thing-list.ts` | `ThingListPage` |
| `dialogs/thing-upsert/` | `thing-upsert.ts` | `ThingUpsertDialog` |
| `components/thing-card/` | `thing-card.ts` | `ThingCard` |

No `Component` suffix anywhere — not in class names, not in file names. The containing directory (`pages/`, `dialogs/`, `components/`) already communicates the type; appending `Component` adds length without adding information.

### Variable naming
- **Signals:** no suffix — `selectedId`, `loading`, `things`
- **Observables:** `$` suffix, only at facade/service level — `things$`, `loadingAll$`; avoid `$` in component class bodies
- **Computed:** descriptive names — `vm`, `filteredThings`, `hasItems`

---

## 8. Testing

All apps use Cypress for e2e testing only — there is no unit test framework (no Jasmine, Jest, or Karma). This makes e2e tests the only automated regression safety net, so every new feature must include them.

Test user flows, not implementation details. A test that breaks when you rename a CSS class is not useful.

```ts
// Use data-cy attributes — decoupled from styling and Angular internals
cy.get('[data-cy="thing-list"]').should('be.visible');
cy.get('[data-cy="add-thing-btn"]').click();
cy.get('[data-cy="thing-name-input"]').type('New Thing');
cy.get('[data-cy="save-btn"]').click();
cy.get('[data-cy="thing-list"]').should('contain', 'New Thing');
```

**Minimum coverage for a CRUD feature:**
- List loads and displays items
- Create dialog: opens, submits, new item appears in list
- Edit dialog: opens with pre-filled values, updates correctly
- Delete: removes item from list
- Error state: displays correctly when API call fails (use `cy.intercept()` to stub the failure)

Test files mirror the feature directory structure: `cypress/e2e/feature-name/`.

---

## 9. General Rules

- **No `any` in new code** — use proper interfaces or `unknown` with type guards. `any` disables the type safety that makes large-scale refactoring safe.
- **Keep components thin** — business logic belongs in facades and services. A component's job is to translate between the ViewModel and the template.
- **No template logic** — derive computed state in the component class via `computed()`, not via ternaries or method calls in the template. Template expressions that can't be read at a glance are a sign that something belongs in the component.
- **Max 400 lines per file, 75 lines per function** — these limits are signals to split responsibilities, not rules to satisfy by cramming. If you're approaching them, look for the seam.
- **Path aliases:** `@app/*` → `src/app/*`, `@env/*` → `src/environments/*`

## Import Organization

All `.ts` files use a consistent categorized import block structure with labeled divider comments. See the `angular-import-organization` skill for the full category list, classification rules, and a worked example. Apply it whenever generating a new file or cleaning up an existing one.