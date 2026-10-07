# Runbook: Account Classification Slice 6 — Event Hosts Deploy (events 1, 2 and 3)

**Last updated:** 2026-10-07
**Repos:** insgt-api (events 1 and 2), insgt-ops (event 3)
**Estimated duration:** ~10 min for event 1 plus the map (hours of reading, not deploying); ~15 min for event 2; ~20 min for event 3
**Status:** Event 1 **deployed 2026-10-07**; production read-out at 12:30:10 UTC. Event 2 **deployed 2026-10-07**; `db:migrate` at 14:45:27 UTC, invariants 1–7, 9 and 10 passed (8 not run separately). Event 3 (insgt-ops 9.65.0) **not yet built**.

## Summary

Ships slice 6a of `docs/architecture/account-classification.md` §3.5 (plan:
`docs/plans/account-classification-slice-6.md`, sub-slices 6a-i, 6a-ii, 6a-ops): every headshot
event gets a **host organization**, and the three association hosts with an event source get that
source. Nothing here writes an account; the attribution that does is slice 6b, with its own runbook.

- **Event 1** (insgt-api, three commits): the ninth organization type `association: 9`; the two
  nullable reference columns `marketing_events.organization_id` and
  `organizations.marketing_source_id`, each with a concurrent index and a NOT VALID foreign key; the
  read-out `rake marketing_events:audit_hosts`. Nothing reads the columns. The read-out is run in
  production, and the host map is written from its output.
- **The map** is `docs/architecture/marketing-event-host-audit-2026-10-07.md`: the production run,
  and a host for each of the 196 events, settled by Dan. Its `MAP_CUTOFF` is the run's timestamp.
- **Event 2** (insgt-api, three commits): migration `20261007120000` transcribes the map — creates
  14 organizations (PSAR, NSDCR, SDAR, YPN as associations; ten brokerage, lender and agent-team
  hosts), sets 186 events' hosts, gives PSAR, NSDCR and SDAR their sources — and `20261007120001`
  validates both foreign keys. The marketing-event API accepts and renders `organizationId` and
  `organizationName`; the organization payload renders `marketingSourceId` and
  `marketingSourceName` to admin and scheduler only.
