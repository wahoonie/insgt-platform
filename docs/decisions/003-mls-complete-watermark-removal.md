# Decision: Remove the Burned Watermark from MLS Complete Downloads

**Status**: Accepted
**Date**: 2026-09-11

## Context

The `mls_with_alters` bundle — "MLS Complete" — delivered altered photos with a watermark PNG
composited into the bottom-left corner of every image. Agents received files they could not upload
as-is.

AB 723 (BPC § 10140.8) asks the agent for two things at publication: a "reasonably conspicuous"
statement near the image, and a link, URL, or QR code to the unaltered original
(`docs/compliance/ab-723.md:33-37`). It does not ask for a mark burned into the pixels. The one
place a watermark appears in our own requirements document is a note that **SFAR adds one itself**
during upload (`docs/compliance/ab-723.md:103`) — that is an MLS's upload behaviour, not a
statutory requirement, and delivering a pre-watermarked file to an SFAR agent produces two marks.

Two lines define our role, and both point away from the burned pixel:

- `docs/compliance/ab-723.md:102` — CRMLS, California's largest MLS, requires altered photos to be
  **labeled** with the original included **adjacent** in the listing. Not a burned mark.
- `docs/compliance/ab-723.md:106` — "Our job is to provide the raw materials (both photo versions,
  clear labeling) so agents can comply regardless of their MLS's specific implementation."

A burned overlay is one MLS's implementation baked irreversibly into the raw material.

## Problem

The overlay made the highest-value deliverable unusable for its primary purpose, while satisfying
no requirement we are actually bound by. `.claude/skills/ab-723-compliance/SKILL.md` places
dropping a watermark flag on its *Never do these* list **absent an explicit decision**. This is
that decision.

## Options Considered

1. **Keep the overlay.** Zero work. Leaves agents editing our files or using them unlabeled.
2. **Drop the overlay, keep every other disclosure signal.** Chosen.
3. **Drop the overlay and add an in-image caption or EXIF disclosure.** A new disclosure mechanism
   is a larger design question, and the archiver already stamps EXIF for copyright only. Not now.

## Decision

Drop the burned overlay from `mls_with_alters`. Keep every other disclosure signal.

Implemented by omitting the third positional argument to `download_file_json` at
`apps/insgt-api/app/models/concerns/order_zip.rb:190` and `:193`. The Lambda's composite is gated
solely on the presence of that key (`functions/insgt-order-archiver/handler.js:236`), with no
fallback that re-derives it — `grep -n "alterationType\|alteration" handler.js` returns nothing.

### What survives — two signals, not four

An earlier draft of this decision credited four signals. Two of them do not reach the agent, and
the count is corrected here so the record is accurate:

| Signal | Where | Reaches the agent? |
| :--- | :--- | :--- |
| `_1_digitally_altered` / `_1_virtually_staged` filename suffix | `file_name.rb:20-23` | **yes** |
| Unaltered `_2` counterpart shipped alongside | `order_zip.rb:191, 194` | **yes** |
| `alterationType` field in the manifest | `order_zip.rb:212` | **no** — the archiver never reads it |
| Disclosure gallery + QR | `order_disclosure.rb` | separate endpoint, not part of the bundle |

The archiver reads exactly four manifest fields — `file.filename`, `file.s3Bucket`, `file.s3Key`,
`file.watermark` — and its only write into the zip is
`archive.append(fileStream, { name: file.filename })` (`handler.js:116-119`). No manifest, no
README, nothing else reaches the person who opens the zip.

**Both surviving signals are therefore a compliance contract, not an incidental artifact.**
Removing either one reopens this decision. They are pinned by
`apps/insgt-api/spec/models/order_zip_spec.rb`.

### What this costs, stated plainly

The burned overlay was the only disclosure signal that travelled with the image **bytes**.
Filenames do not survive MLS ingest, and the paired `_2` file is a separate upload. After this
change **no signal we ship survives into the agent's published listing**; compliance at the point
of publication rests entirely on the agent's own action in their MLS interface.

