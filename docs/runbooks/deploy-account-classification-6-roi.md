# Runbook: Account Classification Slice 6 — Headshot Host ROI Deploy (events 6 and 7)

**Last updated:** 2026-10-19
**Repos:** insgt-api (event 6); insgt-ops (event 7)
**Estimated duration:** ~15 min for event 6
**Status:** Event 6 **deployed 2026-10-15** (release v649, `master` b7b2de9f) and verified, after a
production `ANALYZE` (deploy log). Event 7 **released 2026-10-19** as insgt-ops 9.67.0 (`main` merge
cbc88d5a, tag `v9.67.0`); on site, No host is the last row.

## Summary

Ships slice 6c-api of `docs/architecture/account-classification.md` §5.5's last paragraph (plan:
`docs/plans/account-classification-slice-6.md` G17, G20, OQ5, OQ10; prompt and approved plan:
`docs/plans/account-classification-slice-6c-api.md`).

- **Event 6** (insgt-api, five commits): `HeadshotHostRoi` (`app/services/headshot_host_roi.rb`), the
  read-out `marketing_events:host_roi`, and the owner-only `GET /kpis/headshot_hosts`. Per host:
  events, attendees, converts, conversion, already customers, converts' lifetime value; the no-host
  row last. Every figure comes from `EventAttribution.credit_rows_sql`, which gains four additive
  columns (the latest delivered event order, its event and host, and the events of orders pending
  release). **No migration, no data change, no new ENV.**
- **Event 7** (insgt-ops, two commits): the "Headshot event hosts" panel on the owner's KPIs page,
  below the marketing source breakdown. One row per host, then No host, pinned last under every
  sort; the Total line is the endpoint's `metadata`, so the panel computes nothing. **Released as
  9.67.0** (9.66.0 was taken on 2026-10-08). Plan, evidence and decisions:
  `docs/plans/account-classification-slice-6c-ops.md`.

**What moves for a human.** Nothing on event 6's push: the read-out is invoked by hand and the
endpoint has no client until event 7. The nightly write is unchanged: on the dev sync the
attribution plan's existing columns hash identically on the branch and on `master` over all 2,343
rows, and the write plan is identical (NSDCR 70 · PSAR 13 · SDAR 11). Event 7 adds the owner's card
and changes nothing else: no API change, no data change.

**Pending releases.** Headshot media is held back from release for a few days after most events,
so on any day some accounts have only undelivered event orders. They are not yet attendees and are
counted once delivered, by the next run, with no action on release. The read-out lists them by
event. The table is a point-in-time read: event 6's checks are relationships computed on the day,
not fixed counts.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. A
one-off dyno's filesystem is discarded when it exits, so every capture is a redirect of its stdout,
and `../../docs/architecture/` is the platform repo's docs directory.

The curls need a JWT for a **system_owner** user (`OWNER_JWT`) and one for a **system_scheduler**
(`SCHEDULER_JWT`), taken from a signed-in ops session's network tab or minted with `heroku run rails runner`
from a known user's `api_key` and `jwt_secret`, as `deploy-account-classification-4-worklist.md` does.

## Deploy order and the windows

**Event 6 has no window.** No migration; old code never sees the new columns, and new code reads
only tables that already exist. The nightly recompute's attribution hook reads `credit_rows_sql`
inside its write statement, so it runs the new CTE too; the existing columns it filters on are
unchanged.

**Event 7 strictly after event 6 is curl-verified.** The panel against the old API is a 404.

## Prerequisites

- [x] Dan has merged `feat/headshot-host-roi` (five commits) to `master`; `bundle exec rspec` green
      (1,978 examples on 2026-10-15)
- [x] Slice 6a-ii in production (every event carries its host); 6b merged (`credit_rows_sql` public)
- [x] 6b's write is **not** a prerequisite (§5.5): converts include already-sourced accounts

## Steps — event 6

### 1. Deploy code

```bash
git push heroku master
heroku releases -n 1 -a insgtapi          # record the release beside the read-out's header
```

### 2. The read-out v649   Deploy b7b2de9f

