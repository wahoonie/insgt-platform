# CLAUDE.md

Keep your replies exteremely concise and focus on conveying ht ekey information. No unnecessary fluff, no long code snippets.

Whenever working with any third-party library or something similar, you MUST look up the official documentation to ensure you are working with up-to-date information.
Use the DocsExplorer subagent for efficient documentation lookup.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository

## Project Overview

InsightPhotos is a California real estate photography platform. Core promise: "Shoot Today. Live Tomorrow" — next-day media delivery. The codebase is a **polyrepo** (13 independent projects, each with its own git repo) organized under `/workspace/apps/` and `/workspace/functions/`.

AB 723 (California BPC § 10140.8, effective Jan 1, 2026) is a key compliance driver. The Photo/UnalteredPhoto relationship is the single source of truth for disclosure requirements. UnalteredPhoto is NOT the raw camera file — it's fully processed minus material alterations (sky replacement, object removal, virtual staging). Standard adjustments (HDR, exposure, white balance) never trigger AB 723.

## Repository Structure

### Apps (`/workspace/apps/`)

Services run on the host, not in the container. Claude Code should use host.docker.internal to reach running services.

| App | Stack | Port | Purpose |
|-----|-------|------|---------|
| **insgt-api** | Rails 7.2, PostgreSQL, Sidekiq/Redis | 3000 | Central REST API (Heroku migrating to Render.com) |
| **insgt-app** | Angular 21, NgRx, Material, Tailwind | 4200 | Client/agent dashboard PWA (S3+CloudFront) |
| **insgt-photographers** | Angular 20, NgRx, Material, Tailwind | 4400 | Photographer admin app (S3+CloudFront) |
| **insgt-ops** | Angular 21, NgRx, Material, Tailwind | 4300 | Operations dashboard (S3+CloudFront) |
| **insgt-disclosure-gallery** | Angular 21, DaisyUI, Tailwind 4 | 4500 | AB 723 disclosure page (Render) |
| **insgt-galleries** | Rails 7.1, Tailwind | 3001 | Public photo preview gallery (Render) |
| **insgt-virtual-tour** | Rails 8.0, Tailwind | 3001 | MLS virtual tour viewer (Render) |

### Functions (`/workspace/functions/`) — AWS Lambda

| Function | Purpose |
|----------|---------|
| **insgt-import** | Photo import + ZIP extraction (Sharp, Yauzl) |
| **insgt-order-archiver** | Order archive packaging |
| **insgt-photographer-uploader** | Upload management + SendGrid notifications |
| **insgt-raw-archiver** | Raw image archival |
| **insgt-resource-downloader** | Image download + resizing (Sharp) |
| **insgt-site-sls** | Marketing website (Eleventy + Serverless Framework) |

## Common Commands

### Angular Apps (insgt-app, insgt-photographers, insgt-ops, insgt-disclosure-gallery)
```bash
npm install                    # Install dependencies
ng serve --host 0.0.0.0       # Dev server (see port table above)
ng build                       # Development build
npm run build:prod             # Production build (insgt-app, insgt-photographers, insgt-ops)
ng test                        # Unit tests (Karma/Jasmine)
ng lint                        # ESLint
cypress run                    # E2E tests headless
cypress open                   # E2E tests interactive
```

### Rails Web Apps (insgt-galleries, insgt-virtual-tour)
```bash
rails s --port 3001            # Start server
rails tailwindcss:watch        # Watch CSS changes
./bin/render-build.sh          # Production build (Render.com)
```

### Marketing Site (`/workspace/functions/insgt-site-sls`)
```bash
npm start                      # Dev server with Tailwind watch
npm run build                  # Production build (Eleventy)
```

## Data Model

**Order** is the central entity with parent/child relationships: parent = overall job, children = service-specific assignments per photographer (interiors, aerials, twilight). Orders produce Photos, Videos, Matterports, 3D Tours, Floor Plans.

**Photo → UnalteredPhoto** (optional): Presence of UnalteredPhoto means the photo has material alterations requiring AB 723 disclosure. This relationship drives all compliance UI across apps.

**Listing**: Optional entity combining order + children with MLS API data. Creates public virtual tour URL.

**Accounts**: Organizing entity for users. Internal team (admins, photographers, processors) and customers (agents with teams). Users can belong to multiple accounts.

## Architecture Documentation

Detailed docs live in `/workspace/docs/`:
- `overview.md` — system overview, user types, order lifecycle, design principles
- `data-model.md` — entity relationships and compliance model
- `compliance/ab-723.md` — full AB 723 requirements and InsightPhotos implementation
- `decisions/` — architecture decision records
- `services/` — per-service documentation (partially complete)

## Angular Conventions (All Angular Apps)

- **Standalone components** (default — do NOT set `standalone: true` explicitly in Angular 20+)
- **Signals over RxJS** — use `signal()`, `computed()`, `effect()` for reactivity
- **NgRx SignalStore** for local/global state; Redux-style global store only for event-based scenarios
- **OnPush change detection** on all components
- **Native control flow**: `@if`, `@for`, `@switch` — NOT `*ngIf`, `*ngFor`, `*ngSwitch`
- **`inject()`** over constructor injection
- **`input()`/`output()` functions** (not decorators) in insgt-disclosure-gallery
- **`host` property** instead of `@HostBinding`/`@HostListener` in insgt-disclosure-gallery
- **Accessibility**: WCAG AA minimum, must pass AXE checks
- **File limits**: max 400 lines per file, 75 lines per function
- **NgOptimizedImage** for image elements
- **Conventional Commits**: `feat:`, `fix:`, `docs:`, `chore:` — under 60 characters

## AB 723 Compliance Language

Use disclosure-focused terminology, never "original"/"edited":
- Unaltered photos: "No Disclosures Required"
- Altered photos with counterparts: "MLS Ready — Disclosures Included"
- Progressive disclosure: hide compliance UI when order has no altered photos

## CI/CD

- **insgt-photographers**: GitHub Actions runs Cypress on push/PR to main/develop
- **insgt-galleries, insgt-virtual-tour, insgt-disclosure-gallery**: Render.com auto-deploys from git
- **Angular apps** (insgt-app, insgt-ops): Manual deployment — build → upload to S3 → invalidate CloudFront
- **insgt-api**: Heroku (migration to Render.com planned)
- **Lambda functions**: Direct deployment via Serverless Framework

## Known Technical Debt

- API migration from Heroku to Render.com pending
- Angular apps need automated deployment pipeline (currently manual S3 upload)
- insgt-galleries still Rails (Angular migration considered)
- Public ID strategy (token field) needs cleanup across repos (see `decisions/001-public-id-strategy.md`)
- Service documentation in `/workspace/docs/services/` mostly stubs
