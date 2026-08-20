# Runbook: Listing Suppression Deploy

**Last updated:** 2026-08-04
**Repo:** insgt-api + insgt-ops
**Estimated duration:** ~25 min
**Status:** Deployed 2026-08-05

## Summary

Adds a **confidentiality kill-switch** for a listing. A seller signs an NDA, or asks to go off-market
after the media is already delivered — ops needs one control that takes the listing's public surfaces
down without unwinding the order.

`listings.suppressed_at` is a **backward revocation**, deliberately distinct from `listings.published`,
which is a **forward delivery-readiness gate** flipped once when media work is signed off. They are
orthogonal and compose with AND, encoded once as `Listing.visible` (`published.unsuppressed`).

**What suppression takes down:**

- The virtual tour (`Listing.find_virtual` — the single chokepoint for both unauthenticated listing
  surfaces, `GET /listings/:token/virtual.json` and `GET /order_urls/:id/panorama.json`)
- The team's public listings page and the public site export
- Custom-domain routing — `Listing.custom_domain_exists?` answers `false`, so insgt-virtual-tour's
  `CustomDomainConstraint` renders not-found straight from the routing constraint
- Flyer generation — `FlyersController#create` and `#update` `render_bad`, because `ListingPdf`
  dereferences the `select_virtual` hash unguarded in ~25 places and would otherwise 500

**What it does NOT touch — say this out loud when ops asks:**

- Photos, orders, and listing data are unchanged. Suppression is fully reversible at any time.
- **AB 723 disclosure galleries are unaffected.** They are order-scoped (`order_disclosure.rb`), not
  listing-scoped, and carry no suppression check. This is correct and deliberate: the altered-photo
  disclosure behind a QR code already printed on MLS media is a legal obligation that a marketing
  kill-switch must not be able to revoke. Do not "fix" this.

**Ops UI:** a banner + suppress/unsuppress control on the listing edit page (outside `mat-tab-group`,
so it is visible on arrival rather than hidden behind a tab), a "Suppressed" chip in the listings grid
status column, and a tri-state Suppressed filter (Any / Suppressed only / Visible only).

**No backfill, no new env vars, no Sidekiq changes, no new routes.**

## Prerequisites

- [ ] insgt-api `feat/hide-listing` merged to `master`, suite green — commits `b1abd3d` (feature),
      `5e1ff47` (defunct export removal), `a78e0bd` (minimal-serializer fix)
- [ ] insgt-ops `feat/hide-listing` merged to `main`, `ng lint` and `npm run build:prod` clean,
      Cypress green
- [ ] `heroku` git remote reachable (`git fetch heroku`) — confirm what is actually live rather than
      assuming `heroku/master` is the prod ref
- [ ] AWS creds for the `insgt-apps` bucket and CloudFront `E2GJ3L3JH70697`
- [ ] No active deploy in flight

### Deploy order: API first, then Ops

**Do not reverse this.** Every part of the Ops change reads or writes a field that does not exist in
prod until the API ships.

| Order | Effect |
|---|---|
| **API → Ops** (correct) | Clean. The column, the params gate and both serializers land before anything asks for them. |
| **Ops → API** (do not) | Suppress and unsuppress both report **"Your account is not allowed to change listing suppression"** — wrong message, but it fails closed. The grid chip never renders and the Suppressed filter silently returns everything, with no error anywhere. |

**On the Ops-first failure mode:** it is loud-ish and safe, not silent. The effects test for *presence*
of `suppressedAt` in the response before testing its value, so an API that omits the key entirely is
treated as "the server did not tell us", never as "the server cleared it". An earlier revision tested
truthiness, which inverted unsuppress — it answered every unsuppress with "tour is back online" while
the listing stayed suppressed. That is fixed and pinned by *"reports failure when the unsuppress
response omits the field entirely"* in `cypress/e2e/listings/listing-suppression.cy.ts`. **Do not
relax that check to a truthiness test.**

Ordering is still required for the feature to *work* — it is just no longer required to avoid a lie.

## Steps

### 1. Deploy the API behind maintenance mode

