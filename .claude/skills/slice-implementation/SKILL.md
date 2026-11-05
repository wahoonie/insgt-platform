---
name: slice-implementation
description: Use this skill whenever implementing one slice, phase, or chunk of a written architecture or design document in any InsightPhotos repo (insgt-api, insgt-ops, insgt-app, insgt-site-sls, or any other repo in insgt-platform). Invoke when a prompt mentions a slice number, a section of a design doc, phases, STOP gates, an implementation loop, or "follow the agentic pattern" — even if it does not name this skill. Also invoke when asked to write such a prompt. Carries the survey, plan, plan review (foundation), red-green loop, adversarial review, and write-back protocol so individual slice prompts only need to state scope, contract sections, and traps.
---

# Slice Implementation

InsightPhotos is a solo-engineer polyrepo. Architecture work is written down first, cut into independently shippable slices at dependency and visibility seams, and each slice is implemented in its own Claude Code session. The engineer is the only reviewer and the binding constraint on every decision; the document is the contract; the repo is the memory between sessions.

This skill holds the parts of that workflow that are the same for every slice. A slice prompt supplies only what differs.

**Gate precedence.** The *Gates* section governs every phase-ending STOP below. Pause only at the gates selected in the slice prompt; at other phase boundaries, report progress and continue automatically. Exception stops always apply, regardless of gate selection.

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
4. **Grep for collisions.** Every column, enum, scope, route, or component name this slice introduces: confirm nothing already uses it. For a contract change, grep the consuming repo too — the serializer field, the enum value, the route — since the Angular side mirrors Rails enums as hardcoded consts.

Report the survey and flag anything that changes the plan. STOP only if the survey gate is selected; otherwise continue to the plan.

---

## Phase 1 — plan

Nothing is implemented in this phase.

- **Pin every gap the prompt named.** State the exact rule chosen, the alternative rejected, and why. A gap left as "we'll see during implementation" becomes a decision made at the worst possible time with no record.
- **Approach per unit of work.** SQL or Ruby, window function or array scan, signal or observable — chosen to read like the surrounding code, not to be interesting. Estimate runtime or bundle impact where it matters.
- **Contract impact.** If the slice changes a serializer, permitted params, a route, or an enum that a client repo mirrors: name the serializer, the request spec, and the consuming repo's model or const that must change, and state the deploy ordering — `insgt-api` lands before any consumer that depends on it. The slice prompt's `Repo:` line names the ordered pair; a contract change the prompt did not name as cross-repo is a finding against the prompt, not something to absorb.
- **Model spend.** If the slice adds or changes a call to the Anthropic API: the cost estimate (model, tokens per call, cadence, $/month at current volume) must be in the plan or cited from the document. No estimate is a STOP.
- **Spec plan** with the boundary cases listed by name. The document's edge cases (the refund, the cancelled order, the `parent_pays` child, the 365-day boundary) are the minimum. A spec plan that only covers the happy path is not a plan.
- **Review carry-in.** If the design document's own review or drift audit left items to the plan (the document's status note names them), each gets a pinned decision here, with the finding cited.
- **Commit sequence**, one concern per commit, following `git-commit-messages`. Bisect integrity is the reason: eight months from now the engineer will be bisecting, and a commit that mixes a migration with a calculator change halves the value of the bisect.
- **Post-deploy verification**: the command to run after deploy and 3–5 spot checks with expected values *reasoned from the rules before the code exists*. Expectations written after seeing output are not expectations.
- **Risks**: anything the survey found that could make this slice disagree with an earlier one.

### Plan review

An independent model reads the written plan before the plan gate. It runs for every foundation slice (see the gate table) and for every follow-up whose plan document is the design, with no reviewed design document behind it; edge slices skip it. The step stays in plan mode, and the only file it edits is the plan.

