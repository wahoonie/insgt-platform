# Staff notifications — slice 1: same-day upload alerts via SMS

**Decisions:** six points the survey found the prompt's contract could not hold against the repo are listed under "Decisions taken" at the end, as D1–D6, with Dan's answers of 2026-10-08. All six are folded through the document: **D1** renames the table to `outbound_notifications` and makes it one row per (event, recipient); **D2** schedules the 15:30 Pacific sweep with sidekiq-cron; **D3** gives the delivery worker `retry: 3`; **D4** pins the service by id constant; **D5** resolves recipients from the `system_owner` role; **D6** types `delivered_at` as `datetime`. The write-back carries them into `docs/architecture/staff-notifications.md` v1.0 as the amended §C2, §C4, §C5 and §C7.
**Repos:** `insgt-api` for every code change. Platform repo for the write-back (architecture document, codebase notes, runbook). Two branches, two sets of commits.
**Contract:** §C1–§C7 of the slice prompt (there is no design document yet), as amended by D1–D6. Every gap the prompt names (1–7) is pinned under "Pinned gaps" with the rule chosen and the alternative rejected.
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Status:** Plan, 2026-10-08. Nothing implemented. Gates per the prompt: after plan (this document); after verification.
**Survey date:** 2026-10-08, against `insgt-api` `master` at **70c3f4e3** (tree clean) and the dev database (production restore). Three read-only survey passes (upload path and order model; Twilio, scheduler and config; collisions, migrations and specs) plus targeted reads and read-only `rails runner` queries. Every `file:line` below was read at that SHA. Paths are `apps/insgt-api/` unless prefixed; facts from the restore are labelled **data**.

---

## Context

Insight Photos sells "Same Day Delivery" (service id 35) as an upsell: the shoot happens today and the agent gets media by 8pm Pacific. Today the two owners have no signal when a photographer's zip lands (so processing can start) or when 15:30 arrives with nothing uploaded (so someone can chase the photographer). This slice adds two staff-only SMS alerts through the existing Twilio sender, backed by a new `outbound_notifications` table whose unique index is the dedupe. Nothing existing changes shape; the only visible effect is new texts to the owners.

## Survey findings that changed the prompt's assumptions

1. **`notifications` / `Notification` already exist** (`app/models/notification.rb:1`, `db/schema.rb:562-592`, routes at `config/routes.rb:145`): the legacy template-driven customer notifications, with `notification_audiences` and `order_logs.notification_id` hanging off them. → **D1:** `outbound_notifications` / `OutboundNotification`, one row per (event, recipient), polymorphic `recipient` (a User), `to`, `provider_message_id`, `error`; `delivery_meta` is gone.
2. **No Twilio wrapper class and no SMS worker exist.** Twilio is called inline from `Notification#send_to_message_service` (`app/models/notification.rb:175-216`): `Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])` at :196, `from: ENV['TWILIO_NUMBER'].split(',').sample` at :192, **sends only when `Rails.env.production?`** (:193; logs the message otherwise at :209), `rescue StandardError` → order log + `Notifier.send_error_email` (:212-215). `lib/auth.rb` is Twilio Verify only. The spec that stubs this path is `spec/models/notification_send_to_message_service_spec.rb:38, 53-61`. → The delivery worker copies the client construction, the `from` expression, the production guard and the ops error email.
3. **No scheduler gem.** `Gemfile:33` has sidekiq `~> 7.0` (7.3.10 in the lock); nothing cron-like. Recurring work is rake tasks on Heroku Scheduler, UTC only (`docs/ops/metrics-recompute-cron.md:5`, `lib/tasks/scheduler.rake`, `Procfile` `backgroundworker: bundle exec sidekiq -c 4`). → **D2:** sidekiq-cron. Verified against the gem's README and RubyGems on 2026-10-08: 2.4.0 (released 2026-05-06) depends on `sidekiq >= 6.5.0`; auto-loads `config/schedule.yml` on Sidekiq server boot (`cron_schedule_file`, ERB supported); accepts a zone inside the cron line (`'0 22 * * 1-5 America/Chicago'`); parses with Fugit.
4. **Every worker is `retry: false`** (all 16 files in `app/workers/`; `CLAUDE.md:107` states it as the convention). → **D3:** `retry: 3` for the delivery worker, idempotent per row.
5. **`services` has no key column** (`db/schema.rb:1070-1092`: `name`, `cart` jsonb, `icon`…). The repo pins services by id constant (`app/models/service.rb:18` `BUNDLE_DISCOUNT_ID = 86`, `:22` `CANCEL_AT_DOOR_ID = 16`). "Same Day Delivery" is seeded as id 35 (`service.rb:66`); **data:** it is the only service whose name contains "same". → **D4:** `Service::SAME_DAY_DELIVERY_ID = 35`.
6. **Recipients are Users under D1**, so §C7's env list of E.164 numbers cannot hold: a bare number has no User behind it. → **D5:** active users holding `Role.system_owner` (`app/models/role.rb:286-288` `system_owner_role_id`, which raises if the role row is missing; system roles live in `accounts_users`, `role.rb:115-122`; `User has_many :accounts_users` active-scoped at `user.rb:7`). `to` is frozen from `user.primary_phone_number.text_message_format` (`user.rb:246-248`; `phone_number.rb:175-177`, Phoner E.164 `+1…`). **No new env var.**
7. **`delivered_at`**: every datetime column in the schema is `timestamp without time zone` written as UTC (`ActiveRecord.default_timezone == :utc`; `config/application.rb:29` leaves `config.time_zone` commented out). → **D6:** `t.datetime`.

