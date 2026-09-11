# Runbook: Account Classification Slice 2 Deploy

**Last updated:** 2026-09-11
**Repos:** insgt-api
**Estimated duration:** ~15 min
**Status:** Deployed to production 2026-09-11

## Summary

Ships slice 2 of `docs/architecture/account-classification.md` (v5, §3.4, §5.4, §6): five nullable
columns on `account_metrics` — `rolling_365_parent_count`, `rolling_365_value_cents`,
`peak_365_parent_count`, `peak_365_ended_on`, `active_user_count` — computed by
`AccountMetrics::Calculator` on every nightly sweep, four of them on `GET /accounts/:id/metrics`,
and the two read-outs that used to derive two of them (`accounts:joint_ownership`, the slice 1b
memo) reading the stored columns instead. Branch `feat/account-classification-2`, 16 commits,
cf0745d..ca49f32 (9 implementation, 4 round-1 review fixes, 3 round-2); plan
`docs/plans/account-classification-slice-2.md`.

**Review status.** Round 1 was a seven-lens review plus an independent Codex pass, every finding
adversarially verified: 6 confirmed, 4 refuted, all 6 fixed. Round 2 re-reviewed the fixes and was
**partial** — the `sql-correctness`, `migration-deploy` and `spec-coverage` lenses died on a model
usage limit and did not run. Those three passed clean in round 1 and the round-1 fixes touched
only specs, comments and one dead guard, so the gap is narrow; a third round over the SQL and the
migration is the engineer's call before merging.

**No existing number moves.** Every column the nightly wrote last night it writes again with the
same value: measured on the 2026-09-10 restore, `lifetime_value_cents` sums to 370,187,800 before
and after, and `rolling_90_parent_count` and `lifetime_parent_count` equal a live re-derivation
from the scopes. No shift memo, no hand-over.

**insgt-ops is untouched.** Its `AccountMetricSummary` has every field optional and the service
returns the raw body, so the four new keys land unread. Rendering them is an ops follow-up.

## Deploy order and the window it closes

**Old code on the new schema is safe.** The columns are additive and nullable; `AccountMetric#save!`
writes known attributes only; `SELECT *` gains columns nothing reads.

**New code on the old schema is not.** `Calculator#call` raises `ActiveModel::UnknownAttributeError`
on every account — caught per account, logged, and reported as `Failed: 4,0xx` — and the metrics
dialog 500s because the jbuilder reads the four new attributes. The window is push → `db:migrate`,
and the Procfile has no `release:` phase, so it is closed by hand: **maintenance mode on before the
push, off after the migration and restart** (shape A, chosen 2026-09-10). A couple of minutes of
503.

**Maintenance mode does not stop the scheduler.** Heroku Scheduler runs `metrics:recompute` at
02:30 UTC (`insgt-api/docs/ops/metrics-recompute-cron.md`). If the push lands in that window the
nightly would run new code against the old schema: every account fails, nothing is written, and
the run has to be repeated. Deploy outside 02:15–02:45 UTC, or confirm the migration is up before
02:30.

## Prerequisites

- [ ] insgt-api `bundle exec rspec` green on the branch (1,601 examples on 2026-09-10)
- [ ] `feat/account-classification-2` merged to `master` with `--no-ff`; `origin/master` pushed
- [ ] No deploy in flight; not inside the 02:15–02:45 UTC scheduler window
- [ ] Baseline kept: `heroku run rake accounts:joint_ownership -a insgtapi` output from before the
      deploy. Its "shoots in the window across N accounts" line is live-derived today; after the
      deploy the same line reads the stored columns and must reproduce it, minus the shoots that
      aged out of the window between the two runs (about four a day)
- [ ] `docs/architecture/account-classification.md` is at v5 and the codebase notes are current

## Steps

