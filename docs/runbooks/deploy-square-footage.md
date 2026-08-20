# Runbook: Property Facts Lookup (Square Footage) Deploy

**Last updated:** 2026-07-15
**Repo:** insgt-api + insgt-ops
**Estimated duration:** ~25 min
**Status:** Deployed 2026-07-21

## Summary

Ships property facts — square footage, lot size, property type, neighborhood/community — attached to
`Property` via an async Anthropic **web-search** lookup, overridable in Ops with on-demand **Recalculate**.
Backend (insgt-api) + Ops UI (insgt-ops).

Phase 2 auto-on-create is behind `PROPERTY_FACTS_AUTOLOOKUP_ENABLED`. **Deploy with the flag OFF**, validate
accuracy on real addresses via manual Recalculate, then flip it ON. That flag is also the kill switch.

**Also riding along: the account-info dialog redesign.** Adds `first_shoot_at` and
`most_recent_shoot_at` to `account_metrics` / `system_metrics`, relaxes `/accounts/:id/metrics` and
`/accounts/:id/order_metrics` from owner-only to owner+admin+scheduler (money fields stay owner-only,
gated in the view), and rebuilds the Ops account-info card. Adds **step 2b** below — a
`metrics:recompute` run without which the two new date fields read null everywhere.

The card's "Pending shoots" count is **not** a column: `AccountPendingShootsService` counts it live
per request, so it needs no backfill and is never stale. `/accounts/:id/metrics` also **no longer
204s** when an account has no nightly row — it returns 200 with the live pending count, so a
brand-new account still gets a correct badge.

## Prerequisites

- [ ] `feat/square-footage` merged to `main`, CI green (insgt-api **and** insgt-ops)
- [ ] `ANTHROPIC_API_KEY` present in target env **and web search enabled** on the Anthropic account
- [ ] Sidekiq running (it processes the lookup) + dashboard open in a tab
- [ ] `PROPERTY_FACTS_AUTOLOOKUP_ENABLED` unset / not yet `true` (defaults OFF)
- [ ] No active deploy in flight

## Steps

### 1. Deploy API code

```bash
heroku config:set PROPERTY_FACTS_AUTOLOOKUP_ENABLED=false --app insgtapi
heroku pg:backups:capture --app insgtapi
heroku pg:backups:download --app insgtapi
mv latest.dump tmp/production-latest-2026-07-21_lock.dump
git push heroku master
```

### 2. Run schema migration

```bash
heroku run rake db:migrate -a insgtapi
heroku restart --app insgtapi
```

Fast — schema-add only (adds `ai_*` / `edited_*` fact columns + property-type FK indexes, no backfill;
plus the account/system metrics shoot-date columns, also schema-add).

**Verify:** the new migration shows `up`.

```bash
heroku run rails db:migrate:status -a insgtapi
```

### 2b. Recompute account metrics (required for the account-info card)

```bash
heroku run rake metrics:recompute -a insgtapi        # DRY_RUN=true to preview
```

The two new columns are computed inside `AccountMetrics::Calculator#computed_values`, so this sweep
is what populates them — there is no separate backfill task. **Until it runs, every account reads
`first_shoot_at`/`most_recent_shoot_at` as null** and the dialog's First/Most Recent Shoot rows render
as em dashes. (Pending shoots is unaffected — it is counted live, not stored.) Existing metrics are
unaffected; the sweep is idempotent and isolates per-account failures.

**Verify** against a known account:

```bash
heroku run rails runner 'm = AccountMetric.find_by(account_id: 10); puts [m.first_shoot_at, m.most_recent_shoot_at].inspect' -a insgtapi
```

The dates should equal `MIN`/`MAX` `paid_at` over that account's completed, non-reshoot parent orders.
Note `paid_at` is a **payment** timestamp, not the shoot date — see the
`AddShootDatesAndPendingCountToMetrics` migration comment for why, and what it costs.

**Confirm the nightly cron is actually registered** (`docs/ops/metrics-recompute-cron.md`, suggested
02:30 UTC). `metrics:recompute` is not self-scheduling. The account-metric runbook instructs
registering it, but this has **not been verified live** — if it is missing, these dates go stale
rather than wrong, and this manual run is the only thing populating them.

### 3. Confirm auto-lookup is OFF

```bash
heroku config:get PROPERTY_FACTS_AUTOLOOKUP_ENABLED -a insgtapi   # expect empty
heroku config:set PROPERTY_FACTS_AUTOLOOKUP_ENABLED=true -a insgtapi
```

Explicitly OFF so the deploy does not start firing paid lookups on every new order before accuracy is
validated. Recalculate still works on demand.

### 4. Deploy Ops (insgt-ops)

Build prod → upload to S3 → invalidate CloudFront (manual pipeline). Follow operations deployment
instructions. The facts panel surfaces inside the **order property dialog** (pencil on the order summary).

### 5. Smoke-test a real address (manual)

In Ops: open an order's property → facts panel → **Recalculate** → poll to **Complete**. Console fallback:

```bash
heroku run rails runner 'PropertyDataLookupWorker.perform_async(Property.find(PROPERTY_ID).id)' -a insgtapi
```

**Verify:** `ai_*` populated, `property_data_status = succeeded`, citations present; a low-confidence
neighborhood stays a raw suggestion (no `Area` attached). Also confirm an Ops override (edited sq ft) saves
and the active value flips to it.

### 6. Enable auto-on-create (Phase 2) — only after accuracy is validated