## Pinned gaps (prompt §Gaps 1–7)

**Gap 1 — "upload confirmed complete" is `PUT /orders/:token/queue`.** The photographer uploads a zip straight to S3 (`AwsCredentials`, `app/services/aws_credentials.rb:17-24`; `orders_controller.rb:36-55`). The Lambda `functions/insgt-photographer-uploader` is triggered by `s3:ObjectCreated:*` with suffix `.zip` (`serverless.yml`, `functions.queue.events`), so it runs only once the bytes exist. It head-checks and copies the object (`handler.js:84-93`: `queueFile` pushes to `successFiles` only after `copyLargeObject`, which opens with `s3.headObject`), then `PUT ${API}/orders/${token}/queue` with `{files, errors}` (`handler.js:307-318`). API side: `config/routes.rb:207` → `ProcessingQueuesController#update` (`app/controllers/processing_queues_controller.rb:30-33`) → `OrderImageHandlerQueue.queue` (`lib/order_image_handler_queue.rb:3-14`), which appends to `orders.processing_queue->'queue_files'` (jsonb, `db/schema.rb:772`; **data:** 0 NULL rows). Nothing else writes `queue_files` (`grep -rn 'queue_files\s*=' app lib` → empty), and the `delete 'queue'` route (`routes.rb:209`) points at a `destroy` action that does not exist, so the list is append-only in practice. **The hook goes at the end of `OrderImageHandlerQueue.queue`, only when `files` is non-empty; `queue_error` never fires it.** Presigned-URL issuance (`orders_controller.rb:48-55`) and `POST queue` (the lookup, `processing_queues_controller.rb:8-25`) are not touched. Rejected: an S3 HEAD in the API (the Lambda already did one) and hooking the controller (the lib method is the single write path).

**Gap 1b — parent and child orders (not in the prompt; the data forced it).** **data:** 266 active `order_services` rows for id 35: 250 on parents, 16 on children whose parents do *not* carry it and whose `scheduled_at` differs from the parent's (separate jobs on later days). Of the 250 parents, 74 have active children; uploads landed parent-only 11, parent+child 35, child-only 1, none 27; 73 of 74 have a photographer on both parent and child. 48 orders in the table nest deeper than one level. **Rule:** the *subject* of both events is the nearest of `[order, order.parent]` that carries the service (`Order#same_day_delivery_job`); uploads are counted on the subject **and its direct children**. Grandchildren are out of scope (48 rows ever; documented in the codebase notes).

**Gap 2 — service identity:** `Service::SAME_DAY_DELIVERY_ID = 35`, in this slice, as its own commit (D4). A `services.key` column stays a possible later slice; it would be a four-migration NOT NULL sequence like `order_types.key` (`db/migrate/20260828120000..4`) and is not needed here.

