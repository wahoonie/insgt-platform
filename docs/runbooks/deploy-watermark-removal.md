# Runbook: MLS Complete Watermark Removal Deploy

**Last updated:** 2026-09-11
**Repos:** insgt-ops, insgt-app, insgt-api, functions/insgt-site-sls
**Estimated duration:** ~50 min (four repos, four separate merges — no migration)
**Status:** Draft

## Summary

Drops the burned watermark overlay from the **MLS Complete** (`mls_with_alters`) zip bundle, so agents
receive altered photos they can upload to the MLS as-is. The overlay was never what AB 723 asks for —
BPC § 10140.8 asks for a conspicuous statement near the published image and a link to the unaltered
original, not a mark in the pixels — and SFAR adds its own watermark on upload, so a pre-watermarked
file arrived at those agents double-marked. See `docs/decisions/003-mls-complete-watermark-removal.md`,
which is the authority on this work; `docs/plans/watermark-injection.md` is the superseded plan.

The API change is two lines: the `mls_with_alters` branch of `order_zip.rb` stops passing
`Photo::DIGITALLY_ALTERED_WATERMARK` / `VIRTUALLY_STAGED_WATERMARK` as the third argument to
`download_file_json`. The archiver composites only `if (file.watermark)`, so omitting the key is the
whole mechanism.

**Two signals now carry the disclosure in that bundle, and both are a compliance contract, not an
incidental artifact:** the `_1_digitally_altered` / `_1_virtually_staged` filename suffix built by
`FileName.compliance_suffix`, and the paired `_2` unaltered counterpart. Removing either one reopens
ADR 003.

**What this deploy costs, stated plainly:** the overlay was the only disclosure signal that travelled
with the image *bytes*. Filenames do not survive MLS ingest, and the `_2` file is a separate upload.
After this change no signal we ship survives into the agent's published listing — compliance at the
point of publication rests entirely on the agent's own action in their MLS interface. What makes that
workable is that the product now *tells them to do it*: the rewritten download copy in insgt-ops and
insgt-app instructs the agent to label the photo "Digitally Altered," "Virtually Staged," or equivalent
in the MLS photo-description field. **That instruction is the disclosure mechanism this decision hands
off to**, which is why it governs the deploy order below.

**Also riding along:** insgt-ops merges the `docs/plans/order-download.md` port — the separate web and
print download cards collapse into one card with an in-card size toggle, legacy orders now hide
compliance-only bundles rather than scrimming them, a null-URL guard replaces a navigation to
`.../undefined`, and bundle selection no longer resets on unrelated order saves. insgt-app rewrites the
bundle copy, adds a time-boxed announcement banner, and splits the unaltered-photo dialog into
"Download for MLS — No Watermark" and "Download with Watermark". insgt-site-sls corrects 13 places
where the marketing site advertised the watermark, including indexed FAQ JSON-LD.

**No migration, no backfill, no new env vars, no API contract change, no Sidekiq changes, and no
archiver deploy.** The `insgt-order-archiver` change is comment-only and is already on `main`
(`2db0f15`); its Lambda does not need to be redeployed.

## Deploy order: Angular first, then API — the house rule is inverted here

Every other multi-repo runbook here ships insgt-api first. **This one does not, and that is
deliberate.** There is no API contract change — every param the new UI sends (`size`, `bundle`)
already exists in production — so both orders work *functionally*. The reason to respect the order is
compliance, not breakage.

| Order | Effect |
|---|---|
| **Ops + App → API** (correct) | The MLS-labeling instruction is live before the first unwatermarked file ships. The window risk is cosmetic: the UI says "No watermarks" while zips built before the API deploy still carry them. |
| **API → Ops + App** (do not) | Unwatermarked files reach agents with no instruction to label them — precisely the silent handoff ADR 003 says would reopen the decision. |

Keep the window between step 2 and step 3 short regardless. insgt-site-sls ships last: it is marketing
copy describing behaviour that should already be live.

