# Runbook: Account Classification Slice 6 — Event Attribution Deploy (events 4 and 5)

**Last updated:** 2026-10-14
**Repos:** insgt-api
**Estimated duration:** ~20 min for event 4 plus the memo read (Don); ~5 min for event 5 the next day
**Status:** Event 4 **deployed 2026-10-14** (release v647); `APPLY` at 12:30:56 UTC wrote 94 accounts, every invariant and spot check as expected. Event 5 (the nightly hook) **deployed 2026-10-14** (release v648); its first run is 2026-10-15 02:30 UTC.

## Summary

Ships slice 6b of `docs/architecture/account-classification.md` §5.5 (plan:
`docs/plans/account-classification-slice-6.md`, G9–G16): event attribution into
`accounts.marketing_source_id`. Builds on slice 6a (`deploy-account-classification-6-hosts.md`),
which put a host on every event and a source on PSAR, NSDCR and SDAR.

- **Event 4** (insgt-api, three commits): `EventAttribution` (`app/services/event_attribution.rb`)
  and the task `account_classification:attribute_event_hosts` (`lib/tasks/event_attribution.rake`).
  **Dry run by default; `APPLY=true` writes.** For every active, non-internal account with no source,
  the latest active event order dated strictly before its first paid listing shoot (both by
  `Order.shoot_date_sql`) credits its event's host's source, when the host has one. Written once,
  never over a value, `updated_by_id = 1` and one batch `updated_at`, in one transaction with two
  self-checks. No migration.
- **`APPLY` is a separate, manual production event** behind the dry-run memo, which Don reads
  before the numbers move (§9).
- **Event 5** (insgt-api, one commit, pushed only after `APPLY`): the nightly hook in
  `metrics:recompute`, so each night's new converts are attributed.

**What moves for a human, on `APPLY`.** The owner-only marketing-source KPI (insgt-ops KPIs page):
`attributed_accounts` rises by the memo's written count and the three event sources' rows grow;
`total_accounts` and gross do not move. The accounts report and each written account's edit page
show the derived source. Nothing moves on the push.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. A
one-off dyno's filesystem is discarded when it exits, so every capture is a redirect of its stdout,
and `../../docs/architecture/` is the platform repo's docs directory.

## Deploy order and the windows

**Event 4 has no window.** No migration; nothing reads the two files until someone invokes the
task. The nightly recompute does not call it in this push, so the 02:30 UTC run is unaffected.

**Order inside event 4 is load-bearing:** dry run → **STOP, Don reads the memo** → `APPLY` → second
dry run → invariants → spot checks. `APPLY` is a decision made on the memo, not a step after it.

**Event 5 strictly after `APPLY`.** The hook pushed earlier would make the first write happen at
02:30 UTC with no memo. It is its own commit for that reason.

## Prerequisites

- [x] `feat/account-classification-slice-6-attribution` (three commits) merged to `master`; two
      review rounds closed; `bundle exec rspec` green (1,944 examples on 2026-10-14)
- [x] Slice 6a deployed; `rake marketing_events:audit_hosts MAP_CUTOFF=2026-10-07T12:30:10.007557Z`
      shows 0 unmapped since the cutoff (2026-10-08)
- [x] The KPI baseline captured the same day (step 2)

## Steps — event 4

