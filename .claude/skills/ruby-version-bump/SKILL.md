---
name: ruby-version-bump
description: Use this skill for any change to the Ruby interpreter version in a Rails repo — a patch bump such as 3.4.10 → 3.4.12, or the Ruby 4.0 move — in insgt-api, insgt-galleries, insgt-virtual-tour, or any other Ruby repo in insgt-platform. Invoke when a prompt names a Ruby version, `.ruby-version`, `.tool-versions`, `Gemfile.lock` RUBY VERSION, `BUNDLED WITH`, or mise. Owns the pin inventory, the Bundler pre-install trap, the per-host availability check, the untrusted-regexp exposure report, and the V1–V6 verification ladder, so a bump prompt only needs the from/to versions, the repos, and the reason.
---

# Ruby version bump

The only change is the Ruby version. One branch per repo, one commit per repo, the four pins and nothing else. Everything below was learned on the 3.4.10 → 3.4.12 bump of 2026-10-29 (insgt-api `1497ad8a`, insgt-galleries `b8c6db7`, insgt-virtual-tour `eee78cf`).

**Non-goals, always:** gem changes (`bundle install` only, never `bundle update`), a `BUNDLED WITH` change (that is a STOP, not a commit), fixing an absent or broken suite, host config, boy-scout edits. Each repo is its own git repository; every git command runs inside the repo it concerns.

---

## Survey (read-only, one table per repo)

1. **Pins.** Every `file:line` that encodes the version: `Gemfile` `ruby` directive, `.ruby-version`, `.tool-versions` or `mise.toml`, `Gemfile.lock` `RUBY VERSION`, then `Dockerfile*`, `.devcontainer/`, `app.json`, `.github/workflows/*`, `bin/setup`, `README*`, `docs/**`. Catch-all: `grep -rn -E '3\.4\.(10|11)' . --exclude-dir={node_modules,vendor,log,tmp,.git,public}` (grep is ugrep here; see `slice-implementation` evidence rules). A repo may carry both `.ruby-version` and `.tool-versions`; edit both, in place, never with `mise use`.
2. **Repo state.** Rails version, `BUNDLED WITH`, deploy branch and host read from the repo (`predeploy-review-rails` §1 says how; the prompt may be wrong), `git log --oneline origin/<deploy branch>..<deploy branch>` (unpushed commits ship with the merge push), Sidekiq present or not, error tracker present or not, what suite exists and its result on the current Ruby (the V3 baseline), and `bundle exec rails runner 'Rails.application.eager_load!; puts :ok'` on the current Ruby (the V2 baseline, so a warning can be told from a regression).
3. **Host availability row.** The target version's availability on *that repo's* host, with the evidence, marked verified or unverified. A confirmation for one host says nothing about another: Heroku having 3.4.12 did not establish that Render did. Render resolves the version from `Gemfile.lock` `RUBY VERSION` first, then `.ruby-version`, `.tool-versions`, the Gemfile directive, and fetches the exact `major.minor.patch` at build time; its build log prints `Ruby version: ruby 3.4.12 (2026-10-23 revision 366f5fdc00) +PRISM [x86_64-linux]`. Because Render auto-deploys on push to `main`, an unavailable version is a failed build on the live service.
4. **Untrusted-regexp exposure** (report only; relevant when the release carries Onigmo fixes and the app takes unauthenticated params):
   ```
   grep -rn -E 'Regexp[.](new|union|compile)' app lib config
   grep -rn -E '[.]match[?]?[(][[:space:]]*[^/]' app lib
   grep -rn -E '%r[{].*#[{]|/[^/]*#[{].*[}][^/]*/' app lib --include='*.rb'
   ```
   One line per hit: `file:line`, the pattern source, verdict `request/DB-sourced` or `developer-literal`. `String#match`/`match?` with a String argument compiles it; `Regexp.new(Regexp.escape(x))` is a literal; `where("col ~ ?", x)` is PostgreSQL, not Onigmo. **The third grep's `/…#{…}/` alternative also matches URL path segments inside string literals** (`"/orders/#{token}/gallery"`). Read each hit; interpolation inside a quoted string is a String, verdict `developer-literal`. Four of four hits on 2026-10-29 were URL strings.

STOP with the tables. Wait for the deploy-branch HEADs to be confirmed as the live release.

---

## Implement (per repo)

