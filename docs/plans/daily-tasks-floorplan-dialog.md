# Daily tasks — floor plan list dialog

Built 2026-10-04 in `insgt-ops` on top of the Zillow 3D dialog (`daily-tasks-zillow3d-dialog.md`), uncommitted. No API change: it uses the `parentPays` field that work added to `/orders/processing`, so deploy order is the same. Until the API is live every child opens its own list.

## What it does

The processing queue's package cell shows a table-layout button, beside the 360-degrees one, on any row that has a floor plan. The button opens `FloorplanListDialog`, which reads the order by token and hosts `FloorplanList`. A child row whose parent pays opens the parent's list.

`FloorplanList` replaces `FloorplanListComponent`. It takes its order as an input instead of reading the store, so the order-edit page now passes its order in too.

## Decisions

| Question | Decision | Rejected |
|---|---|---|
| What has a floor plan? | Order type name or **any** service name matches `/floor\s*plan/i`, **or** the order has a Zillow 3D. A Zillow 3D always includes a floor plan (Dan). | Order type id 33; serializing `order_types.key`. |
| Who sees the button? | `ipUserCanProcessOrder`, same as the Zillow button. Shown on child rows; no `processingType` gate. | — |
| Which order does it open? | `payingOrderToken`, moved out of the Zillow file and shared by both buttons. | A second copy of the rule. |
| How does Escape behave? | The dialog owns its close policy: `disableClose`, then backdrop click closes, and Escape closes only while no slideshow is open. MatDialog closes on Escape keydown and the slideshow on keyup, so the default would destroy both on one press. | Stopping propagation, which misses keydowns targeted at the dialog container; an output from the list, since the slideshow has no close output to hook. |
| How does sorting reach the store? | `appSortable` now emits the sorted ids. The list binds it a copy and dispatches `Sort` from the payload. | Binding the store collection, which NgRx freezes in dev; the directive assigns to `.data` on drop. |
| What gates the list's UI? | The collection's data only. `getLoading` and `getError` are not read. | Keying on `getLoading`, which `floorplan.reducers.ts` leaves stuck `true` after any error. |
| Where do failed "Notify agent" events surface? | The dialog observes `orderSnackBar`. `/processing` observes no order snack bar otherwise. This is the one deliberate difference from `Zillow3dListDialog`. | Silence. |

## Code map

| File | What |
|---|---|
| `insgt-ops/src/app/processing/dashboard/daily-tasks-floorplan.ts` | `orderHasFloorplan`, with a Vitest spec beside it |
| `insgt-ops/src/app/processing/dashboard/daily-tasks-paying-order.ts` | `payingOrderToken`, shared with the Zillow button, with a Vitest spec beside it |
| `insgt-ops/src/app/processing/dashboard/processing-grid-data.model.ts` | `hasFloorplan` on the row |
| `insgt-ops/src/app/features/floorplans/components/floorplan-list/floorplan-list.ts` | `FloorplanList` |
| `insgt-ops/src/app/features/floorplans/dialogs/floorplan-list-dialog/floorplan-list-dialog.ts` | `FloorplanListDialog` and its close policy |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.ts` | `openFloorplanDialog` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.html` | the button, after the Zillow button in the processor column's `processor-actions` group (moved there from the package line on 2026-10-04, see `daily-tasks-photos-dialog.md`) |
| `insgt-ops/src/app/shared/sortable.directive.ts` | `appOnSort` emits `number[]` |
| `insgt-ops/src/app/core/icons/icon.module.ts` | `faTableLayout` in the sharp-solid pack |
| `insgt-ops/cypress/e2e/floorplan-list/floorplan-list.cy.ts` | order-edit card: notify, level type, sort mode, empty, 500 |
| `insgt-ops/cypress/e2e/processing/daily-tasks-floorplan.cy.ts` | ten queue flows, including the Zillow rule, parent-pays, 204, and Escape |

## Known and accepted

- The button's tooltip overlapped the photo-count tooltip on `div.package` until the group moved to the processor column on 2026-10-04.
- The dialog's static import puts `FloorplanList`, the slideshow and the uploader into the processing-dashboard chunk.
- `SlideshowComponent.launch` calls `window.scrollTo(0, 0)`, which scrolls the queue behind the dialog.
- Escape on the confirmation opened from the slideshow's Delete closes the confirmation on keydown and the slideshow on keyup. It does the same on order-edit today.
- `floorplan.reducers.ts` routes every error through `readResource`, leaving `loading` true and `error` cleared. Not fixed here; it needs its own reducer spec.
- `FloorplanNewComponent.ngOnDestroy` references `this.uploader.cleanup` without calling it. Pre-existing.
- Drag-sorting is not covered by Cypress: jQuery UI sortable does not respond reliably to synthetic events.
