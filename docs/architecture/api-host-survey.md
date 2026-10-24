# Survey: references to the API's Heroku hostname across insgt-platform

**Old:** `https://insgtapi.herokuapp.com` **New:** `https://api.insightphotos.net`
**Date:** 2026-10-23. Survey only: nothing was edited, committed or branched.
**Scope walked:** every directory under `/workspace`. That covers 15 git repos plus one plain directory. Excluded: `node_modules`, `vendor`, `dist`, `_site`, `.git`, `tmp`, `log`, `coverage`, lockfiles, and `repomix-out/` (generated packs that duplicate the source).

Repos not on the brief's list: `apps/insgt-virtual-tour`, `lib/insgt-ui`, the `insgt-platform` shell itself (`docs/`, `.claude/`, `.devcontainer/`), and `design/insgt-ai-design` (a plain directory, not a git repo). The Lambda repos found are `insgt-import`, `insgt-order-archiver`, `insgt-photographer-uploader`, `insgt-raw-archiver` and `insgt-resource-downloader`. None of the infrastructure formats carry the host: there is no SAM, CDK or Terraform, and neither the GitHub Actions workflow nor the Dockerfile has it. All five Lambdas use the Serverless Framework, so `sam deploy` does not apply. No SSM parameter carries the host: SSM holds only secrets (`prod-insight-rails-jwt`, `sendgrid-ops-transactional`).

---

## 1. Summary

| Repo | A | B | C | What moves them |
|---|---|---|---|---|
| insgt-platform (`docs/`) | 8 lines, 5 files | 1 | 0 | docs-only |
| insgt-api | 4 | 1 | 1 | API deploy (`git push heroku master`) for config and the legacy bundle. `heroku config:set` for `MAILER_URL`. docs-only for the README. Dashboard check for C. |
| insgt-app | 1 | 1 | 0 | rebuild, then manual S3/CloudFront deploy (README: timestamped folder, origin swap, invalidate) |
| insgt-ops | 1 | 1 | 0 | flat-prefix PWA deploy (`npm run deploy:prod`) |
| insgt-photographers | 1 | 1 | 0 | rebuild, then manual S3/CloudFront deploy (README: timestamped folder, origin swap, invalidate) |
| insgt-disclosure-gallery | 2 | 1 | 0 | push to `main` (Render auto-build). docs-only for `CLAUDE.md`. |
| insgt-galleries | 1 | 1 | 0 | Render env var (dashboard click). The A line is an untracked local file. |
| insgt-virtual-tour | 3 | 1 | 0 | Render env var (dashboard click) for B. The A lines are vestigial and move no traffic. |
| insgt-import | 1 (+10 generated) | 1 | 0 | `sls deploy --stage prod` |
| insgt-order-archiver | 1 (+3 generated) | 1 | 0 | `sls deploy --stage prod` |
| insgt-photographer-uploader | 1 (+3 generated) | 1 | 0 | `sls deploy --stage prod` |
| insgt-raw-archiver | 1 | 1 | 0 | `sls deploy --stage prod` (Serverless v3 config, `nodejs14.x`; see Unclear 6) |
| insgt-resource-downloader | 1 (+3 generated) | 1 | 0 | `sls deploy --stage prod` |
| insgt-site-sls | 0 | 0 | 0 | none |
| lib/insgt-ui | 0 | 0 | 0 | none |
| design/insgt-ai-design (not a repo) | 0 | 0 | 0 | none |

A counts lines. B counts variables. "Generated" means untracked `.serverless/` deploy artifacts, which the next `sls deploy` regenerates.

---

## 2. Per repo

### insgt-platform (`docs/`)

