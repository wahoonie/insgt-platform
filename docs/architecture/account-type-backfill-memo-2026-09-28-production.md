# Account classification — account_type backfill (APPLIED at 2026-09-28T19:52:47.158499Z)

Generated 2026-09-28 19:52 UTC against `d4c7q2h3ed4nvs` (latest order 2026-09-28 19:42 UTC), insgt-api `unknown`. Reproduce: `bin/rails account_classification:backfill_account_type [APPLY=true] [OUT=<memo.md>] [CSV=<rows.csv>]`. Contract: docs/architecture/account-classification.md §4.1.

## Rules

- `internal`: `AccountTypeBackfill::INTERNAL_SEED_ACCOUNT_IDS` (11 ids), written where the row is active and NULL.
- `agent`: an active account with `account_type IS NULL`, an active `accounts_organizations` row to an active organization typed brokerage (2), a qualifying parent (`Order.qualifying_parents`), and not a property-manager candidate — own name or a linked organization's name matching `%property manag%` / `%narpm%`, or `marketing_source_id` = the `narpm` source (id 67, resolved by key inside the statement). Candidates are held out, list (c).
- First match wins, in the order internal, agent. A non-NULL value is never written over. Soft-deleted accounts are untouched. `property_manager` is not backfilled: no rule the schema supports derives it (`organizations:audit_types`).
- The write: `update_all` with `updated_by_id = 1` (User.system) and one batch `updated_at`, in one transaction with two self-checks. The (actor, stamp) pair identifies the batch — the actor alone does not, because console writes already carry `updated_by_id = 1`.

## Population

- Active accounts: 4,144; typed: 33 (agent 17 · property_manager 6 · commercial 1 · internal 9); worklist (NULL): 4,111.
- Seed: 11 ids — 9 already typed, 2 to write, 0 soft-deleted, 0 not found: 2 InsightPhotos internal · 3 Pangurbahn internal · 4 Sally Testerton internal · 5 Dan McTesterson internal · 6 Todd McTesterson internal · 89 Insight Photos Marketing internal · 549 Jose Esqueda **to write** · 885 Dan Harms **to write** · 1534 Test McName internal · 2555 Jack Brown internal · 11589 Rav Test internal.

## Tiers

| Tier | To write | Already typed | Held out |
| :-- | --: | --: | --: |
| internal | 2 | 9 | — |
| agent | 1,418 | 15 | 5 |

Already typed, by value and actor:

- internal seed: internal 9 (user 2: 9)
- agent candidates: agent 13 (user 2: 10 · user 1: 3) · property_manager 2 (user 1: 1 · user 2: 1)

NULL after (planned): 2,691 = 4,111 − 1,418 − 2.

### internal — to write (2)

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 549 Jose Esqueda | — | 0 | 10 | lapsed | $0.00 |
| 885 Dan Harms | — | 0 | 0 | prospect | $0.00 |

### agent — top 15 to write, by rolling_365_parent_count DESC NULLS LAST, id ASC (1,418 in all)

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 88 Tamara Kapa | — | 30 | 227 | active | $54,848.00 |
| 1123 Ray Shay | — | 23 | 153 | active | $36,228.00 |
| 78 Mukesh Jain | — | 20 | 235 | active | $50,931.00 |
| 2730 Nick Foster | — | 18 | 82 | cooling | $22,220.00 |
| 185 Tim & Kristine Skoglin | — | 17 | 142 | active | $33,445.00 |
| 191 Rick McCandless | — | 16 | 126 | active | $28,860.00 |
| 2663 Robert Antoniadis | — | 16 | 171 | active | $71,670.00 |
| 11590 Christina Rounds | — | 16 | 16 | active | $2,750.00 |
| 218 Brian Reifeiss | — | 15 | 65 | active | $26,918.00 |
| 336 Mary Frolander | — | 14 | 125 | active | $31,167.00 |
| 1842 Lee Arnold | — | 13 | 205 | active | $47,310.00 |
| 2845 Alisa  Livesley | — | 13 | 53 | active | $11,715.00 |
| 112 Tyler Snyder | — | 12 | 61 | active | $16,825.00 |
| 139 Deborah Harper | — | 11 | 108 | active | $24,048.00 |
| 2704 Tiffany Weis | — | 10 | 38 | active | $7,045.00 |

