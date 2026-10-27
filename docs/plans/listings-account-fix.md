# Listings: virtual tour agent and account fixes

**Repo:** `insgt-api`, plus `insgt-virtual-tour` only if step 3 takes option B. No migration.
**Status:** step 1 deployed 2026-10-26 in v660 (insgt-api `b51d97ba`, 11:41 -0400). Steps 4 and 5 deployed 2026-10-26 in v661 (`bb732fd7` and `4b840dca`, merge `d37ae0df`, 16:42 -0400); Honeybadger shows no `NoMethodError` after v661 as of 2026-10-27 07:58. Steps 2, 3 and 6 not started.
**Counts:** every count comes from the dev database, which is a production restore, on 2026-10-26. The shared filter and the sweep are under [Queries](#queries).

## Background

`GET /listings/D2GbvGq5/virtual.json` returned a 500, reported to Honeybadger as `85cad4da-3caa-4b24-b68c-5bbfaa9d12b7`:

```
NoMethodError (undefined method '[]=' for nil)
app/models/listing.rb:399:in 'Listing.find_agent_team'
```

`Listing.find_agent_team` decides whose contact details the public virtual tour shows. It reads two references that nothing keeps current. Deactivating a user or an account never clears `listings.user_id` or `listings.account_id`. When either pointed at someone inactive, `Account.select_virtual` returned nil and the builder raised.

| Term | Meaning |
|---|---|
| Servable listing | One that `Listing.find_virtual` can return: listing active and not suppressed, order active, order's account active (`listing.rb:289`). |
| Override | `listings.user_id`. The tour shows that user through an account they own. |
| Main account | `listings.account_id`. The code calls it the "dominant account". |
| Team | The main account, or the order's account when no main account is set. |
| Resolves | `Account.select_virtual` returns a row. That needs the account, an `accounts_users` row and that row's user all active (`account.rb:444`). An active account with no active members does not resolve. |

## Step 1: fall back instead of raising (deployed in v660, `b51d97ba`)

| Change | Where |
|---|---|
| An override that doesn't resolve falls back to the team. | `find_override_agent`, `listing.rb:408` |
| A main account that doesn't resolve falls back to the order's account. | `find_agent_team`, `listing.rb:392` |
| Request spec covering a live override, a dead override, a dead main account, and both dead. The last three fail on the old code with the production errors. | `spec/requests/listing_virtual_agent_spec.rb` |

**Rejected: a status filter on the override's membership lookup.** It changed which row Postgres returned for user 497, described in step 2, and moved 150 working pages to account 58. It rescued none of the 29 departed agents behind the broken listings, because none of them has another active owner membership. The lookup at `listing.rb:411` is unchanged from before the fix, with a comment saying why.

| Verification | Result |
|---|---|
| Override URLs | 464 checked. 102 failed before, 0 fail now. |
| Working override URLs whose shown agent changed | 0 |
| URLs on listings whose main account is inactive | 82 checked across 66 listings, 0 fail. |
| Sweep of every servable URL | 12,393 URLs across 8,615 listings. 27 URLs on 14 listings still fail, in the three shapes covered by steps 3 to 5. |
| Full rspec suite | 2,013 examples, 0 failures |
| Running dev server, order `D2GbvGq5` | 200 |

The 14 leftover listings fail the same way on the old code. Steps 4 and 5 are code that step 1 didn't touch. Step 3 is a listing where the old code had no fallback at all.

**Still open after the merge:** the comment at `listing.rb:385–388` was not reworded. It says the order account is the fallback "because find_virtual only serves a listing whose order account is active". Active does not mean it resolves, as step 3 shows, so the comment must not read as a guarantee. Fix it alongside step 3, which is the step that makes the distinction matter.

**Confirmed in production:** the 2026-10-26 Honeybadger report for `gqX9b42B` (step 4's shape) points at `listing.rb:438`, a line that exists only after this fix. Step 1 is live.

## Step 2: make the override lookup deterministic

`find_override_agent` picks the override user's owner membership with `find_by` and no `ORDER BY` (`listing.rb:411`). Postgres plans it as a sequential scan, so it returns whichever row sits first on disk.

```
Limit  (cost=0.00..64.43 rows=1 width=4)
  ->  Seq Scan on accounts_users  (cost=0.00..128.86 rows=2 width=4)
        Filter: ((user_id = 497) AND (role_id = 5))
```

User 497 owns two active accounts. Account 1642 bought account 58's business, and user 497 was made an owner of 58 at the purchase.

| `accounts_users.id` | Account | Created | Shown on the tours today |
|---|---|---|---|
| 2503 | 1642 | 2018-05-10 | Yes. This is the correct account. |
| 17684 | 58 | 2025-06-05 | No |

All 150 servable listings with this override were ordered by account 58, and none was edited after May 2025. Until June 2025 the override could only resolve to account 1642. The tours show 1642 today only because row 2503 sits first on disk. Postgres writes an updated row in a new place, so any save to row 2503 can move it behind row 17684 and switch all 150 pages to account 58. Production's row order may already differ from the restore's.

**Proposal:** add `.order(:id)` to the lookup, so the oldest owner membership wins. On the dev copy this changes no page. The only other override user with two owner memberships is user 1147, on one listing. Both of that user's accounts are inactive, so the page falls back to the team either way. Once the ordering is in place, the rejected status filter becomes safe to add.

**Open decision:** is "oldest owner membership wins" the rule? It fits an acquisition, where the acquired account's membership is always newer. To answer it, list every user with more than one active owner membership, not only override users, and confirm the oldest is the account each should show. Step 2 is blocked until then.

**Spec trap:** in the test database, insertion order, id order and disk order all agree, so a spec passes without the `ORDER BY`. Insert the higher-id membership first, with explicit ids, so disk order and id order disagree.

If production shows account 58 on those pages today, deploying step 2 switches them to 1642, the intended account.

### Checked, no change needed: organizations on those 150 pages

The organizations block comes from the team, which is account 58 (`inject_organizations`, `listing.rb:632`), while the agent block comes from 1642. Accounts 58 and 1642 carry the same four organizations: brokerage 306, MLS 70, MLS 1 and agent 79. The pages look the same whichever account supplies them.

## Step 3: listings where no account resolves

Four servable listings still raise at `listing.rb:395`, one URL each: 7700, 7740, 7777 and 8585. None has an override or a main account. All four were ordered by account 1467. That account is active, but its only membership, owner user 1541, is deleted. Neither fallback resolves, so `team` is nil. Account 1467's fifth servable listing renders. Its last order was 2024-05-30.

**Open decision:** what should the tour do when no account resolves?

| Option | Repos | Effect |
|---|---|---|
| A. The API returns 204, as it does for a suppressed listing. | `insgt-api` | The tour shows its not-found page. |
| B. Render without an agent block. | Both | The tour reads `@listing[:account][:mls]` and `@listing[:account][:name]` with no guard (`_property_table.html.erb:59`, `_map.html.erb:17`). The tour must ship its guards before the API change. |
| C. Data fix: give account 1467 an active owner, or deactivate it. | None | Deactivating also makes `find_virtual` skip all five listings, which is option A by data. Goes through Dan. |

## Step 4: the second-agent lookup (deployed in v661, `bb732fd7`)

`find_second_agent_team` (`listing.rb:422`) still has both crashes that step 1 removed from the first agent. It sets a name on a nil override at `listing.rb:438`, and reads `team['id']` on a nil team at `listing.rb:441`.

88 servable listings have a second account. Nine fail, on 21 URLs: 4505, 7064, 7637, 8310, 20047, 22193, 25704, 25893 and 25924. All nine fail at `:438`, and all nine have the same shape. The second user's owner membership is on the second account itself, and both the membership and the second account are deleted. The user is deleted too on six of them; on 25704, 25893 and 25924 the user is still active, which changes nothing, because the membership and the account are what `select_virtual` needs. No listing has a dead second override with a live second account, or the reverse.

Production hit this on 2026-10-26: `GET /listings/gqX9b42B/virtual.json` (order 73364, listing 25893) 500ed at `:438`, reported as Honeybadger request `634e7b25-7320-84e6-40cd-8e7aa449b7b0`.

So reusing `find_override_agent` for the second user only moves these crashes to `:441`. They are fixed only by skipping the second agent when the second account doesn't resolve.

**Proposal:** reuse `find_override_agent` for the second user. When the second account doesn't resolve, return nil and have `inject_agent_team_info` (`listing.rb:655`) skip the block. insgt-virtual-tour needs no change. The key is already absent on every listing without a second account, and both views and the payload parser guard on it (`_header.html.erb:14`, `show.html.erb:41`, `insight_photo.rb:128`).

**Built 2026-10-26** on branch `fix/missing-second-agent`, as proposed. Line numbers below are on that branch.

| Change | Where |
|---|---|
| The second user goes through `find_override_agent`, so a dead second override falls back to the second account. | `find_second_agent_team`, `listing.rb:434` |
| A second account that doesn't resolve returns nil, and `inject_agent_team_info` leaves the `second_account` key out. The first agent's fallback chain is untouched. | `listing.rb:432`, `listing.rb:656` |
| Five request examples: live second account, live second override, dead second override, dead second account with no override (the `:441` shape), and the production shape above. The last three fail on the old code at `:438` and `:441`. | `spec/requests/listing_virtual_agent_spec.rb` |

| Verification | Result |
|---|---|
| The nine listings, 21 URLs | All render through `Listing.select_virtual`; none carries a `second_account` key. |
| Full rspec suite | 2,018 examples, 0 failures |
| Sweep of every servable URL | 12,393 URLs across 8,615 listings, 881s. 6 URLs on 5 listings still fail, down from 27 on 14: 7700, 7740, 7777 and 8585 at step 3's line, and 1095 at step 5's. The 21 second-agent URLs are gone. |

## Step 5: unguarded owner read (deployed in v661, `4b840dca`)

`inject_account_info` reads `agent_record.owner.mls_number` (`listing.rb:610`). `Account#owner` returns nil when the account has no active owner row (`account.rb:479`). Commit c6fc2052 on 2026-08-31 guarded the other owner references in this file, but missed this one.

One listing fails here, on 2 URLs: 1095. Its team is account 986, which is active with four active members, but its owner row, user 1041, is deleted. Account 986's last order was 2017-05-30.

**Proposal:** `agent_record.owner&.mls_number`. Check how `components/_agent_detail` in insgt-virtual-tour renders a null `mlsNumber` first.

Production hit this on 2026-10-26: `GET /listings/Z2v6bE2z/virtual.json` (order 4031, listing 1095) 500ed at `:610`, reported as Honeybadger request `8df5d8f7-1a85-0912-bf75-1d321dcebb91`.

**Built 2026-10-26** on the step 4 branch as its second commit, `4b840dca`, as proposed. The tour check passed: `components/_agent_detail.html.erb:21` renders the MLS number only when present, and the pano author line (`application_helper.rb:114`) skips blanks, so no tour change.

| Change | Where |
|---|---|
| `agent_record.owner&.mls_number`, with a comment on why `owner` goes nil while the account still resolves. | `inject_account_info`, `listing.rb:607` |
| Request example: team account active with another active member, owner row deleted. Fails on the old code at `:605`. | `spec/requests/listing_virtual_agent_spec.rb` |

| Verification | Result |
|---|---|
| Order `Z2v6bE2z` through `Listing.select_virtual` | Renders; `mlsNumber` is null. |
| Full rspec suite | 2,019 examples, 0 failures |
| Sweep of every servable URL | 12,393 URLs across 8,615 listings, 838s. 4 URLs on 4 listings still fail: 7700, 7740, 7777 and 8585, all at step 3's line. Nothing else in the sweep raises. |

**Trap:** do not remove user 497's ownership of account 58 as a data fix for step 2. User 497 is account 58's only owner. Six servable listings were ordered by account 58 without an override, and they would start raising on this line.

## Step 6 (optional): clear stale references

81 servable listings have an override that doesn't resolve, and 66 have an inactive main account. After step 1 their pages render the same whether or not the references are cleared, so this is data hygiene, not a fix.

**Open decision:** clear them once, and decide whether deactivating a user or an account should clear its references from now on. Any data change goes through Dan.

## Queries

Every count uses this servable-listing filter, which mirrors `find_virtual`:

```sql
FROM listings
INNER JOIN orders ON orders.listing_id = listings.id
INNER JOIN accounts ON accounts.id = orders.account_id
WHERE listings.status_type = 1 AND listings.suppressed_at IS NULL
  AND orders.status_type = 1 AND accounts.status_type = 1
```

The sweep runs every servable URL through the real builder and groups the errors. It is read-only and took about ten minutes on 2026-10-26. Run it with `bin/rails runner`, and rerun it after each step:

```ruby
rows = Listing.connection.select_all(<<~SQL).to_a
  SELECT listings.id AS listing_id, orders.id AS order_id
  FROM listings
  INNER JOIN orders ON orders.listing_id = listings.id
  INNER JOIN accounts ON accounts.id = orders.account_id
  WHERE listings.status_type = 1 AND listings.suppressed_at IS NULL
    AND orders.status_type = 1 AND accounts.status_type = 1
SQL
failures = Hash.new { |hash, key| hash[key] = [] }
rows.each do |row|
  Listing.select_virtual(Order.find(row['order_id']).token)
rescue StandardError => error
  location = error.backtrace.find { _1.include?('/app/') }&.sub(%r{.*/app/}, 'app/')
  failures["#{error.class} @ #{location}"] << row['listing_id']
end
failures.each { |signature, listing_ids| puts "#{listing_ids.uniq.size} listings: #{signature}" }
```

## Change log

| Version | Date | Change |
|---|---|---|
| 1 | 2026-10-26 | Findings from the `D2GbvGq5` investigation and the full sweep. Step 1 built. |
| 2 | 2026-10-26 | Step 1 merged and confirmed live. Steps 4 and 5 built after the `gqX9b42B` and `Z2v6bE2z` reports. Corrected the second user's status on three of step 4's listings. |
| 3 | 2026-10-27 | Steps 4 and 5 deployed in v661. No `NoMethodError` after it in Honeybadger as of 2026-10-27 07:58. |
