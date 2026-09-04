# Packing a repo for an external AI

`bin/repomix-pack` bundles one of the seven `apps/*` repos into a single XML file you can hand to an AI tool that has no access to this container — ChatGPT, Gemini, a coworker's assistant.

Output lands in `repomix-out/`, which is gitignored. **Never commit a pack.** They go stale silently, so regenerate rather than reuse.

## Quick start

    $ bin/repomix-pack                       all seven app repos, both packs
    $ bin/repomix-pack insgt-ops             one repo, both packs
    $ bin/repomix-pack insgt-ops domain      one repo, one pack
    $ bin/repomix-pack --tokens insgt-api    per-file token tree, then the packs
    $ bin/repomix-pack --split 600kb         split any pack over the given size
    $ bin/repomix-pack --self-test           prove the secret guard fires
    $ bin/repomix-pack --help                usage plus every repo's globs

On the host the files are at `<wherever you cloned insgt-platform>/repomix-out/`, ready to drag into a browser upload.

Nothing is installed. The script shells out to `npx --yes repomix@1.18.0`, pinned in one variable at the top. On a freshly rebuilt container the first run re-downloads repomix and its Tree-sitter grammars — about 30 seconds. Later runs are instant.

## The two packs

**`<repo>.domain.xml` — the business layer, full fidelity.** Models, NgRx state, schema, services. Nothing is stripped: comments, method bodies and all. Deliberately so — a signature-only `order.rb` or reducer would be useless for reasoning about behaviour. This is the one to reach for when you want an answer about how something actually works.

**`<repo>.overview.xml` — whole-repo orientation.** Every file in the repo except assets and build output, with function and class bodies stripped by Tree-sitter and comments removed. The directory tree is complete, so files whose contents were skipped are still listed by name. Reach for this when you want "what is in this repo and how is it arranged."

## Measured sizes

Repomix's own token counts, read back from each run — not estimated from file size:

| Pack | Tokens | Fits a 200K window |
|---|---:|---|
| `insgt-api.overview` | 378,738 | no |
| `insgt-api.domain` | 303,811 | no |
| `insgt-ops.domain` | 231,889 | no |
| `insgt-ops.overview` | 175,428 | yes |
| `insgt-app.overview` | 78,548 | yes |
| `insgt-app.domain` | 74,781 | yes |
| `insgt-virtual-tour.overview` | 49,822 | yes |
| `insgt-photographers.overview` | 34,562 | yes |
| `insgt-photographers.domain` | 33,664 | yes |
| `insgt-virtual-tour.domain` | 24,979 | yes |
| `insgt-galleries.overview` | 14,126 | yes |
| `insgt-disclosure-gallery.overview` | 10,545 | yes |
| `insgt-galleries.domain` | 7,893 | yes |
| `insgt-disclosure-gallery.domain` | 7,011 | yes |

Only the two `insgt-api` packs and `insgt-ops.domain` need a 1M-context tool. If a pack is too big for yours, `--split 600kb` breaks it into numbered files — note that under `--split` even a pack that would have fit comes out as `<name>.1.xml`.

### Why `insgt-api.overview` is bigger than its domain pack

Because **Tree-sitter compression does nothing for Ruby.** Measured on this codebase with repomix 1.18.0:

| Input | Without `--compress` | With `--compress` |
|---|---:|---:|
| `insgt-ops` `src/app/**/store/**` (TypeScript) | 169,454 | 51,006 |
| `insgt-api` `app/models/*.rb` (Ruby) | 102,011 | 102,500 |

`rb` is a listed language, but compression returns the file essentially unchanged. The only lever that works on Ruby is `--remove-comments`, worth about 21% (102,500 → 81,127); `--remove-empty-lines` adds nothing on top. Both are already on for overview packs. A large Rails overview is therefore inherent, not a misconfiguration — point a 1M-context tool at it.

## What is in each pack

`bin/repomix-pack --help` prints these live from the script. Summarised:

| Repo | domain includes | overview additionally excludes |
|---|---|---|
| `insgt-api` | `app/models`, `services`, `workers`, `serializers`, `clients`, `mailers`, `views`, `lib/*.rb`, `lib/tasks/*.rake`, `db/schema.rb`, `config/routes.rb` | `public/ops`, `db/migrate`, `test`, `spec`, `app/assets`, `lib/assets`, `config/locales` |
| `insgt-ops` | `src/app/**/store`, `src/app/**/data-access`, `shared/models`, `shared/api` | `src/assets`, `cypress`, `scripts`, `*.html`, specs, styles, the 118 KB upgrade assessment |
| `insgt-app` | same four globs as ops | `src/assets`, `cypress`, `*.html`, specs, styles |
| `insgt-photographers` | store, data-access, `shared/models`, `shared/services` | `src/assets`, `cypress`, `scripts`, `tailwind.config.js`, `*.html`, specs, styles |
| `insgt-galleries` | `app/controllers`, `helpers`, `views`, `lib/*.rb`, `routes.rb`, `schema.rb` | `test`, tailwind config, stylesheets |
| `insgt-virtual-tour` | `app/controllers`, `helpers`, `views`, `lib/*.rb`, `routes.rb` | `test`, `storage`, stylesheets |
| `insgt-disclosure-gallery` | `src/app`, `src/environments` | `cypress`, specs |

Two glob choices are load-bearing and easy to get wrong if you edit them:

- **`src/app/**/store/**` is recursive on purpose.** In insgt-ops it matches 309 files across 36 directories including nested `listings/store/effects/`, `orders/store/services/` and four more. A flat `src/app/*/store/*` drops 40+ effects and service files.
- **`src/app/**/data-access/**` is not scoped to `features/`.** Two of the ten data-access directories — `kpis` and `marketing-sources` — sit at the top level of `src/app`. A `features/`-scoped glob silently drops both. This is the dual-convention trap from `CLAUDE.md`; the recursive glob covers both conventions with one pattern.

Angular templates are excluded from overview packs because Tree-sitter has no HTML grammar — in insgt-ops that is 832 KB of `.html` that `--compress` would leave verbatim, making templates the largest thing in the file. `--include-full-directory-structure` is on, so every template is still listed by name. Rails `.erb` and `.jbuilder` are kept: they are 13–68 KB, not 832 KB, and in `insgt-virtual-tour` and `insgt-galleries` the views *are* the product.

## Secrets — read this before you upload

These files go to a third party, so the script treats a leak as a hard failure. **If the guard fires, the pack is deleted and the run exits non-zero. There is no bypass flag.** Fix the leak instead.

Four layers:

1. **repomix defaults + each app's `.gitignore`.** Covers `node_modules`, `dist`, `vendor`, lockfiles, and the untracked `.env` / `master.key` / `cypress.env.json` files in most repos.
2. **A shared ignore list in the script** — credentials, keys, `config/secrets.yml`, `database.yml`, plus all binaries. This layer exists because repomix reads files with `fs`, so the `Read(**/.env)` deny rules in `.claude/settings.json` do **not** constrain it, and because `apps/insgt-api/config/secrets.yml` is tracked in git with real dev `secret_key_base` values, so no `.gitignore` hides it.
3. **Secretlint**, repomix's own check. Useful, but it excludes-and-warns rather than aborting, and it will not match a bare hex secret.
4. **A post-pack scan in the script.** This is the layer with teeth. It runs on the finished XML, so it does not depend on guessing a filename.

Layer 4 does two things. It greps for credential shapes — AWS keys, Stripe live keys, private key headers, Slack and GitHub tokens, JWTs, `secret_key_base`. And, more importantly, it reads the repo's local `.env`, `config/master.key` and `cypress.env.json`, and searches the pack for those **literal values**. That catches a credential hardcoded into a source file, which no ignore pattern ever could.

Not every `.env` entry is a secret — this one holds bucket names, CDN endpoints, support addresses, a database name and a billing phone number, all of which legitimately appear in source. Comparing every value blind produced 11 hits on insgt-api of which 2 were real. Values are therefore classified first: a name matching `SECRET|PASSWORD|TOKEN|_KEY|USERNAME|AUTH|CREDENTIAL|…`, or a long high-entropy value, and never a URL, an email address, or a short all-lowercase dictionary word.

