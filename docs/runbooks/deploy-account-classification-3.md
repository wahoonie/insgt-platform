# Runbook: Account Classification Slice 3 Deploy

**Last updated:** 2026-09-14
**Repos:** insgt-api
**Estimated duration:** ~15 min
**Status:** Deployed to production 2026-09-14

## Summary

Ships slice 3 of `docs/architecture/account-classification.md` (§3.4, §4.2, §4.3, §6 step 3): four
nullable columns on `account_metrics` (`lifecycle_type`, `lifecycle_type_at`, `value_type`,
`peak_value_type`), one composite index over them, the thresholds config
`lib/account_classification.rb`, three prefixed enums on `AccountMetric`, the `classification`
derivation in `AccountMetrics::Calculator`, and the four labels on `GET /accounts/:id/metrics`.
Plan: `docs/plans/account-classification-slice-3.md`.

**The branch is neither committed nor merged.** As of 2026-09-14 the change lives in the working
tree of `insgt-api` on `feat/account-classification-slice-3`. Committing it and merging it
`--no-ff` onto `master` are prerequisites below, not steps in this runbook.

**No existing number moves.** All four columns are new and nothing reads them yet. The one
read-out that changes is `accounts:joint_ownership`, and only in where its volume bands come from:
the four non-zero rows of `AccountAudit::SHOOT_VOLUME_TIERS` now take their ranges from
`AccountClassification::VALUE_BANDS`, whose edges are identical. Its output was verified
byte-identical across the change on the dev restore. No shift memo, no hand-over.

**insgt-ops is untouched.** It models none of these fields (`AccountMetricSummary` has every field
optional and the service returns the raw body), so the four new keys land unread. Rendering them
is an ops follow-up.

## Deploy order and the window it closes

**Old code on the new schema is safe.** The four columns are additive and nullable, and
`Calculator#call` assigns only the keys its compute hash carries, so old code leaves them alone
and `SELECT *` gains columns nothing reads.

**New code on the old schema is not.** `Calculator#call` raises `ActiveModel::UnknownAttributeError`
on every account (caught per account, logged, reported as `Failed: 4,0xx`) and the metrics dialog
500s because the jbuilder reads the four new attributes. The window is push, then `db:migrate`,
and the Procfile has no `release:` phase, so it is closed by hand: **maintenance mode on before the
push, off after the migrations and restart**. Shape (A), one push, the same choice slice 2 made. A
couple of minutes of 503.

**Maintenance mode does not stop the scheduler.** Heroku Scheduler runs `metrics:recompute` at
02:30 UTC. If the push lands in that window the nightly runs new code against the old schema:
every account fails, nothing is written, and the run has to be repeated. Deploy outside
02:15–02:45 UTC, or confirm both migrations are up before 02:30.

## Prerequisites

- [ ] The working tree committed onto `feat/account-classification-slice-3`, and `git status` clean
- [ ] insgt-api `bundle exec rspec` green on the branch: **1,688 examples, 0 failures** on 2026-09-14
- [ ] `feat/account-classification-slice-3` merged to `master` with `--no-ff`; `origin/master` pushed
- [ ] No deploy in flight; not inside the 02:15–02:45 UTC scheduler window
- [ ] Baseline kept: `heroku run rake accounts:joint_ownership -a insgtapi` output from before the
      deploy. Step 8 diffs it

      heroku run rake accounts:joint_ownership -a insgtapi
 ›   Warning: heroku update available from 11.8.1 to 11.10.0.
