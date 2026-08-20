---
name: angular-core
description: Shared Angular conventions for all InsightPhotos Angular apps (insgt-ops, insgt-app). Use this skill for any task involving components, facades, signals, forms, routing, services, naming, or testing across these repos. Load alongside an app-specific skill when working in a particular repo, and alongside angular-ngrx-state for any work touching the state layer — this skill defines the target pattern both apps are converging toward.
---

# Angular Core — InsightPhotos Shared Conventions

This skill defines the **target patterns** shared across all InsightPhotos Angular apps. App-specific skills (insgt-ops, insgt-app) handle per-repo constraints and divergences — but those constraints are the exception. When in doubt, follow what's here.

All apps share one backend: **insgt-api** (Rails 7.2, PostgreSQL, Sidekiq/Redis).

**Related skills:**
- `angular-ngrx-state` — actions, reducers, selectors, effects, facades, count semantics. Load for any state-layer work.
- `angular-unit-testing` — Vitest specs for state-layer logic.
- `angular-import-organization` — import block structure.

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

## 3. Entity Models

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

**API responses are camelCase.** insgt-api serializes every response to camelCase (its Rails/jbuilder source is snake_case, but keys are camelized on the way out), so response interfaces use camelCase keys — `monthlyTrend`, `lifetimeValueCents`, never `monthly_trend`. Match the wire, not the Rails template. A snake_case key on a response model is a *silent* bug: it reads `undefined` with no compile or runtime error, so the data just never binds.

**Count fields are nullable.** `metadata: Meta | null`, and counts inside `Meta` are `number | null`. Absence is a real state — see `angular-ngrx-state` for how it propagates.

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

## 4. API Services

Three generations of API service exist across the codebase. Always identify which generation a file uses before editing it.

> Generation docs are deleted as generations die. When Gen 1 has no remaining call sites, remove its subsection rather than leaving it as reference.

### Generation 3 — Composition (target for all new code)

`ResourceApiService` is `@Injectable({ providedIn: 'root' })` and acts as a factory. Feature services inject it and call `createClient()` — they extend nothing. Method names have no underscore prefix.

```ts
// ────────────────────────────────
// 🅰️ Angular
// ────────────────────────────────
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

// ────────────────────────────────
// 🧱 Application
// ────────────────────────────────
import { ResourceApiService } from '@app/shared/api/resource-api.service.refactored';

// ────────────────────────────────
// 📦 Data Models
// ────────────────────────────────
import { Thing, ThingCollection, ThingSearch } from './thing.model';

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

For non-standard endpoints (nested resources, custom actions), use `setUrl()` before the call:
```ts
getPhotosForOrder(orderId: string): Observable<PhotoCollection> {
  this.api.setUrl(`orders/${orderId}/photos`);
  return this.api.all<PhotoCollection>();
}
```

### Generation 2 — Typed inheritance (intermediate — edit to match, don't extend further)

`ResourceApiService` (non-refactored) is an inheritance base class. Feature services extend it, pass `instanceClass`/`collectionClass` via constructor, and call underscore-prefixed protected methods. You'll encounter this in partially-migrated code.

```ts
export class ThingService extends ResourceApiService {
  constructor(public injector: Injector) {
    super({ endpoint: 'things', nameSpace: 'thing', injector });
  }
  all(params?: ThingSearch)  { return this._all<ThingCollection>(params); }
  one(id: string)            { return this._one<Thing>(id); }
  create(thing: Thing)       { return this._create<Thing>(thing); }
  update(thing: Thing)       { return this._update<Thing>(thing); }
  destroy(thing: Thing)      { return this._destroy(thing.id); }
}
```

### Generation 1 — Legacy inheritance (edit to match, migrate when touching)

`ApiService` (or `InsightApiService` in insgt-app) — same underscore-method inheritance pattern but requires `instanceClass` and `collectionClass` constructor params and uses `Injector`. Auth is attached manually via `httpOptions()`. When you encounter this pattern, match it for the edit but flag it as a migration candidate.

---

**Rule:** New services always use Generation 3. When editing a Gen 1 or Gen 2 service, match the existing pattern for the edit — don't partially migrate a service mid-task. If the task is explicitly a migration, convert the entire service file at once.

Services are thin HTTP adapters — no business logic, no state. The facade and store own state; the service only maps to/from the API.

---

## 5. Routing

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

## 6. Naming Conventions

### Core principle

**Drop redundant framework suffixes. Keep semantic role suffixes.**

`Component` carries no information — the `@Component` decorator already says the class is a component. `Page` and `Dialog` do carry information: they tell you *how the class is used* without opening the file.

```ts
// Preferred
UsersListPage        UserDetailPage
UserSettingsDialog   DeleteUserDialog
Avatar               StatusBadge        UserForm       UsersTable