Run `bin/repomix-pack --self-test` to watch the guard catch a planted credential. It is worth doing once so you know what a failure looks like.

### When the guard fires

The output names the variable that leaked and the source file it appeared in — never the value itself:

    scanning insgt-api.domain.xml for secrets
        LEAK  the local value of CRMLS_USERNAME appears in lib/crmls.rb
      REJECTED  insgt-api.domain.xml deleted. Fix the leak — do not upload this file.

Two legitimate fixes, in order of preference:

1. **Remove the credential from the source.** Move it to an environment variable, or delete it if it is a leftover in a comment. This is the right answer when the finding is real, and the fix lives in the app repo — a separate commit in a separate repo.
2. **Add the file to the ignore list** in `bin/repomix-pack`, but only when excluding it is defensible on content grounds anyway — a fixture-seeding task, a scratch script. Write down why in the comment next to it. Do not use this to silence a finding about real domain code; that leaves the credential in the repo and teaches the next person to ignore the guard.

**What this has already caught.** On its first real run the guard blocked both `insgt-api` packs on two credentials sitting in tracked source. Both are now fixed, in the `insgt-api` repo:

- `lib/crmls.rb:28` carried a live CRMLS RETS username and password in a plaintext `retscli` example comment, even though the code five lines below correctly reads `ENV['CRMLS_USERNAME']` / `ENV['CRMLS_PASSWORD']`. The comment now interpolates the variables instead.
- `lib/tasks/cypress_users.rake:7` hardcoded the value of `ACCOUNT_PASSWORD` — which `SessionsController#create` treats as an **account-wide authentication bypass**, not merely a test password. It now reads `ENV.fetch('ACCOUNT_PASSWORD')`.

Neither would have been found by Secretlint: one was a comment, the other a bare UUID. Both were caught by the literal-value scan, because the values were sitting in the local `.env` and turned up verbatim in the packed source.

Since both credentials were committed, they are still recoverable from git history. Rotating them is the follow-up that removing them from `HEAD` does not accomplish.

### What the guard does not do

It does not flag production URLs or internal hostnames — those are judgement calls, not secrets, and a guard that cries wolf gets switched off. It cannot catch a credential that is absent from the local `.env`, matches no known shape, and sits in a source file: for example a partner API key this codebase has never held in an env var. Skimming the pack's top-5 largest files before uploading is the only backstop for that.

If a repo has no `.env` on disk the script says so out loud (`no local secret values to compare`) rather than implying a clean bill of health.

## Changing a glob or adding a repo

Everything lives in the `case "$repo" in` block in `bin/repomix-pack`. Each branch sets three variables: `DOMAIN_INCLUDE`, `OVERVIEW_IGNORE`, and optionally `REPO_ALWAYS_IGNORE` (applied to both packs). Add a branch and a name in `ALL_REPOS` to add a repo.

After any glob change, run `bin/repomix-pack --tokens <repo>` and read the token tree — it shows which files dominate and whether an exclusion actually took effect.

`--include` is comma-separated, so **never use brace expansion**: `src/**/*.{ts,html}` splits at the inner comma. Write two globs.

## Troubleshooting

**The first run after a container rebuild is slow.** `~/.npm` is not a named volume, so a rebuild wipes the npx cache. About 30 seconds, once. If it becomes annoying, add `npm-cache:/home/vscode/.npm` as a volume in `.devcontainer/docker-compose.yml`.

**A pack looks out of date.** Each pack's header text carries the commit SHA and timestamp it was built from. Check it before trusting a file you generated earlier.

**A file you expected is missing.** It is most likely hidden by that app's own `.gitignore`, which repomix honours. That is also what makes `node_modules` and `.env` vanish for free.

**"no suspicious files detected" but you are still unsure.** That line is Secretlint (layer 3), not the script's guard. The script's own result is the `scanning …` block below it.

**Nothing should ever be written into an app repo.** The script uses an absolute output path for exactly this reason. If `git status` inside an app repo ever shows an `.xml`, that is a bug — report it.