### agent — held out, property-manager candidates (5)

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 11510 Colleen McDade | — | 26 | 26 | active | $7,285.00 |
| 11983 Chun Cai | — | 4 | 4 | active | $800.00 |
| 789 Anna Song | — | 3 | 14 | active | $2,460.00 |
| 8209 John Frasca | — | 1 | 2 | active | $360.00 |
| 2191 Susan Miller | — | 0 | 1 | lapsed | $195.00 |

## Review lists — not written

### (a) Brokerage present, no qualifying parent — 14

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 4 Sally Testerton | internal | 0 | 0 | prospect | $0.00 |
| 14 Bobbi Rogers | — | 0 | 0 | prospect | $0.00 |
| 15 Ginny Vitovsky | — | 0 | 0 | prospect | $0.00 |
| 432 Candy Vargas | — | 0 | 0 | prospect | $0.00 |
| 1817 Sharon Fornaciari | — | 0 | 0 | prospect | $0.00 |
| 2006 Laurie Guy | — | 0 | 0 | prospect | $0.00 |
| 2204 Christine Ryan | — | 0 | 0 | prospect | $0.00 |
| 3450 Lisa Ruiz | — | 0 | 0 | prospect | $175.00 |
| 3552 Josh Kniffing | — | 0 | 0 | prospect | $0.00 |
| 11232 Zach Campbell | — | 0 | 0 | prospect | $330.00 |
| 11368 Senthil Nathan | — | 0 | 0 | prospect | $0.00 |
| 12075 Kian Rahmanian | — | 0 | 0 | prospect | $0.00 |
| 12081 Andrew Lehrhoff | — | 0 | 0 | prospect | $0.00 |
| 12082 Kathy Ascher | — | 0 | 0 | prospect | $0.00 |

### (b) Qualifying parents, no brokerage-typed organization — 637 (537 with no organization at all); top 25, the rest in the CSV as review_b unless a tier writes the row or it is also on (c)

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 4513 Tammy Barbee | — | 16 | 17 | active | $3,244.00 |
| 11213 Carlos Ledesma | — | 12 | 17 | active | $5,270.00 |
| 6526 Megan Higginson | — | 7 | 11 | at_risk | $2,540.00 |
| 11575 Lexi Cano | — | 6 | 6 | active | $1,090.00 |
| 11679 Maribel Rodriguez | — | 6 | 6 | active | $1,520.00 |
| 2365 Jaie Rodriguez | — | 5 | 18 | cooling | $4,605.00 |
| 10651 Morris Malakha | — | 4 | 6 | at_risk | $1,080.00 |
| 2675 David Volk | — | 3 | 45 | active | $11,640.00 |
| 2907 Sparky Pond | — | 3 | 11 | active | $1,925.00 |
| 3127 Kendra Penski | — | 2 | 5 | at_risk | $1,030.00 |
| 9958 Kyle Weckesser | — | 2 | 5 | at_risk | $1,870.00 |
| 11186 Shelby Laabs | — | 2 | 2 | cooling | $720.00 |
| 11221 Jorge Morales | — | 2 | 3 | active | $740.00 |
| 11462 Terri Cash | — | 2 | 2 | cooling | $390.00 |
| 11473 Cara Brave | — | 2 | 2 | active | $390.00 |
| 11622 Jim Benson | — | 2 | 2 | cooling | $365.00 |
| 11680 Peter Kies | — | 2 | 2 | at_risk | $545.00 |
| 11881 Courtney Grossman | — | 2 | 2 | cooling | $410.00 |
| 11912 Dan Recob | — | 2 | 2 | cooling | $485.00 |
| 11941 Jaime Chambers | — | 2 | 2 | cooling | $195.00 |
| 12147 Tyler Green | — | 2 | 2 | new | $490.00 |
| 12201 Ivy Kung | — | 2 | 2 | new | $740.00 |
| 12214 Lori Morrissey | — | 2 | 2 | new | $370.00 |
| 385 Lydell Fleming | — | 1 | 21 | at_risk | $6,005.00 |
| 823 Adam Nobert | — | 1 | 1 | cooling | $645.00 |