```bash
heroku run --no-tty --exit-code rake marketing_events:host_roi -a insgtapi \
  > ../../docs/architecture/headshot-host-roi-$(date -u +%F).md
```

The header prints `insgt-api unknown`, because the slug carries no `.git` (§20). Add the release
number from step 1 beside it, by hand, before committing the document.

Read:

1. **Totals check** reads `OK`.
2. **No host** is the last row before **Total**.
3. **Pending release** lists events by id with what each will roll in. On the dev sync of
   2026-10-14: `12 on event 1433 (PSAR), 10 not yet attendees` and
   `1 on event 1333 (SDAR), 1 not yet an attendee`.

### 3. Relationships, computed on the day

```bash
heroku run --no-tty --exit-code rails runner '
  funnel = EventAttribution.plan.rows.size
  result = HeadshotHostRoi.call
  totals = result[:totals]
  rows = result[:rows]
  puts "1 funnel #{funnel} - pending #{totals[:pending_release_accounts]} = #{funnel - totals[:pending_release_accounts]}; attendees #{totals[:attendees]}; rows sum #{rows.sum { |row| row[:attendees] }}; totals_match #{totals[:totals_match]}   expect all three equal, true"
  puts "2 converts #{totals[:converts]} already #{totals[:already_customers]} attendee-only #{totals[:attendees] - totals[:converts] - totals[:already_customers]}"
  puts "3 converts > attendees anywhere: #{rows.count { |row| row[:converts] > row[:attendees] }}   expect 0"
  %w[NSDCR PSAR SDAR].each { |name| row = rows.find { |each_row| each_row[:name] == name }; puts "4 #{name} attendees #{row[:attendees]} converts #{row[:converts]} already #{row[:already_customers]}" }
  puts "5 last #{rows.last.slice(:name, :events, :attendees, :converts, :already_customers).inspect}; rows #{rows.size}"
  puts "6 pending #{totals[:pending_releases].inspect}"
' -a insgtapi > tmp/roi-relationships.txt
cat tmp/roi-relationships.txt
```

Expected, reasoned from the rules before the code existed (dev sync of 2026-10-14 in brackets):

1. Distinct attendees = the funnel (active, not internal, with an active event order) − the
   pending-release accounts, both read now; the rows sum to it; `totals_match` true.
   [2,343 − 11 = 2,332]
2. A release of accounts with no paid listing leaves converts and already customers unchanged and
   raises attendee-only by the released count. [converts 203, already customers 151 (M7a's 149 + 2
   already sourced), attendee-only 1,978]
3. 0.
4. Converts per association host, **lower bounds only** — 6b's writes, and converts also include
   the already-sourced: NSDCR ≥ 70, PSAR ≥ 13, SDAR ≥ 11. [71 / 14 / 12] Attendee counts are not
   fixed: they move with every release.
   **Event 1433 (PSAR) released, pre-computed:** PSAR attendees +11 (its 10 pending-only accounts,
   plus 11651, which sits under SDAR on its delivered event 1069 until 1433 releases), SDAR −1,
   total attendees +10, converts unchanged everywhere. 3076 also holds a pending 1433 order but its
   latest delivered event is already PSAR's, so it does not move. If event 1333's order also
   releases, SDAR +1 and the total +1. All 11 pending-only accounts have no paid listing and no
   source.
5. `name: "No host"`, events 10, converts 9 (the nine `skip_latest_unhosted`), already customers 3,
   attendees 51 — none of the pending events is unhosted, so a release does not move it. 46 rows
   (45 hosts + no host).
6. Matches step 2's Pending release section.

Results:
```
1 funnel 2343 - pending 1 = 2342; attendees 2342; rows sum 2342; totals_match true   expect all three equal, true
2 converts 203 already 151 attendee-only 1988
3 converts > attendees anywhere: 0   expect 0
4 NSDCR attendees 636 converts 71 already 66
4 PSAR attendees 809 converts 14 already 12
4 SDAR attendees 320 converts 12 already 13
5 last {name: "No host", events: 10, attendees: 51, converts: 9, already_customers: 3}; rows 46
6 pending [{event_id: 1333, host_name: "SDAR", accounts: 1, not_yet_attendees: 1}]
```