// Avoid
UsersListComponent   UserDetailComponent
UserSettingsDialogComponent             AvatarComponent
```

> The guiding rule: **remove framework implementation suffixes; retain names that communicate architectural or UI meaning.**

### Class and file names

**The file name is the class name in kebab-case — always, with no exceptions.** Whatever suffix the class carries, the file carries too; where the class has no suffix, neither does the file. One mechanical rule, applied in one direction, so you can derive either name from the other without thinking.

| Directory | File | Class |
|---|---|---|
| `pages/thing-list/` | `thing-list-page.ts` | `ThingListPage` |
| `pages/thing-detail/` | `thing-detail-page.ts` | `ThingDetailPage` |
| `dialogs/thing-upsert/` | `thing-upsert-dialog.ts` | `ThingUpsertDialog` |
| `dialogs/delete-thing/` | `delete-thing-dialog.ts` | `DeleteThingDialog` |
| `components/thing-card/` | `thing-card.ts` | `ThingCard` |
| `components/status-badge/` | `status-badge.ts` | `StatusBadge` |

Template and style files share the base filename. **Styles are `.css`, not `.scss`** — the only `.scss` in either repo is insgt-ops' Material theme, which must be Sass:

```text
thing-list-page.ts
thing-list-page.html
thing-list-page.css
```

**The separator is a hyphen, not a dot.** `thing-list-page.ts`, never `thing-list.page.ts`; `thing-upsert-dialog.ts`, never `thing-upsert.dialog.ts`. The dot form is a type-marker convention inherited from older Angular scaffolding; the hyphen form is what you get from mechanically kebab-casing the class name, which is the whole point of the rule. Also never `.component.ts`.

### Roles

**Pages** — top-level routed screens. Suffix `Page`, so a route reads unambiguously:

```ts
{ path: 'users', component: UsersListPage }
```

**Dialogs** — anything presented as a dialog or modal. Suffix `Dialog`. Not `DialogComponent`.

**Embedded components** — semantic name only, no suffix: `Avatar`, `StatusBadge`, `OrderSummary`, `ShootCalendar`. These live in `features/<feature>/components/` and should be private to that feature; anything reused app-wide belongs in the shared UI layer.

**Other semantic roles** — encouraged wherever they make purpose obvious: `UserForm`, `UsersTable`, `OrderCard`, `FilterPanel`, `AddressEditor`, `StatusMenu`, `DatePicker`.

### Feature-first directory structure

The primary organizational boundary is **the feature**. `pages/`, `components/`, and `dialogs/` subdivide code *inside* a feature — they are never top-level:

```text
src/app/features/
  users/
    pages/
      users-list-page/      users-list-page.ts        -> UsersListPage
      user-detail-page/     user-detail-page.ts       -> UserDetailPage
    components/
      avatar/          avatar.ts                 -> Avatar
      status-badge/    status-badge.ts           -> StatusBadge
    dialogs/
      user-settings-dialog/   user-settings-dialog.ts   -> UserSettingsDialog
      delete-user-dialog/     delete-user-dialog.ts     -> DeleteUserDialog
  orders/
  clients/
  shoots/
```

The `data-access/` subtree inside a feature is documented in `angular-ngrx-state`.

**Not permitted** — type-based directories at the app root, which scatter each feature across the tree:

```text
app/
  pages/  components/  dialogs/  services/   ← never