### 1. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release beside the memo
```

### 2. Baseline

```bash
heroku run --no-tty --exit-code rails runner 'puts MarketingSourceMetricsService.call[:metadata].inspect; MarketingSourceMetricsService.call[:rows].select { |row| row[:name].to_s =~ /event/i }.each { |row| puts row.inspect }' -a insgtapi > tmp/attribution-kpi-before.txt
```

### 3. The dry run — read it, then STOP

```bash
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts -a insgtapi > tmp/attribution-dry-run.md
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts OUT=/dev/null CSV=/dev/stdout -a insgtapi > tmp/attribution-dry-run.csv
```

Read, in this order:

1. **The title** reads `(DRY RUN)`.
2. **Funnel.** On the dev sync of 2026-10-14: 2,343 active non-internal accounts with an event
   order; 28 already sourced; 2,315 without; no paid listing 1,967; after-buyers 149; credited 199 =
   to write 94 + host not a source 96 + latest event unhosted 9; 1 internal; 13 undelivered event
   orders (12 on event 1433, "PSAR Headshots Chula Vista", not yet delivered).
3. **Writes by host → source.** Dev: NSDCR 70 · PSAR 13 · SDAR 11, with every account listed.
4. **KPI predicted.** `attributed_accounts` before must equal step 2's; after = before + writes.
   Dev: 189 → 283; NSDCR event 6 → 76, PSAR event 20 → 33, SDAR event 9 → 20.
5. **Credited only under the event date**: 996, 1467, 1516 on dev — what the delivery-date rule
   costs (OQ1). Two are NSDCR writes not made.
6. **Already sourced**: own source beside the derived host — Don's agreement check (823's own
   `nsdcr_event` against a Home Solutions Realty event; 11349 `other` against SDAR).
7. **Events with no host**: the ten mapped no-host events; any marked "created after the host map"
   should be set from the ops edit page and the dry run re-run.

**STOP.** Hand the memo to Don. `APPLY` waits for the go-ahead.

### 4. APPLY

```bash
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts APPLY=true -a insgtapi > ../../docs/architecture/event-attribution-memo-<date>-production.md
```

Read the title and **After**: `Written: …` equal to the dry run's table (unless a scheduler set a
source in between), both self-checks OK, the reversal line. **If it exits with
`EventAttribution::SelfCheckFailed`, nothing was written**: a planned account was sourced,
soft-deleted or typed internal between plan and write, or its host's source was re-keyed. Self-check
2 re-reads every account that already carries a source (about 200), so a scheduler editing any
account's source during the few seconds of `APPLY` also fails it, safely. Either way, re-run step 3,
then this step. Run at a quiet moment; the guarantee is statement-time. Copy the stamp; every later
step keys on it.

### 5. Second dry run plans 0

```bash
heroku run --no-tty --exit-code rake account_classification:attribute_event_hosts -a insgtapi | sed -n '/^## Funnel/,/^## Writes/p'
```

Expect `| credited, to write | 0 |` and "already carrying a source" grown by exactly the written
count (dev: 28 → 122).

### 6. Invariants

Replace `<stamp>` with the memo's microsecond stamp. All expected values are exact.

```bash
heroku run --no-tty --exit-code rails runner '
  stamp = Time.zone.parse("<stamp>")
  batch = Account.where(updated_by_id: 1, updated_at: stamp)
  puts "1 batch rows: #{batch.count}   expect the memo Written total"
  puts "2 batch rows not sourced / free text left / inactive / internal: #{batch.where("marketing_source_id IS NULL OR marketing_source_other IS NOT NULL OR status_type <> 1 OR account_type = 7").count}   expect 0"
  puts "3 by source: #{batch.joins(:marketing_source).group("marketing_sources.key").count.sort.to_h}   expect the memo per-source counts"
  puts "4 second plan writes: #{EventAttribution.plan.writes.size}   expect 0"
  puts "5 KPI: #{MarketingSourceMetricsService.call[:metadata].inspect}   expect attributed = before + written, total and gross unchanged"
  psar = MarketingSource.find_by!(key: "psar_event")
  puts "6 PSAR drill-down holds every PSAR write: #{(batch.where(marketing_source_id: psar.id).pluck(:id) - MarketingSourceAccountsService.call(psar.id).map { |row| row[:account_id] }).empty?}   expect true"
  puts "batch_ids: #{batch.order(:id).pluck(:id).join(",")}"