**Gap 3 — §C3.3 state set.** There is no delivery enum. `orders.status_type` is soft-delete only; cancellation and lifecycle live in `orders.order_event_id` (`db/schema.rb:718`), a cache of the last `sticks_to_order` event (`order_log.rb:4-6`), read via `Order#event?` (`order.rb:1284-1286`) and `OrderEvent.canceled_id` (`order_event.rb:29-31`). Sticky events by `sequence` (**data**): seq 0 = pending_scheduler, raw_uploads_ready, photographer_confirmation, created, scheduling, photographer_confirmed, photographer_declined, manual_email_submission, pending_alternate_payment, shoot_requested, client_confirmed, pending_photographer_confirmation, **canceled**; then scheduled(1), shot(2), pending_processing(3), actively_processing(4), pending_review(5), **completed_processing(6), pending_checkout(7), paid(8), completed(9)**.
- **Excluded:** `canceled`, `completed_processing`, `pending_checkout`, `paid`, `completed`, plus `status_type != active`. Processing is finished at `completed_processing`; a first upload after that is a replacement, not a start. **data:** 0 orders sit at seq 6–8 with a future `scheduled_at`, so these tags never represent a pre-shoot state; 81 orders scheduled in the last 90 days reached 6/7/9 with zero zips (agent-supplied media), which is exactly the population this exclusion is for.
- **Included:** NULL `order_event_id` and every other tag, including `pending_review` (a new upload can still feed re-processing) and the seq-0 payment tags (**data:** two recent same-day orders with uploads sit at `pending_alternate_payment`).
- §C4 applies only `canceled` + active (per §C4.3), not the processing set.

**Gap 4 — shoot date column:** `orders.scheduled_at`, `t.datetime … precision: nil` (`db/schema.rb:729`) = `timestamp without time zone`, written as UTC. Comparison: convert the Pacific calendar day to a UTC instant range and query `scheduled_at` against it (DST-safe, index-friendly, no `AT TIME ZONE` string handling). Ruby side: `BusinessTimeZone.date_of(scheduled_at) == BusinessTimeZone.today`. NULL `scheduled_at` never matches. **data:** real same-day first uploads over the last 120 days arrived between 10:27 and 17:20 Pacific, and shoots start 09:00–13:00 Pacific, so the Pacific day and the UTC day disagree for none of them, but the straddle cases in the spec plan are still the rule.

**Gap 5 — scheduler:** sidekiq-cron 2.4.0, entry `"30 15 * * * America/Los_Angeles"` in `config/schedule.yml`, auto-loaded by the `backgroundworker` Sidekiq process (D2). Zone-awareness is proven by a spec that runs Fugit across both DST transitions (below). Heroku Scheduler is not used for this; the schedule travels with the code, which also survives the planned Render move.

**Gap 6 — business time zone:** none exists (`grep -rnE "America/Los_Angeles|Pacific|business_time_zone" app lib config` → only the `users.time_zone` column default in `db/schema.rb:1226` and `Time.zone =` swaps in `app/helpers/orders_csv_helper.rb:79` / `lib/app_param.rb:30`; `order.rb:411-412` and `lib/order_export.rb:112` use `User.find(2).time_zone` as a stand-in). New: `lib/business_time_zone.rb` (lib is autoloaded, `config/application.rb`) — `BusinessTimeZone::NAME = 'America/Los_Angeles'`, `.zone` (`ActiveSupport::TimeZone[NAME]`), `.now` (`zone.now`), `.today` (`zone.today`), `.date_of(time)` (`time.in_time_zone(zone).to_date`). No `Time.now`, `Date.today`, `Date.current` or `Time.zone.*` anywhere in the slice; instants (`delivered_at`) use `Time.current`.

**Gap 7 — recipient config:** none (D5). Recipients = `User.active.joins(:accounts_users).where(accounts_users: { role_id: Role.system_owner_role_id }).distinct`, each paired with `primary_phone_number&.text_message_format`; a user without an active primary phone is skipped with `Rails.logger.error` and gets no row (`to` is NOT NULL). §C7 is amended accordingly, and the runbook states that granting `system_owner` adds a text recipient.

**Other pins.** Order identifier in the body is `order.token` (what every insgt-ops URL uses, e.g. `insgt-ops/src/app/scheduler/order/scheduler-order.component.ts:373`; a hashid with no digit run, so no phone-pattern risk). Address via `Property.human_readable_address(order.property)` (`property.rb:297-306`, no zip, `''` for no property). Agent via `Account.name_for(order.account)` (`account.rb:568-570`). Photographer via `order.photographer` (`order.rb:1234-1236`, an `OrdersUser` delegating `first_name`/`last_name`, `orders_user.rb:16-21`), "none assigned" when nil. Time format `%-l:%M%P` → `2:14pm`. The hook **never raises into the request**: a 500 on `PUT queue` makes the Lambda record an error and quarantine the zip (`handler.js:49-55`), so the hook rescues `StandardError`, logs, and lets the upload record stand. This is a deliberate exception to the `insgt-api` skill's "don't rescue and swallow inside the service", taken at the call site and commented there.

## Design

