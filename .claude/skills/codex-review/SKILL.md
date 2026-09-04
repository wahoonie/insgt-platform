---
name: codex-review
description: Run a codex review over one or more insgt repos, then plan against the findings
allowed-tools: Bash(codex exec:*), Bash(git:*), Read, Grep, Glob
---

Target repos: $ARGUMENTS
If empty, run `git -C "$repo" status --porcelain` across insgt-api, insgt-ops,
insgt-app and target only those with changes. Tell me which you picked.

For each target repo, run (sequentially, not in parallel — codex is rate-limited
and interleaved output is unreadable):

REPO=insgt-api
codex exec -C "${PLATFORM_ROOT:-/workspace}/$REPO" \
  --sandbox danger-full-access \
  -o "/tmp/codex-review-$REPO.md" \
  "Review the changes in \`git diff main...HEAD\`. Do not modify files.
   For each finding: file:line, severity (blocker/should-fix/nit), the issue,
   and a suggested fix. Flag violations of the conventions in AGENTS.md."

Then read each /tmp/codex-review-$REPO.md and triage every finding:
agree · disagree (say why) · already-intentional · needs-my-decision.
Verify each claim against the actual code before accepting it.

Produce a planning-only output, grouped by repo, then a final cross-repo
section for anything that spans them (API contract drift, shared types).
Numbered tasks, one concern each. Explicit non-goals. Open decisions
requiring my sign-off. Verification checklist with a deliberate-break
per task. No code.