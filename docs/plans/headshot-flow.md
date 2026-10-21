# Headshot flow — stamp the event date on new event orders

**Status:** Draft. Decisions 1–3 taken by Dan on 2026-10-19; decision 4 is this plan's and awaits approval with the rest.
**Repo:** `insgt-api`. Platform repo for the write-back only. No insgt-ops or insgt-app change.
**Contract:** `docs/architecture/account-classification.md` v14 — §5.3 (`Order.shoot_date_sql`, `app/models/order.rb:211–228`), §5.5 (`:1135–1274`; the dating bullet `:1161–1168`; the ROI rules `:1237–1259`), §20's follow-ons (`:2031–2037`). Plan `account-classification-slice-6.md` OQ1 (`:509–514`) and Out of scope 2 (`:43`).
**Skills:** `slice-implementation`, `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Surveyed against:** insgt-api `master` b7b2de9f, whose working tree carries an uncommitted `config/application.rb` change that is not part of this work; the dev restore, latest order 2026-10-19 16:24 UTC. Every count below is from that restore on 2026-10-19 and carries its query in the appendix.

## Why

`OrderHeadshot.find_order_for_account` (`lib/order_headshot.rb:45–53`) builds every attendee's headshot order with `account_id`, `marketing_event_id` and `order_type_id` only. All 2,668 active event orders have `orders.scheduled_at` NULL (Q1), so `Order.shoot_date_sql` dates attendance by the first completed log, which is the delivery date. Ops creates these orders after the event, never on the day: of the 766 created since 2025, 741 came 1–7 days after it and 24 came 7–30 days after (Q2). Most are completed in the same pass, 624 of the 766 within an hour of creation (Q3).

An agent whose first paid listing shoot falls inside that lag reads as having bought first. `EventAttribution` marks the account `skip_after_buying` and never credits the host, and `HeadshotHostRoi` counts it as an already customer, never a convert. The 6b memo prints the NULL-source cases under "credited only under the event date": 996, 1467 and 1516, two of them NSDCR writes not made (Q4). Already-sourced fast converts are not in that line but are miscounted by the ROI the same way: 11944 attended event 1201 on 2026-05-01, shot its first paid listing on 05-06, received the headshot on 05-08, and counts as an already customer (Q4, Q5).

The contract's dating rule stays as written (OQ1). What changes is the input: new event orders carry the event's date, so `Order.shoot_date_sql` returns it. Slice 7 pushes Origin (`marketing_source_id`) to Pipedrive, so this lands first and Pipedrive starts from the better attribution.

## Decisions (Dan, 2026-10-19)

1. **Stamp and gate.** `OrderHeadshot` stamps `orders.scheduled_at` on new event orders, and one predicate keeps attendance orders off the four booking readers below. Rejected: stamping without the gates, because ops would see every attendee order on its calendar, daily tasks and weekly KPIs. Also rejected: leaving `scheduled_at` NULL and giving `Order.shoot_date_sql` a middle arm on `marketing_events.scheduled_at`. That has no reader side effects and is retroactive, but it reverses OQ1's form, changes §5.3's one definition, and re-dates 2,668 orders at once.
2. **An attendee is still a delivered order, now tested explicitly.** `EventAttribution.event_orders_sql` dates an event order only when `Order.completed_log_sql` holds. Today "undelivered" and "NULL shoot date" coincide only because `scheduled_at` is NULL; a stamp would break that for new orders. Rejected: letting a stamped undelivered order count as attendance, which retires pending release for new orders and needs §5.5's attendee rule reworded.
3. **No backfill of the 2,668 historical orders in this slice.** Recorded as an optional follow-on, cheap once the gates exist. 1467 and 1516 can be set by hand in ops as scheduler-set sources (§5.5 `:1219–1224`); 996's host has no source. The memo's "credited only under the event date" line keeps measuring the historical population.

## Decision pinned by this plan

4. **The stamp leaves the order in Created.** `OrderHeadshot` writes the date with `update_columns(scheduled_at:)` right after the create save, only for an order it just created. The stay-at-home flow is the precedent (`app/models/order.rb:1325–1328`). Rejected: passing `scheduled_at` to `Order.new`. The `after_create` path would then log `:scheduling` (`app/models/order_event.rb:127–130`), which sticks to the order (Q6). insgt-app makes timing and options editable to the agent in that state (`apps/insgt-app/src/app/orders/store/order-state-manager.service.ts:40–46`). Most orders complete within the hour, but pending releases sit for days, as event 1433's did. `update_columns` skips callbacks and the audit stamp, which is acceptable here: the row was created by `User.system` a statement earlier, and the one callback that watches `scheduled_at`, `populate_booking_lead_time_metric` (`order.rb:284`), would compute a negative lead time and store nothing.

## What the survey found

### The booking readers

No reader of `orders.scheduled_at` checks `marketing_event_id`. These four treat "has a date" as "is booked", and each would show attendance orders if stamped without a gate.

| Reader | Where | What it filters on | A stamped attendance order, ungated |
| :--- | :--- | :--- | :--- |
| Ops scheduler calendar, `GET /orders?view=scheduler` | date range `app/models/concerns/order_query.rb:293–302`; 500-row page `lib/order_param.rb:134` | Date only. `NOT IN (3,12,19)` (`order_query.rb:247`) applies only when `defaultOrderTypes` is sent, and the calendar does not send it (`insgt-ops/src/app/scheduler/calendar/scheduler-calendar.component.ts:213–237`) | Every attendee order on the event's slot, beside the type 73 container |
| Processors' daily tasks, `GET /orders/processing` | `app/controllers/orders_controller.rb:284–299` | `order_types.generic_photo_processing = true`, which type 3 carries (Q7) | Every attendee order on the event date |
| Photographer app calendar, `view=photographer-scheduler` | `lib/order_param.rb:286–292`, `order_query.rb:336–341` | The photographer's own orders, past created, scheduling and scheduled | On the calendar of user 2, Don, the dialog's default photographer (`insgt-ops/src/app/marketing-events/orders/new-headshot.dialog.ts:112`), once processed |
| Weekly KPIs, `GET /kpis/accounts` and `GET /kpis/order_types` | `app/controllers/kpis_controller.rb:44–67` | Completed or pending alternate payment, dated in the week; no type filter | $0 orders and their lead accounts in total orders, total accounts, first-time accounts and the average order price |

`defaultOrderTypes` is not a usable gate. It is keyed on type, and type 19 Paparazzi orders carry real dates, 51 in 2026 (Q8). The gate is keyed on `marketing_event_id`, because 42 type 3 orders carry no event (Q1).

### Readers left alone

- **`property_work` and everything on it** — `qualifying`, `qualifying_parents`, `pending_shoots`, lifecycle (`order.rb:176–196`). They require category `property`, and no property order carries `marketing_event_id` (Q1).
- **`billable`** (`order.rb:183–189`) includes marketing. 98 type 3 orders are paid (Q9). A stamped paid order's 365-day window moves from the delivery date to the event date, a few days, new orders only.
- **The scheduler's unscheduled sidebar** (`orders_controller.rb:639–646`, `order_query.rb:328–334`). Stamped orders leave it. One type 3 order is there today (Q10). Ops reaches attendance orders from the event's Headshots card, which reads by `marketingEventId` and is unaffected.
- **Outstanding processing** excludes "Free Web Portrait" by name (`orders_controller.rb:237–241`).
- **Public-site feeds** need a commercial property or type 19 (`lib/order_export.rb:10–21`, `:68–77`).
- **Notifications.** None is attached to `scheduling` for type 3 or for any marketing event (Q11), and no template attached to either uses the invoice email, the one template that reads `scheduled_at` without a nil guard (Q12; `app/views/notifier/send_invoice_email.html.erb:19`). With decision 4 no `scheduling` log is written anyway.
- **The default `/orders` sort**, `orders.scheduled_at DESC` (`order_param.rb:136`). Stamped orders sort by event date instead of first among the NULLs. Accepted.

### Facts

- Orders with `marketing_event_id`: type 3 active 2,668, all `scheduled_at` NULL; type 3 deleted 9; type 2 deleted 2. Type 3 active without an event: 42 of 2,710 (Q1).
- Events: 198, 3 without a date (14 Marketing, 31 Aerial Marketing, 35 Glen Oaks Escrow Booth), each with 0 orders of any status (Q13). Of 59 events with headshot orders since 2024, 53 carry a time of day and 6 are date-only at midnight Eastern (Q14). Either way the stamp copies the stored instant.
- `created`, `scheduling` and `completed` all have `sticks_to_order = true` (Q6).
- A second writer exists: `MarketingEventImport#find_order_for_account` (`app/models/marketing_event_import.rb:23–27`), the CSV import, 135 imports, last 2023-10-27 (Q15). Not covered; recorded.
- `OrderHeadshot` has no spec, and `POST /orders/headshot` (`config/routes.rb:197`, `orders_controller.rb:62–67`, admin, scheduler and processor) has no request spec.

