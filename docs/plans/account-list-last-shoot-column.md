# Teams list — Last Shoot column

Built 2026-10-05 in two repos: `insgt-api` on branch `feat/account-list-most-recent-shoot` and `insgt-ops` on branch `feat/account-list-last-shoot-column`. No migration.

## What it does

The teams list (`/#/accounts`) has a new last column, **Last Shoot**, showing each team's most recent completed property visit. The header sorts the loaded page chronologically. A team with no shoot shows an em dash. The "Download Report" CSV gains the same value as a thirteenth column, also named `Last Shoot`.

The value is the stored `account_metrics.most_recent_shoot_at`, written by the nightly sweep. It is the same date as "Most Recent Shoot" in the account info dialog. It is not a live `MAX(orders.scheduled_at)`.

## Decisions

| Question | Decision | Rejected |
|---|---|---|
| Which orders count? | Completed property visits, parents and children, dated by the §5.3 shoot date: the existing `most_recent_shoot_at` (Dan, 2026-10-05). | Every active order including future bookings and cancellations, or active non-cancelled orders. Both needed a new aggregate, and `account-classification.md` §3 forbids a second name for this fact. |
| How does it reach the row? | `mostRecentShootAt` on `GET /accounts`, ISO8601 UTC or null, only with `includes[]=most_recent_shoot_at` and only for admin, scheduler and owner (`reads_account_metrics?`). | Always on. That changes every show, every order view and every other index caller's payload. |
| N+1 | `AccountsController#preload_account_metrics` batches the `has_one` read when the include is present. One `account_metrics` query per page, pinned by a request spec. | A join and select on the search. `ApiSearch#query` forces `DISTINCT` and the `only_once` filter assigns its own select and group, so a join would widen `order_by_sort!`'s constraints. |
| CSV source | The stored column, read in the same batched pluck as `Shoots (365d)`, so the file and the screen agree. | A live grouped `MAXIMUM` like `First Shoot`. That would disagree with the screen until the next nightly. |
| CSV position | Appended thirteenth. The header row is a CRM import contract. | Beside `First Shoot`. That would silently re-map a positional import. |
| CSV date zone | The exporting user's `users.time_zone`, falling back to UTC when it is nil or unrecognized. 119 of 2,088 dated accounts on the dev restore have a different UTC date, mostly twilight shoots. The screen formats in the viewer's local time, and the two agree for a Pacific user. | UTC, which `First Shoot` uses. That would put a twilight shoot on the next day in the file but not on screen. |
| Screen date zone | The viewer's local time, via `moment(iso)`. | `moment.utc`, which shows the next day for every evening Pacific shoot. |
| Label | `Last Shoot`, to pair with the export's existing `First Shoot`. | `Most Recent Shoot`, the dialog's label. It is too wide for a table header. |
| Sort of a never-shot team | null is coerced to 0 by `sortAccountListRows`, so it sorts as the oldest: first under ascending, last under descending. | A null branch in the shared comparator. That changes how every other column sorts. |

## Code map

| File | What |
|---|---|
| `insgt-api/app/helpers/accounts_helper.rb` | `set_most_recent_shoot_at!`, called inside the four-role block beside `set_rolling_365_parent_count!` |
| `insgt-api/app/controllers/accounts_controller.rb` | `preload_account_metrics` on index; `export` passes `current_user.time_zone` |
| `insgt-api/app/services/account_csv_export_service.rb` | `Last Shoot` column, `stored_metrics` (one pluck for both stored columns), optional `time_zone` argument |
| `insgt-api/spec/requests/accounts_most_recent_shoot_spec.rb` | Role gate, opt-in, null states, query count, export time zone |
| `insgt-api/spec/services/account_csv_export_service_spec.rb` | Thirteen headers, stored value, blanks, time zone and fallback |
| `insgt-ops/src/app/shared/models/account.model.ts` | `mostRecentShootAt?: string \| null` |
| `insgt-ops/src/app/features/accounts/data-access/account-list-url.ts` | `ACCOUNT_LIST_INCLUDES` gains `most_recent_shoot_at` |
| `insgt-ops/src/app/features/accounts/pages/account-list/account-list-row.model.ts` | Row fields `mostRecentShootAt` (epoch) and `mostRecentShootOn` (display), sort key, column id |
| `insgt-ops/src/app/features/accounts/pages/account-list/account-list-page.html` | The `mostRecentShootAt` column |
| `insgt-ops/cypress/e2e/accounts/team-list-last-shoot.cy.ts` | Include on the wire, rendering, em dash, sort |

## Deploy order

API first, then ops. Old ops against the new API gets an identical payload, because it does not send the include. New ops against the old API renders em dashes in the column until the API ships. The CSV change ships with the API alone.

## Known and accepted

- **The value is nightly.** A shoot completed today shows tomorrow, like the rest of `account_metrics`.
- **First Shoot stays UTC-dated.** That puts 87 of 2,088 accounts a day later than their Pacific date. Changing an existing column's values was out of scope.
- **The Cypress spec is unrun.** On 2026-10-05 the host's ops and API dev servers accepted TCP but never answered HTTP. It follows the sibling accounts specs: a real `cy.loginAsAdmin` and a stubbed `GET /accounts`.