Running rake accounts:joint_ownership on ⬢ insgtapi... up, run.6786
Joint ownership weighted by volume — 4,132 active accounts weighed
  Excluded: 2 InsightPhotos, 89 Insight Photos Marketing, 2555 Jack Brown
  Active user   = account_metrics.active_user_count: users.status_type 1 holding an active accounts_users row, counted once however many roles they hold
  Owner         = active accounts_users row carrying the account_owner role
  Shared owner  = that owner owns another IN-SCOPE account; two agents each owning their own account do not count
  Shoot         = account_metrics.rolling_365_parent_count: Order.qualifying_parents (completed property parent; reshoots in, recaptures out), dated by scheduled_at, falling back to its first completed log
  Window        = the trailing 365 days as of the recompute that wrote the row, not as of this invocation
  Snapshot      = oldest computed_at among the weighed accounts: 2026-09-14 02:30:32 UTC
  1,473 shoots in the window across 513 accounts
  1 in-scope account(s) have no recomputed row and are excluded from every table below; see Context

  Segment                                      Accts  Accts%     Shoots Shoots%
  Sole owner, one active user                  4,025   97.4%      1,212   82.3%
  More than one active user only                  99    2.4%        254   17.2%
  Owner owns another account only                  6    0.1%          0    0.0%
  Both                                             2    0.0%          7    0.5%
  ----------------------------------------------------------------------------
  Joint by either test                           107    2.6%        261   17.7%

Joint share within each volume tier
  Tier                 Accts   Joint  Joint%     Shoots  JntShts JntSht%
  no shoots            3,619      70    1.9%          0        0    0.0%
  single (1)             278       7    2.5%        278        7    2.5%
  occasional (2-5)       177      17    9.6%        544       57   10.5%
  core (6-11)             39       6   15.4%        289       45   15.6%
  anchor (12+)            19       7   36.8%        362      152   42.0%

Top 25 joint accounts by shoots in the window
    Shoots  Users  Owners  Shared  Acct ID  Name
        51      6       1  no        10288  PURE / San Diego
        25      4       1  no         1123  Ray Shay
        21      2       1  no         1593  Deniese Ossey
        17      2       1  no          185  Tim & Kristine Skoglin
        13      2       1  no         1842  Lee Arnold
        13      2       1  no        11213  Carlos Ledesma
        12      2       1  no         2104  Dana Clymer
        11      2       1  no          139  Deborah Harper
         9      2       1  no         1272  Claude Blackman
         7      4       1  yes        1642  Jon Shea
         6      2       1  no           76  Jason Taylor
         6      2       1  no          380  Jeff Underdahl
         6      2       1  no         2315  Bob Adams
         5      2       1  no           63  Ken & Caroll Dembowski
         5      2       1  no          591  Judy Szamos
         5      3       1  no         2789  Wendy Choisser
         5      4       1  no         8176  Jim Klinge
         4      3       1  no          193  Alex Mickle
         4      2       1  no          454  Mike Acker
         4      2       1  no          618  Joe Green
         3      5       1  no          141  Mike Williams
         3      2       1  no          360  Rick and Trudy McGrath
         3      2       1  no          789  Anna Song
         3      2       1  no          889  George Piner
         3      2       1  no         1433  Jody Sillstrop

Context
  Owners holding more than one in-scope account: 4
  Accounts with no owner                           6    0.1%          0    0.0%
  Accounts with more than one owner                0    0.0%          0    0.0%
  Accounts with no active users                    5    0.1%          0    0.0%
  Accounts with no recomputed metrics row, excluded from every table above: 1

- [ ] `docs/architecture/account-classification.md` amended to v6 and the codebase notes current

## Steps

