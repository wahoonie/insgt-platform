# Order Download — insgt-ops parity with insgt-app

**Status:** Draft
**Repo:** `apps/insgt-ops` (Angular 19) · reference is `apps/insgt-app` (Angular 21)
**Written:** 2026-09-11

## 1. Context

`insgt-ops/src/app/orders/download/` and `insgt-app/src/app/orders/download/` are two hand-maintained copies of the same feature. They diverged on 2026-01-29: insgt-app shipped `ddac989` + `08f0758`, ops shipped `c6ae4475`, and ops has received no content change since. The app copy carries the desired UX.

Component sharing between the two apps is not possible today and is out of scope. `lib/insgt-ui` is imported by neither app — no `package.json` entry, no tsconfig path mapping, and it is Angular 21 + Tailwind 4 + spartan-ng, which ops could not consume on Angular 19 / Tailwind 3 anyway. **This is a copy, not an extraction.**

The intended outcome: ops staff see the same bundle selector, copy, and compliance gating that agents see in insgt-app, so a staff member on the phone with an agent is describing the same screen — while keeping the ops-only affordances that make it a staff tool.

**No API change is required.** Every param the ported UX needs (`size`, `bundle`) already exists on `POST /orders/:id/download_zip_url` (`insgt-api/app/models/concerns/order_zip.rb:6,48-62`).

## 2. Decisions pinned before implementation

Four gaps were open in the survey. All four are now decided.

| # | Gap | Decision | Rejected alternative |
|---|---|---|---|
| D1 | ops renders **two** cards (`[size]="'web'"` / `[size]="'print'"`, `orders/photos/order-photos.html:28,30`); app renders **one** card with a segmented toggle | **Full parity — one card + toggle.** `@Input() size` is deleted for a `downloadSize` signal; the host renders one instance | Keeping two cards. Costs: a processor wanting both zips now toggles between them, and the second download is blocked while `zipPolling` is live (`ts:151`). Accepted — if it bites, the fix is a queue, not a second card |
| D2 | Legacy orders: ops shows all three bundles under an "Option unavailable for legacy orders" scrim (`html:49-53`); app filters the compliance-only ones out | **Full parity — hide them.** Delete the scrim, adopt the app's filter and its `openBundleOptions()` early return | Keeping the scrim as a staff diagnostic. Rejected: `insgt-api` refuses those bundles for legacy orders anyway (`order_zip.rb:170,178,191-193`), so offering them was never honest |
| D3 | App gates the Update banner and the caret on `compliant && hasDigitalAlters()`, derived from `order.photos` | **Do not port `hasDigitalAlters`.** Gate on `complianceMode === compliant` **alone** | Deriving it in ops. Rejected on evidence: `Order.photos` (`shared/models/order.model.ts:80`) has **zero usages repo-wide**, ops never requests photos on the order Read (`features/orders/pages/order-edit/order-edit.page.ts:73-77`), and photos load separately paginated at 150/page (`orders/photos/order-photos.ts:220-226`). Deriving it would silently report `false` for any order whose alterations sit past photo 150. An API-side count was rejected as a second repo and a blocking prerequisite |
| D4 | The `openDescription` copy says altered photos come "without an embedded watermark" — currently false | **Port it, flagged.** Bind `openDescription` and record the inaccuracy in a code comment | Holding the claim, or blocking on the API. Accepted risk — see §7 |

### D3 is a knowing deviation from `ab-723-compliance`

That skill prefers progressive disclosure: *"hide compliance UI entirely when an order has no altered photos."* Under D3, a compliant order with zero alterations still shows the caret, the option list, and the banner. The deviation is sound — the alternative derivation is *wrong* for large orders, and showing more disclosure UI is the safe direction against the skill's standing constraint — but it must be a comment in the file, not something a future reader re-derives.

## 3. What is ported, and what is deliberately not

### Ported from insgt-app

- Segmented web/print toggle inside the card; `downloadSize` signal (D1)
- Header title `MLS / Web-Ready Photos` / `Print-Ready Photos` (ops today: `Download MLS / Web`)
- Compliance filter on the option list + `openBundleOptions()` early return (D2)
- Caret gated on compliance mode, plus the `Options` label and its opacity transition
- The blue "Update:" banner
- `[innerHTML]="option.openDescription"` in the **expanded** branch; `description` stays in the collapsed branch — that asymmetry *is* the progressive-disclosure mechanic, and `openDescription` is currently dead code in ops (defined at `ts:68,77,86`, bound nowhere)
- Click-to-select on the whole row, not just the radio
- Compliant default `mls_originals_only` (ops today: `mls_with_alters`)
- Null-URL guard before `window.location.href`
- The four app `data-cy` names, verbatim

