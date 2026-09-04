# CLAUDE.md — insgt-platform

Keep replies concise. Lead with the key information, skip the preamble, and don't paste long code blocks the user can already read in the file.

When working with a third-party library, look up its official documentation rather than working from memory. Versions here span Angular 19–21 and Rails 7.1–8.0, so a recalled default is often wrong for the repo you are actually in.

Do not shorten variable names — `description` not `desc`, `listing` not `lst`. Applies to every variable, parameter, and property in every language here. Readability over brevity.

## This is a polyrepo shell

`/workspace` is the `insgt-platform` repo. It tracks only `.claude/`, `.devcontainer/`, `docs/`, and the `*.code-workspace` files — **not** the application code.

Every app, function, and library below is its own independent git repo:

- A change spanning two apps is two commits in two repos. There is no atomic cross-repo commit.
- `git status` at `/workspace` never shows application changes. Run git inside the app directory.
- Shared skills live here at the platform level; app-specific skills live in the app repo.

## Services run on the host, not in this container

Nothing runs inside the container. To reach a service use `host.docker.internal:<port>` — `localhost` resolves to the container itself. This applies to an Angular dev server calling the API, and to anything reaching Postgres or Redis.

| Repo | Stack | Dev port |
|---|---|---|
| `apps/insgt-api` | Rails 7.2, PostgreSQL/PostGIS, Sidekiq/Redis | 3000 |
| `apps/insgt-app` | Angular 21, NgRx, Material, Tailwind | 4200 |
| `apps/insgt-ops` | Angular 19, NgRx, Material, Tailwind | 4300 |
| `apps/insgt-photographers` | Angular 20, NgRx, Material, Tailwind | 4400 |
| `apps/insgt-disclosure-gallery` | Angular 21, DaisyUI, Tailwind 4 | 4500 |
| `apps/insgt-galleries` | Rails 7.1, Tailwind | 3001 |
| `apps/insgt-virtual-tour` | Rails 8.0, Tailwind | 3002 |
| `lib/insgt-ui` | Angular 21, Spartan NG, Tailwind — shared component library | — |
| `functions/*` | AWS Lambda — photo import, archiving, upload, download, marketing site | — |

**The Angular versions differ on purpose.** insgt-ops is on 19 and is not being upgraded right now. Never carry a convention from one app to another because both are "Angular" — load that repo's skill instead.

## AB 723

California law (BPC § 10140.8, effective 2026-01-01) requires disclosure when listing photos have been digitally altered. The `Photo → UnalteredPhoto` relationship is the source of truth: an UnalteredPhoto exists only when the photo carries material alterations. Standard adjustments — HDR, exposure, white balance — never trigger it.

Load the **`ab-723-compliance`** skill before touching alteration labeling, watermarks, download bundles, or disclosure galleries. That skill owns the rules; do not reason about them from memory.

## Packing a repo for an external AI

`bin/repomix-pack [repo] [domain|overview]` writes `repomix-out/<repo>.domain.xml` (business layer, full fidelity) and `<repo>.overview.xml` (whole-repo structure, signatures only) for the seven `apps/*` repos. See `docs/repomix-packs.md`; `bin/repomix-pack --help` prints the per-repo globs.

The `.xml` files are gitignored and regenerated on demand — never commit them, and never read one as a substitute for grepping the source. Every pack is scanned for secrets and deleted if anything is found; when that happens, fix the leak, do not bypass it.

## Where instructions live

| Layer | Owns |
|---|---|
| This file | Cross-repo orientation and the traps above |
| `<repo>/CLAUDE.md` | That repo's commands, traps, and non-obvious quirks |
| `.claude/skills/` | All conventions — Angular, NgRx, TypeScript, Rails, commits, AB 723 |
| `.claude/rules/` | Path-scoped pointers to a skill, nothing more |
| `docs/` | Reference material, read on demand |

Conventions are **owned by skills**, not by this file. To write a component, a reducer, a migration, or a commit message, load the relevant skill rather than inferring the pattern from code you happen to have open — several repos contain two coexisting patterns, and the older one is usually the more common.

`docs/` holds `overview.md` (system, user types, order lifecycle), `data-model.md` (entities), `compliance/ab-723.md` (full requirements), `repomix-packs.md` (packing a repo for an external AI), `runbooks/` (one deploy procedure per feature), `decisions/` (ADRs), and `services/` (per-service reference, mostly stubs).
