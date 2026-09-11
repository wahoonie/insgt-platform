# Turn off watermark injection in `mls_with_alters` zip downloads

> **v2 — amended 2026-09-11, after implementation.** The authority on this work is now
> [`docs/decisions/003-mls-complete-watermark-removal.md`](../decisions/003-mls-complete-watermark-removal.md);
> where the two disagree, the ADR wins. The `file:line` map is
> [`docs/architecture/watermark-injection-codebase-notes.md`](../architecture/watermark-injection-codebase-notes.md).
>
> **Change log**
> - **v2, 2026-09-11** — Signal count corrected from four to two (below): `alterationType` never
>   reaches the agent, and the disclosure gallery is a separate endpoint rather than a bundle
>   signal. Scope widened at the planning gate to include the archiver comment cleanup and the
>   insgt-site-sls copy correction. The archiver's print branch was **not** restored — see the ADR.
>   Every `file:line` below is **pre-slice**: the implementation added a 7-line comment at
>   `order_zip.rb:179-185`, so `order_zip.rb` citations after that point are 7 lower than reality,
>   and 10 lines were inserted into `docs/compliance/ab-723.md`. The notes file is named
>   `watermark-injection-codebase-notes.md`, not `zip-watermark-codebase-notes.md` as §Write-back
>   proposed, to match the `<doc-name>-codebase-notes.md` convention.
> - **v1, 2026-09-10** — Initial plan.

## Context

The `mls_with_alters` bundle ("MLS Complete") currently delivers altered photos with a watermark
PNG composited into the bottom-left corner. Agents receive files they cannot use as-is. The goal is
to stop the overlay being applied to images inside that zip, while the bundle continues to declare
which photos are altered.

Scope is **insgt-api only**. No change to `insgt-order-archiver`, `insgt-ops`, `insgt-app`, or any
other repo.

### The compliance decision (explicit, per `ab-723-compliance`)

Dropping a watermark flag is on that skill's *Never do these* list **absent an explicit decision**.
The decision is made here and recorded: **drop the burned overlay, keep every other disclosure
signal.**

The rationale is that the overlay was never the disclosure mechanism. AB 723 (BPC § 10140.8) asks
for a conspicuous statement near the published image plus access to the unaltered original
(`docs/compliance/ab-723.md:33-37`); the burned pixel is one MLS's *upload* behaviour, not a legal
requirement — the doc's only use of the word is a note about SFAR at `docs/compliance/ab-723.md:94`.
After this change the bundle still says an image is altered — **in two ways, not the four this plan
originally claimed** (corrected in v2; the ADR carries the authoritative table):

| Signal | Where | Reaches the agent? |
| :--- | :--- | :--- |
| `_1_digitally_altered` / `_1_virtually_staged` filename suffix | `file_name.rb:20-23` | **yes** |
| Unaltered `_2` counterpart shipped alongside | `order_zip.rb:184,187` (now `:191,194`) | **yes** |
| ~~`alterationType` field in the manifest~~ | `order_zip.rb:205` (now `:212`) | **no** — the archiver never reads it |
| ~~Disclosure gallery + QR~~ | `order_disclosure.rb` | separate endpoint, not a bundle signal |

The skill's standing constraint — a bundle that emits an altered photo must be able to say so — is
still met by the two surviving signals, and both are therefore treated as a compliance contract.
But note what the corrected count exposes and this plan did not: **no signal we ship survives into
the agent's published listing.** See the ADR's "What this costs, stated plainly".

---

## What the survey established

**insgt-api never touches image bytes.** There is no Ruby image library in the repo at all
(`grep -niE "mini_magick|image_processing|ruby-vips|rmagick|paperclip|carrierwave|shrine" Gemfile Gemfile.lock`
→ no output, exit 1). Rails only emits a JSON manifest; an external Lambda composites.

