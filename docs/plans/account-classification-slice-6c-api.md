# Account classification — slice 6c-api: the per-host headshot ROI read-out and the owner-only KPIs endpoint

**Repo:** `insgt-api`. Platform repo for the write-back only. No insgt-ops change; 6c-ops gets its own prompt once event 6 is curl-verified.
**Contract:** `docs/architecture/account-classification.md` v12 — §5.5 (`:1129–1226`; the ROI paragraph `:1220–1226`), §9 (`:1513`, `:1518–1519`), §20 (`:1952–1954`: the OQ10 wording and the endpoint wait for 6c's write-back). Plan `docs/plans/account-classification-slice-6.md` — G17, G20 (the API half), OQ5, OQ10, Q17; spec plan `:321–325` and `:352`; traps `:499–501`; event 6 verification `:457`. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.

## Scope

1. §5.5 last paragraph, G17 — `HeadshotHostRoi` (`app/services/headshot_host_roi.rb`, `.call` → rows and totals), reading `EventAttribution.credit_rows_sql` (`app/services/event_attribution.rb:134`) and nothing else for the derivation.
2. G17 — `marketing_events:host_roi` in `lib/tasks/marketing_events.rake`, beside `audit_hosts`, printing the service; its document `docs/architecture/headshot-host-roi-<date>.md` from the production run.
3. G20, OQ5 — `KpisController#headshot_hosts`, the collection route under `resources :kpis` (`config/routes.rb:112–119`), `app/views/kpis/headshot_hosts.json.jbuilder`, `spec/requests/kpis_headshot_hosts_spec.rb`.
4. Contract spec — a `headshot host ROI (§5.5)` block in `spec/architecture/account_classification_spec.rb` **before `SQL composition`, now at `:761`** (the plan's `:674` predates 6b's block at `:674–759`).
5. Write-back — the v13 amendment (§5.5's last paragraph worded to OQ10's three rules and the endpoint; §9 rows), the codebase notes rows at `:73–77`, the runbook (gap 6), the ROI document.

## Out of scope — do not touch

1. `EventAttribution`'s rules, `plan`, `apply!`, `call`, the memo task, the nightly hook, and every existing column, CTE and `ORDER BY` of `credit_rows_sql`. Gap 1 may add columns; every 6b example must pass unchanged.
2. 6c-ops and its release. **It is not 9.66.0**: insgt-ops 897a7b80 took 9.66.0 (tag `v9.66.0`) on 2026-10-08. It is 9.67.0 or whatever is next. v13 corrects the plan's `:9, :25, :280, :401` and §9 `:1519`.
3. `AccountReport.headshot_event_report` (`lib/account_report.rb:8`), `OrderHeadshot` stamping the event date, `MarketingSourceMetricsService` and the other KPI actions.
4. Any data change to sources, hosts or events.

## Prerequisites

- 6a-ii in production: every event carries its host (§9 `:1515`; `marketing_events:audit_hosts` section 6).
- 6b merged: `credit_rows_sql` public at `event_attribution.rb:134`, `derivation` at `:256–265`, `has_dated_event_order` at `:208–210`, `lifetime_value_cents` at `:216`; fixtures `spec/support/event_orders.rb`; factories `spec/factories/{marketing_events,organizations}.rb`.
- 6b's **write** is not a prerequisite (§5.5 `:1220`). `master` = `heroku/master` = b05f74c2 (v648) at the time of writing.

## Gaps the plan must pin

1. **Where does an uncredited attendee's host come from?** `credit_rows_sql` takes `host_organization_id` from the *crediting* order (`:198–228`), so it is NULL for `skip_no_paid_listing` and `skip_after_buying`. OQ10 puts those accounts under their latest event order's host. The contract says there is no second derivation (§5.5 `:1225–1226`). The expected answer is additive columns (latest dated event order's event and host) from a CTE over the existing `event_orders`. Name the alternative and why it was rejected.
2. **Who is an attendee?** `has_dated_event_order` true. An account with only undelivered event orders (`skip_undated_event_order`) is not one (G9). Re-measure the total against the production memo's funnel (2,343 with an event order, 2026-10-14) less undated-only accounts.
3. **The `derivation` → column map.** Is a convert `write`, `skip_host_no_source` and `skip_latest_unhosted` under the crediting host? Is an already-customer `skip_after_buying` under the latest host? Is not-yet-bought `skip_no_paid_listing` under the latest host? Sourced rows count the same as unsourced ones. Converts never come from `action` or `accounts.marketing_source_id`.
4. **What does `events` count?** Use `MarketingEventAudit.events_by_host`'s definition (`marketing_events.rake:129–141`: all statuses, by `organization_id`), or active only?
5. **The no-host row.** Its label and position, the `conversionPercentage` rounding, and whether an empty no-host row renders.
6. **Runbook.** Is it a new `docs/runbooks/deploy-account-classification-6-roi.md` (events 6 and 7), or event 6 appended to the attribution runbook, which is titled "events 4 and 5" and marked Deployed?
7. **The read-out header on a dyno** prints `insgt-api unknown` (no `.git` on the slug; §20). Does it print the release number instead, or does the runbook record it beside the header?

## Traps for the review

- A second CTE chain over orders, logs or `Order.shoot_date_sql`. Everything comes through `credit_rows_sql`.
- Attendees counted per event or per token, an account under two hosts, or a totals row that differs from the distinct attendee count.
- An after-buyer counted as a convert. Converts found via `marketing_source_id` or `action`, or sourced accounts dropped.
- Undated-only accounts counted as attendees. `account_type <> 7` anywhere.
- The endpoint reachable by any role but owner, or re-deriving anything the service returns.
- A changed existing `credit_rows_sql` column, CTE or ordering, or any edited 6b example.
- `HeadshotHostRoi` referenced at rake file scope (`marketing_events.rake:20–22`).
- The contract block anywhere but immediately before `SQL composition`.

## Commit sketch

Dan commits. Branch `feat/headshot-host-roi`.

1. `feat: carry the latest event order on the attribution rows`, only if gap 1 lands there.
2. `feat: report headshot event ROI per host` (service and spec).
3. `feat: read out headshot event ROI per host` (task and spec).
4. `feat: serve headshot host ROI on the KPIs endpoint` (action, route, jbuilder, request spec).
5. `test: pin the headshot ROI rules in the contract spec`.

Platform repo: the runbook before event 6; after it, the ROI document, `docs: amend account classification to v13 for the headshot ROI`, and `docs: update the classification codebase notes for the headshot ROI`.

## Gates

After plan; at the end, before event 6 (the slice-cut row: "read-out → after plan, at the end; new endpoint → after plan"). Post-deploy verification is the plan's event 6 paragraph (`:457`), with expectations re-reasoned against the day's sync before the code exists.

## Reference pattern

- Service: `app/services/event_attribution.rb` (the header's voice, raw SQL, `select_all`).
- Task: `lib/tasks/marketing_events.rake:172–185`. Its spec: `spec/lib/tasks/marketing_events_rake_spec.rb:1–45`.
- Endpoint: `KpisController#marketing_sources` (`kpis_controller.rb:15–21`), `app/views/kpis/marketing_sources.json.jbuilder`, `spec/requests/kpis_marketing_sources_spec.rb`.
- Service spec: `spec/services/event_attribution_spec.rb:1–60`.

## Plan (approved by Dan 2026-10-15)

Surveyed against insgt-api `master` ee0c146b (`heroku/master` b05f74c2) and the dev restore (latest order 2026-10-14 04:41 UTC). Gaps 1 and 4 approved as proposed; the pending-release framing and the event 6 relationships are Dan's amendments of the same day.

### Gaps pinned

1. **Uncredited attendees' host.** One CTE appended to `ctes_sql`, `latest_event_order`: `DISTINCT ON (account_id)` over the existing `event_orders` where `shoot_date IS NOT NULL`, ordered `shoot_date DESC, created_at DESC, id DESC` (the crediting tiebreak). Additive columns `latest_order_id`, `latest_event_id`, `latest_host_organization_id`, and `pending_release_event_ids` (the events of the account's undelivered event orders, for the read-out's breakdown). No existing column, CTE or `ORDER BY` changes. **Rejected:** a query over orders in `HeadshotHostRoi` (a second derivation, §5.5 `:1225–1226`, whose dating or tiebreak could drift); a COALESCEd "ROI host" column in `credit_rows_sql` (puts an ROI rule in the attribution service — the SQL carries facts, `HeadshotHostRoi` applies OQ10).
2. **Attendee** = `has_dated_event_order`. An account whose only event orders are undelivered is a **pending release**: it attended, its media is held back from release (standing practice, a few days after most events, for marketing reasons), and it is counted once delivered. G9's dated test is unchanged — until the order is delivered the agent has received nothing, so nothing can be credited. The nightly `metrics:recompute` run picks these accounts up on the first run after release with no action; there is no release hook. Measured on the restore: 2,343 rows, 11 pending-release accounts (10 on event 1433 PSAR, created 2026-10-13; 1 on event 1333 SDAR, created 2026-08-07), so 2,332 attendees. All 11 have no paid listing and no source. The memo's "0" counted undelivered orders *before buying*; these 11 have never bought. v13 records that as the correction.
3. **Derivation → column.** A crediting order exists (`write`, `skip_host_no_source`, `skip_latest_unhosted`) → the crediting host (NULL → no host), **convert**. `skip_after_buying` → the latest delivered event order's host, **already customer**. `skip_no_paid_listing` with a delivered order → the latest host, attendee only. Sourced rows count the same as unsourced ones. Converts come from `crediting_order_id` only, never `action` or `accounts.marketing_source_id`.
4. **`events`** = every event by `organization_id`, any status (`events_by_host`, `marketing_events.rake:129–141`; Q15). `MarketingEventAudit` lives in a rake file the web process never loads, so the service owns the count and the read-out prints the service.
5. **No-host row.** Label `No host`, a service constant; always last; always present, zeros included. Rows ordered attendees DESC, name, id. `conversion_percentage` = converts / attendees × 100, `round(1)` (as `MarketingSourceMetricsService`), `nil` when attendees is 0. Converts' lifetime value is the sum of the non-NULL `lifetime_value_cents`. Hosts with events and no attendees render with zeros.
6. **Runbook:** new `docs/runbooks/deploy-account-classification-6-roi.md`, events 6 and 7.
7. **Header:** the git sha or `unknown`, as the memo prints; the runbook records the release number beside it (§20 `:1988`). No `HEROKU_RELEASE_VERSION` read: nothing in the repo reads dyno metadata, and it is not known to be enabled.

### Point in time

The table is a point-in-time read, and pending releases are the usual reason its numbers move between runs. An attendee-only account with a delivered order under host A and a pending order under host B sits under A until B's order releases, then moves to B. That is correct under OQ10: the host is that of the latest event order the agent has received. On the restore, 11651 (delivered SDAR event 1069, pending PSAR event 1433) is under SDAR and moves to PSAR on 1433's release; 3076 (pending 1433, latest delivered also PSAR) does not move.

### Units

- `HeadshotHostRoi.call` → `{ rows:, totals: }`. Row: `organization_id`, `name`, `source_key`, `source_name`, `events`, `attendees`, `converts`, `conversion_percentage`, `already_customers`, `converts_lifetime_value_cents`. Totals: `attendees`, `converts`, `already_customers`, `converts_lifetime_value_cents`, `pending_release_accounts`, `pending_releases` (per event: `event_id`, host name, accounts with a pending order, of which not yet attendees), `totals_match` (row attendees sum = distinct attendees). OQ10 applied in Ruby over `EventAttribution.plan.rows`; one raw SQL read of `marketing_events` × `organizations` × `marketing_sources` for names, sources and event counts.
- `marketing_events:host_roi` prints Markdown (header, rules, the table, totals, the totals check, pending releases by event: "12 on event 1433 (PSAR), 10 not yet attendees"), so the production run pastes into `docs/architecture/headshot-host-roi-<date>.md`. `HeadshotHostRoi` is named only inside the task body.
- `KpisController#headshot_hosts` in `marketing_sources`' shape; the jbuilder maps fields only. Metadata: `attendees`, `converts`, `alreadyCustomers`, `convertsLifetimeValueCents`, `pendingReleaseAccounts`, `totalsMatch`. A non-owner gets **401** (`application_controller.rb:216–220`), not 403.

### Event 6 verification — relationships, computed on the day

Fixed counts go stale as soon as 1433 releases, so event 6 checks relationships read from production at verification time:

1. Distinct attendees (`metadata.attendees`) = the memo funnel's "active, not internal, with an active event order" − `pendingReleaseAccounts`, both read at verification; the rows' attendees sum to it; `totalsMatch` true.
2. A release of accounts with no paid listing leaves total converts and already customers unchanged and raises attendee-only by the released count. Restore baseline: converts 203, already customers 151 (M7a's 149 + 2 sourced), attendee-only 1,978.
3. 1433's release, pre-computed: PSAR attendees +11 (10 new + 11651 from SDAR), SDAR −1, total attendees +10, converts unchanged everywhere. If 1333's order also releases, SDAR +1 and the total +1.
4. Converts per association host, lower bounds only (6b's writes; converts include the already-sourced): NSDCR ≥ 70, PSAR ≥ 13, SDAR ≥ 11. Restore values 71 / 14 / 12.
5. The no-host row last: 10 events, 9 converts (the 9 `skip_latest_unhosted`), 3 already customers, 51 attendees. 46 rows (45 hosts + no host). Admin, scheduler and photographer → 401. The owner's `data` equals the read-out's table.
