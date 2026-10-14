# Runbook: Account Classification Slice 6 — Event Attribution Deploy (events 4 and 5)

**Last updated:** 2026-10-14
**Repos:** insgt-api
**Estimated duration:** ~20 min for event 4 plus the memo read (Don); ~5 min for event 5 the next day
**Status:** Not deployed. Verified on the dev sync 2026-10-14 (dry run, `APPLY`, invariants, reversal).

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

- [ ] `feat/account-classification-slice-6-attribution` (three commits) merged to `master`; two
      review rounds closed; `bundle exec rspec` green (1,944 examples on 2026-10-14)
- [x] Slice 6a deployed; `rake marketing_events:audit_hosts MAP_CUTOFF=2026-10-07T12:30:10.007557Z`
      shows 0 unmapped since the cutoff (2026-10-08)
- [ ] The KPI baseline captured the same day (step 2)

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
ruby -rcsv -e 'puts CSV.read("tmp/attribution-dry-run.csv", headers: true).select { |row| row["action"] == "write" }.map { |row| row["account_id"].to_i }.sort.join(",")' > tmp/attribution-csv-write-ids.txt
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

```bash
heroku logs -a insgtapi --source app | grep -E "Attributed|Event attribution failed"
```

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
