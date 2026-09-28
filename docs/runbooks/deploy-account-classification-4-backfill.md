# Runbook: Account Classification Slice 4 — Backfill Deploy (events 1 and 4)

**Last updated:** 2026-09-28
**Repos:** insgt-api
**Estimated duration:** ~30 min for event 1 (most of it reading two memos); ~15 min for event 4
**Status:** Event 1 deployed to production 2026-09-28; `APPLY` ran at 19:52:47 UTC (release not recorded). Event 4 (the retirement, sub-slice 4e) not yet built.

## Summary

Ships sub-slices 4a and 4b of `docs/architecture/account-classification.md` §4.1 (plan:
`docs/plans/account-classification-slice-4.md`): two rake tasks and their specs, no migration.

- `organizations:audit_types` — the organization type audit slice 4 blocks on. Read-only. Prints
  the type table, what a blank type means, every place NARPM could be represented, the
  property-management-named firms, the edge shape, parent edges, and a **verdict line computed from
  the run's own counts**.
- `account_classification:backfill_account_type` — the tiered backfill of `accounts.account_type`.
  **Dry run by default**; `APPLY=true` writes. Two tiers, first match wins: `internal` from
  `AccountTypeBackfill::INTERNAL_SEED_ACCOUNT_IDS` (eleven ids), then `agent` for an active, NULL
  account with an active edge to an active brokerage-typed organization, a qualifying parent
  (`Order.qualifying_parents`, composed as `to_sql`), and not a property-manager candidate (held out
  for hand classification). Never overwrites a non-NULL value; never touches a soft-deleted account.
  Writes with `update_all`, `updated_by_id = 1` and **one** batch `updated_at`, in one transaction
  with two self-checks.