**A**
- `docs/runbooks/deploy-account-classification-4-worklist.md:54`: `export API=https://insgtapi.herokuapp.com`. Runbook shell. docs-only.
- `docs/runbooks/deploy-account-classification-6-roi.md:149`: `API=https://insgtapi.herokuapp.com`. Runbook shell. docs-only.
- `docs/runbooks/deploy-credit-card.md:104`: "Confirm `environment.prod.ts` `api.url` is `https://insgtapi.herokuapp.com`". docs-only. If the step is re-run after the ops move, this check fails as written.
- `docs/runbooks/deploy-listing-suppression.md:125, :128, :131`: three smoke-test commands, `curl … https://insgtapi.herokuapp.com/s/listings…`. docs-only.
- `docs/runbooks/deploy-listing-suppression.md:158`: "`environment.prod.ts` still points at `https://insgtapi.herokuapp.com`". A historical statement. docs-only.
- `docs/runbooks/deploy-watermark-removal.md:103`: "`insgtapi.herokuapp.com` is listed on the next line". A historical statement about `config.hosts`. docs-only.

**B:** the shell variable `API`; see §3.
**C:** none.

### insgt-api

Lines already on the new host (`config/application.rb:24`, `config/initializers/cors.rb:33`) are omitted.

**A**
- `config/application.rb:25`: `config.hosts << 'insgtapi.herokuapp.com'`. Boot-time config. Changed by an API deploy. This is the server-side allow entry for the old host.
- `config/initializers/cors.rb:32`: `'https://insgtapi.herokuapp.com',`. Listed as an allowed CORS **origin**, meaning pages served from that host may call the API. Boot-time. Changed by an API deploy.
- `public/ops/scripts/app-cd80e956.js:1`: `angular.module("app").constant("App",{env:{production:!0,api:"https://insgtapi.herokuapp.com"}})`. A build-time artifact: the 2016 AngularJS ops bundle (last commit a749ec59, 2016-04-12).
  - The API still serves it at `<api-host>/ops/`: `bin/rails middleware` lists `ActionDispatch::Static`, railties 7.2.3 defaults `public_file_server.enabled = true`, and `config/environments/production.rb:23` leaves the override commented out.
  - Its source is not in the workspace, so only the minified file can change. Changed by an API deploy.
- `README.md:157`: `heroku config:set MAILER_URL=insgtapi.herokuapp.com --app insgtapi`. docs-only.

**B:** `MAILER_URL`; see §3.

**C**
- `config/routes.rb:4`: `get 'up' => 'rails/health#show'`. `config/environments/production.rb:48` and `:99` exempt `/up` from the SSL redirect and from host authorization. Something external polls it, but nothing in the repo says what. Check that monitor's dashboard (§4).

**Checked, no hit**
- No inbound webhook or callback route exists for Stripe, Twilio or SendGrid, in `config/routes.rb` or in any controller.
  - Stripe is outbound only (`config/initializers/stripe.rb`, `app/models/concerns/transaction_stripe.rb`).
  - Twilio SMS polls message status (`app/models/notification.rb:203`) rather than using a status callback. Twilio Verify (`lib/auth.rb`) is outbound.
  - SendGrid is SMTP only (`config/environments/production.rb:104`).
- The API hands no callback URL to the Lambdas it calls (`lib/order_import.rb`, `app/workers/photo_resize_worker.rb`, `app/models/concerns/order_zip.rb:118`). Request bodies carry IDs only.
- JWTs are minted with `iss: request.host` (`app/controllers/sessions_controller.rb:105`, `app/controllers/users_controller.rb:192`). `lib/app_jwt.rb` never validates `iss`, so a token minted on either host works on the other.
- `verify_unauthenticated_request` (`app/controllers/application_controller.rb:133-142`) compares `request.host`, but its result never halts a request.
- 29 more lines match `insgtapi` only as the Heroku **app name** (`--app insgtapi`): `README.md` ×28 and `config/initializers/strong_migrations.rb:12` ×1. They are not host fragments; see Verification.

### insgt-app