### Schema — `db/migrate/<ts>_create_outbound_notifications.rb`

`def change` with `create_table` and the index inside it, copying `db/migrate/20260521120001_create_system_metrics.rb` (the newest create_table; strong_migrations permits an index on a brand-new table, and `StrongMigrations.start_after = 20260806120000` at `config/initializers/strong_migrations.rb:7` means this is the first create_table it will check). Columns exactly as D1's §C2. No `status_type`, no CrudAttribution columns: the precedent for new tables is `system_metrics` and `account_metrics`, neither of which has them.

| column | migration |
|---|---|
| `event_type` | `t.integer :event_type, limit: 2, null: false` |
| `subject` | `t.references :subject, polymorphic: true, null: false, index: false` |
| `recipient` | `t.references :recipient, polymorphic: true, null: false, index: false` |
| `channel` | `t.integer :channel, limit: 2, null: false` (no default) |
| `to` | `t.string :to, null: false` |
| `body` | `t.text :body, null: false` |
| `delivered_at` | `t.datetime :delivered_at` |
| `provider_message_id` | `t.string :provider_message_id` |
| `error` | `t.text :error` |
| timestamps | `t.timestamps` |
| index | `unique: true` on `%i[event_type subject_type subject_id recipient_type recipient_id]`, name `index_outbound_notifications_unique_per_recipient` |

`db/schema.rb` is the schema file (no `structure.sql`). Rolling-deploy windows: old code never touches the table (safe); new code on the old schema hits the hook's rescue (a missed alert, the upload record intact) and the sweep worker's retry → ops email. Runbook: push, migrate immediately.

### Model — `app/models/outbound_notification.rb`

`belongs_to :subject, polymorphic: true`; `belongs_to :recipient, polymorphic: true` (the first Rails `polymorphic:` associations in the repo; every older pair is hand-rolled `resource_id` + `resource_type`, `app/models/concerns/resource_owned.rb:5`); `enum :event_type, { same_day_upload_started: 1, same_day_no_upload: 2 }, prefix: true`; `enum :channel, { sms: 1 }, prefix: true` (pattern `order_type.rb:87-88`; `insgt-api` skill §3); presence validations on `event_type`, `channel`, `to`, `body`. ARCHITECTURE NOTES: the integers are the contract; the unique index is the only dedupe; rows are append-only; no `status_type` by design, so `ApplicationRecord.active` must not be called on it.

### Constant — `app/models/service.rb`

`SAME_DAY_DELIVERY_ID = 35` with a why-comment beside `CANCEL_AT_DOOR_ID` (`service.rb:20-22`).

### Order — `app/models/order.rb` (new scopes beside `pending_shoots`, `:176-196`)

- `scope :with_same_day_delivery` → `where(id: OrderService.where(service_id: Service::SAME_DAY_DELIVERY_ID, status_type: StatusType.active).select(:order_id))` (shape of `lib/tasks/orders.rake:786-790`; no Order scope joins services today).
- `scope :scheduled_on_business_date, ->(date)` → `day_start = BusinessTimeZone.zone.local(date.year, date.month, date.day)`; `where(scheduled_at: day_start.utc...(day_start + 1.day).utc)` (`TimeWithZone#+ 1.day` keeps local midnight across DST).
- `scope :not_canceled` → the predicate inlined at `order.rb:195`, verbatim. `pending_shoots` is **not** refactored to use it: account-classification code stays untouched by this slice; noted for a later cleanup.
- `scope :without_confirmed_uploads` → `jsonb_array_length(COALESCE(orders.processing_queue->'queue_files','[]'::jsonb)) = 0` AND `NOT EXISTS` an active child (`children.parent_id = orders.id`) with a non-empty list.
- `def same_day_delivery_job` → the first of `[self, parent].compact` whose id is in `Order.with_same_day_delivery`, else nil.

### Services — `app/services/staff_notifications/` (namespace precedent: `AccountMetrics::`)

