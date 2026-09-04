# Impersonation — replace the `ACCOUNT_PASSWORD` bypass with audited "view as"

> Spans three repos: `insgt-api`, `insgt-ops`, `insgt-app`. **Three commit streams, no atomic cross-repo change.** Land the API first — both front ends depend on endpoints that must already exist in production.

## Context

Support needs to see a client's dashboard exactly as the client sees it. Today that is done with `ENV['ACCOUNT_PASSWORD']`: a single static string that [sessions_controller.rb:34-39](apps/insgt-api/app/controllers/sessions_controller.rb#L34-L39) accepts in place of any user's real password.

The need is legitimate. The mechanism is a skeleton key, and it just proved its failure mode — the value was found hardcoded in tracked source by the repomix secret guard (see [repomix-packs.md](docs/repomix-packs.md)), was recoverable from git history, and rotating it silently broke Cypress logins in two repos because eight test users had it pasted into `cypress.env.json`.

This plan replaces it with explicit impersonation: authenticate as yourself, request a scoped session for a target user, and leave an audit record. The outcome is that "who looked at this client's account, and when" becomes an answerable question, and revocation becomes per-admin instead of one shared string.

---

## 1. What exists today

**The bypass is checked on the failure path of every login.** [sessions_controller.rb:33-42](apps/insgt-api/app/controllers/sessions_controller.rb#L33-L42):

```ruby
user = query.first
if user_not_authenticated?(user)
  unless create_params[:password] == ENV['ACCOUNT_PASSWORD']
    render json: { errors: 'Not authenticated' }, status: :unprocessable_entity
    return false
  end
  current_user_and_jwt(user)
else
  ...
```

`user_not_authenticated?` is `user.blank? || !user.authenticate(create_params[:password])` ([:108-110](apps/insgt-api/app/controllers/sessions_controller.rb#L108-L110)). So the string functions as a permanent second password on **every account simultaneously**, resolved by email, username **or phone number** ([:112-120](apps/insgt-api/app/controllers/sessions_controller.rb#L112-L120)).

**The token it mints is indistinguishable from a real login.** [sessions_controller.rb:104-106](apps/insgt-api/app/controllers/sessions_controller.rb#L104-L106):

```ruby
def jwt_request_options
  { iss: request.host, sub: @current_user.api_key }
end
```

Signed with the *target's* `jwt_secret`. Two claims, no actor, no expiry.

⚠️ **`jwt_request_options` and `find_jwt_token` are duplicated** in [sessions_controller.rb:100-106](apps/insgt-api/app/controllers/sessions_controller.rb#L100-L106) and [users_controller.rb:176-182](apps/insgt-api/app/controllers/users_controller.rb#L176-L182). Adding claims in one and not the other produces tokens that differ by which endpoint issued them. Consolidate before touching either.

**Verification path.** [app_jwt.rb](apps/insgt-api/lib/app_jwt.rb) unsafe-decodes to read `sub`, looks the user up by `api_key`, then re-decodes against that user's `jwt_secret`. There is no role check at this layer — authorization is a separate `authorize_for(*roles)` before_action ([application_controller.rb:210-214](apps/insgt-api/app/controllers/application_controller.rb#L210-L214)) backed by `system_role?` ([user_roles.rb:24-28](apps/insgt-api/app/models/concerns/user_roles.rb#L24-L28)).

**No impersonation machinery exists.** `grep -riE "impersonat|masquerad|sign_in_as|become_user|view_as"` over `app/` and `lib/` returns nothing.

---

## 2. Why the bypass has to go

| # | Defect | Consequence |
|---|---|---|
| 1 | One shared static string | No per-person revocation. Everyone who has ever held it still holds it. |
| 2 | No actor claim | The resulting JWT is byte-identical to a real login. Nothing downstream can tell. |
| 3 | **Corrupts `CrudAttribution`** | See below — this is the one that damages data, not just security. |
| 4 | Applies to every account | Including `system_owner`. It is not scoped to clients. |
| 5 | Skips phone verification | The Twilio `verify` / `check_verify` flow is bypassed entirely. |

**Defect 3 in detail.** `CrudAttribution` validates `created_by_id` on create and `updated_by_id` on update, and `save(user)` stamps whichever applies ([crud_attribution.rb:10-11, 55-64](apps/insgt-api/lib/crud_attribution.rb#L55-L64)). It is deliberate, load-bearing infrastructure — nothing in this system is hard-deleted, so the attribution columns *are* the history. When support impersonates a client and writes anything, the row records the **client** as the actor. The audit trail the codebase carefully maintains records something that did not happen.

---

## 3. What the impersonation token must carry

**Measured, and it changes the plan: `exp` is already enforced.** `AppJwt` calls `JWT.decode(token, user.jwt_secret, 'HS256')` ([app_jwt.rb:27](apps/insgt-api/lib/app_jwt.rb#L27)), whose third positional argument is `verify`. Against the installed `jwt (2.10.2)`:

```
expired token  -> JWT::ExpiredSignature raised   (exp IS enforced by the current call shape)
token with no exp -> decodes fine                (existing long-lived sessions unaffected)
```

So a short-lived impersonation token needs **no change to `AppJwt`'s verification** and cannot regress existing sessions. The `# TODO: How should we handle time based expiry` comment at [app_jwt.rb:23](apps/insgt-api/lib/app_jwt.rb#L23) is stale on that point — expiry works, it is simply never *issued*.

Claims:

```ruby
{
  iss: request.host,
  sub: target_user.api_key,          # unchanged — downstream lookup still works
  act: { sub: actor_user.api_key },  # RFC 8693 actor claim
  exp: 30.minutes.from_now.to_i,
  jti: impersonation.public_id       # ties the token to its audit row
}
```

`sub` stays the target so every existing controller, helper and permission check behaves exactly as it does for that client — which is the entire point of "see what they see". `act` is additive, so any code that ignores it keeps working.

---

## 4. The handoff problem — ops to app

The admin is in insgt-ops (port 4300). The client dashboard is insgt-app (port 4200). **Different origins, different `localStorage`**, and in production insgt-app is S3 + CloudFront while the API is Heroku — so a shared parent-domain cookie is not available.

Rejected: putting the JWT in a query string. It lands in browser history, `Referer` headers, and CloudFront/Heroku access logs. A credential in a URL is a credential in a logfile.

**Use a one-time exchange code**, the OAuth authorization-code shape:

```
ops  ──POST /impersonations (admin JWT, target + reason)──▶  api
     ◀──{ code, expiresAt }───────────────────────────────
ops opens  https://<app-host>/impersonate?code=<code>
app  ──POST /impersonations/redeem { code }──────────────▶  api
     ◀──{ jwt, actor, target, expiresAt }──────────────────
```

The code is single-use, digest-stored, and expires in 60 seconds. Redeeming it marks the audit row. Redemption needs no auth because the code *is* the credential — and a leaked code is worthless after one use or one minute.

---

## 5. The audit record

One table, which doubles as the audit trail:

```ruby
create_table :impersonations do |t|
  t.references :actor_user,  null: false, foreign_key: { to_table: :users }
  t.references :target_user, null: false, foreign_key: { to_table: :users }
  t.string   :exchange_code_digest, null: false   # SHA-256, never the raw code
  t.datetime :code_expires_at,      null: false
  t.datetime :redeemed_at
  t.datetime :session_expires_at
  t.string   :reason,               null: false
  t.string   :actor_ip
  t.integer  :status_type,          null: false, default: 1
  t.integer  :created_by_id, :updated_by_id
  t.timestamps
end
add_index :impersonations, :exchange_code_digest, unique: true
```

`reason` is `null: false` on purpose — a free-text note costs the admin three seconds and is the difference between an audit log and a list of timestamps.

`status_type` plus the attribution columns follow the repo-wide convention; nothing is hard-deleted and `ApplicationRecord` provides `scope :active`.

Migrations are guarded by `strong_migrations`. A new table with FKs is safe; no `safety_assured` block should be needed.

---

## 6. Read-only for v1

**Reject non-GET requests when `act` is present.** One rule in `ApplicationController`, and it dissolves defect 3 entirely — an impersonated session cannot write, so it cannot mis-attribute.

It also matches the stated need exactly: *"see exactly what they are seeing."* Seeing is reading.

The cost is that any client-app flow which POSTs during normal browsing (cart operations are the likely case — [cart-index.page.ts:171](apps/insgt-app/src/app/cart/index/cart-index.page.ts#L171) writes a cart token) will fail while impersonating. That failure is **visible and diagnosable**, which is the right side to err on. If read-write is needed later, the upgrade is to thread the actor into `save(user)` so writes attribute to the admin — the `act` claim already carries what that needs.

---

## 7. API changes — `insgt-api`

| File | Change |
|---|---|
| `db/migrate/*_create_impersonations.rb` | New table per §5. |
| `app/models/impersonation.rb` | New. Validations, `scope :redeemable`, `#redeem!`. |
| `app/services/impersonation_service.rb` | New. Issues and redeems; owns code generation and the privilege guard. |
| `app/controllers/impersonations_controller.rb` | New. Two actions, thin. |
| [application_controller.rb](apps/insgt-api/app/controllers/application_controller.rb) | `impersonated?`, `acting_user`, and the read-only before_action. |
| [app_jwt.rb](apps/insgt-api/lib/app_jwt.rb) | Read `act` alongside `sub`; expose the actor. No verification change (§3). |
| [sessions_controller.rb](apps/insgt-api/app/controllers/sessions_controller.rb), [users_controller.rb](apps/insgt-api/app/controllers/users_controller.rb) | Consolidate the duplicated `jwt_request_options` / `find_jwt_token` first, then remove the bypass. |
| `config/routes.rb` | `resources :impersonations, only: %i[create]` + a `redeem` collection route. |
| `app/views/impersonations/*.json.jbuilder` | Response shapes; keys camelize automatically. |

Per the `insgt-api` skill: business logic goes in the service, the controller stays thin, and `ImpersonationService` opens with an `ARCHITECTURE NOTES` block covering why the code is digest-stored, why `sub` remains the target, and why v1 is read-only.

**Two guards the service owns, both non-obvious:**

- **Never impersonate a privileged account.** Reject when the target holds `system_owner` or `system_admin`. Without this, impersonation is a privilege-escalation path rather than a support tool.
- **Only `system_owner` and `system_admin` may impersonate**, via the existing `authorize_for` before_action.

---

## 8. `insgt-ops` changes

The trigger: a "View as client" action on the account/user detail view, prompting for `reason`, then opening the app URL returned by the API.

⚠️ **This repo has two coexisting conventions and the right one depends on where the button lands.** `src/app/accounts/` is legacy NgModule (`account.module.ts`, `account-routing.module.ts`); `src/app/features/users/` is modern standalone (`users.routes.ts`, `data-access/`). Load the `insgt-ops-angular-developer` skill and follow whichever pattern hosts the button — do not import the other repo's conventions.

Token handling already exists at [auth.service.ts:19,56](apps/insgt-ops/src/app/core/auth/auth.service.ts#L19). **Ops keeps its own admin session untouched** — it never holds the impersonation token; it only requests a code and opens a URL.

*Marked ESTIMATED: I did not read the account detail components, so the exact host component for the button is unconfirmed.*

---

## 9. `insgt-app` changes

**Entry point.** [app.component.ts:153-154](apps/insgt-app/src/app/app.component.ts#L153-L154) reads the token from storage on boot:

```typescript
private setJwtToken(): void {
  const jwtToken = this.storage.getItem(env.jwt.tokenKey);
```

An `/impersonate` route redeems `?code=` before this runs, stores the returned JWT under the existing `env.jwt.tokenKey`, then routes to the dashboard. Persistence already flows through [session-manager.service.ts:70](apps/insgt-app/src/app/sessions/store/session-manager.service.ts#L70).

**Banner — required, not polish.** [app.component.html:1-2](apps/insgt-app/src/app/app.component.html#L1-L2) opens with `mat-sidenav-container` gated on `sessionFacade.authenticated$`. A persistent bar above it showing *"Viewing as {{ client }} — read-only, expires {{ time }}"* plus an exit control. Without it someone will forget which account they are in; with read-only writes failing silently-looking, that confusion is guaranteed.

**Storage collision.** Impersonating in the same browser profile overwrites the admin's own client-app session under the same `tokenKey`. Either use a distinct key for impersonated sessions, or document "use a private window." *Marked ESTIMATED — needs a decision once the exit flow is designed.*

---

## 10. Retiring `ACCOUNT_PASSWORD`

It has **two** consumers, and both must move first:

1. Support impersonation — replaced by this plan.
2. Cypress login in insgt-ops and insgt-photographers, where eight users in `cypress.env.json` currently hold the bypass value as their password.

For (2), the seeded Cypress users get **real per-user passwords**, and [cypress_users.rake](apps/insgt-api/lib/tasks/cypress_users.rake) generates and prints one rather than reading `ENV['ACCOUNT_PASSWORD']`. That removes the coupling where rotating a production credential breaks e2e in two repos.

Only once both are done does the `unless create_params[:password] == ENV['ACCOUNT_PASSWORD']` branch get deleted and the variable removed from Heroku config.

**Rotation is still required regardless.** The value is in git history in two repos. Removing it from `HEAD` does not revoke it.

---

## Decisions

| # | Decision |
|---|---|
| D1 | `sub` stays the **target** user; the actor rides in `act`. Existing permission code is untouched. |
| D2 | Impersonation tokens carry `exp` of 30 minutes. Enforced today with no `AppJwt` change (§3, measured). |
| D3 | Handoff is a **one-time exchange code**, never a JWT in a URL. |
| D4 | Code TTL 60 seconds, single use, stored as SHA-256 digest. |
| D5 | `reason` is required and `null: false`. |
| D6 | v1 impersonated sessions are **read-only**: reject non-GET when `act` is present. |
| D7 | Only `system_owner` / `system_admin` may impersonate. |
| D8 | Targets holding `system_owner` / `system_admin` may **not** be impersonated. |
| D9 | The `impersonations` table is the audit trail; no separate log. |
| D10 | Consolidate the duplicated `jwt_request_options` **before** adding claims. |
| D11 | Ops never holds an impersonation token — it requests a code and opens a URL. |
| D12 | The banner ships in the same release as the feature, not after. |
| D13 | `ACCOUNT_PASSWORD` is deleted only after Cypress moves to real passwords. |
| D14 | `ACCOUNT_PASSWORD` and the CRMLS RETS password are rotated regardless — both are in git history. |

---

## Implementation

| # | Repo | Concern | Verify | Deliberate break |
|---|---|---|---|---|
| 1 | api | Consolidate `jwt_request_options` / `find_jwt_token` into one place | Existing login specs pass unchanged | Change the claim in the shared helper → both `/sessions` and `/users` tokens change together |
| 2 | api | `impersonations` migration + model | `rails db:migrate` clean under strong_migrations; `Impersonation.active` works | Drop the unique index on `exchange_code_digest` → duplicate-code spec fails |
| 3 | api | `ImpersonationService` — issue, redeem, both guards | Request specs for D7 and D8 | Remove the D8 guard → "cannot impersonate an admin" spec fails |
| 4 | api | `POST /impersonations`, `POST /impersonations/redeem` | 401 without admin JWT; 422 on reused code | Reuse a redeemed code → expect 422 |
| 5 | api | `act` in `AppJwt`; read-only before_action | A `POST` with an `act` token returns 403 | Remove the guard → the read-only spec fails |
| 6 | ops | "View as client" action + reason prompt | Cypress: admin clicks through, lands in app | Strip the reason field → API returns 422 |
| 7 | app | `/impersonate` route redeeming `?code=` | Cypress: code redeems, dashboard renders as client | Redeem twice → second attempt refused |
| 8 | app | Persistent banner + exit | Cypress asserts the banner is present | Remove `act` from the token → banner disappears |
| 9 | api | Cypress users get real passwords | e2e green in ops and photographers **without** `ACCOUNT_PASSWORD` | Revert the rake task → e2e still passes only because of the bypass, proving the coupling |
| 10 | api | Delete the bypass branch; drop the Heroku var | Login with the old bypass value → 422 | This step *is* the break |

### Recommended first slice — read-only impersonation, end to end

**Includes:** steps 1–5, 7, 8. A working audited read-only "view as" reachable by pasting a code, plus the banner.

**Defers:** step 6 (the ops button — the flow is provable with a hand-issued code) and steps 9–10 (retiring `ACCOUNT_PASSWORD`, which is gated on Cypress).

**Deliberate break:** issue a token, wait out the 30-minute `exp`, and confirm the next request 401s. If it does not, D2's measured premise is wrong and everything downstream of it needs revisiting.

---

## Testing

RSpec for all new work — `test/` is legacy and never extended ([insgt-api/CLAUDE.md](apps/insgt-api/CLAUDE.md)). `spec/support/crud_attribution.rb` inserts User ID 1 by raw SQL before the suite, so factories work; mirror existing factory traits.

Request specs to write:

- issue requires an admin JWT (D7); non-admin gets 401
- issuing against a `system_admin` target is refused (D8)
- redeem returns a JWT whose `act.sub` is the actor's `api_key` and whose `sub` is the target's
- a redeemed code cannot be redeemed twice
- an expired code cannot be redeemed
- a `POST` carrying an `act` token is refused (D6)
- a token past `exp` is refused (D2)
- **a normal login token still has no `act` and still works** — the regression guard for step 1

Assert camelCase response keys, per the `insgt-api` skill §6.

Cypress covers the ops → app journey and the banner; component and user-flow testing is Cypress-only in these repos.

---

## Verification

```bash
# API, from apps/insgt-api
bundle exec rspec spec/requests/impersonations_spec.rb
bundle exec rspec spec/requests/sessions_spec.rb     # step 1 regression

# Prove exp is enforced end to end (D2)
#   issue a token with exp 10.seconds.from_now, sleep 15, expect 401

# Prove the bypass is gone (step 10)
#   POST /sessions with a known user's email and the old ACCOUNT_PASSWORD -> 422

# Front ends
cd apps/insgt-ops && xvfb-run npx cypress run --spec 'cypress/e2e/impersonation.cy.ts'
cd apps/insgt-app && xvfb-run npx cypress run --spec 'cypress/e2e/impersonation.cy.ts'
```

Manual smoke: impersonate a client, confirm the dashboard matches what they describe, confirm the banner is visible, confirm a write attempt is refused, confirm the session dies at 30 minutes, then confirm the `impersonations` row records actor, target, reason and timestamps.

---

## Non-goals

- **Not** adding `exp` to normal login sessions. Worth doing, unrelated, and it would log everyone out. The stale TODO at [app_jwt.rb:23](apps/insgt-api/lib/app_jwt.rb#L23) stays.
- **Not** pinning the JWT algorithm. [app_jwt.rb:27](apps/insgt-api/lib/app_jwt.rb#L27) passes `'HS256'` as the `verify` positional rather than via `algorithm:`. Probably benign given per-user secrets, but it is a separate review with its own blast radius. *ESTIMATED — not tested.*
- **Not** read-write impersonation (D6).
- **Not** purging the leaked credentials from git history. Rotation is the fix (D14); history rewriting across two repos is its own project.
- **Not** touching the Twilio verification flow.
