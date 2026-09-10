# Runbook: Account Classification Slices 1a and 1b Deploy

**Last updated:** 2026-09-10
**Repos:** insgt-api (insgt-ops for the order-type form — step 9)
**Estimated duration:** ~30 min, plus the memo hand-over
**Status:** Deployed 2026-09-10 by Dan (API, OPS, steps 1–9)

## Summary

Ships two slices of `docs/architecture/account-classification.md` together, because 1b cannot run
without 1a's column and 1a alone changes nothing anyone sees:

- **1a** — `order_types.category_type` (four migrations, `20260904120000..3`), the enum on
  `OrderType`, and the API field. Merged to `master` at 1b88f09 on 2026-09-04; never deployed.
- **1b** — the `Order.qualifying` / `qualifying_parents` / `billable` / `pending_shoots` scopes and
  every consumer moved onto them: both metrics calculators, the teams dashboard order count and
  "only did one shoot" filter, the CSV export, the pending-shoots count, churn, joint ownership,
  the reshoot audit's linkage read-out, and the first-shoot KPI. Branch
  `feat/account-classification-1b`, commits 7aa170b..afeb1f7.

**Numbers move.** `docs/architecture/shift-memo-slice-1b-2026-09-10.md` says which and by how much
on the 2026-09-08 restore. Step 5 regenerates it against production and step 6 hands it to Don
before the first recompute writes the new values.

`master` also carries slice 4's `account_type` column, API and role gates (c999b29, merged
2026-09-08). They deploy with this whether or not they are wanted yet; nothing in 1b reads them.

## Deploy order and the window it closes

New code reads `order_types.category_type` on every request that touches a shoot count: the
accounts index with the created-on or only-once filters or the `order_count` field, the account
metrics dialog (pending shoots), and the CSV export. Between the release going live and
`db:migrate` finishing, those requests would 500 on the missing column. There is no release phase
in the Procfile, so the window is closed by hand: **maintenance mode on before the push, off after
the migrations**. A few minutes of 503.

Old code against the new schema is safe: the column is additive and every row is valued by the
backfill. The one thing old code cannot do once migration 4 flips NOT NULL is create an order
type, because it does not send `category_type` (see Rollback).

## Prerequisites

- [ ] insgt-api `bundle exec rspec` green on the branch (1,556 examples on 2026-09-10)
- [ ] `feat/account-classification-1b` merged to `master` with `--no-ff`; `origin/master` pushed
- [ ] If more than a week has passed since 2026-09-10, the memo re-read against a fresh production
      restore: `bin/rails account_classification:shift_memo_1b OUT=tmp/memo.md CSV=tmp/rows.csv`
- [ ] Baseline captured: `heroku run rake orders:audit_reshoots -a insgtapi` output kept. The
      linkage section changes meaning — a recapture attached to a completed reshoot now counts
- [ ] insgt-ops `main` carries the order-type form's `categoryType` field (commit 782a8c85, in no
      tagged release as of 2026-09-10) and is ready to deploy per `insgt-ops/DEPLOY.md`
- [ ] No active deploy in flight

## Steps