1. `mise ls ruby` shows the target installed; if not, `mise install ruby@<target>`. Do not touch mise global config.
2. **Pre-install the lockfile's Bundler under the new Ruby.** A fresh Ruby ships only its default Bundler, and `bundle install` under a Bundler other than `BUNDLED WITH` may rewrite that line. Check with `mise exec ruby@<target> -- gem list bundler`; if the lock's version is missing, `mise exec ruby@<target> -- gem install bundler -v <BUNDLED WITH>`. This installs into the mise Ruby's gem directory — not a repo change, not mise config. Then run every bundle command as `mise exec -- bundle _<BUNDLED WITH>_ <cmd>` from inside the repo so the version is explicit. (`mise exec --` is needed because mise activation is static in the Bash tool; `ruby`/`bundle` alone ignore the repo pin.)
3. Branch `chore/ruby-<x-y-z>` from the deploy branch. Edit every pin from the survey with `sed -i` (keeps the file's trailing-newline state). `bundle install`. `git diff Gemfile.lock` must be the `RUBY VERSION` line only. Under Bundler 2.6 that line carries the patch level (`ruby 3.4.12p148`); under Bundler 4 it does not (`ruby 3.4.12`). Both are fine.
4. Commit, Tier 2 per `git-commit-messages`, no trailers:
   ```
   Ruby 3.4.12

   Onigmo regexp compilation fixes (GitLab CVE-2026-89078, -93577,
   -97229, -110264). No gem changes.
   ```

---

## Verify (per repo)

- **V1** `bundle exec ruby -v` and `bundle exec rails runner 'puts RUBY_VERSION'` print the target.
- **V2** `bundle exec rails runner 'Rails.application.eager_load!; puts :ok'` prints `ok` with no warnings beyond the survey baseline.
- **V3** Suite green, matching the survey baseline. insgt-galleries and insgt-virtual-tour have Minitest scaffolding with zero tests (`0 runs`); say so and move on.
- **V4** Only if Sidekiq is present: boot it against local Redis with a 15-second timeout, expect the banner and a clean shutdown.
- **V5** Deliberate break: `mise exec ruby@<previous> -- bundle _<BUNDLED WITH>_ install` must fail with `Your Ruby version is <previous>, but your Gemfile specified <target>` and leave `git status` clean. If it does not fail, the Gemfile directive is wrong: STOP. Re-run V1 under the target afterwards.
- **V6** `git diff <deploy branch> --stat` lists only the pin files.

Then `predeploy-review-rails` with `<prod-ref>` = `origin/<deploy branch>`. For a pin-only diff the §2–§4 lenses have nothing to bite on; the review's value is §1 (what is live, what ships) and the host-availability row.

---

## Handoff (per repo)

Branch, commit SHA, `git diff <deploy branch> --stat`, then the host runbook.

**Render (insgt-galleries, insgt-virtual-tour):** fast-forward the deploy branch, `git push origin main`.
- S1 build log (dashboard → service → Events) names the target version in either wording Render has printed: `Using Ruby version <target> via …/Gemfile.lock` or `Ruby version: ruby <target> …`.
- S2 service Shell tab: `ruby -v`.
- S3 status Live, one Puma boot in Logs, no repeated boots.
- S4 one real public URL and its signature beyond a 200. Galleries: `https://gallery.insightphotos.net/i/<order token>` — first GET is the locked state (`<title>` is the short address, password form); POST `password=photos` renders the grid, N `.lozad` tiles with `data-fancybox="gallery"`. Virtual-tour: `https://insightlistings.com/<address-slug>/b/<order token>` — `<title>` ends `MLS #<number>`, `#carousel` holds N `carousel__slide` divs; `/heartbeat` returns `{"lub":"dub"}`. Galleries has no heartbeat route.
- S5 no error tracker in either: Logs tab for ten minutes after the first request, watching for exceptions and Puma worker restarts.
- Rollback: Events → previous successful deploy → "Rollback to this deploy" (prior image, no rebuild). No database in either app.

**Heroku (insgt-api, until the Render cutover):** merge, `git push heroku master`; S1 `Using Ruby version: ruby-<target>`; S2 `heroku run ruby -v -a <app>`; S3 `heroku ps -a <app>`; S5 `heroku logs --tail -a <app>`; rollback `heroku rollback -a <app>`.

**Finding smoke records in the dev DB (a prod restore):** `Order#token` is a hashid computed from the id, not a column, so `where(token:)` fails; `Listing#order` is a method, not an association, so `joins(:order)` fails. Use `Order.where(parent_id: nil)` filtered in Ruby by `order_event.tag == 'completed' && photos.exists?`, and `Listing.where.not(order_id: nil)` filtered by `Listing.select_virtual(order.token).present?`; `listing.property_website_url_branded` builds the tour path (swap `PROPERTY_WEBSITE_HOST` for the production host).

Close with the ratchet: anything the prompt got wrong, drafted as a rule for this file, not written until approved.