- `Dispatcher.new(event_type:, subject:, body:, channel: :sms).call` → one row per recipient (integers via `OutboundNotification.event_types.fetch` and `channels.fetch`, so no reliance on `insert_all` casting), `OutboundNotification.insert_all(rows, unique_by: :index_outbound_notifications_unique_per_recipient, returning: %w[id])`, `OutboundNotificationDeliveryWorker.perform_async(id)` **only for the ids the insert returned**, returns those rows. `Dispatcher.recipients` is the role query from Gap 7. No `find_by` pre-check, no lock (trap 3). Precedent for a model-adjacent enqueue: `transaction.rb:108, 117`.
- `OrderLine.new(order).to_s` → `"<token>, <address>. Agent: <name>. Photographer: <first last | none assigned>."`, shared by both events.
- `SameDayUploadStarted.new(order).call` → `job = order.same_day_delivery_job`; nil unless job, `job.active?`, `BusinessTimeZone.date_of(job.scheduled_at) == BusinessTimeZone.today`, not `event?(:canceled)`, `order_event&.tag` ∉ `CLOSED_EVENT_TAGS = %w[completed_processing pending_checkout paid completed]`; body `"Same-day upload started <h:mmpm>: <OrderLine> Deliver by 8pm today. - InsightPhotos"`; `Dispatcher…call`.
- `SameDayNoUpload.new(date:).call` → `Order.active.with_same_day_delivery.scheduled_on_business_date(date).not_canceled.without_confirmed_uploads.find_each`; per order: body `"Same-day NO UPLOAD as of <h:mmpm>: <OrderLine> Shoot <h:mmpm>. Deliver by 8pm today. - InsightPhotos"`, `Dispatcher…call`; a per-order `rescue StandardError` logs and continues (the `AccountMetrics::RecomputeAll` posture). Never reads `outbound_notifications` (trap 6).

### Hook — `lib/order_image_handler_queue.rb`

After the `files.each` loop in `queue`: `notify_same_day_upload_started(order) if files.present?`, a private class method wrapping `StaffNotifications::SameDayUploadStarted.new(order).call` in `rescue StandardError => error` → `Rails.logger.error("[OrderImageHandlerQueue] same-day alert failed for Order##{order.id}: #{error.class} — #{error.message}")`. `queue_error` unchanged. Existing `Time.now.to_i` lines in that file are untouched.

### Workers — `app/workers/` (pure `Sidekiq::Worker`; pattern `charge_customer_association_worker.rb:27-39`; no `app/jobs/` exists)

- `OutboundNotificationDeliveryWorker` — `sidekiq_options retry: 3` (D3). `perform(id)`: `find_by` → return if missing; return if `provider_message_id.present?` (idempotent on retry); unless `Rails.env.production?` → `update!(error: 'not sent: non-production environment')`, log the body, return; else `Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']).messages.create(body:, to:, from: ENV['TWILIO_NUMBER'].split(',').sample)` → `update!(provider_message_id: result.sid, delivered_at: Time.current, error: nil)`; `rescue StandardError => e` → `update!(error: "#{e.class}: #{e.message}")`, `Rails.logger.error`, re-raise so Sidekiq retries. `sidekiq_retries_exhausted` → `Notifier.send_error_email('Staff SMS failed', …)` (`app/mailers/notifier.rb:51-55`). ARCHITECTURE NOTES: why `retry: 3` here when every other worker is `retry: false`; why Twilio is called here and never from a model or service (trap 10); no `sleep`/status fetch, because §C2 defines delivery as provider acceptance.
- `SameDayNoUploadSweepWorker` — `sidekiq_options retry: 3` (idempotent via the index; a failed 15:30 sweep is the one worth retrying); `perform` → `StaffNotifications::SameDayNoUpload.new(date: BusinessTimeZone.today).call`.

### Schedule — `Gemfile` + `config/schedule.yml`

`gem 'sidekiq-cron', '~> 2.4'` next to sidekiq (`Gemfile:33-34`); `bundle install` updates the lock. `config/schedule.yml`:

```yaml
same_day_no_upload_sweep:
  cron: "30 15 * * * America/Los_Angeles"
  class: "SameDayNoUploadSweepWorker"
  description: "Staff SMS for same-day orders with no confirmed upload by 15:30 Pacific"
```

No initializer expected (the gem auto-loads the file on server boot); confirm the auto-require name from the installed gem when adding it, and fall back to a one-line wiring initializer only if auto-load does not happen.

### Docs touched in the api repo

`CLAUDE.md:107` ("all disable retries") names the two exceptions. `README.md` scheduler section (`:144-151`) gets a sidekiq-cron line and loses the stale `rake send_notifications` name only if touched anyway.

## Spec plan (red → green → deliberate break for each unit)

