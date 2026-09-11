---
name: ab-723-compliance
description: Use this skill whenever work touches photo alteration labeling, watermarks, alteration types, unaltered counterparts, download or export bundle composition, disclosure galleries, or MLS delivery in any InsightPhotos repo (insgt-api, insgt-ops, insgt-app). Invoke when adding or changing a download option, a photo delivery path, a photo serializer or model field, a processing or export pipeline step, or any UI that presents photos to an agent or a buyer. Also invoke when writing customer-facing copy about disclosure or compliance. AB 723 is a California legal obligation and a competitive differentiator — treat it as a constraint on the design, not a detail to add later.
---

# AB 723 — Digital Alteration Disclosure

California law requires disclosure when listing photos have been digitally altered. Insight Photos delivers a compliant download set on every shoot at no extra cost, and markets this as a differentiator.

Business requirements and the customer-facing promise live in `insgt-platform/docs/compliance/ab-723.md`. That file is outside the individual app repos — if it isn't readable from the current session, work from this skill and say so rather than guessing at the requirement.

**The standing constraint:** every delivery path that can emit an altered photo must be able to say so. If a change would produce a photo file, a bundle, or a gallery where an alteration is present but unlabeled, stop and raise it rather than shipping the simplification.

Alterations currently in scope: sky replacement, grass repair, pool bluing, virtual staging, virtual twilight, furniture removal.

---

## Never do these

- Add a download, export, or share path that bypasses the labeled bundle set
- Drop, default, or make optional a `watermark` flag or `watermark_label` without an explicit decision (ADR 003 is what "an explicit decision" looks like — recorded, with what it costs)
- Present an altered photo to a buyer-facing surface without its disclosure route
- Rename `CompolianceModeIds` in passing (see below)
- Key compliance reporting off an order type's category rather than its `key` (see below)
- Describe altered images as "enhancements" in customer-facing copy — they are disclosed alterations

---

## Compliance mode

Per-order, two modes: `legacy` (id 1) and `compliant` (id 2), via `ComplianceModes`.

The enum is **misspelled** `CompolianceModeIds` in the insgt-ops model layer. It is referenced across repos. Renaming requires a coordinated multi-repo change — never do it as part of unrelated work.

## Compliance reporting

Any report, query, or metric counting AB 723 reprocess work must match on
**`order_type.key == 'reprocess_disclosure_compliance'`** (id 207). Never match on the order
type's category.

`key` is an identity column. `OrderType` guards it with a `key_must_not_change` validation, so no
ordinary save can move it — a deliberate rename needs a migration or something else that skips
validations. A category is an editable classification with no such guard: this row has already been
read as both `internal` (a maintenance reprocess) and `property` (paid work against a listing), and
neither reading is wrong. A report keyed off category silently changes what it counts the next time
someone reclassifies. A report keyed off `key` does not.

The same holds for `name`, which is a display string and free to change independently — id 32 was
created as "Stay at home" and is now "Quick Pics".

## Alteration types

| id | Type | `watermark:` flag |
|---|---|---|
| 1 | `None - Unaltered` | false |
| 2 | `Digitally Altered` | true |
| 3 | `Virtually Staged` | true |

Each type carries a `watermark: true/false` and a `watermark_label` string.

**The flag no longer means "a watermark is burned into the delivered file."** Since 2026-09-11 the
`mls_with_alters` zip ships altered photos with no overlay at all — see
`insgt-platform/docs/decisions/003-mls-complete-watermark-removal.md`. The flag now describes the
single-photo download path only. Read it as "this type is disclosure-bearing", not as a rendering
instruction. An altered photo has an unaltered counterpart; the pair is the unit, not the individual file.

## Download bundles

| Bundle | Contents | Requires compliance mode |
|---|---|---|
| `mls_with_alters` | All photos with alteration labels | yes |
| `mls_originals_only` | Edited photos only, no alterations | yes |
| `standard` | All photos, no labels | no |

A new bundle type is a compliance decision, not a feature flag. The customer-facing set is MLS Complete, MLS Simple, Marketing Photos, and the free disclosure gallery.

## Disclosure gallery

QR code pointing at the disclosure gallery URL, surfaced only when the order's compliance mode is `compliant`.

---

## insgt-ops specifics