## Changes

### 1. The stamp — `lib/order_headshot.rb`

`create_order` remembers whether `find_order_for_account` returned a new record. After `order.save(User.system)` succeeds for a new record, it reads the event (`MarketingEvent.unscoped.find_by(id:)`, no status filter, because a soft-deleted event still happened, §5.5 `:1185–1186`) and calls `order.update_columns(scheduled_at: event.scheduled_at)` when the event has a date. An event without a date leaves the column NULL, today's shape. An existing order found by `find_by` is reused untouched, so a re-submission never stamps retroactively. `scheduled_at` never enters the `find_by` hash, which is the match key.

The class gains an ARCHITECTURE NOTES block: why the date is the event's, why `update_columns` (decision 4), why only new orders, and that the CSV import is not covered.

### 2. The explicit delivered test — `app/services/event_attribution.rb`

In `event_orders_sql` (`:157–162`), `shoot_date` becomes `CASE WHEN <Order.completed_log_sql> THEN <Order.shoot_date_sql> END`. Every reader of `shoot_date IS NULL` keeps its meaning: the ranking CTEs (`:184–234`), `has_dated_event_order`, `pending_release_event_ids` and `null_dated_order_count` (`:327`). No other column, CTE or `ORDER BY` changes. `paid_listings_sql` is untouched; `qualifying_parents` already requires the completed log.

