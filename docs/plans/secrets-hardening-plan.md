# Secrets Hardening Plan — Insight Photos

**Goal:** Reduce exposure to environment-variable / secret-store compromises (e.g. the Trigger.dev incident, Nov 1 2026) without disrupting the Rails/Ruby/Postgres/Heroku upgrade path or the Render migration.

**Principles**
- A breach of a platform's env store should yield nothing usable. Values live somewhere else (SSM), and access comes from workload identity (OIDC), not static keys.
- Limit blast radius: every secret is scoped to the minimum it needs.
- Detect early: canaries in every secret store, alerting to your phone.
- Don't mix secret-loading changes into upgrade soak periods. One variable changes at a time.
- Rejected approach: "encrypt env vars, hard-code the decryption key in code." It only helps against env-store breaches, makes repo/CI breaches worse, and does nothing against runtime (dependency) compromise.

---

## Phase 0 — Now, in parallel with the upgrades (config only, no app code)

Do these during the 1–2 day soak windows. None of them touch application code, so they don't interfere with upgrade debugging.

### 0.1 Set up ntfy for phone alerts (~15 min)
- [x] Install the **ntfy** app (iOS / Android).
- [x] Choose a long random topic name, e.g. `insgt-canary-<16+ random chars>`. On public ntfy.sh, anyone who knows the topic can read and post, so **treat the topic name like a password**.
- [x] Subscribe to the topic in the app.
- [x] iPhone: allow ntfy **time-sensitive notifications** so alerts get through Focus modes.
- [x] Test from a terminal:
  ```bash
  curl -d "ntfy test" "https://ntfy.sh/<your-topic>?priority=urgent&title=Canary%20test"
  ```
- [x] Confirm the notification arrives on your phone.

### 0.2 Deploy hosted canary tokens — canarytokens.org (~30–45 min)
Free, no account needed. Use **one token per location** so an alert identifies exactly which store leaked.

**Locations**
- [ ] Each Heroku app's config vars
- [ ] Each existing Render service (or environment group)
- [ ] GitHub Actions secrets for each repo that has secrets
- [ ] A `.env` file on your laptop (catches malicious npm packages or gems that read local files)