### 4. The endpoint

```bash
API=https://insgtapi.herokuapp.com
curl -s -H "Authorization: Bearer $OWNER_JWT" "$API/kpis/headshot_hosts" > tmp/roi-endpoint.json
jq '.metadata' tmp/roi-endpoint.json
jq -c '[.data[] | [.name, .events, .attendees, .converts, .alreadyCustomers]]' tmp/roi-endpoint.json > tmp/roi-endpoint-rows.json
heroku run --no-tty --exit-code rails runner 'puts HeadshotHostRoi.call[:rows].map { |row| [row[:name], row[:events], row[:attendees], row[:converts], row[:already_customers]] }.to_json' -a insgtapi > tmp/roi-service-rows.json
ruby -rjson -e 'puts JSON.parse(File.read("tmp/roi-endpoint-rows.json")) == JSON.parse(File.read("tmp/roi-service-rows.json")) ? "endpoint = read-out" : "DIFFER"'
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $SCHEDULER_JWT" "$API/kpis/headshot_hosts"
curl -s -o /dev/null -w '%{http_code}\n' "$API/kpis/headshot_hosts"
```

Expected: `metadata.totalsMatch` true and `metadata.attendees` = step 3's; `endpoint = read-out`
(a release between the two calls would show as a diff — re-run both); the scheduler and the
unauthenticated call both `401` (`authenticate_system_owner` renders 401, not 403). Compare parsed,
not with `diff`: Rails writes `&` as `\u0026` and `jq` as `&`, so a textual diff of identical rows
fails on "Windermere Homes & Estates". The scheduler check needs a user who holds no owner role; on
2026-10-15 every scheduler was also an owner, so the request spec's 401 for admin, scheduler and
photographer is the gate's evidence.

Results, 2026-10-15: `metadata` totals match, attendees 2,342 = step 3's; endpoint = read-out
(parsed); unauthenticated `401`; the scheduler token `200`, correctly, since its user is also an
owner (above).

Notes: the first owner curl returned **H12 after 30 s, every time**. Production's planner statistics
were stale: `pg_stat_user_tables` showed `last_analyze` and `last_autoanalyze` nil on `orders`,
`order_logs`, `marketing_events`, `organizations` and `accounts`, and 0 live rows on
`marketing_events`, so the counters had been reset and autovacuum had never re-analyzed. The planner
ran 6b's `sourced_event_before_listing` subquery as a nested loop rescanning `event_orders` per
event per account (455,509 scans, 60.2 s); the fresh local restore hashes it (0.48 s for the whole
query). `heroku pg:psql -a insgtapi -c "ANALYZE;"` at about 16:35 UTC fixed it — skipped only the
system catalogs it may not touch:

```
Running rails runner "
  connection = ActiveRecord::Base.connection
  connection.execute(\"SET statement_timeout = 120000\")
  connection.uncached do
    2.times do |attempt|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      connection.select_all(EventAttribution.credit_rows_sql).to_a
      puts \"run #{attempt + 1}: #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)} s\"
    end
  end
" on ⬢ insgtapi... up, run.7981
run 1: 1.79 s
run 2: 1.62 s
200 2.640782s
```


## Steps — event 7

Strictly after event 6 is curl-verified (done 2026-10-15). `apps/insgt-ops/DEPLOY.md` is the
procedure; these are the slice's parts of it.

### 5. Merge, tag, deploy

```bash
cd apps/insgt-ops
git switch main && git merge feat/headshot-host-roi-panel
git status --short                    # empty: a release goes from a clean main
git ls-remote --tags origin v9.67.0   # empty: the version is free
git tag v9.67.0
npm run deploy:prod                   # build:prod, upload, invalidate the control files
```

### 6. On site, as owner

Open `https://ops.insightphotos.net/#/kpis`. Expected, reasoned before the release from the
2026-10-15 read-out and checked against the dev restore on 2026-10-19 (brackets):

