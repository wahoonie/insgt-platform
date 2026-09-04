# Runbook: Recapture Order Type Deploy

**Last updated:** 2026-09-01
**Repos:** insgt-api, insgt-ops
**Estimated duration:** ~20 min
**Status:** Not yet deployed

## Summary

Introduces the **Recapture** order type — a $0, ops-created, internal service-recovery visit —
plus recapture counts and rates on `account_metrics` / `system_metrics`, and its own tiles in ops.

**The date this runs is the cutover date.** Before it, service-recovery visits were booked as $0
Reshoots and are indistinguishable from goodwill comps. Nothing is backfilled. Record the actual
deploy date in the Status line above when it ships, and see
`docs/decisions/002-recapture-order-type.md`.

## Prerequisites

- [ ] CI green on `main` in both repos
- [ ] No active deploy in flight
- [ ] Baseline captured: run `orders:audit_reshoots` **before** deploying and keep the output.
      It is the pre-cutover reshoot baseline every later comparison is measured against, and this
      deploy also corrects its comped bucket (see step 5).

## Steps

### 1. Deploy code (insgt-api)

```bash
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2026-09-01_lock.dump
git push heroku master
```

Watch build to completion before continuing.

### 2. Run migrations

```bash
heroku run rake db:migrate -a insgtapi
heroku restart --app insgtapi
```

Two migrations:

- `20260901120000_create_recapture_order_type` — inserts the pinned row at **id 300** and bumps
  `order_types_id_seq` past it. Self-verifying: it raises unless exactly one row is keyed
  `recapture` at id 300.
- `20260901120001_add_recapture_counts_to_metrics` — 4 columns × 2 tables, schema-add only.

**Verify:**

```bash
heroku run rails db:migrate:status -a insgtapi
heroku run rake order_types:verify_pinned_ids -a insgtapi
```

`verify_pinned_ids` is the guard against constant drift — the id is pinned in code as
`Order::RECAPTURE_ORDER_TYPE_ID` and this is what confirms it still names the right row. It cannot
live in a spec: the test database is built from `schema.rb`, which never runs data migrations.

### 3. Populate the new columns

```bash
heroku run rake metrics:recompute -a insgtapi
```

Do this in the deploy window rather than waiting for the 02:30 Heroku Scheduler run. Until it
runs, the new counts read 0 and the rates read NULL — correct anyway, since no recapture exists
yet, but the columns should agree with the rest of the snapshot.

No new cron to register. `metrics:recompute` is already scheduled; there is no `sidekiq.yml` and
nothing here is self-scheduling.

### 4. Deploy Operations (insgt-ops)

Follow `insgt-ops/DEPLOY.md`. **API first** — the ops summary fields are all optional, so ops
deployed early would render em dashes, but there is no reason to.

**Verify:** the account metrics card and the KPIs page each show two new tiles, *Recapture rate
(90d)* and *(lifetime)*, separate from the reshoot tiles.

### 5. Confirm the audit read-out

```bash
heroku run rake orders:audit_reshoots -a insgtapi
```

The "$0 total (comped)" bucket now excludes `parent_pays` rows, which bill through their parent
and are real revenue. A new "$0 on this order (parent_pays)" line appears when any exist. Expect
the comped count to be **the same or lower** than the baseline captured in the prerequisites; if
it moved, the difference is rows that were previously miscounted as comped.

### 6. Tell ops the type exists

Recapture appears automatically in the ops order-create dialog (it is an active order type). It is
invisible to the agent-facing PWA because its `cart` is NULL — that, not the `public` flag, is what
gates the customer form. **Do not announce it before step 1 is live**, or a recapture created
against old code would be counted as a shoot until the next recompute.

## Rollback

### If steps 1–2 fail

Standard code rollback. Both migrations are additive and safe to leave in place even if the code
is reverted — the predicates bind a plain integer, so they simply exclude nothing when the row is
absent.

```bash
heroku rollback --app insgtapi
```

### After a recapture order exists

Do **not** roll back `20260901120000`. Its `down` hard-deletes the lookup row and will fail on a
foreign key once any order references it — which is the correct behaviour. Roll back code only.