### 1. Back up the database

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2026-09-14_lock.dump
```

### 2. Maintenance on, deploy code

```bash
heroku maintenance:on --app insgtapi
git checkout master && git merge --no-ff feat/account-classification-slice-3
git push origin master
git push heroku master
```

Watch the build to completion before continuing. Do not lift maintenance yet.

### 3. Run the migrations

```bash
heroku run rake db:migrate -a insgtapi
heroku run rails db:migrate:status -a insgtapi
heroku restart --app insgtapi
heroku maintenance:off --app insgtapi
```

Two migrations, in this order. `db:migrate:status` must show both `up`, and the schema version must
read `2026_09_12_120001`.

1. `20260912120000_add_classification_types_to_account_metrics` adds four nullable columns with no
   defaults: `lifecycle_type` (`:integer, limit: 2`), `lifecycle_type_at` (`:datetime`),
   `value_type` and `peak_value_type` (`:integer, limit: 2`). Metadata-only on PG 15 and
   strong_migrations-clean.
2. `20260912120001_add_lifecycle_index_to_account_metrics` adds one index,
   `index_account_metrics_on_lifecycle_type_and_value_type` on `(lifecycle_type, value_type)`, with
   `disable_ddl_transaction!` and `algorithm: :concurrently` in both directions. Sub-second on
   4,081 rows. `auto_analyze = true` in the strong_migrations initializer fires an
   `ANALYZE account_metrics` straight after it, so expect one extra statement in the log.

The composite `[account_id, lifecycle_type]` that §3.4 also asks for is **deliberately not
shipped**: `db/schema.rb` already carries a UNIQUE index on `account_id`, so there is at most one
row per account and the composite cannot beat a lookup that already exists.

Both migrations were run migrate, rollback, migrate against a restore of production data on
2026-09-14. The schema diff is exactly four column lines inside `create_table "account_metrics"`,
one index line, and the version bump. Note the timing for the deploy log.

### 4. Recompute, in the window, not tonight

```bash
time heroku run rake metrics:recompute -a insgtapi
```

Required. All four columns are NULL on every row until the first sweep, and the dialog shows them
as null until then. Do not wait for the 02:30 UTC nightly.

**Read the task's own summary line first.** `AccountMetrics::RecomputeAll` rescues `StandardError`
per account and the rake task still exits 0, so a bug in the config object or the derivation can
fail every account without failing the command. The line must read `Failed: 0`, and `Scanned` must
equal the active account count, which grows between deploys:

```
Done. Scanned: 4136. Failed: 0.
```

Timing. **Production ran 2 min 37.79 s** for 4,136 accounts on 2026-09-14, against a predicted
2 min 40 s and slice 2's baseline of 2 min 36.89 s for 4,078. Slice 3's extra window query per
account therefore costs under a second across the fleet at production scale, well inside the
~1.4 ms per account measured at survey. That 2 min 37.79 s is the baseline slice 4 extends, not the
dev figures: the same sweep takes 1 min 06 s on a local sync of the same 4,136 accounts, because
`heroku run` dyno start-up and the network hop to the database sit inside the production number.
Record the actual wall clock in the deploy log.

### 5. Invariants

```bash
heroku run rails runner 'puts AccountMetric.joins(:account).where(accounts: { status_type: 1 }).where(lifecycle_type: nil).count' -a insgtapi
```

Expect **0**. Then the full set. Every check runs over active accounts only
(`JOIN accounts ON accounts.id = account_metrics.account_id AND accounts.status_type = 1`) and
re-derives from the row's own stored inputs rather than from the clock, so a non-zero row is a bug
and not drift.

Enum integers, for reading the SQL below: lifecycle `prospect` 1, `new` 2, `active` 3, `cooling` 4,
`at_risk` 5, `lapsed` 6; value `single` 1, `occasional` 2, `core` 3, `anchor` 4.

| # | Check | Expected |
| --: | :-- | :-- |
| 1 | `lifecycle_type IS NULL` on an active account | 0 |
| 2 | `lifecycle_type = prospect AND lifecycle_type_at IS NOT NULL` | 0 |
| 3 | `lifecycle_type <> prospect AND lifecycle_type_at IS NULL` | 0 |
| 4 | `lifecycle_type_at > now()` | 0 |
| 5 | `value_type IS NOT NULL AND rolling_365_parent_count = 0` | 0 |
| 6 | `value_type IS NULL AND rolling_365_parent_count > 0` | 0 |
| 7 | `peak_value_type IS NOT NULL AND peak_365_parent_count = 0` | 0 |
| 8 | `peak_value_type IS NULL AND peak_365_parent_count > 0` | 0 |
| 9 | `value_type > peak_value_type` | 0 |
| 10 | `lifecycle_type = lapsed AND value_type IS NOT NULL` | 0 |
| 11 | `lifecycle_type = prospect AND peak_value_type IS NOT NULL` | 0 |

All eleven returned 0 on the dev restore after the sweep. Run them in one pass:

```bash
heroku run rails runner '
  active = AccountMetric.joins(:account).where(accounts: { status_type: 1 })
  checks = {
    "1  lifecycle_type missing"                => active.where(lifecycle_type: nil),
    "2  prospect with a stamp"                 => active.where(lifecycle_type: :prospect).where.not(lifecycle_type_at: nil),
    "3  non-prospect without a stamp"          => active.where.not(lifecycle_type: :prospect).where(lifecycle_type_at: nil),
    "4  stamp in the future"                   => active.where("lifecycle_type_at > now()"),
    "5  value_type on a zero count"            => active.where.not(value_type: nil).where(rolling_365_parent_count: 0),
    "6  no value_type on a positive count"     => active.where(value_type: nil).where("rolling_365_parent_count > 0"),
    "7  peak_value_type on a zero peak"        => active.where.not(peak_value_type: nil).where(peak_365_parent_count: 0),
    "8  no peak_value_type on a positive peak" => active.where(peak_value_type: nil).where("peak_365_parent_count > 0"),
    "9  value_type above peak_value_type"      => active.where("value_type > peak_value_type"),
    "10 lapsed with a value_type"              => active.where(lifecycle_type: :lapsed).where.not(value_type: nil),
    "11 prospect with a peak_value_type"       => active.where(lifecycle_type: :prospect).where.not(peak_value_type: nil)
  }
  checks.each { |name, relation| puts format("%-42s %6d", name, relation.count) }
  puts "VIOLATIONS: #{checks.count { |_, relation| relation.count.positive? }} of #{checks.size}"
