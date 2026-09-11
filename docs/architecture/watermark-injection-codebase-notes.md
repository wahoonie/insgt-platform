# Zip Watermark Injection — codebase notes

The `file:line` map for `insgt-platform/docs/decisions/003-mls-complete-watermark-removal.md`,
which is the authority; `insgt-platform/docs/plans/watermark-injection.md` is the superseded plan
that preceded it. Read at Phase 0 of every slice that touches
photo delivery; verify the entries the slice depends on before surveying fresh. Flat and factual:
file, line, what it is, which slice or commit put it there. Paths are `apps/insgt-api` unless
prefixed — note `apps/insgt-api/docs/` exists, so platform-repo documents are written
`insgt-platform/docs/...` here rather than bare `docs/...`.

Established 2026-09-11 for the watermark-injection slice, against `insgt-api` at `d98632f`
(`feat/digital-watermarks`), `insgt-order-archiver` at `64d7be9` (`feat/selective-photos`) and
`insgt-site-sls` at `9740aaa` (`feat/digital-watermarks`). Line numbers are **post-slice**. Unlike
the other notes files in this directory, this one's parent document lives in `docs/plans/`, not
beside it here — there is no watermarking contract doc. A moved line is a reason to update this
file, not to distrust it.

## The zip delivery chain

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/concerns/order_zip.rb` | 6 | `ALLOWED_BUNDLES` — duplicated in the Lambda at `functions/insgt-order-archiver/handler.js:28`; must be kept in sync by hand | legacy |
| `app/models/concerns/order_zip.rb` | 43 | Rails-side cache short-circuit: serves the existing zip when the stored `version` matches | legacy |
| `app/models/concerns/order_zip.rb` | 64 | `refresh_zip_files(size, bundle = DEFAULT_BUNDLE)` — the **only** flush entry point; every automatic caller omits `bundle`, so `mls_with_alters` is never auto-invalidated | legacy |
| `app/models/concerns/order_zip.rb` | 87 | Cache key `MD5(filename + s3Version)`. Does **not** include the watermark, which is why ADR 003 is inert for already-built zips | legacy |
| `app/models/concerns/order_zip.rb` | 142–150 | `zip_file_name_compliance_suffix` — names the **directory** (`_simple` / `_complete` / `_marketing`). Watermark-independent | legacy |
| `app/models/concerns/order_zip.rb` | 165–204 | `photos_for_zip_download` — the bundle branch table | legacy |
| `app/models/concerns/order_zip.rb` | 179–185 | **Why no watermark pointer is passed.** The comment that stops the next reader restoring it | watermark slice |
| `app/models/concerns/order_zip.rb` | 186 | The `mls_with_alters` branch | legacy |
| `app/models/concerns/order_zip.rb` | 187 | `params[:watermark] = true` — **not a watermark.** Drives the `_1_*` filename suffix via `FileName.compliance_suffix`. Deleting it silently renames every altered file to `_3_marketing` | legacy; pinned by the slice |
| `app/models/concerns/order_zip.rb` | 190, 193 | The two edited call sites — third positional argument dropped | **watermark slice** |
| `app/models/concerns/order_zip.rb` | 191, 194 | The `_2` counterpart emission. A compliance contract per ADR 003 | legacy; pinned by the slice |
| `app/models/concerns/order_zip.rb` | 206 | `download_file_json(photo, params, watermark = nil)` — **12 call sites**, 8 here + 4 in `order_disclosure.rb`. Shared; edit at the call site, never here | legacy |
| `app/models/concerns/order_zip.rb` | 214 | `json[:watermark] = watermark if watermark.present?` — why dropping the argument suffices | legacy |
| `app/controllers/orders_controller.rb` | 468–479 | `download_files` — the archiver's only endpoint. Renders `zip_file_data(params)` and nothing else, passing live `ActionController::Parameters` straight through (a fourth writer of `params[:watermark]`) | legacy |

## Filenames — the surviving disclosure signal

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/concerns/file_name.rb` | 15–27 | `compliance_suffix`. Branch order matters: `_3_marketing` for legacy/standard (16), `_2` for `mls_originals_only` **or any `UnalteredPhoto` or unaltered `Photo`** (18), `_1_digitally_altered` (20), `_1_virtually_staged` (22), else `_3_marketing` (25). An unaltered photo inside `mls_with_alters` gets `_2`, not `_3_marketing` | legacy |
| `app/models/concerns/file_name.rb` | 8 | Mutates `params[:size]` in place — one of three in-place writes on this chain | legacy |
| `app/models/concerns/file_name.rb` | 29–43 | `base_file_name_for_download`; index from `display_position + 1`, zero-padded to 3. Extension hardcoded `.jpg` | legacy |
| `app/models/unaltered_photo.rb` | 20 | `delegate :display_position, to: :photo` — why a pair shares its `NNN_` index and differs only in the suffix | legacy |
| `app/models/photo.rb` | 71 | `has_one :unaltered_photo, -> { active }` — **the known gap.** A soft-deleted counterpart silently drops the `_2` while the `_1_*` still ships | legacy; pinned as KNOWN GAP |

