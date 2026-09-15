---
name: architecture-planning
description: Use this skill when planning a feature or architectural change before any implementation — writing a new design document, revising an existing one, cutting a document into delivery slices, or reviewing a plan before it becomes a contract. Invoke when asked to "plan," "design," "architect," or "think through" something with no document yet, or when a prompt names a design doc that does not exist. Stop using it once the document is approved; `slice-implementation` takes over from there.
---

# Architecture Planning

`slice-implementation` works because the contract already exists. This skill is how the contract gets written. The output is a design document the next session can implement from without the transcript.

The engineer is the only reviewer and the binding constraint. Every phase ends with a STOP.

**This skill owns:** the discovery protocol, the document's required sections, the slice-cutting test, and the adversarial pass.

**It does not own:** the design. Options and tradeoffs are produced here; the choice is the engineer's.

---

## Phase 0 — discovery

Read-only. No design, no options, no schema proposals. The single output is a facts file, `docs/architecture/<doc-name>-discovery.md`.

1. **Schema as it is.** Every table, column, enum, constraint, and index this change would touch. Actual definitions from `structure.sql`, not from the model.
2. **Who computes and who reads.** For each value in scope: what writes it, what derives from it, what displays it. `file:line` for each.
3. **Counts from the dev DB.** The population being partitioned, sliced, or migrated. Query and output pasted.
4. **Prior art.** The nearest existing thing of this shape in the repo — migration, job, page, enum. Named by path.
5. **Contradictions.** Anywhere two parts of the codebase already disagree about the same fact. These become open decisions, not footnotes.

Design that starts before this file exists produces sections that have to be retracted later.

STOP with the facts file.

---

## Phase 1 — shape

Still no document.

- **The problem, in one paragraph**, stated as what is wrong today and for whom. If the beneficiary is the engineer rather than a user or the business, say so plainly.
- **Non-goals.** What this change deliberately does not fix.
- **The axes.** What independent dimensions exist. Collapsing two into one flat list is the most common failure; so is splitting one into two that always move together.
- **Two or three approaches**, each with what it costs in solo-engineer hours and what it forecloses. Not one recommendation.
- **Counts before enums.** Any proposed enum, tier, or category is accompanied by the row count that would land in each value. A value with a handful of rows is a flag or a note, not an enum member.

STOP for the engineer's choice.

---

## Phase 2 — document

Write the document only after the shape is chosen. Required sections:

| Section | Holds |
| :--- | :--- |
| Purpose and non-goals | Phase 1, as approved |
| Vocabulary | Every domain term used ambiguously anywhere in the repo, defined once |
| Current state | The facts file, condensed, with its `file:line` map intact |
| Schema changes | Columns, types, nullability, enum integers pinned |
| Rules and derivations | How each value is computed, including the boundary cases by name |
| Open decisions | See below |
| Delivery slices | See Phase 3 |
| Change log | Version, date, what changed |

**Open decisions carry a resolution path, not just an ID.** Each entry states the question, the query to run or audit to do that would answer it, what each outcome implies, and what is blocked until then. A decision with no attached action becomes a blocker with no owner, and the sections that depend on it go stale silently.

Nullability is a decision, never a default. State what NULL means for every nullable column, or make it NOT NULL.

STOP with the document.

---

## Phase 3 — slice cut

Slices are cut at **dependency seams and visibility seams**. The document's slice table needs a column for each.

Apply to every slice: **when this is deployed, what changes for the person who uses the system?** "Nothing — deferred to slice N" is a valid answer and must be written in the table. Three consecutive slices with that answer is a sequencing finding, not a coincidence.

Each slice row states: scope, prerequisite slices, repo, what becomes visible, and any cross-repo deploy ordering. Where a slice spans repos, the ordering constraint belongs in the row.

A slice that cannot be deployed alone is not a slice.

STOP with the slice table.

---

## Phase 4 — adversarial pass

Run in a fresh session, against the document alone, with the only instruction being to attack it. Findings, not fixes.

The document does not become a contract until this pass is clean or the remaining findings are accepted in writing.

Look for:

- Sections that can be read two ways by a competent implementer.
- A slice naming a prerequisite that no earlier slice produces.
- One decision that is secretly two.
- A rule with no spec that could ever catch it being violated.
- A count, threshold, or enum value with no source in the facts file.
- Anything asserted about the schema that Phase 0 did not verify.

---

## Evidence rules

The evidence rules in `slice-implementation` apply unchanged: `file:line` for claims about code, the grep and its empty output for "there is no X", facts and assumptions and estimates labeled and kept apart, nothing "should work."

One addition: **no number without a query.** Any count, ratio, or population figure in the document carries the query that produced it and the date it was run.

---

## What this skill does not decide

- Which approach to take, or whether to build it at all.
- Whether an open decision is worth resolving now or deferring.
- When the document is good enough to implement from. That is a STOP.