Reworded to match: the ARCHITECTURE NOTES OQ1 paragraph (`:22–29`), the memo's rules text (`lib/tasks/event_attribution.rake:132`), `spec/support/event_orders.rb:1–7`, and `app/helpers/matterport_csv_helper.rb:37`.

### 3. Attendance orders off the booking readers — one predicate, four sites

- `app/models/order.rb`: `scope :event_attendance, -> { where.not(marketing_event_id: nil) }`, which `event_orders_sql` adopts in place of its inline predicate, and `Order.not_event_attendance_sql` returning `'orders.marketing_event_id IS NULL'` for the raw-where sites. Both sit beside `completed_log_sql`, with a comment naming the four readers and saying why the sidebar is not one.
- `app/models/concerns/order_query.rb`: append the fragment beside the `default_order_types` filter (`:247`) when `params[:view]` is `scheduler` or `photographer-scheduler`, or when a new boolean `exclude_event_attendance` is set. Add that boolean to the list at `lib/order_param.rb:153`.
- `app/controllers/kpis_controller.rb#find_transactions`: `params[:exclude_event_attendance] = true` beside `params[:scheduled] = true` (`:45`). Both pending-payment and completed queries go through it.
- `app/controllers/orders_controller.rb#processing`: add the fragment to `conditions` (`:295`).

Behaviour today is unchanged: a NULL date never matched those date ranges. The predicate only keeps stamped rows out.

## Specs

Each unit is red, then green, then broken on purpose with the red output pasted.