### Kept as-is — ops-specific, do not overwrite

- **Order comes from the NgRx store** (`store.select(orderSelectors.getOrder)`), not an `@Input()`. Ops has no order facade
- **No `accessToken`.** Staff are JWT-authenticated; ops's `downloadZipUrl` signature has no such param (`orders/store/services/order.service.ts:37`). Leave it alone
- **No in-card Disclosure Gallery button or MatDialog.** Ops already renders `<app-disclosure-gallery-qr-code>` as a sibling card (`order-photos.html:24`)
- **FontAwesome Sharp string tuples** (`[icon]="['fasr','sign-hanging']"`), not imported icon objects. **Verified: all five icons the port needs are already registered** — `sign-hanging` (`core/icons/icon.module.ts:52,140`), `print` (`:50,139`), `circle-check` solid (`:72,152`), `circle` regular (`:35,130`), `caret-down` solid (`:69,151`). No registry change
- `<app-button>` / `<app-spinner>` arrive via the `SharedModule` the component already imports. Ops's data hook input is **`dataCy`**, not the app's `buttonDataCy` (`shared/ui/buttons/button.component.ts:20`)

## 4. Styling translation — ops is Tailwind 3 with no DaisyUI

Verified: `tailwind.config.js` uses `theme.extend.colors` (`:5,:15`), so Tailwind defaults (`gray-*`, `green-*`) survive **and** the custom palette is added. `blue-50` `:107`, `blue-800` `:115`, `blue-200-accent` `:118`, `orange-50` `:242`, `orange-700` `:249` all exist — **the Update banner ports 1:1 with no class changes.**

Three things do not survive. `grep '\.alert' src/styles.css src/styles/*.css` → no output. `src/styles.css:636-639` carries an explicit note that DaisyUI was never wired into the build and the package is gone; only four compound names were hand-reimplemented (`.btn.btn-circle` and friends, `:640-652`), so bare `.btn`, `.join`, and `.join-item` resolve to nothing.

| Class | Where | Replacement |
|---|---|---|
| `join` / `join-item` / `btn` | size toggle, `app html:2-23` | Hand-rolled pair: `px-4 py-2 text-sm font-semibold border border-gray-300 rounded-l-md transition-colors duration-200 disabled:opacity-50 disabled:cursor-not-allowed` (mirror with `rounded-r-md border-l-0`), plus a **ternary** `[ngClass]` — `vm.downloadSize === 'web' ? 'bg-gray-500 border-gray-500 text-white' : 'bg-white text-gray-700 hover:bg-gray-100'`. A ternary, not an object literal: static `bg-white` and conditional `bg-gray-500` are both single-class selectors, so an object map leaves the winner to Tailwind's emission order |
| `alert alert-warning` | inside the `openDescription` **string** in the `.ts`, so `<app-notice>` is unavailable | `mt-2 flex gap-2 items-start rounded border border-orange-700 bg-orange-50 p-2 text-sm text-gray-800` — `#f57c00` on `#fff3e0` are the same two values ops's own `.card-notice.warning` uses (`src/styles/_notice.css:38-40`), so it reads as native ops warning chrome |
| `md:w-lg` | card, Tailwind 4 arbitrary scale | `md:w-[26rem]`. The literal 1:1 is `32rem`, but the inner options container is `w-96` (384px) + `md:p-4` = 416px = exactly `26rem`; `32rem` leaves 96px dead and pushes the flex row toward wrapping. Also **do not** port the app's `sm:w-full` on the options container — against an auto-width card that is a circular sizing dependency |

Two app classes to drop rather than translate: `hidden md:inline` / `md:hidden` responsive label pairs (ops is a 1280px desktop dashboard; the short labels exist for the PWA phone breakpoint), and `mx-auto px-4 md:px-0 w-full` on the outer wrapper (`w-full` would blow apart the `flex-wrap` row at `order-photos.html:23`).

**One verification step that must not be skipped.** Tailwind's extractor is a regex over raw file text and the `content` glob covers `.ts` (`tailwind.config.js:2`), so classes inside a TS string literal *should* be collected. After the change, build and grep the emitted CSS for `border-orange-700` and `bg-orange-50`. This fails silently — the callout would render as unstyled text, looking exactly like today. If the grep comes back empty, split `openDescription` into `{ body, warning }` and move the callout into real template markup.

## 5. Defects fixed along the way

Each is a separate commit so it bisects.

