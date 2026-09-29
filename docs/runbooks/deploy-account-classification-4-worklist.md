# Runbook: Account Classification Slice 4 — Worklist Ordering Deploy (events 2 and 3)

**Last updated:** 2026-09-28
**Repos:** insgt-api (event 2), insgt-ops (event 3)
**Estimated duration:** ~20 min for event 2 (most of it the curl table); ~15 min for event 3
**Status:** Draft. Event 2 (sub-slice 4c) is built on `feat/account-classification-slice-4-sort`
and verified on the 2026-09-28 dev sync; not yet committed, merged or deployed. Event 3 (sub-slice
4d, insgt-ops 9.60.0) is not yet built.

## Summary

Ships sub-slice 4c of `docs/architecture/account-classification.md` §4.1 and §9 (plan:
`docs/plans/account-classification-slice-4.md`, gaps G11–G16, decisions 6–10): the classification
worklist ordering on the API, and, on the same machinery, the two segment filters. No migration.

- `GET /accounts` and `POST /accounts/export` accept `sort=rolling_365_parent_count` with
  `direction=asc|desc` (`desc` when absent, §4.1's direction). `AccountQuery#order_by_sort!` adds a
  `LEFT JOIN account_metrics`, appends the column to the select, widens the `GROUP BY` under
  `only_once`, and orders `DESC NULLS LAST, accounts.id ASC`. Anything else — an unknown sort, the
  camelCase spelling, `ASC`, `direction` without `sort` — is a **400**, never a silent fallback.
  With no `sort` the index is byte-identical to today's.
- A sorted index row carries `rolling365ParentCount` (null = no metrics row or never recomputed;
  0 = a real zero) for system_admin, system_scheduler and system_owner only — the metrics
  endpoint's allow-list — and only when the search selected it. Unsorted calls, `show`, and every
  order view that renders an account are unchanged.
- The accounts CSV export gains **`Shoots (365d)` as its twelfth and last column**, read from
  `account_metrics` for every export, sorted or not. The eleven existing columns keep their names
  and order.
- `lifecycle_type=<name>` and `value_type=<name>` filter by the §4.2 / §4.3 labels (the enum name
  on the wire, the integer in SQL, a WHERE on the same LEFT JOIN); an unknown name is a 400 on
  index and export.

**What moves for a human, on event 2.** One thing: every accounts export made from ops after the
push has twelve columns. If the CRM import maps by column position rather than header name, its
mapping needs extending once (decision 9's recorded risk). Nothing else is visible until event 3
— the API accepts params nobody sends yet.

**What moves for a human, on event 3** (4d, 9.60.0, not yet built): Don and Dan get a
Classification worklist button that lists unclassified teams most-active-first with the count
beside each, `sort` in the URL, the header arrows inert while server-sorted, and Lifecycle and
Value selects beside Team Type.

## Where the commands run

Every command below runs **on the host**, from `apps/insgt-api` inside the platform checkout (the
devcontainer has no `heroku` CLI); `tmp/` is insgt-api's own gitignored scratch directory. The
curls need a JWT for a **system_admin** user (the export rows, a **system_owner**). Take it from a
logged-in ops session (the `Authorization` header of any request in the browser's network panel)
or mint it with `heroku run rails runner` from a known user's `api_key` and `jwt_secret`, into a
shell variable only — **never into this file, a log, or a commit**:

```bash
export API=https://insgtapi.herokuapp.com
export JWT='<system_admin token>'        # and OWNER_JWT='<system_owner token>' for the export rows
get() { curl -s -H "Authorization: Bearer $JWT" "$API/accounts?$1"; }
code() { curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $JWT" "$API/accounts?$1"; }
```

## Deploy order and the window it closes

**There is no window.** No migration, no maintenance mode, not scheduler-window sensitive
(nothing touches `metrics:recompute` or any calculator). Rolling-safe in both directions: old code
on the new push changes nothing until a request carries `sort`; new code with the old ops (9.59.0)
receives no `sort` and builds the same SQL as before.

**Event 2 must be live and curl-verified before event 3.** Against the current API an unknown
`sort` param is **ignored, not 400ed** (`search_query_options` copies only what it is told), so a
9.60.0 ops against a pre-4c API gets a 200, unordered, with no `rolling365ParentCount` key — the
list looks sorted (the column header is there) and is not. `lifecycle_type` and `value_type` fail
the same way: a 200, unfiltered, under a selected segment. Both failures are silent, which is why
the order is API first, curl table, then ops. The same fact drives the rollback order below.

**Expected numbers are the 2026-09-28 sync's after the backfill `APPLY`; step 2's runner is the
authority on the day.** Hand classification through ops moves the worklist down and the head
shifts as shoots age in and out. On the sync:

| Figure | Value |
| :-- | --: |
| Worklist head (`account_type IS NULL`, `rolling_365_parent_count DESC NULLS LAST, id ASC`) | 11510 (26) · 4513 (16) · 11213 (12) · 6526 (7) · 11575 (6) |
| Worklist (`totalCount` for `account_type=unset`) | **2,691** |
| Worklist accounts with no metrics row | **0** |
| Worklist rows with a non-zero count | **138** → the 1 → 0 transition on **page 6** at `per_page=25` |
| `lifecycle_type=lapsed` | **1,572** |
| `value_type=anchor` | **20** (every count ≥ 12) |
| `lifecycle_type=lapsed&value_type=anchor` | **0** — structural (§4.3: `lapsed ⇒ value_type IS NULL`), on any database |

## Prerequisites

- [ ] The nine units committed onto `feat/account-classification-slice-4-sort` in the plan's
      order (commits 3–9; the per-unit patches under insgt-api `tmp/slice-4c-units/` are the
      split), `git status` clean
- [ ] insgt-api `bundle exec rspec` green on the branch: **1,819 examples, 0 failures** on
      2026-09-28 (after both review rounds)
- [ ] Both review rounds (`predeploy-review-rails`, an independent Claude reviewer and Codex on a copy
      of the tree, each round) closed with no blocker on 2026-09-28: seven findings fixed (fixture
      order, the SQL-text pins, three wordings, the who-may-filter pins, the evidence file); one open
      question for the engineer (whether sorting and segment filtering, usable by every index role
      like `account_type=`, should be gated to the three roles that read the count — see the plan's
      review record)
- [ ] `feat/account-classification-slice-4-sort` merged to `master` with `--no-ff`;
      `origin/master` pushed
- [ ] No deploy in flight
- [ ] **Baseline kept for step 4:** the router-log `service=` time of an unsorted worklist page
      before the push. Run `get "account_type=unset&per_page=25"` five times and copy the five
      `service=<n>ms` values from `heroku logs -n 50 -a insgtapi | grep 'path="/accounts'`
- [ ] Whoever owns the CRM import knows the export gains a twelfth column (header
      `Shoots (365d)`), and whether the import maps by position

## Steps — event 2

No database backup step: nothing in event 2 writes.

### 1. Deploy code

```bash
git checkout master && git merge --no-ff feat/account-classification-slice-4-sort
git push origin master
git push heroku master
heroku releases -n 1 -a insgtapi        # record the release beside the deploy log entry
```

No maintenance mode. Watch the build to completion. Nothing to migrate: `heroku run rails
db:migrate:status -a insgtapi` still reads `2026_09_12_120001` at the top.

### 2. The runner — the reference numbers, the same minute

```bash
heroku run --no-tty --exit-code rails runner 'puts AccountMetric.joins(:account).where(accounts: { status_type: 1, account_type: nil }).order(Arel.sql("rolling_365_parent_count DESC NULLS LAST, account_id ASC")).limit(5).pluck(:account_id, :rolling_365_parent_count).inspect; puts Account.where(status_type: 1, account_type: nil).count; puts Account.where(status_type: 1, account_type: nil).left_joins(:account_metric).where(account_metrics: { id: nil }).count; puts AccountMetric.joins(:account).where(accounts: { status_type: 1 }).where(lifecycle_type: :lapsed).count; puts AccountMetric.joins(:account).where(accounts: { status_type: 1 }).where(value_type: :anchor).count' -a insgtapi
```

Five lines: the worklist head as `[[id, count], …]`, the worklist count, the worklist accounts with
no metrics row (0 on the sync; small on any day — accounts created since the last sweep), the
`lapsed` population, the `anchor` population. On the sync: `[[11510, 26], [4513, 16], [11213, 12],
[6526, 7], [11575, 6]]` · 2691 · 0 · 1572 · 20. Every expectation in step 3 reads from these five
lines, not from this file.

### 3. The curl table

Every row against production, with the runner's five lines as the expectations.

| Call | Expect |
| :-- | :-- |
| `get "account_type=unset&sort=rolling_365_parent_count&direction=desc&per_page=5" \| jq -c '[.data[] \| [.id, .rolling365ParentCount]], .metadata.totalCount'` | the runner's five pairs, in order; `totalCount` = the runner's second line |
| `get "account_type=unset&per_page=5" \| jq -c '.metadata.totalCount, ([.data[] \| has("rolling365ParentCount")] \| any)'` | the same `totalCount`; `false` — no row carries the key unsorted |
| `get "account_type=unset&sort=rolling_365_parent_count&per_page=25&page=<n>" \| jq -c '[.data[] \| [.id, .rolling365ParentCount]]'` where `25(n−1) <` (non-zero worklist rows) `≤ 25n` — page 6 on the sync (138 non-zero rows) | the last positive count and the first zero on the same page; zeros in ascending id from there |
| `…&sort=rolling_365_parent_count&per_page=25&page=<metadata.pageCount>` (108 on the sync) | rows reading `"rolling365ParentCount": null` = the runner's third line (0 on the sync); every other row 0, ids ascending |
| `get "account_type=unset&sort=rolling_365_parent_count&only_once=true&per_page=5&includes[]=order_count" \| jq -c '[.data[].orderCount], .metadata.totalCount'` | **200** (decision 7: the `GROUP BY` is widened, not refused); every `orderCount` 1; `totalCount` equal to `get "account_type=unset&only_once=true&per_page=5"`'s (478 on the sync) |
| `code "sort=password_digest"` · `code "sort=rolling365ParentCount"` · `code "direction=asc"` · `code "sort=rolling_365_parent_count&direction=ASC"` | four **400**s, body `{"errors":"Bad request"}` |
| `curl -s -X POST -H "Authorization: Bearer $OWNER_JWT" "$API/accounts/export?account_type=unset&sort=rolling_365_parent_count&direction=desc" \| jq -r .url` then `curl -s -o tmp/worklist-export.csv "<url>"` | 200 with a `url`; `head -1 tmp/worklist-export.csv` ends `…,Industry,Shoots (365d)` (twelve columns, the first eleven unchanged); `sed -n 2p` starts with the runner's first id and its last cell is that id's count; `wc -l` = the worklist count + 1 |
| `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Authorization: Bearer $OWNER_JWT" "$API/accounts/export?sort=password_digest"` | **400**, nothing uploaded |
| `get "lifecycle_type=lapsed&per_page=1" \| jq .metadata.totalCount` | the runner's fourth line |
| `get "value_type=anchor&sort=rolling_365_parent_count&per_page=25" \| jq -c '.metadata.totalCount, [.data[].rolling365ParentCount]'` | the runner's fifth line; every count ≥ 12, descending |
| `get "lifecycle_type=lapsed&value_type=anchor&per_page=1" \| jq .metadata.totalCount` | **0** — structural; a non-zero here is a data bug, not drift |
| `code "lifecycle_type=bogus"` · `code "value_type=ANCHOR"` · `code "lifecycle_type=6"` | three **400**s |
| `totalCount` for `name=ro`, `name=ro&only_once=true` and `only_once=true`, each with and without `sort=rolling_365_parent_count` | equal pairwise (the join cannot move `COUNT(DISTINCT accounts.id)`; 414 / 81 / 979 on the sync) |

**If any 400 row returns 200** the old code is still serving (the build has not finished, or the
push did not land): stop and check `heroku releases`. **If the sorted call returns rows without
`rolling365ParentCount`** for the admin token, the same. Do not proceed to event 3 on either.

### 4. The router-log latency check

```bash
for i in 1 2 3 4 5; do get "account_type=unset&sort=rolling_365_parent_count&direction=desc&per_page=25" > /dev/null; done
for i in 1 2 3 4 5; do get "account_type=unset&only_once=true&sort=rolling_365_parent_count&direction=desc&per_page=25" > /dev/null; done
heroku logs -n 100 -a insgtapi | grep 'path="/accounts' | grep -o 'sort=[^ ]*\|only_once=[^& ]*\|service=[0-9]*ms'
```

Compare the sorted `service=` times with the prerequisite baseline. Measured on the sync the sort
adds nothing (bare SQL 10.5 ms sorted vs 12.3 ms unsorted median; full local round trip 0.205 s vs
0.247 s; with `only_once` 0.278 s vs 0.301 s), so **anything over ~50 ms above the unsorted call
is a finding**, and so is a sorted `only_once` call that is not within noise of its unsorted twin.

### 5. insgt-ops (9.59.0, still live)

Nothing to deploy. Team Type = **Unset** still lists the worklist, unordered, and the count matches
the runner's second line. An export from the page downloads with twelve columns.

## Steps — event 3 (insgt-ops 9.60.0; sub-slice 4d, not yet built)

Placeholder until `feat/account-worklist-sort` exists (plan commits 10–17, G17–G19). Preconditions,
both from this runbook: event 2 deployed and **every row of step 3 passing in production**.

`scripts/deploy.sh` neither tags nor refuses a dirty tree (it warns and deploys anyway), and the tag
series already skips `v9.53.0` and `v9.54.0`, so the release is stated step by step:

```bash
cd apps/insgt-ops
git checkout main && git pull --ff-only && [ -z "$(git status --porcelain)" ] && echo clean
grep '"version"' package.json                          # 9.60.0
npm run build:prod                                     # green before anything ships
git tag v9.60.0 && git push origin main --tags
npm run deploy:prod                                    # build:prod + upload + invalidate
aws s3 cp s3://insgt-apps/ops/releases/<epoch>/RELEASE.txt -   # the SHA that shipped; record it below
```

Then on `https://ops.insightphotos.net/#/accounts` (a hard reload first): press **Classification
worklist** → Team Type reads Unset, Sort by reads the 365-day option, the URL carries
`accountType=unset&sort=rolling_365_parent_count`, the request carries
`sort=rolling_365_parent_count&direction=desc`, the first row is the runner's first id with its
count under **Shoots (365d)**, the header arrows are inert; page 2 continues the server order;
**Clear** removes the column, the arrows return, the URL is bare;
`/#/accounts?sort=rolling_365_parent_count` in a new tab loads sorted on entry with Team Type
"Any". Lifecycle = Lapsed and Find → the request carries `lifecycle_type=lapsed` and the count
matches the runner's fourth line; Value = Anchor with Lifecycle = Lapsed → the empty state;
`/#/accounts?lifecycleType=lapsed` restores the select and searches on entry. Record the
`ng build` chunk delta.

## Rollback

**Order: ops first, then the API**, and never the API alone while 9.60.0 is live. A 9.60.0 ops
against a rolled-back API is the silent failure above — 200, unordered, no `rolling365ParentCount`,
a Shoots (365d) column of em dashes over an unsorted list with inert arrows — and it lasts until
the client discovers the rolled-back ops build.

### insgt-ops (event 3)

```bash
cd apps/insgt-ops
npm run rollback                     # lists releases with SHA and branch
npm run rollback -- <epoch>          # the 9.59.0 release
```

**The window is real but bounded.** Silent deferred updates have been live since v9.55.0, so a
client already running 9.60.0 keeps it until its next update check (`UPDATE_CHECK_INTERVAL_MS`,
5 min, or sooner on a trigger) and then a safe reload — the next navigation, a return to the tab
after 10 s hidden, or 60 s idle (plan G19). Roll the ops build back, wait for that window to pass
(or tell the two users to reload), then roll the API back if it must go too. `DEPLOY.md:111–113`'s
"propagation is fast" sentence predates silent updates; 4d's doc commit corrects it.

### insgt-api (event 2)

```bash
heroku rollback --app insgtapi
```

Nothing to undo in data or schema: event 2 writes nothing and adds no column. After the rollback
every export is back to eleven columns.

## Deploy log

- 2026-09-28: **verified on the dev sync** (production sync of 19:05 UTC with the backfill
  rehearsal `APPLY` at 19:31 UTC: 4,144 active accounts, 1,435 `agent`, worklist 2,691). Suite
  1,819 examples, 0 failures after two review rounds. Fourteen deliberate breaks pasted red across
  the four app files during implementation, seven more for the review fixes. A
  local server on the working tree and system_admin / system_owner JWTs minted read-only: the
  sorted head `[[11510, 26], [4513, 16], [11213, 12], [6526, 7], [11575, 6]]` with `totalCount`
  2,691 and the same count unsorted with no key; the 1 → 0 transition inside page 6 (12338 → 7);
  page 108 with 16 zero rows, no nulls, ids ascending; `only_once` + sort a 200 with every
  `orderCount` 1 and `totalCount` 478 both ways; the four sort 400s and the three filter 400s;
  `lapsed` 1,572, `anchor` 20 (48 … 12 descending), lapsed ∧ anchor 0; `totalCount` equal with
  and without the sort for four shapes. The export's 400 verified; its **200 path was not** — the
  dev IAM user may not `PutObject` to the export bucket, so nothing uploaded — and the CSV was
  verified through `AccountCsvExportService` with the controller's exact params instead: twelve
  headers ending `Industry, Shoots (365d)`, 2,691 rows, `11510 → 26` first, 2,553 zeros, 0 blanks,
  every account's twelve cells identical sorted and unsorted, the sorted ids equal to the SQL
  worklist order. Latency, five local runs each: unsorted 0.247 s, sorted 0.205 s; `only_once`
  0.301 s unsorted, 0.278 s sorted (medians).
- `<date>`: **deployed to production (event 2).** `<release>`; runner lines `<…>`; curl table
  `<every row>`; router-log `service=` sorted `<n>` ms vs unsorted `<n>` ms; export
  `<header, first id, row count>`.
- `<date>`: **9.60.0 released (event 3).** `<tag, RELEASE.txt SHA, chunk delta, the ops checks>`.
