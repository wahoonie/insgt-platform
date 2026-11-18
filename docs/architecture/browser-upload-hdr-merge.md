# Browser Upload and Server-Side HDR Merge: Architecture and Roadmap

Nov 12, 2026 · @pangurbahn

## Summary

Insight Photos proposes to replace desktop S3 clients and long-lived AWS keys with authenticated in-browser uploads that go directly to S3, recorded by the platform as verified upload batches. Once that is in place, the HDR merge moves from processors' desktops to a server-side PhotomatixCL job, so processors download only the images that need manual work.

The work ships in six deliverables (D0 to D5). D1 and D2 remove every contractor-held AWS key without changing the shape of anyone's workflow. D3 to D5 change the workflow and carry most of the risk.

### Reviewer brief

This document is written for adversarial review. Statements are marked as **fact** (stated by the owner or documented by a vendor), **proposal** (a design choice made here) or **assumption** (not yet verified against the codebase or production). The most useful attacks are on:

- **Completeness:** can an order be marked fully uploaded when files are missing, wrong or corrupt?
- **Security:** does the presigned-URL model leave a path that is worse than the keys it replaces?
- **Bracket grouping:** where does automated grouping silently produce a wrong merge?
- **Sequencing:** is there a deliverable that cannot be reversed, or that blocks next-day delivery if it fails?
- **Operational load:** is this maintainable by one engineer alongside two platform migrations?
- **Unstated assumptions:** anything the design relies on that the Assumptions list does not name.

## Problem

Shoot files reach S3 through a path the platform does not control: contractors use desktop S3 clients with permanent AWS keys, and the platform learns about the result afterwards. Five problems follow from that.

1. **Permanent credentials on contractor machines.** Each photographer uploads with Transmit or Cyberduck using their own AWS access key, and those keys never expire (fact). The photographers are independent contractors on personal machines. A lost laptop or a departed contractor leaves a working credential until someone remembers to delete it. The permissions attached to each key have not been audited for this document (assumption: they are broader than one order).
2. **Uploads are not authorized per order.** A key authorizes writing to the bucket, not uploading shoot X for order Y. Nothing prevents a file landing under the wrong order or name, and the platform holds no first-class record of who uploaded which file.
3. **Completeness rests on the zip.** Photographers zip a shoot before uploading. A whole zip arriving is today's evidence that all the photos arrived, and it is what allows the order to be marked as uploaded (fact). The zip proves that what was zipped arrived together. It does not prove the photographer zipped every frame, and bracket errors are found later, by a processor, after a multi-gigabyte download.
4. **Processors move the full bracket set twice.** Processors download the photographer's zips with Transmit, verify bracket sets by hand, merge them in desktop Photomatix with Insight's own presets, then upload the final processed photos, also with Transmit (fact). Most of the bytes they download are brackets that only exist to be merged. Processors also hold AWS access.
5. **One order has several uploads of different kinds.** An aerial photographer, a ground photographer and a videographer may each upload to the same order, and a photographer may return later with supplemental phone photos (fact). Video and supplemental photos do not go through the HDR merge. A single "uploaded" state per order cannot describe this.

The business cost is concentrated in three places: credential exposure during an active security-hardening effort, processor hours spent on downloads and bracket checks, and a next-day delivery promise ("Shoot Today. Live Tomorrow.") that depends on knowing promptly and accurately when a shoot's files are in.

## Current state

Insight Photos is a San Diego real estate media company running about 155 shoots a month for licensed agents, with contractor photographers and contractor processors, and one engineer.

| Item | Today |
| --- | --- |
| Upload client | Transmit or Cyberduck on the photographer's machine |
| Credential | One non-expiring AWS access key per photographer |
| Upload unit | One zip per photographer per shoot; sometimes more than one zip per order |
| Upload size | 400 MB to 7 GB per shoot |
| Largest shoot | About 800 photos |
| Zip contents | Mostly bracketed HDR exposures; sometimes individual photos |
| Other uploads on an order | Aerial photos, video clips, supplemental phone photos |
| HDR merge | Desktop Photomatix on the processor's machine, Insight's custom presets |
| Bracket verification | Manual, by the processor, before merging |
| Processor transfer | Transmit, for both download and upload |
| Fallback merge | AutoHDR web interface, used as an outlier for rush shoots; far more expensive per shoot than Photomatix |

### Platform context

- **Backend:** `insgt-api`, Rails 8.1.4 with PostgreSQL, Redis and Sidekiq, on Heroku. A move from Heroku to Render is planned.
- **Frontends:** separate Angular apps, including `insgt-photographers` (photographer-facing) and `insgt-ops` (internal operations).
- **AWS:** S3 for shoot files, with STS and SSM already in use. A separate hardening effort aims to replace static AWS keys with role-based identities.
- **Alerts in progress:** SMS to the owners when a photographer uploads on a same-day order, and a 3:30pm Pacific warning when a same-day order has no upload. Both depend on a reliable upload event.

