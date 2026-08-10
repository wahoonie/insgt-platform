---
name: git-commit-messages
description: Use this skill whenever writing, drafting, or revising a git commit message in any InsightPhotos repo (insgt-api, insgt-app, insgt-ops, insgt-site-sls, or any other repo in insgt-platform). Invoke on any request to commit, stage and commit, write a commit message, amend a message, or squash commits — including when a commit is a step inside a larger task and the message was not explicitly asked for. Defaults to short messages; expand only under the specific conditions below.
---

# Git Commit Messages

InsightPhotos is a solo-engineer polyrepo. Commit history is read by exactly one person, usually eight months later, usually mid-bisect. Optimize for that reader.

**The default is short.** A commit body is not a summary of the diff — the diff is right there. A body exists only to carry information the diff cannot.

---

## Tiers

Pick the smallest tier that fits. When torn between two tiers, pick the smaller.

### Tier 1 — Subject line only

The default. Use for anything where reading the diff answers "why."

- Dependency bumps, lockfile updates, config tweaks
- Formatting, lint fixes, import reorganization
- Copy and content changes
- Renames, file moves, straightforward extractions
- Adding a field, column, or route where the name says what it does
- Test additions that cover obvious cases

### Tier 2 — Subject + one or two sentences

Most feature work and most bug fixes. State what changed and why now. Stop.

- New features where the trigger or the constraint isn't obvious from the code
- Bug fixes where the cause is visible in the diff but the symptom isn't
- Refactors with a motivating reason beyond tidiness

### Tier 3 — Full body

Reserved. A commit qualifies only if at least one is true:

1. **The code misleads about intent.** A function name, file location, or handler type says one thing and the live path does another. This is the strongest trigger — it's the case where future-you will read the diff and reach the wrong conclusion.
2. **The change establishes or extends a pattern** other code should follow. Name the other location.
3. **There is a deploy or migration ordering constraint** — two-phase deploy, Sidekiq back-compat window, `strong_migrations` exception, blue/green asset dependency, or anything that breaks if applied out of order.
4. **A non-obvious decision was made among real alternatives**, and the rejected one looks better on its face.
5. **A revert, or a fix to a fix.** Say what the earlier attempt got wrong.

---

## Subject line

```
<type>: <imperative summary, ≤ 72 chars, no trailing period>
```

Types: `feat` · `fix` · `refactor` · `perf` · `test` · `docs` · `chore` · `build` · `revert`

- Imperative mood: "decrement counts by records removed," not "decremented" or "decrements."
- Name the behavior change, not the mechanism. `fix: prevent totalCount drifting below zero` beats `fix: add removedCount variable`.
- No scope prefixes. The repo is already known; the paths are in the diff.

---

## What belongs in a body

- **Why the current code is wrong** in a way the diff doesn't show — especially when naming or placement is misleading.
- **The live call path**, when it differs from what the function name implies.
- **Cross-references to sibling code** that already solves the same problem, or now needs to match.
- **Ordering and deploy constraints.**
- **Why a non-obvious test exists** — one sentence, only if someone might delete it as redundant.

## What does not belong in a body

- **A restatement of the diff.** If the sentence could be reconstructed by reading the changed lines, cut it.
- **A description of what the tests assert.** The spec file says that. Only *why a test exists* is ever worth a line, and only for tests whose purpose isn't self-evident.
- **A changelog of files touched.** `git show --stat` does this better.
- **Justification of the work itself.** No "this improves maintainability," no "this makes the code more robust."
- **Hedging or future work.** TODOs go in the code or the tracker, not in immutable history.

---

## Trailers

- **No `Co-Authored-By` trailer.** Single-engineer repo — there is no contributor graph to credit, and it pollutes `git shortlog`.
- **Never put a model name or version in a trailer.** It goes stale immediately and means nothing to a future reader.
- Permitted trailers: `Refs:`, `Reverts:`, `Co-Authored-By:` only when a real second human wrote code in that commit.

---

## Worked examples

### Tier 1

```
chore: bump @fortawesome packages to 7.2.0
```

```
refactor: organize imports in order-list.component.ts
```

### Tier 2

```
fix: null AccountMetric rates when denominator is zero

Rates were rendering as 0% for accounts with no orders in the window,
which reads as bad performance rather than no data.
```

### Tier 3 — earns the body

```
fix: decrement collection counts by records actually removed

deleteResourceSuccessDraft dropped totalCount and pageMax by a flat 1
whether or not the filter removed anything.

Despite the name, the live path is not a delete. Both callers invoke it
on a create, to pull the new record out of the search-results pool it
was picked from — organizations CreateChildSuccess and accounts
CreateOrganizationSuccess, both targeting searchCollection. Create an
organization without searching first and totalCount drops for a row it
never held, once per create, walking past zero.

Counts now track removedCount, derived from the filtered array. Matches
order.reducers.ts, which already computes this difference by hand when
clearing double-booked orders.
```

Qualifies on triggers 1 and 2: the handler name says delete, the live path is create; and it aligns with an existing pattern in `order.reducers.ts`. Note what was cut — the paragraph describing what the two specs assert. The specs are in the diff.

### Tier 3 — ordering constraint

```
feat: add suppressed_at to listings

Deploy before the serializer change in the next commit. The column is
nullable with no backfill, so old app instances ignore it safely, but
the serializer references it and will 500 on instances that predate
this migration.
```

---

## Rules

- **Default to Tier 1 or 2.** Tier 3 should be a small minority of commits. If most messages are coming out long, the tier test is being applied too loosely.
- **Never pad to reach a tier.** A body with nothing to say is worse than no body.
- **Wrap body text at 72 characters.** Blank line between subject and body.
- **One logical change per commit.** If the body needs the word "also," split the commit.
- **Don't narrate the tier choice** in the message or in conversation. Just write the message.