```

This deliberately differs from Angular's recommendation against type-based directories. The distinction holds because the structure stays feature-first: type folders only ever appear one level *below* a feature.

### Current state — migration in progress, not a sweep

**Target: every feature lives under `src/app/features/`.** Neither repo is there yet, and the gap is a half-finished move rather than an empty tree — many features currently exist in *both* locations at once. Most class names are already correct; the **filenames** lag, and for the large majority the gap is only the separator (`.` → `-`).

Renaming a component file means updating its `templateUrl`, `styleUrls`, and every import path, so this is not a find-and-replace.

**Existing names are legacy, not violations.** Do not open rename PRs against them — not for `*Component` classes, not for dot-form filenames. New code follows the convention; existing code migrates when you are already touching it for another reason. When consolidating a split feature, move the whole feature in one commit rather than leaving a third partial copy.

> Do not record migration counts here. They decay with every commit and a stale number reads as a live decision gate. Grep when you need one.

### Not enforced by lint

`@angular-eslint/component-class-suffix` can only *whitelist* suffixes, so it cannot express "must not end in `Component`." Both `component-class-suffix` and `directive-class-suffix` are therefore `"off"` in each repo's `.eslintrc.json`, with a comment pointing here. They must be explicitly `"off"` rather than omitted — both are `"error"` in `plugin:@angular-eslint/recommended`, whose default suffix list is just `["Component"]`, so deleting the entry silently re-enables a stricter rule.

This convention is upheld by review. If it needs teeth later, a `no-restricted-syntax` rule matching `ClassDeclaration[id.name=/Component$/]` would do it — but only once the existing `*Component` classes are migrated.

### Variable naming
- **Signals:** no suffix — `selectedId`, `loading`, `things`
- **Observables:** `$` suffix, only at facade/service level — `things$`, `loadingAll$`; avoid `$` in component class bodies
- **Computed:** descriptive names — `vm`, `filteredThings`, `hasItems`

---

## 7. Testing

Both apps use **Vitest** for unit tests and **Cypress** for end-to-end tests.
No Karma, no Jasmine, no Jest.

- **Unit tests** cover reducers, selectors, pure mappers, formatters, and validators.
  See the `angular-unit-testing` skill.
- **E2E tests** cover user flows. Everything below applies to Cypress.

Both are required. Neither substitutes for the other.

### Three tests per feature

Every feature needs exactly these three specs — no more needed to cover 90% of real failure surface:

1. **Happy path** — primary flow works end-to-end with realistic stubbed data
2. **Empty/zero state** — feature handles no data gracefully
3. **Error state** — feature degrades gracefully when the API returns a 500

### Key rules

- **Stub all API calls** with `cy.intercept()` — real network calls make tests slow and data-dependent. Target: full suite runs in under 3 minutes.
- **`data-cy` attributes are non-negotiable** — add them to every interactive element and display region when building a component. Never select by CSS class or Angular component structure.
- **One spec file per feature** in `cypress/e2e/feature-name/feature-name.cy.ts` — integration between steps is where bugs live.
- **Boy scout rule** — when you change a feature, leave it with a test that didn't exist before.
- **Regression rule** — when a bug is found, write the failing test first, then fix it.

> For full spec structure, fixture conventions, `data-cy` naming standards, and intercept patterns — see `references/cypress-patterns.md`.

---

## 8. General Rules

- **No `any` in new code** — use proper interfaces or `unknown` with type guards. `any` disables the type safety that makes large-scale refactoring safe.
- **Keep components thin** — business logic belongs in facades and services. A component's job is to translate between the ViewModel and the template.
- **No template logic** — derive computed state in the component class via `computed()`, not via ternaries or method calls in the template. Template expressions that can't be read at a glance are a sign that something belongs in the component.
- **Max 400 lines per file, 75 lines per function** — these limits are signals to split responsibilities, not rules to satisfy by cramming. If you're approaching them, look for the seam.
- **Path aliases:** `@app/*` → `src/app/*`, `@env/*` → `src/environments/*`

## Import Organization

All `.ts` files use a consistent categorized import block structure with labeled divider comments. See the `angular-import-organization` skill for the full category list, classification rules, and a worked example. Apply it whenever generating a new file or cleaning up an existing one.

---

## 9. Inline Documentation

### The dual-audience rule
Every non-trivial comment has two readers: a human engineer onboarding to the feature, and a future Claude Code session that needs to understand intent before making changes. Write for both. Don't restate what the code does — explain *why* this approach was chosen, what invariants must be preserved, and what would break if the logic changed.

### ARCHITECTURE NOTES block
Any service, facade, or state file with non-obvious design choices must open with an `ARCHITECTURE NOTES` block. This is the first thing a future reader (human or AI) sees when entering the file.
```ts
/**
 * ARCHITECTURE NOTES
 *
 * Why immutable ai_features after creation:
 *   Regeneration appends new ListingFeatures records rather than overwriting the
 *   existing ones. This preserves a full audit trail of what the model produced at
 *   each point in time and prevents silent data loss if a regeneration produces
 *   lower-quality output. The active copy is always resolved via
 *   `edited.presence || ai_generated` — never by mutating the AI record.
 *
 * Why description_unlocked is a boolean gate rather than a credit counter:
 *   Billing is prepaid per-listing access, not per-generation. A credit counter
 *   would require tracking generation costs on the model, adding complexity with
 *   no business value. The boolean gate is sufficient for the current billing model.
 *
 * Invariants that must hold:
 *   - ai_features is never updated after initial creation — only new records are inserted.
 *   - edited_features starts null and is only set by explicit user action.
 *   - description_unlocked must be true before any generation is attempted.
 */
```

### When to add an ARCHITECTURE NOTES block
Add one when the file contains any of:
- An immutability or append-only pattern
- A gate, flag, or guard that controls access to a feature
- A non-obvious ordering or priority rule (e.g., tiered photo selection)
- A deliberate constraint imposed by an external standard (Fair Housing Act, AB 723, MLS character limits)
- A pattern that looks like it could be simplified but can't be (and the reason why)

### Inline why-comments
For logic that isn't worth a full block, add a brief inline comment explaining the constraint or intent:
```ts
// confidence used as tiebreaker within scene type only —
// never to promote a lower-tier scene over a higher-tier one
const sorted = candidates.sort((a, b) => b.confidence - a.confidence);

// AB 723: any digitally altered photo must be flagged before delivery,
// regardless of whether the agent requested the alteration
if (photo.isVirtuallyStaged) photo.requiresDisclosureLabel = true;
```

### What not to document
Skip comments that restate the obvious:
```ts
// ❌ restates the code
const listings = await this.facade.all$; // gets all listings

// ✅ explains the constraint
// all$ emits the full collection from the store — not paginated.
// For large result sets, use collection$ which respects the current meta.page.
```

State-layer documentation targets are in `angular-ngrx-state`.