**Deploy event 1** pushes both tasks. **`APPLY` is a separate, manual production event** behind two
reads that must be done first: the audit read-out (its verdict gates the backfill's tiers) and the
dry-run memo (the day's numbers). Nothing in the product changes on the push; everything changes on
`APPLY`.

**What moves for a human, on `APPLY`.** On ops.insightphotos.net (9.59.0) Team Type = **Agent**
rises by the memo's written count, **Internal** gains 549 and 885, and the **Unset** worklist falls
by the total written. The marketing-source KPI does **not** move: the four internal-account
constants stay in force until event 4.

**Deploy event 4** (sub-slice 4e, four commits on `feat/account-classification-slice-4-retire`, not
yet built) retires the four constants onto `Account.account_type_internal`. It is gated on a
production invariant this runbook establishes at step 7, and it is the one event that moves an
owner-visible number (the KPI's `total_accounts` and gross). Its section is a placeholder until
4e exists.

## Where the commands run

Every command below runs **on the host**, from `apps/insgt-api` inside the platform checkout; the
devcontainer has no `heroku` CLI. Two roots follow from that, as in the slice 1a/1b runbook:
`tmp/` is insgt-api's own (gitignored) scratch directory, and `../../docs/architecture/` is the
platform repo's docs directory — insgt-api has no `docs/architecture` of its own. A one-off dyno's
filesystem is discarded when it exits and it cannot read a file on the host, so every capture is a
redirect of the dyno's stdout, and every comparison against a local file happens locally.

## Deploy order and the window it closes

**There is no window.** No migration, no maintenance mode, not scheduler-window sensitive: the
nightly `metrics:recompute` never reads `account_type` (`grep -n account_type
app/services/account_metrics/calculator.rb` is empty). Old code on the new push: nothing reads the
two rake files until someone invokes them. New code on the old data: the tasks read what is there.
Rolling-safe in both directions.

**The order inside event 1 is load-bearing.** Audit read-out → dry run → STOP and read → `APPLY` →
second dry run → invariants. The audit runs before the dry run so that a production database that
contradicts the survey (a NARPM organization, event or edge; a property-management firm typed other
than brokerage) prints its own verdict before anything is written, and the tiers re-open then
rather than after.

**Expected numbers are the 2026-09-28 sync's; the day's dry run is the authority.** More accounts
will have been typed by hand through ops since, so expect fewer writes, never more. On the sync:

| Tier | To write | Already typed | Held out |
| :-- | --: | --: | --: |
| `internal` | **2** (549, 885) | 9 | — |
| `agent` | **1,417** | 15 (13 `agent` + 2 `property_manager`) | 5 (789, 2191, 8209, 11510, 11983) |
| NULL after | **2,692** = 4,111 − 1,417 − 2 | | |

## Prerequisites

- [ ] `feat/account-classification-slice-4-backfill` merged to `master` with `--no-ff`;
      `origin/master` pushed
- [ ] insgt-api `bundle exec rspec` green on the branch: **1,747 examples, 0 failures** on
      2026-09-28 (after both review rounds)
- [ ] Both review rounds (`predeploy-review-rails` with the Codex pass) closed with no blocker
- [ ] No deploy in flight
- [ ] **No Heroku config var named `APPLY`, `OUT` or `CSV`.** The task reads those generic names
      (plan G4, the shift memo's shape), so a config var `APPLY=true` would turn step 4's dry run
      into a write, and `OUT`/`CSV` would send the memo to a file on a dyno whose filesystem is
      discarded. Expect no output from:

      ```bash
      heroku config -a insgtapi | grep -E '^(APPLY|OUT|CSV):'
      ```
- [ ] Baseline kept: **the production "before" list**, every typed row by id. Step 7 compares it
      row for row after `APPLY`:

      ```bash
      heroku run --no-tty --exit-code rails runner 'puts Account.where.not(account_type: nil).order(:id).pluck(:id, :account_type, :updated_by_id, :updated_at).map { |row| row.join("|") }' -a insgtapi > tmp/account-type-before-2026-09-28.txt
      wc -l tmp/account-type-before-2026-09-28.txt     # <n> rows; 33 on the 2026-09-28 sync
      ```

- [ ] Baseline kept for event 4 (skip for event 1 alone): the marketing-source KPI's
      `total_accounts` and `total_gross_cents`, and `rake metrics:margin_ltv_exclusions_manifest`

## Steps — event 1

### 1. Back up the database

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2026-09-28_lock.dump
```

Cheap, and the reversal in the Rollback section is the same one line whether or not it exists.

### 2. Deploy code

```bash
git checkout master && git merge --no-ff feat/account-classification-slice-4-backfill
git push origin master
git push heroku master
```

No maintenance mode. Watch the build to completion. Nothing to migrate: `heroku run rails
db:migrate:status -a insgtapi` still reads `2026_09_12_120001` at the top.

### 3. The audit read-out

```bash
heroku run --no-tty --exit-code rake organizations:audit_types -a insgtapi > ../../docs/architecture/organization-type-audit-2026-09-28.txt
tail -1 ../../docs/architecture/organization-type-audit-2026-09-28.txt
```

Read the whole thing; it is the body of the platform repo's
`docs/architecture/organization-type-audit-2026-09-28.md`. The last line is the gate:

```
Verdict: property_manager is not derivable from organizations: 0 NARPM organizations, 0 NARPM events, <n> property-management firms typed brokerage, 0 typed otherwise.
```

On the 2026-09-28 sync the four numbers read **0, 0, 6, 0** and the six firms are 349, 1786, 1951,
3073, 3276, 3342. **If the line begins "Verdict: property_manager may be derivable" — STOP.** A
NARPM organization or event, or a property-management firm typed other than brokerage, means the
backfill's `TIERS` and hold-out re-open before `APPLY` (plan G1, G5). Do not proceed to step 4.

Two other lines to note for the audit document, neither a gate: "Active edges to a soft-deleted
organization" (13 on the sync, all to organization 15, a brokerage deleted in 2022) and the upper
bound on defaulted or free-text brokerages (255 of 643 on the sync).

### 4. The dry run — read it, then STOP

```bash
heroku run --no-tty --exit-code rake account_classification:backfill_account_type -a insgtapi > tmp/account-type-dry-run-2026-09-28.md
# a one-off dyno's filesystem is discarded on exit and stdout is the only channel home, so the per-account plan is a second read-only run with the memo silenced
heroku run --no-tty --exit-code rake account_classification:backfill_account_type OUT=/dev/null CSV=/dev/stdout -a insgtapi > tmp/account-type-dry-run-2026-09-28.csv
```

Both runs are read-only (`APPLY` absent). About 2 s of query time on the sync; dyno start-up
dominates. Read, in this order:

1. **The title** reads `(DRY RUN)`.
2. **Population**: active accounts, typed by value, worklist. The typed count is the "before" list's
   row count.
3. **The tier table.** `internal` to write is the seed ids still NULL (2 on the sync, or fewer if
   549 or 885 has been typed by hand since); `agent` to write is the day's number (≤ 1,417); held
   out is the five, or fewer if one has been classified by hand.
4. **`agent — held out`** names the property-manager candidates the rule would have written. On
   the sync: 11510 Colleen McDade, 11983 Chun Cai, 789 Anna Song, 8209 John Frasca, 2191 Susan
   Miller.
5. **List (c)** is the hand-classification list (the five plus 11912 Dan Recob and 11625 NARPM
   NARPM); **list (d)** names the two test-pattern false positives (2479, 9958) that are
   deliberately not written; **list (f)** names typed rows the rules disagree with (six on the
   sync) — information, not a blocker.
6. **"NULL after (planned)"** is the arithmetic to check against step 7.

STOP here. `APPLY` is a decision made on this memo, not a step that follows it.

### 5. APPLY

```bash
heroku run --no-tty --exit-code rake account_classification:backfill_account_type APPLY=true -a insgtapi > ../../docs/architecture/account-type-backfill-memo-2026-09-28-production.md
```

That file, in the platform repo's `docs/architecture/`, is the hand-over copy, as slice 1b's
production memo was. Its provenance line reads
`insgt-api \`unknown\`` on a dyno (a slug carries no `.git`), so record the release beside it:
`heroku releases -n 1 -a insgtapi` (not recorded on 2026-09-28). Read its title and its **After**
section first:

```
# Account classification — account_type backfill (APPLIED at <stamp with microseconds>)
…
## After
- Applied at <stamp> by user 1 (User.system). Every written row carries `updated_by_id = 1 AND updated_at = '<stamp>'`.
- Written: internal <n> · agent <n>
- Self-check 1 (planned = written): OK — internal <n> = <n> · agent <n> = <n>
- Self-check 2 (pre-typed rows unchanged): OK — <n> rows re-read identical
- NULL before <n> → after <n>
- Reversal, if ever wanted, keyed on the pair: `Account.where(updated_by_id: 1, updated_at: '<stamp>').update_all(account_type: nil, updated_at: Time.current)`
```

The tier table in this memo must equal the dry run's (step 4) unless someone classified an account
between the two runs. **If the command exits non-zero with `AccountTypeBackfill::SelfCheckFailed`,
nothing was written**: a planned row stopped qualifying between plan and apply — classified through
ops, soft-deleted, its brokerage edge or shoot removed, a property-manager signal added — or a
pre-typed row changed under the write. Each tier's UPDATE repeats its whole predicate, so such a row
falls out of the WHERE, the count comes up short, the transaction rolls back, and the fix is to
re-run step 4 and then this step. That guarantee is statement-time: it holds when each UPDATE
evaluates, and the transaction locks the account rows, not the edges or the orders, so run `APPLY`
at a quiet moment rather than during a burst of ops edits. Copy the stamp; every later step keys on
it.

### 6. Second dry run: every tier plans 0

```bash
heroku run --no-tty --exit-code rake account_classification:backfill_account_type -a insgtapi | sed -n '/^## Tiers/,/^NULL after/p'
```

Expect `| internal | 0 | <11> | — |`, `| agent | 0 | <n> | <held out> |`, and under "agent
candidates" the written rows now read as already typed by **user 1**. On the dev sync after
`APPLY`: `internal 11 (user 2: 9 · user 1: 2)`, `agent 1,430 (user 1: 1,420 · user 2: 10)`.

**Production, 2026-09-28** (one-off dyno `run.2446`):

```
| Tier | To write | Already typed | Held out |
| :-- | --: | --: | --: |
| internal | 0 | 11 | — |
| agent | 0 | 1,433 | 5 |

- internal seed: internal 11 (user 2: 9 · user 1: 2)
- agent candidates: agent 1,431 (user 1: 1,421 · user 2: 10) · property_manager 2 (user 1: 1 · user 2: 1)

NULL after (planned): 2,691 = 2,691 − 0 − 0.
```

The arithmetic closes: 1,431 agent candidates typed = 13 before the run + 1,418 written; 1,421 by
user 1 = 3 console writes + 1,418.

### 7. Invariants

Against `accounts`; the CSV from step 4 is a local convenience, not the source of truth. Two parts:
a runner on a dyno for the counts, which prints the batch's ids as its last line, then the "before"
list and the CSV compared on the host, because a dyno cannot read a local file. Replace `<stamp>`
with the memo's microsecond stamp. All expected values are exact.

```bash
heroku run --no-tty --exit-code rails runner '
  stamp = Time.zone.parse("2026-09-28T19:52:47.158499Z")
  batch = Account.where(updated_by_id: 1, updated_at: stamp)
  puts "1 batch rows (updated_by_id = 1 AND updated_at = stamp): #{batch.count}   expect the memo Written total"
  puts "2 batch rows outside {agent, internal}: #{batch.where.not(account_type: %w[agent internal]).count}   expect 0"
  puts "3 batch by type: #{batch.group(:account_type).count.inspect}   expect the memo per-tier counts"
  puts "5 NULL active after: #{Account.where(status_type: 1, account_type: nil).count}   expect the memo NULL after = NULL before - written"
  puts "6 soft-deleted rows carrying a type: #{Account.where(status_type: 2).where.not(account_type: nil).count}   expect 0"
  internal_ids = Account.account_type_internal.pluck(:id).sort
  puts "7 internal ids: #{internal_ids.inspect}; includes 2, 89, 2555: #{([2, 89, 2555] - internal_ids).empty?}   expect true (the event 4 precondition)"
  by_type = Account.where(status_type: 1).group(:account_type).count
  puts "8 active by type: #{by_type.sort_by { |type, _| type.to_s }.inspect}; sum #{by_type.values.sum} = active #{Account.where(status_type: 1).count}"
  puts "9 post-APPLY worklist head: #{AccountMetric.joins(:account).where(accounts: { status_type: 1, account_type: nil }).order(Arel.sql("rolling_365_parent_count DESC NULLS LAST, account_id ASC")).limit(6).pluck(:account_id, :rolling_365_parent_count).inspect}"
  puts "batch_ids: #{batch.order(:id).pluck(:id).join(",")}"
' -a insgtapi > tmp/account-type-invariants-2026-09-28.txt
grep -v "^batch_ids" tmp/account-type-invariants-2026-09-28.txt
```
**Production, 2026-09-28**, every line as expected (1,420 = 1,418 + 2; 2,691 = 4,111 − 1,420;
1,435 = 17 + 1,418):

```
1 batch rows (updated_by_id = 1 AND updated_at = stamp): 1420
2 batch rows outside {agent, internal}: 0
3 batch by type: {"internal" => 2, "agent" => 1418}
5 NULL active after: 2691
6 soft-deleted rows carrying a type: 0
7 internal ids: [2, 3, 4, 5, 6, 89, 549, 885, 1534, 2555, 11589]; includes 2, 89, 2555: true
8 active by type: [[nil, 2691], ["agent", 1435], ["commercial", 1], ["internal", 11], ["property_manager", 6]]; sum 4144 = active 4144
9 post-APPLY worklist head: [[11510, 26], [4513, 16], [11213, 12], [6526, 7], [11575, 6], [11679, 6]]
```

Invariant 4, on the host: every row of the prerequisites' "before" list reads the same after, and
the rows that are new are exactly the batch. Re-run the prerequisites' command into an "after"
file and compare the two locally:

```bash
heroku run --no-tty --exit-code rails runner 'puts Account.where.not(account_type: nil).order(:id).pluck(:id, :account_type, :updated_by_id, :updated_at).map { |row| row.join("|") }' -a insgtapi > tmp/account-type-after-2026-09-28.txt
comm -23 <(sort tmp/account-type-before-2026-09-28.txt) <(sort tmp/account-type-after-2026-09-28.txt)               # 4a: expect no output — no before row changed
comm -13 <(sort tmp/account-type-before-2026-09-28.txt) <(sort tmp/account-type-after-2026-09-28.txt) | wc -l       # 4b: expect invariant 1's count
comm -13 <(sort tmp/account-type-before-2026-09-28.txt) <(sort tmp/account-type-after-2026-09-28.txt) | grep -vc "|1|"   # 4c: expect 0 — every new row by user 1
```
**Production, 2026-09-28:** 4a no output (no before row changed), 4b 1,420, 4c 0.

Then the CSV cross-check, also on the host: the batch ids equal the CSV rows whose `action` is
`write`. The CSV comes from an earlier plan than the `APPLY` run's, so a one-row difference is drift
between the two runs (a shoot completing, a hand classification) and the `APPLY` memo is the
authority; a difference the memo's tier table does not account for is a bug:

```bash
ruby -rcsv -e 'puts CSV.read("tmp/account-type-dry-run-2026-09-28.csv", headers: true, encoding: "UTF-8").select { |row| row["action"] == "write" }.map { |row| row["account_id"].to_i }.sort.join(",")' > tmp/csv-write-ids.txt
diff <(sed -n "s/^batch_ids: //p" tmp/account-type-invariants-2026-09-28.txt) tmp/csv-write-ids.txt && echo "batch ids = CSV write ids"
```
**Production, 2026-09-28:** `batch ids = CSV write ids`.

**On the dev sync after `APPLY` (2026-09-28 15:25 UTC)**: 1 → 1,419; 2 → 0; 3 →
`{"agent" => 1417, "internal" => 2}`; 4a → no output, 4b → 1,419, 4c → 0 (the 33 before rows
unchanged); 5 → 2,692; 6 → 0; 7 → the eleven seed ids, true; 8 → `agent` 1,434 · `commercial` 1 ·
`internal` 11 · `property_manager` 6 · NULL 2,692, sum 4,144; 9 → 11510 (26), 4513 (16), 11213
(12), 6526 (7), 11575 (6), 11679 (6); the CSV's `write` ids equalled the batch ids.

### 8. Spot checks

Reasoned from the rules (plan G5–G8); re-derive the "before" column from the day's memo.

```bash
heroku run rails runner 'Account.where(id: [89, 2555, 11510, 789, 12209, 4, 549, 885, 88, 2479, 9958]).order(:id).each { |a| puts [a.id, a.name, a.account_type, a.updated_by_id, a.updated_at&.utc&.iso8601(6)].inspect }' -a insgtapi
```

| Account | Before | Rule | After |
| --: | :-- | :-- | :-- |
| 89 Insight Photos Marketing | `internal` | seed; already typed | `internal`, untouched (actor and stamp unchanged) |
| 2555 Jack Brown | `internal` | seed; not an `agent` match anyway (CRMLS only) | `internal`, untouched |
| 11510 Colleen McDade | NULL; brokerage, 26 shoots | `agent` match, **held out** (PM-named organization) | **NULL**, on list (c) |
| 789 Anna Song | NULL; brokerage, 14 lifetime shoots | held out | NULL, on list (c) |
| 12209 San Diego City Property Management | `property_manager` | `agent` match, already typed | `property_manager`, on list (f) |
| 4 Sally Testerton | `internal`; brokerage edge, no shoot | seed; list (a)'s only typed member | `internal`, untouched |
| 549 Jose Esqueda | NULL | seed (decision 2) | **`internal`**, `updated_by_id` 1, the batch stamp |
| 885 Dan Harms | NULL | seed (decision 2) | **`internal`**, the batch stamp |
| 88 Tamara Kapa | NULL; rolling 30; edge 1196 → organization 2 (type 2) | `agent` match, not held out | **`agent`**, the batch stamp; the memo's first `agent` row |
| 2479 Ana Maria Goodemote | NULL | pattern hit, not seeded | NULL, on list (d) |
| 9958 Kyle Weckesser | NULL; $1,870 lifetime | pattern hit, not seeded | NULL, on lists (b) and (d) |

All eleven matched on the dev sync after `APPLY`.

**Production, 2026-09-28**, all eleven as reasoned. 88, 549 and 885 carry the batch pair
(`updated_by_id` 1, `2026-09-28T19:52:47.158499Z`); the four pre-typed rows keep their 2026-09-14
and 2026-09-11 stamps; the held-out and pattern rows are still NULL:

```
[4, "Sally Testerton", "internal", 2, "2026-09-14T13:20:51.588170Z"]
[88, "Tamara Kapa", "agent", 1, "2026-09-28T19:52:47.158499Z"]
[89, "Insight Photos Marketing", "internal", 2, "2026-09-14T13:22:14.238651Z"]
[549, "Jose Esqueda", "internal", 1, "2026-09-28T19:52:47.158499Z"]
[789, "Anna Song", nil, 1, "2025-07-10T01:45:46.682395Z"]
[885, "Dan Harms", "internal", 1, "2026-09-28T19:52:47.158499Z"]
[2479, "Ana Maria Goodemote", nil, nil, "2020-03-11T18:39:21.347708Z"]
[2555, "Jack Brown", "internal", 2, "2026-09-14T13:21:34.415462Z"]
[9958, "Kyle Weckesser", nil, nil, "2025-06-01T18:34:16.408006Z"]
[11510, "Colleen McDade", nil, 1, "2026-07-14T10:00:47.586600Z"]
[12209, "San Diego City  Property Management", "property_manager", 1, "2026-09-11T16:11:39.523758Z"]
```

### 9. insgt-ops (9.59.0, already live)

On `https://ops.insightphotos.net/#/accounts`: Team Type = **Agent** count = the pre-`APPLY` agent
count + the memo's `agent` written; **Internal** = 11; **Unset** = the memo's "NULL after". Both
filters read active accounts only, so Agent + Unset + the other typed values = the active account
count (invariant 8's sum). 11510 is still Unset.

**Production, 2026-09-28:** not recorded. From invariant 8 the expected reads are Agent 1,435,
Internal 11, Unset 2,691; unverified on the ops screen.

## Steps — event 4 (retirement; not yet built)

Placeholder until `feat/account-classification-slice-4-retire` exists (plan commits 18–21, G20,
G21). Preconditions, both from this runbook: `APPLY` has run in production and invariant 7 holds
(`Account.account_type_internal.pluck(:id) ⊇ [2, 89, 2555]`).

Before the push, capture the KPI baseline (`KpisController#marketing_sources`: `total_accounts`,
`total_gross_cents`) and `heroku run rake metrics:margin_ltv_exclusions_manifest -a insgtapi`.
After: `total_accounts` falls by exactly the number of active `internal` accounts outside
{2, 2555} — **9** after `APPLY` (3, 4, 5, 6, 89, 1534, 11589, 549, 885); the manifest lists all
eleven by name; `accounts:composition`'s "Excluded:" line names the same set;
`EXCLUDED_ACCOUNT_IDS=` still narrows it. A gross delta not explained by those names is a
finding. This table is the slice's shift memo.

| | Before | After | Delta |
| :-- | --: | --: | --: |
| `total_accounts` | `4142` | `<n>` | −9 |
| `total_gross_cents` | `372408100` | `<n>` | `<explained by the nine>` |

## Rollback

### Code

```bash
heroku rollback --app insgtapi
```

Leaves the written rows in place, **which is correct**: they are data, the ops dialog edits them,
and old code reads `account_type` exactly as new code does. Nothing else to undo.

### Data (only if ever wanted)

One line, keyed on the batch pair from the memo, documented and deliberately not built as a task:

```bash
heroku run rails runner 'puts Account.where(updated_by_id: 1, updated_at: Time.zone.parse("<stamp>")).update_all(account_type: nil, updated_at: Time.current)' -a insgtapi
```

The actor alone would not do: console writes already carry `updated_by_id = 1`.

## Deploy log

- 2026-09-28: **verified on the dev sync** (production sync of 2026-09-28: 4,144 active accounts,
  33 typed). Dry run on a read-only connection: `internal` 2 (549, 885), `agent` 1,417, held out
  [789, 2191, 8209, 11510, 11983], NULL after 2,692, lists (a)–(g) 14 / 638 (538 with no
  organization) / 7 / 2 / 12 / 6 / 1 — every line equal to the same day's re-baseline queries.
  `APPLY=true` on the dev sync at 15:25:45.430277 UTC: written internal 2 · agent 1,417, both
  self-checks OK, NULL 4,111 → 2,692, 2.3 s wall. Second dry run planned 0 in every tier. All nine
  step 7 invariants held and the CSV `write` ids equalled the 1,419 batch ids; all eleven step 8
  spot checks as reasoned. The audit read-out on the same sync: verdict 0, 0, 6, 0.
- 2026-09-28, 15:39 EDT: **deployed to production.** Merged `--no-ff` as 25a694c3 (e195ae98 the
  audit, 3976ea07 the backfill, 96544bf6 the dollar formatting, e59a0e19 the review fixes), pushed
  to origin and heroku. No migration. Before the push: a dress rehearsal of the whole sequence on a
  fresh production sync taken 19:05 UTC (`account-type-backfill-memo-2026-09-28-test.md`), whose
  memo came out identical to production's apart from the stamps. Then in production: the audit
  read-out (`organization-type-audit-2026-09-28.md`) with the verdict **0, 0, 6, 0** — the gate
  passed; the dry run planning `internal` 2 (549, 885), `agent` 1,418, held out 5, NULL after
  2,691; **`APPLY` at 19:52:47.158499 UTC**: written internal 2 · agent 1,418, both self-checks OK,
  NULL 4,111 → 2,691 "as planned" (`account-type-backfill-memo-2026-09-28-production.md`); the
  second dry run planning 0 in both tiers with the 1,418 now already typed by user 1; invariants
  1–9 exact (1,420 batch rows, none outside {agent, internal}, no before row changed, 1,420 new rows
  all by user 1, NULL 2,691, no typed soft-deleted row, internal ⊇ {2, 89, 2555}, sum 4,144, the
  worklist head 11510 · 4513 · 11213 · 6526 · 11575 · 11679); the CSV `write` ids equal to the
  batch; all eleven spot checks as reasoned. The one-row difference from the morning sync's 1,417 is
  the day's drift. Not recorded: the release number and the step 9 ops counts. Event 4's baseline
  captured: `total_accounts` 4,142, `total_gross_cents` 372,408,100.
