---
name: codex-review
description: Run an independent Codex review over the diff about to ship in one or more Insight repos (insgt-api, insgt-ops, insgt-app, or any other repo in insgt-platform), one repo at a time, then triage the findings against the code. Use directly as a final adversarial review before merge; predeploy-review-rails and predeploy-review-angular embed this Codex step; and it supplies the Codex invocation for the plan review in slice-implementation, where the brief is plan-review-brief.md and the plan is passed by absolute path. Read-only — surfaces findings and produces a plan, never edits or commits.
allowed-tools: Bash(codex exec:*), Bash(codex sandbox:*), Bash(git:*), Read, Grep, Glob
---

Target repos: $ARGUMENTS (any repo under `${PLATFORM_ROOT:-/workspace}`).

If empty, target every repo among `insgt-api`, `insgt-ops`, and `insgt-app`
whose branch has commits beyond its base:

```bash
for REPO in insgt-api insgt-ops insgt-app; do
  ROOT="${PLATFORM_ROOT:-/workspace}/$REPO"
  BASE=$([ "$REPO" = insgt-api ] && echo master || echo main)
  git -C "$ROOT" diff --quiet "$BASE...HEAD" || echo "$REPO"
done
```

Tell me which you picked. Uncommitted changes do not make a repo a target;
the review covers what is committed (see *The review covers HEAD*).

## Base branch

`insgt-api` is on `master`; every other repo is on `main`. The exception goes
away with the Render move; until then this skill carries it. Set `BASE` per
repo as above and use it everywhere a base ref is needed — the target check,
the brief's diff, and the plan review's worktree.

## Run configuration is recorded, never inferred

Every run passes the model and the reasoning effort explicitly on the command
(below). The report Codex writes describes itself in its first line, and that
self-description has been wrong about the effort before: a report said "high
effort" while the session header said `reasoning effort: none`, because the
command had passed neither. The record of a run is the session header
`codex exec` prints — model, reasoning effort, sandbox — plus the command
count, the token count, the start and end times, the sandbox mode
(`read-only` or `worktree`) and the probe result, and in worktree mode the
worktree path, `$SHA` and the four verification check results, copied into
the triage output. A run whose header does not match the command is a failed
run; re-run it.

## Model and reasoning effort

Use `gpt-6-astra` for the independent review.

Default to `high` reasoning effort. This is the normal setting for a completed
feature or slice review: the implementation and tests already exist, and
Codex's job is to independently look for defects, regressions, and incorrect
assumptions.

Escalate a repo's review to `max` when its diff materially touches any of
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
Tell me when a repo was escalated to `max` and why.

A foundation plan review (slice-implementation) is always `max`: the plan is
read once, before any code exists, and a flaw missed there costs the slice.

## Running the review

Run one `codex exec` per target repo, sequentially, never in parallel — Codex
is rate-limited and interleaved output is unreadable.

### Sandbox mode is probed once, before any review

Codex's read-only sandbox needs bwrap, and bwrap needs unprivileged user
namespaces. Many containers block those. Probe once at the start of the skill,
not per repo, and record the mode in the run configuration:

```bash
# The command follows `sandbox` directly; codex-cli 0.166 has no `linux` subcommand.
if codex sandbox true >/dev/null 2>&1; then
  MODE=read-only
else
  MODE=worktree
fi
```

- `read-only`: Codex runs in its own sandbox against the real tree.
- `worktree`: the sandbox can't start here. Codex runs with
  `--sandbox danger-full-access` inside a detached, disposable worktree at
  HEAD, so it never touches the tree we ship from. The container is the
  isolation boundary. Do not loosen container seccomp or AppArmor to make
  bwrap work.

Never let a review attempt fail into the fallback. If the probe chose
`read-only` and a review run still dies with the bwrap error, treat that run as
failed: discard its output file, switch to `worktree`, and re-run that repo.

### Per-repo run