- **`spec/lib/order_headshot_spec.rb`** (new). A new order carries the event's `scheduled_at`; an undated event leaves it NULL; an existing order is reused and not re-stamped; a new order's only log is `created` and its `order_event` is Created. Breaks: drop the stamp; pass `scheduled_at` to `Order.new` instead, which adds the `scheduling` log.
- **`spec/requests/orders_headshot_spec.rb`** (new; pattern `spec/requests/orders_create_spec.rb`, `jwt_headers_for`). 200 with `scheduledAt` equal to the event's; a photographer gets 401.
- **`spec/services/event_attribution_spec.rb`**. The fast convert with the stamp — event 03-01, order stamped 03-01 and delivered 03-08, listing 03-03 — is `write`, and `event_date_only` is empty. The existing OQ1 example (`:53`) stays as the unstamped shape. A stamped undelivered order is dropped, counted in `null_dated_order_count`, and its account is `skip_undated_event_order`. Break: remove the CASE, and the undelivered examples go red.
- **`spec/services/headshot_host_roi_spec.rb`**. A stamped undelivered order is a pending release, not an attendee; on delivery the account is a convert under the event's host.
- **Request specs for the four readers.** A stamped attendance order on the event day is absent from `view=scheduler`, `view=photographer-scheduler`, `GET /orders/processing`, `GET /kpis/accounts` and `GET /kpis/order_types`. It is still present in `GET /orders?marketingEventId=`. Patterns: `spec/requests/orders_processing_release_on_spec.rb`, `spec/requests/kpis_marketing_source_accounts_spec.rb`, and `spec/requests/metadata_contract_spec.rb` for the scheduler view's setup in a new `orders_scheduler_view_spec.rb`. Break: drop one site's predicate, and that endpoint's example goes red.
- **`spec/architecture/account_classification_spec.rb`**, in the `event attribution (§5.5)` block (`:680`), before `SQL composition` (`:807`). A stamped order inside the delivery lag credits; a stamped undelivered order stays undated.
- **`spec/support/event_orders.rb`**. `create_event_order` gains `scheduled_at:`, default `nil`, documented as the unstamped shape every existing example uses.

## Commits

Branch `feat/headshot-event-date`; one concern each. Dan merges; nothing is pushed.

1. `fix: date event orders by their delivery log only when delivered` — change 2 and its specs. First, so no commit exists where a stamped undelivered order counts.
2. `feat: keep event attendance orders off the booking views` — change 3 and the request specs.
3. `feat: stamp the event date on new headshot orders` — change 1 and both new specs.
4. `test: pin the event-date rules in the contract spec`.

Platform repo, after the deploy: this plan marked approved with its evidence; runbook `docs/runbooks/deploy-headshot-event-date.md`; `docs: amend account classification to v15 for the event-date stamp` (§5.5's dating bullet, a §9 row for this change, §20's follow-on marked done, a "Changes from v14" section); `docs: update the classification codebase notes for the event-date stamp` (the `lib/order_headshot.rb` row, the `event_attribution.rb` rows, the new specs, "Branch and deploy state").

## Verification

Expectations below are reasoned from the rules before any code exists. A mismatch is a finding, never a reason to adjust the expectation.

1. **Suite.** `bundle exec rspec`: the 6c-api baseline was 1,978 examples, 0 failures; re-measure before commit 1. The count grows; no existing example changes.
2. **Nothing moves on the restore.** Before and after commit 1, and again after commit 4, every `EventAttribution.credit_rows_sql` row hashes identically (2,343 rows today, Q5), `HeadshotHostRoi.call` returns the same rows and totals, and `plan.event_date_only` is still 996, 1467 and 1516. Reason: no stamped order exists, and for a NULL `scheduled_at` the CASE and the bare `shoot_date_sql` agree on every row.
3. **End to end, rolled back.** One `rails runner` script inside a transaction that ends in `ActiveRecord::Rollback`, because the dev database holds production data. The processing and KPI endpoints build their queries in the controller, so the request specs are their only check:

   | Step | Expected |
   | :--- | :--- |
   | `OrderHeadshot.create_order` on event 1433 (PSAR, 2026-10-09 18:00 UTC) for a new agent | `scheduled_at` 2026-10-09 18:00 UTC; Created; one `created` log |
   | `Order.select_all(OrderParam.search_params(...))` with `view: 'scheduler'` and with `view: 'photographer-scheduler'`, both for 2026-10-09 | The order is absent |
   | The same with `marketing_event_id: 1433` and no view | The order is present |
   | `EventAttribution.plan`, undelivered | `skip_undated_event_order`; `null_dated_order_count` one higher |
   | A paid listing shot 2026-10-11, then the headshot completed 2026-10-13 | `write`, source `psar_event`; the unstamped code would give `skip_after_buying` |

