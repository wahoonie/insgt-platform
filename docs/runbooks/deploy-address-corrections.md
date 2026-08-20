# Runbook: Property Address Corrections Deploy

**Last updated:** 2026-07-28
**Repo:** insgt-api + insgt-ops
**Estimated duration:** ~20 min
**Status:** Deployed 2026-07-29

## Summary

Makes an address edit a **correction, not a relocation**. Agents give us wrong addresses constantly;
the physical job does not move, so the fix now propagates in place to **every order on that
`properties` row belonging to the initiating order's account** — parent, children, unrelated
siblings, completed orders. The API forks to a separate row only when a **different account** has an
active order on it, and in that case it repoints the initiating account's orders itself.

This lands on top of the property de-duplication in the same branch (`PropertiesController#create`
reuses an existing row at the same address), which is what makes rows shared by reference in the
first place. The previous copy-on-write guard forked as soon as a second order appeared, which
stranded a parent's children on the typo being corrected.

**Also riding along:**

- `Order#possible_parents` and the `sameAddress` order-index param now match on **address** rather
  than the exact `property_id` FK, so the Ops "add parent" lookup finds siblings that sit on
  different rows. New opt-in `excludeCanceled` param on `GET /orders`.
- A concurrent partial index on the six address columns backing `Property.matching_address`.
- **Geocoding is now conditional** (`Property#geocode_needed?`). It used to fire a live Google
  request on *every* `Property` save; it now fires only on create, on an address-column change, or
  on an explicit force. See the verification step — this is the change most likely to surprise.
- The Ops **"Force Geocoding?"** checkbox works for the first time. It has been inert since it was
  added: the param arrives nested under `property` and underscored, and the controller only ever
  looked for a top-level `forceGeocoding`.

**No backfill, no new env vars, no Sidekiq changes.**

## Prerequisites

- [X] `fix/parent-orders` committed, merged to `master`, suite green (insgt-api **and** insgt-ops)
- [ ] `heroku` git remote reachable (`git fetch heroku` — this failed on auth during review; confirm
      what is actually live before assuming `heroku/master` is the prod ref)
- [ ] No active deploy in flight
- [ ] Ops build ready to ship **immediately after** the API — see the ordering note below

### Deploy order is not optional: API first, then Ops

The two are not symmetrically compatible, so do not reverse this.

| Order | Effect |
|---|---|
| **API → Ops** (correct) | During the window, old Ops sends no `orderId`, so an address edit on a row shared by two accounts returns **422** ("must be made from an order"). Loud, narrow, single-account rows unaffected. |
| **Ops → API** (do not) | New Ops stopped repointing the order client-side because the server now owns it. Against the old API a fork returns a new property id that **nobody applies** — the order silently stays on the stale row and the edit appears to do nothing. |

The failure mode of getting it backwards is silent data divergence, not an error. Keep the window
between the two deploys short.

Sizing the window: as of 2026-07-28, **333 of 14,660** order-backed property rows (2.27%) are shared
across two or more accounts — so the 422 is reachable but uncommon. Re-check before deploying:

```bash
heroku run rails runner 'c = Order.active.where.not(property_id: nil).group(:property_id).distinct.count(:account_id); puts "#{c.count { |_, n| n > 1 }} of #{c.size}"' -a insgtapi
```

## Steps

### 1. Deploy API code

```bash
heroku pg:backups:capture --app insgtapi
git push heroku master
```

### 2. Run the schema migration

**No release phase exists in the `Procfile`** — migrations do not run automatically on deploy. This
one must be run by hand.

```bash
heroku run rake db:migrate -a insgtapi
```

Adds `index_properties_on_address_components` — a partial (`status_type = 1`), six-column b-tree
built with `algorithm: :concurrently`. `properties` is ~23k rows, so this is seconds, and it takes no
write lock.

**Code-first is correct here and there is no two-phase requirement**: nothing in the code needs the
index to exist. It is purely a planner optimization for `Property.matching_address`, which is
correct (just slower) without it. Running the migration before or after the code push both work.

**Verify:**

```bash
heroku run rails db:migrate:status -a insgtapi        # 20260727120000 shows up
```

**If it fails, just re-run it.** The migration drops any leftover index under that name before
recreating it, so a failed concurrent build heals itself. (Do *not* reach for a bare
`DROP INDEX CONCURRENTLY` — that manual step is no longer needed.)

### 2b. Break the parent-chain loops

```bash
heroku run rake orders:repair_parent_cycles DRY_RUN=true -a insgtapi   # preview first
heroku run rake orders:repair_parent_cycles -a insgtapi
```