**A**
- `src/environments/environment.prod.ts:58`: `url: 'https://insgtapi.herokuapp.com',`. Build-time: `angular.json` fileReplacements swap the file in, and `production` is the default configuration.
  - Changed by a rebuild plus the manual deploy in `README.md:45-53` (timestamped folder under `insgt-apps/dashboard-pwa`, origin swap, invalidate `EH3XX4N13ZUTM`).
  - Clients running a build cached by the service worker keep the old value until the worker updates.

**B:** `env.api.url`; see §3.
**C:** none.

### insgt-ops

**A**
- `src/environments/environment.prod.ts:54`: `url: 'https://insgtapi.herokuapp.com',`. Build-time. Changed by the flat-prefix PWA deploy: `npm run deploy:prod` runs `scripts/deploy.sh` (bucket prefix `insgt-apps/ops/`, distribution `E2GJ3L3JH70697`). Has a service worker.

**B:** `env.api.url`.
**C:** none.

### insgt-photographers

**A**
- `src/environments/environment.prod.ts:11`: `url: 'https://insgtapi.herokuapp.com',`. Build-time. Changed by a rebuild plus the manual deploy in `README.md:47-55` (timestamped folder under `insgt-apps/photogs/`, origin swap, invalidate `E2KY09NFQ8WLK0`). Has a service worker.

**B:** `env.api.url`.
**C:** none. `.github/workflows/cypress.yml` runs against `localhost:4400` only.

### insgt-disclosure-gallery

**A**
- `src/environments/environment.prod.ts:6`: `apiUrl: 'https://insgtapi.herokuapp.com',`. Build-time. Changed by a push to `main`: Render runs `npm run build`, whose default configuration is `production`.
- `CLAUDE.md:100`: "`environment.prod.ts` points to `insgtapi.herokuapp.com`". docs-only.

**B:** `env.apiUrl`.
**C:** none.

### insgt-galleries

**A**
- `.env:1`: `#INSIGHT_API_ENDPOINT=https://insgtapi.herokuapp.com`. The line is commented out, and `.env` is untracked (`git ls-files` does not list it). Production never reads it. Local edit only.

**B:** `INSIGHT_API_ENDPOINT`.
**C:** none.

### insgt-virtual-tour

**A** (all vestigial: no request is built from them)
- `config/routes.rb:11`: `get ':address/b/pano/:id/:order_url_id' => 'panos#show', branded: true, api_subdomain: 'insgtapi'`
- `config/routes.rb:12`: the same route with `branded: false`.
- `lib/insight_photo.rb:124`: `@api_subdomain_allowlist ||= %w{insgtapi insgtnvapi}`

These are runtime code, but nothing builds a URL from them:
- `get_order_url` (`lib/insight_photo.rb:87-94`) ignores `options[:api_subdomain]`.
- `listing_exists?` (`:96-103`) loops over the allowlist without using the loop variable.

Every request URL comes from `INSIGHT_API_ENDPOINT`, so editing these lines moves no traffic. If they are edited, Render auto-deploys on push.

**B:** `INSIGHT_API_ENDPOINT`.
**C:** none.

### Lambdas (Serverless Framework)

Each repo's `serverless.yml` sets `custom.env.prod.apiEndpoint`. A deploy writes it into the Lambda environment as `API_ENDPOINT`, which the handler reads at runtime. The dev-stage values are ngrok URLs and are out of scope.

