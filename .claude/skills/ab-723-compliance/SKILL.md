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
- Drop, default, or make optional a `watermark` flag or `watermark_label` without an explicit decision
- Present an altered photo to a buyer-facing surface without its disclosure route
- Rename `CompolianceModeIds` in passing (see below)
- Describe altered images as "enhancements" in customer-facing copy — they are disclosed alterations

---

## Compliance mode

Per-order, two modes: `legacy` (id 1) and `compliant` (id 2), via `ComplianceModes`.

The enum is **misspelled** `CompolianceModeIds` in the insgt-ops model layer. It is referenced across repos. Renaming requires a coordinated multi-repo change — never do it as part of unrelated work.

## Alteration types

| id | Type | Watermark |
|---|---|---|
| 1 | `None - Unaltered` | no |
| 2 | `Digitally Altered` | yes |
| 3 | `Virtually Staged` | yes |

Each type carries a `watermark: true/false` and a `watermark_label` string. An altered photo has an unaltered counterpart; the pair is the unit, not the individual file.

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

<!-- FILL IN: insgt-api — serializers, processing pipeline stages, and the S3 delivery paths
     that carry watermark_label. Add here so the skill covers the repo where the labeling
     actually originates, not just the repo where it's displayed. -->

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