### Current flow

1. The photographer shoots, then zips the files for the order.
2. The photographer uploads the zip to S3 with a desktop client and their AWS key.
3. An S3 bucket event triggers a Lambda function (the insgt-photographer-uploader repo), and the order shows as uploaded on a processing-queue screen (fact). What the function checks and what it writes to the platform is to be confirmed in D0.
4. A processor downloads the zip, verifies the bracket sets, merges them in desktop Photomatix, and edits the images that need it.
5. The processor uploads the finished images, and the order proceeds to delivery.

## Goals, non-goals and constraints

### Goals

- **G1. No long-lived AWS credentials outside the server side.** No contractor machine holds an AWS key.
- **G2. Every upload is authorized and attributed.** Each file is tied to an authenticated user and a specific order before any bytes move.
- **G3. Platform-verified completeness.** The platform, not the zip, decides that an upload is complete, with assurance at least equal to today's.
- **G4. Processors download only what needs manual work.** The merge runs server-side and processors review its output.
- **G5. No desktop S3 client.** Photographers and processors work entirely in the browser.
- **G6. Next-day delivery is never at risk from the migration.** Each deliverable can be rolled back, and the old path stays available until the new one is proven.

### Non-goals

- Replacing the processors' manual editing, or automating quality judgment of merged images.
- Processing video. Video clips are uploaded and stored, and skip the merge.
- Making AutoHDR part of the main path. It stays an outlier, and could later become one more processing route.
- Uploading full shoots from a phone. Small supplemental batches from a phone are in scope.
- Changing how finished images are delivered to agents.

### Constraints

- **One engineer.** Anything that adds a deploy target or an on-call surface has to justify it.
- **Platform migrations in flight.** The Heroku to Render move overlaps this work, so the design avoids depending on either host's specifics.
- **Upload bytes must not pass through the app servers.** Multi-gigabyte request bodies do not fit Heroku's request timeout or dyno memory.
- **Home internet connections.** Upstream bandwidth is the bottleneck, and connections drop. Uploads must survive both.
- **Contractor tooling.** Photographers and processors use their own computers and browsers, which the company does not manage.

## Architecture overview

The browser sends file bytes straight to S3 using short-lived presigned URLs, while `insgt-api` authorizes each upload, records it as a batch, and verifies the result against S3 before anything downstream runs.

&#91;embedded content: architecture · 5 components, 7 data paths\]

Both browsers exchange file bytes with S3 directly; `insgt-api` sees only manifests and signing requests, and the merge worker reaches S3 and the API but never a browser.

### Components

| Component | Responsibility | Status |
| --- | --- | --- |
| Upload UI in `insgt-photographers` | File selection, manifest, chunking, parallel upload, retry, resume, progress | New |
| Processing queue in insgt-ops | Download originals, upload final processed photos, and later review merged images | Existing screen, new download and upload UI |
| `insgt-api` upload endpoints | Authorize, create batches, sign S3 requests, complete and abort uploads | New |
| Batch verifier (Sidekiq job) | Compare the manifest with what S3 holds; mark the batch complete | New |
| S3 bucket | Originals, merged outputs and finals under server-chosen keys | Existing bucket, new prefixes and configuration |
| Merge queue | Carries one job per complete batch that needs an HDR merge | New |
| Merge worker | Linux EC2 instance running PhotomatixCL, started on demand and stopped when idle: fetch files, group brackets, merge, write outputs, report back | New |

### End-to-end flow (target state, after D5)

1. The photographer opens the order in `insgt-photographers`, chooses the batch kind, and selects the shoot folder.
2. The browser reads file names, sizes and EXIF data, warns about incomplete bracket sets, and sends a manifest to `insgt-api`.
3. `insgt-api` checks that this user may upload to this order, creates an upload batch, and returns signed S3 requests for the declared files.
4. The browser uploads files in parallel directly to S3, with a checksum on each, retrying failures.
5. The browser reports that it is finished. The verifier lists the batch's prefix in S3 and compares it with the manifest.
6. On an exact match the batch becomes complete. Order completeness is recomputed, and the upload event fires for alerts.
7. If the batch's route is an HDR merge, a job goes on the merge queue. Video and supplemental batches stop here.
8. The merge worker groups files into bracket sets, runs PhotomatixCL per set with the route's preset, writes merged images to S3, and reports per-set results to `insgt-api`.
9. A processor reviews the merged images, accepts most, and downloads only those needing manual work, with the option to pull the original brackets for any one set.
10. The processor uploads finished images through the same upload component as a finals batch, and the order proceeds to delivery.