**5a. A staff member's bundle choice is silently discarded** (`ts:97-109`). The subscription re-derives `selectedBundleOption` on *every* order emission. The comment says "when compliance mode changes"; the code does not do that. `reducerService.updateResourceSuccess` assigns a **new** object from the API (`core/services/reducer.service.ts:192-194`), so `getOrder` re-emits on any `UpdateAttributeSuccess` — including the compliance toggle in the adjacent card (`orders/compliance/order-compliance.component.ts:61`), the property dialog, the related-order form, the YouTube thumbnail upload, and the `ReadSuccess` from classify polling (`orders/photos/order-photos.ts:356,360`). The Media tab keeps the component mounted throughout.

Fix — a `computed` *is* `distinctUntilChanged`, so derive the mode and let an effect depend on that, not on the order:

```ts
private readonly order = toSignal(this.store.select(orderSelectors.getOrder));
private readonly complianceMode = computed(() => this.order()?.complianceMode);

constructor() {
  effect(() => {
    const compliant = this.complianceMode() === ComplianceModes.compliant.id;
    this.selectedBundleOption.set(compliant ? 'mls_originals_only' : 'standard');
  });
}
```

**The tradeoff, stated:** an explicit choice is still discarded when compliance mode *genuinely* changes. That is deliberate. `insgt-api` guards both compliant bundles on `compliant_delivery?` and falls through to the unlabeled branch otherwise (`order_zip.rb:170,178,191-193`), so a legacy order still showing "MLS Simple" would hand the agent the plain marketing set under a compliance label — a labeling mismatch on an AB 723 surface. Resetting is the safe direction; what the fix buys is that *unrelated* saves no longer trigger it.

**5b. No null guard on the zip URL** (`ts:172`): `window.location.href = response.url` navigates to `undefined` when the API returns `ready` with no URL. Port the app's guard (`app ts:204-209`), minus its redundant second `resetZipPolling()`.

**5c. Wrong compliant default** (`ts:104-105`): `mls_with_alters` → `mls_originals_only`, matching `app ts:119`.

**5d. Zero `data-cy` hooks.** The feature has no e2e coverage in either repo beyond the app's two smoke assertions.

**5e. Redundant registration** (`orders/edit/order-edit.module.ts:60,89`): `OrderPhotos` is standalone and imports the component directly (`order-photos.ts:42,55`), and `app-order-download` appears in exactly one template repo-wide. `OrderComplianceComponent` and `DisclosureGalleryQrCodeComponent` are redundant there for the same reason — note it, but keep the commit scoped. `npm run knip` confirms.

## 6. Shape of the change

Convert mutable fields to signals first (`zipLoading`, `bundleOptionsOpen`, `selectedBundleOption`, and **`zipPollingCount`** — that last one drives the progress bar and is the thing that breaks under OnPush), then collapse template logic into one `vm` computed:

```ts
readonly vm = computed(() => {
  const order = this.order();
  const compliant = order?.complianceMode === ComplianceModes.compliant.id;
  const size = this.downloadSize();
  const selected = this.bundleOptions.find(option => option.id === this.selectedBundleOption());
  return {
    order, compliant, downloadSize: size,
    zipLoading: this.zipLoading(),
    progressPercent: (this.zipPollingCount() / this.maxZipPollingCount) * 100,
    bundleOptionsOpen: this.bundleOptionsOpen(),
    // Legacy orders can only receive the unlabeled bundle — insgt-api enforces the
    // same rule server-side (order_zip.rb:170,178), so the list must not offer more.
    options: this.bundleOptions.filter(o => !o.requiresCompliance || compliant),
    selectedLabel: size === 'web' ? selected?.webLabel : selected?.printLabel,
    selectedDescription: selected?.description,
  };
});
```

That removes three pieces of template logic the app carries: the compliance `@if` inside the `@for` (`app html:88`), the `@for`+`@if` scan for the selected option in the collapsed branch (`ops html:85-93`), and the repeated web/print label ternary (`ops html:67,87`). Template unwraps once with `@if (vm(); as vm)`, matching `order-photos.html:1-2`.

`changeDetection: OnPush` is worth adding per `angular-core` §2, but **only after** the signal conversion — otherwise the progress bar silently freezes at 0% while polling still works.

### Files

