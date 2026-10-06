# Daily tasks — video list dialog

Built 2026-10-05 in `insgt-ops` on branch `feat/daily-tasks-video-dialog`, on top of the Zillow 3D, floor plan, photos and Matterport dialogs (`daily-tasks-zillow3d-dialog.md`, `daily-tasks-floorplan-dialog.md`, `daily-tasks-photos-dialog.md`, `daily-tasks-matterport-dialog.md`). No API change: it reads `orderType.video` and `services[].video`, which `/orders/processing` already sends, and the `parentPays` field the Zillow work added.

**Verified:** Vitest (578), the dev build, ESLint, the Cypress type check, and Cypress against the host servers: the two new specs plus every other `daily-tasks-*` spec and the Matterport and Zillow list specs, 58 tests. Two rounds of Codex review; the second found nothing. Not checked by eye in a browser.

## What it does

The processing queue's `processor-actions` group shows a video button, after the Matterport cube, on any row whose order type or any service carries the API's video flag. It opens `VideoListDialog`, which reads the order by token and shows the token and address above `VideoList`. A child row whose parent pays opens the parent's list.

The button replaces a cloud-upload icon that opened the old `OrderUrlListDialog` for any package *named* video or matterport. That is why a Matterport package used to open Videos. The icon appeared twice, in the processor actions and in the package column's services loop, and both copies are gone, with the dialog and the `ipHasOrderUrl` pipe.

`VideoList` replaces `VideoListComponent` and moved into `features/order-url-groups`, with its new and edit dialogs and the thumbnail upload. That folder now holds all three url-group lists. It takes its order as an input instead of reading the store, so the order-edit page now passes its order in.

## Decisions

| Question | Decision | Rejected |
|---|---|---|
| What has a video? | `orderHasVideo`: `orderType.video` or **any** `service.video`, the API's own flags. Both are coerced to booleans by `OrdersController#processing` (`orders_controller.rb:402`, `:417`). | Name matching like the three siblings, which exist because Zillow and Matterport have no flag. "Video" appears in names that are not videos. |
| Row flag | One `hasVideo`, from the helper, replaces `hasVideo` (order type only) and `hasVideoServices`. Its other reader, the unbranded-video notice, is unchanged in behaviour. | Three overlapping flags. |
| Who sees the button? | `ipUserCanProcessOrder`, on children and on schedule-no-processing rows, as the Matterport button. | The old icon's `!parentId` and `processingType` gates, which hid it from a parent-paid child. |
| Which order does it open? | `payingOrderToken`. | `processingOrderToken`, the photos rule. |
| Notify agent | Stays on the list. `VideoList` toasts its own success, as `FloorplanList` does, because no snack bar announces it. The chip appears from the order the TriggerEvent returns. | — |
| Snack bars in the dialog | `orderSnackBar` and `orderUrlSnackBar`. The second is the only signal for the edit dialog's link removal and MP4 upload on `/processing`. | `orderSnackBar` alone, as the Matterport dialog has. |
| The edit dialog's order | Passed in dialog data by the list. | The shared order slice, which every TriggerEventSuccess replaces. |
| The thumbnail upload | Takes the `orderUrlGroup` input the edit dialog already bound. It had no such input and read the store; basic template type-checking let that through. | Moving it unchanged. |
| Move scope (Dan) | Only `order-url-groups/videos`. `order-urls/video` and `order-urls/youtube` stay, used by `OrderUrlsComponent`. | Starting a split of the `order-urls` feature. |
| Width and close policy | 750px, MatDialog default, as the Matterport dialog. | — |
| `validate()` | The new dialog's `(ngSubmit)` called a missing `validate()`, so Enter threw. It calls `submit()`. | — |

## Code map

| File | What |
|---|---|
| `insgt-ops/src/app/features/order-url-groups/components/video-list/video-list.ts` | `VideoList`, with an `order` input |
| `insgt-ops/src/app/features/order-url-groups/components/video-thumbnail-upload/` | moved; `orderUrlGroup` input |
| `insgt-ops/src/app/features/order-url-groups/dialogs/video-new-dialog/` | moved; selector; `submit()` fix |
| `insgt-ops/src/app/features/order-url-groups/dialogs/video-edit-dialog/` | moved; selector; order from dialog data |
| `insgt-ops/src/app/features/order-url-groups/dialogs/video-list-dialog/` | `VideoListDialog` |
| `insgt-ops/src/app/features/orders/pages/order-edit/order-edit.page.html` | passes `[order]` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks-video.ts` | `orderHasVideo`, with a Vitest spec beside it |
| `insgt-ops/src/app/processing/dashboard/processing-grid-data.model.ts` | one `hasVideo` on the row |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.ts` | `openVideoDialog`; `openOrderUrlDialog` removed |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.html` | the button; both upload icons removed |
| `insgt-ops/src/app/processing/processing.module.ts` | stray `VideoListComponent` import removed |
| `insgt-ops/src/app/shared/order.pipe.ts`, `shared.module.ts` | `OrderHasOrderUrlPipe` removed |
| `insgt-ops/src/app/order-urls/list/order-url-list.dialog.*` | deleted |
| `insgt-ops/cypress/e2e/video-list/video-list.cy.ts` | order-edit card: links, add to edit handoff, Enter submits, Notify agent, empty, 500 |
| `insgt-ops/cypress/e2e/processing/daily-tasks-video.cy.ts` | ten queue flows, including the flags, parent pays, schedule-no-processing child, notify inside the dialog, 500 and 204 |

## Known and accepted

- **Failed video saves are silent.** Nothing announces `CreateVideoError`, `UpdateVideoError`, `DeleteVideoError` or `ReadVideoCollectionError`, on order-edit or in the dialog. Matterport and Zillow 3D are identical, and nothing observes `orderUrlGroupSnackBar`. Fix all three lists in one follow-up.
- `VideoUploadComponent` resets its spinner on `orderActions.CreateUrlSuccess`, but its own dispatch is `orderUrlActions.Create`, so that listener never fires. The dialog's `orderUrlSnackBar` covers the failure toast. Pre-existing.
- The Matterport dialog does not observe `orderUrlSnackBar`, so its link removal is silent on `/processing`. Follow-up.
- `ReadVideo` clears `resource`, not `video` (`order-url-group.reducers.ts`), so the edit form initialises from the previous record behind the spinner. Same as Matterport.
- `resourceLoading` is shared by the whole order slice, the same caveat as the other dialogs.
- The dialog's static import puts `VideoList` and its dialogs into the processing-dashboard chunk.
