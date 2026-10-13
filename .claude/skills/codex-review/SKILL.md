---
name: codex-review
description: Run an independent Codex review over one or more Insight repos, then triage the findings against the code. Use as a final adversarial review before merge. Read-only — surfaces findings and produces a plan, never edits or commits.
allowed-tools: Bash(codex exec:*), Bash(git:*), Read, Grep, Glob
---

Target repos: $ARGUMENTS

If empty, run `git -C "$repo" status --porcelain` across `insgt-api`,
`insgt-ops`, and `insgt-app` and target only those with changes. Tell me which
you picked.

## Model and reasoning effort

Use `gpt-6-astra` for the independent review.

Default to `medium` reasoning effort. This is the normal setting for a completed
feature or change review: the implementation and tests already exist, and
Codex's job is to independently look for defects, regressions, and incorrect
assumptions.

Escalate a repo's review to `high` when its diff materially touches any of
these:

- authentication, authorization, permissions, or customer-data boundaries
- order pricing, payments, credits, refunds, taxes, or financial calculations
- database migrations or hard-to-reverse data invariants
- background jobs, retries, concurrency, locking, or idempotency
- destructive operations, file deletion, or irreversible external side effects
- photo, media, or storage operations where originals or customer assets could
  be lost or corrupted
- public or cross-repo API contracts
- secrets, credentials, webhook verification, or other security boundaries
- production configuration or deployment behavior with significant blast radius

Do not use `max` for normal code review. Reserve it for exceptional,
foundational reviews where a missed architecture, security, or data-integrity
flaw would be unusually expensive to recover from.

Choose the effort separately for each repo after inspecting that repo's diff.
Tell me when a repo was escalated to `high` and why.

## Running the review

Run one `codex exec` per target repo, sequentially, never in parallel — Codex
is rate-limited and interleaved output is unreadable.

Use `--sandbox read-only` first. This is a review, not a fix.

If the run dies because the sandbox cannot start in the current container,
re-run with `--sandbox danger-full-access` only on a fully committed tree.
Check `git status --porcelain` immediately afterwards and report any unexpected
change.

```bash
REPO=insgt-api
EFFORT=medium

codex exec -C "${PLATFORM_ROOT:-/workspace}/$REPO" \
  --model gpt-6-astra \
  --config "model_reasoning_effort=\"$EFFORT\"" \
  --sandbox read-only \
  -o "/tmp/codex-review-$REPO.md" \
  "Perform an independent adversarial review of the completed changes in
   \`git diff main...HEAD\`.

   Do not modify files. Do not implement fixes. Review the code that exists.

   Assume the implementation and its tests may share the same incorrect
   assumptions. Your job is to find defects that could survive the author's
   own review and test suite.

   Look specifically for:
   - correctness bugs and behavioral regressions
   - security or authorization failures
   - data loss, corruption, or incorrect persistence
   - concurrency, retry, transaction, and idempotency failures
   - missing or incorrectly handled edge cases
   - broken assumptions about another Insight repo or API
   - API contract drift between producers and consumers
   - requirements the implementation satisfies only partially
   - tests that validate the implementation without actually validating the
     intended behavior
   - violations of documented conventions in AGENTS.md

   Where relevant to the changed code, pay particular attention to:
   - order totals, product pricing, discounts, payments, and financial values
   - background jobs that can run more than once or partially fail
   - destructive media, file, or record operations
   - API request and response shapes consumed by another repo
   - authentication and authorization checks
   - database migrations and assumptions about existing production data
   - external-service failures, timeouts, retries, and duplicate callbacks
   - frontend behavior that assumes the API always succeeds or returns a
     particular shape
   - backend changes that assume only one frontend or caller exists

   Report only actionable findings. Do not report stylistic preferences,
   speculative concerns, cleanup opportunities, or generic best practices
   unless they create a concrete failure in this codebase.

   For every finding provide:
   - file:line
   - severity: blocker | should-fix | nit
   - issue
   - concrete failure scenario: what breaks, for whom, and under what condition
   - minimum suggested remediation

   A blocker should mean the change should not ship as written because it can
   cause a serious security, data-integrity, financial, availability, or
   customer-impacting failure.

   A should-fix finding must describe a real defect or credible regression, not
   an improvement that would merely make the code cleaner.

   If you cannot describe a plausible concrete failure scenario, do not report
   the finding.

   Do not rewrite the implementation. Do not praise the code or summarize the
   diff. Findings only.

   If no actionable findings survive this standard, say so explicitly."
```

## Triage

Read each `/tmp/codex-review-$REPO.md` and triage every finding:

**agree · disagree (say why) · already-intentional · needs-my-decision**

Verify every claim against the actual code at the cited `file:line` before
accepting it. A Codex finding is evidence to investigate, not a conclusion.

For findings that depend on behavior in another Insight repo, inspect that repo
before accepting the finding when it is available locally. Do not accept
cross-repo speculation as fact.

Reject a finding if:

- the cited code does not support the claim
- the stated failure scenario cannot actually occur
- existing code elsewhere provides the protection Codex says is missing
- the behavior is intentional and documented
- it is only a style preference, cleanup suggestion, or generic best practice
  with no concrete consequence
- Codex assumed an API contract or cross-repo behavior that the actual code
  contradicts
- an existing test exercises the exact failure scenario and demonstrates that
  the concern is not valid

Do not reject a finding merely because tests currently pass. The implementation
and tests may encode the same incorrect assumption.

## Cross-repo verification

After triaging the individual repos, inspect accepted findings for assumptions
that cross repo boundaries.

Specifically check for:

- API request or response contract drift
- renamed or removed fields still consumed elsewhere
- differing assumptions about nullability, enums, IDs, dates, or money
- frontend behavior relying on backend implementation details
- duplicated domain rules that have diverged
- a backend change that works for one client but breaks another
- deployment or sequencing dependencies between repos

A cross-repo concern must identify both sides of the mismatch when both are
available. Do not report a hypothetical consumer without evidence.

## Output

Produce a planning-only output, grouped by repo, followed by a cross-repo
section for findings that span repositories.

Include:

- numbered tasks, one concern each
- the accepted finding and its verified failure scenario
- affected repo or repos
- minimum remediation direction
- explicit non-goals
- open decisions requiring my sign-off
- a verification checklist with a deliberate-break per task

Do not include rejected Codex findings as tasks. Briefly list rejected findings
separately with the reason they were rejected so the review has an audit trail.

No code. Do not edit files or commit anything.