## Watermark producers — three unrelated meanings

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `app/models/photo.rb` | 24–32 | `DIGITALLY_ALTERED_WATERMARK` / `VIRTUALLY_STAGED_WATERMARK` → `watermarks/*-cropped.png`. Live consumer is `photos_controller`, **not** the zip | legacy |
| `app/models/photo.rb` | 34–46 | `FRONT_END_*` variants → `watermarks/*.png` (uncropped, `wRatio`/`hRatio`). Used by `listing.rb:737,740` | legacy |
| `app/models/photo.rb` | 406–412 | `alteration_types` frozen hash carrying `watermark:` and `watermark_label:`. Describes the single-download path only since ADR 003 | legacy |
| `app/models/photo.rb` | 463–471 | `requires_watermark?` (**zero callers**) and `watermark_label` (serialized nowhere) | legacy |
| `app/controllers/photos_controller.rb` | 137, 144–150 | Single-photo download — **still burns pixels** via `insgt-resource-downloader`. The known divergence from the zip | legacy |
| `app/models/concerns/order_disclosure.rb` | 20, 50, 55 | Disclosure gallery: sets `watermark: true` and passes the constants. Untouched by the slice | legacy |
| `lib/image_handler.rb` | 6 | `ImageHandler::WATERMARK` → `watermark-3.png`. **Unrelated** — the legacy branding mark, driven by `Order.jailed_to_watermarks?` (`order.rb:990`) via `lib/cloudfare.rb:20-28` | legacy |
| `db/schema.rb` | 884–887 | Paperclip watermark attachment columns. **Unrelated** again | legacy |

## The archiver

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `functions/insgt-order-archiver/handler.js` | 19–26 | `SIZES`. `print` and `original` are both 3360×2240 | legacy |
| `functions/insgt-order-archiver/handler.js` | 116–119 | `archive.append(fileStream, { name: file.filename })` — the **only** write into the zip. No manifest, no README. This is why `alterationType` never reaches the agent | legacy |
| `functions/insgt-order-archiver/handler.js` | 236 | `if (file.watermark)` — the sole composite gate. No fallback: `grep -n "alterationType\|alteration" handler.js` → exit 1 | legacy |
| `functions/insgt-order-archiver/handler.js` | 249–252 | Replaces the stale `366d001` print-experiment comment. Records that the branch is now unreachable | **watermark slice** |
| `functions/insgt-order-archiver/handler.js` | 272–304 | `getResizeStream` — resize (285–290), `.withMetadata({ exif })` injecting `Copyright`/`Artist` (291), composite (294–301), `.toFormat` (303). Restoring the print bypass would skip **all** of these, not just the composite | legacy |

Manifest fields the archiver actually reads: `file.filename`, `file.s3Bucket`, `file.s3Key`,
`file.watermark`. Nothing else. `grep -o "file\.[A-Za-z0-9_]*" handler.js | sort -u` confirms.

## Specs

| File | Line | What it is | Slice / commit |
| :-- | :-- | :-- | :-- |
| `spec/models/order_zip_spec.rb` | 1–273 | 19 examples. The entire coverage of this area — there was none before | **watermark slice** |
| `spec/models/order_zip_spec.rb` | 36–69 | No watermark pointer on any `mls_with_alters` entry (red before the slice) | watermark slice |
| `spec/models/order_zip_spec.rb` | 71–90 | The `_1_*` suffix survives — the `order_zip.rb:187` guard | watermark slice |
| `spec/models/order_zip_spec.rb` | 92–122 | The `_2` counterpart and its shared index — the pairing contract | watermark slice |
| `spec/models/order_zip_spec.rb` | 168–180, 182–198 | Two KNOWN GAP examples: an altered photo ships `_1_*` unpaired when the counterpart never existed, and when it was soft-deleted | watermark slice |
| `spec/models/order_zip_spec.rb` | 243–271 | Disclosure gallery keeps its watermark — locks the shared-method contract | watermark slice |
| `spec/factories/photos.rb` | 11, 21–29 | `alteration_type` default and the `:altered` / `:virtually_staged` traits | watermark slice |
| `spec/factories/orders.rb` | 8–13 | `:compliant` trait. No default — legacy stays the factory default, matching production | watermark slice |
| `spec/factories/unaltered_photos.rb` | 1–17 | New. `status_type` active is load-bearing (the `has_one` is scoped) | watermark slice |

Spec traps, all hit during implementation: `create(:photo)` needs an explicit `order:`
(`photo.rb:475-476` dereferences `order.listing` unguarded); two photos in one example must share
one `property` (the states/countries factories use fixed names behind uniqueness validations);
`CrudAttribution` forces `status_type` active on create (`crud_attribution.rb:9, 50-52`), so a
soft-deleted row can only be reached by a later write; the params hash is mutated in place at
`order_zip.rb:169, 187` and `file_name.rb:8`, so every example needs a fresh unfrozen hash.

## Repo documentation

| File | What it is |
| :-- | :-- |
| `insgt-platform/docs/decisions/003-mls-complete-watermark-removal.md` | The decision, its cost, and the two open items it accepts |
| `insgt-platform/docs/compliance/ab-723.md` | Requirements. `:33-37` the legal obligation, `:102` CRMLS, `:103` SFAR, `:106` our role |
| `insgt-platform/.claude/skills/ab-723-compliance/SKILL.md` | `## insgt-api specifics` — the three delivery paths and the two traps |
| `functions/insgt-site-sls` | Public copy. 13 lines across 5 files said "watermark"; now zero |

## Branch and deploy state

`insgt-api` and `insgt-site-sls` both sit on a branch named `feat/digital-watermarks`; the
`insgt-api` one was a stale placeholder, 0 commits ahead of `master`. `insgt-order-archiver` is on
`feat/selective-photos` at `64d7be9`, **not** `master` — anything verified against that working
tree is not verified against the deployed Lambda. The archiver change is comment-and-whitespace
only, so no Lambda deploy is required. `insgt-site-sls` needs a `site-data.json` drop into the data
bucket to regenerate HTML and invalidate CloudFront — deploying the Lambda alone does not
republish the site.
