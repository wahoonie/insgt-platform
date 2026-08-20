# Deploy Runbooks

Step-by-step procedures for shipping features to production — Heroku for **insgt-api**, manual S3 +
CloudFront invalidation for the Angular apps. One file per deploy, named `deploy-<feature>.md`.

## Conventions

**Runbooks are kept, never deleted.** They are durable, reusable records, not tickets: our deploys recur
(the metric and description runbooks are near-identical), the **Rollback** section stays relevant long
after the deploy, and the file is the audit trail of what shipped and when. Completion is therefore marked
with a `**Status:**` header field rather than by removing the file. Valid states:

- `Draft` — still being written
- `Ready` — reviewed, safe to execute
- `Deployed <date> [by <name>]` — run in production

Grep the live/history split with `grep -rl "Status:\*\* Deployed" .`. When a deploy emits useful output
(backfill counts, warnings, migration timings), paste it under a trailing `## Deploy log` section — see
[deploy-account-metric.md](deploy-account-metric.md) for the pattern.
