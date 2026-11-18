# CRMLS REcore — slice 1: move the listing sync from RETS to the REcore RESO Web API

**Repo:** insgt-api. Write-back docs land in insgt-platform (`/workspace/docs`). No changes elsewhere.
**Contract:** this plan, committed as `docs/plans/crmls-recore-web-api.md`. `tmp/recore.html`
(vendor documentation) is the only external source. Write-back adds the architecture document
`docs/architecture/crmls-recore.md`.
**Deadline:** CRMLS switches RETS off on 2027-01-25.
**Skill:** `slice-implementation`. Also load: `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Branch:** `feat/crmls-recore-web-api` from `master` (`24309546`).
**Model spend:** none — no model calls in this slice.

## Context

CRMLS is moving its MLS feed to the REcore Marketplace platform. Today `lib/crmls.rb` pulls
listings over RETS with the `rets` gem: hourly via `rake import_listings` and on demand from
`Listing#sync_right_now`. The engineer chose REcore's RESO Web API on-demand queries over the
vRETS compatibility layer and over full replication, and confirmed REcore access for CRMLS is
approved. This slice replaces the transport only; mapping, storage, the hourly task, the quota
endpoint and every caller stay.

## Gates

**Slice character:** visible or computed values (listing status, price, size and features are read
by agents and ops), so all gates apply. Plan review also applies, because this plan is the design.
**Pause at:** after the probe (the survey's unfinished part, unit 0), after plan (this gate), after
verification, and at the end.

## Scope

1. A REcore Web API client: `lib/recore_client.rb`.
2. `lib/crmls.rb`: replace RETS login, query and lease fallback with the client.
3. `app/models/crmls_transform.rb` / `app/models/crmls_feed.rb`: only the value and name
   differences the probe proves.
4. Remove what the switch orphans: `app/models/crmls_metadata.rb`, the `test_*` console helpers in
   `lib/crmls.rb:457-563`.
5. Rewrite `spec/lib/crmls_login_timeout_spec.rb`. **This changes an existing spec on purpose**: it
   stubs `Rets::Client`, which `Crmls` stops using.
6. `Listing#sync_right_now` (`listing.rb:142-159`), one change only: it inspects `'No record found'`
   only when the sync attempt completed. Added by plan review P4 and approved by the engineer.

## Out of scope — do not touch

1. Existing mapping defects: monthly HOA returning nil (`crmls_transform.rb:42`), `rets_class`
   never written (`crmls.rb:111`), the discarded hash in `update_listing_organizations`, the empty
   bedroom mapping.
2. `lib/sandicor.rb`, `app/models/sandicor_*.rb`, the `rets` gem in `Gemfile:31` (Sandicor still
   references it), the `mls_metadata_caches` table.
3. The rest of `Listing#sync_right_now` (`listing.rb:142-165`): its routing of org 1 listings to
   `Crmls`, and its turning `sync_with_mls` off on a confirmed `'No record found'`.
4. The replication endpoint, Media, Members, Offices.
5. `spec/support/stripe.rb:14` (`WebMock.allow_net_connect!`).
6. Any change in insgt-ops or insgt-app.

## Phase 0 — survey

### Facts (verified at `24309546`)

| What | Where |
|---|---|
| Hourly entry: `Crmls.import` then the Honeybadger check-in | `lib/tasks/scheduler.rake:17, 22-23` |
| `import` = `extract_listings` + `load_listings` | `lib/crmls.rb:63-66` |
| Failed login returns early, no `mls_imports` row, no raise | `lib/crmls.rb:92-94` |
| Batches of 20, newest listing ID first | `lib/crmls.rb:319-325` |
| `logout; login` before every batch | `lib/crmls.rb:332-333` |
| DMQL query by `ListingId`, `Residential` then `ResidentialLease` fallback | `lib/crmls.rb:335-375` |
| Missing listing → `import_error: 'No record found'` | `lib/crmls.rb:379-389` |
| Signature `MD5("2#{raw_listing}")`, payload stored as JSON | `lib/crmls.rb:402-420` |
| Login: `Rets::Client.new`, rescue → Honeybadger + ops email | `lib/crmls.rb:422-451` |
| `load_listing` stamps `mls_synced_at`, skips on equal signature | `lib/crmls.rb:120-143` |
| On-demand sync runs inside the web request; `'No record found'` turns `sync_with_mls` off | `app/models/listing.rb:142-159` |
| Status mapping matches `'Active Under Contract'`, `'Coming Soon'`, `'Closed'` | `app/models/crmls_transform.rb:76-95` |
| Only spec coverage: 2 login-failure examples + 4 scheduler examples | `spec/lib/crmls_login_timeout_spec.rb`, `spec/lib/tasks/scheduler_rake_spec.rb` |
| Hourly run today: 654–659 listings, 272–417 s; dev replay: 655 listings, 646 with a payload, 9 without | `docs/architecture/rails-upgrade-codebase-notes.md:475-476` |
| `rets` 0.11.2 locked; `webmock` 3.26.2 in test | `Gemfile.lock:443, 559` |
| Scalar listing values are stripped in place: `raw_value.strip! unless raw_value.blank?` | `lib/crmls.rb:195` |
| A stored RETS payload holds only strings and arrays (259 and 52 in the newest dev row); booleans are `"1"`/`"0"`, empty is `""`, numbers are strings (`"DaysOnMarket" => "423"`) | dev `mls_listings`, newest org 70 row |
| `sync_right_now` calls `MlsListing.find_by(listing_id: id).import_error` right after the sync, whatever the sync did | `app/models/listing.rb:151-152, 156-157` |
| `Net::HTTP` retries an idempotent request once by default (`max_retries: 1`) | `net-http-0.9.1/lib/net/http.rb:1156` |
| The suite allows unmatched HTTP; the tagged-example block is the pattern for blocking it | `spec/support/stripe.rb:14, 109-114` |

### Collisions and consumers

- `grep -rn -E "RecoreClient|recore|RECORE|REcore"` over `app lib config spec db Gemfile README.md`:
  empty. `grep -rln -i -E "recore"` over `insgt-ops/src`, `insgt-app/src`, `/workspace/docs`: empty.
- `ls spec/lib spec/models | grep -i -E "crmls|recore|mls"` → only `crmls_login_timeout_spec.rb`.
  `spec/fixtures` does not exist.
- insgt-ops requests `includes: ['mls_listing']` (`listing.effects.ts:33, 46` and four other
  effects) but reads only `mlsListing.importError` (`listing-mls-form.component.html:191-192`).
  insgt-app: `grep -rn -E "mlsListing|mls_listing" insgt-app/src` is empty.
- `spec/architecture/rails_upgrade_spec.rb`: `grep -n -i -E "crmls|rets|mls_import"` is empty.

### Prerequisites

- REcore application approved for CRMLS, with a Server Token and the dataset code: **stated by the
  engineer, not yet verified from this container.** Dev `.env` has no `CRMLS*` names
  (`grep -o -E "^CRMLS[A-Z_]*" .env` is empty), so the token and dataset code must be added to dev
  `.env` before unit 0.

### What the vendor doc states, and what it leaves out

Stated: base URL `https://api.marketplace.recore.net/api/v2/OData/{dataset_id}/{resource}`;
`Authorization: Bearer {server_token}`; `$filter` with `eq`/`or`; `$top` default 10, max 200;
`$unselect=Media`; filtering is case-sensitive; 5,000 requests per hour and 334 per minute; status
codes 400, 401, 403, 404, 408, 415, 429, 500, 503; tokens are restricted to allowlisted IP
addresses if any are set.

Not stated: the JSON envelope, the resource segment (`Property` and `Properties` both appear), the
enum strings CRMLS sends, how removed listings appear, the error body shape. The doc never
mentions CRMLS.

## Phase 1 — plan

### Unit 0 — probe (read-only, first thing after approval, then STOP and report)

From a dev Rails console, using real credentials:

1. Fetch 5 listings we hold by `ListingId`: two Active, one Pending or Active Under Contract, one
   lease, one whose stored payload has a monthly HOA. Record the working resource segment and the
   envelope.
2. Fetch 4 listings our stored payloads show as recently closed or off market: two `Closed`, one
   `Expired` or `Withdrawn`, one rented lease. **Switch prerequisite:** each must come back with
   its terminal status. If the approved feed type hides them, a listing that closes would read as
   "not found", never reach Sold, and never fire its order event.
3. Diff each payload against the same listing's stored `mls_listings.data`, limited to the fields
   `CrmlsFeed::CLASS_MAPPINGS[:residential]` and `CrmlsTransform` read. Record JSON types as well
   as values. The diff is the complete change list for units 2 and 3.
4. List every distinct character class in the `mls_number` values of
   `Listing.find_active_imports_for(70)`, and how many are not `/\A[A-Z0-9-]+\z/`. Query two of the
   exceptions as stored. This sets the identifier grammar the client accepts.
5. Read the rate-limit response headers once and record them.
6. Confirm in the REcore dashboard that the application has no IP allowlist. Heroku dynos have no
   fixed address.
7. Save payloads under `spec/fixtures/files/recore/` — active sale, pending, closed, lease — with
   agent, office and address values replaced by placeholders and JSON types left as received.

The probe credentials live only in dev `.env`. Specs never read them (see *Spec plan*).

Exception stop: a mapped field that is absent, a `ListingId` that no longer matches our
`mls_number`, a lease that does not come back from the same resource, or a terminal-status listing
from item 2 that does not come back.

### Gaps pinned

| Gap | Rule chosen | Rejected, and why |
|---|---|---|
| Credentials | Env vars `CRMLS_RECORE_SERVER_TOKEN`, `CRMLS_RECORE_DATASET`; base URL a constant in the client | SSM Parameter Store — the existing `CRMLS_*` values are plain config vars and the scheduler dyno already reads them |
| Token placement | `Authorization` header only | `access_token` query parameter — it lands in request logs |
| Filter | `ListingId eq 'A' or ListingId eq 'B' …`, `$top` = batch size, `$unselect=Media` | An `in` operator — the doc does not list one |
| Batch size | Stays 20 (about 33 requests per hour) | 200 — a longer URL for no benefit at this volume |
| Unsafe `mls_number` | A number outside the grammar unit 0 item 4 establishes is not sent and gets `import_error: 'Invalid MLS number'`. That is not `'No record found'`, so it does not turn sync off | Writing `'No record found'` — a local rejection is not a confirmed absence (review P2). Escaping and sending — one malformed value would fail the whole batch, and every later batch, each hour |
| Timeouts | Open 5 s, read 15 s, write 5 s, `max_retries = 0`: at most 25 s per request | Defaults — `Net::HTTP` retries a GET once, so a 20 s read timeout could take 40 s inside a web request under Heroku's 30 s limit (review P3) |
| Value types | `Crmls` normalizes each record before the signature and before storage, to the shape RETS stored: numbers → strings, `true` → `"1"`, `false` → `"0"`, `null` → `""`, arrays kept with string elements | Teaching every transform about JSON types — `crmls.rb:195` calls `strip!` on scalars, and `transform_listing_address_display_type` would read `false` as full address (review P1). The normalized shape also stays readable by the previous release |
| Response validation | Before any row is written: the body parses, `value` is an array, every record has a non-blank `ListingId`. Anything else is a `RequestError` | Trusting a 200 — `{"value":[{}]}` would mark the whole batch absent (review P6) |
| Request failure (non-200, timeout, socket error, invalid body) | `RecoreClient::RequestError`. `import_batch` records it in `@import_errors`, sends one Honeybadger notice and one ops email, and leaves the batch's `mls_listings` rows untouched. `extract` stops after the first failed batch | Marking the batch `'No record found'` — sync would be turned off for listings during an outage. Continuing through all batches — up to 33 notices per hour |
| On-demand caller | `Crmls.extract_and_load_listing` returns `true` only when the request completed; `sync_right_now` reads `import_error` only on `true` | Leaving the caller alone — after a failed attempt it raises on a listing with no `mls_listings` row and turns sync off on a stale `'No record found'` row (review P4). The same hole exists today on a failed login (`crmls.rb:76`) |
| Missing env var | Same path as today's failed login: `@import_errors`, Honeybadger, ops email, no `mls_imports` row, no raise | Raising — the swallow is logged behaviour (`rails-upgrade.md` §8 item 32) and the check-in semantics depend on it |
| 429 | Treated as a request failure; no retry | Retry with backoff — the next hourly run is the retry |
| Lease fallback | Removed, if unit 0 item 1 confirms one resource serves leases | Keeping a second query — it is a RETS class concept |
| Signature | Version constant 2 → 3 | Leaving it — the payload shape changes regardless; the bump records that the full reload is intended |
| Removed listings | Unchanged: absent from the response → `'No record found'` | — |

### Approach per unit

**Unit 1 — `RecoreClient`** (`lib/recore_client.rb`, plain `Net::HTTP` like `app/clients/anthropic_client.rb`).
`#properties(listing_ids)` returns an array of hashes; an empty result is a normal return.

**Unit 2 — transform values.** Add the strings unit 0 found alongside the existing ones in each
`case` of `CrmlsTransform`. Additive and inert under RETS, so it lands before the switch. A
frequency alias for monthly HOA goes on the early return at `crmls_transform.rb:42` as well as the
`case`, so the existing nil result is preserved. A renamed key in `CrmlsFeed`, if unit 0 finds one,
is not inert and lands in the switch commit.

**Unit 3 — switch `Crmls`.** `#login` becomes client construction plus the env var check.
`#import_batch` loses lines 332-375, calls `client.properties`, and normalizes each record; lines
377-414 stay. `.extract_and_load_listing` returns whether the request completed, and
`sync_right_now` honours it. Remove `#logout`, the `logout` calls at `crmls.rb:86, 105`,
`PROPERTY_SEARCH_CLASSES`, and the header comment's RETS examples. `SEARCH_PARAMS` stays.

**Unit 4 — remove orphans.** `app/models/crmls_metadata.rb` and `crmls.rb:457-563`.

### Contract impact

None across repos. The `mls_listing` include keeps its shape. `import_error` is free text that
insgt-ops prints as "MLS error: …" (`listing-mls-form.component.html:192`), so the new
`'Invalid MLS number'` value needs no client change. No client reads the raw `data` blob (evidence
under *Collisions and consumers*).

### Spec plan

Every new spec stubs the two env vars with fake values and runs under
`WebMock.disable_net_connect!`, restored afterwards, following `spec/support/stripe.rb:109-114`.
A missed stub then fails instead of sending an authenticated request (review P8).

`spec/lib/recore_client_spec.rb`:

- builds the `or` filter, `$top`, `$unselect=Media` for two IDs
- sends the bearer header and no `access_token` parameter
- empty `value` returns `[]`
- 401, 429, 503 each raise `RequestError` carrying the status
- a read timeout raises `RequestError` after exactly one request (pins `max_retries = 0`)
- invalid JSON, a missing `value`, and a record without `ListingId` each raise `RequestError`

`spec/lib/crmls_import_batch_spec.rb` (fixtures, FactoryBot listings):

- found listing: `data`, `signature` written, `import_error` nil, `total_updated` incremented
- stored `data` holds only strings and arrays: `false` → `"0"`, `423` → `"423"`, `null` → `""`
- same payload twice: second run does not increment `total_updated`
- listing absent from a valid response: `'No record found'`
- `mls_number` outside the grammar: not sent, `'Invalid MLS number'`
- `RequestError`: rows untouched, one Honeybadger notice, `import_errors` non-empty, remaining
  batches not requested

`spec/lib/crmls_load_listing_spec.rb` (fixtures through `Crmls.load_listing`):

- 2 full baths and 1 half bath → `bath` 2.5
- `InternetAddressDisplayYN` false → `address_display_type` 2; true → 1
- Active → Pending fires `:listing_pending` once; loading the same payload again fires nothing
- Active → Closed fires `:listing_sold` once
- the lease fixture maps without a second request
- monthly HOA stays nil (the existing defect, pinned so this slice cannot change it silently)

`spec/models/crmls_transform_spec.rb`: each status string, old and new, against the literal
`ListingStatusType` integer, including Active Under Contract and Coming Soon.

`spec/requests/listings_mls_sync_spec.rb` (on-demand path through `ListingsController#update`):
failed request with no `mls_listings` row → no raise, `sync_with_mls` stays true; failed request
with a stale `'No record found'` row → stays true; confirmed absence → turned off; success →
values updated.

`spec/lib/crmls_login_timeout_spec.rb`, renamed `crmls_credentials_spec.rb`: missing token, and
missing dataset code → email, Honeybadger notice with `import_errors`, no `mls_imports` row, no
raise. Same three assertions as today.

`spec/architecture/crmls_recore_spec.rb` (contract spec): the status integers above, the
normalized-payload rule, and "a failed request never writes `'No record found'`".

Deliberate breaks to show red: drop `$unselect`; set `max_retries` back to 1; skip normalization
of `false`; make `RequestError` write `'No record found'`; remove one new status string; make
`sync_right_now` ignore the return value.

### Commit sequence

1. `feat: add the REcore Web API client` — client + spec + fixture
2. `feat: map the REcore listing values in CrmlsTransform` — transform + spec
3. `feat: read CRMLS listings from the REcore Web API` — `lib/crmls.rb`, the batch, load and
   credentials specs
4. `fix: keep MLS sync on when an on-demand sync attempt fails` — `listing.rb`, request spec
5. `chore: remove the CRMLS RETS metadata cache and console helpers`
6. `test: pin the CRMLS REcore invariants in a contract spec`
7. insgt-platform: `docs: add the CRMLS REcore plan` — `docs/plans/crmls-recore-web-api.md`,
   committed before implementation starts
8. insgt-platform: `docs: record the CRMLS REcore slice` — the architecture document
   `docs/architecture/crmls-recore.md` (transport, rules pinned here, probe results, change log),
   codebase notes
   (`docs/architecture/crmls-recore-codebase-notes.md`, and the stale `crmls.rb` rows in
   `rails-upgrade-codebase-notes.md:254, 262-266`), runbook `docs/runbooks/deploy-crmls-recore.md`,
   review record

No migration. Deploy ordering: set both config vars in Heroku before the release, or the hourly
task emails ops every run.

### Verification and shift memo

Before the switch commit, against the dev database, inside one rolled-back transaction (the P-5a
replay shape, `rails-upgrade-codebase-notes.md:476`):

1. Run the current RETS import first, so the baseline is today's MLS state and not the restore's.
   Snapshot every column in `CrmlsFeed`'s `listing_attributes`, the feature rows, the county and
   complex areas, and `accounts.mls_number`.
2. Fetch every listing in `Listing.find_active_imports_for(70)` from REcore, write the normalized
   payload and signature to `mls_listings`, and run `Crmls.load_listing`, with order events,
   mail and Sidekiq stubbed.
3. Diff the snapshot against the result. The memo lists every listing that moved, by field, with
   old value, new value and the numeric difference.

Expectations, reasoned before any code exists:

| Check | Expected | Basis |
|---|---|---|
| Listing with 2 full and 1 half bath | `bath` 2.5 | `crmls.rb:227-232` |
| Listing whose address display is off in the MLS | `address_display_type` 2, same as before | `crmls_transform.rb:108-117`; a `false` read as full address would disclose an address |
| Listing under contract | `listing_status_type` = pending | `crmls_transform.rb:81` |
| Listing with size in square feet | `size` unchanged to the unit | `crmls_transform.rb:64-67` |
| Order events the replay would fire | 0 | the RETS import ran minutes earlier |
| Listings found | 646 of 655 in dev, ± listings that changed status since the restore | same IDs, same MLS |
| `listing_status_type` moves | 0 beyond genuine MLS changes since the stored payload | transport change only |
| Listings that go from found to not found | 0; any are case or format mismatches from unit 0 item 3 | case-sensitive filter |
| First run `total_updated` | equals listings found | signature version bump |
| Second run `total_updated` | under 50 | only real changes; a value near the total means a volatile field is in the signature |
| Run duration | under 120 s (estimate) | 33 requests against 272–417 s with a login per batch |

Post-deploy, after the first hourly run that **started** after the release (a Scheduler dyno
already running keeps the old code; `created_at - duration` is the start):
`MlsImport.where(organization_id: 70).last` shows `total_listings` 654–659; the check-in arrives;
no ops email; `MlsListing.where(organization_id: 70).where.not(import_error: nil).count` is no
higher than before the deploy; `GET /listings/mls_quota` lists the run.

Rollback: revert the release while RETS is still live. Stored payloads keep the strings-and-arrays
shape, so the previous release can read them, and its next hourly run computes a version 2
signature, sees a difference, and rewrites every row from RETS. Keep the four RETS `CRMLS_*`
config vars until CRMLS switches RETS off; after that date there is no rollback.

### Risks

- Every listing reloads once on the first run. `load_listing` fires
  `OrderEvent.handle_order_event` on a move to Pending or Sold (`crmls.rb:207-224`), so a wrong
  status mapping would fire events in bulk. The shift memo's zero-moves expectation is the guard.
- An outage no longer looks like "not found", which is a behaviour change in the safe direction.
- Normalizing a JSON float may give `"2.0"` where RETS gave `"2"`. Columns that take the raw value
  without a transform would show it; the shift memo's per-field diff is the guard.
- The `Regexp::TimeoutError` exposure that slice 5a documented came through the `rets` parser; it
  goes away for CRMLS, so `rails-upgrade-codebase-notes.md:205` needs its row amended.

### Decisions from the engineer (2026-11-16)

1. Renaming and rewriting `crmls_login_timeout_spec.rb` is accepted.
2. The plan is committed as `docs/plans/crmls-recore-web-api.md`. The finished implementation is
   also written up as an architecture document, `docs/architecture/crmls-recore.md`, at write-back.
3. The change to `Listing#sync_right_now` (scope item 6) is approved.
4. CRMLS switches RETS off on **2027-01-25**. That is the deadline for this slice and the last day
   a rollback is possible; the RETS `CRMLS_*` config vars are removed after it.

### Open questions for the engineer

None.

### Unverified

- That the token works and the dataset serves our listings (unit 0).
- That our feed type returns closed and off-market listings (unit 0 item 2, a switch prerequisite).
- The response envelope, resource segment, JSON types and enum strings (unit 0).
- The `mls_number` grammar (unit 0 item 4).
- Run duration and second-run `total_updated` (estimates).
- `AGENTS.md`, which the review brief names, does not exist in insgt-api or `/workspace`; the
  reviewer read `CLAUDE.md` instead.

## Plan review

`gpt-6-astra`, reasoning effort `max` (session header matches the command), sandbox
`danger-full-access` in worktree mode (`codex sandbox true` failed the probe), detached worktree at
`24309546a1258f1b6960b7ad095c19956e045fb3` with no `.env`. 2026-11-16 15:47:55 → 16:00:48 UTC,
39 commands, 165,331 tokens. Plan snapshot sha256 `4cdf2d61…53ca5b`, unchanged after the run.
Worktree clean and at the base SHA afterwards; the real tree's HEAD and status unchanged. One
round; no second round, because no fix changed a migration and the commit sequence only gained
two commits.

| ID | Severity | Disposition | Change or reason |
|---|---|---|---|
| P1 | blocker | fixed | Verified at `crmls.rb:195` and against a stored payload. Added the *Value types* normalization rule, typed fixtures and the load specs |
| P2 | major | fixed | The "outcome it has today" claim was wrong: `crmls.rb:335` sends the value as stored. Grammar now comes from the probe; a rejected number gets `'Invalid MLS number'`, not `'No record found'` |
| P3 | major | fixed | Verified `max_retries: 1` at `net/http.rb:1156`. Retries off, 25 s worst case, pinned by a spec |
| P4 | blocker | fixed | Verified at `listing.rb:151-152`. `sync_right_now` moved into scope for one change (scope item 6), approved by the engineer |
| P5 | blocker | fixed | Terminal-status listings added to the probe as a switch prerequisite and exception stop |
| P6 | major | fixed | *Response validation* rule and three client examples |
| P7 | major | fixed | Load, transform, request and contract specs added, with literal integers, event counts and the monthly HOA pin |
| P8 | major | fixed | Verified at `spec/support/stripe.rb:14`. Fake credentials and a blocked network around the new specs |
| P9 | major | fixed in part | Fixed: a renamed key lands in the switch commit; the verification run is identified by start time; rollback readability follows from normalization. Rejected: staged switch with cache restoration — the previous release rewrites every row on its next run because the signature version differs |
| P10 | major | fixed | Shift memo covers every mapped output against a fresh RETS baseline, with five rule-derived spot checks |

Challenges to logged decisions: none.