' -a insgtapi > tmp/attribution-invariants.txt
grep -v "^batch_ids" tmp/attribution-invariants.txt
ruby -rcsv -e 'puts CSV.read("tmp/attribution-dry-run.csv", headers: true, encoding: "UTF-8").select { |row| row["action"] == "write" }.map { |row| row["account_id"].to_i }.sort.join(",")' > tmp/attribution-csv-write-ids.txt
diff <(sed -n "s/^batch_ids: //p" tmp/attribution-invariants.txt) tmp/attribution-csv-write-ids.txt && echo "batch ids = CSV write ids"
```

**On the dev sync, 2026-10-14 (stamp 11:57:30.340630Z):** 1 → 94; 2 → 0; 3 →
`{"nsdcr_event" => 70, "psar_event" => 13, "sdar_event" => 11}`; 4 → 0; 5 → 283 of 4,153, gross
unchanged; 6 → true (33 PSAR accounts).

### 7. Spot checks

Reasoned from the rules before the code ran; confirmed on the dev sync. Production ids for the
sources come from the dry run (dev: NSDCR 2, PSAR 3, SDAR 4).

| Account | Why | Expected |
| :-- | :-- | :-- |
| 77 Kim Glynn | NSDCR delivered 2020-02-04, first paid listing 2020-07-25 | `nsdcr_event` |
| 572 Serena Alexander | SDAR 2016-05-24, first paid 2018-07-11 | `sdar_event` |
| 214 Maria Lopez | NSDCR 2019-02-27, first paid 2022-11-21; a 2025 NSDCR event does not move it | `nsdcr_event` |
| 3039 | the lowest-id PSAR write | `psar_event` |
| 10 Rick Sauer | Windermere Homes & Estates-Rancho Bernardo, a host with no source | NULL (`skip_host_no_source`) |
| 47 Kurt Kinsey | first paid 2015-08-27, attended 2016-06-16 | NULL (`skip_after_buying`) |
| 1467 Giovanni Ruiz, 1516 Russell Coats | NSDCR event before the listing, headshot delivered after it (OQ1) | NULL; listed under "credited only under the event date" |
| 823 Adam Nobert | already `nsdcr_event` | unchanged, `updated_at` unchanged |
| 1534 Test McName | internal | unchanged |

```bash
heroku run --no-tty --exit-code rails runner 'puts Account.where(id: [77, 572, 214, 3039, 10, 47, 1467, 1516, 823, 1534]).order(:id).pluck(:id, :marketing_source_id, :updated_by_id, :updated_at).inspect' -a insgtapi
```

### 8. insgt-ops (already live)

As owner, the KPIs page's marketing-source table shows the step 6 numbers. One written account's
edit page (77) shows "NSDCR event" as its source and saves without a validation error.

## Steps — event 5 (the nightly hook)

### 9. Deploy the hook

Strictly after step 4. `feat: run event attribution in the nightly recompute` merged to `master`:

```bash
git push heroku master
```

The next 02:30 UTC `metrics:recompute` prints, after "Recomputed SystemMetric" and before `Done.`,
`Attributed 0 accounts` (or that night's new converts). A failure prints `Event attribution failed:`
and the metrics summary still prints.

**Capture it within the hour, or it is gone.** `heroku logs` returns 100 lines by default and at
most 1,500 (`-n`), and Logplex retains only the most recent 1,500 lines of the whole app, so a
morning grep over the default window cannot see a 02:30 UTC run (2026-10-15, below). Scheduler
jobs run as one-off dynos named `scheduler.X`, so filter on that base name:

```bash
heroku logs -a insgtapi --dyno scheduler -n 1500 | grep -E "Recomputed SystemMetric|Attributed|Event attribution failed|Done\. Scanned"
```

If the lines have already scrolled out, the database says whether the sweep ran tonight and whether
the hook wrote anything, but it cannot tell `Attributed 0 accounts` from `Event attribution failed`
(both write nothing). Adjust the date:

```bash
heroku run --no-tty --exit-code rails runner 'puts "account_metrics computed_at max: #{AccountMetric.maximum(:computed_at)&.utc}"; puts "accounts sourced by user 1 since 02:30 UTC: #{Account.where(updated_by_id: 1).where("updated_at >= ?", Time.utc(2026, 10, 15, 2, 30)).where.not(marketing_source_id: nil).count}"' -a insgtapi
```

To capture the line itself after a miss, start `heroku logs -a insgtapi --dyno scheduler --tail`
before 02:30 UTC the next night, or run the first command within the hour after.

## Rollback

### Code

```bash
heroku rollback --app insgtapi
```

Leaves the written rows in place, **which is correct**: they are data, ops edits them, and old
code reads `marketing_source_id` exactly as new code does. Rolling back event 5 stops the nightly
writes and nothing else.

### Data (only if ever wanted)

Keyed on the batch pair from the memo; the actor alone would not do, because console writes also
carry `updated_by_id = 1`:

```bash
heroku run rails runner 'puts Account.where(updated_by_id: 1, updated_at: Time.zone.parse("<stamp>")).update_all(marketing_source_id: nil, updated_at: Time.current)' -a insgtapi
```

It restores the source only. A cleared `marketing_source_other` is not restored (0 accounts carried
text on the dev sync; the memo prints the day's count).

## Deploy log

- 2026-10-14: **verified on the dev sync** (production sync of 2026-10-14 04:41 UTC). Dry run 0.85 s:
  writes 94 (NSDCR 70 · PSAR 13 · SDAR 11), KPI predicted 189 → 283. `APPLY` at
  11:57:30.340630 UTC, 0.93 s: written 94, both self-checks OK, KPI 283 exactly as predicted
  (NSDCR event 76, PSAR event 33, SDAR event 20). Second plan 0; invariants 1–6 as expected; the
  spot checks as reasoned. The printed reversal cleared 94 rows and the KPI returned to 189.
- 2026-10-14, 08:18 EDT: **event 4 deployed to production** as release **v647**.
  `feat/account-classification-slice-6-attribution` (40b6fd93, b6522ea4, 42bc1d20) merged to
  `master` as 12bf9a36; two review rounds, no blocker; 1,944 examples, 0 failures. No migration.
  - **Baseline (step 2):** `attributed_accounts` 189 of 4,153; NSDCR event 6 · PSAR event 20 · SDAR
    event 9.
  - **Dry run (step 3), 12:21 UTC:** universe 2,315; to write 94 (NSDCR 70 · PSAR 13 · SDAR 11); 96
    credited to a host without a source; 9 latest-unhosted; 149 after-buyers; 13 undelivered event
    orders (12 on event 1433). Identical to the dev rehearsal. Handed to Don before `APPLY`.
  - **`APPLY` (step 4) at 12:30:56.771630 UTC**
    (`../architecture/event-attribution-memo-2026-10-14-production.md`; the memo's "insgt-api
    unknown" is v647): written 94, both self-checks OK (192 pre-sourced rows unchanged),
    no-source accounts 3,974 → 3,880.
  - **Second dry run (step 5), one-off dyno `run.2329`:**

    ```
    | active, not internal, with an active event order | 2,343 |
    | already carrying a source (never written) | 122 |
    | no source: the universe | 2,221 |
    | no paid listing | 1,967 |
    | attended only after the first paid listing | 149 |
    | only undelivered event orders before buying | 0 |
    | credited (an event order before the first paid listing) | 105 |
    | credited, to write | 0 |
    | credited, host is not a marketing source | 96 |
    | credited, latest event has no host | 9 |
    ```

    Already sourced 28 → 122, the universe 2,315 → 2,221 and credited 199 → 105: each moved by
    exactly the 94 written.
  - **Invariants (step 6):** 1 → 94; 2 → 0; 3 → `{"nsdcr_event" => 70, "psar_event" => 13,
    "sdar_event" => 11}`; 4 → 0; 5 → `attributed_accounts` 283 of 4,153 (6.8%), gross 374,510,000
    unchanged; 6 → true. Batch ids = CSV write ids, after the UTF-8 fix below.
  - **Spot checks (step 7), one-off dyno `run.9775`:** every row as reasoned.

    ```
    [[10, nil, 2, 2026-09-14 17:19:01.308540], [47, nil, 1, 2026-09-28 19:52:47.158499],
     [77, 2, 1, 2026-10-14 12:30:56.771630], [214, 2, 1, 2026-10-14 12:30:56.771630],
     [572, 4, 1, 2026-10-14 12:30:56.771630], [823, 2, 1, 2026-08-18 17:53:56.215203],
     [1467, nil, 1, 2026-09-28 19:52:47.158499], [1516, nil, 1, 2026-09-28 19:52:47.158499],
     [1534, nil, 2, 2026-09-14 13:21:53.733423], [3039, 3, 1, 2026-10-14 12:30:56.771630]]
    ```

    77, 214, 572 and 3039 carry the batch stamp and NSDCR, NSDCR, SDAR and PSAR. 10, 47, 1467,
    1516 and 1534 stay NULL; the 2026-09-28 stamp on 47, 1467 and 1516 is slice 4b's batch, not
    this one. 823 keeps its own `nsdcr_event` from August.
  - **ops (step 8):** the KPIs page shows 283; account 77's edit page shows "NSDCR event" and saves.
- 2026-10-14: **step 6's CSV cross-check fixed.** It read the CSV without `encoding: "UTF-8"` and
  failed on an accented name (row 2156); the slice 4b runbook's version had the encoding.
- 2026-10-14, 08:52 EDT: **event 5 deployed to production** as release **v648**. `feat: run event
  attribution in the nightly recompute` (409655b8) merged as b05f74c2; 1,947 examples, 0 failures.
  First run 2026-10-15 02:30 UTC: expect `Attributed 0 accounts` between "Recomputed SystemMetric"
  and `Done.` (step 9). Not yet recorded.
- 2026-10-15, morning EDT: **first-run capture inconclusive.** Step 9's original command
  (`heroku logs -a insgtapi --source app | grep …`, the default 100-line window) printed nothing.
  That is the window, not evidence about the run: the 02:30 UTC output was hours of request
  traffic ago and Logplex keeps 1,500 lines in all. Step 9 corrected to `--dyno scheduler -n 1500`
  with the runner fallback. The first run is **still not recorded**; the runner check or tonight's
  tail is the next capture.
- 2026-10-15, later that morning: **first run verified from the database; the log line was not
  captured.** The scheduler-filtered grep over the full 1,500-line buffer was empty too: the run's
  lines had scrolled out. The runner check (one-off dyno `run.6115`): `account_metrics`
  `computed_at` max **2026-10-15 02:32:26 UTC**, so the sweep ran and its last account landed about
  two and a half minutes after the 02:30 start, in line with the 2 min 38 s baseline; accounts
  sourced by user 1 since 02:30 UTC **0**. Consistent with `Attributed 0 accounts`; it cannot rule
  out `Event attribution failed`, which also writes nothing. The line itself gets captured on a
  later night: tail before 02:30 UTC, or the first command within the hour after.
