# Expanded Team Search — segmentation filters for `/teams`

> Spans two repos: `insgt-api` and `insgt-ops`. **Two commit streams, no atomic cross-repo change.**
> API changes are additive and land first.

## Context

The Teams page is the segmentation surface for sales, retention, reactivation and customer
segmentation across the full account history back to 2007 — roughly 2,800 accounts, of which ~532
ordered in the trailing twelve months and ~98 are monthly-active. Today it filters on name, phone,
scheduler, sales person, marketing source, a created-date range, and one boolean "Only did one
shoot?". None of that reaches order history, so the segments the business actually runs — "last shot
18 months ago", "came in via a headshot and never booked listing work" — cannot be expressed.

This adds four filter groups: **Activity** (first / most recent shoot), **Order history** (total
parent shoots), **Services / packages** (has / has never ordered), and **Account origin** (a
partition, not a condition). All combine as AND, all resolve server-side before pagination.

**Accounts with zero orders are in scope** — "signed up, never converted" is a real segment. Count
filters must therefore include 0, while activity-date filters must not match a null date. That
asymmetry is the most likely source of a silently wrong result set and is specified in full below.

Two cohorts drive v1: **reactivation** and **headshot conversion**. Everything else is aspirational
and shapes nothing here.

---

## 1. What exists today