- Mode toggle: `orders/compliance/order-compliance.component.ts`, dispatches `orderActions.UpdateAttribute`
- Unaltered pair management: `unaltered-photos/crud/unaltered-photo-crud.dialog.ts` — shows altered alongside unaltered, handles upload via `UnalteredPhotoUploadComponent`, downloads both versions, deletion behind a confirmation dialog. This is also the repo's typed-form exemplar (`FormGroup<T>` / `FormControl<T>`) — copy from it rather than the `UntypedFormGroup` files.
- Bundles: `orders/download/order-download.component.ts`. Zip generation polls every 10 seconds, max 10 attempts before timeout.
- QR: `disclosure-galleries/qr-code/`

## insgt-api specifics

**insgt-api never touches image bytes.** There is no Ruby image library in the repo —
`grep -niE "mini_magick|image_processing|ruby-vips|rmagick|paperclip|carrierwave|shrine" Gemfile Gemfile.lock`
returns nothing. Rails emits a JSON manifest; external Lambdas composite. So "the labeling
originates here" means *the manifest and the filename*, never a pixel. If a task sounds like
"change how the watermark looks", the work is in a `functions/` repo, not this one.

**Where `watermark_label` lives.** `Photo.alteration_types` (`app/models/photo.rb:406-412`) is a
frozen hash carrying `watermark:` and `watermark_label:` per type; `Photo#watermark_label` and
`Photo#requires_watermark?` read it (`:463-471`). Neither is a delivery mechanism —
`requires_watermark?` currently has **no callers**, and `watermark_label` is not serialized into any
download path. The label that actually reaches an agent is the **filename suffix** built by
`FileName.compliance_suffix` (`app/models/concerns/file_name.rb:15-27`):
`_1_digitally_altered` / `_1_virtually_staged` for altered photos, `_2` for the unaltered
counterpart, `_3_marketing` for unlabeled.

**The three delivery paths, and which burns pixels:**

| Path | Producer | Consumer | Burns a watermark? |
| :--- | :--- | :--- | :--- |
| Zip bundles | `order_zip.rb:165-204` → `GET /orders/:id/download_files` | `insgt-order-archiver` | **no**, since ADR 003 |
| Single photo download | `photos_controller.rb:144-150` | `insgt-resource-downloader` | **yes** |
| Disclosure gallery JSON | `order_disclosure.rb:41-57` | `insgt-disclosure-gallery` | yes, but client-side — the API's `watermark` key is ignored and the overlay is derived from `alterationType` against the gallery's own constants |

That middle row is a known divergence: the same altered photo is watermarked when downloaded singly
and unwatermarked inside MLS Complete. Do not "fix" one to match the other without reopening ADR 003.

**Two traps when editing the zip path:**

1. **`download_file_json` is shared.** It has 12 call sites — 8 in `order_zip.rb`, 4 in
   `order_disclosure.rb`. Changing the method itself, its `watermark = nil` default, or the
   `Photo::*_WATERMARK` constants reaches the disclosure gallery and the single-download path too.
   Edit at the specific call site.
2. **`params[:watermark] = true` (`order_zip.rb:187`) is not about watermarks.** It is a
   shared-hash mutation read by `FileName.compliance_suffix` to pick the `_1_*` suffix. Deleting it
   — the intuitive "turn off the watermark" edit — silently renames every altered file in the
   bundle to `_3_marketing`, stripping the bundle's only remaining disclosure signal. It has four
   writers that reach `compliance_suffix`: `order_zip.rb:187`, `order_disclosure.rb:20`,
   `photos_controller.rb:137`, and the HTTP request itself via `orders_controller.rb:476`.

`spec/models/order_zip_spec.rb` pins all of the above, including the deliberate-break cases.

insgt-app and insgt-ops expose the download surfaces.

<!-- FILL IN: insgt-app — which agent-facing download surfaces expose which bundles. -->

---

## Copy rules

**Use disclosure-focused terminology, not "original" / "edited".** The pairing is not original-vs-edited, it is altered-vs-unaltered, and the labels should say what the agent needs to know:

- Unaltered photos → "No Disclosures Required"
- Altered photos with counterparts → "MLS Ready — Disclosures Included"
- Hide compliance UI entirely when an order has no altered photos (progressive disclosure)

The one deliberate exception is **consumer-facing** surfaces. insgt-disclosure-gallery labels unaltered photos "Original Photo" on purpose — a buyer reading a disclosure page needs plain language, not the agent-facing compliance vocabulary. Keep the agent-facing terminology everywhere else.

AB 723 downloads are included free with every shoot. Permitted framing: the agent gets the files they need for MLS use, marketing, and disclosure requirements.

Do not write "we guarantee full legal compliance." Write that Insight Photos provides AB 723-compliant download options designed to support California digital alteration disclosure requirements. The compliant download set is a marketing asset most competitors handle badly — treat it that way, not as a compliance tax.