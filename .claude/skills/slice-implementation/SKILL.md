---
name: slice-implementation
description: Use this skill whenever implementing one slice, phase, or chunk of a written architecture or design document in any InsightPhotos repo (insgt-api, insgt-ops, insgt-app, insgt-site-sls, or any other repo in insgt-platform). Invoke when a prompt mentions a slice number, a section of a design doc, phases, STOP gates, an implementation loop, or "follow the agentic pattern" — even if it does not name this skill. Also invoke when asked to write such a prompt. Carries the survey, plan, red-green loop, adversarial review, and write-back protocol so individual slice prompts only need to state scope, contract sections, and traps.
---

# Slice Implementation

InsightPhotos is a solo-engineer polyrepo. Architecture work is written down first, cut into independently shippable slices at dependency and visibility seams, and each slice is implemented in its own Claude Code session. The engineer is the only reviewer and the binding constraint on every decision; the document is the contract; the repo is the memory between sessions.

This skill holds the parts of that workflow that are the same for every slice. A slice prompt supplies only what differs.

---

## Division of labor

**The design document owns:** every decision, every rule, every enum integer, every scope definition, and a versioned change log. Read the sections the prompt cites; treat them as the contract. Never restate a rule from memory when the section can be read.

**The slice prompt owns:**

- Scope and out-of-scope, by section number and by name.
- Which document sections are the contract for this slice.
- Known gaps: things the document leaves open that the plan must pin.
- Slice-specific traps the review must not accept.
- A sketch of the commit sequence.
- Gate calibration for this slice (see *Gates*).

**This skill owns:** the phases, the evidence rules, the implementation loop, the review handoff, the write-back, and the report format.

If a prompt restates a rule and the document says something different, STOP and report the disagreement. Do not pick one.

---

## Phase 0 — survey

Read-only. Nothing is written in this phase.

1. **Read the codebase notes first.** If `docs/architecture/<doc-name>-codebase-notes.md` exists, it is the `file:line` map from earlier slices. Verify each entry this slice depends on is still true; survey fresh only what the notes don't cover or what has moved. If the notes don't exist, this session creates them in the write-back phase.
2. **Prerequisite check.** Every slice depends on earlier ones. Confirm each prerequisite has landed — the scope exists, the column exists, the consumer already reads the new predicate. A missing prerequisite is a STOP, not something to work around. Building on the old predicate produces code that is correct today and wrong the day the prerequisite lands.
3. **Survey what this slice touches.** For each file: what it does, what computes it, what reads it, what tests it. Include the patterns to copy — the nearest existing migration of the same shape, the nearest existing spec that builds the same fixtures, the nearest existing job.
4. **Grep for collisions.** Every column, enum, scope, route, or component name this slice introduces: confirm nothing already uses it.

STOP with the survey. Flag anything that changes the plan.

---

## Phase 1 — plan

Nothing is implemented in this phase.

- **Pin every gap the prompt named.** State the exact rule chosen, the alternative rejected, and why. A gap left as "we'll see during implementation" becomes a decision made at the worst possible time with no record.
- **Approach per unit of work.** SQL or Ruby, window function or array scan, signal or observable — chosen to read like the surrounding code, not to be interesting. Estimate runtime or bundle impact where it matters.
- **Spec plan** with the boundary cases listed by name. The document's edge cases (the refund, the cancelled order, the `parent_pays` child, the 365-day boundary) are the minimum. A spec plan that only covers the happy path is not a plan.
- **Commit sequence**, one concern per commit, following `git-commit-messages`. Bisect integrity is the reason: eight months from now the engineer will be bisecting, and a commit that mixes a migration with a calculator change halves the value of the bisect.
- **Post-deploy verification**: the command to run after deploy and 3–5 spot checks with expected values *reasoned from the rules before the code exists*. Expectations written after seeing output are not expectations.
- **Risks**: anything the survey found that could make this slice disagree with an earlier one.

STOP for approval.

---

## Implementation loop

Run this loop once per unit of work — one column, one component, one migration — never once per phase.

1. **Red.** Write the spec first. Run it. It must fail, and it must fail for the right reason: a missing method, not a syntax error in the spec.
2. **Green.** Implement the smallest thing that passes.
3. **Deliberate break.** Change one thing the spec is supposed to guard — an enum integer, a boundary, a predicate — and confirm the spec goes red. Restore. Paste the red output. A spec that has never been seen red proves nothing; this step is the only evidence it guards anything.
4. **Lint** the touched files.
5. **Full suite for the touched area.** Not just the new examples. Existing behavior must produce identical results; a changed existing spec is a regression in this slice, not a problem for an earlier one.
6. **Commit.**

**Three strikes.** If the same step fails three times, STOP and report. A fourth approach chosen under pressure is how a workaround gets committed.

### Migrations

