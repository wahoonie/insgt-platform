# Daily tasks — Zillow 3D list dialog

Shipped 2026-10-04 on two unmerged branches: `insgt-api` `feat/processing-parent-pays`, `insgt-ops` `feat/daily-tasks-zillow3d-dialog`. Deploy the API first; until it is live, ops rows carry no `parentPays` and every child opens its own list.

## What it does

The processing queue's package cell shows a 360-degrees button on any row whose order type or any service is a Zillow 3D. The button opens `Zillow3dListDialog`, which reads the order by token and hosts the existing `Zillow3dList`. A child row whose parent pays opens the parent's list.

## Decisions

| Question | Decision | Rejected |
|---|---|---|
| How does the row know the parent pays? | `parent_pays` added to `/orders/processing` (SQL select list plus `json[:parentPays]`, coerced so NULL is `false`). | A second client-side read in the dialog; treating every child as parent-pays. |
| What is a Zillow 3D? | Order type name or **any** service name contains `zillow`, case-insensitive. Mirrors `ipIsMatterport`. | Order type id 75; serializing `order_types.key`. |
| Who sees the button? | `ipUserCanProcessOrder`, same as the upload icon. Shown on child rows; no `processingType` gate. | Everyone on the queue; admins and schedulers only. |
| What does the dialog receive? | `{ orderToken }`. The caller resolves `parentPays && parentToken ? parentToken : token`. | Passing `{ id } as Order`. |
| Where is `hasZillow3d` computed? | `newGridObject`, from the raw order's services. The row's `services` drops anything not requiring processing. | — |
| When is the dialog's load "failed"? | Read settled and no order with the requested token arrived. Not keyed on `error`: a soft-deleted order returns 204, which `ApiService._one` turns into an empty `Order` and a `ReadSuccess`. | `!order && !loading && !!error`, which spun forever on 204. |

## Code map

| File | What |
|---|---|
| `insgt-api/app/models/concerns/order_sql.rb:41` | `orders.parent_pays` in `select_all_processing` |
| `insgt-api/app/controllers/orders_controller.rb:366` | `json[:parentPays]` |
| `insgt-api/spec/requests/orders_processing_parent_pays_spec.rb` | true, false, NULL, parent row |
| `insgt-ops/src/app/processing/dashboard/daily-tasks-zillow3d.ts` | `orderHasZillow3d`, with a Vitest spec beside it |
| `insgt-ops/src/app/processing/dashboard/daily-tasks-paying-order.ts` | `payingOrderToken` (was `zillow3dOrderToken`; now shared with the floor plan button, see `daily-tasks-floorplan-dialog.md`), with a Vitest spec beside it |
| `insgt-ops/src/app/processing/dashboard/processing-grid-data.model.ts:47-49, 154-155` | `parentPays`, `hasZillow3d` on the row |
| `insgt-ops/src/app/features/order-url-groups/dialogs/zillow3d-list-dialog/zillow3d-list-dialog.ts` | `Zillow3dListDialog` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.ts:141` | `openZillow3dDialog` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.html` | the button, in the processor column's `processor-actions` group (moved there from the package line on 2026-10-04, see `daily-tasks-photos-dialog.md`) |
| `insgt-ops/src/app/core/icons/icon.module.ts` | `fa360Degrees` in the sharp-solid pack |
| `insgt-ops/cypress/e2e/processing/daily-tasks-zillow3d.cy.ts` | seven flows, including parent-pays and the 204 case |

## Known and accepted

- The button's tooltip overlapped the photo-count tooltip on `div.package` until the group moved to the processor column on 2026-10-04.
- The dialog's static import puts `Zillow3dList` and its new and edit dialogs into the processing-dashboard chunk, as `OrderUrlListDialog` already does.
- `resourceLoading` is shared by the whole order slice. A `ReadOutstandingProcessingError` landing mid-read can end the spinner early, after which the matching order still renders.
