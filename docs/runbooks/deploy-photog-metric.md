# Runbook: Photographer Confirm Metric Deploy

**Last updated:** 2026-05-18
**Repo:** insgt-api
**Estimated duration:** ~10 min
**Status:** Deployed 2026-05-18

## Summary

Ships phographer confirm metric migrations and backfills the data for it.

## Prerequisites

- [ ] CI green on `main`
- [ ] No active deploy in flight

## Steps

### 1. Deploy code

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2025-05-19_lock.dump
git push heroku master
```

Watch build to completion before continuing.

### 2. Run schema migrations

```bash
heroku run rake db:migrate -a insgtapi
```

**Verify:** `bin/rails db:migrate:status` shows all 5 as `up`.

```bash
heroku run rails db:migrate:status -a insgtapi
```

### 3. Populate from existing data (async)

```bash
heroku run rake metrics:backfill_time_to_photographer_confirm
```

### 4. Deploy Operations

Follow operations deployment instructions.

## Rollback

### If steps 1–2 fail

Standard code rollback. The 5 migrations are schema-add only, so leaving
them in place is safe even if code is reverted.

```bash
heroku rollback -app insgtapi
```