Before D5, steps 1 to 4 handle zips in place of individual files. Before D4, processors continue to merge on the desktop.

## Upload batch data model

The unit of upload is a batch, not an order: one contributor's set of files of one kind for one order. An order has many batches, and each completes and is processed independently. Everything in this section is a proposal; names are placeholders.

### Records

| Record | Key fields | Purpose |
| --- | --- | --- |
| `UploadBatch` | order, uploader, kind, processing route, container (`zip` or `files`), status, declared file count and bytes, verified-at | One contributor's upload for one order |
| `UploadFile` | batch, file name, S3 key, declared size, checksum, verified size, status, capture time, exposure bias, bracket set | One declared file and its verification result |
| `BracketSet` | batch, member files, grouping confidence, merge status, output key, error, review state | One merge unit and its outcome |

### Batch kinds and routes

| Kind | Typical uploader | Processing route |
| --- | --- | --- |
| Ground photos | Ground photographer | HDR merge, ground preset |
| Aerial photos | Aerial photographer | HDR merge with an aerial preset when bracketed; otherwise none |
| Video | Videographer | None |
| Supplemental photos | Photographer returning to the property, often by phone | None |
| Finals | Processor | None; feeds delivery |

The route is a preset choice or "none", not a yes/no flag. The uploader picks the kind, defaulted from their assignment on the order. Within a merge-routed batch, routing is decided again per bracket set: a group of one frame passes through unmerged, which covers shoots that mix brackets with individual photos.

### Batch status

1. `declared`: manifest accepted, nothing uploaded yet.
2. `uploading`: at least one file has started.
3. `verifying`: the client has reported completion and the verifier is running.
4. `complete`: S3 matches the manifest exactly. This is the upload event.
5. `processing`, then `ready_for_review` or `processing_failed`: merge-routed batches only.
6. `abandoned`: no progress within a timeout, or cancelled by the uploader. Uploaded objects are cleaned up.

A batch that fails verification returns to `uploading` with the missing or mismatched files listed, so the uploader can resume.

### Order completeness

Batch completeness is mechanical. Order completeness is a business rule, and it is derived, never stored as a one-way flag.

- **Expected batches** come from the order's assignments: if aerial, ground and video are assigned, the order waits on three batches. Expected batches key on the assigned service, not the person, because one photographer can hold several services on an order (assumption: assignment data can express this).
- **Late batches are normal.** A supplemental batch added after the order looked complete reopens it and returns it to the processors' screen.
- **Unexpected batches are allowed.** A batch with no matching assignment is accepted from a user assigned to the order and flagged for ops attention.
- **Multiple batches of one kind are allowed.** A photographer who forgot a card uploads a second ground batch; both are processed.

## Upload mechanics

Large files use S3 multipart upload and small files use a single presigned PUT; in both cases the server chooses the key and signs each request for a short lifetime.

### Why multipart

A single S3 PUT is capped at 5 GB, and shoots reach 7 GB, so one-request uploads cannot cover zips. Multipart splits a file into parts of 5 MB to 5 GB, up to 10,000 parts, each uploaded and retried independently. A dropped connection costs one part.

### API surface in `insgt-api` (proposal)

| Call | Does |
| --- | --- |
| Create batch | Authorizes user and order, stores the manifest, returns the batch and the server-chosen key for each file |
| Sign requests | Returns presigned URLs for a set of files or parts; called in groups, not once per file |
| List parts | Returns the parts S3 already holds for one multipart upload, for resume |
| Complete file | Calls `CompleteMultipartUpload` for one file |
| Finish batch | Client reports it is done; enqueues the verifier |
| Abort | Aborts open multipart uploads and marks the batch abandoned |

### Parameters (proposal, to be tuned in D1)

- **Multipart threshold:** files above about 100 MB use multipart; smaller files use one PUT. Zips and video clips are multipart; individual photos are single PUTs.
- **Part size:** 32 MB, giving about 220 parts for a 7 GB file.
- **Concurrency:** 3 to 4 parallel requests per browser.
- **URL lifetime:** one hour or less, with the client requesting fresh URLs as it goes.
- **Key layout:** `orders/{order}/batches/{batch}/{sanitized file name}`. The client never supplies a key.

### Resume

- **Within a session:** failed parts and files retry automatically with backoff.
- **After a reload or closed tab:** the browser cannot keep a handle to the files, so the uploader selects the same zip or folder again. The client matches files to the open batch by name and size, asks which parts and files S3 already holds, and sends only the rest.
- **Across devices:** an open batch can be resumed from another computer by the same user.

### Bucket configuration

- **CORS:** allow PUT from the app origins and expose the `ETag` response header, which multipart completion requires.
- **Lifecycle:** abort incomplete multipart uploads after 7 days, so orphaned parts stop accruing storage cost.
- **Encryption and access:** unchanged from the bucket's current settings (assumption: public access is already blocked).