' -a insgtapi
```

### 6. Distributions

```bash
heroku run rails runner '
  active_metrics = AccountMetric.joins(:account).where(accounts: { status_type: 1 })
  sweep_start = active_metrics.minimum(:computed_at)
  puts "sweep start: #{sweep_start}"
  puts "lifecycle_type:  #{active_metrics.group(:lifecycle_type).count}"
  puts "value_type:      #{active_metrics.group(:value_type).count}"
  puts "peak_value_type: #{active_metrics.group(:peak_value_type).count}"
  puts "reactivation cohort: #{active_metrics.where(lifecycle_type: :lapsed, peak_value_type: :anchor).count}"
' -a insgtapi
```

Measured twice. The 2026-09-14 row is the closest thing to a production expectation, because it
comes from a full production sync migrated and swept under this code; the 2026-09-10 row is the
figure the plan reasoned out before the code existed, which the implementation reproduced exactly
when replayed at that instant.

| Column | 2026-09-14 sync (4,136 active accounts) | 2026-09-10 restore (4,078) |
| :-- | :-- | :-- |
| `lifecycle_type` | `prospect` 2,061 · `new` 58 · `active` 156 · `cooling` 133 · `at_risk` 168 · `lapsed` 1,560 | `prospect` 2,004 · `new` 61 · `active` 152 · `cooling` 138 · `at_risk` 166 · `lapsed` 1,557 |
| `value_type` | NULL 3,621 · `single` 279 · `occasional` 177 · `core` 40 · `anchor` 19 | NULL 3,563 · `single` 277 · `occasional` 178 · `core` 41 · `anchor` 19 |
| `peak_value_type` | NULL 2,061 · `single` 1,072 · `occasional` 701 · `core` 191 · `anchor` 111 | NULL 2,004 · `single` 1,071 · `occasional` 701 · `core` 191 · `anchor` 111 |
| `lapsed AND peak_value_type = anchor` | 42 | 42 |

**Production reproduced the 2026-09-14 column exactly, every bucket of all three rows**, because
the sync was taken sixteen minutes before the production sweep and no account crossed a boundary in
between. Do not expect that on a later deploy; expect it only when the two runs are minutes apart.

Two structural checks hold on every dataset and are worth reading off the output directly. The NULL
`peak_value_type` count equals the `prospect` count exactly, because no visit ever means no parent
ever. The NULL `value_type` count equals `prospect` plus `lapsed` exactly, because no visit in 365
days means no parent in 365 days. In production: 2,061 and 2,061 + 1,560 = 3,621.

**These drift with the clock and must be re-derived on the day. Do not treat them as pass/fail.**
The two columns above are four days apart on overlapping data and the four lifecycle bands between
`new` and `at_risk` all moved. Replaying the older restore three days on accounted for every one of
its moves by name, 13 accounts crossing a boundary. That is the lifecycle columns working, not a
regression. The only figures that should match across two runs of the same data are the
`peak_value_type` row and the structural identities just above.

`peak_value_type` is the exception: it does not drift with time at all, being monotonic against
the passage of time. Any movement in the `peak_value_type` row is a real finding and must be
explained before the window is called done.

Re-derive the lifecycle distribution against the labels the sweep actually wrote, pinning the
evaluation instant to `AccountMetric.minimum(:computed_at)` rather than `now()`. `computed_at` is
taken per account across a sweep that runs about two and a half minutes, so two accounts sitting on
the same boundary can legitimately land in different buckets within one run:

```bash
heroku run rails runner '
  active_metrics = AccountMetric.joins(:account).where(accounts: { status_type: 1 })
  sweep_start = active_metrics.minimum(:computed_at)
  mismatches = active_metrics.find_all do |metric|
    expected_lifecycle = AccountClassification.lifecycle(
      first_shoot_at: metric.first_shoot_at,
      most_recent_shoot_at: metric.most_recent_shoot_at,
      now: sweep_start
    )
    expected_lifecycle.to_s != metric.lifecycle_type
  end
  puts "re-derived at #{sweep_start}; mismatches: #{mismatches.count}"
  puts mismatches.first(20).map { |metric| [metric.account_id, metric.lifecycle_type].inspect }