Helpers to reuse: `jwt_headers_for(user)` (`spec/support/auth_helpers.rb:6`); roles seeded by `spec/support/roles.rb` (`system_owner` included); `AccountsUser.create!(user_id:, account_id:, role_id: Role.find_by!(tag:).id, status_type: 1, created_by_id: 1)` (`spec/models/account_update_authorization_spec.rb:26`); `create(:phone_number, resource_id: user.id)` (`spec/factories/phone_numbers.rb` yields `+1760440xxxx`, obviously fake — trap 9); `create(:order_service, order:, service:)` (`spec/factories/services.rb:15-22`) with a service whose id is `Service::SAME_DAY_DELIVERY_ID`; `OrdersUser.create!(… role_id: Role.system_photographer.id …)` (`spec/requests/phone_numbers_spec.rb:506-508`); `include ActiveSupport::Testing::TimeHelpers` + `travel_to` (`spec/models/order_log_spec.rb:6, 25`); Twilio doubles and `stub_rails_env('production')` as in `notification_send_to_message_service_spec.rb:46-61`; `Worker.jobs` under `Sidekiq::Testing.fake!` (`spec/support/sidekiq.rb`).

Boundary instants (trap 4), used wherever "today" is decided: `2026-10-09T05:30:00Z` is Oct 8 Pacific (counts on Oct 8); `2026-10-08T06:59:00Z` is Oct 7 (does not); DST end `2026-11-01`: `2026-11-02T07:30:00Z` is Nov 1 23:30 PST (counts on Nov 1), `2026-11-01T06:59:00Z` is Oct 31 23:59 PDT (does not); DST start `2027-03-14`: `2027-03-15T06:30:00Z` is Mar 14 23:30 PDT (counts), `2027-03-14T07:59:00Z` is Mar 13 23:59 PST (does not).

| spec file | examples |
|---|---|
| `spec/lib/business_time_zone_spec.rb` | `NAME`; `today` / `date_of` for the six instants under `travel_to`; `zone.now` offset flips across both DST dates |
| `spec/models/outbound_notification_spec.rb` | `event_types == {'same_day_upload_started'=>1,'same_day_no_upload'=>2}`, `channels == {'sms'=>1}`; prefixed predicates only (`not_to respond_to(:sms?)`); unknown value → `ArgumentError`; nil channel → invalid; duplicate (event, subject, recipient) → `ActiveRecord::RecordNotUnique`; same event + subject, different recipient → allowed |
| `spec/models/order_same_day_spec.rb` | `with_same_day_delivery`: active service 35 in / soft-deleted `order_service` out / other service out; `scheduled_on_business_date` on the six instants; `not_canceled`: NULL in, scheduled in, canceled out; `without_confirmed_uploads`: no files in, own file out, child file out, soft-deleted child's file ignored; `same_day_delivery_job`: self, parent, child-with-own-service → self, none → nil |
| `spec/services/staff_notifications/dispatcher_spec.rb` | one row per `system_owner` with a phone; `to` is the E.164; `recipient` is the User; `body` frozen; owner without phone skipped and logged; non-owner never a recipient; second call → `[]`, row count unchanged, no new job; jobs == rows; **concurrency** (trap 3): group with `self.use_transactional_tests = false` (`spec/rails_helper.rb:48` has transactional fixtures on), two threads behind a `Queue` barrier calling `Dispatcher` for the same subject, assert rows == recipients and `OutboundNotificationDeliveryWorker.jobs.size == recipients`, `after { OutboundNotification.delete_all }` |
| `spec/services/staff_notifications/same_day_upload_started_spec.rb` | nil when no service / not today (four straddle instants) / canceled / each of the four closed tags / soft-deleted (trap 7); rows for `scheduled`, `pending_processing`, `pending_review`, NULL event; subject is the parent when the service is on the parent and the upload hits the child; body contains token, address, agent, photographer, `/\d{1,2}:\d{2}[ap]m/`, `8pm`, ends `- InsightPhotos`; body matches neither `%r{https?://}` nor `/(\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}/` nor `/\d{7,}/` (trap 1); "none assigned" without a photographer; repeat call → no new row |
| `spec/services/staff_notifications/same_day_no_upload_spec.rb` | picks today's same-day, active, not-canceled, zero-upload orders; excludes own upload, child upload, canceled, yesterday/tomorrow by the straddle instants, soft-deleted; **includes an order that already has a `same_day_upload_started` row but zero files** (pins "uploads, not notifications", trap 6); one order raising does not stop the others; body shape as above |
| `spec/lib/order_image_handler_queue_spec.rb` | `queue` with files → `SameDayUploadStarted` invoked once; empty files → not; `queue_error` → not (trap 2); a raising service → logged, `queue` still returns true and the file is still recorded |
| `spec/requests/processing_queues_spec.rb` | `PUT /orders/:token/queue` with `jwt_headers_for` on a same-day order today → 200, files recorded, rows == owners, jobs enqueued; second PUT → no new rows; non-same-day order → no rows |
| `spec/workers/outbound_notification_delivery_worker_spec.rb` | `sidekiq_options['retry'] == 3`; production: `messages.create` receives `body/to/from`, row gets SID + `delivered_at`, `error` nil; already-sent row → Twilio not called; Twilio raises → `error` recorded and re-raised; non-production → Twilio not called, `error` note; missing row → no raise; retries-exhausted block emails ops |
| `spec/workers/same_day_no_upload_sweep_worker_spec.rb` | calls the service with `BusinessTimeZone.today`; `retry == 3` |
| `spec/config/schedule_spec.rb` | loads `config/schedule.yml`; entry class constantizes to a Sidekiq worker; cron ends with `America/Los_Angeles` (trap 5); `Fugit.parse_cron(cron).next_time(from)` in UTC: from `2026-10-31T00:00Z` → `22:30Z` (PDT), from `2026-11-01T00:00Z` → `23:30Z` (PST), from `2027-03-13T00:00Z` → `23:30Z`, from `2027-03-14T00:00Z` → `22:30Z` |
| `spec/architecture/staff_notifications_spec.rb` (write-back) | the pinned integers; the unique index columns via `connection.indexes('outbound_notifications')`; `Service::SAME_DAY_DELIVERY_ID == 35`; `BusinessTimeZone::NAME`; the closed-tag set; the schedule zone; the body regex invariants |

