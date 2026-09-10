# Slice prompt template

A slice prompt supplies only what `slice-implementation` cannot know. Aim for 30–60 lines. If a prompt is growing past that, it is restating the document or the skill; cut it and cite instead.

```markdown
# <Document short name> — slice <N>: <one-line summary>

**Repo:** <one repo>. No changes elsewhere.
**Contract:** `docs/architecture/<doc>.md` §<a>, §<b>, §<c>. Read them; they are the rules.
**Skill:** `slice-implementation`. Also load: <repo skills, e.g. git-commit-messages, predeploy-review-rails, angular-core + app skill>.

## Scope

<Numbered list. Section numbers and names. Nothing vague.>

## Out of scope — do not touch

<Numbered list. Include the things a reasonable engineer would be tempted to fix while in there.>

## Prerequisites

<Which earlier slices must have landed, and the observable proof: "Order.qualifying exists and AccountMetrics::Calculator reads it.">

## Gaps the plan must pin

<Each thing the document leaves open for this slice, phrased as a question. If none, say "None — the document is complete for this slice.">

## Traps for the review

<Slice-specific things the adversarial review must not accept. The skill already covers re-derived predicates, unstated defaults, and changes to existing computation; list only what is specific here.>

## Commit sketch

<Ordered, one concern each. The plan may revise it.>

## Gates

<Which STOPs are real for this slice, per the skill's gate table, or "All."> 

## Reference pattern

<The one file to copy, by path, if the slice introduces a component, migration, job, or spec of a shape the repo already has.>
```

## What not to put in a slice prompt

- Restated rules from the document. Cite the section.
- Evidence rules, loop steps, review disposition, report format. The skill has them.
- Decisions the document already made. "Decisions already made — do not reopen" was a symptom of the document not being in the repo; once it is, the section is a citation.
- A `Mode` section. The skill's gates section and the prompt's `Gates` line cover it.