**For each token**
- [ ] Token type: **AWS API key**
- [ ] Email: your alert email (keep it as a backup channel)
- [ ] Webhook: `https://ntfy.sh/<your-topic>?priority=urgent&title=Canary%20triggered`
- [ ] Memo naming the exact location, e.g. `heroku insgt-api prod`, `render <service> prod`, `github insgt-ops actions`, `laptop .env`
- [ ] Store it under a **non-colliding name**. Never use `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, because the AWS SDK reads those automatically. Use e.g. `AWS_BACKUP_ACCESS_KEY_ID` / `AWS_BACKUP_SECRET_ACCESS_KEY` or `LEGACY_S3_ACCESS_KEY`.
- [ ] Grep both codebases for the chosen name to confirm nothing reads it.
- [ ] **Test it:** use the canary key once, e.g.
  ```bash
  AWS_ACCESS_KEY_ID=<canary> AWS_SECRET_ACCESS_KEY=<canary> aws sts get-caller-identity
  ```
  Confirm the ntfy alert and email arrive with the correct memo.
- [ ] Record each token (location, memo, env var name) in the secret inventory (0.3).

**Known limitation:** hosted tokens report back to Thinkst's infrastructure, so a careful attacker may recognize and avoid them. Step 0.7 closes this gap.

### 0.3 Build the secret inventory
For every secret, record:

| Secret | Where it lives (Heroku app / Render service / GitHub / laptop) | What it can do (scope) | Who can read it | How to rotate | Last rotated |
|---|---|---|---|---|---|

- [ ] Include canary entries so they aren't mistaken for real credentials later.
- [ ] Keep this file outside the repo (e.g. a password manager note).

### 0.4 Narrow scope and rotate
- [ ] **AWS:** remove any admin or broad-permission AWS keys from Heroku/Render env. Replace each with a key scoped to specific actions and resources (e.g. a single S3 bucket prefix).
- [ ] **Stripe:** replace the full secret key with **restricted keys** scoped to what each service actually calls.
- [ ] Use a separate key per vendor and per environment (prod / staging), so a leak in one place doesn't reach others.
- [ ] Rotate anything long-lived or of unknown age while you're in there.
- [ ] Before rotating, review usage logs (Stripe dashboard, CloudTrail, email-provider send logs) for anything unexpected.

### 0.5 Harden the accounts that hold the secrets
- [ ] Hardware MFA (security key) on AWS (root + admin), Heroku, Render, GitHub, Stripe.
- [ ] Remove long-lived admin access keys from AWS.
- [ ] Prune Heroku and Render collaborators and GitHub org members to those who need access.
- [ ] Store break-glass material (AWS root credentials, MFA recovery codes) **offline**, outside AWS.

### 0.6 Supply-chain hygiene (runtime compromise)
- [ ] Commit lockfiles and use `npm ci` (Angular) and `bundle install` against `Gemfile.lock` (Rails).
- [ ] Set `ignore-scripts` for npm where feasible.
- [ ] Add a minimum release age / cooldown for new dependency versions (Renovate or Dependabot cooldown; pnpm `minimumReleaseAge` if applicable).
- [ ] Pin GitHub Actions to commit SHAs.
- [ ] Keep production secrets off the laptop and out of CI jobs that don't need them.

### 0.7 (Optional, stronger) Self-hosted IAM canary
A canary in your own AWS account can't be fingerprinted as a canary.
- [ ] Create an IAM user with **no permissions**; generate access keys.
- [ ] Ensure CloudTrail is enabled (management events).
- [ ] EventBridge rule matching API calls by that user → **SNS topic**.
- [ ] SNS **HTTPS subscription** to `https://ntfy.sh/<your-topic>`. The SNS subscription-confirmation message arrives as an ntfy notification; open its `SubscribeURL` to confirm.
- [ ] Plant the keys (non-colliding names) alongside or instead of the hosted tokens.
- [ ] Test with `aws sts get-caller-identity` and confirm the alert. Note: not every AWS API call is logged in CloudTrail, so keep the hosted tokens too.

---

## Phases 1–3 — Upgrades (keep the 1–2 day soaks)

**Do not change how secrets load during these phases.**

1. [x] **Rails → 8.1.4**, then soak.
2. [ ] **Ruby 3 → Ruby 4**, then soak. If currently on Ruby 3.2 or older, it's already end-of-life, so this upgrade is itself security work.
3. [ ] **Heroku Postgres 15 → newer major version**, then soak.

Phase 0 work continues in the soak windows.

---

## Phase 4 — Heroku stack upgrade, then the SSM loader

1. [ ] **Upgrade the Heroku stack**, then soak until stable.
2. [ ] **Move secret values into AWS SSM Parameter Store** (SecureString, customer-managed KMS key):
   - [ ] Path convention: `/insgt/<env>/<service>/<NAME>` (e.g. `/insgt/prod/api/STRIPE_SECRET_KEY`).
   - [ ] Separate prod and non-prod, ideally separate AWS accounts via AWS Organizations.
   - [ ] **Leave `DATABASE_URL` out.** It's platform-managed and changes with the Render move.
3. [ ] **Build the boot-time loader** (add `aws-sdk-ssm` now, after Ruby 4):
   - [ ] Fetch once at boot with `GetParametersByPath` and cache in memory. Never fetch per request; SSM has throughput limits, and a running process should survive a brief SSM outage.
   - [ ] Load early, in `config/application.rb` before anything reads ENV, and before Puma forks if preloading. This also covers release phase, one-off dynos, and rake tasks.
   - [ ] Use the **AWS SDK default credential chain** so the code works unchanged on Heroku (static env key) and on Render (OIDC via `AWS_WEB_IDENTITY_TOKEN_FILE`).
   - [ ] Asset precompile must not need real secrets (`SECRET_KEY_BASE_DUMMY=1`).
