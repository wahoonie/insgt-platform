# Runbook: Postal Code Descriptions Deploy

**Last updated:** 2026-05-11
**Repo:** insgt-api
**Estimated duration:** ~30 min (depends on Sidekiq queue drain time in step 3)
**Status:** Deployed 2026-05-11

## Summary

Ships the 5 SEO schema-add migrations and backfills `seo_city_names` /
`seo_neighborhood_names`, then regenerates all postal code descriptions.

Steps 4 and 5 can run in parallel. Step 6 must wait for both.

## Prerequisites

- [ ] CI green on `main`
- [ ] Sidekiq dashboard open in a browser tab
- [ ] Anthropic API key present in target env (regeneration calls the API)
- [ ] No active deploy in flight

## Steps

### 1. Deploy code

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2025-05-17_lock.dump
git push heroku master
```

Watch build to completion before continuing.

### 2. Run schema migrations

```bash
heroku run rake db:migrate
```

Should be fast — all 5 are schema-add only, no data backfill.

**Verify:** `bin/rails db:migrate:status` shows all 5 as `up`.

```bash
heroku run rails db:migrate:status -a insgtapi
```

### 3. Populate coordinates (async)

```bash
heroku run rake city_seo:populate_coordinates -a insgtapi
```

Enqueues geocoding jobs into Sidekiq. Rake returns immediately.

**Wait for the queue to drain before continuing.** Options:

- Sidekiq UI: watch the relevant queue depth go to 0
- Shell poll:
  ```bash
  heroku run runner '
  stats = Sidekiq::Stats.new
  puts "enqueued:  #{stats.enqueued}"          # waiting to start
  puts "busy:      #{Sidekiq::WorkSet.new.size}" # currently running
  puts "retries:   #{stats.retry_size}"        # failed, will retry
  puts "scheduled: #{stats.scheduled_size}"    # scheduled for future
'
  ```

**Verify before continuing:** queue size is 0 AND retry set is empty
(failed jobs would block step 4 from finding coords).

### 4. Populate city names (synchronous)

```bash
heroku run rake city_seo:populate_city_names -a insgtapi
```

Reads the coords from step 3, fills `seo_city_names`.
Seconds per few hundred cities. Blocks the shell until done.

**Can run in parallel with step 5** — open a second shell.

### 5. Populate neighborhood names (synchronous, parallel-safe)

```bash
heroku run rake city_seo:populate_neighborhood_names -a insgtapi
```

Fills `seo_neighborhood_names` from tags. Independent of step 4 —
does not depend on coordinates or city names.

### 6. Regenerate postal code descriptions

**Do not start until steps 4 AND 5 are both complete.**

```bash
heroku run rake postal_code_descriptions:regenerate_all  -a insgtapi
```

Calls the Anthropic API per zip; expect this to be the longest step.
Watch for API errors and rate-limit responses in the rake output.

### 7. Regenerate postal code descriptions

**Do not start until steps 4 AND 5 AND 6 are complete.**

```bash
heroku run rake city_descriptions:regenerate_all -a insgtapi
```

Calls the Anthropic API per zip; expect this to be the longest step.
Watch for API errors and rate-limit responses in the rake output.


## Verification

- [ ] Spot-check 3 random zips: `ZipCode.find_by(...).ai_intro_description`
      is present and references real neighborhoods from `seo_neighborhood_names`
- [ ] No new Sentry errors in last 10 min
- [ ] Sidekiq retry set empty


### 8. Backfill metrics
```bash
heroku run rake metrics:backfill_order_durations -a insgtapi
```

### 9. Deploy Operations

Follow operations deployment instructions.

### 10. Deploy insgt-site-sls

Follow README deployment instructions.

### 11. Export Site

Export website using utilities in operations app.

## Rollback

### If steps 1–2 fail

Standard code rollback. The 5 migrations are schema-add only, so leaving
them in place is safe even if code is reverted.

```bash
heroku rollback -app insgtapi
```

### If step 3 fails mid-flight (some coords populated)

Re-running `city_seo:populate_coordinates` is safe — the task should
no-op for cities that already have coords. (Verify this assumption against
the task implementation before relying on it.)

### If step 4, 5, or 6 fails partway through

All three populate writes to `ai_*` columns under the
append-only/immutable record pattern — re-running is safe and will
either no-op or append new records. No data destruction risk.

**If you need to clear bad AI output** before re-running:
manual cleanup via Rails console, scoped to the affected records.
Do not truncate the `ai_*` columns wholesale.


To rollback the website:

Set the origin for the www.insightphotos.net distribution to 1778219877


## Notes

- The `populate_coordinates` step is the only async one. Every other
  step blocks the shell — if a rake task returns immediately, something
  is wrong.
- Steps 4 and 5 in parallel saves ~half the time of the data-backfill
  phase. Worth doing.