Chain: `POST orders/:id/download_zip_url` → `Order#zip_file_status`
([order_zip.rb:48-62](../../apps/insgt-api/app/models/concerns/order_zip.rb#L48-L62))
→ `ZipRefreshWorker` → `Order#refresh_zip_file` → HTTPS POST to `ENV['ZIP_ORDER_ENDPOINT']` →
the Lambda GETs back `orders/:token/download_files` → `Order#zip_file_data` returns
`{version, filename, files[]}` → Lambda streams each S3 object through `sharp` and uploads the zip.

The burn site is `functions/insgt-order-archiver/handler.js:236` `if (file.watermark) {` →
`:297-304` `pipeline.composite([{ input: watermarkBuffer, gravity: 'southwest' }])`. It is gated
**solely** on the presence of that key — `grep -n "alterationType\|alteration" handler.js` returns
nothing, so there is no fallback that would re-derive the watermark from the alteration type. Omit
the key and the composite does not happen.

The only branch that sets it for zips is
[order_zip.rb:179-191](../../apps/insgt-api/app/models/concerns/order_zip.rb#L179-L191).
`mls_with_alters` appears in exactly three lines repo-wide, all in `order_zip.rb`: the
`ALLOWED_BUNDLES` constant (`:6`), the filename-suffix branch (`:145`), and this photo-selection
branch (`:179`). Nothing in specs, seeds, docs, views, or serializers.

### Two traps the survey found

**Trap 1 — `download_file_json` is shared with the disclosure gallery.**
It has 9 call sites: 7 in `order_zip.rb`, and 2 in
[order_disclosure.rb:50,55](../../apps/insgt-api/app/models/concerns/order_disclosure.rb#L50-L56).
Changing `download_file_json` itself, or its `watermark = nil` default, or the `Photo::*_WATERMARK`
constants, **would strip watermarks from the disclosure gallery too**. The edit must be at the two
zip call sites only.

**Trap 2 — `params[:watermark] = true` at `order_zip.rb:180` also drives filenames.**
It is a shared-hash mutation read by `FileName.compliance_suffix`
([file_name.rb:20-23](../../apps/insgt-api/app/models/concerns/file_name.rb#L20-L23)).
Deleting that line — the intuitive "turn off the watermark" edit — silently renames every altered
file in the bundle from `_1_digitally_altered` to `_3_marketing`, a second unintended contract
change. **The line stays.**

---

## The change

One edit, two lines, in
[app/models/concerns/order_zip.rb](../../apps/insgt-api/app/models/concerns/order_zip.rb#L179-L191):
drop the third positional argument at `:183` and `:186`. `download_file_json` already defaults
`watermark = nil` (`:199`) and only emits the key when present
(`:207` `json[:watermark] = watermark if watermark.present?`), so no other change is needed.

```ruby
elsif compliant_delivery? && params[:bundle] == 'mls_with_alters'
  params[:watermark] = true  # KEPT — drives the _1_* compliance filename suffix
  all_photos.each do |photo|
    if photo.altered?
      download_photos << download_file_json(photo, params)
      download_photos << download_file_json(photo.unaltered_photo, params) if photo.unaltered_photo.present?
    elsif photo.virtually_staged?
      download_photos << download_file_json(photo, params)
      ...
```

Add a comment above the branch recording *why* the watermark pointer is deliberately absent, so the
next reader does not "fix" it back. The `Photo::DIGITALLY_ALTERED_WATERMARK` /
`VIRTUALLY_STAGED_WATERMARK` constants stay — the disclosure gallery and `photos_controller` still
use them.

---

## Test work

There is **zero** existing coverage:
`grep -rniE "watermark|alteration|mls_with_alters|unaltered|order_zip|zip_file" spec/`
returns nothing, exit 1. The factories cannot express the scenario either.

### Factory gaps to fill

Per `insgt-api/CLAUDE.md`, these are the "nullable column whose NULL means something" vs "required
column" recipes, and they point opposite ways:

- `spec/factories/photos.rb` — add `alteration_type` defaulting to `1` (matches
  `db/schema.rb:891`, `default: 1, null: false`). Deliberately **do not** set `s3_content_type`:
  leaving it blank short-circuits `after_create :sync_s3_version`
  ([s3_image_handler.rb:164-166](../../apps/insgt-api/app/models/concerns/s3_image_handler.rb#L164-L166))
  so no S3 HEAD is issued. Add `:altered` and `:virtually_staged` traits.
- `spec/factories/orders.rb` — add a `:compliant` trait setting `compliance_mode: 2`. No default;
  legacy (1) stays the factory default, matching production.
- New `spec/factories/unaltered_photos.rb` — mirror the existing factory style.

### `spec/models/order_zip_spec.rb`

Boundary cases by name, not just the happy path:

1. `mls_with_alters` + altered photo → manifest entry has **no** `:watermark` key.
2. `mls_with_alters` + virtually staged photo → **no** `:watermark` key.
3. `mls_with_alters` → filename still ends `_1_digitally_altered` / `_1_virtually_staged`
   (guards Trap 2).
4. `mls_with_alters` → the unaltered counterpart is still emitted, still suffixed `_2`
   (guards the disclosure pairing).
5. `mls_with_alters` + unaltered-only photo → unchanged.
6. `mls_originals_only` → unchanged.
7. `standard` → unchanged.
8. **Legacy order requesting `mls_with_alters`** → falls to the `else` branch (`:192`), unchanged.
9. Altered photo with **no** unaltered counterpart → still emitted, no crash.
10. `photos_for_disclosure_gallery` → **still carries** `:watermark` (guards Trap 1). This is the
    single most important example in the file.

`download_file_json` calls `photo.s3_bucket`, which constructs an `Aws::S3::Resource`
([lib/image_handler.rb:24-38](../../apps/insgt-api/lib/image_handler.rb#L24-L38)) — this raises
`Aws::Errors::MissingRegionError` at construction if `S3_REGION` is unset, and attempts an IMDS
fetch to `169.254.169.254` (blocking until timeout) if credentials are unset. Confirm `S3_REGION`
is present in `.env` before running, and export `AWS_EC2_METADATA_DISABLED=1`. No S3 request is
made; only client construction.

### Deliberate break (required evidence)

Restore `Photo::DIGITALLY_ALTERED_WATERMARK` as the third argument, confirm examples 1 and 3 go
red, restore, paste the red output. Separately flip the disclosure-gallery call site and confirm
example 10 goes red.

---

## Local end-to-end verification

The chosen depth is **build a real zip locally and look at the pixels**. This is done without
modifying any repo: the driver lives in the scratchpad and the archiver repo is only read.

1. **Dump two real manifests** from the dev DB (which holds a production restore) with
   `rails runner`, for a compliant order that has altered photos with counterparts:
   - `order.zip_file_data(size: 'web', bundle: 'mls_with_alters')` → `after.json`
   - the same, with the watermark pointer re-injected by hand → `before.json`

   Pick the order by querying for `compliance_mode = 2` with photos where `alteration_type IN (2,3)`
   and an `unaltered_photo` present. Verify `sorted_photos(params)` accepts a plain symbol-keyed
   hash — it is normally fed `ActionController::Parameters`.

2. **Build both zips** with a Node driver script in the scratchpad. It replicates the pipeline at
   `handler.js:275-307` verbatim (`sharp().resize(...).withMetadata({exif})`, plus
   `.composite([...])` only when `file.watermark` is present) and pipes through `archiver`.
   `require` resolves via `NODE_PATH=/workspace/functions/insgt-order-archiver/node_modules` —
   `sharp` 0.34.5 loads there on arm64 and `@img` ships both arm64 and x64 libvips binaries, so no
   install is needed and the archiver repo is left untouched.

3. **Compare.** `before.zip` images carry the overlay in the bottom-left; `after.zip` images do
   not; filenames are byte-identical between the two. That side-by-side *is* the red/green evidence
   for the pixel-level behaviour, since neither zip goes through the code under test twice.

Reads source objects from the real `insgt` bucket (`GetObject` only) and writes both zips to the
scratchpad. **Nothing is written to S3** — this deliberately avoids the `insgt-zip` bucket, which
the archiver's dev and prod stages share with identical key names
(`functions/insgt-order-archiver/serverless.yml`), so a careless dev run would overwrite a
production zip.

Requires AWS credentials with read on `insgt`, and `node` (v22 present).

---

## Commit sequence

One concern per commit, per `git-commit-messages`, for bisect integrity:

1. `test: add alteration and compliance factory traits for zip bundle specs`
2. `test: cover mls_with_alters manifest and disclosure gallery watermark contract` — red against
   current code for examples 1–2, green for the rest.
3. `fix: stop injecting watermarks into mls_with_alters zip downloads` — the two-line change;
   examples 1–2 flip green.

Branch off `master`. Note the current branch `feat/digital-watermarks` is a stale placeholder with
no commits ahead of `master`; do not reuse it. **No commits will be made** — changes are left in
the working tree for review.

---

## Known limitation, accepted

The zip cache key is `MD5(filename + s3Version)`
([order_zip.rb:87](../../apps/insgt-api/app/models/concerns/order_zip.rb#L87))
and does not include the watermark. Filenames are unchanged by this work, so the digest is
byte-identical and **both** short-circuits — Rails at `:39-43` and the Lambda at `handler.js:61,383`
— will keep serving already-built, watermark-burned zips.

The decision is to **do nothing**: existing `mls_with_alters` zips stay watermarked until a photo
change bumps `s3Version` and invalidates them naturally. Consequence to expect: for orders whose
zip is already built, the change will appear not to work. If a specific order needs to be flushed
sooner, `order.refresh_zip_files(size, 'mls_with_alters')` deletes and rebuilds it
(`order_zip.rb:64-67`). The local verification above bypasses both caches entirely, so it is
unaffected.

Note also that every *automatic* invalidation in the codebase (`photo.rb:140-141`,
`order_event.rb:41-42,56-57`, `photo_copy_worker.rb:38-39`) calls `refresh_zip_files` with a size
only, defaulting `bundle` to `'standard'` — so the `mls_with_alters` zip is never automatically
purged by any of them.

---

## Risks

- **Silent leak into the disclosure gallery** if the edit drifts to `download_file_json` or the
  constants. Example 10 is the guard.
- **Silent filename change** if `params[:watermark] = true` is removed. Example 3 is the guard.
- The `ALLOWED_BUNDLES` list is duplicated in Rails (`order_zip.rb:6`) and the Lambda
  (`handler.js:28-30`). Not touched here, but worth knowing it must be kept in sync.
- `insgt-ops` polls zip status every 10s, max 10 attempts. Unaffected — no timing or contract
  change on the status endpoint.

## Write-back

Per `slice-implementation`, the repo must remember this:

- Record the compliance decision above — that the overlay was dropped deliberately and which four
  signals replace it — in `docs/compliance/ab-723.md`, since no ADR or design doc for watermarking
  exists (`docs/decisions/` has none).
- Fill the `<!-- FILL IN: insgt-api -->` gap in `.claude/skills/ab-723-compliance/SKILL.md` with the
  manifest-not-pixels architecture and the two traps.
- Create `docs/architecture/watermark-injection-codebase-notes.md` (renamed in v2 to match the
  `<doc-name>-codebase-notes.md` convention) with the `file:line` map from this survey.

These are separate commits and are part of the slice.

## Verification checklist

- [ ] `bundle exec rspec spec/models/order_zip_spec.rb` — green, with red output pasted for both
      deliberate breaks
- [ ] `bundle exec rspec` — full suite, no pre-existing example changed
- [ ] `rails_best_practices -e "db/migrate,vendor" .` on the touched files
- [ ] `before.zip` / `after.zip` built locally and images compared visually
- [ ] `grep -rn "watermark" app/models/concerns/order_disclosure.rb` — disclosure path unchanged