## Prerequisites

Four repos, four commits — **there is no atomic cross-repo commit.** Each branch is named
`feat/digital-watermarks`, each is exactly 1 commit ahead of its own base and 0 behind (verified
2026-09-11), so no rebase is needed anywhere. None has been pushed — all four are local-only with no
upstream.

- [ ] insgt-ops `feat/digital-watermarks` (`59fab85c`) merged `--no-ff` to `main`, pushed
- [ ] insgt-app `feat/digital-watermarks` (`09a0c7c`) merged `--no-ff` to `main`, pushed
- [ ] insgt-api `feat/digital-watermarks` (`9da0e77`) merged `--no-ff` to `master`, pushed to
      `origin` **and** `heroku` — Heroku only builds `master`, so merge rather than pushing the
      feature branch, or `heroku/master` drifts from the ref every future deploy diffs against
- [ ] functions/insgt-site-sls `feat/digital-watermarks` (`c9f5d61`) merged `--no-ff` to `main`, pushed
- [ ] insgt-api `bundle exec rspec` green — `spec/models/order_zip_spec.rb` is 19 examples and is the
      **entire** coverage of this area; there was none before this branch
- [ ] insgt-ops `ng lint` clean, `npm run build:prod` clean, `npm run test:e2e` green including the new
      `cypress/e2e/orders/order-download.cy.ts`
- [ ] insgt-app `npx ng lint insight-client-pwa` clean, `npm run build:prod` clean, version bumped from
      `4.9.0` in `package.json` **and in the environment files** — the app reads the version at build
      time, and the README's manual procedure lists this as step 1
- [ ] insgt-site-sls `npm run test:jsonld` and `npm run test:meta` green. The change edits FAQ JSON-LD
      `acceptedAnswer` blocks in `src/_data/faq.js` and
      `src/_includes/components/city-faq-schema.njk` — indexed structured data, so a malformed answer
      is a search-visible regression. **That repo's `CLAUDE.md` claims "No test suite exists" twice
      and is wrong**: `package.json` defines `test:html`, `test:spelling`, `test:jsonld`, `test:meta`
      and `test:links`, backed by real files under `test/`. Do not skip these on the strength of the
      CLAUDE.md.
- [ ] The platform docs are committed in `insgt-platform`. `order_zip.rb`'s new comment and the
      archiver's `handler.js:249-252` both cite `docs/decisions/003-mls-complete-watermark-removal.md`
      **by path**, and that file — along with `docs/plans/watermark-injection.md` and
      `docs/architecture/watermark-injection-codebase-notes.md` — is still untracked. Ship them or the
      code comments point at nothing.
- [ ] AWS credentials for the `insgt-apps` bucket, CloudFront `E2GJ3L3JH70697` (ops) and
      `EH3XX4N13ZUTM` (app); `AWS_PROFILE=insight` for the site-sls deploy
- [ ] No active deploy in flight

**On the ngrok hunk in the API commit:** `9da0e77` also changes `config/application.rb`, swapping one
local ngrok host for another (`a5b524f55267` → `edd7-173-66-117-174.ngrok-free.app`). It is unrelated
dev noise and it is shipping deliberately rather than being stripped. Harmless: `config.hosts` only
extends the Host-header allowlist, and no production path reads either value —
`insgtapi.herokuapp.com` is listed on the next line and is unaffected.

## Steps

### 1. Deploy insgt-ops

ops migrated to a script-driven, additive deploy on 2026-08-13. Use it:

```bash
npm run deploy:prod          # build:prod + release archive + additive upload + control-file invalidation
```

`apps/insgt-ops/DEPLOY.md` is the source of truth. Version is already `9.59.0`.

**Do not follow the S3/CloudFront steps in `deploy-listing-suppression.md:147-151`** — that runbook
describes the pre-migration timestamped-origin procedure, which no longer applies to ops. The origin
path is now permanently `/ops` and must never be moved.