| Repo | A (source) | A (generated `.serverless/`, untracked) | Trigger | Changed by |
|---|---|---|---|---|
| insgt-import | `serverless.yml:24` `apiEndpoint: https://insgtapi.herokuapp.com` | ×10: `cloudformation-template-update-stack.json:226`; `serverless-state.json:260, 602, 653`; `meta.json:29, 324, 683, 991, 1317, 1572` | S3 | `sls deploy --stage prod` (`README.md:33`) |
| insgt-order-archiver | `serverless.yml:24` | ×3: `serverless-state.json:633`; `meta.json:29, 1401` | HTTP POST `/zip` | `sls deploy --stage prod` (`README.md:33`) |
| insgt-photographer-uploader | `serverless.yml:22` | ×3: `serverless-state.json:583`; `meta.json:27, 1257` | S3 | `sls deploy --stage prod` (`README.md:32`) |
| insgt-raw-archiver | `serverless.yml:17` | none (never packaged on this machine) | HTTP POST `/zip` | `sls deploy` (`README.md:34`). `frameworkVersion: '3'`, `nodejs14.x`. |
| insgt-resource-downloader | `serverless.yml:24` | ×3: `serverless-state.json:615`; `meta.json:29, 1343` | HTTP `/download` | `sls deploy --stage prod` (`README.md:33`) |

**B:** `API_ENDPOINT` in each repo; see §3.
**C:** none. The API Gateway functions set `cors: true`, which allows any origin and references nothing.

### No hits

- **insgt-site-sls:** builds from S3 JSON (`insgt-site-data`) that the API's `SiteExport` writes. It never calls the API. `SIGN_IN_URL` and `CART_URL` point at `dashboard.insightphotos.net`.
- **lib/insgt-ui:** no API URL and no injection token.
- **design/insgt-ai-design:** a Next.js and Convex app. Its only outbound URL variable, `OTP_ENDPOINT` (`convex/ResendOTP.ts:17`), posts `{email, token, chatId, appName, secretKey}`. No insgt-api route accepts that shape.

---

## 3. Variables map (class B)

| Variable | Repo | Definition | Read sites | Production value source |
|---|---|---|---|---|
| `env.api.url` | insgt-app | `src/environments/environment.prod.ts:58` (dev: `environment.ts:59`) | `core/services/insight-api.service.ts:144`; `shared/api/resource-api.service.refactored.ts:131`; `shared/pipes/order/order-mls-zip-url.pipe.ts:19`; `shared/pipes/order/order-print-zip-url.pipe.ts:19` (all under `src/app/`) | in repo, build-time |
| `env.api.url` | insgt-ops | `src/environments/environment.prod.ts:54` | `shared/api/api.service.ts:143`; `shared/api/resource-api.service.ts:131`; `shared/order.pipe.ts:232`; `floorplans/store/floor-plan-uploader.service.ts:327` | in repo, build-time |
| `env.api.url` | insgt-photographers | `src/environments/environment.prod.ts:11` | `core/services/insight-api.service.ts:135` | in repo, build-time |
| `env.apiUrl` | insgt-disclosure-gallery | `src/environments/environment.prod.ts:6` (typed in `environment.interface.ts:4`) | `src/app/gallery/gallery.service.ts:25`; validated in `environment.validator.ts:15-43` | in repo, build-time |
| `INSIGHT_API_ENDPOINT` | insgt-galleries | runtime env, not in repo (`render.yaml` declares only `RAILS_MASTER_KEY`) | `lib/insight_photo.rb:4` | Render dashboard only |
| `INSIGHT_API_ENDPOINT` | insgt-virtual-tour | runtime env, not in repo. `docs/services/insgt-virtual-tour.md:88` gives the dev value only. | `lib/insight_photo.rb:50, 52, 72, 88, 98` | Render dashboard only |
| `API_ENDPOINT` | insgt-import | `serverless.yml:24` → `:96` | `handler.js:674, 701, 721, 742` (`:740` is a log line) | in repo. The deployed value is visible only in Lambda config. |
| `API_ENDPOINT` | insgt-order-archiver | `serverless.yml:24` → `:86` | `handler.js:187` (`:185` is commented out) | in repo, and Lambda config |
| `API_ENDPOINT` | insgt-photographer-uploader | `serverless.yml:22` → `:83` | `handler.js:298, 310, 324` | in repo, and Lambda config |
| `API_ENDPOINT` | insgt-raw-archiver | `serverless.yml:17` → `:52` | `handler.js:92` | in repo, and Lambda config |
| `API_ENDPOINT` | insgt-resource-downloader | `serverless.yml:24` → `:86` | `handler.js:316` | in repo, and Lambda config |
| `MAILER_URL` | insgt-api | runtime env, Heroku config. `README.md:157` documents it as `insgtapi.herokuapp.com`. | `config/environments/production.rb:102` sets `action_mailer.default_url_options[:host]`. **Nothing consumes it:** no mailer or mailer view uses a route `_url` helper. The only URL in a mailer view is `User#password_reset_url`, built from `DASHBOARD_HOST`, `OPS_APP_HOST` or `PHOTOGS_APP_HOST`. | Heroku config only |
| `API` (shell) | insgt-platform docs | `runbooks/deploy-account-classification-4-worklist.md:54`; `runbooks/deploy-account-classification-6-roi.md:149` | worklist `:56, :57, :170, :171`; roi `:150, :155, :156` | in repo (docs) |

