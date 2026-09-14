# Runbook: Account Classification Slice 3 Deploy

**Last updated:** 2026-09-14
**Repos:** insgt-api
**Estimated duration:** ~15 min
**Status:** Draft (not deployed)

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
- [ ] `docs/architecture/account-classification.md` amended to v6 and the codebase notes current

## Steps

### 1. Back up the database

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-<YYYY-MM-DD>_lock.dump
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
fail every account without failing the command. The line must read:

```
Done. Scanned: 4078. Failed: 0.
```

Timing. On the dev restore the sweep took **1 min 11 s** for 4,078 accounts with slice 3 in place.
The production baseline from slice 2 is **2 min 36.89 s**. Slice 3 adds one window query per
account, measured at ~1.4 ms at survey, so expect roughly **2 min 40 s**. Record the actual wall
clock in the deploy log.

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
heroku pg:psql -a insgtapi <<'SQL'
WITH active_metrics AS (
  SELECT account_metrics.*
  FROM account_metrics
  JOIN accounts ON accounts.id = account_metrics.account_id
  WHERE accounts.status_type = 1
)
            SELECT  '1  lifecycle_type missing'          AS check_name, count(*) FROM active_metrics WHERE lifecycle_type IS NULL
  UNION ALL SELECT  '2  prospect with a stamp',                         count(*) FROM active_metrics WHERE lifecycle_type = 1 AND lifecycle_type_at IS NOT NULL
  UNION ALL SELECT  '3  non-prospect without a stamp',                  count(*) FROM active_metrics WHERE lifecycle_type <> 1 AND lifecycle_type_at IS NULL
  UNION ALL SELECT  '4  stamp in the future',                           count(*) FROM active_metrics WHERE lifecycle_type_at > now()
  UNION ALL SELECT  '5  value_type on a zero count',                    count(*) FROM active_metrics WHERE value_type IS NOT NULL AND rolling_365_parent_count = 0
  UNION ALL SELECT  '6  no value_type on a positive count',             count(*) FROM active_metrics WHERE value_type IS NULL AND rolling_365_parent_count > 0
  UNION ALL SELECT  '7  peak_value_type on a zero peak',                count(*) FROM active_metrics WHERE peak_value_type IS NOT NULL AND peak_365_parent_count = 0
  UNION ALL SELECT  '8  no peak_value_type on a positive peak',         count(*) FROM active_metrics WHERE peak_value_type IS NULL AND peak_365_parent_count > 0
  UNION ALL SELECT  '9  value_type above peak_value_type',              count(*) FROM active_metrics WHERE value_type > peak_value_type
  UNION ALL SELECT '10  lapsed with a value_type',                      count(*) FROM active_metrics WHERE lifecycle_type = 6 AND value_type IS NOT NULL
  UNION ALL SELECT '11  prospect with a peak_value_type',               count(*) FROM active_metrics WHERE lifecycle_type = 1 AND peak_value_type IS NOT NULL
  ORDER BY 1;
SQL
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

Measured on a 2026-09-10 production restore evaluated at 2026-09-11 14:20 UTC. The implementation
reproduced every one of these exactly when replayed at that instant:

| Column | Distribution |
| :-- | :-- |
| `lifecycle_type` | `prospect` 2,004 · `new` 61 · `active` 152 · `cooling` 138 · `at_risk` 166 · `lapsed` 1,557 |
| `value_type` | NULL 3,563 · `single` 277 · `occasional` 178 · `core` 41 · `anchor` 19 |
| `peak_value_type` | NULL 2,004 · `single` 1,071 · `occasional` 701 · `core` 191 · `anchor` 111 |
| `lapsed AND peak_value_type = anchor` | 42, the §4.3 reactivation cohort |

**These drift with the clock and must be re-derived on the day. Do not treat them as pass/fail.**
Evaluated three days later, the same data gave `new` 58 · `active` 153 · `cooling` 134 ·
`at_risk` 169 · `lapsed` 1,560, because 13 named accounts crossed a boundary in between. That is
the lifecycle columns working, not a regression.

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

One account per label, with the derived `lifecycle_type_at`. Verified on the dev restore
(2026-09-10 production snapshot, evaluated 2026-09-11 14:20 UTC):

| Account | `lifecycle_type` | `lifecycle_type_at` | `value_type` | `peak_value_type` |
| --: | :-- | :-- | :-- | :-- |
| 3 | `prospect` | nil | NULL | NULL |
| 11364 | `new` | 2026-07-06 22:00 UTC | `occasional` | `occasional` |
| 10288 | `active` | 2025-09-10 18:30 UTC | `anchor` | `anchor` |
| 1842 | `cooling` | 2026-08-10 16:00 UTC | `anchor` | `anchor` |
| 2687 | `at_risk` | 2026-07-30 21:45 UTC | `core` | `anchor` |
| 58 | `lapsed` | 2026-06-03 15:00 UTC | NULL | `anchor` |

```bash
heroku run rails runner '
  AccountMetric.where(account_id: [3, 11364, 10288, 1842, 2687, 58]).order(:account_id).each do |metric|
    puts [metric.account_id, metric.lifecycle_type, metric.lifecycle_type_at, metric.value_type, metric.peak_value_type].inspect
  end
' -a insgtapi
```

The labels and the stamps move as shoots land, so re-derive the table on deploy day before
comparing. Two shapes are absolute and are pass/fail:

- **10288 is the new-to-active handover canary.** Its stamp equals `first_shoot_at + 90 days`
  (`first_shoot_at` 2025-06-12 18:30 UTC, stamp 2025-09-10 18:30 UTC), because its current run of
  visits reaches back to its first shoot. A stamp equal to `first_shoot_at` means the `max` against
  the run start was lost. A stamp equal to `most_recent_shoot_at` means the run scan was dropped.
- **58 is the reactivation-cohort shape**: `lapsed`, `value_type` NULL, `peak_value_type` `anchor`.
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
  byte-identical before and after. Not yet deployed to production.
