# insgt-photographers

## Purpose
Photographer-facing PWA for managing shoot schedules — viewing assigned shoots, recording arrival and departure times, viewing order details, and setting availability. Used by contract photographers on mobile devices in the field.

This is **not** the upload app. Photographers upload photos through insgt-app at `/uploads/:orderToken`.

## Public URLs
- Production: https://photogs.insightphotos.net
- Hosting: S3 + CloudFront, manual deploy

## Tech Stack
- Framework: Angular 20, standalone components, NgRx (Redux pattern)
- UI: Angular Material 20, Tailwind CSS 4.1, DaisyUI 5.0, angular-calendar
- Dates: date-fns throughout (**not** moment.js — insgt-ops uses moment; do not mix)
- Icons: Font Awesome Pro via private npm registry

## How It Connects
Reads orders, photos, schedules, and users from insgt-api. Auth is JWT, attached manually in `InsightApiService.httpOptions()` — there are no Angular HTTP interceptors.

Images are served through the CloudFront image handler (`environment.aws.imageHandlerEndpoint`). `PhotoService` picks image dimensions from viewport breakpoints (mobile 736px, tablet 1024px).

The dev environment points at an **ngrok tunnel**, not localhost, so the app can be tested on real mobile devices. `api.url` in `src/environments/environment.ts` must be updated whenever the tunnel changes.

## Key Behaviors

### Viewing the schedule (`/scheduler`)
`SchedulerIndexPage` loads orders assigned to the signed-in photographer for the current date. `SchedulerCalendarComponent` renders day/week/month views via angular-calendar, auto-loading when the date changes and **polling every 30 seconds in production** for near-real-time updates. Polling stops on component destroy.

Clicking an order opens `SchedulerOrderDialog` (full-screen Material dialog) showing property address, contact info with phone/SMS/maps links, service items, notes, and photos. From there a photographer can confirm or decline the shoot, record arrival and departure times, mark whether the agent or owner was present, and add processing notes.

`QueueDialog` shows files already uploaded for the order — read-only, with timestamps.

### Managing availability (`/schedules`)
`ScheduleIndexPage` shows a week calendar of availability blocks in three types: Available (green), Not Available (gray), and Vacation. Clicking a slot creates a block; clicking an existing block edits or deletes it. Repeat patterns supported: daily, weekly on a specific day, weekdays, weekends — with a configurable end date.

### Authentication
Phone number → Twilio SMS or call with a code → code verification → JWT. Email/password is an alternative path. The token is persisted by the `saveToken$` effect via `AppStorageService`; on load, `setJwtToken()` reads it and dispatches `ReadJwtSuccess`. `AuthGuardService` checks token and photographer role on every navigation.

### Upload flow (lives in insgt-app)
The queue dialog's "Upload Files" button navigates to `{host}/uploads/{orderToken}` on insgt-app. For reference, that flow is:

1. insgt-app requests presigned S3 PUT URLs from insgt-api (`POST /orders/:token/raw_photos/upload_url`)
2. Files upload directly to S3, no server pass-through, 5-day URL expiration
3. A `RawPhoto` record is created on completion
4. The photographer clicks "Submit for Processing"
5. Queue metadata is stored in `Order.processing_queue` (JSONB) — this is what the queue dialog reads

The only S3 interaction in insgt-photographers itself is `HeadshotService.uploadUrl(id)`, which fetches a presigned URL for the profile photo.

## Deployment

CI is GitHub Actions (`.github/workflows/cypress.yml`) on push to `main`/`develop` and on PRs: `npm ci` → `npm run build` → start dev server → wait for `http://localhost:4400` (60s timeout) → Cypress headless in Chrome via `cypress-io/github-action@v6`. Screenshots upload on failure, videos always.

Deployment is manual S3 + CloudFront:

1. Update the version in `package.json` and the environment files
2. `ng lint && npm run build:prod`
3. Upload `dist/` to a timestamped S3 folder (e.g. `1615312408`)
4. Point the CloudFront origin path at `insgt-apps.s3-website-us-west-1.amazonaws.com/photogs/{timestamp}`
5. Create a CloudFront invalidation for `/*`
6. Trim deployments older than the last 10

| | Bucket | CloudFront | Distribution |
|---|---|---|---|
| Production | `insgt-apps` (`photogs/`) | `d1qiv85gf0dc85.cloudfront.net` | `E2KY09NFQ8WLK0` |
| Staging | `insgt-photogs-staging` | `d2jzvci8yy97l3.cloudfront.net` | `E10KWT3DJUF653` |

Last known-good rollback target: `1754944302`.

## AB 723 Impact
None directly. This app shows photographers their own shoot schedule and does not deliver photos to agents or buyers, so no disclosure surface exists here. Alteration work happens downstream in processing (insgt-ops) and delivery (insgt-app).

## Known Debt / Gotchas
- No app-specific Claude skill exists for this repo, and `angular-core` scopes itself to insgt-ops and insgt-app — so conventions here are documented in the repo's own `CLAUDE.md` rather than in the skill layer.
- Deployment is entirely manual, with no pipeline.
- `tailwind.config.js` is 523 lines, mostly an inlined Material Design palette.
- Session cookie path differs by environment (`/photographers` dev, `/photographer-admin` prod), so cookie auth silently fails if the path is wrong.