**insgt-ops** — route `teams` → `AccountModule` → `AccountDashboardPage`
([app-routing.module.ts:124-129](apps/insgt-ops/src/app/app-routing.module.ts#L124-L129),
[account-dashboard.page.ts:40-254](apps/insgt-ops/src/app/accounts/dashboard/account-dashboard.page.ts#L40-L254)).
Legacy throughout: `standalone: false`, constructor injection, `UntypedFormGroup`, no `OnPush`,
`*ngIf`/`*ngFor`, `alive`+`takeWhile` teardown. Twelve controls built in `setForm()`
([:150-167](apps/insgt-ops/src/app/accounts/dashboard/account-dashboard.page.ts#L150-L167)); the raw
`this.form.value` is dispatched straight to `accountActions.ReadCollection`
([:136-140](apps/insgt-ops/src/app/accounts/dashboard/account-dashboard.page.ts#L136-L140)) with no
mapper. State is legacy `accounts/store/`, no facade, and **search params are never stored** —
`ReducerService.readCollection` ignores the payload
([reducer.service.ts:38-52](apps/insgt-ops/src/app/core/reducer.service.ts#L38-L52)).

**insgt-api** — `GET /accounts` → `Account.search(search_params)`
([accounts_controller.rb:38-40](apps/insgt-api/app/controllers/accounts_controller.rb#L38-L40)) →
`AccountQuery#search`
([account_query.rb:54-68](apps/insgt-api/app/models/concerns/account_query.rb#L54-L68)) →
`ApiSearch#query` ([api_search.rb:16-30](apps/insgt-api/lib/api_search.rb#L16-L30)). Filters push
onto `options[:where]`/`[:joins]`, each becoming a separate `.where(...)` — they AND, and are not
deduplicated. **No Ransack, Elasticsearch, pg_search or kaminari** (Gemfile verified); 17 `*Query`
concerns. The framework extends cleanly and is not being replaced.

### Limitations that block the segmentation

1. **No order-history filter of any kind exists.** `Order.search` has no `service_id` param
   ([order_param.rb:5-6](apps/insgt-api/lib/order_param.rb#L5-L6)); `AccountQuery`'s only
   account↔order predicate is the positive `INNER JOIN` in `join_shoots!`.
2. **The created-date filter silently excludes zero-order accounts** — `where_created_on` calls
   `join_shoots!`, an INNER JOIN
   ([account_query.rb:151-157](apps/insgt-api/app/models/concerns/account_query.rb#L151-L157),
   [:194-201](apps/insgt-api/app/models/concerns/account_query.rb#L194-L201)). Also, `end_on` alone
   is a no-op — the guard is on `start_on` only.
3. **`Order.shoots` excludes only order type 3**, so headshot events, paparazzi and reels count as
   shoots today. A free headshot at a recent event *does* currently reset most-recent-shoot — the
   exact failure this tool exists to prevent.
4. **`GET /accounts` emits no `ORDER BY`.** `options[:order]` is never set and `Account` has no
   `default_scope`, so pagination is not a stable partition.
5. **`order_count` is an N+1** — `orders.shoots.count` per row unless `only_once` supplied the
   `shoot_count` alias ([account.rb:75-79](apps/insgt-api/app/models/account.rb#L75-L79)) — plus
   four sibling N+1s on the same list.
6. **Filters never reach the URL** (no `ActivatedRoute` import on the page); sorting is client-side
   and page-local.
7. **Zero test coverage** — no request spec for `GET /accounts`, no Cypress for the search.

---

## 2. Data model findings

**Team is `Account`.** No `Team` model exists ([account.rb:2](apps/insgt-api/app/models/account.rb#L2)).

| Prompt term | Codebase term |
|---|---|
| Team | `Account` |
| Package | `OrderType` |
| Service / line item | `Service` via `OrderService` |
| Package composition | `OrderTypesService` |
| `only_one_shoot` | `only_once` (API) / `onlyOnce` (Angular control) |
| Cancelled | `order_events.tag = 'canceled'`, cached on `orders.order_event_id` |

**`orders.account_id` is `NOT NULL` and is the only ownership path**
([db/schema.rb:696](apps/insgt-api/db/schema.rb#L696),
[order.rb:113](apps/insgt-api/app/models/order.rb#L113)). No order reaches an account indirectly
through users; `OrdersUser` carries contractors only
([orders_user.rb:24-30](apps/insgt-api/app/models/orders_user.rb#L24-L30)). **"Orders by any user on
the team" is therefore automatic** — there is no owner-only variant to build.

**Parent/child is `orders.parent_id`, and the tree is not one level deep**
([order.rb:116-131](apps/insgt-api/app/models/order.rb#L116-L131)) — a child may itself be a parent,
which is how one checkout groups several orders.

**There is no shoot-date column.** `orders` carries `scheduled_at` (nullable; **nulled on
reschedule**, [order.rb:975-983](apps/insgt-api/app/models/order.rb#L975-L983); **synthetic** for
Quick Pics, [order.rb:1147-1156](apps/insgt-api/app/models/order.rb#L1147-L1156)), `paid_at`,
`requested_on`, `photographer_arrived_at`/`_left_at`, `created_at`. No `shoot_date`, `delivered_at`,
`completed_at` or `cancelled_at`.

**Two shipped "first shoot" numbers already disagree.** The Teams CSV export uses
`MIN(scheduled_at)`
([account_csv_export_service.rb:82-91](apps/insgt-api/app/services/account_csv_export_service.rb#L82-L91));
`account_metrics.first_shoot_at` uses `MIN(paid_at)`
([calculator.rb:412-429](apps/insgt-api/app/services/account_metrics/calculator.rb#L412-L429)). The
migration that added the latter says so in capital letters — *"paid_at IS A PAYMENT TIMESTAMP, NOT A
SHOOT DATE"* — and accepts that comped accounts read NULL for both dates
([20260715120000](apps/insgt-api/db/migrate/20260715120000_add_shoot_dates_to_metrics.rb#L19-L27)).

**`account_metrics` is the rollup**, unique-indexed on `account_id`, and `RecomputeAll` covers
**every active account**
([recompute_all.rb:43-51](apps/insgt-api/app/services/account_metrics/recompute_all.rb#L43-L51)). A
zero-order account therefore has a row with `lifetime_parent_count = 0` and NULL shoot dates — the
null semantics below fall out of the table shape rather than needing to be engineered.

**`Account.merge` reassigns orders with `update_columns`**, moving soft-deleted rows too and
retaining their original `created_at`
([account.rb:136-138](apps/insgt-api/app/models/account.rb#L136-L138)). An account's history can
therefore grow retroactively.

---

## 3. The listing-vs-non-listing predicate

**Six mutually inconsistent definitions already exist**, one of which matches on a mutable name
string:

| Set | Where |
|---|---|
| `{3}` | [order.rb:100](apps/insgt-api/app/models/order.rb#L100) · [account_query.rb:199](apps/insgt-api/app/models/concerns/account_query.rb#L199) |
| `{3, 12, 19}` | [order_query.rb:247](apps/insgt-api/app/models/concerns/order_query.rb#L247) |
| 13 ids, `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` | [order.rb:51](apps/insgt-api/app/models/order.rb#L51) |
| the above `+ {28, 32}` | [order.rb:52-53](apps/insgt-api/app/models/order.rb#L52-L53) |
| `{3, 73, 19, 74}` | [account_report.rb:676-677](apps/insgt-api/lib/account_report.rb#L676-L677) |
| **by name string** | [orders_controller.rb:237](apps/insgt-api/app/controllers/orders_controller.rb#L237) |

**Resolved to one constant.** The order-type names (confirmed against the database) settle it:

```ruby
# Order
NON_LISTING_ORDER_TYPE_IDS = [3, 12, 14, 19, 23, 24, 27, 34, 68, 73, 74, 207].freeze
#   3 Free Web Portrait            12 WebPortrait Event      14 Test package
#  19 Paparazzi                    23 WebPortrait            24 Scheduler event
#  27 Matterport 3D Hosting Renewal  34 Personalized web address (Custom URL)
#  68 Stock Photos                 73 Headshot Event         74 Free Instagram Reel
# 207 Reprocess - Disclosure Compliance
#
# Deliberately NOT here: 4 Stager's special (real listing work), 28 Virtual Staging,
# 32 Quick Pics — the agent shoots, we process, and they paid for listing work.
SHOOT_EXCLUDED_ORDER_TYPE_IDS = (NON_LISTING_ORDER_TYPE_IDS + [RESHOOT_ORDER_TYPE_ID]).freeze
```

Three facts the names settled:

- **`OrderType::HEADSHOT_ID = 3` is a misnamed constant** — id 3 is *Free Web Portrait*. The scope
  defining the Teams shoot count is named after the wrong product.
- **Id 14 is "Test package"** — test orders are an order type, not a flag. Nothing else in the
  schema marks test data.
- Namespace collision: **order type** 68 is Stock Photos; **service** 68 is Aerial 360° Pano.

**Keep the list non-empty.** An empty list compiles to `NOT IN (NULL)`, which is NULL for every row
and silently excludes everything — the warning already written at
[order.rb:44-46](apps/insgt-api/app/models/order.rb#L44-L46).

---

## 4. Service history — the package-composition trap

The failure to design against: *account bought a package containing a floor plan → system reports
"Never ordered Floor Plan."*

**Package defaults are expanded into rows at creation.** `after_create
:create_default_order_services!` ([order.rb:145](apps/insgt-api/app/models/order.rb#L145)) →
[order_service.rb:65-79](apps/insgt-api/app/models/order_service.rb#L65-L79) writes one
`order_services` row per `order_types_services` entry, at `price: 0`. In place since 2015.

**But that snapshot is destroyed, and `insgt-app` destroys it unconditionally.**

1. `Order.create_from_cart` saves the order, the callback writes the defaults, and it then calls
   `create_additional_order_services(order, { services: cart.services })`
   ([order.rb:1131](apps/insgt-api/app/models/order.rb#L1131)). That argument is a **Ruby hash
   literal**, so `options.key?(:services)` at
   [order_service.rb:82](apps/insgt-api/app/models/order_service.rb#L82) is **always true** — even
   for an empty cart.
2. `delete_existing_services` therefore always fires. It is a hard `delete_all` with no tombstone
   ([order_service.rb:206-208](apps/insgt-api/app/models/order_service.rb#L206-L208)).
3. Only `cart.services` is re-created — the agent's chosen add-ons from
   `Service.where('cart IS NOT NULL')`
   ([carts_controller.rb:8-12](apps/insgt-api/app/controllers/carts_controller.rb#L8-L12)), seeded
   as service ids 20, 23, 28, 35, 68, 69, 72, 82, 83, 84, 87, 88
   ([service.rb:53-100](apps/insgt-api/app/models/service.rb#L53-L100)).

**Service 33 — floor plan — is not in that catalog.** For every order booked through the agent PWA,
a bundled floor plan leaves no `order_services` row.

`insgt-ops` is set-preserving by contrast — its cart dialog re-posts the full `order.services` list
([order-cart.dialog.ts:126-131](apps/insgt-ops/src/app/orders/cart/order-cart.dialog.ts#L126-L131))
— but **not value-preserving**: after the delete every line takes `create_for_order`'s
`price = service.price`
([order_service.rb:151-159](apps/insgt-api/app/models/order_service.rb#L151-L159)), rewriting
package defaults from `0`. Two *unintended* ops call sites also post the whole order object and
trigger this —
[order-property.dialog.ts:57-63](apps/insgt-ops/src/app/orders/property/order-property.dialog.ts#L57-L63)
and
[order-compliance.component.ts:56-69](apps/insgt-ops/src/app/orders/compliance/order-compliance.component.ts#L56-L69),
the latter on **every** compliance-mode click.

Two further ways history moves: cancelling a child soft-deletes a line item off the parent
([order.rb:939-948](apps/insgt-api/app/models/order.rb#L939-L948)), and `order.services` filters
`services.status_type` ([order.rb:69-71](apps/insgt-api/app/models/order.rb#L69-L71)) so retiring a
Service erases it from every historical order. **Query `order_services.service_id` directly, never
`order.services`.**

This vindicates the repo's own ruling — *"We can't safely go off of the package, or the services…"*
([order_query.rb:46-49](apps/insgt-api/app/models/concerns/order_query.rb#L46-L49)).

### The design

Union only **immutable** signals. Current package composition via `order_types_services` was
considered and **rejected**: it reconstructs today's package, not what was bought, so a service
later removed from a package makes genuine historical purchases vanish — the unsafe
false-*"never ordered"* direction.

| Product | Signals unioned |
|---|---|
| Floor Plan | `order_services.service_id = 33` **∪** `floorplans` where `status_type = 1` |
| Aerial | `order_services.service_id IN (28, 69)` **∪** child orders `order_type_id IN (25, 13)` |

`floorplans` is a genuine artifact table keyed on `order_id`, written by staff upload
([floorplans_controller.rb:13-30](apps/insgt-api/app/controllers/floorplans_controller.rb#L13-L30)).
It proves delivery rather than purchase, which for *"do not pitch floor plans to someone who has
them"* is the better signal — but it **must** filter `status_type = 1` or it counts soft-deleted
artifacts.

**Residual gap, stated plainly:** an app-booked order whose package contained a floor plan that was
never delivered has neither row, and reads as *"never ordered Floor Plan."* This is the known,
bounded limit of the design. Verification query 1 below measures how often it occurs, and **must be
run before this filter ships.**

Aerial photos (service 28) and video (69) ship as one combined control; service 68 (360° pano) is a
sub-add-on never sold alone and is excluded. Existing precedent for this exact read:
`order.order_services.map(&:service_id).include?(28)`
([photo_report.rb:214-216](apps/insgt-api/lib/photo_report.rb#L214-L216)).

---

## 5. Account origin

There is **no origin column** on `accounts`, and three existing inferences disagree — first-order-is-
type-3 by `created_at` ([account_report.rb:1085](apps/insgt-api/lib/account_report.rb#L1085)),
has-any-type-3 ([:311-315](apps/insgt-api/lib/account_report.rb#L311-L315)), and
has-any-non-`{3,73,19,74}` ([:318-330](apps/insgt-api/lib/account_report.rb#L318-L330)). The last two
are not complements: an account can satisfy both, and a zero-order account satisfies neither. A
`Headshot lead` Tag also exists
([marketing_event_import.rb:14](apps/insgt-api/app/models/marketing_event_import.rb#L14)) but tags
attach to *users*, not accounts
([account.rb:367-373](apps/insgt-api/app/models/account.rb#L367-L373)).

**Definition adopted** — the order type of the account's **earliest surviving active parent order by
`created_at`**:

```ruby
HEADSHOT_ORIGIN_ORDER_TYPE_IDS = [3, 12, 23, 73].freeze
# Free Web Portrait, WebPortrait Event, WebPortrait, Headshot Event.
# Narrower than NON_LISTING_ORDER_TYPE_IDS: Paparazzi (19), Scheduler event (24) and
# Free Instagram Reel (74) are non-listing but are not headshot acquisition.
```

- **`created_at`, not `paid_at`** — a $0 headshot may never have a `paid_at`.
- **Parent orders only** — avoids child-order noise.
- **Cancelled orders included** — an abandoned first headshot booking still made the account a
  headshot account. This is a product decision with cohort impact, not a derivation.
- **Not "acquisition."** `Account.merge` can retroactively replace the destination's earliest order,
  so the honest phrasing is *earliest surviving parent order across merged history*.
- **Non-headshot is the true complement**, including the `IS NULL` branch. Every account lands on
  exactly one side.

---

## 6. The search model

```ruby
# A shoot: one listing job we actually went out and did, that was not cancelled.
scope :shoots, -> {
  active
    .where(parent_id: nil)
    .where.not(order_type_id: SHOOT_EXCLUDED_ORDER_TYPE_IDS)
    .where('orders.order_event_id IS NULL OR orders.order_event_id != ?',
           OrderEvent.find_by(tag: 'canceled')&.id || -1)
}
```

Two things here are load-bearing:

- **The `IS NULL OR !=` form.** A bare `where.not(order_event_id: id)` compiles to `!= id`, which is
  NULL-unsafe and would drop every order that has never logged an event.
- **`OrderEvent.canceled_id` does not exist.** Only `OrderEvent.tag_id(tag_name)`
  ([order_event.rb:90](apps/insgt-api/app/models/order_event.rb#L90)). The house idiom, including
  the `|| -1` fallback so a missing tag matches nothing rather than raising on a read path, is
  [account_pending_shoots_service.rb:47](apps/insgt-api/app/services/account_pending_shoots_service.rb#L47).

| Concept | Definition |
|---|---|
| Total parent shoots | `account_metrics.lifetime_parent_count` over the universe above |
| First shoot | `account_metrics.first_shoot_at` — `MIN(paid_at)`, `completed` log required |
| Most recent shoot | `account_metrics.most_recent_shoot_at` — `MAX(paid_at)` |
| Service history | `NOT EXISTS` over the union in §4 |
| Account origin | §5 |

### Null handling for zero-order accounts

| Filter | Zero-order account | Headshot-only account | Mechanism |
|---|---|---|---|
| `count ≤ N` / `= 0` | **matches** | **matches** | `COALESCE(lifetime_parent_count, 0)` |
| `first_shoot_at` between | **no match** | **no match** | NULL propagates through `>=`/`<=` |
| `most_recent_shoot_at` between | **no match** | **no match** | same |
| `never ordered X` | **matches** | matches unless the headshot carried X | `NOT EXISTS` true over zero rows |
| `has ordered X` | **no match** | depends | `EXISTS` false over zero rows |
| origin = Headshot | no | **yes** | subquery returns a headshot-origin type |
| origin = Non-headshot | **yes** | no | subquery `IS NULL` branch |

The headshot-only account is the row that matters: **parent shoot count 0 and NULL dates, while
still having order history.** `Account origin = Headshot` + `Total parent shoots = Exactly 0`
returns exactly that cohort.

**Everything ANDs.** `ApiSearch#build_where` makes each pushed condition a separate `.where`, so AND
is what the framework already does; OR would need new machinery and is a non-goal.

---

## 7. API changes

| File | Change |
|---|---|
| [order.rb:22-53](apps/insgt-api/app/models/order.rb#L22-L53) | Add `NON_LISTING_ORDER_TYPE_IDS`, `SHOOT_EXCLUDED_ORDER_TYPE_IDS`, `HEADSHOT_ORIGIN_ORDER_TYPE_IDS` with ID→name comments. **Separately** remove `4` from `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` — that changes the margin metric, so it is its own commit |
| [order.rb:93-100](apps/insgt-api/app/models/order.rb#L93-L100) | Widen `Order.shoots`; update the comment, which already says *"Change one, change the other"* |
| [account_query.rb:194-201](apps/insgt-api/app/models/concerns/account_query.rb#L194-L201) | `join_shoots!` mirrors the new predicate in raw SQL |
| [calculator.rb](apps/insgt-api/app/services/account_metrics/calculator.rb) | **All seven order-type exclusion sites — lines 209, 273, 292-293, 337, 366, 396, 425** — move together, plus the cancelled guard. Widening only `shoot_dates_sql` and `reshoot_counts_sql` leaves median / average / rolling-90 shoot values on the old universe, so one `AccountMetric` row would encode inconsistent shoot universes |
| [system_metrics/calculator.rb:181,370](apps/insgt-api/app/services/system_metrics/calculator.rb#L181) | Either widen to match, or explicitly accept that fleet KPIs diverge from account KPIs. It aggregates raw orders, so it does **not** follow the per-account rewrite |
| [account_query.rb:54-68](apps/insgt-api/app/models/concerns/account_query.rb#L54-L68) | New `where_shoot_dates`, `where_shoot_count`, `where_service_history`, `where_account_origin`; new `join_on[:account_metrics]` **LEFT JOIN** |
| [accounts_controller.rb:230-236](apps/insgt-api/app/controllers/accounts_controller.rb#L230-L236) | New params |

**Param names follow the existing range convention** — `order_query.rb`'s `METRIC_RANGE_COLUMNS`
already uses `#{column}_gt` / `_lt`
([order_query.rb:251-262](apps/insgt-api/app/models/concerns/order_query.rb#L251-L262)):

```ruby
times:    %i[start_on end_on first_shoot_at_gt first_shoot_at_lt
             most_recent_shoot_at_gt most_recent_shoot_at_lt],
integers: %i[... lifetime_parent_count_gt lifetime_parent_count_lt
             never_ordered_service_ids ordered_service_ids],
strings:  %i[... account_origin]
```

`AppParam.integer_params` maps arrays element-wise
([app_param.rb:36-46](apps/insgt-api/lib/app_param.rb#L36-L46)), so `never_ordered_service_ids[]`
needs no new extraction. Multiple service conditions **AND** — each id set becomes its own
`NOT EXISTS`.

```sql
-- never ordered (floor plan shown; NOT EXISTS per the ruling at user_query.rb:59-66)
NOT EXISTS (SELECT 1 FROM order_services os
              JOIN orders o ON o.id = os.order_id
             WHERE o.account_id = accounts.id
               AND o.status_type = 1 AND os.status_type = 1
               AND os.service_id IN (?))
AND NOT EXISTS (SELECT 1 FROM floorplans f
                  JOIN orders o2 ON o2.id = f.order_id
                 WHERE o2.account_id = accounts.id
                   AND o2.status_type = 1 AND f.status_type = 1)

-- account origin
(SELECT o.order_type_id FROM orders o
  WHERE o.account_id = accounts.id AND o.status_type = 1 AND o.parent_id IS NULL
  ORDER BY o.created_at ASC, o.id ASC LIMIT 1) IN (?)
```

`ORDER BY created_at ASC, id ASC` — the id tiebreak makes same-timestamp imports deterministic.
Non-headshot is `(subquery) IS NULL OR (subquery) NOT IN (?)`.

**Relative dates resolve on the client.** `search_time_params` already parses `start_on`/`end_on` in
`current_user.time_zone` ([app_param.rb:94-100](apps/insgt-api/lib/app_param.rb#L94-L100));
teaching the API "14 months ago" would duplicate that.

**No serializer change for v1** — the table columns are unchanged.

---

## 8. Front-end changes

The page is legacy NgModule and **stays** legacy — do not half-convert. The new filter panel is a
**new file**, so it is written modern (standalone, `OnPush`, `inject()`, typed forms) and imported
by the existing module, exactly as standalone `UserForm` is imported by legacy `AccountEditModule`.

| File | Change |
|---|---|
| `accounts/dashboard/components/advanced-filters/advanced-filters.ts` *(new)* | Standalone, `OnPush`, typed `FormGroup`. Follow `UnalteredPhotoCrudDialog` as the typed-form exemplar |
| `accounts/dashboard/account-search.model.ts` *(new)* | `AccountSearch` interface, `accountSearchFields` config, and **pure** `toApiParams` / `parseUrlParams` / `toChips` |
| [account.model.ts:76-83](apps/insgt-ops/src/app/shared/models/account.model.ts#L76-L83) | Extend `AccountSearchParams` — it declares 6 fields while the form sends 12, a gap the untyped form hides |
| [account-dashboard.page.ts](apps/insgt-ops/src/app/accounts/dashboard/account-dashboard.page.ts) | Host the panel; `(search)` output → existing dispatch; URL round-trip |
| [account-dashboard.page.html:15-108](apps/insgt-ops/src/app/accounts/dashboard/account-dashboard.page.html#L15-L108) | Mount the panel, add the chip strip |

**Form structure.** Activity and Services are `FormArray<FormGroup<…>>`; Order history is a single
group; **Account origin is a plain `FormControl<'any'|'headshot'|'non_headshot'>`** — it partitions
the account set rather than adding a condition, so forcing it into a FormArray would misrepresent it
and break `Clear`. **There is no FormArray prior art in any filter surface in this repo** — the only
two are edit forms
([order-type-form.component.ts:123](apps/insgt-ops/src/app/order-types/form/order-type-form.component.ts#L123),
[service-form.component.ts:132](apps/insgt-ops/src/app/services/form/service-form.component.ts#L132))
— so copy the typed-form idiom, not a filter idiom.

**Chips derive from form state** — one `computed()` over the form value, never a parallel array.
Removing a chip patches the form, which re-derives the strip and re-runs the search. The only chip
UI in the repo is hand-rolled at
[matterport-list-page.html:60-75](apps/insgt-ops/src/app/features/matterports/pages/matterport-list/matterport-list-page.html#L60-L75)
(there is no `mat-chip` usage anywhere).

**URL round-trip** follows `seedFromUrl` / `syncUrl` / `filterQueryParams` at
[user-list-page.ts:205-301](apps/insgt-ops/src/app/features/users/pages/user-list/user-list-page.ts#L205-L301),
with framework-free parsers in the model file so they are unit-testable — the pattern
[user-directory.model.ts:150-253](apps/insgt-ops/src/app/features/users/data-access/user-directory.model.ts#L150-L253)
already establishes. Hash routing is unaffected.

**Dates** use `moment` (repo standard — do not introduce `date-fns` or `luxon`). **Clear** resets the
FormArrays to empty and origin to `'any'`, then drops the query params; preserve the existing
behaviour of re-running the search immediately
([:182-199](apps/insgt-ops/src/app/accounts/dashboard/account-dashboard.page.ts#L182-L199)).

---

## 9. Database and performance — **ESTIMATED**

No `EXPLAIN ANALYZE` was run; database access was unavailable. Treat this section as reasoning from
schema and row counts, not measurement.

- `account_metrics` LEFT JOIN is one-to-one (unique index on `account_id`). Cheap, though not
  literally free — `ApiSearch` applies `DISTINCT` unconditionally
  ([api_search.rb:20](apps/insgt-api/lib/api_search.rb#L20)).
- Date and count predicates read `account_metrics` columns. At ~2,800 rows a sequential scan is
  sub-millisecond. **No index proposed** — indexing here would be premature.
- **The likeliest real cost is the double execution.** `Metadata.calculate` re-runs the entire
  filter set unpaginated for the total count
  ([api_search.rb:29](apps/insgt-api/lib/api_search.rb#L29),
  [metadata.rb:43-62](apps/insgt-api/lib/metadata.rb#L43-L62)), so every union-backed `NOT EXISTS`
  and the origin subquery are evaluated twice per request.
- The origin correlated subquery narrows by `index_orders_on_account_id` first, so each lookup sorts
  a small per-account set. `orders(account_id, created_at)` is a **plausible** first index but is
  not justified without a measured plan.
- Any index ships as its own migration: `disable_ddl_transaction!` + `algorithm: :concurrently`, one
  statement, matching
  [20260818120000](apps/insgt-api/db/migrate/20260818120000_add_directory_indexes_to_users_and_accounts_users.rb).
- **Filtering stays before pagination** — every predicate is a `WHERE` in the same statement as
  `LIMIT/OFFSET`. Reading `lifetime_parent_count` rather than a `HAVING` also avoids the expensive
  `:having` subquery branch at [metadata.rb:44-47](apps/insgt-api/lib/metadata.rb#L44-L47).

---

## 10. Backward compatibility

1. **`only_once` keeps its parameter and its HAVING semantics — but its result set will change**,
   because it depends on `join_shoots!`, which widens. Unavoidable, and arguably the fix. Do not
   describe it as unchanged.
2. **`Exactly 1 parent shoot` is not equivalent to `only_once`.** The latter means *exactly one shoot
   **and it was paid***
   ([account_query.rb:178-186](apps/insgt-api/app/models/concerns/account_query.rb#L178-L186)). Both
   controls ship; neither replaces the other.
3. **The Order Count column will drop** for accounts with Scheduler events, WebPortraits, Stock
   Photos, hosting renewals, reshoots or cancellations. Two people use this page daily — announce it.
4. **A recompute can flip an account's visible Active/Inactive badge.** `lifetime_parent_count`,
   `rolling_90_parent_count`, both reshoot rates and the shoot dates all move, and they are consumed
   by [account-info-card.ts:207,261](apps/insgt-ops/src/app/features/accounts/components/account-info-card/account-info-card.ts#L207),
   [account-metrics.ts:156](apps/insgt-ops/src/app/features/accounts/components/account-metrics/account-metrics.ts#L156)
   and [accounts_metrics/show.json.jbuilder:17,34,48](apps/insgt-api/app/views/accounts_metrics/show.json.jbuilder#L17).
   `lifetime_margin_value_cents` also moves for Stager's-special accounts.
5. A full `rake metrics:recompute` is required after deploy.
6. The created-date filter keeps its hidden INNER JOIN. Documented, not fixed.
7. All new API params are additive; old clients are unaffected.

---

## Decisions

| # | Decision |
|---|---|
| D1 | Widen `AccountMetrics::Calculator` alongside `Order.shoots` and `join_shoots!` — one predicate, one home |
| D2 | Reshoots (6) excluded from count **and** dates |
| D3 | `completed`-log required for **dates only**, not counts |
| D4 | Canonical date is `paid_at`, via `account_metrics` |
| D5 | Cancelled excluded; the guard goes in the calculator too |
| D6 | Junk accounts `[2, 89, 2555]`, search-only, never applied to `account_metrics`, and never excluding zero-order accounts |
| D7 | Service history = `order_services.service_id` ∪ delivered artifact. Mutable package composition **rejected** |
| D8 | Aerial = services `{28, 69}` combined; Floor Plan = service `{33}`; service 68 excluded |
| D9 | Origin = earliest surviving active **parent** order by `created_at`, cancelled included |
| D10 | Zero-order account → **Non-headshot** |
| D11 | AND-only |
| D12 | Relative dates resolved client-side to concrete bounds |
| D13 | `only_once` kept, **not** aliased onto the count filter |
| D14 | Count filter reads `lifetime_parent_count`, not `HAVING` |
| D15 | `NON_LISTING_ORDER_TYPE_IDS` = the 12 ids in §3; `4 Stager's special` is listing work and is also removed from `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` |
| D16 | `HEADSHOT_ORIGIN_ORDER_TYPE_IDS = [3, 12, 23, 73]` |

---

## Implementation

Two repos, two commit streams. API is additive and lands first.

| # | Repo | Concern | Verify | Deliberate break |
|---|---|---|---|---|
| 1 | api | Constants + widen `Order.shoots` + `join_shoots!` | `bundle exec rspec spec/models/order_shoots_spec.rb` | Revert the constant to `[3]` → Headshot-Event and Paparazzi examples fail |
| 2 | api | Widen all seven calculator sites (order types, reshoots, cancelled) | `bundle exec rspec spec/services/account_metrics/` | Drop the cancelled guard → the cancelled-order date example fails |
| 3 | api | `SystemMetrics::Calculator` — widen or document divergence | `bundle exec rspec spec/services/system_metrics/` | Widen only one of the two → the fleet/account agreement example fails |
| 4 | api | Remove `4` from `MARGIN_LTV_REVENUE_EXCLUDED_ORDER_TYPE_IDS` | `bundle exec rspec spec/lib/tasks/metrics_rake_spec.rb` | Re-add 4 → the Stager's-special margin example fails |
| 5 | api | `where_shoot_dates` + `where_shoot_count` + params | `bundle exec rspec spec/requests/accounts_search_spec.rb` | Replace `COALESCE(...,0)` with a bare column → the zero-order `count = 0` example fails |
| 6 | api | `where_service_history` (union `NOT EXISTS`) | same spec | Point it at `order.services` → the floor-plan-inside-a-package example fails |
| 7 | api | `where_account_origin` | same spec | Drop the `IS NULL` branch → the zero-order partition example fails |
| 8 | ops | `account-search.model.ts` — interfaces + pure functions | `npm run test` | Break the months-ago math → the date spec fails |
| 9 | ops | Panel: Activity FormArray | `npx ng lint` + Cypress happy path | Remove a `data-cy` → the Cypress selector fails |
| 10 | ops | Order-history + Account-origin controls | Cypress | Make origin a FormArray → Clear leaves a stale value |
| 11 | ops | Services FormArray | Cypress | — |
| 12 | ops | Chips derived from form state | Cypress chip-removal | Duplicate chips into a parallel array → removal desyncs |
| 13 | ops | URL round-trip | Cypress reload | Drop `filterQueryParams` → an off filter persists in the URL |

Each API step leaves the app green and additive; each ops step leaves the panel usable.

### Recommended first slice — Account origin, end to end

The only filter with **no `account_metrics` dependency and no calculator change** — a correlated
subquery over `orders` alone. It proves the whole vertical (Rails query → API param → Angular
control → visible result) without touching shipped metrics, without the recompute, and without the
seven-site widening, and it delivers half the headshot-conversion cohort on day one.

Includes: `HEADSHOT_ORIGIN_ORDER_TYPE_IDS`, `where_account_origin` + the `account_origin` param, one
`FormControl` in the new panel, and `spec/requests/accounts_search_spec.rb` — the first request spec
`GET /accounts` has ever had.

Defers: the widened shoot predicate, every calculator change, activity dates, shoot counts, **the
entire service-history filter**, chips, URL round-trip, and all FormArrays.

Deliberate break: delete the `IS NULL` branch — never-ordered accounts must then vanish from both
sides of the partition. Roughly half a day to a day, two commits.

---

## Testing

**RSpec** — new `spec/requests/accounts_search_spec.rb`.

Accounts with: zero orders · exactly one parent order · multiple parents · child orders · cancelled
orders · soft-deleted orders · first shoot in/out of range · last shoot in/out of range · floor plan
standalone · **floor plan inside a package** · aerial standalone · **aerial inside a package** ·
multiple service exclusions · combined activity + volume + service filters.

Origin and null handling:

- headshot-origin account whose only order is the headshot
- headshot-origin account that later booked listing work
- **listing work 14 months ago + a headshot last month → most recent shoot still 14 months ago**
- **headshot-only → count 0, NULL dates, found by `origin = Headshot` + `count = 0`**
- **event-photography-only account → same exclusion as headshots**
- one order under **each** of the 12 excluded ids
- account manually created before its headshot order
- first order a cancelled headshot, then a later listing shoot → still Headshot origin
- non-headshot account with a headshot add-on mid-history → still Non-headshot
- zero-order vs a count filter including 0 → **matches**
- zero-order vs an activity-date filter → **does not match**
- zero-order vs the partition → lands on exactly one side
- **an order with `order_event_id IS NULL`** → still counts (the NULL-safety case)

Plus `spec/models/order_shoots_spec.rb` and extensions to
`spec/services/account_metrics/calculator_spec.rb`.

**Vitest (insgt-ops)** — state layer only: `toApiParams`, `parseUrlParams`, `toChips`, relative-date
resolution. No component tests, no TestBed.

**Cypress** — happy path across all four groups, empty state, API 500, chip-removal round-trip, URL
restore-on-reload. Every new control gets `data-cy`.

---

## Verification

**Run these before building the service-history filter.** They were never run — database access was
unavailable during planning — and query 1 gates §4.

```sql
-- 1. How much package-default history was destroyed, and when.
--    If service 33 appears, order_services alone cannot answer the floor-plan question.
SELECT o.id, o.created_at, o.order_type_id, ots.service_id
  FROM orders o
  JOIN order_types_services ots
    ON ots.order_type_id = o.order_type_id AND ots.status_type = 1
  LEFT JOIN order_services os
    ON os.order_id = o.id AND os.service_id = ots.service_id AND os.status_type = 1
 WHERE os.id IS NULL;

-- 2. Which package defaults are invisible to the app catalog (destroyed, never restored)
SELECT ot.id, ot.name, ots.service_id, s.name, s.price, (s.cart IS NOT NULL) AS in_cart_catalog
  FROM order_types_services ots
  JOIN order_types ot ON ot.id = ots.order_type_id
  JOIN services   s  ON s.id  = ots.service_id
 WHERE ots.status_type = 1 ORDER BY ot.id, ots.service_id;

-- 3. Has the price 0 -> services.price rewrite already fired on live rows?
SELECT count(*) FROM order_services os
  JOIN orders o ON o.id = os.order_id
  JOIN order_types_services ots
    ON ots.order_type_id = o.order_type_id AND ots.service_id = os.service_id
   AND ots.status_type = 1
 WHERE os.price <> 0;
```

Also unrun: the population profile — total accounts, accounts with ≥1 order, zero-order accounts,
the distribution of lifetime parent-shoot count, and months-since-most-recent-shoot buckets. Segment
sizes for the five example searches are therefore unknown, and whether the default search should
exclude never-ordered accounts is still undecided.

```bash
cd /workspace/apps/insgt-api
bundle exec rspec spec/requests/accounts_search_spec.rb spec/models/order_shoots_spec.rb \
                  spec/services/account_metrics/ spec/services/system_metrics/
bundle exec rspec
rubocop <changed files>

cd /workspace/apps/insgt-ops
npm run test && npx ng lint
npx cypress run --spec "cypress/e2e/accounts/*.cy.ts"
```

After deploy: `heroku run rake metrics:recompute`, then spot-check that an account's Active/Inactive
badge and Order Count moved only where expected.

---

## Review record

Reviewed by Codex (gpt-5.6), read-only, against both repos. Ten findings; eight accepted, two
partially disputed.

**Accepted and folded in:** the mutable package-composition leg errs in both directions (it was
removed); `calculator.rb` has seven exclusion sites, not two; the Active/Inactive badge and
account-info tiles are unnamed consumers that a recompute moves; `SystemMetrics::Calculator` does not
follow the per-account rewrite; **`OrderEvent.canceled_id` does not exist** and the original scope
sketch would have raised `NoMethodError`; `Account.merge` breaks "acquisition" phrasing; the double
execution of the predicate set is a likelier cost than the origin subquery.

**Disputed:** that `floorplans` is not a usable signal — its `status_type` omission was a real bug
and is fixed, but rows are written by staff upload and delivery evidence is the better signal for
this question, so it stays. And that cancelled-first-order origin is an unlabelled assumption — it
is D9, surfaced and decided deliberately.

**Known gaps, carried deliberately:** no segment sizing or data-quality profile (queries above);
the residual false-*"never ordered"* case in §4; and every performance claim estimated rather than
measured, with §9 the weakest section.

---

## Non-goals

- OR groups, anywhere. Every condition ANDs.
- Saved or shareable segments (the mockup's "Save as segment").
- CSV export — sequenced immediately after v1, not in it.
- Relative-date presets beyond custom bounds and N-months-ago.
- Per-service date windows; service history is lifetime-only.
- Sorting or paginating by any computed column — and **not** fixing the missing `ORDER BY` on
  `GET /accounts`.
- **Not** fixing the `order_count` N+1 or the four sibling N+1s on the same list.
- **Not** renaming `OrderType::HEADSHOT_ID` despite id 3 being *Free Web Portrait*.
- **Not** changing `where_created_on`'s hidden INNER JOIN, so "Team created between" keeps excluding
  zero-order accounts.
- **Not** reconciling the other four divergent order-type exclusion lists, or the name-string match
  at [orders_controller.rb:237](apps/insgt-api/app/controllers/orders_controller.rb#L237).
- **Not** fixing `delete_existing_services`' hard `delete_all`, nor the literal-hash bug at
  [order.rb:1131](apps/insgt-api/app/models/order.rb#L1131) that makes `insgt-app` destroy package
  defaults at creation. Both are real defects with their own blast radius.
- **Not** fixing the two unintended ops call sites that re-post whole orders and rewrite line-item
  prices.
- **Not** fixing `Service#order_services`' misspelled table name
  ([service.rb:8](apps/insgt-api/app/models/service.rb#L8)).
- **Not** converting the Teams page off NgModules, and not migrating `accounts/store/` to
  `data-access/`.
- Merged-team reconciliation; the other Angular apps.