1. A "Headshot event hosts (all time)" card below "Marketing source breakdown", after 2–3 s of
   "Loading…" (the endpoint's production time, step 4).
2. The last row is **No host** [10 events · 51 attendees · 9 converts · 17.6% · 3 already
   customers · $5,540.00].
3. Rows by converts descending [NSDCR 71, PSAR 14, SDAR 12, RE/MAX Tidal 11, Windermere Homes &
   Estates-Rancho Bernardo 9 …], one per host in a same-minute curl of step 4 [46 rows].
4. The Total line equals that curl's `metadata` [198 events · 2,342 attendees · 203 converts (8.7%)
   · 151 already customers · $354,700.00 converts' lifetime value · 1 pending release]. A release
   between the curl and the page moves attendees: take them in the same minute.
5. Sort by Attendees, then again: No host stays last both ways.

Known, kept by decision (v14 §22): a first click on Converts, the default column, leaves the order
unchanged and clears the header arrow. The marketing source panel does the same on Gross.

Results, 2026-10-19: check 2 confirmed by Dan, so the card rendered. Checks 3–5, against a
same-minute curl, were not recorded.

## Rollback

**Event 7 first**, if both must go. In insgt-ops, `npm run rollback` lists the releases and
`npm run rollback -- <stamp>` restores 9.66.0's control files (`DEPLOY.md` §Rollback). Clients take
it at their next update check: minutes, not seconds. The panel against an API without the endpoint
would show its error state, not break the page, but there is no reason to leave it.

**Event 6:**

```bash
heroku rollback --app insgtapi
```

Nothing to undo in data: event 6 writes nothing. The nightly write runs the old `credit_rows_sql`
again, whose existing columns are identical to the new one's.

## Deploy log

- 2026-10-19: **event 7 released** as insgt-ops 9.67.0 (`main` merge cbc88d5a of 1eb796c4, the
  panel, and 0338b7fc, the version; tag `v9.67.0`). On site as owner, No host is the last row (Dan).
  Before the release, on the branch: the panel's Cypress spec red first, then green, and seven
  deliberate breaks each red; every KPIs-page spec 15 of 15; Vitest 609 of 609; the production
  build's warnings identical to `main`'s; the KPIs chunk 41.47 → 50.38 kB raw, 8.66 → 9.83 kB
  transferred. Unstubbed against the dev API, the panel rendered the endpoint's 46 rows, No host
  last, with the Total line equal to the 2026-10-15 read-out. `predeploy-review-angular` with one
  Codex pass: no blocker; the one should-fix (the default column's first header click) kept as is
  by Dan (v14 §22).

- 2026-10-15: **event 6 deployed** as release v649 (`master` merge b7b2de9f of the five commits
  afa851c6..9c81f15d). No migration. Read-out 14:49 UTC →
  `../architecture/headshot-host-roi-2026-10-15.md`. Event 1433 (PSAR) had released since the dev
  sync, exactly as pre-computed: PSAR attendees 798 → 809, SDAR 321 → 320, total 2,332 → 2,342,
  attendee only 1,978 → 1,988, converts 203 and already customers 151 unchanged; one pending release
  left (event 1333, SDAR). Step 3: 2,343 − 1 = 2,342 = rows sum, totals check OK, no row with more
  converts than attendees, NSDCR 71 · PSAR 14 · SDAR 12 converts (≥ 70 / 13 / 11), No host last
  (10 / 51 / 9 / 3), 46 rows. Step 4: H12 until `ANALYZE` at about 16:35 UTC (step 4's notes); then
  `credit_rows_sql` 1.6–1.8 s uncached and the endpoint 200 in 2.6 s, equal to the read-out. The
  read-out itself ran before the fix: a one-off dyno has no 30 s limit. Follow-ons in v13 §21.

- 2026-10-15: **verified on the dev sync** (production sync of 2026-10-14 04:41 UTC). Read-out 2.5 s
  including boot; `HeadshotHostRoi.call` ~20 ms warm. Totals 2,332 attendees · 203 converts · 151
  already customers · 1,978 attendee only; totals check OK; 46 rows, No host last (10 events, 51
  attendees, 9 converts, 3 already customers); NSDCR 636 / 71 / 66, PSAR 798 / 14 / 12, SDAR
  321 / 12 / 13; pending releases 1333 (1) and 1433 (12, 10 not yet attendees).