**Verify:**

```bash
HOST=https://ops.insightphotos.net
curl -sI $HOST/ngsw.json | grep -i cache-control     # must be no-cache
curl -sI $HOST/orders | head -1                      # deep link returns the app
```

### 2. Deploy insgt-app

**insgt-app is *not* on the ops pipeline.** It is a sibling in the same bucket under its own prefix and
still uses the old timestamped-origin pattern (`DEPLOY.md`, "Sibling apps" — migration is deliberate
future work). Two apps deploying by two different mechanisms in the same window is the most likely
mistake in this runbook.

```bash
npx ng lint insight-client-pwa
npm run build:prod
```

Then, per `apps/insgt-app/README.md`:

1. Create a timestamped folder under `s3://insgt-apps/dashboard-pwa/`
2. Upload the contents of local `dist/` to it
3. Repoint the CloudFront origin to
   `insgt-apps.s3-website-us-west-1.amazonaws.com/dashboard-pwa/<timestamp>`
4. **Create a CloudFront invalidation `/*` on `EH3XX4N13ZUTM`**
5. Trim deploys older than ~10 back (housekeeping)

Record the previous timestamp before repointing — it is the rollback target, and nothing else writes
it down.

### 3. Deploy insgt-api

```bash
heroku pg:backups:capture --app insgtapi
git push heroku master
```

Watch the build to completion.

**No maintenance mode and no `db:migrate` — that is correct, not an omission.** Every neighbouring
runbook has both because those deploys carried schema changes. This one adds no columns and reads no
new ones, so there is no window in which new code meets an old schema. The only production file that
changes behaviour is `app/models/concerns/order_zip.rb`.

**Verify** the manifest no longer carries a watermark pointer, using any compliant order with an
altered photo:

```bash
heroku run rails runner 'd = Order.find(<id>).zip_file_data(size: "web", bundle: "mls_with_alters"); puts d[:files].map { |f| [f[:filename], f.key?(:watermark)] }.inspect' -a insgtapi
```

`zip_file_data` takes a params hash, not positional arguments. Every entry must report `false` for the
key check — `download_file_json` adds `:watermark` only `if watermark.present?`, so on success the key
is **absent entirely**, not set to `nil`. The altered entries must still end in `_1_digitally_altered`
or `_1_virtually_staged`, each with a `_2` counterpart alongside. A file that came back `_3_marketing`
means `params[:watermark] = true` was lost — see Rollback.

### 4. Flush cached MLS Complete zips — the change is inert until you do

**Already-built zips stay watermarked, and there is no automatic invalidation.** The cache key is
`MD5(filename + s3Version)` (`order_zip.rb:87`) and filenames are unchanged, so the digest is
byte-identical and both short-circuits — Rails and the Lambda — keep serving the old archive. All
eight automatic flush callers (`photo.rb:140-141`, `order_event.rb:41-42,56-57`,
`photo_copy_worker.rb:38-39`) pass a size only and default `bundle` to `'standard'`, so
`mls_with_alters` is **never** auto-invalidated. For an order already delivered, the change is inert
until a photo edit bumps `s3Version`.

ADR 003's recorded decision was to **do nothing in bulk**. Flush individual orders on request:

```bash
heroku run rails runner 'Order.find(<id>).refresh_zip_files("web", "mls_with_alters")' -a insgtapi
```

**Tell support before they hear it from an agent:** on an order whose bundle was already built, the
change will appear not to have worked. That is expected, and the command above fixes one order.

### 5. Deploy insgt-site-sls, then trigger a site export

```bash
./deploy.sh prod             # AWS_PROFILE=insight, npm ci, fresh cache-version.txt, sls deploy --stage prod
```

Use **Node 22** — `.nvmrc` says 20.14.0 and is wrong; `.tool-versions` and the `serverless.yml` runtime
(`nodejs22.x`) are right.