Two orders in production name each other as parent (`13232↔13233`, `13546↔13547`, both from 2020).
`Order#parent_must_not_create_a_cycle` now prevents new ones, but it is gated on the `parent_id`
change so existing rows stay editable — this task is what clears what is already stored.

Expect exactly two loops. In each, the task detaches the order with `parent_pays = false` (the one
that pays for itself, i.e. the root of that checkout group), leaving the parent-paid add-on still
parented to it. **Multi-level chains are legitimate and must not change** — a child being a parent is
how one checkout groups several orders. Verify the count of genuine grandchildren is unaffected:

```bash
heroku run rails runner 'a = Order.active; d = a.where.not(parent_id: nil).where(parent_id: a.where.not(parent_id: nil).select(:id)); puts "cycles=#{Order.parent_cycles.size} multi_level=#{d.count}"' -a insgtapi
```

`cycles=0`, and `multi_level` should drop by exactly 4 (the loop members, which the query counted as
grandchildren) and no further.

### 3. Deploy Ops (insgt-ops)

Build prod → upload to S3 → invalidate CloudFront (manual pipeline). Follow the operations
deployment instructions. Ship this **directly after** step 2 — see the ordering table above.

### 4. Smoke-test both branches on a real order

The whole feature is one decision, so test both sides of it.

**Same account (in place).** Find a parent order with children, open Edit Order Property from a
**child**, change the street, save.

- Expect: no new `properties` row, and the parent *and both children* show the corrected address.
- Network tab: `addressCorrection: { forked: false, repointedOrderIds: [] }`.

**Cross account (fork).** Find a `properties` row backed by orders from two different accounts, then
correct the address from one of them.

```bash
heroku run rails runner 'ids = Order.active.where.not(property_id: nil).group(:property_id).distinct.count(:account_id).select { |_, c| c > 1 }.keys.first(3); puts ids.inspect' -a insgtapi
```

- Expect: a new row; every order of the *initiating* account moves to it; the other account's orders
  stay on the original address, which is unchanged.
- Network tab: `forked: true`, and `repointedOrderIds` lists exactly the moved orders.

### 5. Confirm geocoding still fires where it should

This is the highest-risk behavioral change in the deploy — it removes a side effect that ran on
every save.

- Edit a property's **street** → coordinates refresh (Google request in the logs).
- Edit only **facts** (square footage / commercial) → **no** geocoder request. This is the intended
  saving; it is also the regression to watch for if anything downstream was quietly relying on the
  old unconditional geocode to backfill missing lat/lng.
- Tick **"Force Geocoding?"** and save without touching the address → coordinates refresh. This path
  has never worked before, so it is genuinely new behavior rather than a regression check.

## Verification

- [ ] `db:migrate:status` shows `20260727120000` as `up`; index present and valid
- [ ] `orders:repair_parent_cycles` reports 0 remaining; multi-level chains unchanged (step 2b)
- [ ] Same-account correction: parent + children all updated, no new row, `forked: false`
- [ ] Cross-account correction: forked, initiating account's orders moved, other account untouched
- [ ] Ops **Remove property** still detaches (this path was restructured — see Notes)
- [ ] Editing a property from the **Organization** edit screen still saves
- [ ] Editing a property from the **Listing** edit screen still saves
- [ ] Scheduler "add parent" lookup returns siblings at the same address on different rows
- [ ] Facts-only property edit issues **no** geocoder request; street edit does
- [ ] "Force Geocoding?" refreshes coordinates on an unchanged address
- [ ] No new Sentry errors in last 10 min

## Rollback

```bash
heroku rollback -a insgtapi
```

Then redeploy the previous Ops build to S3 + invalidate CloudFront.

**Roll back both, not just one.** Rolling back Ops alone leaves the strict API facing a client that
cannot send `orderId`, so multi-account rows 422 from the order dialog. Rolling back the API alone
leaves new Ops relying on a server-side repoint that no longer happens — the silent case from the
ordering table.

**Leave the migration in place.** The index is additive and unused by the old code; dropping it buys
nothing and costs another concurrent DDL.

**No data to unwind.** Address corrections are ordinary column updates and `orders.property_id`
repoints. There is no reverse migration for an already-applied correction — if one was applied to
the wrong set of orders, fix it forward from the order that should own the address.

## Notes

- **`PATCH /properties/:id` can return a different `id` than the URL.** That is the fork. Ops rebinds
  to the response body; any other consumer must too. The response now carries an
  `addressCorrection` block (`forked`, `sourcePropertyId`, `repointedOrderIds`) so a client can tell
  what happened and refresh accordingly.