4. **After the deploy** (the runbook). The first event created afterwards: its orders carry the event's date and sit in Created. On the nightly memo, "credited only under the event date" stays 996, 1467 and 1516 and never gains an account from a post-deploy event. `GET /kpis/headshot_hosts` totals are unchanged on the day of deploy.
5. **Deploy safety.** No migration and no client release. Old code against new data and new code against old data both work, because nothing is stamped until commit 3's code creates an order.

## What people will see

- **Ops order summary**, new headshot orders only: the "Pending scheduling" chip gives way to the Scheduled block with the event's date and a Scheduler button (`insgt-ops/src/app/orders/summary/order-summary.component.html:5`, `:111–138`, `:221`). The button opens the event day, where the order is deliberately not listed.
- **insgt-app**, new headshot orders only: the order shows the event's date instead of "No time has been set yet" (`order-scheduled-at.pipe.ts:34`).
- **Calendars, daily tasks and weekly KPIs:** nothing.
- **Attribution:** an agent who buys inside the delivery lag is credited on the first nightly run after delivery, and counts as a convert in the ROI panel.

## Out of scope, recorded

- The backfill of historical orders (decision 3).
- `MarketingEventImport`, the second writer.
- An event whose date is edited after its orders exist; the orders keep the original date.
- `lib/order_headshot.rb:132` calls an undefined `errors`, so a missing contractor raises `NameError`; `:51` reuses soft-deleted orders through `find_by` without a status filter.
- `AccountReport.headshot_event_report`, still parsing hosts from event names.
- Pipedrive (slice 7).

## Appendix — survey queries (dev restore, 2026-10-19)

Run with `rails runner`; read-only.

| # | Query | Result |
| :-- | :-- | :-- |
| Q1 | `SELECT order_type_id, status_type, scheduled_at IS NULL, count(*) FROM orders WHERE marketing_event_id IS NOT NULL GROUP BY 1,2,3`; active type 3 total | (2, deleted, NULL) 2 · (3, active, NULL) 2,668 · (3, deleted, NULL) 9; type 3 active 2,710 |
| Q2 | Active type 3 orders since 2025 joined to their event, bucketed by `orders.created_at − marketing_events.scheduled_at` | 1–7 d 741 · 7–30 d 24 · none under a day; 766 created since 2025 |
| Q3 | The same orders by first active completed log − `orders.created_at` | < 1 h 624 · < 1 d 127 · 1–7 d 13 · 7 d+ 1 · undelivered 1 |
| Q4 | `EventAttribution.plan.event_date_only` | 996 (2017-03-21 → listing 03-22 → delivered 03-28, no source) · 1467 (2018-01-30 → 02-02 → 02-07, `nsdcr_event`) · 1516 (2018-03-15 → 03-20 → 03-22, `nsdcr_event`) |
| Q5 | `EventAttribution.plan.rows`; row 11944; event orders since 2025 with the event before the first paid listing and the delivery at or after it | 2,343 rows; 11944 has its own source 13, no crediting order, latest event 1201; 11944 is the only such account since 2025 |
| Q6 | `order_events` where tag in created, scheduling, completed | 21 Created, 22 Scheduling, 19 Completed, all `sticks_to_order` true |
| Q7 | `order_types` 3, 12, 19, 73 | all `marketing`, `generic_photo_processing` true, active |
| Q8 | Active type 12 and 19 orders with `scheduled_at` by year | type 19: 51 in 2026, 66 in 2025; type 12: none after 2019 |
| Q9 | Active type 3 with `paid_at` | 98 of 2,710 |
| Q10 | Active type 3, `scheduled_at` NULL, not completed | 1 |
| Q11 | Active notifications for resource type 4 (marketing event) or type 5 with id 3, by order event | marketing events: Completed 195, Manual email submission 32; type 3: Manual payment 1 |
| Q12 | The same, with `email_template = 'send_invoice_email'` | none |
| Q13 | Events with `scheduled_at` NULL, with order counts of any status | 14, 31, 35, each 0 orders |
| Q14 | Events with orders since 2024, by UTC hour of `scheduled_at` | 18 h 29 · 19 h 12 · 16 h 6 · 17 h 4 · 4 h 4 · 5 h 2 · 15 h 1 · 20 h 1 |
| Q15 | `marketing_event_imports` count and latest `created_at` | 135, 2023-10-27 18:28 UTC |
