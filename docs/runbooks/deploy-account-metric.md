# Runbook: Account Confirm Metric Deploy

**Last updated:** 2026-07-06
**Repo:** insgt-api
**Estimated duration:** ~10 min
**Status:** Deployed 2026-07-06

## Summary

Ships KPI metrics for Ops.

## Prerequisites

- [ ] CI green on `main`
- [ ] No active deploy in flight

## Steps

### 1. Deploy code

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2026-07-06_lock.dump
git push heroku master
```

Watch build to completion before continuing.

### 2. Run schema migrations

```bash
heroku run rake db:migrate -a insgtapi
heroku restart --app insgtapi
```

**Verify:** `bin/rails db:migrate:status` shows all 5 as `up`.

```bash
heroku run rails db:migrate:status -a insgtapi
```

### 3. Populate from existing data (async)

```bash
heroku run rake metrics:backfill_time_to_account_confirm -a insgtapi
heroku run rake metrics:recompute -a insgtapi
```

### 4. Deploy Operations

Follow operations deployment instructions.

### 5. Setup Heroku Cron Job Rake Task

Sign in to Heroku and setup the cron job.

Read insgt-platform/apps/insgt-api/docs/ops/metrics-recompute-cron.md

Register the nightly cron for metrics:recompute on Render/Heroku Scheduler — it is not self-scheduling (no sidekiq-cron). Suggested 02:30 UTC (docs/ops/metrics-recompute-cron.md).

### 6. Update icons

Ensure all package and service icons are up to date.

## Rollback

### If steps 1–2 fail

Standard code rollback. The 5 migrations are schema-add only, so leaving
them in place is safe even if code is reverted.

```bash
heroku rollback -app insgtapi
```




W, [2026-07-06T11:21:55.230379 #2]  WARN -- : [OrderMetrics] Negative duration for Order#19606: -1974m
Scanned 19000 orders...
W, [2026-07-06T11:21:57.542613 #2]  WARN -- : [OrderMetrics] Negative duration for Order#20740: -14348m