### 1. Back up the database

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2026-09-11_lock.dump
```

### 2. Maintenance on, deploy code

```bash
heroku maintenance:on --app insgtapi
git checkout master && git merge --no-ff feat/account-classification-2
git push origin master
git push heroku master
```

Watch the build to completion before continuing. Do not lift maintenance yet.

### 3. Run the migration

```bash
heroku run rake db:migrate -a insgtapi
heroku run rails db:migrate:status -a insgtapi
heroku restart --app insgtapi
heroku maintenance:off --app insgtapi
```

One migration, `20260911120000_add_slice_2_columns_to_account_metrics`: five nullable
`add_column`s, no default, no index, metadata-only on PG 15. `db:migrate:status` must show it
`up`. Note the timing for the deploy log.

### 4. Recompute — in the window, not tonight

```bash
time heroku run rake metrics:recompute -a insgtapi
```

Required. Every row's five new columns are NULL until the first sweep, and the dialog shows them
as null until then. The 02:30 UTC nightly would fill them, but the recapture deploy set the
precedent of not waiting on it. Dev restore: 4,079 accounts, 0 failed, 50 s wall; expect the
previous production duration plus ~12 s. Record the wall-clock in the deploy log — the 1a/1b log
says "not recorded", and this is the first time the sweep's duration matters to a plan.

**Production baseline, recorded 2026-09-11: 2 min 36.89 s wall, 0 failed**, against 50 s on the
dev restore for the same account count. The "previous production duration plus ~12 s" above was
never checkable — the prior duration was never written down — so treat 2:36.89 as the baseline the
next slice compares against, not as a regression against the restore. `heroku run` dyno start-up
and the network hop to the database are inside that number; the restore's 50 s is not comparable.

### 5. Invariants

```bash
heroku run rails runner 'puts AccountMetric.joins(:account).where(accounts: { status_type: 1 }).where(rolling_365_parent_count: nil).count' -a insgtapi
```

Expect **0**. Then, from a fresh restore or via `rails runner`, the invariant set. Every row is
over active accounts (`JOIN accounts ON status_type = 1`).

| Check | Expected |
| :-- | :-- |
| `rolling_365_parent_count IS NULL` | 0 |
| `rolling_365_parent_count > peak_365_parent_count` | 0 |
| `rolling_90_parent_count > rolling_365_parent_count` | 0 |
| `rolling_365_parent_count > lifetime_parent_count` | 0 |
| `peak_365_parent_count > lifetime_parent_count` | 0 |
| `(peak_365_ended_on IS NULL) <> (peak_365_parent_count = 0)` | 0 |
| `peak_365_ended_on > CURRENT_DATE` | 0 |
| `rolling_365_value_cents > lifetime_value_cents` | 0 |
| `active_user_count IS NULL` | 0 |
| `rolling_365_value_cents > 0 AND rolling_365_parent_count = 0` | a small number (3 on the 2026-09-10 restore) — **legal**, §5.4: a paid order cancelled after payment, or a self-paying child with no property parent in the year |
| accounts with `active_user_count > 1` | ≈ 102 |
| accounts with `active_user_count = 0` | ≈ 5 |
| `active_user_count` ≠ `Account#users_count` for any active account | 0 |
| `SUM(lifetime_value_cents)` | unchanged from the night before (370,187,800 on the restore) |

The three non-zero rows reproduced exactly on the 2026-09-11 restore after a second independent
recompute — 3 legal value-without-parents, 102 accounts over one active user, 5 at zero — so the
`≈` on the last two is tighter than it looks. `SUM(lifetime_value_cents)` read 370,825,800 there
against the 2026-09-10 restore's 370,187,800; the 638,000 is a day of new orders, not a
regression. That row only means anything compared **before and after the deploy on the same
database** — never against a restore captured on a different day.

Fleet sums against a live re-derivation, with the check's cutoff pinned to the sweep's — otherwise
the shoots that aged out between the two show up as a difference of a few rows:

```ruby
sweep_start = AccountMetric.joins(:account).where(accounts: { status_type: 1 }).minimum(:computed_at)
cutoff = sweep_start - 365.days
# SUM(rolling_365_parent_count) == Order.qualifying_parents on active accounts with shoot_date_sql >= cutoff
# SUM(rolling_365_value_cents)  == the billable sum over the same rows' own shoot dates >= cutoff
```