' -a insgtapi
```

Expect **0 mismatches**. A handful of accounts sitting exactly on a boundary can legitimately
differ if the re-derivation runs long after the sweep; check each one by hand against its own
`most_recent_shoot_at` before treating it as a failure.

### 7. Spot checks

One account per label, with the derived `lifecycle_type_at` and how long that label has held.
Verified against the 2026-09-14 production sync:

| Account | `lifecycle_type` | `lifecycle_type_at` | held | `value_type` | `peak_value_type` |
| --: | :-- | :-- | --: | :-- | :-- |
| 3 | `prospect` | nil | - | NULL | NULL |
| 11364 | `new` | 2026-07-06 22:00 UTC | 69 d | `occasional` | `occasional` |
| 10288 | `active` | 2025-09-10 18:30 UTC | 369 d | `anchor` | `anchor` |
| 39 | `cooling` | 2026-07-02 16:00 UTC | 74 d | `single` | `anchor` |
| 76 | `at_risk` | 2026-09-10 18:00 UTC | 4 d | `core` | `anchor` |
| 48 | `lapsed` | 2017-04-16 20:00 UTC | 3,438 d | NULL | `anchor` |

Account 48 is the row that makes the case for deriving this column rather than stamping it. It has
been lapsed for nine and a half years; a column stamped when the nightly first noticed a change
would read "lapsed since the deploy date" for it, and for 1,559 others.

```bash
heroku run rails runner '
  ids = [3, 11364, 10288, 39, 76, 48]
  now = AccountMetric.joins(:account).where(accounts: { status_type: 1 }).minimum(:computed_at)
  AccountMetric.where(account_id: ids).sort_by { |metric| ids.index(metric.account_id) }.each do |metric|
    held = metric.lifecycle_type_at ? ((now - metric.lifecycle_type_at) / 1.day).floor : nil
    puts [metric.account_id, metric.lifecycle_type, metric.lifecycle_type_at, held, metric.value_type, metric.peak_value_type].inspect
  end