Deliberate breaks to show red: renumber an enum (model spec); swap `...` for `..` on the day range (scope spec); drop `canceled` from the guard (service spec); remove the `America/Los_Angeles` suffix (schedule spec); make the dispatcher enqueue for every row rather than for inserted rows (dispatcher spec).

## Commit sequence (insgt-api, branch `feat/staff-notifications-1` off `master`)

1. `feat: add BusinessTimeZone helper` — lib + spec.
2. `feat: add outbound_notifications table and model` — migration, model, spec. `migrate` / `rollback` / `migrate`; paste the `db/schema.rb` diff. (Migrations are run by Dan: `rails db:*` is denied in this container; STOP and ask at this step.)
3. `feat: pin the same-day delivery service id` — `Service::SAME_DAY_DELIVERY_ID`.
4. `feat: add same-day delivery scopes to Order` — four scopes + `same_day_delivery_job` + spec.
5. `feat: add OutboundNotificationDeliveryWorker` — worker + spec + the `CLAUDE.md` retry sentence. Tier 2 body: why `retry: 3` here.
6. `feat: dispatch staff notifications to system owners` — `Dispatcher`, `OrderLine`, specs including concurrency.
7. `feat: alert staff when a same-day upload starts` — `SameDayUploadStarted`, hook, lib spec, request spec. Tier 3 body (trigger 1): the hook sits in `lib/order_image_handler_queue.rb` because `PUT queue` is the only post-bytes signal, and it must never 500 because the Lambda quarantines on error.
8. `build: add sidekiq-cron` — Gemfile + lock, README line.
9. `feat: alert staff at 15:30 Pacific on same-day orders with no upload` — `SameDayNoUpload`, sweep worker, `config/schedule.yml`, specs. Tier 2 body: the zone lives in the cron line; the Fugit spec is the DST proof.
10. `test: add staff notifications contract spec` (write-back).

Platform repo, branch `docs/staff-notifications-1` off `main`: `docs: add staff notifications architecture v1.0` — `docs/architecture/staff-notifications.md` (§C1–§C7 verbatim, then D1–D6 and the pinned gaps as the v1.0 amendments, a change log in the `account-classification.md` style), `docs/architecture/staff-notifications-codebase-notes.md` (flat `file:line` table), `docs/runbooks/deploy-staff-notifications-1.md`.

Per the memory rules: branches and commits only, never merge into the default branch (`master` in insgt-api, `main` here), never push, no `Co-Authored-By` trailer. Every new identifier in this document (`OutboundNotification`, `outbound_notifications`, `BusinessTimeZone`, `SAME_DAY_DELIVERY_ID`, the four scopes, `same_day_delivery_job`, both worker names, `StaffNotifications`, `schedule.yml`, `sidekiq-cron`) greps to zero hits in `app lib config db spec Gemfile*` at 70c3f4e3.

## Post-deploy verification

Also run against the dev DB after the implementation loop, where delivery is stubbed by the production guard and the row records `error: 'not sent: non-production environment'`.