Both matched exactly on the restore (1,485 / 514 accounts; 42,882,200 cents). The plan's survey
figures (1,486 / 515; 42,904,700) were one order — 73516, shot 2025-09-10 16:00 UTC, 22,500 cents —
that aged out between the survey and the sweep.

### 6. Spot checks

Values on the 2026-09-10 restore; production on deploy day will differ by the shoots completed
since, so re-derive with the fleet queries before comparing. Every column matched the plan's
reasoned expectations exactly on the restore.

**These numbers move daily — do not treat them as pass/fail.** Re-derived on the 2026-09-11
restore, one day later, four of the five accounts had already drifted: 10288 and 1123 each lost a
parent off the back of the window (rolling 55 → 54 and 26 → 25, value −14,500 each, `lifetime`
static), while 11510 and 1593 each gained a shoot (`lifetime` 25 → 26 and 164 → 165, rolling and
value up with it). Only account 88 was unchanged on all six columns. Every drift moved in a
self-consistent direction and every invariant below still read 0.

| Account | `rolling_365_parent_count` | `peak_365_parent_count` | `peak_365_ended_on` | `rolling_365_value_cents` | `active_user_count` | `lifetime_parent_count` |
| --: | --: | --: | :-- | --: | --: | --: |
| 10288 | 55 | 81 | 2026-07-03 | 832,500 | **6** | 82 |
| 88 | 29 | 31 | 2026-06-08 | 1,168,500 | 1 | 225 |
| 1123 | 26 | 26 | 2026-08-28 | 600,000 | 4 | 153 |
| 11510 | 25 | 25 | 2026-08-14 | 702,000 | 1 | 25 |
| 1593 | 20 | 35 | 2021-08-09 | 582,000 | 2 | 164 |

Two cells are absolute — they do not move with new shoots, so check them as pass/fail:

- **10288 is the G1 canary.** It has 9 membership rows and 6 people; reading 9 means `DISTINCT` or
  the users join was lost. Read **6**. Confirmed 6 on the 2026-09-11 restore.
- **1593's `peak_365_ended_on` is anchored at 2021-08-09.** A five-year-old peak cannot shift
  unless the peak scan is wrong. This is the reactivation shape §4.3 describes: an anchor five
  years ago, occasional now. Confirmed unmoved on the 2026-09-11 restore.

The rest are shape checks, and the account that carries each shape changes as shoots age out:

- **The `peak == rolling` case** — where `>=` must not be `>` — was 1123 on the 2026-09-10
  restore. It was **11510** on 2026-09-11 (26/26), because a shoot aged out from under 1123 and a
  new one landed on 11510. Read this shape off whichever account currently satisfies it after the
  production recompute, not off a fixed account id.
- **1123 now demonstrates the complementary case**: rolling 25 against a peak of 26 still ending
  2026-08-28. A parent aged out of the trailing window and the historical max correctly *held*
  rather than following it down. If 1123's peak ever tracks rolling downward, the peak is being
  recomputed as a current-window value instead of a max.
- **11510's peak equals its lifetime** and its trailing value equals its `lifetime_value_cents`:
  every shoot inside one year. Both still true on 2026-09-11 at 26 parents / 728,500 cents.

### 7. The read-out

```bash
heroku run rake accounts:joint_ownership -a insgtapi
```

Its Snapshot line reads today's `computed_at`; its Context line "Accounts with no recomputed
metrics row" reads 0; its "shoots in the window across N accounts" line equals the fleet sums from
step 5 **minus the three excluded accounts** (2, 89, 2555 — on the restore, 12 shoots on 2 of
them: 1,485 − 12 = 1,473 across 514 − 2 = 512). The plan's invariant table said "equals the two
sums"; the exclusion is the difference and is by design.

Production on 2026-09-11 read **1,476 shoots across 513 accounts**, and it reconciles the same
way: the fleet sums were 1,488 across 515, and accounts 2 and 2555 carry 3 and 9 shoots — the same
12 shoots on 2 of the 3 excluded accounts as the restore. 1,488 − 12 = 1,476, 515 − 2 = 513.