' -a insgtapi
```

The labels and the stamps move as shoots land, so re-derive the table on deploy day before
comparing. Two shapes are absolute and are pass/fail:

- **10288 is the new-to-active handover canary.** Its stamp equals `first_shoot_at + 90 days`
  (`first_shoot_at` 2025-06-12 18:30 UTC, stamp 2025-09-10 18:30 UTC), because its current run of
  visits reaches back to its first shoot. A stamp equal to `first_shoot_at` means the `max` against
  the run start was lost. A stamp equal to `most_recent_shoot_at` means the run scan was dropped.
- **48 is the reactivation-cohort shape**: `lapsed`, `value_type` NULL, `peak_value_type` `anchor`.
  It is one of the 42 accounts in step 6's cohort count.

**The three degrading stamps are `most_recent_shoot_at + 91 / 181 / 366 days`**, one day later than
the table in `docs/plans/account-classification-slice-3.md`, which was arithmetically wrong. The
rule is that each stamp is the exact instant the floored-day rule crosses that boundary, so a label
and its timestamp come from one set of numbers and cannot disagree. Check a degrading account's
stamp against its own `most_recent_shoot_at`, not against the plan's table.

### 8. The read-out

```bash
heroku run rake accounts:joint_ownership -a insgtapi
```

Diff it against the baseline kept in the prerequisites. This is the whole of the no-shift check:
the only thing slice 3 changes here is where the four non-zero tier ranges come from, and
`AccountClassification::VALUE_BANDS` carries the same edges (1..1, 2..5, 6..11, 12+) that
`SHOOT_VOLUME_TIERS` did, with the `no shoots` row still local to the read-out. On the dev restore,
where both runs read one sweep, the output was byte-identical across the change.

In production the two runs straddle a recompute, so the Snapshot line reads the new `computed_at`
and the volume numbers move by the shoots that landed or aged out since the previous sweep, as they
would on any night. What must not move: the five tier labels, the band edges printed beside them,
and the shape of the segment table. A changed label or a changed band edge means the reconciliation
changed behaviour and the deploy should be rolled back.

**Production passed, and every moved number is accounted for.** The five tier labels, the band
edges printed beside them and the four segment rows came back identical to the baseline, compared
string by string. The volume tiers:

| Tier | Baseline, 02:30:32 UTC snapshot | After the deploy sweep, 21:28:50 UTC | Accts |
| :-- | --: | --: | --: |
| `no shoots` | 3,619 | 3,620 | +1 |
| `single (1)` | 278 | 279 | +1 |
| `occasional (2-5)` | 177 | 176 | -1 |
| `core (6-11)` | 39 | 39 | 0 |
| `anchor (12+)` | 19 | 19 | 0 |
| weighed | 4,132 | 4,133 | +1 |

Two movements, nineteen hours apart, neither of them this slice. The baseline reported one in-scope
account with no recomputed row, excluded from every table; the deploy sweep gave it one, so the
weighed set grew by one and that account landed in `no shoots`. Separately one account fell from
`occasional` to `single` as a shoot aged out of its trailing window, which is why `occasional`
shoots drop by exactly 2 (544 to 542) while `single` shoots rise by exactly 1 (278 to 279). That is
the arithmetic of one account going from two shoots to one.

The tier counts also reconcile to the fleet distribution minus the three excluded accounts: 4,133
weighed against 4,136 active, with one excluded account in `no shoots`, one in `occasional` and one
in `core`, so 3,620 + 279 + 176 + 39 + 19 comes to 4,133.

### 9. insgt-ops

Nothing to deploy. The interface ignores the four new keys.

## Rollback

### Code only (schema stays)

```bash
heroku rollback --app insgtapi
```

Old code runs against the new schema without error, but the four columns do **not** go back to
NULL: `Calculator#call` assigns only the keys its compute hash carries, so the old code keeps
refreshing `computed_at` every night while the four go on holding the labels of the last sweep
under the new code. This is the same trap the slice 2 migration header and runbook spell out, and
it is **worse here**: a stale *label* reads as a current judgment about an account in a way a
stale *count* does not. Nobody looking at `at_risk` on the dialog reads it as "as of whenever the
code was rolled back"; they read it as what the account is today, and the fresh `computed_at`
beside it says so. Tell anyone reading these labels that they stopped moving, or roll the schema
back too.

### Schema

```bash
heroku run rake db:rollback STEP=2 -a insgtapi
```

Two steps, in reverse: `20260912120001` drops the index (concurrently, spelled out by hand in its
`down`, because `StrongMigrations.check_down` is `false` and a plain `remove_index` would take the
ACCESS EXCLUSIVE lock the forward migration goes out of its way to avoid), then `20260912120000`
drops the four columns. Nothing references them once the code is rolled back; roll the code back
first.

## Deploy log

