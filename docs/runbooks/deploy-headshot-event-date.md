# Runbook: Headshot Flow — Stamp the Event Date on New Event Orders

**Last updated:** 2026-10-21
**Repos:** insgt-api (one push); platform repo for the write-back
**Estimated duration:** ~15 min on the day; the stamp's own check waits for the first headshot
orders ops creates after the deploy
**Status:** **Deployed 2026-10-21** as release v650, at 09:19:57 EDT (13:19:57 UTC), `master` merge
03384f32 of the five commits. Steps 1–3 done, as expected; steps 4 and 5 wait for the first headshot orders created
after the deploy.

## Summary

Ships `docs/plans/headshot-flow.md` (decisions 1–4) against `docs/architecture/account-classification.md`
v14 §5.3 and §5.5. Branch `feat/headshot-event-date`, five commits:

1. `3032269c` fix: date event orders only once delivered — `EventAttribution.event_orders_sql` dates
   an event order only when its completed log exists, so a stamped order waits for delivery.
2. `d7da897e` feat: keep event attendance orders off the booking views — `Order.event_attendance`
   and `Order.not_event_attendance_sql` keep orders on a marketing event off both calendars
   (`view=scheduler`, `view=photographer-scheduler`), `GET /orders/processing`, and the weekly KPIs.
3. `c97fe140` feat: stamp the event date on new headshot orders — `OrderHeadshot` writes the event's
   `scheduled_at` with `update_columns` after the create save, on orders it just created only. The
   order stays in Created; no `scheduling` log.
4. `cea56a98` test: pin the event-date rules in the contract spec.
5. `4c425277` fix: keep event attendance orders out of order timing metrics — no turnaround for
   attendance orders, and `AccountOrderMetricsService` leaves them out.

**No migration, no ENV, no client release, no backfill.** The 2,668 historical event orders keep a
NULL `scheduled_at` and stay dated by delivery (decision 3).

**What moves for a human.** Nothing at the push: no event order carries a date until ops creates one
with the new code. From the first headshot order created afterwards:

- **Ops order summary** of a new headshot order: the Scheduled block with the event's date in place
  of "Pending scheduling", and a Scheduler button that opens the event day, where the order is
  deliberately not listed.
- **insgt-app**: the order shows the event's date in place of "No time has been set yet".
- **Date-only events** (6 of the 59 events with headshot orders since 2024) are stored at midnight
  Eastern, and the stamp copies that instant, so their orders read as **9pm the previous evening** in
  Pacific, in both apps. Kept: the plan copies the stored instant.
- **Calendars, daily tasks, weekly KPIs, account order metrics:** nothing.
- **Attribution:** an agent who shoots a paid listing inside the delivery lag is credited on the first
  02:30 UTC run after delivery and counts as a convert in the ROI panel, where unstamped they read as
  already customers.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. Captures
are redirects into `tmp/`, which is gitignored.

## Deploy order and the windows

**New code, old data: safe.** Nothing is stamped until the new code creates an order, and for a NULL
`scheduled_at` the delivered test and the bare shoot date agree on every row. On the dev restore of
2026-10-19 the attribution rows (2,343), the ROI rows and totals, `event_date_only` and the per-account
order metrics of all 2,345 attendees hashed identically before and after every commit.

**Old code, new data: NOT safe** once a stamped order exists. Old code dates an event order by
`scheduled_at` with no delivered test and has no gates, so a stamped order would count as attendance
before delivery (the nightly write could credit its host then, and that write is never revisited), and
would appear on both calendars, the daily tasks and the KPIs. **Rollback** below clears the stamps.

Nothing in the push touches the 02:30 UTC `metrics:recompute`. A rollback does: keep it out of the
scheduler's 02:15–02:45 UTC window.

## Prerequisites

- [x] Dan has merged `feat/headshot-event-date` (five commits, `3032269c..4c425277`) to `master`
      (03384f32); `bundle exec rspec` green (1,997 examples, 0 failures on 2026-10-21)
- [x] Step 1 reads `dated event orders 0`. That is what makes the rollback safe: after the push,
      every event order with a date got it from the stamp.

## Steps

### 1. Before the push — the zero check and the baseline

Old code is live, so these use the raw predicate, not `Order.event_attendance`.

```bash
heroku run --no-tty --exit-code rails runner '
  puts "dated event orders #{Order.where.not(marketing_event_id: nil).where.not(scheduled_at: nil).count}   expect 0"
  plan = EventAttribution.plan
  puts "event_date_only #{plan.event_date_only.map { |row| row[:account_id] }.inspect}"
  puts "null_dated #{plan.null_dated_order_count}"
  puts "roi #{HeadshotHostRoi.call[:totals].slice(:attendees, :converts, :already_customers, :pending_release_accounts).inspect}"
' -a insgtapi > tmp/headshot-date-before.txt
cat tmp/headshot-date-before.txt
```

