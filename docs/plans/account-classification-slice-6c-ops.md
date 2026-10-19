# Plan: Headshot event hosts KPI panel (slice 6c-ops) in `insgt-ops`

**Repo:** `apps/insgt-ops` (`main` at 897a7b80, 9.66.0). Platform repo for the write-back only. No `insgt-api` change.
**Contract:** `docs/architecture/account-classification.md` v13 — §5.5 "Shipped" paragraph (`:1230–1264`), §9 rows 6c-api / 6c-ops (`:1555–1556`), §21 (`:2043–2044`). Plan `docs/plans/account-classification-slice-6.md` — slice-cut row 6c-ops (`:25`), G20 ops half (`:280`), approach row (`:305`), Cypress sketch (`:358`), commits 13–14 (`:398–401`), event 7 verification (`:457`), traps (`:501`), OQ5 (`:518`), OQ10 (`:523–527`). Runbook `docs/runbooks/deploy-account-classification-6-roi.md` ("Steps — event 7", placeholder).
**Skills loaded:** `slice-implementation`, `angular-core`, `insgt-ops-angular-developer`, `git-commit-messages`. At implementation also `angular-import-organization`, `predeploy-review-angular`.
**Status:** Plan 2026-10-19, **approved by Dan the same day** with the recommended defaults for open decisions A–D. Implemented the same day on insgt-ops `feat/headshot-host-roi-panel` (from `main` 897a7b80) as 1eb796c4 (the panel) and 0338b7fc (9.67.0); "Implementation, 2026-10-19" at the end records the evidence and what the implementation decided that the plan did not. Not reviewed, not released. The survey findings sit in Phase 1 below; the write-back transcribes the new `file:line` rows into `account-classification-codebase-notes.md`'s 6c sub-table (its `:76–78` already reserves the place: "6c-ops adds the ops KPI panel's rows to the second").

---

## Context

Slice 6c-api shipped `GET /kpis/headshot_hosts` on 2026-10-15 (insgt-api release v649): one row per headshot-event host with events, attendees, converts, conversion, already customers and the converts' lifetime value, plus a "No host" row, all computed by `HeadshotHostRoi` from the one attribution derivation. The endpoint has no client. 6c-ops gives the owner a table on the KPIs page beside the marketing-source breakdown, so the headshot-event decision (which associations and brokerages are worth hosting events for) can be read on site instead of from a rake read-out. This is deploy event 7 of slice 6, insgt-ops release 9.67.0.

---

## Phase 1 — Survey (read-only; every claim `file:line`)

### Prerequisites — landed (facts)

| Prerequisite | Evidence |
| :-- | :-- |
| Event 6 in production and curl-verified | contract §9 `:1555` ("Deployed 2026-10-15 as release v649 … the endpoint equal to it"); runbook deploy log 2026-10-15 (steps 3–4 results pasted); `insgt-api` `master` b7b2de9f = `heroku/master` per codebase notes `:305` |
| The endpoint exists on `master` | `config/routes.rb:118` `get 'headshot_hosts'`; `app/controllers/kpis_controller.rb:33–41`; `app/views/kpis/headshot_hosts.json.jbuilder:1–30` |
| 6a-ops (9.65.0) and 9.66.0 released; 9.67.0 free locally | `git tag --list 'v9.6*'` → v9.62.0 … v9.66.0; `package.json:3` `"version": "9.66.0"`; `git log` head 897a7b80 `chore: bumped version` |
| Reference panel in place | `src/app/kpis/components/marketing-source/marketing-source.{ts,html}`; `cypress/e2e/marketing-source/marketing-source.cy.ts` |

### Repo state

- insgt-ops `main` 897a7b80, **tree not clean**: ` M package-lock.json` (pre-existing; memory: npm runs in this repo prune `node_modules`). The release must go from a clean `main`; Dan decides what to do with that diff.
- insgt-api `master` b7b2de9f, ` M config/application.rb` (pre-existing, untouched by this slice).
- Angular 19.2.19, Material 19.2.19 (`node_modules/@angular/{core,material}/package.json:3`). Cypress ^15.19.0 (`package.json:101`).

### 1. Reference component — `kpis/components/marketing-source/`

