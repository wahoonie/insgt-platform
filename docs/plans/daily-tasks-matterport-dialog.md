# Daily tasks — Matterport list dialog

Built 2026-10-04 in `insgt-ops` on branch `feat/daily-tasks-matterport-dialog`, on top of the Zillow 3D, floor plan and photos dialogs (`daily-tasks-zillow3d-dialog.md`, `daily-tasks-floorplan-dialog.md`, `daily-tasks-photos-dialog.md`). No API change: it uses the `parentPays` field the Zillow work added to `/orders/processing`, so the same deploy order applies.

**Cypress not yet run.** The host's dev server (4300) and API (3000) accepted connections but answered no HTTP request while this was built, so login timed out in every spec, the untouched `zillow3d-list.cy.ts` included. Vitest, the dev build, ESLint and the Cypress type check pass. Run the specs below before merging.

## What it does

The processing queue's `processor-actions` group shows a cube button, after the Zillow 3D one, on any row with a Matterport. It opens `MatterportListDialog`, which reads the order by token, with the `matterport_status` include. The dialog shows the token and address, then the Matterport status card, then `MatterportList`. A child row whose parent pays opens the parent's list.

`MatterportList` replaces `MatterportListComponent` and moved into `features/order-url-groups`, with its new and edit dialogs. It takes its order as an input instead of reading the store, so the order-edit page now passes its order in.

## Decisions

| Question | Decision | Rejected |
|---|---|---|
| What has a Matterport? | Order type name or **any** service name contains `matterport`, case-insensitive. Mirrors `orderHasZillow3d`. | `ipIsMatterport`, which reads the package name only. It still gates the queue's Matterport info icon and upload icons. |
| Who sees the button? | `ipUserCanProcessOrder`, as the Zillow and floor plan buttons. Shown on child rows; no `processingType` gate. | — |
| Which order does it open? | `payingOrderToken`, as the Zillow and floor plan buttons. | `processingOrderToken`, the photos rule. |
| Where does the status card go? (Dan) | The host decides. `MatterportList` has `showStatus`, default true, so order-edit keeps the card hanging over the card's top edge (`-mt-12`). The dialog passes false and renders the card in flow above the list. | The old wrapper inside the dialog, which covered the title row and the close button. Dropping `-mt-12` everywhere, which grew the order-edit card by about 3rem. |
| How does the card get its dates? | The dialog's `orderActions.Read` passes `includes: ['matterport_status']`, as order-edit and the scheduler map do. | — |
| How does the list close its dialogs? | Tracks the new and edit dialog refs and closes only those, as `Zillow3dList`. | `dialog.closeAll()`, which closed the host dialog too. |
| Width | 750px, as the Zillow dialog. The status card is above the list, not in its header. | 900px. |
| Close policy | MatDialog default. The list has no slideshow. | — |
| `validate()` (Dan) | Both the Matterport and the Zillow 3D new dialogs bound `(ngSubmit)` to a missing `validate()`, so Enter threw. Both now call `submit()`. | Fixing only the Matterport one. |

## Code map

| File | What |
|---|---|
| `insgt-ops/src/app/features/order-url-groups/components/matterport-list/matterport-list.ts` | `MatterportList`, with `order` and `showStatus` inputs |
| `insgt-ops/src/app/features/order-url-groups/dialogs/matterport-new-dialog/` | moved; gained a selector; `submit()` fix |
| `insgt-ops/src/app/features/order-url-groups/dialogs/matterport-edit-dialog/` | moved; dead `orderSelectors.getOrder` read removed |
| `insgt-ops/src/app/features/order-url-groups/dialogs/matterport-list-dialog/` | `MatterportListDialog` |
| `insgt-ops/src/app/features/order-url-groups/dialogs/zillow3d-new-dialog/zillow3d-new-dialog.html` | `submit()` fix |
| `insgt-ops/src/app/shared/orders/matterport-status.card.html` | `data-cy="matterport-status-card"` |
| `insgt-ops/src/app/features/orders/pages/order-edit/order-edit.page.html` | passes `[order]` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks-matterport.ts` | `orderHasMatterport`, with a Vitest spec beside it |
| `insgt-ops/src/app/processing/dashboard/processing-grid-data.model.ts` | `hasMatterport` on the row |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.ts` | `openMatterportDialog` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.html` | the button, after Zillow 3D in `processor-actions` |
| `insgt-ops/src/app/core/icons/icon.module.ts` | `faCube` in the sharp-solid pack |
| `insgt-ops/cypress/e2e/matterport-list/matterport-list.cy.ts` | order-edit card: links, status card, add to edit handoff, Enter submits, empty, 500 |
| `insgt-ops/cypress/e2e/processing/daily-tasks-matterport.cy.ts` | nine queue flows, including the include, parent-pays, create inside the dialog, 500 and 204 |

## Known and accepted

- The dialog's static import puts `MatterportList` and its new and edit dialogs into the processing-dashboard chunk, as the Zillow dialog already does.
- `resourceLoading` is shared by the whole order slice, the same caveat as the Zillow dialog.
- `ReadMatterport` passes no `resource` override to `readResource` (`order-url-group.reducers.ts`), so the edit dialog builds its form from the previous record before the fresh one lands. `CreateMatterport` toggles `resourceLoading`, not `matterportResourceLoading`, so the new dialog never spins. Zillow is identical. Not fixed here.
- Nothing on `/processing` observes `orderUrlSnackBar`, so clearing a link from the edit dialog inside the queue dialog shows no toast. The field still clears. Same as Zillow.