**STOP if the first line is not 0.** An event order with a date that the stamp did not write means the
rollback statement would clear it too; find out where it came from first. On the dev restore of
2026-10-19: 0 of 2,679 event orders, `event_date_only` `[996, 1467, 1516]`, null-dated 1, ROI
2,342 attendees · 204 converts · 151 already customers · 1 pending release. Production may differ if
1467 or 1516 were set by hand since (plan decision 3): each leaves the list once it carries a source.

Results, 2026-10-21: `dated event orders 0`, so the prerequisite held. The other lines stayed in
`tmp/headshot-date-before.txt` on the host; step 3 compares against them.

### 2. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release and its time; step 4 uses the time
```

### 3. Right after the push — nothing moved

```bash
heroku run --no-tty --exit-code rails runner '
  puts "dated event orders #{Order.event_attendance.where.not(scheduled_at: nil).count}"
  plan = EventAttribution.plan
  puts "event_date_only #{plan.event_date_only.map { |row| row[:account_id] }.inspect}"
  puts "null_dated #{plan.null_dated_order_count}"
  puts "roi #{HeadshotHostRoi.call[:totals].slice(:attendees, :converts, :already_customers, :pending_release_accounts).inspect}"
' -a insgtapi > tmp/headshot-date-after.txt
diff tmp/headshot-date-before.txt tmp/headshot-date-after.txt
```

Expected, reasoned from the rules before the code existed: the only difference is the first line's
`   expect 0` suffix. The count stays 0 until ops creates a headshot order. A release between the two
runs moves `null_dated` down and ROI attendees up by the same accounts; re-run step 1's lines to tell
the two apart.

Results, 2026-10-21:
```
1c1
< dated event orders 0   expect 0
---
> dated event orders 0
```

Only the suffix differs: still no dated event order, and `event_date_only`, null-dated and the ROI
totals identical before and after the push.

### 4. The first headshot orders after the deploy

Ops creates attendee orders 1–7 days after an event, so this waits for the first event's batch.
The time is step 2's release time, 2026-10-21 09:19:57 EDT.

```bash
heroku run --no-tty --exit-code rails runner '
  deployed_at = Time.iso8601("2026-10-21T09:19:57-04:00")
  orders = Order.event_attendance.where("orders.created_at >= ?", deployed_at).includes(:order_event).to_a
  events = MarketingEvent.unscoped.where(id: orders.map(&:marketing_event_id)).index_by(&:id)
  puts "1 new event orders #{orders.size} on events #{events.keys.sort.inspect}"
  puts "2 date = event date #{orders.count { |order| order.scheduled_at == events[order.marketing_event_id]&.scheduled_at }} of #{orders.size}   expect all (an undated event leaves NULL)"
  puts "3 order events #{orders.group_by { |order| order.order_event&.tag }.transform_values(&:size).inspect}   expect created, and completed once delivered"
  puts "4 scheduling logs #{OrderLog.where(order_id: orders.map(&:id), order_event_id: OrderEvent.tag_id(:scheduling)).count}   expect 0"
  puts "5 turnaround stored #{orders.count { |order| order.turnaround_time_minutes }}   expect 0"
' -a insgtapi
```

On site, for that event's day:

1. Ops scheduler calendar: the event's own Headshot Event order is listed, none of the attendee orders.
2. Ops processing (daily tasks): none of the attendee orders.
3. One new attendee order's summary in ops: the Scheduled block with the event's date (9pm the
   previous evening if the event is date-only, above).

### 5. The first memo after a delivery

After the first post-deploy event's media is released, on the next morning:

```bash
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts -a insgtapi \
  | sed -n '/Credited only under the event date/,/^## /p'
```

Expected: no account from a post-deploy event **with a delivered date**. The section can list such an
account with a blank delivered date while its stamped order is still held back, if the agent shot a
paid listing after the event: `event_date_only` does not test delivery, for stamped or unstamped
orders alike (unchanged by this deploy). It leaves the list on the first run after delivery, credited.

## Rollback

**Not a bare `heroku rollback`** once step 4's count is above 0: roll back, then clear the stamps
(Deploy order, above). Every dated event order is a stamp, because step 1 read 0 before the push.

Do it outside 02:15–02:45 UTC, and finish both steps before 02:30, so the nightly write never runs old
code against a stamped order.

**1. Roll back the code first,** so nothing stamps again while you clear:

```bash
heroku rollback --app insgtapi
```

**2. Save the stamps, then clear them,** in one dyno. Old code is live again: raw predicate.

```bash
heroku run --no-tty --exit-code rails runner '
  scope = Order.where.not(marketing_event_id: nil).where.not(scheduled_at: nil)
  scope.order(:id).pluck(:id, :scheduled_at).each { |id, at| puts "#{id},#{at.utc.iso8601(6)}" }
  puts "# cleared #{scope.update_all(scheduled_at: nil)}"