### Coexistence with the existing uploader Lambda

Today a bucket event triggers a Lambda function (the `insgt-photographer-uploader` repo), and that is how an order comes to show as uploaded (fact). The new design replaces that signal with the verified batch, for two reasons.

- **A bucket event reports one object, not a complete set.** It works today because one zip is one object. With individual files a shoot produces up to 800 events, none of which says the shoot is complete.
- **A bucket event carries no authorization.** It says an object appeared, not who was allowed to put it there or for which order.

Both paths run side by side until the last desktop key is revoked, so they must not react to each other's objects:

- **Separate prefixes (proposal).** Browser uploads write under a new prefix that the Lambda's trigger does not match, so the Lambda keeps serving desktop uploads unchanged and never fires on browser uploads. Note that a completed multipart upload also raises an object-created event, so a shared prefix would double-report zips.
- **One definition of "uploaded" for the queue.** The processing queue shows an order as uploaded if either the Lambda or a verified batch says so, until the Lambda is retired.
- **Retirement.** When D2 exits with no desktop keys left, the Lambda's trigger is removed and the function is retired. Anything else it does beyond marking the upload has to move into the batch verifier first; that inventory is part of D0.

### Client library

Uppy's S3 multipart plugin is the candidate: it is framework-agnostic and handles chunking, concurrency, retry and pause. Its current API has not been checked for this document, and D0 confirms it against the versions of Angular in use. The fallback is a thin custom client over the browser's `fetch` and `File.slice`.

### Known limits of a browser upload

- The tab must stay open and the computer awake. At 10 Mbps upstream a 7 GB shoot takes about 1.6 hours. The Screen Wake Lock API and a visible "keep this tab open" state reduce the risk.
- Phones suspend background tabs, so full shoots are laptop or desktop only. Supplemental batches of a few photos are small enough for a phone.
- Throughput should match the desktop clients, since both are limited by the uploader's connection.

## Completeness and integrity

A batch is complete only when the server has confirmed that S3 holds exactly the files the uploader declared, each at its declared size and checksum. The client's own report of success is never sufficient.

### The manifest

Before any bytes move, the browser sends a manifest listing every file's name and size, plus capture time and exposure data for photos. The server stores it as the batch's expected contents. The manifest is the replacement for the zip: it is what makes "all files arrived" a checkable statement.

### Four layers of assurance

| Layer | Question | Mechanism | Enforced by |
| --- | --- | --- | --- |
| Transport | Did each file arrive uncorrupted? | Checksum sent with each PUT or part; S3 rejects a mismatch | S3 |
| Manifest | Did every declared file arrive? | List the batch prefix; compare keys and sizes with the manifest | Server |
| Exactness | Is anything present that was not declared? | Same listing; extra objects fail verification | Server |
| Selection | Did the photographer select every frame? | Bracket and sequence checks on EXIF data before upload | Browser, as warnings |

The first three layers are hard gates. The fourth is advisory, because the platform cannot know about a frame that was never selected, and individual non-bracketed photos are legitimate.

### Selection checks (D5)

With individual files, the browser can inspect a shoot before upload and warn while the photographer still has the card:

- **Incomplete set:** a group with fewer exposures than the shoot's prevailing bracket size.
- **Sequence gap:** a missing number in the camera's file name sequence.
- **Count mismatch:** a total that is not a multiple of the bracket size, with no single frames to explain it.

The photographer can override each warning with a reason, which is stored on the batch and shown to the processor.

### Zips versus individual files

| Property | Zip (D1 to D4) | Individual files and manifest (D5) |
| --- | --- | --- |
| Everything selected arrived intact | Yes: size and checksum of the zip | Yes: size and checksum per file |
| Cost of a failure | Retry of the affected parts | Retry of one file |
| Contents known to the platform at upload | No, until something unzips it | Yes |
| Bracket sets checked before upload | No | Yes, as warnings |
| Photographer selected every frame | Not provable | Not provable, but gaps are detectable |

In the zip phases, assurance equals today's: the platform verifies the zip object's size and checksum. From D3, the merge worker opens the zip and can fail the batch if the archive is unreadable.

## Processing: server-side HDR merge

A complete, merge-routed batch is handed to a worker that groups its files into bracket sets and runs PhotomatixCL once per set with Insight's existing presets. This is the least certain part of the design, and D3 exists to test it before any workflow depends on it.

### What the vendor documents (facts)