**The exclusions net out of the user counts too, and that trips the step 5 comparison.** The
segment table's "More than one active user only" (99) plus "Both" (2) is 101 accounts with
`active_user_count > 1`, against the ≈102 the invariant table expects. Both are right: account 2
(InsightPhotos) holds 16 active users and is excluded from the read-out, so the fleet count is 102
and the in-scope count is 101. Do not chase the missing one. "Accounts with no active users" needs
no such adjustment — all 5 are in scope, so the read-out and the invariant both read 5.

### 8. insgt-ops

Nothing to deploy. The interface ignores the new keys.

## Rollback

### Code only (schema stays)

```bash
heroku rollback --app insgtapi
```

Old code runs against the new schema without error, but the five columns do **not** go back to
NULL: `Calculator#call` assigns only the keys its compute hash carries, so the old code keeps
refreshing `computed_at` every night while leaving the five holding the values of the last sweep
under the new code. The dialog and the read-out go on showing them, and
`accounts:joint_ownership` prints a *fresh* Snapshot date over *stale* volume and user counts,
because the Snapshot line reads `computed_at`. Tell anyone reading those numbers that they stopped
moving, or roll the schema back too.

### Schema

```bash
heroku run rake db:rollback STEP=1 -a insgtapi
```

Drops the five columns. `strong_migrations` does not check the down direction (`check_down`
defaults to `false`). Nothing references them once the code is rolled back; roll the code back
first.

## Deploy log

- 2026-09-10 — verified on the dev restore (2026-09-10 production snapshot, 4,079 active accounts):
  migrate → rollback → migrate clean; recompute 4,079 scanned, 0 failed, 50 s wall; every
  invariant 0; fleet sums matched the live re-derivation exactly with the cutoff pinned; all five
  spot checks matched the plan on all six columns; `lifetime_value_cents` unchanged at
  370,187,800. Slice 2 adds 3.09 ms/account (busiest 150) and 2.60 ms (random 150) to
  `Calculator#compute`.
- 2026-09-11 — second dev-restore pass, on a fresh 2026-09-11 snapshot after an independent
  `metrics:recompute`: all twelve invariants 0, the three non-zero rows exact again (3 legal
  value-without-parents, 102 over one active user, 5 at zero), 10288's `active_user_count` 6,
  1593's `peak_365_ended_on` unmoved at 2021-08-09, 11510 still peak == lifetime == 26 with
  trailing value == `lifetime_value_cents` == 728,500. Four of the five spot-check accounts had
  drifted one day of shoots from the 2026-09-10 table and the `peak == rolling` shape had moved
  from 1123 to 11510, so §6 was rewritten to name the shapes and the two absolute cells rather
  than fixed account ids.
- 2026-09-11 — **deployed to production.** Migration `20260911120000` logged at 13:24:41 UTC,
  outside the 02:15–02:45 scheduler window. `metrics:recompute` 2 min 36.89 s wall, 0 failed,
  writing a 13:26:20 UTC snapshot over 4,078 active accounts. Every step 5 invariant 0. All five
  step 6 spot checks matched the same-day dev restore on all six columns — 30 of 30 cells — with
  both absolute cells good: 10288's `active_user_count` 6, 1593's `peak_365_ended_on` still
  2021-08-09. 11510 carried the `peak == rolling` shape (26/26, peak == lifetime, trailing value
  == `lifetime_value_cents` == 728,500) and 1123 the complementary one (peak 26 held over rolling
  25). Fleet `SUM(rolling_365_parent_count)` 1,488 matched a live `Order.qualifying_parents`
  re-derivation exactly with the cutoff pinned to the sweep; `SUM(rolling_365_value_cents)`
  43,026,700. The read-out's Snapshot line read the new `computed_at`, "no recomputed metrics row"
  0, and its 1,476 shoots across 513 accounts reconciled to the fleet sums minus the 12 shoots on
  the 2 excluded accounts. Steps 4 and 7 were amended from this run: the sweep now has a
  production duration baseline, and the read-out's user counts are documented as net of the
  exclusions (101 in scope vs 102 fleet-wide, account 2 holding 16 active users).