That is defensible under `docs/compliance/ab-723.md:43` ("Our customers (agents) are ultimately
responsible for compliance") and `:106`, and it is the division of responsibility the product was
already built around. It is written down here because it is the substance of what was decided, not
a side effect.

What makes it workable is that the product now *tells the agent to do it*. In-flight (uncommitted
at the time of writing) changes to the download UI in both insgt-ops and insgt-app rewrite the MLS
Complete bundle description to read: "Digitally altered photos are provided **without an embedded
watermark** and are immediately followed by their unaltered version… **Important:** When uploading
an altered photo to the MLS, label it 'Digitally Altered,' 'Virtually Staged,' or equivalent in the
MLS photo-description field."
(the `mls_with_alters` entry's `openDescription` in `bundleOptions`, in
`apps/insgt-ops/src/app/orders/download/order-download.component.ts` and
`apps/insgt-app/src/app/orders/download/order-download.component.ts` — cited by symbol rather than
line because those files were being actively edited when this was written.) That instruction is
the disclosure mechanism this decision hands off to. **If it does not ship alongside this change,
the handoff is silent and the decision should be revisited.**

### Supersedes: print-size watermarking (366d001)

`functions/insgt-order-archiver` commit `366d001` "Added watermarks to print downloads"
(2026-01-28) commented out a `if (size === 'print')` bypass so print-size entries began receiving
the overlay, with a live comment reading *"Commenting that out for now to see if that is more what
agents are expecting."*

That commit was **correct for its inputs**: per the engineer's own account, agents in January 2026
did expect watermarks on print downloads, and the experiment bore that out. Note the repo itself
records no outcome — the comment poses the question and no later commit, ticket or measurement
answers it, so that result rests on recollection, not on anything reviewable here. Either way it is
superseded because **MLS actions changed the requirement**, not because the experiment failed. The stale comment has been removed so it no
longer contradicts current behaviour.

The print branch itself was **not** restored. After this change no zip manifest carries a
`watermark` key at any size, so the composite is already unreachable and restoring the branch would
remove zero watermarks — while stripping the 3360×2240 resize, the injected `Copyright` / `Artist`
EXIF, and the JPEG re-encode from print entries in **every** bundle. Full-resolution print output
may be a good product change; it is a different one, and it needs its own measurements and an
explicit decision about losing copyright EXIF.

## Consequences

**Good.** MLS Complete files are usable as delivered. Copy across the platform can finally describe
the product accurately — `functions/insgt-site-sls` advertised the watermark in 13 places,
including indexed FAQ JSON-LD, and now does not.

**Accepted limitations, deliberately not addressed here:**

- **Already-built zips stay watermarked.** The cache key is `MD5(filename + s3Version)`
  (`order_zip.rb:87`) and filenames are unchanged, so the digest is byte-identical and both
  short-circuits — Rails `order_zip.rb:39-43` and the Lambda `handler.js:61,380` — keep serving the
  old zip. No automatic invalidation path ever touches this bundle: all eight automatic callers
  (`photo.rb:140-141`, `order_event.rb:41-42,56-57`, `photo_copy_worker.rb:38-39`) pass a size
  only and default `bundle` to `'standard'`. The one caller that does pass a bundle,
  `order_zip.rb:59`, is the user-initiated build-if-missing path — it fires only when the zip is
  absent or its version already mismatches, so it never invalidates a valid cached zip. For an order already delivered the change is inert
  until a photo change bumps `s3Version`. `order.refresh_zip_files(size, 'mls_with_alters')`
  flushes one on demand.
- **Individual photo downloads still burn a watermark.** `photos_controller.rb:144-150` →
  `functions/insgt-resource-downloader/handler.js:85-97` is untouched, so the same altered photo is
  watermarked when downloaded singly from insgt-ops or insgt-app and unwatermarked inside the MLS
  Complete zip. Out of scope for this slice; it should be reconciled.

**Open compliance risk, pinned but not fixed — and this decision sharpens it.** An altered photo
can reach the bundle with no unaltered counterpart, by two routes: none was ever created, or one
was created and later soft-deleted (`Photo#unaltered_photo` is scoped `-> { active }`,
`photo.rb:71`, and insgt-ops offers counterpart deletion behind a confirmation dialog). Either way
the altered photo still ships labeled `_1_*` while the `_2` it points at is absent. The bundle
then asserts an alteration whose unaltered original it does not carry — a direct conflict with the
standing constraint in `ab-723-compliance`.

This is pre-existing behaviour, but **this decision makes its consequence worse**: before, such a
file at least carried the burned overlay declaring it altered; now the filename suffix is the only
thing it has, and that does not survive MLS ingest. An independent review graded it a blocker on
exactly this reasoning. It is accepted here as out of scope for this slice, not dismissed.

Both routes are pinned by examples in `spec/models/order_zip_spec.rb` labelled KNOWN GAP, so the
next change to either is deliberate. Closing it — failing closed, or falling back to the unscoped
association — needs its own slice, and should be the next one.

## Notes

- `Photo::DIGITALLY_ALTERED_WATERMARK` and `VIRTUALLY_STAGED_WATERMARK` stay. Their live
  pixel-burning consumer is `photos_controller#download_info` →
  `functions/insgt-resource-downloader`. They are also passed into the disclosure gallery JSON
  (`order_disclosure.rb:50,55`), but no client reads that key — `insgt-disclosure-gallery` derives
  its overlay client-side from `alterationType` against its own hardcoded constants, which point at
  a *different* asset (`watermarks/digitally-altered.png`) than the API sends
  (`...-cropped.png`). The gallery examples in `order_zip_spec.rb` lock the JSON contract anyway,
  cheaply, because that drift is the kind of thing that bites later.
- `Photo#requires_watermark?` (`photo.rb:463-466`) has no callers, and
  `Photo.alteration_types` still carries `watermark: true` for ids 2 and 3. Both now describe the
  single-download path only, not the zip.
- Three unrelated things in insgt-api are called "watermark": this AB 723 overlay; the legacy
  branding mark `ImageHandler::WATERMARK` (`lib/image_handler.rb:6`, `watermark-3.png`) driven by
  `Order.jailed_to_watermarks?`; and the Paperclip attachment columns at `db/schema.rb:884-887`.
  Only the first is touched here.