```bash
REPO=insgt-api
ROOT="${PLATFORM_ROOT:-/workspace}/$REPO"
BASE=$([ "$REPO" = insgt-api ] && echo master || echo main)
SHA="$(git -C "$ROOT" rev-parse HEAD)"
EFFORT=high

# Record the real tree's state before the run
git -C "$ROOT" rev-parse HEAD
git -C "$ROOT" status --porcelain

if [ "$MODE" = worktree ]; then
  WT="/tmp/codex-review-wt-$REPO-$SHA"
  git -C "$ROOT" worktree prune   # clears a registration left by a wiped /tmp
  [ -d "$WT" ] || git -C "$ROOT" worktree add --detach "$WT" "$SHA"
  RUN_DIR="$WT"
  SANDBOX=danger-full-access
else
  RUN_DIR="$ROOT"
  SANDBOX=read-only
fi

codex exec -C "$RUN_DIR" \
  --model gpt-6-astra \
  --config model_reasoning_effort="$EFFORT" \
  --sandbox "$SANDBOX" \
  -o "/tmp/codex-review-$REPO.md" \
  "Perform an independent adversarial review of the completed changes in
   \`git diff $BASE...HEAD\`.

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
   - violations of documented conventions in AGENTS.md and in the design
     document under docs/architecture/ that the diff's commits cite

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

The output file is written to `/tmp`, outside the worktree, so it is not
mistaken for a write by Codex.

### Read-only verification (worktree mode, after each repo)

```bash
git -C "$WT" status --porcelain        # must be empty
git -C "$WT" rev-parse HEAD            # must equal $SHA
git -C "$ROOT" rev-parse HEAD          # must equal the pre-run value
git -C "$ROOT" status --porcelain      # must equal the pre-run value
```

If any check fails, the run is invalid. Report exactly what changed, do not use
its findings, and recreate the worktree before the next run.

Each repo gets its own worktree, since each has its own HEAD. A worktree is
reused across runs within one invocation and removed at the end:

```bash
git -C "$ROOT" worktree remove --force "$WT"
```

### The review covers HEAD

Worktrees share refs with the main checkout, so `git diff $BASE...HEAD` inside
the brief resolves the same way in either mode. Uncommitted or untracked files
in the real tree are deliberately **not** in the worktree. The review covers
HEAD, which is what ships. If a target repo's tree is dirty when the skill
starts, say so in the output.

### Plan review (slice-implementation)

The plan review keeps the probe, the run directory, the sandbox mode, the
flags, and the read-only verification above, and swaps the brief: the filled
`plan-review-brief.md` from the slice-implementation skill folder goes in on
stdin (`-` as the prompt), the plan is passed by absolute path (a `/tmp`
snapshot, not a committed file), and the effort is `max`. In worktree mode the
worktree is detached at the plan's base ref (`$BASE`) rather than HEAD, as that
step states, so the committed-at-HEAD rule does not apply to it.

## Triage

Read each `/tmp/codex-review-$REPO.md` and triage every finding:

**agree · disagree (say why) · already-intentional (cite the doc section) ·
needs-my-decision**

Verify every claim against the actual code at the cited `file:line` before
accepting it. A Codex finding is evidence to investigate, not a conclusion.

Where a finding rests on a measurable fact ("this happens on N rows", "a
shared phone number can belong to more than one account"), measure it against
the repository's data or evidence files and mark the result; a finding Codex
labels "plausible" is confirmed, re-graded, or rejected on the measurement,
never carried at face value.

Read Codex's severities and fixes against the brief: it tends to propose fixes
that add scope where a smaller change or a logged trigger exists.

For findings that depend on behavior in another Insight repo, inspect that repo
before accepting the finding when it is available locally. Do not accept
cross-repo speculation as fact.

Reject a finding if:

- the cited code does not support the claim
- the stated failure scenario cannot actually occur
- existing code elsewhere provides the protection Codex says is missing
- a documented invariant or decision makes the behavior intentional (cite it)
- it is only a style preference, cleanup suggestion, or generic best practice
  with no concrete consequence
- Codex assumed an API contract or cross-repo behavior that the actual code
  contradicts
- an existing test exercises the exact failure scenario and demonstrates that
  the concern is not valid

Do not reject a finding merely because tests currently pass. The implementation
and tests may encode the same incorrect assumption.

Known noise: a finding that a repo should ship `structure.sql` instead of
`schema.rb`, or the reverse, is rejected on sight. The schema format each repo
ships is a logged decision, and Codex has flagged it wrongly before.

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

- the run configuration per repo (session header, sandbox, commands, tokens,
  times, sandbox mode and probe result, tree state before and after, and in
  worktree mode the worktree SHA and read-only verification results)
- numbered tasks, one concern each
- the accepted finding and its verified failure scenario, attributed to the
  pass that raised it when more than one ran
- affected repo or repos
- minimum remediation direction
- findings rejected, each with the reason, so the review has an audit trail
- explicit non-goals
- open decisions requiring my sign-off; a finding that reverses a decision the
  design document has logged is one of these and gets a change-log entry in
  that document, never a quiet edit
- a verification checklist with a deliberate-break per task

No code. Do not edit files or commit anything.