- **New 422 without order context.** An address change on a row shared by 2+ accounts, submitted with
  no `orderId`, is rejected rather than guessed at. The order dialog and the listing edit screen both
  pass `orderId`. The **organization** edit screen has no order to pass, so an office address shared
  with two accounts' orders still 422s there — rare, and the operator can correct it from an order.
- **Organizations do not force a fork.** An office address that also backs orders is normal (an event
  / paparazzi shoot is booked *at* the brokerage), so the org and the order describe the same place
  and a correction propagates to both. Only another *account's* order earns a fork.
- **Ops `remove` was split from `update`.** `remove()` used to route through `update(order, {id: null})`;
  `update()` now short-circuits to a refresh when the order already has a property, which would have
  broken detaching. Worth an explicit click in verification.
- **Completed orders are included.** A correction rewrites the address on delivered orders too, which
  changes their property-website URLs. Accepted trade — a live page showing the wrong address is worse
  than a changed URL.
- **Reviewed and deliberately deferred — `excludeCanceled` filters post-`LIMIT`.**
  `OrderSql#filter_canceled` runs in Ruby *after* the SQL `LIMIT`, and adjusts `total` by only the
  canceled rows on the current page. A paginated consumer therefore gets short pages and a
  `totalCount` that is wrong in both branches (the early return leaves the raw unfiltered total).

  Deferred on purpose for this deploy: the sole caller is the possible-parents lookup at
  `perPage: 10`, one page, no pagination UI — so none of the symptoms surface. The fix also touches
  the shared conditions builder used by every orders query, which wants its own blast radius and its
  own pagination specs rather than riding along here.

  **The trigger that makes this urgent: a second, paginated client adopting `excludeCanceled`.**
  At that point push the exclusion into the WHERE clause so both the `LIMIT` query and the `COUNT`
  see it, then delete `filter_canceled`. The sibling `completed` filter at `OrderQuery` line ~207
  is the exact pattern:
  `options[:where] << ['(order_event_id != ? OR order_event_id IS NULL)', OrderEvent.find_by_tag('canceled').id]`
- **Explicitly out of scope:** re-merging families already split across duplicate `properties` rows.
  Read-side stitching (`Property.same_address_ids`) already makes them behave as one address. A
  physical merge would rewrite tens of thousands of `orders.property_id` / `photos.property_id` rows
  and change published listing URLs with no operator in the loop — it belongs in a separate,
  dry-runnable rake task with a report.



# Notes from deployment

Running rails runner "c = Order.active.where.not(property_id: nil).group(:property_id).distinct.count(:account_id); puts \"#{c.count { |_, n| n > 1 }} of #{c.size}\"" on ⬢ insgtapi... up, run.1763


334 of 14675



heroku run rake orders:repair_parent_cycles DRY_RUN=true -a insgtapi
Running rake orders:repair_parent_cycles DRY_RUN=true on ⬢ insgtapi... up, run.8569
Found 2 parent-chain loop(s).
  loop: 13232(parent=13233, parent_pays=true) -> 13233(parent=13232, parent_pays=false)
    [DRY RUN] would clear parent_id on Order#13233
  loop: 13546(parent=13547, parent_pays=true) -> 13547(parent=13546, parent_pays=false)
    [DRY RUN] would clear parent_id on Order#13547
Would break 2 loop(s); 2 remaining.

heroku run rake orders:repair_parent_cycles -a insgtapi
Running rake orders:repair_parent_cycles on ⬢ insgtapi... up, run.5299
Found 2 parent-chain loop(s).
  loop: 13232(parent=13233, parent_pays=true) -> 13233(parent=13232, parent_pays=false)
    cleared parent_id on Order#13233
  loop: 13546(parent=13547, parent_pays=true) -> 13547(parent=13546, parent_pays=false)
    cleared parent_id on Order#13547
Broke 2 loop(s); 0 remaining.
heroku run rake orders:repair_parent_cycles DRY_RUN=true -a insgtapi
Running rake orders:repair_parent_cycles DRY_RUN=true on ⬢ insgtapi... up, run.7998
No parent-chain loops found.


 heroku run rails runner 'a = Order.active; d = a.where.not(parent_id: nil).where(parent_id: a.where.not(parent_id: nil).select(:id)); puts "cycles=#{Order.parent_cycles.size} multi_level=#{d.count}"' -a insgtapi
Running rails runner "a = Order.active; d = a.where.not(parent_id: nil).where(parent_id: a.where.not(parent_id: nil).select(:id)); puts \"cycles=#{Order.parent_cycles.size} multi_level=#{d.count}\"" on ⬢ insgtapi... up, run.7358
cycles=0 multi_level=35