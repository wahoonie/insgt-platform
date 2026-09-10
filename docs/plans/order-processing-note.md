# Planning prompt — `OrderProcessingNote`

**Mode: planning only.** Do not write migrations, models, components, or specs. Produce a plan document. Stop at each phase boundary and report.

Load skills: `insgt-api`, `insgt-ops-angular-developer`, `angular-core`, `angular-ngrx-state`, `angular-unit-testing`, `clean-typescript`, `git-commit-messages`, `predeploy-review-rails`.

---

## 1. Context

Photographers increasingly send agents' editing requests to ops by iMessage: a short caption plus one or more photos or a video (e.g. "blur out the neighbors' homes", "watch the edge of my hand in the second-to-last backyard photo"). Today ops retypes the caption into `orders.processing_notes` (single text column, rendered in the `insgt-ops` order table Notes column) and the media stays in iMessage. The processor never sees the media.

The caption and its media are one instruction and must be stored together. A single text column cannot express that.

## 2. Decisions (constraints — do not re-litigate)

**D1. New model `OrderProcessingNote`.** `belongs_to :order`. The order may be a parent or a child; no fan-out logic. One note = one message body + 0..n files.

**D2. Attachments.** `has_many_attached :attachments` via Active Storage on S3. Mixed images and videos on the same note. Content-type allowlist: `image/jpeg`, `image/png`, `image/heic`, `image/webp`, `video/mp4`, `video/quicktime`. Attachment order = attachment id ascending. Image thumbnail variant only, for the ops list. Videos: serve original via short-expiry signed URL. No transcoding, no poster frames, no derivatives pipeline. Do not model these after `Photo` or `OrderUrl` — those are deliverables; these are reference material.

**D3. Author.** Polymorphic `author` (`author_type`, `author_id`), nullable (legacy backfill has no author). Confirm the concrete author classes by reading the codebase — expected candidates are the ops user model and the photographer model; report actual class names.

**D4. Source.** `source` stored as `smallint`, Rails enum. Fixed values:
`ops: 0, photographer_sms: 1, agent: 2, twilio: 3, legacy: 4`. Phase 1 writes only `ops` (via ops UI) and `legacy` (via backfill).

**D5. Body.** `body` text, presence required. A note that is "just files" gets a body like "see attached" from the transcriber.

**D6. Acknowledgement.** Per-note: `acknowledged_at` (timestamp, nullable) + `acknowledged_by_id` (nullable FK to the ops user model). Two states only; no status enum.

**D7. Retention.** Indefinite. No purge job. Attachments survive order lifecycle transitions. Report what the existing `Order` `dependent:` behavior is and recommend matching or diverging.

**D8. Backfill.** Every order with non-blank `processing_notes` gets one `OrderProcessingNote` with `source: legacy`, `author: nil`, `body: processing_notes`, `created_at: order.updated_at` (or the best available timestamp — report options). After backfill and verification, `processing_notes` is added to `ignored_columns`, writes stop, and the column is dropped in a separate follow-up migration under `strong_migrations` rules.

**D9. Twilio reservation.** Add `external_message_id` (string, nullable) with a unique partial index `WHERE external_message_id IS NOT NULL`. Not written in Phase 1.

**D10. Reads.** After backfill, all read sites use the notes collection. No dual-read period beyond the verification gate.

**D11. `MARGIN_LTV_*` constants and the shoot predicate are a no-touch boundary.** This work must not touch account classification, order type identity, or revenue exclusion logic.

## 3. Phase 0 — read-only research

Read. Do not modify. Report with file:line and counts.

