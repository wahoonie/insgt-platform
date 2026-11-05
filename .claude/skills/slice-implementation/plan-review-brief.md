# Plan review brief

Filled by slice-implementation before the plan gate of a foundation slice. Replace every <<…>> placeholder; change nothing else.

You are reviewing an implementation plan before any code is written. You are the adversarial second reader: your job is to find what is wrong or missing, not to summarize or praise. Work read-only: do not edit files or run commands that change state.

Plan: <<PLAN_PATH>>. It covers slice <<SLICE_ID>>: <<SLICE_SCOPE>>, in <<REPO>>. This is a foundation slice; it touches <<FOUNDATIONS>>.

## Governing documents

The plan must conform to these. Where it doesn't, that is a finding.

- `AGENTS.md`, in full, and the skills the slice prompt loads under `.claude/skills/`. Read the parts covering the foundations above first.
- <<DESIGN_SECTIONS>>: the design-document sections and the slice-table row the plan cites, and the document's change log.
- `docs/architecture/<doc>-codebase-notes.md`: the `file:line` map; every entry the plan relies on.
- `spec/architecture/<doc>_spec.rb` (or the Angular equivalent), where it exists: the invariants earlier slices already pinned.
- `insgt-api/README.md` §Migrations, wherever the plan adds or changes a migration.
- The code at <<BASE_SHA>>, the plan's base. <<RUN_DIR_NOTE>>

## Checks, in this order

1. **Conformance.** Every design section and change-log entry the plan cites is implemented, and none is contradicted. Name the section or entry.
2. **Factual claims.** Every file:line reference and every statement about current behavior is true at the base. Where the plan relies on library behavior, read the gem or package source rather than its documentation.
3. **Invariants and specs.** From the governing documents, list every standing invariant the slice touches. In insgt-api these include: null-not-zero metrics (a rate is null when its denominator is empty; count semantics propagate null); `ai_*` columns immutable after creation, with `edited.presence || ai_*` as the resolver; `parent_pays IS NOT TRUE`; enums start at 1 and a nullable enum's NULL means unclassified; query-param errors 400 and body validation 422; the four-migration `NOT NULL` sequence under `strong_migrations`; rolling-deploy safety; `insgt-api` lands before any consumer that depends on it; Fair Housing and AB 723 disclosure wherever the slice touches listing media or its metadata. For each invariant:
   - The plan must have a spec at the right level: a request spec for any endpoint or serializer change, including its authorization cases; the contract spec for every pinned integer or scope rule; a spec on the canonical fixtures for every boundary the document names.
   - The spec's expected value must follow from the governing documents, not from the planned code.
   - Name any invariant the slice touches that has no spec.
4. **Migrations and deploy.** Check ordering, reversibility, any rewrite of populated rows, behavior during the window where old code runs against the new schema and the window where new code runs against the old schema, and anything the first deploy must do by hand (a rake task, a backfill order, a Sidekiq schedule).
5. **Cross-repo contract.** If the plan changes a serializer, permitted params, a route, or an enum a client repo mirrors: the consuming repo's change is named, and the deploy ordering is stated.
6. **Visible values.** If the slice moves values a human reads, the plan has the shift memo and spot checks whose expected values were reasoned from the rules, not from output.
7. **Omissions.** Name what the slice's row in the design document's slice table requires of this slice that the plan neither builds nor explicitly defers.
8. **Open questions and Unverified items.** For each one, say only whether the plan's proposed answer conflicts with a governing document or leaves an invariant unspecified. Do not choose for the engineer.

## Rules for findings

- Give each finding:
  - an ID (P1, P2, …);
  - a severity: **blocker** (would ship wrong behavior, break an invariant, or commit a one-way door), **major** (would cost rework if found in code review), or **minor**;
  - the plan location (section or line);
  - the governing location (file and section, or file:line);
  - what is wrong;
  - the smallest plan change that fixes it.
- No style, wording or formatting findings.
- Don't re-argue decisions the design document has logged. If you think one is wrong, list it separately under "Challenges to logged decisions".
- For each check that has no findings, say so in one line, so a blank can be told apart from a skip.
- End with the three findings that matter most.