**Deploying the Lambda alone does not republish the site.** The rebuild fires on a `site-data.json`
`ObjectCreated` event in the `insgt-site-data` bucket — that is what runs Eleventy, uploads the new
HTML, moves the CloudFront origin and invalidates. So after the deploy, **trigger the site export from
insgt-ops**, the same mechanism as `deploy-listing-suppression.md:185-194`, and confirm the FAQ pages
actually changed. Until that export runs, the live site still says "watermarks".

### 6. Smoke test

Ops uses hash routing — URLs are `https://ops.insightphotos.net/#/orders/<id>`.

1. **insgt-ops, compliant order** → one download card with a web/print toggle (previously two cards).
   Flip the toggle: title and icon change, selection is preserved.
2. **insgt-ops, legacy order** → compliance-only bundles are absent, not greyed out. No caret, no scrim
   text.
3. **insgt-ops, selection persistence** → make an unrelated edit to the order and save. The selected
   bundle must not reset. Changing compliance mode *should* reset it.
4. **insgt-app, compliant order with alterations** → the blue "Update:" banner reads *"MLS Complete" no
   longer adds disclosure watermarks to digitally altered photos.* Expand MLS Complete: the description
   ends in "No watermarks." and is followed by a **visibly styled amber callout** carrying the "For MLS
   upload:" instruction.
5. **Default bundle differs between the two apps, and this is deliberate.** insgt-ops lands a compliant
   order on **MLS Complete** (`order-download.component.ts:166`); insgt-app lands the agent on **MLS
   Simple** (`:132`). Staff triage from the complete bundle; agents are steered to the simpler one.
   `docs/plans/order-download.md` §5c asks for these to match and is **stale** — do not "fix" ops.
6. **Download a freshly-built MLS Complete zip** (an order whose bundle has not been built before, or
   one flushed in step 4). Altered photos carry **no overlay**, still end in `_1_digitally_altered` /
   `_1_virtually_staged`, and each has its `_2` counterpart in the archive.
7. **Single-photo download is still watermarked** — confirm, do not report as a bug. See Notes.
8. **www.insightphotos.net** — the FAQ, pricing and FSBO pages say "disclosure labeling", not
   "disclosure watermarks". Check the rendered page, not just the deploy log; the export in step 5 is
   what publishes it.

## Verification

- [ ] `zip_file_data` for `mls_with_alters` omits the `watermark` key on every entry, with `_1_*` and
      `_2` filenames intact
- [ ] A freshly-built MLS Complete zip contains no overlaid images
- [ ] insgt-ops on `9.59.0`, insgt-app on its bumped version, both serving from the new build
- [ ] insgt-app's MLS-upload callout renders as a styled alert, not plain text
- [ ] Marketing site FAQ JSON-LD validates in Google's Rich Results Test after the export
- [ ] Support told about the cached-zip behaviour in step 4
- [ ] No new Sentry errors in last 10 min

## Rollback

### Roll back together, or not at all

The four commits are one compliance decision split across repos. Reverting the API alone leaves both UIs
advertising a watermark removal that has not happened. Reverting the Angular apps alone leaves
unwatermarked files reaching agents with no instruction to label them — the exact condition ADR 003
says reopens the decision, and the worse of the two directions.

### insgt-ops

```bash
npm run rollback                    # lists releases with SHA and branch
npm run rollback -- <epoch>
```

Restores the four control files from the release archive. Not instant — clients pick it up on their
next update check, which today fires a refresh dialog.

### insgt-app

Repoint the CloudFront origin to the previous timestamped folder recorded in step 2, and re-invalidate
`/*` on `EH3XX4N13ZUTM`. The invalidation is not optional: `index.html` is not hashed.

### insgt-api

```bash
heroku rollback --app insgtapi
```

No migration to reverse. Note the correct `--app` form — several older runbooks here carry a `-app`
typo that fails.