- **Snapshot.** The plan is not committed. Copy it to `/tmp/codex-plan-review-<slice>/plan.md` and pass that absolute path as `<<PLAN_PATH>>`. Record its `sha256sum` before and after the run; a changed hash invalidates the run. Triage against the snapshot's line numbers.
- **Fill.** Copy `plan-review-brief.md` (beside this file) to the scratchpad and replace every `<<…>>` placeholder from the plan and its slice row. `<<BASE_SHA>>` is the plan's base ref resolved — the repo's default branch, which `codex-review` names per repo (`master` for insgt-api, `main` elsewhere). `<<RUN_DIR_NOTE>>` is one sentence, by sandbox mode — worktree: "The run directory is a detached worktree at <base>; read files directly."; read-only: "The working tree may differ from <base>; use `git show <base>:<path>`." Change nothing else.
- **Run.** Take the sandbox probe, run directory, invocation, and read-only verification from `codex-review`, the same way the predeploy review skills do; restate none of it. The model is `codex-review`'s; the effort is `max`. In worktree mode, detach the worktree at the plan's base ref, not HEAD, and record that SHA. The brief goes in on stdin (`-` as the prompt) and the output to the scratchpad with `-o`, in the background with no timeout.
- **State.** The worktree add and remove and the `/tmp` writes are this step's only state changes. Neither touches refs or the working tree, so plan mode permits them.
- **Triage, one round.** Verify each finding against the repo before accepting it. Give each one a disposition: fixed (the plan edited), rejected (a one-clause reason), or out of scope (where it is recorded). A finding that challenges a decision the document has already logged becomes an open question for the engineer, not a plan change. Run a second round only if a blocker fix changes the commit sequence or the migration shape.
- **Record.** Add a *Plan review* section to the plan: model, effort, sandbox mode and base SHA, then one line per finding (ID, severity, disposition, and the change or reason). Add the questions the review raised to the plan's open questions. Present the plan at the gate with the blockers and rejections listed in the reply.

Report the plan. STOP for approval only if the plan gate is selected; otherwise continue to implementation.

---

## Implementation loop

Run this loop once per unit of work — one column, one component, one migration — never once per phase.

1. **Red.** Write the spec first. Run it. It must fail, and it must fail for the right reason: a missing method, not a syntax error in the spec.
2. **Green.** Implement the smallest thing that passes.
3. **Deliberate break.** Change one thing the spec is supposed to guard — an enum integer, a boundary, a predicate — and confirm the spec goes red. Restore. Paste the red output. A spec that has never been seen red proves nothing; this step is the only evidence it guards anything.
4. **Lint and typecheck** the touched files: `rubocop` for Rails; `eslint` and `ng build` for Angular (`tsc --noEmit` where the app has a script for it).
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
- Report runtime, bundle, or query-count delta where the plan estimated one.
- **Shift memo when visible numbers move.** If existing values that a human reads change as a result of this slice, compute old and new side by side across the full population, diff, and produce a one-page memo stating which records moved, by how much, and in which direction. "Numbers changed and nobody knows why" is a trust failure with the only person who reads them.

Report the results. STOP only if the verification gate is selected; otherwise continue to adversarial review.

---

## Adversarial review

Run the repo's predeploy review skill over the full diff of the slice — `predeploy-review-rails` for insgt-api, `predeploy-review-angular` for any Angular repo — including the Codex second-opinion step and its triage. A slice spanning two repos runs both, each over its own repo's diff.

The review must not accept, without evidence in the diff:

- Any predicate that re-derives what an existing scope or selector already defines.
- A default on a column the document declares nullable, or a `NOT NULL` the document doesn't specify.
- A change to how an existing column, metric, or selector is computed, unless the slice's scope names it.
- An enum, serializer, or permitted-params change in `insgt-api` with no matching change — or a named follow-up commit — in the consuming repo's model or const.
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
4. **Review record.** Write `docs/architecture/reviews/<date>-slice-<id>-<repo>.md` from the record text the adversarial review produced (one file per repo reviewed). The handoff's review section is cut from the same text.

These are commits, following `git-commit-messages`, and they are part of the slice.

---

## Finish — handoff and final report

After all required checks, verification, adversarial review, fixes, and write-back are complete, produce the handoff: the branch name; the commit list with hashes and subjects, stating which are still local; the pre-handoff checks (full suite, lint, build) pasted as evidence; and the command block the engineer runs for the push — and for `gh pr create`, with the body at `/tmp/pr-<slug>.md` cut from the final report, where the repo uses pull requests. The push is the engineer's: the session's permissions deny it, and the session never claims to have pushed, opened a PR, merged, or deployed. Then give the final report with the handoff at its end. The end gate is this completed handoff; it is not an approval pause before writing it.

Do not merge or deploy. Merging and deployment remain the engineer's decisions. If a required check, review, write-back step, or the handoff cannot be completed, report the blocker and remaining work; do not claim the slice is finished.