### 1. Back up the database

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-<date>_lock.dump
```

### 2. Maintenance on, deploy code

```bash
heroku maintenance:on --app insgtapi
git checkout master && git merge --no-ff feat/account-classification-1b
git push origin master
git push heroku master
```

Watch the build to completion before continuing. Do not lift maintenance yet.

### 3. Run migrations

```bash
heroku run rake db:migrate -a insgtapi
heroku run rails db:migrate:status -a insgtapi
heroku run rake order_types:verify_pinned_ids -a insgtapi
heroku restart --app insgtapi
heroku maintenance:off --app insgtapi
```

Five migrations: the four `category_type` migrations (nullable add, backfill keyed on
`order_types.key` that raises on any unmapped row, unvalidated CHECK, validate-and-flip) and
`20260904120004_add_account_type_to_accounts` (slice 4, nullable add). The backfill is the one
most likely to stop: it raises naming the row if production holds an order type whose `key` is
not in `CATEGORY_KEYS`. If it does, decide the category, add the key in a new migration, and
rerun; do not lift maintenance with the column half-valued.

**Verify:** `verify_pinned_ids` prints "All 5 pinned order-type ids match their keys."

### 4. Record the cutover timestamp (§2.1)

```bash
heroku run rails runner 'puts OrderType.find(300).created_at' -a insgtapi
```

Write it into `account-classification.md` §2.1 if it differs from 2026-09-02 12:01:26 UTC, the
value on the 2026-09-08 restore.

### 5. Produce the production memo — BEFORE recompute

The stored `account_metrics` rows are still the old definition until `metrics:recompute` runs.
The memo's stored-row cross-check depends on that, so this step comes first.

**Primary: a fresh production snapshot in local Postgres.** Capture and restore (step 1's dump
works), run the five migrations against it (`bin/rails db:migrate` — the scopes read
`category_type`), then from `apps/insgt-api` on the merged code:

```bash
bin/rails account_classification:shift_memo_1b \
  OUT=../../docs/architecture/shift-memo-slice-1b-<date>-production.md \
  CSV=tmp/shift-1b-production.csv
```

Progress prints to the terminal; the memo goes to the platform repo's `docs/architecture/`
(the path is relative to `apps/insgt-api` — there is no `docs/architecture` in insgt-api itself);
the per-account CSV stays in `tmp/` for Don if he wants the full list.

**Fallback: a one-off dyno**, if a snapshot is not to hand. The dyno's stdout and stderr arrive
over one stream, so the task keeps its progress lines off when stderr is not a terminal, and
`--no-tty` keeps carriage returns out of the file:

```bash
heroku run --no-tty --exit-code rake account_classification:shift_memo_1b -a insgtapi \
  > ../../docs/architecture/shift-memo-slice-1b-<date>-production.md
```

Either way, expect the Population table to show 0 stored rows disagreeing on any column other
than `rolling_90_parent_count`, that one to be the parents completed in the hours since the
nightly ran, and every "Residual" line at $0.00. Anything else is a finding: stop and look
before step 7.

### 6. Hand the memo to Don

This is the hand-over point. He reads it before the numbers change on the dashboard. Commit the
production memo beside the dev one.

### 7. Recompute

```bash
heroku run rake metrics:recompute -a insgtapi
```

Every `account_metrics` row and the `system_metrics` row now carry the new definitions. Dev
timing for 4,076 accounts: see the deploy log.

### 8. Spot checks

- An account from the memo's "By lifetime shoot count" table reads its New value on the dashboard.
- `SystemMetric.current.lifetime_parent_count` equals `Order.qualifying_parents.count` across the
  fleet, and the sum of active accounts' `lifetime_parent_count` is that minus shoots on
  soft-deleted accounts.
- An account with a reshoot booked ahead shows it in the dialog's Pending shoots.
- The teams dashboard "Only did one shoot" returns rows, and the order count beside each reads 1.

### 9. Deploy Operations

Follow `insgt-ops/DEPLOY.md`. Until this ships, the order-type form cannot create a new type (the
API now requires `category_type`); editing existing types is unaffected. The same release carries
slice 4's team-type dialog and filter.

## Rollback

### Code only (schema stays)

```bash
heroku rollback --app insgtapi
```

Old code runs against the new schema without error. Two consequences: the next nightly recomputes
every metric under the old definitions, so the dashboard reverts by morning (or run
`metrics:recompute` to do it now), and creating an order type fails until the code is rolled
forward or migration 4 is reversed.

### Reversing the NOT NULL

`20260904120003` and `20260904120002` reverse cleanly (`change_column_null` back to nullable, drop
the CHECK): `heroku run rake db:rollback STEP=2 -a insgtapi`. Leave the column and backfill
(`..120000`, `..120001`) in place; they are additive and correct, and re-running the backfill later
is a no-op.

## Deploy log

- 2026-09-10 — memo produced against a local production snapshot (`shift-memo-slice-1b-2026-09-10-production.md`): 4,078 active accounts, every residual $0.00, 0 window mismatches, 2 revenue mismatches (accounts 60 and 10288, orders changed after the 02:31 nightly). Migration timings and recompute runtime not recorded.
