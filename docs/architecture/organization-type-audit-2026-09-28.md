# Organization type audit: `organizations.type_of` and the `accounts_organizations` edge

**Date:** 2026-09-28 · **Contract:** `docs/architecture/account-classification.md` v6 §4.1 ("An organization type audit is a prerequisite of slice 4"), §9 ("Slice 4 blocks on the organization type audit") · **Repo:** `apps/insgt-api` `master` at 25a694c3 (the slice 4a/4b merge, deployed to production 2026-09-28) · **Task:** `rake organizations:audit_types` (`lib/tasks/organizations.rake`, commit e195ae98). Read-only; nothing was persisted.

Evidence conventions: the read-out below is the **production** run, captured on a one-off dyno on 2026-09-28 (`heroku run --no-tty --exit-code rake organizations:audit_types -a insgtapi`, from `docs/runbooks/deploy-account-classification-4-backfill.md` step 3). The survey figures it is compared against come from the 2026-09-14 production sync (`docs/plans/account-classification-slice-4.md`, Appendix A, Q3a–Q3n, Q9a–Q9d) and the 2026-09-28 dev sync (that plan's Phase 0 re-baseline). `file:line` is the insgt-api path unless prefixed. Facts, assumptions and estimates are labelled where they differ.

---

## 1. The four questions

The audit exists to answer four questions before the tiered backfill wrote anything. Each answer is
read off the production run in §3.

**Which `type_of` values are real and populated?** Eight values are declared in `Organization.types`
(`app/models/organization.rb:97–109`, a frozen hash validated as a range, not an enum). Five carry
rows: MLS (8 active), brokerage (643 active, 4 soft-deleted), agent team (33 / 1), franchise
(27 / 1), social media (1 / 1). Three carry **no rows at all**: lender, stager, office. Nothing is
stored outside 1..8. Coverage through an active edge to an active organization: MLS reaches 1,511
active accounts, brokerage 1,452, agent team 28, franchise 7, social media 0.

**What does a blank type mean?** Nothing, structurally: `organizations.type_of` is `NOT NULL`
(`db/schema.rb:820`) and `Organization#set_type!` (`organization.rb:143–145`, `before_validation`)
writes brokerage over any blank, so a blank never reaches the table and a chosen brokerage cannot
be told from a defaulted one. The answerable question is how many brokerages were never chosen.
The upper bound — active brokerages with no url, no email, no logo and no parent, the shape
`User#update_broker`'s free-text branch creates (`user.rb:213–228`) — is **255 of 643**. That is a
bound, not a count: a chosen brokerage may also carry none of those fields.

**Is NARPM affiliation representable?** No. Zero organizations carry NARPM in name, url, email or
logo; zero marketing events are named for NARPM or property management; the only NARPM signals in
the database are one `marketing_sources` row (id 67, key `narpm`, one active account: 11912 Dan
Recob) and one account named "NARPM NARPM" (11625, the organization-proxy account §4.2 describes).
There is no `property_management` organization type and the edge table carries no type or role
(`db/schema.rb:117–126`).

**Can `property_manager` be backfilled by any rule the data supports?** No. The six
property-management-named firms are all typed brokerage (349, 1786, 1951, 3073, 3276, 3342),
each linked to exactly one active account, so `organizations.type_of` cannot carry the fact and
any rule would read a brokerage. The name proxy (own name or linked organization matching
`%property manag%` / `%narpm%`, or the `narpm` source) reaches nine accounts, two of them already
typed by hand, one an organization proxy that §4.2 calls `other`, and six that also satisfy the
`agent` rule. A tier that writes at most six rows and needs a precedence rule the contract does not
state is a review list, not a confidence tier. Decision 3 of 2026-09-15 (the plan's decisions
table) dropped the tier and held those candidates out of the `agent` write; the production run
confirms the premise.

The verdict line the task prints is built from the run's own counts, never pasted, so a production
database that contradicted the survey would have printed a different sentence. It did not:

```
Verdict: property_manager is not derivable from organizations: 0 NARPM organizations, 0 NARPM events, 6 property-management firms typed brokerage, 0 typed otherwise.
```

## 2. Comparison with the survey

| Line | 2026-09-14 sync | 2026-09-28 production | Note |
| :-- | :-- | :-- | :-- |
| Organizations, active / soft-deleted | 710 / 7 | 712 / 7 | two brokerages added |
| Brokerage rows, active | 641 | 643 | |
| Types with no rows | lender, stager, office | same | |
| `type_of` outside 1..8; NULL or 0 | 0; 0 | 0; 0 | |
| NARPM in organizations / events | 0 / 0 | 0 / 0 | the gate |
| Property-management-named firms | 6, all brokerage | 6, all brokerage | same six ids |
| Brokerage coverage (R1) | 1,446 | 1,452 | the `agent` tier's denominator |
| Edges, active / soft-deleted | 3,362 / 1,093 | 3,375 / 1,094 | |
| Duplicate pairs, active / all statuses | 0 / > 0 | 0 / 113 | the survey did not count the second |
| Active edges to a soft-deleted organization | not measured | **13** | §3, finding 1 |
| Accounts by active-link count | 0: 2,577 · 1: 134 · 2: 1,112 · 3: 303 · 4: 10 | 0: 2,580 · 1: 146 · 2: 1,103 · 3: 305 · 4: 10 | drift |
| Parent edges | brokerage→franchise 173 · agent team→brokerage 6 · agent team→franchise 1 | same | |

Nothing on the plan's stop-and-flag list occurred: no NARPM organization, event or edge; no
property-management firm typed other than brokerage.

## 3. Findings, none of them gates

1. **Thirteen active edges point at a soft-deleted organization**, all at organization 15,
   "Solutions Real Estate - Carlsbad", a brokerage soft-deleted 2022-11-17, from thirteen distinct
   active accounts (the VERBOSE run lists them: edges 45, 194, 222, 493, 509, 561, 696, 721, 941,
   943, 945, 1175, 1598). `User#update_broker` soft-deletes the old **edge** when a broker changes
   (`user.rb:201–204`) but nothing soft-deletes edges when the **organization** is deleted, so the
   edge outlives its target. Consistent with the survey's Q3h (each of the thirteen also holds an
   active edge to an active organization, or the survey's two counts would have differed). No
   effect on the backfill: every predicate in it filters `organizations.status_type`, so none of the
   thirteen is a brokerage through that edge. Worth a one-line repair task if the edge table is ever
   given a type (§8 Q7).
2. **255 of 643 active brokerages match the defaulted / free-text shape.** Recorded as the plan's
   accepted risk: the `agent` tier trusts `type_of = 2`, bounded by the shoot condition and the
   hold-out; the residual is an organization-proxy or property-manager account with a mis-typed
   brokerage, real shoots and no name signal, which the worklist and the ops dialog correct.
3. **113 `(account_id, organization_id)` pairs occur more than once across statuses, none twice
   active.** The uniqueness on `AccountsOrganization` is a model validation scoped to active rows
   (`accounts_organization.rb:7`) and the index is not unique (`db/schema.rb:125`); the duplicates
   are the churn `update_broker` leaves behind. Harmless to every reader that filters the edge's
   status; a reader that does not (`AccountQuery#where_organization`, `account_query.rb:271–276`)
   can see one account twice.
4. **"Values with no code path", under both counting rules** (the plan's disagreement 4). By code:
   `grep -rn "type_of" app lib` names only `brokerage` and `mls`, so **six** of the eight values have
   no `app`/`lib` code path outside the hash, or five if `db/migrate/20170214165154_social_media.rb`
   counts. By data: **three** have no rows (lender, stager, office). The contract's "five of the
   eight" was neither count; v7 states both.
5. **insgt-ops carries its own copy of the eight types** (`src/app/shared/models/organization.model.ts:45–56`,
   `src/app/organizations/store/organization.service.ts:112–123`). A finding with no action: the
   two lists agree today, and a ninth value is not being added (§4).

## 4. Recommendation to the accounts-versus-users workstream (§8, Q7)

If property-management affiliation is ever to be derivable, represent it as a **typed edge** on
`accounts_organizations` (or a typed relationship table), not as a ninth `organizations.type_of`
value. The audit's evidence for that shape: the firms that would carry a `property_management`
type are already typed brokerage and linked to their accounts through the same untyped edge every
other brokerage uses; `set_type!` would keep defaulting blanks to brokerage; and the one
affiliation signal that does exist (`marketing_sources` id 67) is a per-account attribution, not an
organization at all. A typed edge also gives the thirteen dangling edges (finding 1) a natural
repair. Until then `property_manager` stays hand-classified, from the backfill's list (c).

## 5. Disposition

The backfill's two tiers stand as decided on 2026-09-15 (plan decisions 3 and 4): `internal` from
the seed, `agent` from a strict brokerage edge plus a qualifying parent, property-manager candidates
held out. `APPLY` ran in production at 2026-09-28 19:52:47 UTC; the memo is
`account-type-backfill-memo-2026-09-28-production.md`.

---

## Appendix — the production read-out, verbatim

```
Organization type audit — 719 organizations (712 active, 7 soft-deleted); 4,144 active accounts
  Types  = Organization.types (app/models/organization.rb): a frozen hash, range-validated, not an enum.
  Linked = active accounts with an active accounts_organizations row to an ACTIVE organization of the type.
  Read-only; nothing is persisted. VERBOSE=true lists ids.

1. Organizations by type
  ID  TYPE           ACTIVE  DELETED  LINKED ACCOUNTS
   1  MLS                 8        0            1,511
   2  Brokerage         643        4            1,452
   3  Lender              0        0                0  [NO ROWS]
   4  Stager              0        0                0  [NO ROWS]
   5  Agent team         33        1               28
   6  Franchise          27        1                7
   7  Social media        1        1                0
   8  Office              0        0                0  [NO ROWS]
  Stored type_of outside Organization.types (1..8): 0

2. What blank means
  type_of IS NULL OR type_of = 0: 0
  Structurally zero: organizations.type_of is NOT NULL (db/schema.rb) and Organization#set_type! writes
  brokerage over any blank before validation, so a chosen brokerage and a defaulted one are the same row.
  Upper bound on defaulted or free-text brokerages (active type 2 with no url, email, logo or parent —
  the shape User#update_broker's name branch creates): 255 of 643

3. NARPM
  Organizations with NARPM in name, url, email or logo: 0
  Marketing events named NARPM or property management: 0
  marketing_sources keyed 'narpm': 1 (67 NARPM → 1 active account)
  Active accounts named NARPM: 1 (11625 NARPM NARPM)

4. Property-management-named organizations (name ILIKE '%property manag%')
  ID     TYPE          STATUS   LINKED  NAME
  349    Brokerage     active        1  Chase Pacific Property Management
  1786   Brokerage     active        1  Aviara Property Management
  1951   Brokerage     active        1  Frasca Realty & Property Management
  3073   Brokerage     active        1  Investment Safe Property Management
  3276   Brokerage     active        1  Kosmix Property Management
  3342   Brokerage     active        1  San Diego City Property Management
  Property-management-named organizations: 6 — 6 typed brokerage, 0 typed otherwise

5. Edges (accounts_organizations)
  Edges by status: active 3,375 · soft-deleted 1,094
  Active edges to a soft-deleted organization: 13
  Duplicate (account_id, organization_id) pairs: active 0 · all statuses 113
  Active accounts by active-link count: 0: 2,580 · 1: 146 · 2: 1,103 · 3: 305 · 4: 10
  Active accounts by linked type set: {}: 2,580 · {1}: 99 · {1,2}: 1,378 · {1,2,5}: 22 · {1,5}: 6 · {1,6}: 6 · {2}: 52 · {6}: 1

6. Parent edges (organizations.parent_id, active children)
  Brokerage → Franchise: 173
  Agent team → Brokerage: 6
  Agent team → Franchise: 1

Verdict: property_manager is not derivable from organizations: 0 NARPM organizations, 0 NARPM events, 6 property-management firms typed brokerage, 0 typed otherwise.
```