### (c) Property-manager candidates — classify by hand — 7

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 11510 Colleen McDade | — | 26 | 26 | active | $7,285.00 |
| 11983 Chun Cai | — | 4 | 4 | active | $800.00 |
| 789 Anna Song | — | 3 | 14 | active | $2,460.00 |
| 11912 Dan Recob | — | 2 | 2 | cooling | $485.00 |
| 8209 John Frasca | — | 1 | 2 | active | $360.00 |
| 2191 Susan Miller | — | 0 | 1 | lapsed | $195.00 |
| 11625 NARPM NARPM | — | 0 | 0 | prospect | $0.00 |

### (d) Test-pattern hits not in the seed — review, never written — 2

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 9958 Kyle Weckesser | — | 2 | 5 | at_risk | $1,870.00 |
| 2479 Ana Maria Goodemote | — | 0 | 0 | prospect | $0.00 |

### (e) Agent team or franchise only, with shoots (reading R3, not written) — 12

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 73 Steve Lincoln | — | 0 | 73 | lapsed | $15,413.00 |
| 92 Sandy Eischen | — | 0 | 2 | lapsed | $185.00 |
| 209 Wendy Maze | — | 0 | 4 | lapsed | $660.00 |
| 364 Linda Brent | — | 0 | 3 | lapsed | $495.00 |
| 415 David Oleary | — | 0 | 10 | lapsed | $1,840.00 |
| 526 Ron Scharck | — | 0 | 2 | lapsed | $390.00 |
| 890 Peter Buehrle | — | 0 | 1 | lapsed | $284.00 |
| 1798 Lana Sokolovskiy | — | 0 | 1 | lapsed | $155.00 |
| 1939 Harriet Nemeth | — | 0 | 1 | lapsed | $185.00 |
| 2925 Tanya Brooking | — | 0 | 7 | lapsed | $2,615.00 |
| 2996 Michael Ciavirella | — | 0 | 1 | lapsed | $155.00 |
| 7912 Joanie Moes | — | 0 | 2 | lapsed | $330.00 |

### (f) Typed rows the rules disagree with — 6

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 2104 Dana Clymer | property_manager | 12 | 38 | active | $7,360.00 |
| 2594 Richard Eisendrath | agent | 5 | 34 | active | $11,425.00 |
| 1941 Victor Phan | agent | 3 | 17 | active | $3,380.00 |
| 12209 San Diego City  Property Management | property_manager | 3 | 3 | new | $545.00 |
| 12242 Nora Romero | agent | 1 | 1 | new | $175.00 |
| 12339 Sharon Gandy | agent | 0 | 0 | prospect | $0.00 |

### (g) Prospects with trailing-365 revenue (§4.2 review flag) — 1

| Account | Type | Shoots (365d) | Lifetime shoots | Lifecycle | Lifetime value |
| :-- | :-- | --: | --: | :-- | --: |
| 3068 The Phana Par Group | — | 0 | 0 | prospect | $1,050.00 |

## After

- Applied at 2026-09-28T19:52:47.158499Z by user 1 (User.system). Every written row carries `updated_by_id = 1 AND updated_at = '2026-09-28T19:52:47.158499Z'`.
- Written: internal 2 · agent 1,418
- Self-check 1 (planned = written): OK — internal 2 = 2 · agent 1,418 = 1,418
- Self-check 2 (pre-typed rows unchanged): OK — 33 rows re-read identical
- NULL before 4,111 → after 2,691 (as planned)
- Reversal, if ever wanted, keyed on the pair: `Account.where(updated_by_id: 1, updated_at: '2026-09-28T19:52:47.158499Z').update_all(account_type: nil, updated_at: Time.current)`