' -a insgtapi > tmp/headshot-stamps-$(date -u +%F).csv
tail -1 tmp/headshot-stamps-$(date -u +%F).csv
heroku run --no-tty --exit-code rails runner 'puts "dated event orders #{Order.where.not(marketing_event_id: nil).where.not(scheduled_at: nil).count}   expect 0"' -a insgtapi
```

Expected: `# cleared N`, with N the number of id lines above it, then 0. `update_all` writes no
`updated_at` and fires no callbacks, the same as the stamp. The CSV is the record of what was cleared;
keep it.

**Nothing else to undo.** Accounts the new code credited from a stamped, delivered order keep their
source: §5.5 writes once, and old code never writes over a value. No turnaround was stored on an
attendance order. The calendars, daily tasks and KPIs read live, so they are right again as soon as
the stamps are gone. Cleared orders are dated by delivery, like every order before the stamp.

**Re-deploying later.** Push the code again, then re-stamp the cleared orders from their events, never
before the push, because old code has no delivered test:

```bash
IDS=$(grep -E '^[0-9]+,' tmp/headshot-stamps-<date>.csv | cut -d, -f1 | paste -sd, -)
heroku run --no-tty --exit-code rails runner "
  restored = Order.where(id: [$IDS], scheduled_at: nil).to_a.count do |order|
    event = MarketingEvent.unscoped.find_by(id: order.marketing_event_id)
    event&.scheduled_at && order.update_columns(scheduled_at: event.scheduled_at)
  end
  puts \"restored #{restored}\"
" -a insgtapi
```

Expected: `restored` = the CSV's id lines, unless an event was re-dated in between, in which case its
orders take the new date and differ from the CSV.

## Known, kept by decision

- **The CSV import** (`MarketingEventImport#find_order_for_account`, last run 2023-10-27) builds event
  orders and stamps nothing. Out of scope.
- **An event re-dated after its orders exist** leaves them on the original date.
- **The console reports** `OrderReport.annual_daily_order_count` and `annual_range_package_report`
  count stamped, delivered attendance orders by event date. Console only.
- **Historical orders** are not backfilled (decision 3). 1467 and 1516 can be set by hand in ops as
  scheduler-set sources (§5.5); 996's host has no source.

## After the deploy — write-back (platform repo)

- `docs/plans/headshot-flow.md` marked approved, with this runbook's evidence.
- `docs: amend account classification to v15 for the event-date stamp`: §5.5's dating bullet, a §9 row,
  §20's follow-on marked done, a "Changes from v14" section. It should record the rollback hazard
  above, the turnaround and account-metrics exclusions (commit 5, not in the plan), and that the
  plan's Verification 5 claim about old code was wrong.
- `docs: update the classification codebase notes for the event-date stamp`.

## Deploy log

- 2026-10-21: **deployed** as release v650 at 09:19:57 EDT (13:19:57 UTC), `master` merge 03384f32
  of the five commits `3032269c..4c425277`. No migration. Step 1 before the push: 0 dated event
  orders. Step 3 after it: the two captures differ only by step 1's `expect 0` suffix, so nothing
  moved at the push: still 0 dated event orders, and `event_date_only`, null-dated and the ROI totals
  unchanged. Steps 4 and 5 wait for the first post-deploy event's headshot orders and their release.

- 2026-10-21: **verified on the dev restore** (production sync of 2026-10-19 16:24 UTC). Suite 1,978
  → 1,997 examples, 0 failures; every new spec red first, then green, and each deliberate break red.
  Nothing moved on the restore across all five commits (Deploy order, above). End to end in a
  transaction rolled back: `OrderHeadshot.create_order` on event 1433 (PSAR, 2026-10-09 18:00 UTC) for
  a new agent stamped 2026-10-09 18:00 UTC, Created, one `created` log; absent from both calendar views
  for 2026-10-09 (also as user 2 once completed), present with no view and by `marketingEventId`;
  undelivered with no listing `skip_no_paid_listing`, with a 2026-10-11 paid listing
  `skip_undated_event_order`, null-dated 1 → 2; delivered 2026-10-13, `write` to `psar_event`, crediting
  date 2026-10-09 18:00 UTC, ROI 2,342 → 2,343 attendees and 204 → 205 converts; the same order unstamped
  `skip_after_buying`. `predeploy-review-rails` with one Codex pass: no blocker; the two should-fixes
  were fixed (commit 5) or added to this runbook (Rollback).