| File | Change |
|---|---|
| `src/app/orders/download/order-download.component.ts` | Signals, `vm` computed, `downloadSize`, `openBundleOptions()`, effect-based default, null guard, copy-accuracy comment |
| `src/app/orders/download/order-download.component.html` | Size toggle, header title, banner, option filter, gated caret + `Options`, `openDescription` binding, clickable rows, `data-cy` |
| `src/app/orders/photos/order-photos.html:26-31` | Two instances → one; the `relative z-30` wrapper moves **into** the component (see R1) |
| `src/app/orders/compliance/order-compliance.component.html` | One `data-cy` on the compliant radio, for the 5a regression test |
| `src/app/orders/edit/order-edit.module.ts:60,89` | Drop redundant registration |
| `cypress/e2e/orders/order-download.cy.ts` | New |

### Commit sequence

Per `git-commit-messages`, one concern each. Commits 2–4 are worth eyeballing before 5, which is the first that changes what staff see.

1. `feat: sync order download bundle copy with the agent dashboard` — the already-dirty working tree; body cites the watermark inaccuracy
2. `refactor: move order download component state to signals`
3. `fix: keep the chosen download bundle across unrelated order saves` — 5a; the commit a bisect should land on
4. `fix: guard against a missing zip url and default compliant orders to MLS Simple` — 5b + 5c
5. `feat: replace the download size input with an in-card web/print toggle` — D1; component and host cannot compile apart
6. `feat: hide unavailable bundles on legacy orders instead of scrimming them` — D2 + gated caret
7. `feat: surface the watermark update banner and expanded bundle descriptions` — D4 + clickable rows
8. `test: add data-cy hooks and a Cypress spec for the order download card`
9. `perf: run the order download component on OnPush` *(optional)*
10. `chore: drop the redundant OrderDownloadComponent registration`

## 7. The watermark copy is not true yet — accepted risk

`openDescription` for `mls_with_alters` says altered photos are provided *"without an embedded watermark."* **insgt-api still composites the overlay.** `order_zip.rb:178-187` passes `Photo::DIGITALLY_ALTERED_WATERMARK` / `VIRTUALLY_STAGED_WATERMARK` into `download_file_json`, and `functions/insgt-order-archiver/handler.js:236,297-304` burns it in on the presence of that key.

`docs/plans/watermark-injection.md` is written but **unimplemented** — it is untracked, scoped to insgt-api only, and states no commits were made. It also records an accepted limitation that matters here: the zip cache key is `MD5(filename + s3Version)` and excludes the bundle, and every automatic invalidation passes size only, so **already-built `mls_with_alters` zips stay watermarked even after the API fix lands.**

Per D4 this ships anyway — ops is an internal surface and insgt-app already carries the identical copy, so ops is inheriting an inaccuracy rather than creating one. But ops staff quote this text to agents on the phone, so the implementation **must** carry a comment above the `mls_with_alters` entry naming `order_zip.rb:180-187` and `docs/plans/watermark-injection.md` as the unblock.

**Follow-up, outside this work:** land `watermark-injection.md` in insgt-api, then revisit this copy. Its own write-back obligations are also still open — the decision is not recorded in `docs/compliance/ab-723.md`, the `<!-- FILL IN: insgt-api -->` gap in the `ab-723-compliance` skill is unfilled, and `docs/architecture/zip-watermark-codebase-notes.md` does not exist.

## 8. Verification

### Manual, on `/#/orders/<token>/edit` → Media tab (dev server 4300, API on `host.docker.internal:3000`)

| Check | Expected |
|---|---|
| Compliant order, ≥1 photo | One card. Title `MLS / Web-Ready Photos`. Collapsed label `MLS Simple`. Blue Update banner present. Caret + `Options` present |
| Toggle to Print | Title `Print-Ready Photos`, icon swaps to printer, label becomes `Print Simple` |
| Expand options, compliant | Three rows. MLS Complete shows the two-paragraph `openDescription` with a **visibly orange-bordered** callout — not a wall of unstyled text |
| Legacy order | One row (Marketing Photos). **No** caret, **no** banner, **no** "Option unavailable for legacy orders" text anywhere. Collapsed row does not open |
| Select a bundle, then edit an unrelated order attribute | Selection **survives** (5a) |
| Toggle compliance mode | Selection resets — deliberate (§5a) |
| Expand options with photos loaded | The three rows paint **above** the "Notify agent photos ready" button row (R1). Manual only |
| Click Download, zip pending | Overlay, both size buttons disabled, progress bar advancing in 10% steps |

Plus `npx ng build` (a green test run with a broken template is not green), `ng lint` on the touched files, and the Tailwind CSS grep from §4.

### Automated