---

## Gates

The phase approval gates are **after survey**, **after plan**, and **after verification**. **At the end** means the final handoff after write-back. **All** means all three phase approval gates plus the final handoff.

The slice prompt's gate selection takes precedence over phase-ending STOP instructions. At a selected phase gate, report and wait; do not read ahead into the next phase while waiting. At an unselected boundary, report progress and continue automatically through implementation, verification, adversarial review, in-scope fixes, write-back, and the handoff. Skipping a pause never skips the work or evidence required for that phase.

The prompt selects gates according to the table. The engineer is the bottleneck at every STOP, and a gate that cannot change a decision costs an afternoon without buying safety. The split follows foundation versus edge: a foundation is something other code or another repo depends on.

| Slice character | Gates that must be real | Plan review |
| :--- | :--- | :--- |
| Foundation: a scope or predicate other code reads, a metrics calculator or its nightly recompute, order lifecycle or billing rules, payments, the Twilio sender, the disclosure pipeline, a serializer or enum consumed by more than one client repo | All | Yes |
| Visible or computed values: changes what a human sees or touches existing computed values, without touching a foundation | All | No |
| Additive: new columns, new scopes, a new endpoint with its single consumer; nothing existing reads it yet | After plan; after verification | No |
| Screen or component only, against an existing serializer | At the end | No |
| Mechanical: enum add, five-row backfill, copy change | After plan; at the end | No |
| Bug fix inside an already-landed slice | At the end | No |

When the prompt says nothing, all gates apply. An unclear gate selection is not permission to skip a pause. A follow-up whose plan document is the design, with no reviewed design document behind it, takes the plan review whatever its row.

### Exception stops — always apply

Gate selection never overrides a missing prerequisite, a prompt that disagrees with the document, a missing model-spend estimate, the three-strikes limit, or unresolved review findings under the two-round rule. Fix clear in-scope findings within that review process; STOP when a finding cannot be safely resolved or justified as out of scope. Report the blocker, evidence, and decision needed before continuing.

If the survey or implementation shows that a screen, mechanical change, or ordinary bug fix changes a foundation (the table's first row), STOP before making that change. Report the scope change and the proposed classification, plan, and gates; wait for the engineer to reassess them. Do not silently retain the lighter gate selection or broaden the slice.

---

## Evidence rules

These apply to every phase and every report.

- `file:line` for every claim about existing code. "The calculator handles this" is not a claim; `app/services/account_metrics/calculator.rb:41` is.
- The grep command and its empty output for every "there is no X."
- `grep` here is ugrep and `rg` is a Claude Code shell function, not a binary. Write every pattern for `grep -rn -E`: bare `|` for alternation, `[(]` and `[{]` for literal brackets, `-F` for a literal string. `\|` is a literal pipe (counts come back 0) and `\(` errors. A prompt that says `rg` means this.
- Spec output pasted, red and green, not summarized.
- Nothing "should work." It ran, or it is listed as unverified.
- Facts, assumptions, and estimates labeled as such and kept apart.
- Where a document section and the code disagree, quote both. Do not resolve it silently in either direction.

---

## Report structure

Every selected gate, exception stop, and final handoff uses this shape; omit sections that are empty for the phase. At unselected boundaries, give a brief progress report and continue without requesting approval.

```
## <Phase name> — <slice identifier>

### Done
### Evidence
### Decisions made in this phase
### Open questions for the engineer
### Unverified
### Next step
```

At a selected phase gate or exception stop, name the approval or decision needed in **Next step**. The final report adds: commit hashes with subjects, review findings and disposition, the spot-check table, the post-deploy command, the write-back commits, and the handoff (branch, push command block, PR body path where used), stating which commits are still local. State that the push, merge, and deployment are pending the engineer.

---

## What this skill does not decide

- Which slice to do next, or whether the document is right. That is the document's job and the engineer's.
- Whether to add a fourth approach after three strikes, or a third review round. Those are STOPs.
- Anything domain-specific — null-not-zero semantics, `parent_pays IS NOT TRUE`, enum starting at 1. The document says those; cite it.

## Prompt template

`references/prompt-template.md` is the skeleton for a slice prompt that relies on this skill. Read it when asked to write one; it is deliberately short. `plan-review-brief.md` is the reviewer brief the plan-review step fills; it is not read in any other phase.