- 2026-09-14: verified on the dev restore (2026-09-10 production snapshot, 4,078 active accounts,
  4,081 metric rows): both migrations run migrate, rollback, migrate clean, with a schema diff of
  exactly four column lines, one index line, and the version bump to `2026_09_12_120001`; the index
  build sub-second on 4,081 rows plus its `ANALYZE`; `metrics:recompute` read
  `Done. Scanned: 4078. Failed: 0.` in 1 min 11 s wall; all eleven invariants 0; the three
  distributions and the 42-account reactivation cohort reproduced the 2026-09-11 14:20 UTC
  measurement exactly when replayed at that instant; all six spot checks matched on all four
  columns, with 10288's stamp at `first_shoot_at + 90 days`; `accounts:joint_ownership`
  byte-identical before and after.
- 2026-09-14, 17:12 EDT: **dry run against a full production sync** (4,136 active
  accounts). Both migrations applied; `metrics:recompute` swept every account in 1 min 06 s with 0
  unswept rows left behind; all eleven invariants 0; the re-derivation check reported 0 mismatches
  across all 4,136 rows; every spot check agreed with the rule, including 10288's handover stamp;
  both structural identities held exactly (NULL `peak_value_type` 2,061 = `prospect` 2,061; NULL
  `value_type` 3,621 = `prospect` + `lapsed`). Step 5 originally used `heroku pg:psql` with a
  heredoc, which returned without running; rewritten onto `heroku run rails runner`, the idiom
  slice 2 actually used in production, and all four runner blocks re-run against the sync.
- 2026-09-14, 17:26 EDT: **deployed to production.** Merged `--no-ff` as f811e97 at 17:22 EDT,
  pushed to origin 17:22 and to heroku 17:26. Both migrations applied. `metrics:recompute` read
  `Done. Scanned: 4136. Failed: 0.` in **2 min 37.79 s** wall, writing a 21:28:50 UTC snapshot over
  4,136 active accounts, against a predicted 2 min 40 s and slice 2's 2 min 36.89 s over 4,078, so
  slice 3's extra window query costs under a second across the fleet. §6 now carries a production
  duration for slice 4 to extend. All eleven step 5 invariants 0, including both
  directions of the zero-count rule on each tier column. The step 6 distribution reproduced the
  pre-deploy sync **exactly, every bucket of all three rows**, the sync having been taken sixteen
  minutes earlier with no account crossing a boundary in between: `prospect` 2,061 · `new` 58 ·
  `active` 156 · `cooling` 133 · `at_risk` 168 · `lapsed` 1,560; `value_type` NULL 3,621 ·
  `single` 279 · `occasional` 177 · `core` 40 · `anchor` 19; `peak_value_type` NULL 2,061 ·
  `single` 1,072 · `occasional` 701 · `core` 191 · `anchor` 111; the reactivation cohort 42. Both
  structural identities held: NULL `peak_value_type` 2,061 equals the `prospect` count, and NULL
  `value_type` 3,621 equals `prospect` plus `lapsed`. The step 6 re-derivation reported **0
  mismatches across all 4,136 rows** with the cutoff pinned to the sweep. All six step 7 spot
  checks matched on all five columns, 29 of 29 cells, with both absolute shapes good: 10288's
  stamp at `first_shoot_at + 90 days` (2025-09-10 18:30 UTC, 369 days held), and 48 carrying the
  reactivation shape at `lapsed` / NULL / `anchor`, stamped 2017-04-16 and held **3,438 days**,
  which is the row a stamped column would have reported as "lapsed since today". The
  `accounts:joint_ownership` read-out passed its no-shift check against the 02:30:32 UTC baseline
  kept in the prerequisites: the five tier labels, the band edges beside them and the four segment
  rows came back identical, compared string by string. Three tier counts moved and both causes are
  nineteen hours of ordinary drift rather than this slice. The baseline's one un-recomputed
  in-scope account got a row and joined `no shoots`, and one account fell from `occasional` to
  `single` as a shoot aged out, which is why `occasional` shoots drop by exactly 2 and `single`
  shoots rise by exactly 1. The tier counts reconciled to the fleet distribution minus the three
  excluded accounts (4,133 weighed of 4,136 active). Step 8 carries the comparison.

  Steps 4, 6 and 8 were amended from this run: the sweep now has a production duration baseline,
  the expected `Scanned` count is stated as a shape rather than a fixed number, and step 8 records
  what the no-shift comparison actually proved.