**Vitest: nothing to add, and that is correct.** `angular-unit-testing` scopes it to the state layer and says explicitly *not* to use it for component, template, or user-flow testing. There is no download state layer — no actions, no reducer, no selector; the component calls `OrderService` directly. Do not manufacture a helper file just to have something Vitest-shaped to assert.

**Cypress e2e** — new `cypress/e2e/orders/order-download.cy.ts`, following `order-photos.cy.ts` conventions (`cy.loginAsAdmin()`, real seed order, `cy.viewport(1280, 2000)`, `scrollIntoView()` before every interaction; credentials from `cypress.env.json`). Control compliance mode by **patching the real order response**, not fixturing it — the order model is large and a fixture would rot:

```ts
cy.intercept('GET', `**/orders/${TOKEN}*`, (req) => {
  req.continue((res) => { res.body.complianceMode = mode; });
}).as('getOrder');
```

Cover: (1) compliant happy path — exactly one `download-card`, default `MLS Simple`, size toggle flips title and label, three rows on expand; (2) legacy — no banner, no caret, one row, scrim string absent; (3) **selection survives an unrelated save** — write red first against the pre-fix code; (4) a compliance change *does* reset; (5) zip request 500 → toast, overlay clears; (6) **`ready` with no URL → toast, no navigation** — write red first; (7) pending → overlay up, controls disabled.

**Never stub a `ready` response carrying a real S3 URL** — the `window.location.href` assignment navigates cross-origin and blows up the run.

**Skip** the 100-second max-polling timeout; `cy.clock()` is unreliable against zone.js-patched timers. Note it in the spec header rather than leaving a reader wondering.

**One repo gap to flag:** `cypress.config.ts` defines a `component` block and one component spec exists (`features/orders/components/order-metrics/order-metrics.cy.ts`), but `npm run test:e2e` is plain `cypress run`, which runs e2e only — that spec is orphaned from every script. If component specs are wanted here, add `"test:component": "cypress run --component"` rather than letting a second spec go unrun.

## 9. Risks

**R1 — Stacking context.** `order-photos.html:27` wraps only the *web* instance in `<div class="relative z-30">`. That is not decoration: `#bundle-options-container` is `absolute … z-20` inside a `relative` parent with no z-index, which is not a stacking context. Without the wrapper, that `z-20` competes in whatever the nearest real stacking context is — and photo tiles below carry `z-30` children (`order-photos.html:193`), the Notify/Sort/Tag button row sits directly beneath (`:81-99`), and `.grid-overlay` is `z-index: 100` (`styles.css:491-494`). The expanded dropdown grows downward out of an `h-20` box, so it *will* overlap that row. **Mitigation:** move `relative z-30` onto the component's own outer wrapper and render `<app-order-download>` bare in the host. Manual check only.

**R2 — The flex row grows taller.** `order-photos.html:23` is `flex flex-wrap` with default `align-items: stretch`, and both sibling cards use `h-full`. A ~40px toggle above the download card makes the compliance and QR cards ~40px taller. Cosmetic. If it reads badly, `items-start` on the row fixes it — but that changes the host layout for three cards, so decide it deliberately.

**R3 — Two-card loss.** D1's accepted cost. Named in §2.

**R4 — Silent Tailwind extraction failure.** §4's grep step exists for this.

**R5 — OnPush before signals.** Ordering constraint, not a judgment call: `zipPollingCount` must be a signal first or the progress bar freezes at 0% with nothing failing.

**R6 — Naming convention.** Ops's convention is no `Component` suffix and no `.component.ts`, and existing code migrates when already being touched. **Recommend against renaming in this work** — it would touch `order-photos.ts:42,55`, `order-edit.module.ts:60,89`, and the `templateUrl`, muddying a diff that already carries real behavior changes. If wanted, make it commit 11, pure.

**R7 — The "Dislosure" typo** in the `standard` bundle labels exists identically in both repos (`ops ts:83-84`, `app ts:102-103`). Fixing it in ops alone breaks copy parity. Fix both or neither — not silently here. The app's Update banner also has `orignal`; fix that in ops and flag it upstream.

**R8 — AB 723 deviation.** D3, recorded in §2. Must appear as a comment in the file.

## 10. Prerequisites and state at time of writing

- **Both repos have uncommitted changes to this component.** ops: `order-download.component.ts` (copy strings already synced to the app's wording). insgt-app: both `.ts` and `.html` (the same copy, plus the Update banner and a commented-out default-selection branch). **Work from the working tree, not from HEAD** — and do not inherit the app's commented-out block.
- No API change required (§1).
- `docs/plans/watermark-injection.md` is **not** a blocking prerequisite under D4, but it is the unblock for the §7 copy.