**The code must not serve traffic before the migration has run.** There is no release phase in the
`Procfile`, so `git push heroku master` restarts the dynos onto the new slug immediately, and the
migration lands only when someone runs it by hand. In between, the new code queries a column that does
not exist yet — `PG::UndefinedColumn` on the unauthenticated virtual tour, on `custom_domain_exists?`
(which insgt-virtual-tour's routing constraint calls on *every* vanity-domain request), on the site
export, and on the public agent feed.

Maintenance mode closes that window. This is the sequence from `README.md`, and it is not optional
for this deploy:

```bash
heroku pg:backups:capture --app insgtapi     # also the agreed retention for the dropped tables
heroku maintenance:on  -a insgtapi
git push heroku master
heroku run rake db:migrate -a insgtapi
heroku restart -a insgtapi
heroku maintenance:off -a insgtapi
```

Adds `listings.suppressed_at` (`datetime`, `precision: nil`, nullable, no index, no default), and
drops `listing_exports` / `listing_export_logs`.

**On "safe in either order":** an earlier version of this runbook — and of the migration's own comment
— said the migration was order-independent relative to the code push. That is true only of the
*backfill*: existing rows read as unsuppressed with no data step. It is **false** of the code/schema
relationship, which is why the sequence above exists. Both comments have been corrected.

Both migrations set `lock_timeout = '5s'`. If either fails with a lock timeout, that means a
long-running query was holding `listings`; just re-run `db:migrate`.

`precision: nil` matches the neighbouring datetimes on this legacy table (`created_at`, `updated_at`,
`mls_synced_at`). No index is deliberate: low-selectivity flag, sequential scan wins at current table
size. If the site export becomes hot later, the right move is a composite index including
`status_type`, not a standalone index here.

**Verify:**

```bash
heroku run rails db:migrate:status -a insgtapi     # 20260731120000 shows up
```

### 3. Verify the API contract before touching Ops

Three things must be true, and `a78e0bd` is the one easy to lose in a squash — it is the only reason
the dashboard chip works.

```bash
# a) full serializer emits the key for a system user
curl -sH "Authorization: Bearer $JWT" https://insgtapi.herokuapp.com/s/listings/<id> | jq '.listing.suppressedAt'

# b) MINIMAL serializer emits it too — this is a78e0bd, and the grid chip depends on it
curl -sH "Authorization: Bearer $JWT" "https://insgtapi.herokuapp.com/s/listings?includes[]=minimal" | jq '.listings[0].suppressedAt'

# c) the suppressed search param filters
curl -sH "Authorization: Bearer $JWT" "https://insgtapi.herokuapp.com/s/listings?suppressed=true" | jq '.metadata.totalCount'
```

(a) and (b) must return `null` (present, empty) — **not** `undefined`/absent. An absent key means the
serializer gate or `a78e0bd` did not ship, and the Ops UI will correctly refuse to write.

### 4. Deploy Ops (insgt-ops)

```bash
npx ng lint insight-ops
npm run build:prod
```

Version is already `9.47.0` in `package.json` (the app reads it at build time). Then, per the manual
S3/CloudFront pipeline in the ops README:

1. Create a timestamped folder under `s3://insgt-apps/ops/`
2. Upload the contents of local `dist/` to it
3. Repoint the CloudFront origin to `insgt-apps.s3-website-us-west-1.amazonaws.com/ops/<timestamp>`
4. **Create a CloudFront invalidation `/*` on `E2GJ3L3JH70697`**
5. Trim deploys older than ~10 back (housekeeping)

**The invalidation is not optional.** Hashed bundle filenames self-bust, but `index.html` is not
hashed, and ops has the service worker enabled — a stale shell pins users to 9.46.0 indefinitely.

**Not needed for this deploy:** no `ngsw-config.json` change (no new routes or assets), no
`npm run build:daisy-scope` (no DaisyUI change), no env var changes. `environment.prod.ts` still
points at `https://insgtapi.herokuapp.com`; the Render migration is a separate, later piece of work.

### 5. Smoke test

Note ops uses hash routing — URLs are `https://ops.insightphotos.net/#/listings`.

As a **scheduler**, not just an admin (the write gate is `system_admin` + `system_scheduler`, and
admin-only testing would not catch a gate that accidentally narrowed):

1. Open a test listing's edit page → the suppress control is visible above the tabs.
2. Suppress → confirmation dialog states the consequences → confirm → banner appears with timestamp,
   snack bar reads "Listing suppressed — tour offline and hidden from public pages".
3. **Confirm the tour is actually down** — open the listing's branded tour URL in a private window.
   It must render not-found, not the tour.
4. Open the **Flyers** tab (renamed from "Publishing" in this release) → warn notice explains flyers
   cannot be created or edited; the add and edit buttons are gone; remove is still available.
5. Listings dashboard → the row shows a red "Suppressed" chip alongside its status.
6. Filter: **Suppressed only** returns just suppressed rows, **Visible only** excludes them, **Any**
   returns both. All three matter — `false` has to survive `buildApiParams` and the query-param round
   trip, and `Any` sends the literal string `null`, which `AppParam.boolean_params` skips.
7. Unsuppress → banner clears, chip disappears, tour URL loads again.
8. **Confirm the panorama endpoint fails closed** — with the listing suppressed, hit
   `GET /order_urls/:id/panorama.json?order=<token>` with no `Authorization` header. It must answer
   **204**, and the body must not contain the street address. Before this release it fell through to
   an order-sourced fallback that republished address, latitude, longitude and agent contact on an
   unauthenticated endpoint.

### 5b. Re-run the public site export — suppression is not automatic

**Suppressing a listing does not remove it from the marketing site on its own.** The export queries
are correct, but nothing re-runs them: `SiteExportWorker` is enqueued only when someone triggers an
export. Until it runs, the previously exported `site-data.json` still contains the listing.

**After suppressing anything in prod, trigger the site export from insgt-ops** and confirm the listing
is gone from the site. Tell whoever requested the suppression that the public site updates on that
export, not on the click — if the request was urgent (an NDA, an off-market demand), run it
immediately rather than waiting for the next scheduled export.

The same applies to the sibling feeds this release also gated (`videos`, `matterports`, `zillows`,
`commercial`, `events`) — they all live in the same payload and all refresh on the same export.

### 6. Rollback

Repoint the CloudFront origin path to the previous timestamped folder and re-invalidate `/*`.

**Rolling back Ops does not unsuppress anything.** `suppressed_at` is server-side, and the API's
`unsuppressed` / `visible` scopes keep applying — tours for suppressed listings stay down, which is
the correct direction to fail for a confidentiality control. It only removes the UI for managing it.
To actually restore a listing during an Ops outage:

```bash
heroku run rails runner 'Listing.find(<id>).update_column(:suppressed_at, nil)' -a insgtapi
```

Rolling back the **API** additionally requires reverting the migration, which drops the column and
therefore un-suppresses every suppressed listing at once. Do not do this without checking what is
currently suppressed:

```bash
heroku run rails runner 'puts Listing.suppressed.pluck(:id, :suppressed_at).inspect' -a insgtapi
```
