# Daily tasks — order photos dialog

Built 2026-10-04 in `insgt-ops` on branch `feat/daily-tasks-photos-dialog`, on top of the Zillow 3D and floor plan dialogs (`daily-tasks-zillow3d-dialog.md`, `daily-tasks-floorplan-dialog.md`). No API change.

## What it does

The processing queue's processor cell shows an images button on every row the user may process. The whole `processor-actions` group (upload, Zillow 3D, floor plans, photos) moved from the package cell to the processor cell, beneath the assignment, and is dimmed to 60% so the solid icons do not outweigh the name above them. The button opens `OrderPhotosDialog`, which reads the order by token and hosts `OrderPhotos`, the same Photos card the order-edit Media tab embeds: the grid, sort, tagging, classification, the uploader, the compliance toggle, the download bundles and the disclosure QR code. A child row processed on its parent opens the parent's photos.

`OrderPhotos` now takes its order as an input, so the order-edit page passes its order in, as it already does for the Zillow 3D and floor plan lists.

## Decisions

| Question | Decision | Rejected |
|---|---|---|
| Which order does a child row open? | The API's `Order#processing_token` rule: the parent when the row has `parentId` and `processingType` is not `default`. That is where the child's photos were uploaded. `processingOrderToken`, beside `payingOrderToken`. | `payingOrderToken`, as the Zillow and floor plan buttons use: who pays is a billing rule. A non-default child whose parent does not pay would open an empty grid; a default-processing parent-paid child uploads under its own token. |
| Who sees the button? | `ipUserCanProcessOrder`, same as the other two buttons. No `hasX` flag (every order has the card) and no `processingType` gate (the helper already resolves non-default children to the parent, which is what order-edit's "upload to the parent order" notice tells the processor). | — |
| How does `OrderPhotos` get its order? | `input.required<Order>()`. The dialog reads the order into the shared `orders` slice by token and passes the token-matched order in. | Leaving it on the store (it stayed the one list on order-edit without an input). Converting its two store-reading children too; see Known and accepted. |
| What keys the photo load? | The order id, not the object. Fed from the store, every `UpdateAttributeSuccess` (compliance toggle), `TriggerEventSuccess` (Notify) and the classify poll's `ReadSuccess` replaces the object, and keying on it blanked and reloaded the grid each time. Latent on order-edit before. | — |
| What about the previous order's photos? | The root photos slice is never cleared when a dialog closes. The card resets its local copy before dispatching `ReadCollection` and only copies a store collection whose photos carry its own order id. | Clearing the slice from the dialog, which would need a new photo action. |
| Why is the dialog not OnPush like its siblings? | `OrderDownloadComponent` gates its "Building file" overlay on polling fields set from an HTTP subscribe and an `interval`, and the uploader's progress bar reads a plain `uploader.progress`. Under an OnPush host the overlay stayed up after the zip downloaded and the bar moved once per completed file. `FloorplanNewComponent` uses signals, which is why the floor plan dialog never showed this. | Converting both children to signals (out of scope). |
| How does Tag behave? | The card's Tag button routes to `/photos?orderId=`. MatDialog's `closeOnNavigation` only watches popstate and hashchange, and `Router.navigate` fires neither, so the dialog closes itself on the first `NavigationStart`. | `OrderPhotos` closing an optionally injected `MatDialogRef` (it is also embedded on order-edit and must stay host-agnostic). |
| How does Escape behave? | As in `FloorplanListDialog`: the dialog owns its close policy, Escape closes only while the card's slideshow is closed. `OrderPhotos` exposes `slideshowOpen()`. Nested dialogs (alterations, tag, confirmations) get Escape first; the CDK keyboard dispatcher delivers keydown only to the most recently attached overlay. | — |
| Size | `90vw` by `80vh` with `full-height-dialog`. `.tiles.md` tiles are 200px tall and sized by viewport media queries, so a 900px dialog would cram six 140px tiles; 150 tiles a page needs the surface to scroll inside, which Material's 65vh content cap would otherwise leave as dead space. | 900px like the floor plan dialog. |

## Code map

| File | What |
|---|---|
| `insgt-ops/src/app/orders/photos/order-photos.ts` | `order` input, id-keyed photo load, `slideshowOpen()` |
| `insgt-ops/src/app/orders/photos/order-photos.html` | test hooks: `tag-photos-btn`, `photo-tile-open`, `photos-slideshow` |
| `insgt-ops/src/app/features/orders/pages/order-edit/order-edit.page.html` | passes `[order]` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks-processing-order.ts` | `processingOrderToken`, with a Vitest spec beside it |
| `insgt-ops/src/app/features/orders/dialogs/order-photos-dialog/order-photos-dialog.ts` | `OrderPhotosDialog`: token-matched read, close policy, navigation close, order snack bar |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.ts` | `openPhotosDialog` |
| `insgt-ops/src/app/processing/dashboard/daily-tasks.component.html` | the button, last in `processor-actions`, now in the processor column |
| `insgt-ops/src/app/core/icons/icon.module.ts` | `faImages` in the sharp-solid pack |
| `insgt-ops/cypress/e2e/processing/daily-tasks-photos.cy.ts` | eleven queue flows: gate, parent and child tokens, 500, 204, Escape, backdrop, Tag navigation, no stale photos |

## Known and accepted

- `OrderDownloadComponent` and `DisclosureGalleryQrCodeComponent` still read `orderSelectors.getOrder` from the store, not the card's input. Inside the dialog that is the same order, but a future dialog that dispatches `orderActions.Read` while this one is open would silently redirect those two. Converting them to inputs is the follow-up.
- The `photoSceneTypes` slice is not provided on `/processing`. `TagPhotoDialog` (the per-tile tag button, shown only when the order type classifies photos) injects its facade but binds nothing from it, so it opens.
- The virtualized sort viewport is `70vh`, slightly taller than the dialog's content area, so the outer content scrolls a little in that mode (more than 150 photos only).
- `SlideshowComponent.launch` calls `window.scrollTo(0, 0)`, which scrolls the queue behind the dialog, as on floor plans.
- `PhotoUploaderService` is a root singleton: an upload started in one dialog keeps its order after the dialog closes. Same as navigating between order-edit pages today.
- The static import puts the card, the slideshow, the uploader and the two nested dialogs into the processing-dashboard chunk. The new weight is `@fancyapps/ui` via `UnalteredPhotoCrudDialog`, roughly 60-80 KB minified, previously only in order-edit. Lazy chunks are unbudgeted.
- Escape on the confirmation opened from the slideshow's Delete closes the confirmation on keydown and the slideshow on keyup, as on order-edit and floor plans today.
- `appSortable` is unchanged: the directive still assigns `.data` on the mutable local copy the card binds, then emits. Binding `(appOnSort)` as the floor plan list does is optional cleanup.