```bash
heroku run rails runner '<line>' --app insgtapi
```

| check | expected (reasoned before the code exists) |
|---|---|
| `OutboundNotification.event_types; OutboundNotification.channels` | `{"same_day_upload_started"=>1,"same_day_no_upload"=>2}`; `{"sms"=>1}` |
| `StaffNotifications::Dispatcher.recipients.size` | 2 (the owners, §C1); each `to` starts `+1` and is 12 characters |
| `BusinessTimeZone.date_of(Time.utc(2026,10,9,5,30))` / `(…,10,8,6,59)` | `2026-10-08` / `2026-10-07` |
| `Order.with_same_day_delivery.count` | ≈266 (restore of 2026-10-08: 250 parents + 16 children; production may be a few higher) |
| `Order.active.with_same_day_delivery.scheduled_on_business_date(BusinessTimeZone.today).not_canceled.without_confirmed_uploads.pluck(:id)` | the list ops sees as today's same-day orders with no files |
| fire: `StaffNotifications::SameDayUploadStarted.new(Order.find_by_token_or_id('<today's same-day token>')).call` | 2 rows returned; within ~10 s each has `provider_message_id =~ /\ASM/`, `delivered_at` set, `error` nil; paste the received text into the report |
| fire again | `[]`; row count still 2 |
| `Sidekiq::Cron::Job.all.map { [_1.name, _1.cron, _1.klass] }` | includes `["same_day_no_upload_sweep", "30 15 * * * America/Los_Angeles", "SameDayNoUploadSweepWorker"]`; next enqueue 22:30 UTC while PDT |

Runbook order: `git push heroku` → `heroku run rake db:migrate` immediately → confirm `backgroundworker` restarted (sidekiq-cron registers the schedule on boot) → the checks above. No env var to set.

## Risks

- **Hook inside the Lambda's request path.** Mitigated by the rescue; the spec that a raising service still records the file is the guard. Worth a review eye regardless.
- **`bundle install` needs network** in the container for commit 8; if it fails, STOP rather than hand-edit the lockfile.
- **sidekiq-cron require name and auto-load** — read the installed gem's README at commit 8 rather than trusting the fetched summary.
- **Concurrency spec** runs outside the transactional fixture and must clean up; it may surface that `Sidekiq::Testing` job arrays are not thread-synchronised. If flaky, assert the row count only there and cover "enqueue only inserted ids" in the sequential example.
- **Role-based recipients** mean a future `system_owner` grant adds a text recipient silently; the runbook states it.
- **Sticky-state cache**: `order_event_id` is maintained by `log_event` (`order_log.rb:156` keeps `completed` from being overwritten), so the exclusions hold; an order whose cache lags could be alerted once. Acceptable for an advisory text.
- **Pre-existing, untouched:** `processing_queues#destroy` route with no action (`routes.rb:209`); `ImportProcessedPhotosWorker.perform_async` at `order.rb:486` refers to a class with no file; the Lambda's `successFiles` accumulates across orders within one S3 event (`handler.js:33-57`). Noted in the codebase notes, not in scope.
- **Unverified:** the real `system_owner` user list and their phone rows could not be read during planning (the runner query was denied); the "2 recipients" expectation rests on §C1 and is checked first at verification.

## Decisions taken

| # | Question the survey raised | Dan's answer, 2026-10-08 |
|---|---|---|
| D1 | `notifications` / `Notification` already exist. Name? | `outbound_notifications` / `OutboundNotification`, and §C2 rewritten to one row per (event occurrence, recipient): `recipient_type`/`recipient_id` polymorphic NOT NULL (a User), `to` string NOT NULL frozen at creation, `body`, `delivered_at`, `provider_message_id` nullable (Twilio SID), `error` text nullable; unique index on (event_type, subject_type, subject_id, recipient_type, recipient_id); insert-tolerates-conflict, one send job per inserted row |
| D2 | No scheduler gem; Heroku Scheduler is UTC-only. How to run 15:30 Pacific? | Add sidekiq-cron |
| D3 | §C2 says Sidekiq retry; all 16 workers are `retry: false`. | `retry: 3`, idempotent per row, ops email on exhaustion |
| D4 | `services` has no stable key. | `Service::SAME_DAY_DELIVERY_ID = 35` |
| D5 | Recipients are Users under D1; §C7's E.164 env list cannot hold. | Active users holding the `system_owner` role; `to` from the primary phone |
| D6 | §C2 says `timestamptz`; every column in the schema is `timestamp without time zone`. | `datetime`, like every other column |