1. `Order` model: all note-like columns (`processing_notes`, `photographer_notes`, `notes`, anything similar). The ops table renders notes with at least two distinct icons (camera, gear); identify which column drives which icon. **Do not plan to migrate any column other than `processing_notes` without sign-off.**
2. Every read site and every write site of `processing_notes` across `insgt-api`, `insgt-ops`, `insgt-photographers`, `insgt-app`, `insgt-galleries`. Counted list.
3. `photo.rb` and `order_url.rb`: how Active Storage is currently configured (service, S3 bucket, direct upload or server-side, variant processor). Report what is reusable (service config, bucket) and what is not (derivative pipelines).
4. Active Storage security posture after the 7.2.3.2 RCE patch: confirm the content-type validation path currently used and whether `active_storage.content_types_allowed_inline` / `content_types_to_serve_as_binary` need changes for video.
5. `Order` serializer(s) consumed by `insgt-ops`: which serializer, what it exposes, and how a nested notes collection with signed attachment URLs would fit without over-exposing author PII (name only; no email, phone, or IDs beyond what the ops UI already receives).
6. Authorization: the policy/scope that gates order reads and writes for ops users. The new endpoints must inherit it. Flag any horizontal-access risk (note id enumeration across orders).
7. `insgt-ops` Notes column component: file, current state shape in NgRx, whether order entities are normalized so notes can live as a nested array or need their own entity slice.
8. Existing multipart/file-upload pattern in `insgt-ops` (any component that already uploads a file to the API). If none, say so.

**Stop. Report Phase 0 findings. Wait for sign-off before Phase 1.**

## 4. Phase 1 — plan document

Produce `docs/plans/order-processing-notes.md` (or the repo's conventional plan location — report which) containing:

### 4.1 Schema
- `order_processing_notes` table: columns, types, null constraints, indexes (`order_id`, `[author_type, author_id]`, partial unique on `external_message_id`), FK behavior.
- Migration sequence under `strong_migrations`: create table → backfill (rake task, batched, idempotent, re-runnable) → `ignored_columns` → follow-up drop migration (separate PR).

### 4.2 Model
- Associations, enum, validations (body presence, attachment content-type allowlist, attachment count ceiling — propose a number), `acknowledge!(user)` method.
- Scopes: `unacknowledged`, `for_order`.

### 4.3 API
- Endpoints for ops: list notes for an order, create note (multipart: body + files[]), acknowledge note. Report whether direct-upload (client → S3) or server-side upload is the right call given `insgt-ops`'s existing pattern from Phase 0 §8, and give the reason.
- Serializer changes: nested `processing_notes` on the order payload, or a separate endpoint — recommend one with reasoning against the other.
- Signed URL expiry for attachments: propose a value.

### 4.4 `insgt-ops`
- Notes column replacement: list of notes (body, source, author name, created_at, ack state, thumbnails / video link).
- Add-note form: body textarea + multi-file input, single submit.
- Ack control per note.
- NgRx: actions, reducer, selectors, effects. Follow `angular-ngrx-state`. Propagate-null count semantics for any counts shown (e.g. unacknowledged count).
- `data-cy` attributes on the add form, file input, submit, ack control, note list.
- Note any place the existing Angular 19 NgModule vs standalone split affects the choice.

### 4.5 Tests
- RSpec: model validations (including a deliberate-break case for content-type allowlist), backfill task (idempotency proven by running twice), serializer PII exposure spec, authorization spec proving a note cannot be read or acknowledged via another order's scope.
- Vitest: reducer and selectors, state-in/state-out, `FLAGGED DEFECT:` convention, no silent fixes.
- Cypress: add note with two images and one video; acknowledge; reload; state persists.

### 4.6 Rollout
- Order of PRs (one concern per diff).
- Verification gate between backfill and `ignored_columns`: count of orders with non-blank `processing_notes` == count of `legacy` notes; report the query.
- Deliberate-break checklist for each PR.

### 4.7 Open decisions for sign-off
List anything discovered in Phase 0 that the constraints above don't settle. Do not resolve them yourself.

**Stop. Deliver the plan document. Do not proceed to implementation.**

## 5. Non-goals

- `insgt-photographers` upload UI (Phase 2, separate prompt).
- Twilio inbound endpoint (only the `external_message_id` column is reserved).
- Agent-facing visibility in `insgt-app`.
- Per-photo targeting (linking a note to a specific media item).
- Migrating any note column other than `processing_notes`.
- Video transcoding, poster frames, or any derivative beyond one image thumbnail variant.
- Retention/purge jobs.
- Changes to `photo.rb`, `order_url.rb`, or the delivery pipeline.
- Anything touching account classification, order type keys, or `MARGIN_LTV_*` constants.
- Rails or Angular version changes.

## 6. Evidence requirements

Every claim in Phase 0 carries file:line. Every "there is no X" claim carries the grep command used. Counts are numbers, not "several". Where two approaches are viable, argue the case against the one you recommend before recommending it.