### Do not "turn the watermark back on" by deleting the flag

`params[:watermark] = true` (`order_zip.rb:187`) is the intuitive thing to delete and it is the wrong
one. That flag never reaches the archiver — it is a shared-hash mutation read by
`FileName.compliance_suffix` to pick the suffix. Deleting it silently renames every altered file in the
bundle from `_1_digitally_altered` to `_3_marketing`, stripping one of the two remaining disclosure
signals while removing zero watermarks. The overlay is controlled solely by the third argument to
`download_file_json`; restoring it means restoring that argument at the two `mls_with_alters` call
sites, nothing else.

Any rollback also leaves the flushed zips from step 4 rebuilt without overlays until they are flushed
again.

## Notes

**insgt-ops renders the MLS-upload callout as unstyled text.** The ported copy at
`order-download.component.ts:110` uses `class="alert alert-warning"`, which is DaisyUI — and **DaisyUI
is not installed in insgt-ops**. It is absent from `package.json`, from `tailwind.config.js`, and from
`node_modules`; ops runs plain Tailwind 3, and the only `.alert` rule in the repo is scoped inside
`orders/invoice/invoice-template.component.css`. So the instruction will appear as plain unstyled text
inside the description. There is a pre-existing instance of the same mistake at
`features/users/pages/user-list/user-list-page.html:80`, which suggests this has happened before and
gone unnoticed.

This is cosmetic and internal — ops is the staff dashboard — and it does **not** affect the ADR 003
handoff, which runs through the agent-facing app. insgt-app does have DaisyUI (`^5.0.43`), so the
callout renders correctly there. Worth fixing in ops, either by styling it with the Tailwind utilities
ops actually has or by using the repo's own `_notice.css` pattern. Not a reason to hold the deploy.

**Individual photo downloads still burn a watermark.** `photos_controller.rb:144-150` →
`functions/insgt-resource-downloader` is untouched, so the same altered photo is watermarked when
downloaded singly from ops or the app, and unwatermarked inside the MLS Complete zip. Known, deliberate,
out of scope for this slice. insgt-app's unaltered-photo dialog now surfaces both paths explicitly
("Download for MLS — No Watermark" and "Download with Watermark"), so an agent can choose. Reconciling
the two paths needs its own decision — do not "fix" one to match the other without reopening ADR 003.

**Open compliance risk, accepted and pinned.** An altered photo can reach the bundle with no active
unaltered counterpart — never created, or soft-deleted, since `Photo#unaltered_photo` is scoped
`-> { active }` and ops offers counterpart deletion behind a confirm dialog. It then ships with the
`_1_*` suffix and no `_2`. This change makes the consequence worse: before, such a file at least carried
the burned overlay declaring it altered; now the suffix is all it has. An independent review graded this
a blocker on exactly that reasoning. It is pinned rather than fixed by two `KNOWN GAP` examples at
`spec/models/order_zip_spec.rb:168` and `:182`. Closing it needs its own slice and should be the next
one.

**Calendar item — 2026-10-23.** insgt-app's announcement banner is hard-coded to expire on that date
(`watermarkRemovalNoticeExpiresOn`, `order-download.component.ts:83`). On expiry, delete the constant,
`showWatermarkRemovalNotice`, its assignment in `ngOnInit`, and the notice block in the template. It
will stop rendering on its own; only the dead code needs removing.

**Constants that stay.** `Photo::DIGITALLY_ALTERED_WATERMARK`, `Photo::VIRTUALLY_STAGED_WATERMARK`, the
`watermark: true` entries in `Photo.alteration_types`, and `Photo#requires_watermark?` (zero callers)
are all still referenced by the single-photo and disclosure-gallery paths or are deliberate dead code.
Do not clean them up as part of this.

## Deploy log

Paste migration timings, flush counts, and any warnings here after the run, per
`docs/runbooks/README.md`. Update the `**Status:**` field above to `Deployed <date> by <name>`.
