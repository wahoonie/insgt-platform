# Slice prompt template

A slice prompt supplies only what `slice-implementation` cannot know. Aim for 30–60 lines. If a prompt is growing past that, it is restating the document or the skill; cut it and cite instead.

```markdown
# <Document short name> — slice <N>: <one-line summary>

**Repo:** <one repo, or the ordered pair for a contract change, e.g. insgt-api → insgt-ops>. No changes elsewhere.
**Contract:** `docs/architecture/<doc>.md` §<a>, §<b>, §<c>. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: `git-commit-messages`, the review skill per repo (`predeploy-review-rails` for insgt-api, `predeploy-review-angular` for insgt-ops, insgt-app, and the other Angular repos), <`angular-core` + the app skill and `angular-unit-testing` for any Angular repo>.

## Scope

<Numbered list. Section numbers and names. Nothing vague.>

## Out of scope — do not touch

<Numbered list. Include the things a reasonable engineer would be tempted to fix while in there.>

## Prerequisites

<Which earlier slices must have landed, and the observable proof: "Order.qualifying exists and AccountMetrics::Calculator reads it"; "the account serializer exposes account_type and account.model's const mirrors the enum values".>

## Model spend

<"None — no model calls in this slice", or the estimate: model, tokens/call, cadence, $/month at current volume, with the doc section it comes from.>

## Gaps the plan must pin

<Each thing the document leaves open for this slice, phrased as a question. If none, say "None — the document is complete for this slice.">

## Traps for the review

<Slice-specific things the adversarial review must not accept. The skill already covers re-derived predicates, unstated defaults, changes to existing computation, and a contract change without the consuming repo's change; list only what is specific here.>

## Commit sketch

<Ordered, one concern each. The plan may revise it.>

## Gates

**Slice character:** <Foundation | Visible or computed values | Additive | Screen/component | Mechanical | Bug fix>.
**Pause at:** <All | After plan and after verification | After plan and at the end | At the end>, per the skill's gate table. All means after survey, after plan, after verification, and at the end.
At other phase boundaries, report progress and continue automatically through implementation, verification, adversarial review, fixes, and write-back. Exception stops in the skill always apply, including reassessment if the work changes a foundation.
**Finish:** Complete the required checks, reviews, fixes, and write-back; produce the handoff (branch, commits, the push command block — and the PR body at `/tmp/pr-<slug>.md` if this repo uses pull requests) and the final report. The end gate is this handoff, not a pause before writing it; the push is the engineer's. Do not merge or deploy.

## Reference pattern

<The one file to copy, by path, if the slice introduces a component, migration, job, or spec of a shape the repo already has.>
```

## What not to put in a slice prompt

- Restated rules from the document. Cite the section.
- Evidence rules, loop steps, review disposition, report format. The skill has them.
- Decisions the document already made. "Decisions already made — do not reopen" was a symptom of the document not being in the repo; once it is, the section is a citation.
- A `Mode` section. The skill's gates section and the prompt's `Gates` block cover it.