| Point | What HDRsoft states | Source |
| --- | --- | --- |
| Platforms | Linux and Windows builds exist | [Pricing](https://hdrsoft.com/order/PhotomatixCL-pricing.php) |
| Presets | A custom preset saved as an XMP file can be applied from the command line | [Download and command generator](https://www.hdrsoft.com/download/photomatixcl.html) |
| Batching | A companion driver processes a folder of sets, with a fixed set size in its sample command | [Driver](https://www.hdrsoft.com/download/PhotomatixCL-driver.html) |
| Licensing | The license is loaded on one server, or shared across several through a license server | [Installation](https://hdrsoft.com/support/doc/PhotomatixCL-install.html) |
| Credits | Plans carry monthly merge credits; when they run out, output is watermarked | [FAQ](https://hdrsoft.com/support/faq-photomatix-command-line-tool.html) |
| Output | Processed images save as JPEG or TIFF | [Pricing](https://hdrsoft.com/order/PhotomatixCL-pricing.php) |

### Bracket grouping (proposal)

Grouping is the hard problem: it is what processors verify by hand today, and a wrong group produces a plausible-looking wrong image.

1. Read capture time, exposure bias, shutter speed and camera serial from each file's EXIF data.
2. Sort by camera and capture time.
3. Start a new set when the gap to the previous frame exceeds a threshold, or when the exposure sequence restarts.
4. Score each set. A set whose size matches the shoot's prevailing bracket size and whose exposures form the expected sequence is high confidence.
5. Merge high-confidence sets. Pass single frames through unmerged. Send everything else to the processor as "needs grouping" with its original files, and do not merge it.

The vendor's fixed-size driver is not used, because shoots mix bracket sets with single frames and dropped exposures. Thresholds and the confidence rule are set from past shoots in D3.

### Worker execution (proposal)

- **Host:** one Linux EC2 instance that is stopped by default and runs only while there is work. Photographers upload mostly in the evening, so an always-on host would sit idle most of the day. A stopped instance costs only its disk.
- **Start:** when a batch completes, `insgt-api` enqueues the merge job and calls `StartInstances` on this one instance. The call does nothing if it is already running. The app's IAM identity is allowed to start this instance and nothing else in EC2.
- **Stop:** the worker drains the queue, waits a few idle minutes, then shuts itself down. Start-up adds about a minute before the first merge.
- **Start/stop race:** a job can arrive while the instance is shutting down, and `StartInstances` fails on an instance in the stopping state. The start call is retried until the instance reports running, and an alarm on the age of the oldest queued message catches anything that slips through.
- **Concurrency:** one batch at a time to begin with, in arrival order. Whether to run several at once is decided from the merge time per shoot measured in D3.
- **Portability:** the worker is written as a program that takes one job, processes it and exits or takes the next, with no assumptions about the machine. That keeps a later move to one ephemeral container per batch a packaging change. Containers remove host maintenance and give every shoot a fresh disk; they are deferred because they depend on the licensing answers below.
- **Licensing:** a single instance fits a single-system license, provided the license survives a stop and start of the same instance (D0 question). HDRsoft's [pricing FAQ](https://www.hdrsoft.com/order/PhotomatixCL-pricing.php) describes loading the license key at start-up in serverless environments; which plans allow that is the second D0 question.
- **Queue:** SQS, with one message per batch. The worker is a small standalone program, not a Rails process, so it does not depend on where `insgt-api` is hosted during the Heroku to Render move.
- **Per batch:** download the files (or unzip the zip) to a per-job directory on local disk, group, merge each set, upload outputs to a `merged/` prefix under the batch, post per-set results to `insgt-api`, and delete the directory.
- **Idempotency:** outputs are keyed by set, so a redelivered message overwrites the same objects and reports the same results.
- **Failure:** a failed set is retried once, then reported as failed for that set only. A failed batch never blocks the order: processors fall back to downloading the originals.
- **Credits:** the worker reports remaining merge credits, with an alert well before zero. A watermarked output must never reach a processor's review screen.

### Shadow mode (D3)

The merge runs on every live shoot while processors keep working exactly as they do today. Its output is compared with what processors produced, and the following are measured before D4 is allowed to start: grouping accuracy, merge failure rate, time from upload-complete to merged, and credits consumed per shoot.

## Processor workflow

Processors move from "download everything, merge, edit some" to "review merged results, download only what needs editing". The change arrives in two steps so that their file transfer moves to the browser well before their work changes.

### D2: same work, no desktop client

- **Download:** each batch on the processing queue has a download action that issues a short-lived presigned link. The browser's own download manager handles a 7 GB zip, including pause and resume.
- **Upload:** final processed photos go up in the browser from the order's row in the processing queue, replacing Transmit. Details below.
- **Unchanged:** processors still verify brackets and merge in desktop Photomatix.

### Finals upload in the `insgt-ops` processing queue

Processors upload final processed photos with Transmit today (fact). D2 adds an upload action to each order in the `insgt-ops` processing queue, built on the same upload component and batch model as photographer uploads.

1. The processor opens the order in the processing queue and chooses "Upload finals".
2. They select or drop the finished files or folder. The browser builds a manifest and `insgt-api` creates a finals batch on the order.
3. Files upload directly to S3 as individual files, not a zip. Finals are single images, so each is one presigned PUT.
4. The verifier confirms S3 matches the manifest, and the finals batch becomes complete.
5. Completion triggers whatever the arrival of finals triggers today, so the order proceeds to delivery exactly as it does now.

Design points specific to finals:

- **Destination keys:** finals must land where the delivery pipeline already reads them, or the pipeline must learn the new batch prefix. Which of the two is decided in D0.
- **Additional and replacement uploads:** a processor can add a later finals batch, or replace individual files, without re-uploading the set. Replacement rules need to match how re-edits are handled today.
- **Expected count:** before D4 the platform does not know how many finals to expect, so completeness means "everything the processor selected arrived". From D4 the expected set is the reviewed images.
- **Deployment order:** the `insgt-api` endpoints ship before the `insgt-ops` UI that calls them, per the project's standing convention.

### D4: review screen

The review screen is order-level, with batches listed beneath, each showing its own state: for example ground ready for review, aerial still merging, video waiting to be collected.

For a merged batch, the processor sees every merged image and can:

- **Accept** it as it stands.
- **Mark for editing** and download that merged image alone, or a selection as one archive.
- **Reject the merge** and download that set's original brackets to merge by hand.
- **Resolve a "needs grouping" set** by downloading its originals. Regrouping in the browser is out of scope.

Finished images are uploaded as a finals batch. An order is ready for delivery when every merged image is either accepted or replaced by an uploaded final (proposal: how finals map back to merged images is an open question below).

### The escape hatch

At every stage after D4, a processor can download a whole batch's originals and work as they do today. This is the rollback path for a bad merge, a worker outage or exhausted credits, and it is why the merge can fail without stopping delivery.

## Security model

Permanent, bucket-scoped keys on contractor machines are replaced by application sessions and presigned requests that each authorize one operation on one object for about an hour.

### Before and after

| Property | Today | Proposed |
| --- | --- | --- |
| Credential on contractor machine | AWS access key, never expires | Application session only |
| What a leaked credential allows | Whatever the key's policy allows, until the key is deleted | One PUT or GET on one server-chosen key, until the URL expires |
| Authorization decision | IAM policy, per key | `insgt-api`, per user and order, on every batch and signing call |
| Removing a contractor | Find and delete their IAM key | Deactivate their account |
| Object key chosen by | The contractor | The server |
| Record of who uploaded what | Not held by the platform | Batch and file records |

### Authorization rules (proposal)

- **Photographers** may create and resume batches only on orders they are assigned to, within a time window around the shoot.
- **Processors** may download originals and merged outputs, and upload finals, only for orders on their queue.
- **Signing** is refused for any file not in the batch's manifest, and for any batch not in `declared` or `uploading`.
- **Download links** are issued per request, expire in minutes to an hour, and are logged with the requesting user.

### Server-side credentials

- `insgt-api` signs with an IAM identity limited to the upload bucket's order prefixes: multipart operations, put, get and list. No delete outside batch cleanup.
- The merge worker uses an instance role limited to reading originals and writing the `merged/` prefix. It holds no database credentials and talks to `insgt-api` through a narrow, authenticated callback.
- Moving the app's own AWS access from static keys to role-based identities is a separate hardening effort; this design does not make it harder.

### Residual risks

- **A presigned URL is a bearer token.** Anyone holding it can use it until it expires. Mitigation: short lifetimes, one object per URL, HTTPS only, and URLs never written to logs.
- **A compromised contractor session** can upload junk to that contractor's assigned orders and download what their role allows. This is bounded by the assignment rules and is no worse than today.
- **Untrusted file content reaches the worker.** Zips can contain path-traversal entries or expand far beyond their size, and image files exercise a third-party decoder. Mitigation: extract with entry-name and size limits into a per-job directory, run the merge as an unprivileged user, and keep the worker's role and network access minimal.
- **Abuse of storage.** An authorized user could declare an enormous manifest. Mitigation: per-batch limits on file count and total bytes, set above the largest real shoot.
- **Cross-origin exposure.** The bucket's CORS rule allows PUT only from the app origins. CORS does not authenticate anything; the presigned signature does.

### Key retirement

Keys are revoked one contractor at a time as each moves to the browser, with the old path left working for the rest. D2 exits only when IAM shows no contractor access keys and CloudTrail shows no use of the retired ones (assumption: CloudTrail data events or S3 access logs are available for the bucket).

## Roadmap

The build order differs from the pipeline order on purpose: the key removal ships first and stands alone, the uncertain merge is proven in shadow before anyone depends on it, and photographers stop zipping only after the merge can consume loose files.

### Why not build in pipeline order

If photographers switched to individual files first, processors would have no practical way to fetch a shoot's brackets until the server-side merge was trusted. That would require a throwaway server-side zip bridge, and it would make the security fix wait on the riskiest component.

### Deliverables

| ID | Deliverable | Scope | Exit criteria | Depends on | Size (estimate) |
| --- | --- | --- | --- | --- | --- |
| D0 | Discovery and decisions | Audit IAM keys and their policies. Confirm how "uploaded" is set today, the bucket layout, and the assignment model. Confirm the client library. Put the two licensing questions to HDRsoft. Confirm where final processed photos must land for the delivery pipeline, and what their arrival triggers today. | Open questions 1 to 8 below answered in writing | None | Small |
| D1 | Photographer browser upload (zips) | Batch and file records, upload endpoints, verifier, bucket CORS and lifecycle, upload UI with resume. Batch kinds for ground, aerial, video and supplemental. Upload event wired to alerts. Browser uploads kept out of the existing uploader Lambda's trigger. | Two pilot photographers complete 10 consecutive shoots with no fallback to a desktop client, including one shoot above 5 GB and one interrupted and resumed | D0 | Medium |
| D2 | Processor browser transfer and key retirement | In the insgt-ops processing queue: presigned downloads of originals, and a new browser upload UI for final processed photos (finals batch). Key revocation for each photographer and processor. | Zero contractor IAM access keys exist. No desktop client in use for 2 weeks. | D1 | Small to medium |
| D3 | Merge spike and shadow mode | PhotomatixCL on a Linux host with Insight's presets. Bracket grouping. Queue and worker. Runs on past shoots first, then on every live shoot without affecting processors. | Thresholds agreed in advance and met over 2 weeks of live shoots: grouping accuracy, merge failure rate, time to merged, credits per shoot. Processors judge output equivalent to desktop. | D1 for live shoots; the spike on past shoots can start alongside D1 | Large |
| D4 | Processor review screen | Order-level review with per-batch state, accept, mark for editing, selective download, reject-to-originals, needs-grouping handling. | Processors handle 2 weeks of orders from the review screen. Full-batch original downloads fall below an agreed share of batches. | D2, D3 | Medium to large |
| D5 | Individual-file upload | Folder selection, per-file manifest, grouped signing, pre-upload bracket and sequence warnings, worker reads loose files. Zip upload remains available. | Pilot photographers upload 10 shoots as loose files, including the largest shoot type. Pre-upload warnings are reviewed against processor findings. | D3; D4 in practice | Medium |

### Rollback per deliverable

- **D1 and D2:** desktop clients keep working until each contractor's key is revoked, and a revoked key can be reissued in minutes.
- **D3:** shadow mode has no effect on delivery by construction. Turning it off is a queue toggle.
- **D4:** the escape hatch (download originals) is the old workflow, available per batch.
- **D5:** zip upload stays as an option in the upload UI.

### What ships value on its own

D1 and D2 together meet goals G1, G2 and G5 and are worth doing even if D3 fails. D3 failing its gate ends the roadmap at D2 without loss; the alternative merge routes in that case are listed under Alternatives.

## Risks, assumptions and open questions

The largest risk is automated bracket grouping producing wrong merges that look right; the largest unknown is whether PhotomatixCL output matches the desktop presets closely enough for processors to accept it.

### Risks

| Risk | Consequence | Mitigation |
| --- | --- | --- |
| Bracket grouping is wrong on some shoots | A plausible but wrong image reaches review, or delivery | Confidence scoring; low-confidence sets are not merged; shadow-mode accuracy gate before D4; processor review of every merged image |
| CLI output differs from desktop Photomatix | Processors reject merges and download originals anyway, so D4 saves nothing | Side-by-side comparison on past shoots in D3 before any build beyond the spike |
| Browser uploads fail more often than desktop clients | Late or missing uploads threaten next-day delivery | Resume, wake lock, pilot gate in D1, desktop path kept until each contractor is proven on the browser |
| Merge worker is a single host, started on demand | An outage stops merges. A job that arrives while the instance is stopping can sit in the queue. | Escape hatch to originals; queue retains jobs; start call retried until the instance is running; alarm on the age of the oldest queued job; instance rebuilt from an image. Not highly available by design. |
| Merge credits run out | Watermarked outputs | Credit monitoring and alert; worker refuses to publish outputs when credits are zero |
| Verification passes on a bad file | Corrupt or truncated image accepted | Checksums enforced by S3; worker fails sets whose files do not decode |
| Scope outgrows one engineer | Work stalls half-migrated | Each deliverable is independently valuable and reversible; D1 and D2 stand alone |
| Collision with the host migration | Rework, or risky concurrent deploys | Worker is decoupled from the app host; upload endpoints use no host-specific features; deliverables are scheduled around migration steps |
| Contractors resist the change | Parallel workflows persist | D1 and D2 remove steps and add none; zip upload remains through D5 |

### Assumptions

- Photographer and processor apps already authenticate users with sessions strong enough to replace AWS keys as the gate on uploads.
- Order assignments identify which photographer is expected to deliver which service.
- Contractor IAM keys are broader than a single order's prefix.
- The bucket blocks public access, and S3 access logging or CloudTrail data events can be enabled to confirm key retirement.
- Camera files carry reliable capture time and exposure data. Phone and drone files may not.
- Processors will accept server-merged output if it matches what their desktop presets produce.
- Supplemental phone photos may arrive as HEIC; conversion is out of scope unless processors require it.

### Open questions

Questions 1 to 8 are answered in D0.

1. What does the existing uploader Lambda do when a bucket event fires: which prefixes and file types trigger it, how it maps an object to an order, what it writes to the platform, and whether it also handles processors' finals?
2. What do the existing IAM keys permit, and how many are active across photographers and processors?
3. What is the current bucket and key layout for originals and for final processed photos, and what reads from it?
4. Where must final processed photos land for the delivery pipeline, and what does their arrival trigger today?
5. Can assignment data express expected batches per service on an order?
6. Does the current Uppy release support the multipart and batch-signing behaviour described, in the Angular versions in use?
7. For HDRsoft: does a single-system PhotomatixCL license survive stopping and starting the same EC2 instance?
8. For HDRsoft: which plans allow the license to be loaded on ephemeral instances or containers, and may several run at once?
9. What bracket sizes and camera models are in use, and how often do shoots mix brackets with single frames?
10. How many merges does a month of shoots require, and which PhotomatixCL plan covers that with headroom?
11. What are the acceptance thresholds for D3: grouping accuracy, failure rate, and time to merged?
12. From D4, how do uploaded finals map back to the merged images they replace: by file name, or by explicit selection?
13. Should merged outputs that a processor accepts unedited become finals automatically, or must they still be uploaded?
14. How long are original brackets retained once finals are delivered, now that they are stored as loose files?
15. Do California digital-alteration disclosure obligations (AB 723) attach to anything in the merge step, and does the batch record need to carry evidence for it?

## Alternatives considered

Each alternative below was set aside for the reason given; the reviewer is invited to argue that one of them is better.

### Upload path

| Alternative | Why not chosen |
| --- | --- |
| Rails Active Storage direct upload | Uses a single PUT per file, which S3 caps at 5 GB; shoots reach 7 GB. No part-level retry. |
| Upload through `insgt-api` | Multi-gigabyte bodies do not fit the host's request timeout or memory, and the app would carry all upload bandwidth. |
| Temporary STS credentials scoped to one batch prefix, with the browser signing its own requests | Viable, and fewer round trips for 800 files. Set aside as the default because per-request signing gives a simpler audit trail and tighter per-object control. Kept as the fallback if grouped signing proves slow. |
| A resumable-upload server (tus protocol) | Adds a server that receives all bytes and must be operated; S3 multipart already provides resumability. |
| Managed SFTP in front of S3 | Still a desktop client and a per-user credential; no manifest or order-level authorization. |
| Keep desktop clients, issue short-lived keys | Fixes credential lifetime only. No authorization per order, no manifest, no upload event, and still a desktop client. |
| Third-party file-request service | Files land outside the platform and need a second transfer; no tie to orders or batches. |

### Merge path

| Alternative | Why not chosen |
| --- | --- |
| Keep merging on processors' desktops | The fallback if D3 fails. Leaves full-bracket downloads and manual bracket checks in place. |
| AutoHDR for every shoot | Already available and used for outliers, but far more expensive per shoot than Photomatix (owner's assessment). Could be added later as another route on the batch. |
| Open-source merge tools | Would not reproduce Insight's existing Photomatix presets, so processors' output would change. |
| Ephemeral containers per merge job | Deferred, not rejected: it is the planned migration path. No host to maintain, no start/stop race, and a fresh disk per shoot. It waits on HDRsoft confirming a plan that allows ephemeral instances, and the D3 spike needs a host to experiment on in any case. |
| Run the worker as a Sidekiq process of `insgt-api` | Reuses app code, but ties the worker to the app's host and Redis during a host migration, and puts a third-party binary beside application credentials. |

### Sequencing

| Alternative | Why not chosen |
| --- | --- |
| Individual files from day one | Processors would need a server-side zip bridge until the merge is trusted, and key removal would wait on the riskiest component. |
| Build the merge first | Delivers nothing for security, and shadow mode needs a reliable upload-complete event that only D1 provides. |