4. [ ] **Heroku bootstrap key** (unavoidable on Heroku; dynos can't assume IAM roles):
   - [ ] IAM policy: only `ssm:GetParametersByPath` on `/insgt/prod/api/*` plus `kms:Decrypt` on that one KMS key.
   - [ ] Two separate controls: an IAM path-scoped policy **and** a KMS key policy.
   - [ ] CloudTrail alerts on `GetParameter*` / `Decrypt` from unexpected principals or IPs.
5. [ ] Remove the now-migrated plaintext secrets from Heroku config vars.

**What this buys on Heroku:** one narrowly scoped key in the env store instead of many secrets, one place to rotate, instant revocation, and a full read audit trail. That key can still read its parameters if leaked, so the full benefit comes in Phase 5.

---

## Phase 5 — Migrate to Render with OIDC (removes the static key)

Render-to-AWS OIDC is GA as of July 2026, for **Pro workspaces and higher**. Confirm your plan tier.

1. [ ] Add Render as an **OIDC identity provider** in AWS IAM (`oidc.render.com/<workspace-id>`).
2. [ ] Create an IAM role per service with the same SSM/KMS permissions as the Heroku bootstrap key.
3. [ ] Trust policy: restrict the `sub` condition to the **specific service ID**, not the whole workspace:
   `workspace:*:environment:*:service:srv-<id>`
4. [ ] On the Render service, set **only** `AWS_ROLE_ARN` (plus the SSM path, if configured via env). Render sets `AWS_WEB_IDENTITY_TOKEN_FILE` automatically; don't set it manually.
5. [ ] Deploy. The loader picks up OIDC credentials with no code change.
6. [ ] Cut over traffic, then **delete the Heroku bootstrap key** in IAM.
7. [ ] Move canaries to the new Render services; retire the Heroku ones when the apps are decommissioned.

**Why SSM before the move:** without it, migrating means copying every secret into Render's env store while they still sit in Heroku's, which doubles exposure during the overlap. With it, you copy roughly two values, and both platforms read one source of truth.

*Optional:* existing Render services that already need AWS access can adopt OIDC at any time. They don't have to wait for the Heroku apps.

---

## Incident response — if a canary fires or a vendor reports a breach

Do this **the same day, regardless of where you are in the upgrade sequence**. Rotation is a config change and independent of the upgrades.

1. [ ] Identify the location from the canary memo (or the vendor notice).
2. [ ] Rotate **every** real secret stored in that location, using the inventory (0.3).
3. [ ] Review usage logs for each rotated secret (CloudTrail, Stripe, email provider, etc.) for the period before rotation.
4. [ ] Revoke any sessions or tokens issued by the affected platform; review collaborators and audit logs there.
5. [ ] Replace the triggered canary with a new token.
6. [ ] Note what happened and what changed in the inventory.

---

## Summary sequence

| # | Step | Touches app code? | When |
|---|---|---|---|
| 0.1 | ntfy alerts | No | Now |
| 0.2 | Hosted canary tokens | No | Now |
| 0.3 | Secret inventory | No | Now |
| 0.4 | Narrow scope + rotate | No | Soak windows |
| 0.5 | Account hardening / MFA | No | Soak windows |
| 0.6 | Supply-chain hygiene | Config only | Soak windows |
| 0.7 | Self-hosted IAM canary (optional) | No | Soak windows |
| 1 | Rails 8.1.4 | Yes | Soak 1–2 days |
| 2 | Ruby 4 | Yes | Soak 1–2 days |
| 3 | Postgres upgrade | No | Soak |
| 4 | Heroku stack upgrade → SSM loader | Yes | After stable |
| 5 | Render migration with OIDC | Config | After Phase 4 |