- `migrate`, `rollback`, `migrate` again. Paste the schema diff (`db/schema.rb` in insgt-api today; `structure.sql` once PostGIS lands); it must contain only the expected changes.
- `strong_migrations` checks are the rule. Concurrent indexes, `disable_ddl_transaction!`, and the four-migration sequence for anything that ends `NOT NULL`: nullable add, backfill, unvalidated CHECK, validate-and-flip (`insgt-api/README.md` §Migrations; `order_types.category_type`, `db/migrate/20260904120000..3`, is the worked example).
- Diff whichever schema file the repo ships. insgt-api ships `schema.rb`; a review that flags that as wrong is itself wrong.
- Rolling-deploy safety: name the window where old code runs against the new schema, and the window where new code runs against the old schema, and confirm neither fails. Additive nullable columns satisfy this; anything else needs a stated ordering.

### Angular

- State-layer code (reducers, selectors, mappers, facades) ships with Vitest per `angular-unit-testing`. Component and route behavior is Cypress-only.
- Build before commit. A green Vitest run with a broken template is not green.
- Load `angular-core` and the app-specific skill; the pattern to copy is the reference component the prompt names, not the nearest file.

---

## Verification

After the loop completes for the whole slice:

- Run the post-deploy verification from the plan against the dev DB. Compare to the reasoned expectations. **Explain every mismatch; never adjust the expectation to match the output.** A mismatch is either a bug or a wrong rule, and both are findings.
- Report runtime or bundle delta where the plan estimated one.
- **Shift memo when visible numbers move.** If existing values that a human reads change as a result of this slice, compute old and new side by side across the full population, diff, and produce a one-page memo stating which records moved, by how much, and in which direction. "Numbers changed and nobody knows why" is a trust failure with the only person who reads them.

STOP with results.

---

## Adversarial review

Run the repo's predeploy review skill over the full diff of the slice — `predeploy-review-rails` or `predeploy-review-angular` — including the Codex second-opinion step and its triage.

The review must not accept, without evidence in the diff:

- Any predicate that re-derives what an existing scope or selector already defines.
- A default on a column the document declares nullable, or a `NOT NULL` the document doesn't specify.
- A change to how an existing column, metric, or selector is computed, unless the slice's scope names it.
- A spec whose deliberate-break red output was not shown.
- Anything on the prompt's slice-specific trap list.

**Disposition per finding:** fix in place if in scope and clearly correct, re-running the loop on the fix; otherwise record it as out of scope with the reason and where it should go. Amend only the commit the finding belongs to, and only on an unpushed branch; otherwise add a fix commit.

**Two rounds.** Re-run the review after fixes. If findings remain after the second round, STOP and list them. A third round is the engineer's call.

---

## Write-back

The slice is not done until the repo remembers it.

1. **Document amendment.** Every gap the plan pinned, every decision the implementation made that the plan didn't anticipate, becomes a short amendment to the design document with a version bump and a line in its change log. The next slice reads the document, not this session's transcript.
2. **Codebase notes.** Update `docs/architecture/<doc-name>-codebase-notes.md` with the `file:line` map this slice established or changed. Keep it flat and factual: file, line, what it is, which slice put it there.
3. **Contract spec.** If the document has a contract spec (`spec/architecture/<doc-name>_spec.rb` or the Angular equivalent), add this slice's invariants to it: pinned integers, scope behavior on the canonical fixtures, boundary rules. The contract spec is what catches slice 6 quietly breaking a slice 2 rule; per-slice specs never will.

These are commits, following `git-commit-messages`, and they are part of the slice.

---

## Gates

Every phase above ends with a STOP: report, then wait. Do not read ahead into the next phase's work while waiting.

The prompt calibrates which gates are real for this slice. The engineer is the bottleneck at every STOP, and a gate that cannot change a decision costs an afternoon without buying safety.

| Slice character | Gates that must be real |
| :--- | :--- |
| Changes what a human sees; touches existing computed values | All of them |
| New columns, new scopes, nothing reads them yet | After plan; after verification |
| Enum add, five-row backfill, mechanical | After plan; at the end |
| Bug fix inside an already-landed slice | At the end |

When the prompt says nothing, all gates are real.

---

## Evidence rules

These apply to every phase and every report.

- `file:line` for every claim about existing code. "The calculator handles this" is not a claim; `app/services/account_metrics/calculator.rb:41` is.
- The grep command and its empty output for every "there is no X."
- Spec output pasted, red and green, not summarized.
- Nothing "should work." It ran, or it is listed as unverified.
- Facts, assumptions, and estimates labeled as such and kept apart.
- Where a document section and the code disagree, quote both. Do not resolve it silently in either direction.

---

## Report structure

Every STOP uses this shape; omit sections that are empty for the phase.

```
## <Phase name> — <slice identifier>

### Done
### Evidence
### Decisions made in this phase
### Open questions for the engineer
### Unverified
### Next phase, if approved
```

The final report adds: commit hashes with subjects, review findings and disposition, the spot-check table, the post-deploy command, and the write-back commits.

---

## What this skill does not decide

- Which slice to do next, or whether the document is right. That is the document's job and the engineer's.
- Whether to add a fourth approach after three strikes, or a third review round. Those are STOPs.
- Anything domain-specific — null-not-zero semantics, `parent_pays IS NOT TRUE`, enum starting at 1. The document says those; cite it.

## Prompt template

`references/prompt-template.md` is the skeleton for a slice prompt that relies on this skill. Read it when asked to write one; it is deliberately short.