```bash
heroku config:set PROPERTY_FACTS_AUTOLOOKUP_ENABLED=true -a insgtapi
```

No redeploy needed (config change restarts dynos). **Verify:** a new-address order enqueues exactly one
`PropertyDataLookupWorker` job; a re-order against a known address enqueues none.

## Verification

- [ ] `db:migrate:status` all `up`; new columns present
- [ ] Manual recalc: `ai_*` populated + citations, status `succeeded`
- [ ] Low-confidence geo → raw suggestion, no stray `Area`
- [ ] Ops override (edited sq ft) → active value flips, persists
- [ ] Flag ON: new-address order enqueues 1 job; Sidekiq retry set empty
- [ ] No new Sentry errors in last 10 min

### Account-info card

- [ ] `metrics:recompute` ran; a known account's dates/pending are populated (step 2b)
- [ ] As an **admin**: open an order → account info (ℹ next to the account name) → stats rows and the
      Active/Inactive badge render, brokerage shows, no money figures anywhere on the card
- [ ] As a **processor** (from the processing queue, on an order assigned to you): the identity card
      renders with **no stats block and no badge** — unchanged from before this deploy. This is the
      one that regresses if the client-side gate is lost; processors 401 on `/metrics` by design
- [ ] A **video** order's info dialog is unchanged (that branch was deliberately untouched)
- [ ] `/teams/:id/edit` → the account metrics card now renders for admins/schedulers for the first
      time (it was owner-gated and always hid itself). Money tiles must be **absent** for them and
      present for an owner
- [ ] Scheduler → click an order → account info: the brokerage row is populated (it was silently
      missing before — four scheduler dispatches omitted `includeOrganization`)

## Rollback

### Kill switch (no redeploy — use first)

```bash
heroku config:set PROPERTY_FACTS_AUTOLOOKUP_ENABLED=false -a insgtapi
```

Stops all auto-lookups instantly. Manual Recalculate is unaffected. Use this the moment cost or accuracy
looks wrong — before considering a code rollback.

### Code rollback

```bash
heroku rollback -a insgtapi
```

The migration is schema-add only, so leaving it in place is safe even if code is reverted. Ops: redeploy the
previous build to S3 + invalidate CloudFront.

Rolling back the API also re-gates `/accounts/:id/metrics` and `/order_metrics` to owners. If Ops is
still on the new build, the account-info card's stats block and the `/teams/:id/edit` metrics card
will 401 and hide themselves for admins/schedulers — degraded, not broken (the identity card and the
rest of the page still render). **Roll Ops back too, or forward-fix.** The recomputed metric columns
are harmless if the code is reverted: nothing reads them.

### Bad AI output

`ai_*` is overwrite-on-force — just re-run **Recalculate**, or clear via Rails console scoped to the affected
record. Never wholesale-truncate the `ai_*` columns. Human `edited_*` overrides are never touched.

## Tuning (optional env vars)

The lookup model, source allow-list, and web-search tool version are env-overridable so you can A/B
accuracy during step 5 without a redeploy:

- `PROPERTY_FACTS_MODEL` — the Anthropic model. Default `claude-sonnet-4-5`. Try e.g. `claude-sonnet-5`
  or `claude-opus-4-8` on a handful of known addresses and compare `ai_*` accuracy before committing.
- `PROPERTY_FACTS_ALLOWED_DOMAINS` — comma-separated domains the search is restricted to. **Defaults to
  `zillow.com,redfin.com,sdarcc.gov`** (last = SD County Assessor) — precision over recall, the
  highest-leverage accuracy knob. Set it **empty** to search the whole web; add other counties'
  assessors as coverage expands. Two gotchas: (1) every domain must be crawlable by Anthropic's user
  agent or the API **400s the whole request** — `realtor.com` blocks the crawler and is excluded for
  that reason, so test any addition with a single recalc. (2) a property not on the allowed sites
  returns `not_found` (ops re-runs / overrides). sdarcc.gov also restricts online APN lookups (AB 1785),
  so the listing sites do most of the work.
- `PROPERTY_FACTS_WEB_SEARCH_VERSION` — web-search tool version. Default `web_search_20250305` (basic,
  works on every model). Set `web_search_20260318` **only** on a model that supports dynamic filtering
  (Sonnet 4.6/5, Opus 4.6+) — it runs search via code execution and returns a different response shape,
  so re-run the step-5 smoke test after enabling. A model swap alone does **not** require touching this.

## Notes

- `retry: false` — a failed lookup lands in the Sidekiq **dead set** (each retry is a paid API call). Triage
  manually; re-trigger via Recalculate rather than requeueing blindly.
- Search is **restricted to the allow-list by default** (see Tuning). If step-5 lookups come back
  `not_found` more than expected, first suspect the allow-list, not the model — widen it or set
  `PROPERTY_FACTS_ALLOWED_DOMAINS` empty to confirm.
- A lookup can now resolve to **Estimated** (status id 5), not just Complete: facts were found but the
  square footage / lot size were inferred from comparable neighbors (typical for off-market/unindexed
  homes whose own record isn't searchable). Ops sees "Estimated (from comps)" and should verify. A
  property whose size came from its MLS Listing stays **Complete** — the estimate flag only applies when
  the AI's comp-derived size is the resolved value.
- Facts are best-effort estimates; override + recalculate exist by design. `edited_*` always wins over `ai_*`.
- **No backfill in this deploy.** Existing properties stay NULL until recalculated on demand or (flag ON)
  auto-looked-up on their next new order. Backfilling every property would be a large paid batch — out of scope.