- **Event 3** (insgt-ops 9.65.0): a required host picker on both event forms ("Hosted by Insight
  Photos" stored as NULL), and the ninth type in `OrganizationTypes`.

**What moves for a human.** Events 1 and 2: nothing in the product — the marketing-source KPI does
not move, because no account is written. Event 3: schedulers must choose a host on every new event,
and existing events show theirs.

## Where the commands run

`heroku` runs **on the host**, from `apps/insgt-api`; the devcontainer has no `heroku` CLI. A
one-off dyno's filesystem is discarded when it exits, so every capture is a redirect of its stdout.
Production has **no release phase** (Procfile): `db:migrate` is a hand step after each push.

## Deploy order and the windows

**Events 1 and 2 have no window.** Event 1 is additive and nullable, and no model, helper or
controller reads the columns until event 2. Event 2 adds the readers of columns that already exist,
so new code before the migrate renders NULL hosts, and old code ignores the populated columns.

**Order: event 1 → production read-out → the map → event 2 → event 3**, each strictly after the
previous. The read-out ships in event 1 because `heroku run` executes the deployed slug: the map
cannot be written from production until the task is deployed.

**The window between events 2 and 3.** Ops 9.64.0 cannot send a host, so an event created then is
stored with a NULL host — "hosted by Insight Photos" by §3.5's definition, whether or not that is
true. The read-out lists those under "Unmapped since the cutoff"; step 9 works through them.

**Event 3 depends on event 2.** 9.65.0 against an API that does not permit `organization_id` would
drop the host silently on create and block every edit save (a required field with no value). If
both must be rolled back, roll ops back first.

## Prerequisites

- [x] Event 1: `feat/account-classification-slice-6-hosts` (0e71d2b, 53a6108, a85b694) merged to
      `master` (8f1f5dc); two review rounds closed with no blocker; `bundle exec rspec` 1,874
      examples, 0 failures
- [x] The map written and committed (platform `bc28471`), with Dan's decisions for every event
- [x] Event 2: `feat/account-classification-slice-6-hosts` (1a1c7fb, 9d76b32, 0f4d286) merged; two
      review rounds closed with no blocker and two nits declined (below); `bundle exec rspec`
      1,897 examples, 0 failures
- [x] Migrations 3 and 4 proven on the dev restore: a red run naming every planted break and
      writing nothing; a green run; the cutoff proven in both directions; the scoped `down` keeping
      a hand-changed host, a post-cutoff host and an unrelated source; a re-run reusing the
      organizations it created
- [ ] Event 3: `feat/marketing-event-host` reviewed (`predeploy-review-angular`), `ng build` clean,
      `package.json` at 9.65.0, on a clean `main`

## Steps — event 1

### 1. Deploy code

```bash
git push heroku master
heroku run rake db:migrate -a insgtapi
heroku run rake db:migrate:status -a insgtapi | tail -3     # 20261006120000 and 20261006120001 up
```

Both migrations build their index concurrently and are safe to re-run after a partial failure.

### 2. The production read-out — then STOP for the map

```bash
heroku run --no-tty --exit-code rake marketing_events:audit_hosts -a insgtapi > audit-prod.txt
```

Compare with the dev run line for line from line 4 on. On 2026-10-07 the two were identical: 196
events, none created since the restore. The line `MAP_CUTOFF for this run: …` is migration 3's
cutoff. **STOP**: the map is written from this file (OQ3, OQ4, OQ11) and committed before event 2's
migration is written.

## Steps — event 2

### 3. Deploy code and migrate

```bash
git push heroku master
heroku run rake db:migrate -a insgtapi
```

Migration 3 checks the whole map before writing anything and reports **every** problem in one
error; a raise rolls back everything, created organizations included. `[strong_migrations] DANGER:
No lock timeout set` prints before the foreign-key validation; on these tables it took 7 ms
(follow-on: the repo sets no migration lock timeout).

### 4. The read-out with the cutoff

```bash
heroku run --no-tty --exit-code rake marketing_events:audit_hosts MAP_CUTOFF=2026-10-07T12:30:10.007557Z -a insgtapi
```

Section 6 must equal the audit document's §3.4: PSAR 55, NSDCR 53, SDAR 22, YPN 1, 41 other hosts
summing to 55, no host 10, plus any event listed under "Unmapped since the cutoff". On 2026-10-07:
exactly that, and **0** unmapped.

### 5. Invariants

```bash
heroku run --no-tty rails console -a insgtapi < event2_invariants.rb   # read-only; first line sets the session read-only
```

| # | Check | Expected | 2026-10-07 |
| :-- | :-- | :-- | :-- |
| 1 | association organizations | 4 | pass |
| 2 | organizations with a source | NSDCR `nsdcr_event`, PSAR `psar_event`, SDAR `sdar_event` | pass |
| 3 | events with no host | 10 + the unmapped list | pass |
| 4 | events by host (step 4) | the audit document's §3.4 | pass |
| 5 | `GET /marketing_events/1137` as scheduler; `/14` | PSAR; null | pass |
| 6 | `PUT /marketing_events/1137` with `organizationId: null`, then back; a bogus id | both save; 422 | pass |
| 7 | `MarketingSourceMetricsService.call[:metadata]` | unchanged: no account written | pass |
| 8 | ops 9.64.0 events pages | unchanged; the old client ignores the new keys | not run separately |
| 9 | `GET /marketing_events?per_page=25` | one organizations query (router log) | pass |
| 10 | `GET /organizations/<PSAR>` as scheduler; an agent's `GET /users/self?includes=broker` (`API-Version: 2021-06-29`) | `marketingSourceId` = `psar_event`'s public id, "PSAR event"; neither key for the agent | pass |

Production ids for reference: PSAR 3405, NSDCR 3406, SDAR 3407, YPN 3408; the ten others
3409–3418.

## Steps — event 3 (insgt-ops 9.65.0)

### 6. Release

```bash
git status                      # clean main
git tag v9.65.0 && npm run deploy:prod
```

### 7. On the site

- Both forms show the host picker: the order page's create block (headshot-event orders) and
  `/marketing-events/new`.
- **Save without a choice** toasts and sends nothing.
- **Hosted by Insight Photos** sends `organizationId: null` (network tab).
- An existing event's edit page shows its host; an Insight event shows the Insight option.
- The organizations page lists the four associations with type "Association".

### 8. Re-run the read-out

The step 4 command. Section 6 is unchanged apart from any host set since.

### 9. Work through "Unmapped since the cutoff"

For each event listed, set its host from the ops edit page, then re-run step 4 until the list is
**0** or holds only events that really were hosted by Insight Photos. 6b's dry-run memo repeats the
list, so anything left here is visible again before the first attribution write.

## Rollback

### Code

```bash
heroku rollback --app insgtapi
```

Leaves both columns and their values in place, which is correct: old code ignores them. If ops
9.65.0 is live, **roll ops back first** (redeploy the previous tag), for the reason under "Deploy
order".

### Data (only if ever wanted)

```bash
heroku run rake db:migrate:down VERSION=20261007120001 -a insgtapi   # a no-op; Postgres cannot un-validate
heroku run rake db:migrate:down VERSION=20261007120000 -a insgtapi
```

`down` clears only what `up` wrote and is still there: mapped events still carrying their mapped
host, and the three hosts still carrying their mapped source. Hosts schedulers set from ops since
survive. The 14 organizations stay: soft-delete is the repo's only delete, and ops may have edited
them. Proven on the dev restore on 2026-10-07.

## Deferred, with reasons

- **Two round-two review nits, declined by Dan on 2026-10-07.** The final check does not assert NULL
  on the 45 unsourced hosts, and `down` re-resolves hosts by name and type rather than by the row
  `up` used. Both need a write to `organizations.marketing_source_id`, which has no path outside a
  migration.
- **`GET /marketing_event_imports` returns a 500** for any non-empty table: `ApiSearch#query`
  applies `DISTINCT`, and Postgres has no equality operator for the table's two `json` columns.
  Pre-existing; ops has no client; legacy (plan, out of scope 9). Follow-on.
- **No migration lock timeout** (step 3). Follow-on before a migration touches a large table.

## Deploy log

| Event | Date | What | Result |
| :-- | :-- | :-- | :-- |
| 1 | 2026-10-07 | insgt-api `master` 8f1f5dc; two reference migrations; read-out at 12:30:10.007557 UTC | 196 events, identical to the restore |
| map | 2026-10-07 | platform `bc28471`, the audit document | 196 events mapped once each |
| 2 | 2026-10-07 | insgt-api, backfill and FK validation migrated at 14:45:27 UTC | 186 hosted, 10 no host, 0 unmapped; invariants 1–7, 9, 10 pass |
| 3 | — | insgt-ops 9.65.0 | not yet built |