**Not found anywhere:** `ZONE_API`, `API_URL`, `API_HOST`, `API_BASE`, `apiHost`. `baseUrl` appears only as tsconfig `compilerOptions.baseUrl` and as Cypress `baseUrl`, which is a frontend dev URL. Neither carries the API.

**Similar names checked, none of which carry the API:**
- `ZONE_HOST`: the marketing site, used in insgt-api email templates.
- `DASHBOARD_HOST`, `OPS_APP_HOST`, `PHOTOGS_APP_HOST`: frontend hosts.
- `PROPERTY_WEBSITE_HOST`: virtual-tour pages.
- `IMPORT_ENDPOINT`, `ZIP_ORDER_ENDPOINT`, `ZIP_FUNCTION_ENDPOINT`, `PHOTO_RESIZE_ENDPOINT`: calls from the API to Lambdas, the opposite direction.
- insgt-ops `legacyOpsUri`: `https://www.insightphotos.net/ops/#`.

---

## 4. External checklist (class C)

| Third party | What to look for in its dashboard | Route it should point at |
|---|---|---|
| Uptime monitor (none named in any repo) | any check against `https://insgtapi.herokuapp.com/up` | `https://api.insightphotos.net/up` (`config/routes.rb:4`) |
| New Relic (`config/newrelic.yml`, app_name `InsightPhotos.net`; add-on in `README.md:140`) | Synthetics monitors or alert conditions that contain a URL on the old host. APM itself reports by app name, not hostname. | the same path on `api.insightphotos.net` |
| Stripe | Developers → Webhooks: any endpoint on the old host | **none.** insgt-api has no webhook route, so any registered endpoint is already failing. |
| Twilio | each number in `TWILIO_NUMBER`: messaging and voice webhook URLs and status callbacks; Messaging Services; Verify service "Ravelpix" (`lib/auth.rb:7`) | **none.** No inbound route; message status is polled. |
| SendGrid | Settings → Mail Settings → Event Webhook; Inbound Parse | **none.** No receiving route. |
| Zapier, Quo, Front, Honeybadger, OAuth providers | no reference anywhere in the workspace, code or docs. Check each account for webhooks or zaps aimed at the old host. | **none** exists in insgt-api for any of them |

---

## 5. Unclear