Folder holds four files: `marketing-source.ts`, `marketing-source.html`, `marketing-source-accounts.dialog.ts`, `marketing-source-accounts.dialog.html`. **There is no `.css` and no `.spec.ts`** (the prompt's "styles, spec"): styling is Tailwind utility classes in the template, and the spec is the Cypress e2e file under §4.

`marketing-source.ts`:

| Line | What |
| :-- | :-- |
| 1–36 | Import block in `angular-import-organization` sections (Angular, Application, Data Models, Pipes, UI Components) |
| 38–43 | `type SortColumn = 'name' \| 'accounts' \| 'gross'`; `interface SortState { active; direction: 'asc' \| 'desc' }` |
| 45–49 | `interface State { loading; error; rows }` — local state, one signal |
| 51–64 | `interface Vm { loading; error; empty; rows; coveragePercent: number \| null }` with why-comments; `empty` is distinct from loading/error (`:54`) |
| 66–75 | `compareRows(a, b, column)` — pure, `localeCompare` for strings, subtraction for numbers |
| 77–81 | `sortRows(rows, sort)` — copies before sorting (`:77`), `factor = asc ? 1 : -1` |
| 83–93 | `coveragePercent(rows)` — **null, not 0, when the denominator is 0** (`:85–87`) |
| 95–108 | `buildVm(state, sort)` — filters the Unattributed bucket out of the table (`:100`), `empty` = no named rows (`:104`), `rows: sortRows(namedRows, sort)` (`:105`) |
| 110–116 | `@Component`: `selector: 'app-marketing-source'`, `templateUrl`, `standalone: true`, `OnPush`, `imports: [CommonModule, MatTableModule, MatSortModule, MatDialogModule, PennyToDollarsPipe]` |
| 118–120 | `inject(MarketingSourceKpiService)`, `inject(DestroyRef)`, `inject(MatDialog)` |
| 122, 124 | `state = signal<State>({ loading: true, error: false, rows: [] })`; `sortState = signal<SortState>({ active: 'gross', direction: 'desc' })` |
| 126, 128 | `displayedColumns`; `vm = computed<Vm>(() => buildVm(this.state(), this.sortState()))` |
| 130–140 | Constructor: `service.all().pipe(takeUntilDestroyed(destroyRef)).subscribe({ next, error })` — **next/error, not catchError-to-empty**, so a 500 is a distinct state (`:131–132`) |
| 142–149 | `onSort(sort: Sort)`: Material's third toggle clears `direction` → fall back to the default sort (`:143–147`); else `sortState.set(...)` |
| 153–161 | `onRowClick` → `MarketingSourceAccountsDialog` — **not mirrored** (no drill-down in this slice; plan `:305` "without its dialog") |

`marketing-source.html`:

| Line | What |
| :-- | :-- |
| 1–2 | `div.app-card.mb-4` `data-cy="marketing-source-kpis"`; `div.app-card-header` title |
| 4–11 | `@if (vm(); as vm)` → `@if (vm.loading)` `-loading` / `@else if (vm.error)` `-error` / `@else if (vm.empty)` `-empty` / `@else` the table |
| 12–16 | Coverage line, rendered only when `coveragePercent !== null`, `data-cy="marketing-source-coverage"`, `number: '1.0-0'` |
| 18–25 | `<mat-table [dataSource]="vm.rows" matSort matSortActive="gross" matSortDirection="desc" (matSortChange)="onSort($any($event))" data-cy="marketing-source-table">` |
| 27–32 | Sticky header row; `mat-row` with `data-cy="marketing-source-row"` |
| 34–47 | Three `matColumnDef`s; `mat-header-cell mat-sort-header`; cells carry `data-cy="marketing-source-{name,accounts,gross}"`; `accountCount \| number`; `(grossCents \| appPennyToDollars) \|\| '—'` |

### 2. Data access — `kpis/data-access/`

`marketing-source-kpi.model.ts`: `:5–10` `interface MarketingSourceKpi { marketingSourceId: number \| null; name; accountCount; grossCents }` (camelCase, cents as integers, `:1–4`); `:12–17` `MarketingSourceKpiMetadata` (four numbers, none nullable); `:19–22` `MarketingSourceKpiCollection { data: MarketingSourceKpi[]; metadata: MarketingSourceKpiMetadata \| null }`.

**Null-not-zero, as it actually appears.** The marketing-source model has no nullable rate (`attributedPercentage: number`, `:15`). The pattern the prompt describes lives in two other places: the component's Vm (`coveragePercent: number \| null`, `:59–63`, computed null over a zero denominator `:85–87`) and the new API (`conversion_percentage` is `nil` when `attendees` is 0, `app/services/headshot_host_roi.rb:84–86`, with `converts` and `attendees` served beside it, `headshot_hosts.json.jbuilder:21–23`). The new model carries it on the wire type: `conversionPercentage: number \| null`.

`marketing-source-kpi.service.ts`: `:17–18` `@Injectable({ providedIn: 'root' }) export class MarketingSourceKpiService extends ApiService` — **Generation 1** (`insgt-ops-angular-developer` "Legacy API service"); `:19–27` `super({ endpoint: 'kpis/marketing_sources', nameSpace: 'kpi', instanceClass: Object, collectionClass: Object, injector })`; `:34–36` `all(): Observable<MarketingSourceKpiCollection> { return this._all<…>(); }`. Error path: `shared/api/api.service.ts:76–84` `_all` → `catchError(handleError)`; `:132–140` `handleError` → `throwError(error.error)` (status discarded, per the repo's trap 3). All four `kpis/data-access/*.service.ts` subclass `ApiService` the same way.

The repo's most recent new service (9.65.0, 6a-ops) is **Generation 3**: `marketing-events/data-access/marketing-event-host.service.ts:38–47` `inject(ResourceApiService).createClient({ endpoint })`, `api.all<Collection<…>>()`. Its error path is the same shape: `shared/api/resource-api.service.ts:156–166` `all` → `catchError`, `:311–313` `handleError` → `throwError`. Either base rejects the observable on a 500, so the component's `next`/`error` handling is identical under both. See Open decision A.

### 3. `kpis-list` — where the panel goes

- `kpis/pages/kpis-list/kpis-list.html:21` `<app-marketing-source></app-marketing-source>`, the last child of the page's `div.mx-4` (`:1`, closed `:22`); `<app-system-metrics>` precedes it at `:20`.
- `kpis-list.module.ts:8` `import { MarketingSource } from '../../components/marketing-source/marketing-source';`, `:26` in the NgModule `imports` array (a standalone component imported into a legacy `standalone: false` page module, `kpis-list.ts:7`).
- `kpi-routing.module.ts:13` the page is `roles.owner` only (`shared/models/role.model.ts:28` `owner: 'system_owner'`), which matches the endpoint's gate.

### 4. `cypress/e2e/marketing-source/marketing-source.cy.ts`

| Line | What |
| :-- | :-- |
| 4 | `const breakdownUrl = '**/kpis/marketing_sources*'` |
| 6–20 | Fixture inline (no `cypress/fixtures` file), **deliberately not in display order** (`:6–7`) so the test proves the component sorts |
| 22–24 | `beforeEach(() => cy.loginAsAdmin())` — `cypress/support/commands.ts:91–93` signs in `adminUser`; the owner-only route works for it today, so `adminUser` holds `system_owner` |
| 26–50 | Happy path: `cy.intercept('GET', url, body).as(...)`, `cy.visit('/#/kpis')`, `cy.wait`, `scrollIntoView()` on the card, `.then($cells => [...$cells].map(innerText))` `deep.equal` on names and formatted money, coverage text |
| 52–61 | Empty: stub `{ data: [], metadata: null }`; `-empty` exists, `-table` does not |
| 63–72 | Error: stub `{ statusCode: 500, body: { errors: 'Server error' } }`; `-error` exists, `-table` does not |
| 74–126 | Drill-down modal describe — not mirrored |

Location facts for Open decision B: `npm run test:e2e` is `cypress run` (`package.json:12`), e2e only; `cypress.config.ts:81` `baseUrl http://localhost:4300`; component testing is configured (`:112–119`, `specPattern: 'src/**/*.cy.ts'`, `cy.mount` in `cypress/support/component.ts:21–36`) and exactly one co-located component spec exists (`src/app/features/orders/components/order-metrics/order-metrics.cy.ts`, from 2026-05) against 61 e2e specs; no npm script runs component specs. Two other KPIs-page specs live in `cypress/e2e/kpis/` (`system-metrics.cy.ts`, `kpis-order-type-channels.cy.ts`); the reference lives in its own folder.

### 5. The `insgt-api` endpoint — exists, deployed

| File | Line | What |
| :-- | :-- | :-- |
| `config/routes.rb` | 112–120 | `resources :kpis` collection: `order_types`, `accounts`, `marketing_sources`, `marketing_source_accounts`, **`headshot_hosts`** (118) |
| `app/controllers/kpis_controller.rb` | 2–3 | `prepend_before_action :authenticate_with_jwt`; `before_action :authenticate_system_owner` — owner-only, **401** for every other role (request spec `:24–35`) |
| same | 33–41 | `headshot_hosts`: `HeadshotHostRoi.call` → `@rows`, `@totals`; "this action and its jbuilder only rename keys" |
| `app/views/kpis/headshot_hosts.json.jbuilder` | 5–14 | `metadata`: `events`, `attendees`, `converts`, `conversion_percentage`, `already_customers`, `converts_lifetime_value_cents`, `pending_release_accounts`, `totals_match` |
| same | 16–30 | `data[]`: `organization_id` (**null on the no-host row, always last**, `:18`), `name`, `events`, `attendees`, `converts`, `conversion_percentage`, `already_customers`, `converts_lifetime_value_cents`, `marketing_source_name` (**null for a host that is not a source**, `:28`) |
| `app/services/headshot_host_roi.rb` | 40 | `NO_HOST_LABEL = 'No host'` — the no-host row's `name` |
| same | 62–73 | `host_rows`: hosts by `[-attendees, name, organization_id]`, then `+ [no_host]` (`:72`) — the wire order; the no-host row is always present, zeros included |
| same | 84–86 | `percentage` → `nil` over zero attendees ("a rate over nobody is unknown, not zero") |
| `spec/requests/kpis_headshot_hosts_spec.rb` | 50–60 | Wire shape pinned camelCase: `marketingSourceName`, `conversionPercentage` (100.0), `alreadyCustomers`, `convertsLifetimeValueCents`; `data.last` has `organizationId: nil`, `name: 'No host'`, `marketingSourceName: nil`; `metadata` keys `events … totalsMatch` |

Wire keys are camelCase (`angular-core` §3: match the wire). Production figures on 2026-10-15 (`docs/architecture/headshot-host-roi-2026-10-15.md`): 46 rows (45 hosts + No host), totals 198 events · 2,342 attendees · 203 converts · 8.7% · 151 already customers · $354,700.00; No host 10 / 51 / 9 / 17.6% / 3 / $5,540.00; 1 pending release. The endpoint takes 2–3 s in production (codebase notes `:153`; §21 `:2060–2066` the stale-statistics incident and its `ANALYZE`).

### 6. The design doc on slice 6c and "event 7"

- **Event 7** is settled: slice 6 has seven deploy events (plan `:16–27`); event 7 is the insgt-ops release carrying this panel, "after event 6" (`:25`), verified on site as owner with rows and totals matching event 6's curl and the no-host row last (`:457`); the runbook's "Steps — event 7" is a placeholder for the 6c-ops session to fill. Not an open decision.
- **G20 ops half** (`:280`): standalone OnPush beside `kpis/components/marketing-source/`, `inject()`, signals, `MatTableModule` + `MatSortModule`, local state, **no NgRx slice**; service and model in `kpis/data-access/`; added to `kpis-list` next to `<app-marketing-source>`; Cypress in `marketing-source.cy.ts`'s shape; names per `angular-core`; **the no-host row renders last under a stable label**; release 9.67.0 or next (v13).
- **Cypress sketch** (`:358`): panel renders for the owner; **rows sort by converts descending by default**; no-host row last under its label; a host without a source shows `none`; empty `data` → empty state; 500 → error state. Vitest only if a pure mapper appears.
- **Commits** (`:398–401`): 13 `feat: add the headshot event hosts KPI panel` (component, service, model, `kpis-list` entry, Cypress; tier 2 body); 14 `chore: bumped version`. Branch `feat/headshot-host-roi-panel` (`:270`, G18: Dan commits).
- **Traps** (`:501`): the panel with an NgRx slice; hiding the no-host row.
- **Two names in one document:** the slice-cut row calls the panel `HeadshotHostRoi` (`:25`), the approach table places it at `kpis/components/headshot-hosts/…` (`:305`). Pinned below as `HeadshotHosts`.
- Contract §5.5 `:1230–1264` restates OQ10's rules and "The endpoint renames the service's keys and computes nothing" (`:1264`); §9 `:1556` "6c-ops … Not started; event 6 curl-verified 2026-10-15".

### 7. `angular-core` naming, applied

Class = file in kebab-case, hyphen separator, no `Component` suffix, `.css` only if styles exist; embedded components carry a semantic name only. `data-access/` files keep the repo's `*.model.ts` / `*.service.ts` form (`angular-ngrx-state` `:31–32`; all 40 `data-access` files in insgt-ops, including 9.65.0's `marketing-event-host.service.ts`). Cypress e2e: `cypress/e2e/<feature>/<feature>.cy.ts` (`angular-core` §7).

### Collisions (grep, output pasted)

```
$ grep -rniw "headshot-host\|headshotHost\|HeadshotHostRoi\|headshot_hosts\|headshot-hosts\|host-roi\|hostRoi" src cypress   (insgt-ops)
(empty)
```

### Where the prompt and the codebase disagree

1. "component, template, **styles, spec**" — no `.css`, no `.spec.ts` exist for the reference (§1). The panel ships `.ts` + `.html`; its spec is Cypress.
2. "Mirror marketing-source's error handling; do not introduce a new pattern" reads as Gen 1 `ApiService`; `angular-core` §4 says new services are Gen 3, and 9.65.0 did that. → Open decision A.
3. "Co-located with the component" vs "shaped like `marketing-source.cy.ts`" (an e2e spec under `cypress/e2e/`). → Open decision B.
4. "null-not-zero … numerators/denominators stored alongside rates" is not in the marketing-source model; it is in the Vm and in the new API (§2). Carried on the new model, not invented.

---

## Phase 2 — Plan

### Files to create / modify

| File | Action | Purpose |
| :-- | :-- | :-- |
| `src/app/kpis/data-access/headshot-host-kpi.model.ts` | create | Wire types: `HeadshotHostKpi`, `HeadshotHostKpiMetadata`, `HeadshotHostKpiCollection` |
| `src/app/kpis/data-access/headshot-host-kpi.service.ts` | create | `HeadshotHostKpiService.all()` → `GET /kpis/headshot_hosts` |
| `src/app/kpis/components/headshot-hosts/headshot-hosts.ts` | create | `HeadshotHosts` — standalone, OnPush, signals, local state; the sort and the no-host pin |
| `src/app/kpis/components/headshot-hosts/headshot-hosts.html` | create | Card, four states, totals line, `mat-table` + `matSort`, `data-cy` on every region and cell |
| `src/app/kpis/pages/kpis-list/kpis-list.html` | modify | `<app-headshot-hosts></app-headshot-hosts>` after `:21` |
| `src/app/kpis/pages/kpis-list/kpis-list.module.ts` | modify | Import `HeadshotHosts` beside `MarketingSource` (`:8`, `:26`) |
| `cypress/e2e/headshot-hosts/headshot-hosts.cy.ts` | create | Happy path (with the pin under sort), empty, error |
| `package.json` | modify | `9.66.0` → `9.67.0` (own commit) |

No `.css` (none needed; the reference has none). No `cypress/fixtures` file (the reference inlines its fixture). No Vitest: no pure mapper beyond `compareRows`/`sortRows`, which the reference also keeps untested in Vitest; Cypress is the component's test per `angular-core` §7.

### Model — `headshot-host-kpi.model.ts`

```ts
// One host row of GET /kpis/headshot_hosts (account-classification.md §5.5, slice 6c). Keys are
// camelCase because insgt-api camelizes every response. Money is integer cents.
export interface HeadshotHostKpi {
  organizationId: number | null;        // null on the no-host row — the ONLY way the row is identified
  name: string;                         // 'No host' on the no-host row (HeadshotHostRoi::NO_HOST_LABEL)
  marketingSourceName: string | null;   // null for a host that is not a marketing source → rendered 'none'
  events: number;                       // every event the host held, any status
  attendees: number;
  converts: number;
  conversionPercentage: number | null;  // converts / attendees × 100, one decimal; null when attendees is 0
                                        // (a rate over nobody is unknown, not 0 — headshot_host_roi.rb:84–86)
  alreadyCustomers: number;             // never counted as converts (OQ10)
  convertsLifetimeValueCents: number;
}

export interface HeadshotHostKpiMetadata {   // the Total row, computed by the API, never by the panel
  events: number;
  attendees: number;
  converts: number;
  conversionPercentage: number | null;
  alreadyCustomers: number;
  convertsLifetimeValueCents: number;
  pendingReleaseAccounts: number;
  totalsMatch: boolean;
}

export interface HeadshotHostKpiCollection {
  data: HeadshotHostKpi[];
  metadata: HeadshotHostKpiMetadata | null;
}
```

Row type for the table is `HeadshotHostKpi` itself, no view-row type: the no-host row is an ordinary row whose `organizationId` is `null`. Nothing in the panel reads `name === 'No host'`; the label is rendered from the wire and identified by the id.

### Service — `headshot-host-kpi.service.ts`

- `@Injectable({ providedIn: 'root' }) export class HeadshotHostKpiService` (root-provided like its four `kpis/data-access` siblings, so the legacy page module needs no `providers` entry).
- One method: `all(): Observable<HeadshotHostKpiCollection>` → `GET /kpis/headshot_hosts`, **no params** (an all-time, point-in-time view, as `marketing_sources`).
- Base per Open decision A. Recommended: Gen 3, `private readonly api = inject(ResourceApiService).createClient({ endpoint: 'kpis/headshot_hosts' })`, `all() { return this.api.all<HeadshotHostKpiCollection>(); }` (`marketing-event-host.service.ts:40–41`'s shape). Fallback if Dan prefers the exact sibling shape: `extends ApiService` with `super({ endpoint: 'kpis/headshot_hosts', nameSpace: 'kpi', instanceClass: Object, collectionClass: Object, injector })` and `this._all<…>()` (`marketing-source-kpi.service.ts:19–36`).
- Error handling: none in the service — both bases `catchError → throwError(error.error)` (`api.service.ts:132–140`; `resource-api.service.ts:311–313`), so a 500 rejects the observable and the component's `error:` handler runs. No `catchError` added, no new pattern.
- Doc comment in the sibling's voice (`:29–33`): owner-only; `{ data, metadata }`; `metadata` is the Total row.

### Component — `headshot-hosts.ts` / `.html`

**Decorator:** `selector: 'app-headshot-hosts'`, `templateUrl`, `standalone: true`, `changeDetection: OnPush`, `imports: [CommonModule, MatTableModule, MatSortModule, PennyToDollarsPipe]` (no `MatDialogModule`: no drill-down).

**Inputs:** none (mirrors the reference: no time frame, no params).

**Injected:** `HeadshotHostKpiService`, `DestroyRef`.

**Signals held:**
- `state = signal<State>({ loading: true, error: false, rows: [], metadata: null })`
- `sortState = signal<SortState>({ active: 'converts', direction: 'desc' })` — the default per plan `:358`; ties keep the wire order (attendees desc, name) because `Array.prototype.sort` is stable.

**Types (module scope):** `type SortColumn = 'name' | 'source' | 'events' | 'attendees' | 'converts' | 'conversion' | 'alreadyCustomers' | 'lifetimeValue'`; `SortState`; `State`; `Vm { loading; error; empty; rows: HeadshotHostKpi[]; totals: HeadshotHostKpiMetadata | null }`.

**`computed` derivations:** one, `vm = computed<Vm>(() => buildVm(this.state(), this.sortState()))`, where `buildVm` is a pure module function (reference `:95–108`): `empty = !loading && !error && rows.length === 0` (a response holding only the no-host row is **not** empty — it renders), `rows = sortRows(state.rows, sort)`, `totals = state.metadata`. The template reads only `vm`.

**Pure helpers (module scope, reference `:66–81`):**
- `compareRows(a, b, column)`: `name` and `source` by `localeCompare` (`marketingSourceName ?? ''`); numeric columns by subtraction; `conversion` by `(a.conversionPercentage ?? -1) - (b.conversionPercentage ?? -1)` — a null rate sorts below 0 % (last in descending, first in ascending), one line, no NULLS-LAST machinery.
- `sortRows(rows, sort)`: see "No-host row" below.

**Constructor:** `this.service.all().pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ next: collection => state.set({ loading: false, error: false, rows: collection.data ?? [], metadata: collection.metadata ?? null }), error: () => state.set({ loading: false, error: true, rows: [], metadata: null }) })` — `next`/`error`, with the reference's comment on why not `catchError`.

**`onSort(sort: Sort)`:** the reference's `:142–149` verbatim with the default swapped to `{ active: 'converts', direction: 'desc' }` on the third (cleared) toggle.

**`displayedColumns`:** `['name', 'source', 'events', 'attendees', 'converts', 'conversion', 'alreadyCustomers', 'lifetimeValue']`.

**Template:** `div.app-card.mb-4` `data-cy="headshot-hosts-kpis"`, header "Headshot event hosts (all time)"; `@if (vm(); as vm)` → loading / error ("Could not load headshot event hosts.") / empty ("No headshot event hosts found.") / else: the totals line then the table. `mat-table [dataSource]="vm.rows" matSort matSortActive="converts" matSortDirection="desc" (matSortChange)="onSort($any($event))"`, sticky header row, `mat-row` (no click handler, no `cursor-pointer`). Cells: `name` as is; `source` `{{ row.marketingSourceName ?? 'none' }}` (plan `:358`); counts `| number`; `conversion` as `@if (row.conversionPercentage !== null) { {{ row.conversionPercentage | number: '1.1-1' }}% } @else { — }` (block control flow, no ternary — `angular-core` §8); `lifetimeValue` `| appPennyToDollars` (never null on this wire; `$0.00` for zero, like the read-out).

**Totals line** (`data-cy="headshot-hosts-totals"`, rendered when `vm.totals !== null`, the reference's coverage-line slot `:12–16`): "{{events | number}} events · {{attendees | number}} attendees · {{converts | number}} converts ({{conversionPercentage | number:'1.1-1'}}%) · {{alreadyCustomers | number}} already customers · {{convertsLifetimeValueCents | appPennyToDollars}} converts' lifetime value · {{pendingReleaseAccounts | number}} pending release". Every figure is `metadata`'s; the panel sums nothing (codebase notes `:150–151`; runbook event 7: "rows and totals match step 4's curl"). `totalsMatch` is not rendered: it is the API's self-check and the read-out's "Totals check" line surfaces it.

**`data-cy` attributes:** `headshot-hosts-kpis`, `-loading`, `-error`, `-empty`, `-totals`, `-table`, `-row`; cells `-name`, `-source`, `-events`, `-attendees`, `-converts`, `-conversion`, `-already-customers`, `-lifetime-value`; header cells `-sort-name`, `-sort-source`, `-sort-events`, `-sort-attendees`, `-sort-converts`, `-sort-conversion`, `-sort-already-customers`, `-sort-lifetime-value` (new relative to the reference, which never clicks a header; `angular-core` §7 wants `data-cy` on every interactive element rather than `.mat-sort-header` selectors).

**No NgRx.** No action, reducer, selector, effect, facade, provider or `data-access/state/` file. State is the two signals above, exactly as the reference (plan `:280`, trap `:501`).

### No-host row

- **Label:** `'No host'`, served as `name` by the API (`headshot_host_roi.rb:40`, jbuilder `:18`, request spec `:58`). The panel renders `row.name` and never substitutes; identification is `organizationId === null`. Not blank, not `null`, not `'undefined'`, and not a second copy of the constant in ops.
- **Where the pin lives: `sortRows`, the pure function the `computed` calls** (reference `:77–81`):

  ```ts
  // The no-host row (organizationId null) is pinned last whatever the sort: it is the bucket the
  // host rows are measured against, and the API also serves it last (headshot_host_roi.rb:72).
  // Hiding it is a trap (slice 6 plan :501) — the rows must still sum to the distinct attendee count.
  function sortRows(rows: HeadshotHostKpi[], sort: SortState): HeadshotHostKpi[] {
    const factor = sort.direction === 'asc' ? 1 : -1;
    const hosts = rows.filter(row => row.organizationId !== null);
    const noHost = rows.filter(row => row.organizationId === null);
    return [...hosts].sort((a, b) => factor * compareRows(a, b, sort.active)).concat(noHost);
  }
  ```

- **Why there and not elsewhere:** the service is a thin adapter (`angular-core` §4) and the wire order is already right — but the wire order is lost the moment a header is clicked, so the pin has to sit where the display order is decided. That is `sortRows`, the one function between state and template; the reference already makes its display-shaping decision (dropping the Unattributed bucket, `:100`) at this seam. A custom `sortData` on `MatTableDataSource` would introduce `MatTableDataSource` (the reference binds a plain array) and move the rule into Material's API; a `computed` separate from `sortRows` would be a second function doing half the ordering.
- **Why it survives every column and direction, by construction:** the no-host row is never in the array that `sort()` runs over. `factor`, `sort.active` and `compareRows` only touch `hosts`; `noHost` is appended after. Ascending, descending, and the cleared third toggle (which resets to converts desc) all go through the same line. A `noHost` array (0 or 1 rows) rather than a single element keeps a response without the row rendering.
- **Deliberate break** (red proof): replace the two filters with `[...rows].sort(...)` → the Cypress attendees-ascending assertion fails (fixture below puts the no-host row's attendees strictly between the hosts').

### `kpis-list` change

- `kpis-list.html`: insert line 22 `<app-headshot-hosts></app-headshot-hosts>` directly after line 21 `<app-marketing-source></app-marketing-source>`, inside the closing `</div>` of `div.mx-4`. Both cards carry `mb-4`; no wrapper, no grid (the two package tables above use a grid; the two breakdown cards are full-width).
- `kpis-list.module.ts`: line 9 `import { HeadshotHosts } from '../../components/headshot-hosts/headshot-hosts';` (relative, as the sibling at `:8`); `imports: [RouterModule.forChild(routes), SharedModule, SystemMetrics, MarketingSource, HeadshotHosts]`. No `declarations` or `providers` change.

### Cypress spec — `cypress/e2e/headshot-hosts/headshot-hosts.cy.ts`

`describe('KPIs - Headshot event hosts')`, `const hostsUrl = '**/kpis/headshot_hosts*'`, `beforeEach(() => cy.loginAsAdmin())` (`marketing-source.cy.ts:1–24`). All API calls stubbed with `cy.intercept()`; the other KPIs endpoints are left unstubbed exactly as the reference leaves them.

**Fixture** (inline, realistic values from the 2026-10-15 read-out, **deliberately out of display order** and built so the no-host row sits strictly between the hosts on every numeric column and alphabetically — otherwise a sort could put it last by accident):

```ts
const hosts = {
  data: [
    { organizationId: 2031, name: 'Coldwell Banker Realty - Vista', marketingSourceName: null,
      events: 2,  attendees: 29,  converts: 6,  conversionPercentage: 20.7, alreadyCustomers: 3,  convertsLifetimeValueCents: 505_800 },
    { organizationId: null, name: 'No host', marketingSourceName: null,
      events: 10, attendees: 51,  converts: 9,  conversionPercentage: 17.6, alreadyCustomers: 4,  convertsLifetimeValueCents: 554_000 },
    { organizationId: 2044, name: 'Windermere Real Estate', marketingSourceName: null,   // only event pending release
      events: 1,  attendees: 0,   converts: 0,  conversionPercentage: null, alreadyCustomers: 0,  convertsLifetimeValueCents: 0 },
    { organizationId: 2017, name: 'PSAR', marketingSourceName: 'PSAR event',
      events: 56, attendees: 809, converts: 14, conversionPercentage: 1.7,  alreadyCustomers: 12, convertsLifetimeValueCents: 657_500 },
  ],
  metadata: { events: 198, attendees: 2342, converts: 203, conversionPercentage: 8.7, alreadyCustomers: 151,
              convertsLifetimeValueCents: 35_470_000, pendingReleaseAccounts: 1, totalsMatch: true },
};
```

**Test 1 — happy path** (`it('renders host rows sorted by converts descending with the no-host row pinned last')`):
1. Stub, visit `/#/kpis`, wait, `scrollIntoView` on `headshot-hosts-kpis`; `headshot-hosts-table` exists.
2. Names `deep.equal` `['PSAR', 'Coldwell Banker Realty - Vista', 'Windermere Real Estate', 'No host']` — converts desc (14, 6, 0) with No host (9) pinned, not third.
3. Sources `['PSAR event', 'none', 'none', 'none']`; conversion `['1.7%', '20.7%', '—', '17.6%']` (the null rate renders a dash, not `0.0%`); lifetime value `['$6,575.00', '$5,058.00', '$0.00', '$5,540.00']`.
4. Totals line contains `2,342 attendees`, `203 converts (8.7%)`, `151 already customers`, `$354,700.00`, `1 pending release`.
5. **The pin under sort, both directions, two columns** (the prompt's fourth assertion): click `headshot-hosts-sort-attendees` → ascending: `['Windermere Real Estate', 'Coldwell Banker Realty - Vista', 'PSAR', 'No host']` (natural order would put No host third); click again → descending: `['PSAR', 'Coldwell Banker Realty - Vista', 'Windermere Real Estate', 'No host']` (natural: second). Click `headshot-hosts-sort-name` → ascending: `['Coldwell Banker Realty - Vista', 'PSAR', 'Windermere Real Estate', 'No host']` (natural: second); click again → descending: `['Windermere Real Estate', 'PSAR', 'Coldwell Banker Realty - Vista', 'No host']` (natural: third).

Material's toggle order on a column that is not active starts at `asc` (`start` default), so the first click on Attendees or Host is ascending and the second descending; the default column is deliberately not used for this check because its first click clears the direction (reference `:143`).

**Test 2 — empty state** (`'shows the empty state and no table when there are no hosts'`): stub `{ data: [], metadata: null }`; `headshot-hosts-empty` exists; `headshot-hosts-table` does not.

**Test 3 — error state** (`'degrades to the error state when the endpoint returns 500'`): stub `{ statusCode: 500, body: { errors: 'Server error' } }`; `headshot-hosts-error` exists; `headshot-hosts-table` does not.

### Commit plan (`git-commit-messages`; branch `feat/headshot-host-roi-panel`, plan `:270`)

1. **`feat: add the headshot event hosts KPI panel`** — model, service, component, template, the two `kpis-list` lines, the Cypress spec. One unit of work, as the reference landed (bed7f368, 2026-06-30, one commit for the panel, its data access, the page entry and the spec): the service and model have no reader without the component, and a data-access-only commit would be dead code that `npm run knip` flags. Tier 2 body — the panel carries two non-obvious decisions:

   ```
   feat: add the headshot event hosts KPI panel

   One row per host plus the no-host row, read from the owner-only
   GET /kpis/headshot_hosts; converts and already customers stay separate
   columns. The no-host row is pinned last under every sort rather than
   hidden, so the table always accounts for every attendee.
   ```

2. **`chore: bumped version`** — `package.json` 9.66.0 → 9.67.0. Tier 1; the repo's standing subject (897a7b80, 23c8233d).

Per the slice-implementation loop: Cypress red first (the spec against the unmodified page: the card does not exist), then green, then the deliberate breaks below with red output pasted, then `ng build` and `ng lint` on the touched files, then the commit. Who runs `git commit` follows G18 (Dan) unless Dan says otherwise at implementation.

Platform repo, in order: before implementation `docs: add the slice 6c-ops plan` (this document as `docs/plans/account-classification-slice-6c-ops.md`, as 6c-api's is); with the release `docs: fill in event 7 in the slice 6 ROI runbook`; after it `docs: update the classification codebase notes for the headshot hosts panel` and `docs: amend account classification to v14 for the headshot hosts panel` (§9 row 6c-ops → Released, §5.5 "Shipped" names the panel, a short §22 table).

### Deploy ordering

- The `insgt-api` endpoint is **neither new nor changed** by this plan. It is on `master` b7b2de9f and in production since 2026-10-15 (release v649), curl-verified as owner, 401 unauthenticated (runbook deploy log). No API commit, no API deploy, no window.
- Event 7 strictly after event 6 — already satisfied. The panel against an API without the route would be a 404 → the error state (runbook "Deploy order and the windows").
- Release 9.67.0: `git tag v9.67.0 && npm run deploy:prod` on a clean `main` after Dan's merge (`package.json:18`; `DEPLOY.md` is the procedure). **Unverified:** whether `v9.67.0` exists on `origin` — `git ls-remote` could not resolve the host from the container; re-check on the host before tagging.
- Rollback: redeploy the previous build (9.66.0); nothing in data or the API to undo.

### Deliberate-break verification (one-line change per test → red)

| Cypress test | The one-line change | Why it goes red |
| :-- | :-- | :-- |
| 1 happy path, default order | `sortState` default `direction: 'desc'` → `'asc'` | names `deep.equal` fails (Windermere 0 converts first) |
| 1 happy path, the pin | in `sortRows`, `[...hosts].sort(...).concat(noHost)` → `[...rows].sort(...)` | attendees-ascending names fail: No host lands third, not last |
| 1 happy path, null rate | `@if (row.conversionPercentage !== null)` → `!== undefined` | conversion cells read `%` instead of `—` for Windermere |
| 1 happy path, totals | delete the totals `div` | `headshot-hosts-totals` does not exist |
| 2 empty state | `empty: … rows.length === 0` → `rows.length === 1` | the `@else` branch renders an empty table; `headshot-hosts-empty` missing |
| 3 error state | `error: () => this.state.set({ …, error: true, … })` → `error: false` (degrade to the empty state) | `headshot-hosts-error` missing (the reference's `:131–132` comment names this exact failure) |

Each break is applied, the spec run, the red output pasted into the report, and the change restored before the commit.

### Post-deploy verification (event 7; expectations reasoned before the code exists)

Attendee counts move with every pending release, so the checks are relationships against a curl of `GET /kpis/headshot_hosts` taken as owner in the same minute (runbook step 4's command); the 2026-10-15 read-out gives the bracketed expectations.

1. On site as owner, `/#/kpis`: the "Headshot event hosts" card renders below "Marketing source breakdown", after a 2–3 s "Loading…".
2. Row count = `data.length` [46]; the last row is **No host** [10 events · 51 · 9 · 17.6% · 3 · $5,540.00].
3. Default order is converts descending: NSDCR [71], PSAR [14], SDAR [12], RE/MAX Tidal [11], Windermere Homes & Estates-Rancho Bernardo [9] …; equal converts keep attendees-descending order.
4. Click Attendees twice: ascending then descending, No host last both times; descending top is PSAR [809].
5. Totals line = `metadata` [198 events · 2,342 attendees · 203 converts (8.7%) · 151 already customers · $354,700.00 · 1 pending release].
6. Spot rows: NSDCR source "NSDCR event" [53 · 636 · 71 · 11.2% · 66 · $79,974.00]; RE/MAX Tidal source `none`; every row's converts ≤ attendees.
7. The runbook's event 7 section and deploy log are filled with the observed values.

### Risks and unverified

- **Dirty tree.** ` M package-lock.json` on `main` predates this slice; the release needs a clean `main` (Dan's call on the diff). `ng lint` has broken after npm runs pruned `node_modules` here before (memory) — check `package-lock.json` after any npm invocation.
- **Cypress in the container** needs the ops dev server on 4300 and insgt-api on 3000, run by Dan (`bin/dev`); probe with bash `/dev/tcp` first, `xvfb-run`, never `npm start` (memory). The plan does not run Cypress.
- **Other KPIs-page specs** (`system-metrics.cy.ts`, `kpis-order-type-channels.cy.ts`, `marketing-source.cy.ts`) will now trigger an unstubbed `GET /kpis/headshot_hosts` against the dev API, as they already do for each other's endpoints; none asserts on it. No change to them (non-goal: no changes to `marketing-source` or its spec).
- **Endpoint latency** 2–3 s in production, and the H12 incident of 2026-10-15 was a stale-statistics problem (§21); a recurrence shows as the panel's error state, not a hang. The `ANALYZE` follow-ons are API-side and out of scope.
- **`adminUser` is an owner** only by the evidence of the existing KPIs specs passing; not re-verified.
- **Bundle:** inside the lazy `KpisListModule` chunk; `MatTable`/`MatSort`/`PennyToDollarsPipe` are already in it via `MarketingSource`, so the delta is the component itself (ESTIMATE ~150 lines, a few KB).

### Write-back (part of the slice)

1. `docs/plans/account-classification-slice-6c-ops.md` — this plan, after sign-off.
2. Runbook "Steps — event 7": tag, deploy, the on-site checks above, the deploy log line with the release date and the observed figures.
3. Codebase notes: rows in the "Headshot host ROI (slice 6c-api)" sub-table for `headshot-hosts.{ts,html}` (the pin's line, `data-cy` prefixes), `headshot-host-kpi.{model,service}.ts`, `kpis-list.{html,module.ts}` lines, the Cypress spec; a "Branch and deploy state, <date> (slice 6c-ops released)" block.
4. Contract: §9 `:1556` → "Released <date> as insgt-ops 9.67.0"; §5.5 "Shipped" paragraph gains the panel as the endpoint's client; §22 "Changes from v13", one short table. No contract spec change (the Angular side has none; the panel adds no rule).

---

## Open decisions for sign-off

Settled by the survey, not open: the no-host label (`'No host'` from the API, identified by `organizationId === null`); what "event 7" is (the insgt-ops release, slice 6 plan `:25`, `:457`); the endpoint shape (built, deployed, pinned by `spec/requests/kpis_headshot_hosts_spec.rb:50–60`).

**A. Service base — Gen 3 `ResourceApiService.createClient` (recommended) or the sibling's Gen 1 `ApiService` subclass.** `angular-core` §4 says new services are Gen 3 and 9.65.0's host service is the precedent; the prompt's "mirror marketing-source's error handling; do not introduce a new pattern" is met either way, because both bases reject the observable identically and the error handling the prompt means lives in the component's `next`/`error`. Pick Gen 1 only if "matching its shape exactly" is meant file for file.

**B. Cypress location — `cypress/e2e/headshot-hosts/headshot-hosts.cy.ts` (recommended) or co-located `src/app/kpis/components/headshot-hosts/headshot-hosts.cy.ts`.** The reference is an e2e spec that visits `/#/kpis` and therefore also exercises the `kpis-list` wiring; `npm run test:e2e` runs it; `angular-core` §7 names this path. A co-located file would be a `cy.mount` component spec (`specPattern: 'src/**/*.cy.ts'`), a different shape from the reference, that no npm script runs and that cannot prove the page entry.

**C. No-host pin in `sortRows` (recommended), not the service and not a `sortData`.** Rationale under "No-host row". Listed because the prompt expects it; the survey settles it.

**D. Pinned in the plan — say so if you want otherwise:** class `HeadshotHosts` / `app-headshot-hosts` / `kpis/components/headshot-hosts/` (plan `:305`, endpoint symmetry with `MarketingSource` ↔ `kpis/marketing_sources`) rather than `HeadshotHostRoi` (plan `:25`); default sort converts descending (plan `:358`) rather than the wire's attendees descending; a totals line rendered from `metadata` (runbook event 7 "rows and totals", codebase notes `:150`), `totalsMatch` not rendered; a null conversion rate sorts below 0 % and renders `—`; `none` for a host without a source (plan `:358`).

## Implementation, 2026-10-19

On insgt-ops `feat/headshot-host-roi-panel`: 1eb796c4 `feat: add the headshot event hosts KPI panel`, 0338b7fc `chore: bumped version`. Open decisions A–D taken as recommended: the Gen 3 client, the spec under `cypress/e2e/`, the pin in `sortRows`, and the names, default sort and totals line as pinned in D.

### Evidence

- **Red first.** The spec against the unchanged page: 3 failing, each `cy.wait() … No request ever occurred` for the endpoint, after a successful sign-in.
- **Green.** 3 passing.
- **Deliberate breaks**, each red, each restored byte for byte, with the dev server confirmed serving the original chunk again:

| Break | Change | Red |
| :-- | :-- | :-- |
| Default sort | `DEFAULT_SORT` direction `'desc'` → `'asc'` | happy path: names open with Windermere, not PSAR |
| No-host row sorted | `sortRows` returns `hostRows.concat(noHostRows).sort(…)` | happy path: No host second under converts descending |
| Pin in descending only | the pin kept for `'desc'`, dropped for `'asc'` | happy path: the attendees-ascending order puts No host third, while the default order still passes |
| Null rate | `@if (row.conversionPercentage !== null)` → `!== undefined` | happy path: conversion cells `['1.7%', '17.2%', '%', '17.6%']` |
| Total line | `totals.attendees` → `totals.events` in the attendees figure | happy path: `198 attendees` for `2,342 attendees` |
| Empty | `rows.length === 0` → `=== 1` | empty: `headshot-hosts-empty` never found |
| Error | the `error:` handler sets `error: false` | error: `headshot-hosts-error` never found |

- **Touched area.** Every spec that visits `/#/kpis`: `dashboard-check`, `headshot-hosts`, `kpis-order-type-channels`, `system-metrics`, `marketing-source`: 15 of 15 passing. Vitest 609 of 609.
- **Lint.** ESLint over the six touched `src` files: clean.
- **Build.** `ng build --configuration production`: passes; the warnings are identical to `main`'s.
- **Bundle.** `kpis-list-module` chunk:

| | `main` 897a7b80 | branch |
| :-- | --: | --: |
| raw | 41.47 kB | 50.38 kB |
| transfer | 8.66 kB | 9.83 kB |

  Initial total unchanged at 2.63 MB. The plan's "a few KB" holds for transfer; raw is +8.9 kB.
- **Live, dev API** (a production restore; one throwaway unstubbed spec, deleted after the run): 46 rows equal to the endpoint's, No host last, default order converts descending (NSDCR 71, PSAR 14, SDAR 12, RE/MAX Tidal 11 …), Total line `198 events · 2,342 attendees · 203 converts (8.7%) · 151 already customers · $354,700.00 converts' lifetime value · 1 pending release`, identical to the production read-out of 2026-10-15.
- **knip.** Nothing from this slice is an unused export. knip lists all 62 Cypress specs and `kpis-list.css` as unused files, the reference spec included; a pre-existing configuration gap.

### Decided in implementation, not in the plan

1. **Fixture.** PSAR, Coldwell Banker Realty - Vista and No host carry the production read-out's figures; Windermere Real Estate is a host whose only event is pending release, so it has 0 attendees and a null rate.
2. **The pin break, reworded.** The plan's one-line break (`[...rows].sort(…)`) left both filtered arrays unused. The run in that form never reached the dev server, likely because the watcher saw the in-place write half-done. The break became `hostRows.concat(noHostRows).sort(…)`, the realistic way to undo the pin, and a second break pins descending only, so the ascending assertions are shown red on their own.
3. **The Total-line break** is a wrong binding rather than a deleted line: it guards each figure, not only the line's presence.
4. **The service file** has no import dividers: `angular-import-organization` skips them under six imports. Its `kpis/data-access` siblings carry them.
5. **The lockfile's two root `version` fields** go to 9.67.0 with `package.json`, as 9.65.0's bump (23c8233d) did. 9.66.0's bump (897a7b80) left them at 9.65.0, which is why `main` showed a lockfile diff before this slice.
6. **Long host names wrap** to two or three lines in the eight-column table (for example "Windermere Homes & Estates-Rancho Bernardo"). The reference has three columns and no column styling, so none was added.

### Environment notes for the next session

- Dan's `ng serve` on the host missed the container's first writes and served the old KPIs chunk until the files were touched. Confirm a change is served before trusting a Cypress run, for example by checking the served `kpis-list.module-*.js` for the new selector.
- Vite hands a build error buffered while no browser is connected to the next page that connects. It shows up as an element "covered by" `<pre class="frame">` or `<div class="tip">` during sign-in, in a run that has nothing to do with it.
- `node_modules` had lost the `@typescript-eslint` plugins before this session; `npm install --no-audit --no-fund` restored them. npm then wanted to add 690 lockfile lines; the lockfile was put back to its pre-install copy.

## Next

1. `predeploy-review-angular` over the branch diff, with its Codex pass on an rsync copy.
2. Dan merges.
3. Release 9.67.0 as event 7. Fill in the runbook's "Steps — event 7" and deploy log.
4. Write-back: the codebase notes rows and v14.