1. **Is `/ops/` on the API host still used?** The 2016 bundle is served there and calls the old host. Its source is not in the workspace, so editing the minified file is the only change available. *Resolve:* look for requests to `/ops/` in Heroku or Papertrail logs.
2. **Why is the API's own host an allowed CORS origin (`cors.rb:32`)?** If the entry exists for the legacy `/ops/` page, then `:33` covers the same page when it is served from the new host. *Resolve:* find any caller that sends `Origin: https://insgtapi.herokuapp.com`.
3. **What is `INSIGHT_API_ENDPOINT` set to on Render, for insgt-galleries and insgt-virtual-tour?** Neither repo records it. *Resolve:* Render dashboard → each service → Environment.
4. **Is `MAILER_URL` dead?** No consumer was found. *Resolve:* `heroku config:get MAILER_URL -a insgtapi`, then confirm no gem generates route URLs in mail.
5. **Do the deployed Lambda values match `serverless.yml`?** A console edit would make them differ. *Resolve:* `aws lambda get-function-configuration --function-name <service>-prod-<function> --query Environment.Variables.API_ENDPOINT` for each of the five.
6. **How is insgt-raw-archiver deployed?** It has `frameworkVersion: '3'` (the others are `'4'`), runtime `nodejs14.x`, and no local `.serverless/`. AWS's Lambda runtimes page says console updates to a `nodejs14.x` function are blocked, but CLI and CloudFormation updates stay allowed until 2027-08-31. *Resolve:* find out which Serverless CLI version deploys it and who last did.
7. **Do out-of-workspace Lambdas call the API back?**
   - `IMPORT_ENDPOINT` takes an HTTP POST. The in-workspace insgt-import is S3-triggered only, so this endpoint is a different function.
   - `PHOTO_RESIZE_ENDPOINT` is the "photo resizer"; `huh4oe1geg.execute-api…` also appears in `cors.rb:41`.
   - Whatever backs `ZIP_ORDER_ENDPOINT` and `ZIP_FUNCTION_ENDPOINT`.

   *Resolve:* check each function's environment for an API host.
8. **Are API-hosted links shared outside the apps?** insgt-app (`order-mls-zip-url.pipe.ts:19`, `order-print-zip-url.pipe.ts:19`) and insgt-ops (`order.pipe.ts:232`) render `<api>/orders/<token>.zip?accessToken=…` as links. Any link copied into an email, an MLS listing or a bookmark keeps the old host, and the repo cannot enumerate them.
9. **Are executed runbooks records or reusable templates?** This decides whether the 8 docs A lines change at all. `deploy-credit-card.md:104` asserts the old host as a check.
10. **Do the insgt-app and insgt-photographers READMEs reflect current practice?** Both describe a timestamped folder plus an origin swap. Only insgt-ops has the flat-prefix script.
11. **Is `insgtnvapi` (`insight_photo.rb:124`, the Las Vegas zone) still a running Heroku app?** It is a separate host and outside this survey.

---

## Verification

- **Literal search:** `insgtapi`, case-insensitive, with the exclusions above. GNU grep (`/usr/bin/grep -rIin`) found **286** lines. ripgrep (`rg -i --no-ignore --hidden -uu`) found **286**. Diffing the two `file:line` sets showed them identical. For `insgtapi.herokuapp.com` alone, both tools found **42**.
- **Reconciliation:** 42 host-form lines + 3 host fragments in virtual-tour = **45 class A lines**. The other **241** lines are Heroku app-name uses: docs 212, insgt-api README 28, `strong_migrations.rb` 1. Every one sits in a `heroku …`, `-a insgtapi` or `⬢ insgtapi` context, and none is a host. The custom domain leaves them unchanged.
- **Trap:** in this container the shell's `grep` is a ugrep wrapper with `--ignore-files`. It honours `/workspace/.gitignore` (whose first rule is `*`) and silently skips every app repo; a first pass with it found docs only. Both counted passes bypass the wrapper.
- **Exclusions:** no path in this report is under an excluded directory or is a lockfile; a check of the result set found 0. `.serverless/` is not on the exclusion list, so its 19 lines are reported, grouped as generated. `repomix-out/` holds 42 more matching lines, all copies of source; they are not counted.
- **`.env` files:** both passes searched them. Their contents were otherwise not read; reading insgt-api's `.env` was denied.
- **Variables:** every variable in §3 has at least one read site. The exception is `MAILER_URL`: it is read into config, but nothing consumes it. It is reported, not dropped.
