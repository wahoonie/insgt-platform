# Rails upgrade — slice 3: 8.1.4, the landing target

**Repo:** `insgt-api`. Platform repo for the runbook and the write-back only.
**Contract:** `docs/architecture/rails-upgrade.md` v5 — §4.4 (the slice), §4.0 (the verification kit), §2 (sequencing), §3 (dependency audit), §1.3 (the 8.0 security end date, Sat 2026-11-07), §5 R1 (a gem fails at a major bump). Prompt: `docs/architecture/rails-upgrade-slices/slice-3.md`.
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Status:** **Deployed 2026-11-02 08:12:27 -0500 as v666** (`05e3fd42`; S7, S9 and SH pass — the record is in the runbook's Deploy log). **Approved 2026-10-28 by Dan** — all eight open questions as recommended, with three additions (A–C) and the smaller notes recorded in the next section and folded into the plan below. **Control dump done (Dan, 2026-10-28, on `master`):** `[7.2]` → `[8.0]` **plus** the `plpgsql` extension line re-qualified as `pg_catalog.plpgsql` and re-sorted — 8.0's dumper, not drift (recorded under "Gaps pinned" 1); the 8.1 dump is now expected to show those two hunks and nothing else. **Implemented and verified 2026-10-30** on insgt-api `chore/rails-upgrade-slice-3` off `master` f86877f5 (v665): five commits, `a5bfab70`…`5ffe92c4` (rebuilt after review round 1; the pre-review `934abe6b`…`41b8a546` differ only by a spec comment); Dan's 8.1 dump gave exactly the two predicted hunks (commit 5) and the round-trip load an empty diff; P1 (twice) to P8 and P-PROD pass. Deviations and one new finding (an Active Storage WARN line at every 8.1.4 boot) are under "Implementation record" at the end. Two review rounds done (no blocker, no open should-fix). Runbook `docs/runbooks/deploy-rails-upgrade-3.md` is `Deployed`.
**Survey date:** 2026-10-28, against insgt-api `master` 03e270c6 (production v663, 2026-10-28 08:53:30 -0400; `git diff --stat 4b464230 03e270c6` is empty, so the 2,045-example run slice 2 recorded on `4b464230` is this tree's baseline — production has since moved to **v664** (`96f89db8`, 2026-10-28 15:35:27 -0400, adding the `orders#show` 401 fix `55c86f1d`; the suite on it is 2,048 examples, 0 failures, 65.1 s) and the **Ruby 3.4.12** bump is deployed as **v665** (`f86877f5`, 2026-10-29 08:02:41 -0400, merging insgt-api `chore/ruby-3-4-12` `1497ad8a`: the four pins only, no gem change, outside the slices — §2 item 6's constant is now 3.4.12), so the slice branch is cut from `master` at or after `f86877f5` and every pre-push capture below is taken on v665) and the platform repo at `docs/rails-upgrade-slice-2-deploy` 1a241a3. Every 8.1.4 fact below comes from three rsync copies of the tree in this session's scratchpad, `/tmp/claude-1000/-workspace/5f87edf2-cfe4-4aac-9b66-b95ef752d526/scratchpad/`: `pristine` (8.0.5.1, as `master`), `work` (8.1.4 and the `app:update --force` run, diffed against `pristine`; `app-update/app-update.diff`, 708 lines, `app-update/app-update.log`, `app-update/files.txt`) and `probe` (8.1.4 with `config/application.rb:14–20` deleted: the suite, P3, P-PROD, the route tables `routes-pristine.txt`/`routes-probe.txt`, the probes). Rails 8.1.4 was installed into the Ruby 3.4.10 gem set by `bundle update rails --conservative` in the copy; source citations are the installed `activesupport-8.1.4`, `actionpack-8.1.4`, `activerecord-8.1.4`, `railties-8.1.4`, `actionmailer-8.1.4` gems and their `-8.0.5.1` counterparts for the before. No `rails db:*` command was run (the session's deny rule; OD7's dump is Dan's step, below).

Facts are stated with their source. ASSUMPTION, ESTIMATE and UNVERIFIED are labelled. Nothing below "should work": it ran, or it is under Unverified.

## Approval — decisions and modifications (Dan, 2026-10-28)

All eight open questions answered as recommended:

1. `action_text-trix` accepted; a §3.1 row; §8 item 7 unchanged (pulling `rails/all` forward to avoid one inert gem inverts the post-upgrade scoping).
2. The `application.rb:14–20` deletion rides in the bump commit. (Wording corrected: keeping the line is *pointless*, not impossible — a `Rails.gem_version < Gem::Version.new('8.1')` guard around it would let the deletion be its own commit, green on both versions, at the cost of a third commit with no bisect value. The body says the guard was considered.)
3. Commit 1 first, `return if performed?`, one spec file — plus addition A's exhaustive read, the unauthenticated examples, and `raw_photos_controller.rb:60` decided in this plan.
4. The `to_time` contract example is rewritten, not deleted: redundant with the boot raise, but the only place that says why the key must be absent, and it survives 8.2 removing the knob.
5. `bin/rubocop` accepted as its own tier-1 commit, as slice 2 did for the binstubs.
6. The OD7 dump sequencing confirmed, with addition B's control dump before and round-trip load after — three `db:*` sequences, all Dan's.
7. S-404 included: the only direct production proof of commit 1.
8. Build now, review Thursday, push Monday 2026-11-02.

Additions folded in before the first commit:

- **A. The double-`head` enumeration is exhaustive, not a three-line window.** Every `head` is produced by one of five things (the two literals, `render_no_content`, `find_instance`/`find_instance_by_public_id`, `destroy_instance`); every method containing one of them was listed by a parser walk and read for one question — can anything have rendered earlier in this request without halting? Result below ("The exhaustive read"): no sixth new site; two pre-existing cases recorded for §8. The trap now reads "a `return if performed?` outside the enumerated sites". Two spec additions: unauthenticated requests on each path, pinning whether the auth layer answers before the setter runs (it does not for orders `show` or raw photos — probed, below), and `raw_photos_controller.rb:60` decided here.
- **B. A control dump on 8.0.5.1 before the 8.1 dump, and a round-trip load after.** `db/schema.rb` has never been re-dumped under 8.0, so "header-only" assumed the committed file equals what the current dumper writes. Dan runs the four `db:` commands on `master` before the branch is cut, expects `[7.2]` → `[8.0]` and nothing else, and discards the result; anything else is pre-existing drift, understood before the 8.1 STOP rule means anything. After commit 5, the committed `[8.1]` file is loaded into a clean test database and dumped again; the diff must be empty — P1 as sequenced never loads the new file, so this is the only proof that the `[8.1]` header loads under 8.1's compatibility class and reproduces itself.
- **C. The root cause goes to §8 so the patch does not become the fix.** `find_instance` renders as a side effect and returns false-or-instance; its 55 callers were written defensively against that, which is why the second guards exist. A §8 item in the v6 write-back: make the return value the idiom, or move the miss to a `rescue_from` → 204. Off this branch.

Smaller notes, folded in: DST ends Sun 11-01 and the push is the next morning — S8's `-0800`/`PST` already accounts for it; S9's "on time" is judged in UTC; any time-zone-shaped error in SH on Monday is a DST suspect before it is an 8.1 suspect. S7's `DoubleRenderError` watch only sees a site someone hits in the hour (another reason for A). The runbook Summary carries one line placing this push in the remaining schedule (slices 4 and 5, the quiet week, the Render rehearsal — §6) so Mon/Tue/Wed is not read as the end of it.

## Scope (the prompt's five items, by §4.4 number)

1. `Gemfile:29` → `gem 'rails', '~> 8.1.4'`; the lock diff §4.4 expects (resolved below). **As found:** one line §4.4 does not name — `action_text-trix (2.1.19)` enters the lock as Action Text 8.1's new runtime dependency (open question 1).
2. `app:update --force` on an rsync copy, the complete diff captured (below) and §4.3's table with the 8.1 deltas applied file by file. **As found:** the 8.1 shim (six flags, all commented) accepted; `config/ci.rb`, `bin/ci`, `bin/dev`, `bin/setup` rejected; `bin/rails` and `bin/rake` identical this time; `bin/rubocop` differs by one comment (open question 5); `active_storage:update` copied nothing.
3. §4.4 item 3, the `config/application.rb:20` line. **Decided by the survey: delete it, lines 14–20, inside the bump commit** — on 8.1.4 any set value deprecates at boot and the test environment raises; on 8.0.5.1 the deleted line also fails the boot, so the deletion and the bump are one commit (open question 2).
4. §4.4 item 4, the `db/schema.rb` re-dump from a clean test database (OD7). **As found:** the three `t.float` columns are PostgreSQL `double precision`, so no `limit:` is coming; prediction header-only; **Dan runs three `db:` sequences** — a control dump on `master` before the branch is cut, the 8.1 dump after commit 4, a round-trip load after commit 5 (addition B, decision 6).
5. §4.4's breaking-change list traced with `file:line`, the spec plan, S11, `docs/runbooks/deploy-rails-upgrade-3.md`. **As found:** the `head` change is wider than the two literal sites §4.4 names — five `find_instance`-then-`render_no_content` setters answer a missing record with two `head`s, which 8.1 turns into a 500 (open question 3); an exhaustive read of every head-producing call site (addition A) found no sixth. Deadline: in production before Sat 2026-11-07; the push is **Mon 2026-11-02, 09:00–11:30 PT** (open question 8).

## Out of scope — do not touch

The prompt's four: every flag in `new_framework_defaults_8_1.rb` and `config.load_defaults`; the `.or` sites' SQL and `belongs_to` (slice 4); `config/ci.rb`, `bin/ci`, `rails/all`, any gem beyond `rails`, the rejected environment files; a dump taken from the development database. Plus, found in the survey and left alone, each a §8 item in the v6 write-back: `NotificationAudiencesController#set_notification_audience` (`app/controllers/notification_audiences_controller.rb:39–40` — a missing audience raises `NoMethodError` on `nil.notification_id` before any `head`; pre-existing, not an 8.1 change); `OrdersController#download_files` (`orders_controller.rb:476–477` — `find_instance` heads on a miss and `return render_unauthorized if @order.blank?` then renders: a render after a head, which `render` has raised `DoubleRenderError` on since before 8.0 — probed on both copies, below; the Lambda's path; one `return if performed?` on its own branch); `OrdersController#show` without credentials (`show` is exempt from `authenticate_with_jwt`, `:6–8`; `set_order` leaves `@order` nil and renders nothing; the `show` template then raises `ActionView::Template::Error` on both versions — pre-existing; **fixed after the survey** by `55c86f1d` on `master`, prerequisites table); the `find_instance` contract itself (addition C); `config/initializers/content_security_policy.rb` (the 8.1 template adds four comment lines to a file §8 item 2 deletes — rejected, below); the `upsert_all` at `lib/tasks/marketing_source.rake:41` (on a class, not an association — 8.1.0's deprecation does not reach it; still unspecced, §8); `StringUtils` and its `mb_chars` (`string_utils-1.0.8/lib/string_utils.rb:169–170`, off the app's path; 8.1 deprecates `mb_chars`, §8 item 6); the 24 rack `:unprocessable_entity` warnings (§8 item 1).

---

## Phase 0 — survey

### Done

Read §4.4, §4.0, §4.3 (v5, as built), §2, §3, §1.3, §5–§9 of the design document, the slice 2 and 3 prompts, the slice 2 plan and runbook, and the codebase notes; re-verified every notes row this slice depends on against 03e270c6; resolved the 8.1.4 lock on a scratch copy and installed it; ran `bin/rails app:update --force` on a copy and diffed it against a pristine copy; read the installed 8.1.4 `to_time` writer and reader, railtie, `load_defaults` blocks, `head`, `remote_ip`, health controller, JSON renderer and schema dumper sources, and the 8.1.0–8.1.4 CHANGELOG headlines of nine framework gems; booted the copy in test with and without the `application.rb` line, in development, and in production mode with Honeybadger reporting off; ran the full suite twice on 8.1.4 (plain and `CI=1`); diffed the route tables; ran a Sidekiq job end to end on 8.1.4; ran a throwaway request spec for the double-`head` path on both versions; queried the development database for every `real`/`double precision` column.

### Prerequisites — landed and pending (facts)

| Prerequisite (§4.4, prompt) | Evidence |
| :-- | :-- |
| Slice 2 deployed; `Rails.version` → `8.0.5.1`; `loaded_config_version` → `7.2` in a production runner | `docs/runbooks/deploy-rails-upgrade-2.md` Deploy log: **v663** `03e270c6`, 2026-10-28 08:53:30 -0400; S3 printed `8.0.5.1` and `:zone`; S10 `7.2`; S8 `2026-11-02 10:00:00 -0800` / `PST` / `ActiveSupport::TimeZone`; `Booted Rails 8.0.5.1 application in production environment` on `backgroundworker.1` at 12:53:38 UTC; S0 notice `92126f23-…`; S4 `["Carlsbad", "Oceanside", "Leucadia"]`; S-RT identical to v662; S7 pass (`status=5` 0; the only class `ActionController::RoutingError`, 2 lines); S9 pass (check-in 13:36 UTC) |
| §4.3's commits on `master` | `git log`: `671c3c6b`, `df0e12ec`, `df7826c5`, `f1b2af6e`, `4b464230`, merged by `03e270c6` |
| The suite green with `:raise` | 2,045 examples, 0 failures, 0 deprecation lines at `4b464230` (notes, "slice 2 runs"), whose tree equals `03e270c6` |
| **SH clean since slice 2** | **Passes** (read 2026-10-29 at about 21 h, Dan's call; runbook step 7): no unresolved error since the push, no `RailsDeprecation`. The one resolved error in the window is the `orders#show` no-credential 500 this survey found (below), fixed on its own branch — insgt-api `55c86f1d`, merged into `master` as `96f89db8` (2026-10-28 15:33 -0400) and deployed as **v664** (15:35:27 -0400). **So `master` has moved past this survey's baseline `03e270c6`:** `set_order` is restructured (`orders_controller.rb:681–701`; the `find_instance` this plan cites at `:688–689` is now `:699`, inside the new `set_order_for_current_user`), and `spec/requests/orders_show_authentication_spec.rb` exists. Re-verify the `orders_controller.rb` lines and rerun the baseline count on the new `master` before cutting the branch |

### Codebase notes — rows this slice depends on, re-verified

| Notes row | Today (03e270c6) | Drift |
| :-- | :-- | :-- |
| `Gemfile:29` `'~> 8.0.5'`; `Gemfile:10` `gem 'benchmark'` | same | none |
| `application.rb:12` `load_defaults 7.2`; `:14–20` the `:zone` comment and line; `:49` `draw_routes = false` | same | none; the block is deleted by this slice (below) |
| `db/schema.rb:13` `ActiveRecord::Schema[7.2].define(version: 2026_10_07_120001)`; `:903, 970, 972` the three `t.float` | same | the UNVERIFIED type is now known: all three `double precision` (below) |
| `application_controller.rb:303` `head :no_content` (inside `render_no_content`, `:302–305`); `orders_controller.rb:597` `head :ok` (first statement of `order_event`, `:594–598`) | same | the row understated the exposure: `render_no_content` has 35 direct call sites and 107 more through `find_instance`, `find_instance_by_public_id` and `destroy_instance`; five follow a `find_instance` that already headed (below) |
| `transactions_controller.rb:55` `request.remote_ip` → `client_ip` | same | none |
| `config/routes.rb:4` `get 'up' => 'rails/health#show'` | same | none |
| the 10 `.or(` sites: `account_query.rb:378`, `property_query.rb:61, 70, 79, 80, 81`, `user_query.rb:314`, `notification_query.rb:29, 35`, `phone_number.rb:209` | same | none; the `#merge`/`#or` fix is 7.2.3's (v5) |
| `config/database.yml:4, 24` `pool:` | same | none; 8.1.4 boots with it (P-PROD below) |
| `test.rb:18` `eager_load = ENV["CI"].present?`; `:58` `:raise`; `production.rb:84–85` `report_deprecations = true` / `:notify` | same | none |
| `new_framework_defaults_8_0.rb:18, 25, 30` all commented; `new_framework_defaults_8_1.rb`, `config/ci.rb`, `bin/ci`, `bin/dev` absent | same (`ls`) | none |
| `spec/architecture/rails_upgrade_spec.rb:1–120`, 11 examples | same | one example (`:23–25`) cannot run on 8.1.4 (below) |
| `8-1-stable active_support.rb:131–137` "writer always warns"; `railtie.rb:142–147` `set_configs` forwards | installed 8.1.4: `active_support.rb:131–137` (writer) **and `:124–129` (the reader warns too)**; `railtie.rb:142–147` | reader row added |
| `8-1-stable configuration.rb:335–342, 343–367` "the 8.0 block has no `to_time` line; the 8.1 block = …" | installed 8.1.4: `when "8.1"` at `:343–367` as listed; **no `load_defaults` block sets `to_time_preserves_timezone` at all** (`grep` of `configuration.rb` → only the `when` lines) — the 5.0 block's `:offset` is gone, so with our line deleted no key reaches the writer | consequence added |
| `date +%z` → `+0000` | same | none |

Collision greps: `grep -rn "to_time_preserves_timezone" app config lib spec` → `config/application.rb:20` and `spec/architecture/rails_upgrade_spec.rb:24` only; `grep -rn "performed?" app` → one comment (`accounts_users_controller.rb:37`), no call; `grep -rn "ActionText\|action_text\|has_rich_text" app lib config` → empty.

### Fresh facts the plan rests on

**Lock resolution** (`bundle update rails --conservative` in the `work` copy; `diff -u pristine/Gemfile.lock work/Gemfile.lock`):

- the 13 gems and their `(= …)` pins `8.0.5.1` → `8.1.4`; `DEPENDENCIES` `rails (~> 8.1.4)`; 14 checksum lines replaced;
- `activesupport` drops `benchmark (>= 0.3)` and adds `json` (both as §1.2 predicted; `benchmark (0.4.x)` stays through `Gemfile:10`, `json` was already locked);
- **`action_text-trix (2.1.19)` enters the lock** — `actiontext (8.1.4)` depends on `action_text-trix (~> 2.1.15)` (`actiontext-8.1.4.gemspec:31`); it depends only on `railties`. Its engine (`action_text-trix-2.1.19/lib/action_text/trix/engine.rb`) has one initializer that appends `trix.js`/`trix.css` to `config.assets.precompile` **only `if app.config.respond_to?(:assets)`** — this API-only app has no asset pipeline (the 8.1 `app:update` created and removed `assets.rb` for that reason), so it is inert; every boot below loaded it without incident. It is loaded because `rails/all` (`application.rb:3`) loads Action Text (§8 item 7). Not a Gemfile change, not a major bump; §2.6's "no gem added" is about the Gemfile and §3.1's table needs a row (open question 1);
- nothing else moves: `minitest (5.27.0)`, `rack (3.2.4)`, `racc`, `uri`, `useragent`, `rails-dom-testing`, `rails-html-sanitizer` as before.

**`app:update --force` on 8.1.4** (`work` copy; run log and decision per file; `--force` accepted as in 8.0):

| Generated file | `app:update` said | What the template would do (from the diff) | Decision |
| :-- | :-- | :-- | :-- |
| `config/boot.rb`, `config/initializers/inflections.rb`, `bin/rails`, `bin/rake` | identical | — | — (slice 2 already took the 8.0 binstubs) |
| `config/application.rb` | force | keeps `load_defaults 7.2`; drops the `:zone` block (`:14–20` — which this slice deletes anyway), the autoload lines (`:28–29`), both `config.hosts` (`:32–33`) and the `draw_routes` block (`:46–49`); double quotes | **reject** |
| `config/environment.rb` | force | drops `Jbuilder.key_format` and `Phoner` (4 changed lines) | **reject** |
| `config/puma.rb` | force | the 8.0 delta again: `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]`, quotes, a `WEB_CONCURRENCY` comment | **reject** (slice 2's ruling) |
| `config/environments/development.rb` | force | 33 changed lines (ngrok host, `:null_store` branch, `disallowed_deprecation*`) | **reject** |
| `config/environments/production.rb` | force | **`report_deprecations = false`**, no `:notify` (undoes slice 1); drops the SendGrid block, the logger chain, the two `/up` exclusions; adds `silence_healthcheck_path`, `assume_ssl`, `TaggedLogging.logger(STDOUT)` | **reject** |
| `config/environments/test.rb` | force | **`:raise` → `:stderr`** (undoes slice 1's gate); drops `host_authorization`, `disallowed_deprecation*`; `default_url_options` → `example.com` | **reject** |
| `config/initializers/content_security_policy.rb` | force (was identical on 8.0) | four new comment lines (`content_security_policy_nonce_auto`) in a file that is meaningless API-only and slated for deletion (§8 item 2) | **reject** — comment-only, but §4.3's "accept if comment-only" was written for `inflections.rb`/`puma.rb`, not for a file the follow-up list deletes; one sentence in commit 4's body |
| `config/initializers/cors.rb`, `filter_parameter_logging.rb` | force | the allow-list replaced (60 lines); the filter list narrowed (10 lines) | **reject** |
| `config/initializers/assets.rb` | create, then remove | net: no file | — |
| `config/initializers/new_framework_defaults_8_1.rb` | create | six commented flags: `action_controller.escape_json_responses = false`, `active_support.escape_js_separators_in_json = false`, `active_record.raise_on_missing_required_finder_order_columns = true`, `action_controller.action_on_path_relative_redirect = :raise`, `action_view.render_tracker = :ruby`, `action_view.remove_hidden_field_autocomplete = true`; no ERB | **accept, verbatim** (commit 4); slice 5b flips and deletes |
| `config/ci.rb` | create | `CI.run` with `bin/setup --skip-server`, `bin/rubocop`, `bin/rails test`, `db:seed:replant` | **reject** (§4.4: an RSpec repo with no CI; `bin/rails test` would run nothing) |
| `bin/ci` | create | requires `active_support/continuous_integration` and `config/ci.rb` | **reject** |
| `bin/dev` | create | `exec "./bin/rails", "server", *ARGV` | **reject** (slice 2's ruling; the platform `bin/dev` owns the servers) |
| `bin/setup` | force | the 8.0 template again plus `db:reset` on `--reset`; its tail still `exec "bin/dev"` | **reject** (slice 2's ruling) |
| `bin/rubocop` | force | **one comment line** (`# explicit rubocop config` → `# Explicit RuboCop config`) | **accept** (open question 5 — it is the whole of commit 3) |
| `rails active_storage:update` | ran | `diff -rq pristine/db/migrate work/db/migrate` → identical; the three 2026-01-29 migrations stay | nothing to do |

No generated file is absent from this table. Gap: no STOP.

**`to_time` on 8.1.4.** The knob is deprecated in both directions and the behaviour is unconditional:

- `activesupport-8.1.4/lib/active_support.rb:124–129` — the **reader** `self.to_time_preserves_timezone` calls `ActiveSupport.deprecator.warn("`config.active_support.to_time_preserves_timezone` is deprecated and will be removed in Rails 8.2")` before returning the ivar; `:131–137` — the **writer** warns the same and stores the value;
- `active_support/railtie.rb:142–147` — `active_support.set_configs` still forwards every `config.active_support` key to a writer, so a set key reaches the deprecator during initialization;
- `railties-8.1.4/lib/rails/application/configuration.rb` — no `load_defaults` block sets the key (the 7.2/8.0 `:offset`/`:zone` lines are gone), so with no app line the writer is never called;
- `core_ext/date_and_time/compatibility.rb` — `preserve_timezone` no longer exists (only `utc_to_local_returns_utc_offset_times`); `time_with_zone.rb:501–503` — `to_time` is `getlocal(time_zone)` unconditionally.

Boot, test environment, 8.1.4, **with `application.rb:20` present** (`probe` copy before the deletion; `RAILS_ENV=test bin/rails runner`):

```
activesupport-8.1.4/lib/active_support/railtie.rb:145:in 'Kernel#public_send': DEPRECATION WARNING: `config.active_support.to_time_preserves_timezone` is deprecated and will be removed in Rails 8.2 (called from <top (required)> at …/probe/config/environment.rb:5) (ActiveSupport::DeprecationException)
```

With lines 14–20 deleted: the boot succeeds; `Rails.application.config.active_support.key?(:to_time_preserves_timezone)` → `false`; `loaded_config_version` → `7.2`; and **the reader raises under `:raise`** (`ActiveSupport.to_time_preserves_timezone` → `ActiveSupport::DeprecationException`, the same message). The behaviour is identical to 8.0.5.1 on every value the contract spec pins:

```
S8: 2026-11-02 10:00:00 -0800 | %Z=PST | zone.class=ActiveSupport::TimeZone | utc_offset=-28800 | dst=false
arith: -28800    (parse('2026-10-31 10:00').to_time + 2.days)
slice1: -25200   (2026-10-23 10:00)
```

Development boot with the line deleted: `0` `DEPRECATION` lines. **Consequences:** the line is deleted (keep and replace are impossible: any value warns; nothing replaces an unconditional behaviour); the deletion must ride in the bump commit — on 8.0.5.1 the deletion alone fails the test boot (the 7.2 `load_defaults` value `:offset` reaches the 8.0 writer, slice 2's plan), on 8.1.4 the bump alone fails it (above) — so §4.4's separate commit 4 cannot exist as a green step; the contract example at `rails_upgrade_spec.rb:23–25` (`expect(ActiveSupport.to_time_preserves_timezone).to eq(:zone)`) is rewritten to pin the **absence** of the key; and **no production command may call the reader** — under `:notify` it would send a `RailsDeprecation` to Honeybadger and poison SH (slice 2's S3 second line and P-PROD's `p ActiveSupport.to_time_preserves_timezone` are both replaced below).

**`head` on 8.1.4 — the double-`head` sites.** `actionpack-8.1.4/lib/action_controller/metal/head.rb:28` — `raise ::AbstractController::DoubleRenderError if response_body`; `:52` — `head` ends with `self.response_body = ""`. 8.0.5.1's `head.rb` has no such check, so on 8.0 a second `head` silently overwrote the first. In this app `head` is called at two literal sites (notes), but `render_no_content` (`application_controller.rb:302–305`, `head :no_content; false`) has 35 direct call sites, and `find_instance` (`:186–194`, 55 callers) and `destroy_instance` (`:181–184`, 51 callers) call it on a miss and after a destroy. **Five setters call `find_instance` and then `render_no_content` again when the instance is blank** — the second guard is dead on 8.0 and a 500 on 8.1:

| Setter | Lines | Before-action for |
| :-- | :-- | :-- |
| `OrdersController#set_order` | `orders_controller.rb:688–689` | `show`, `update`, `destroy`, `order_event`, `child`, `contractors`, `home_entry`, the upload/download URL actions (`:20–23`) |
| `TransactionsController#set_transaction_order` | `transactions_controller.rb:74–75` | `order_transactions` (`GET /orders/:id/transactions`, `routes.rb:234`) |
| `RawPhotosController#set_order` | `raw_photos_controller.rb:54–55` **and `:60`** (a third `head` after either branch) | every action (`:5`; `/orders/:order_id/raw_photos…`, `routes.rb:184`) |
| `ListingRoomsController#set_listing_room` | `listing_rooms_controller.rb:30–31` | `show`, `update`, `destroy` (`:2`; `routes.rb:41`) |
| `ListingPropertyFeaturesController#set_listing_property_feature` | `listing_property_features_controller.rb:30–31` | `show`, `update`, `destroy` (`:2`; `routes.rb:43`) |

Proof (a throwaway request spec, `jwt_headers_for(create(:user))`, run on both copies and deleted):

```
8.0.5.1 (pristine):  2 examples, 0 failures            GET /orders/0 → 204; GET /listing_rooms/0 → 204
8.1.4   (probe):     2 examples, 2 failures
  Failure/Error: head :no_content
  AbstractController::DoubleRenderError: Render and/or redirect were called multiple times in this action. …
  # ./app/controllers/application_controller.rb:303:in 'ApplicationController#render_no_content'
  # ./app/controllers/orders_controller.rb:689:in 'OrdersController#set_order'
  # ./app/controllers/listing_rooms_controller.rb:31:in 'ListingRoomsController#set_listing_room'
```

A second throwaway spec then ran all five paths with a JWT, with no credentials, and with a bogus `access_token`, on both copies (`jwt_headers_for(create(:user))`; `RAISED` is the exception class the request raised in the test environment):

| Request | 8.0.5.1 | 8.1.4 |
| :-- | :-- | :-- |
| `GET /orders/0`, JWT | `204` | `DoubleRenderError` |
| `GET /orders/0`, no credentials | `ActionView::Template::Error` (pre-existing: `show` is exempt from the JWT check, `set_order` renders nothing, the template dereferences nil) | same |
| `GET /orders/0?access_token=bogus` | `204` | `204` (one head, `:686`) |
| `GET /orders/0/transactions`, JWT | `204` | `DoubleRenderError` |
| `GET /orders/0/transactions`, no credentials | `401` | `401` (`prepend_before_action :authenticate_with_jwt`, `:3`) |
| `GET /orders/0/transactions?access_token=bogus` | `401` | `401` |
| `GET /orders/0/raw_photos`, JWT | `204` | `DoubleRenderError` |
| `GET /orders/0/raw_photos`, no credentials | `204` | `204` (one head, `:60`) |
| `GET /orders/0/raw_photos?access_token=bogus` | `204` | **`DoubleRenderError`** (`:58` then `:60`) |
| `GET /listing_rooms/0`, JWT | `204` | `DoubleRenderError` |
| `GET /listing_rooms/0`, no credentials | `401` | `401` |
| `GET /listing_property_features/0`, JWT | `204` | `DoubleRenderError` |
| `GET /listing_property_features/0`, no credentials | `401` | `401` |
| `GET /orders/0/download_files` | `DoubleRenderError` | `DoubleRenderError` (pre-existing: a render after a head, `:476–477`) |

So the auth layer answers before the setter on three of the five paths; on orders `show` the double head needs a JWT (without one the request fails in the template, pre-existing), and on raw photos **it is reachable without a token** — a bogus `access_token` heads at `:58` and again at `:60`. **No existing spec reaches any of the five**: the full suite on 8.1.4 is green apart from the `to_time` reader example (below), and `grep -rln "listing_rooms\|listing_property_features\|raw_photos\|order_transactions" spec/requests` → empty. In production the symptom would be a 500 (`DoubleRenderError`) on every `GET /orders/<missing or inactive id>` from a logged-in insgt-ops or insgt-app user, instead of today's 204.

**The exhaustive read (addition A).** Every `head` this app sends comes from one of five things: the two literals (`application_controller.rb:303` inside `render_no_content`, `orders_controller.rb:597`), `render_no_content` (35 direct call sites outside its definition), `find_instance` (**55 calls**), `find_instance_by_public_id` (1) and `destroy_instance` (51; it heads after the destroy). A Prism walk over `app/controllers/**/*.rb` (`scratchpad/head_callers.rb`, output `head_callers.txt`) listed every method containing one of these — **127 methods, 140 call sites** — with every rendering-ish call inside it in source order (`render*`, `head`, `find_instance*`, `destroy_instance`, `authorize*`, `authenticate*`, `set_*`, `find_current_user`), and each was read for the one question: can anything have rendered earlier in this request without halting? Only head-after-render and head-after-head are new in 8.1; render-after-head raised already (`rendering.rb:166` on 8.0.5.1, `:172` on 8.1.4). Results:

- **95 methods** have a single head-producing call and no other rendering call (`def destroy; destroy_instance(@x); end`, `def set_x; find_instance(X); end`, a `sort` ending in `render_no_content`, a guard that is the first statement). One head at most.
- **32 methods** have more than one rendering-ish call. Ten are one `find_by` plus one guard (`accounts_order_metrics#set_account`, `accounts_users#set_account`, `imports#set_order`, `listings#find_listing_for_virtual_tour`, the three `sort`s, `order_url_groups#set_order_url_group`, `order_urls#set_order_url`, `unaltered_photos#set_photo`) — one head. Eight `destroy` actions precede `destroy_instance`/`render_no_content` with `return render_unauthorized …`/`return render_errors …` (`accounts:110–116`, `accounts_users:43–46`, `flyers:47–51`, `headshots:38–41`, `listing_photos:28–31`, `listings:102–106`, `phone_numbers:49–53`, `users:103–106`) — returned, safe. Three `return render_no_content …` guards (`accounts_metrics:22`, `order_urls:120`, `users:131`) — safe. Three if/else setters head once per branch (`accounts_users#set_accounts_user :102–110`, `marketing_events#set_marketing_event :46–56`, `users#set_user :253–260`) — safe. `orders#order_event` (`:594–616`) heads first and returns. That leaves the **five setters** (head after head — new) and **two pre-existing cases**: `orders#download_files` (`:473–484`, render after head, probed above on both versions) and `notification_audiences#set_notification_audience` (`:38–41`, `NoMethodError` before any second head).
- Implicit renders after a conditional head (`transactions#show :12–14`, `order_urls#panorama :39–42`, `users#self :50–53`, `accounts_users#index :6–9`) are skipped by Rails when `performed?`, and a before-action that renders halts the chain, so no action body runs after a before-action's head. `render_ok` (`application_controller.rb:307–310`) is `render json: {}, head: :ok` — a `render` with an ignored `head:` option, not a `head`. `set_order_with_access_token` (`:19–32`) and `find_current_user` (`:237–243`) render nothing.

**No sixth new site.** The enumerated sites for commit 1 are the five setters; the trap reads "a `return if performed?` outside the enumerated sites".

**The suite on 8.1.4** (`probe` copy: Gemfile and lock at 8.1.4, `application.rb:14–20` deleted, nothing else changed; the log filter dropped Ruby `warning:` lines, so the 24 rack warnings are not counted here):

```
plain:  2045 examples, 1 failure   (1 min 10.84 s)      CI=1:  2045 examples, 1 failure   (1 min 7.57 s)

rspec ./spec/architecture/rails_upgrade_spec.rb:23 # Rails upgrade contract to_time preserves the receiver zone (§4.2 item 2, §4.3 gap 1) opts in to the zone behaviour
     Failure/Error: expect(ActiveSupport.to_time_preserves_timezone).to eq(:zone)
     ActiveSupport::DeprecationException: DEPRECATION WARNING: `config.active_support.to_time_preserves_timezone` is deprecated and will be removed in Rails 8.2 (called from … rails_upgrade_spec.rb:24)
```

`grep -c "DEPRECATION WARNING"` → `1` in each run, the failure's own message. So: no other 8.1 deprecation fires under `:raise`, eager-loaded or not — not `mb_chars`, not `update_all` with unsupported methods, not `insert_all` on associations, not the `MissingRequiredOrderError` precursor, not `pool`; the autosave, `.or`, HWIA, enum and `has_secure_password` paths are green; the four R3 boundary specs, P4 (4 examples), P5 and P7 are inside the run; `spec/requests/properties_spec.rb` (41 examples), the ten `spec/requests/accounts_*` files (96), `phone_numbers_spec.rb`, `users_directory_spec.rb` — the `.or` sites' callers — all green, **no count changed** (gap 4). `bin/rails zeitwerk:check` on 8.1.4 → "all is good" (the `lib/` notice as on `master`). The two one-second flakes did not fire.

**Schema dump prediction (OD7, gap 1).** Development database, `information_schema.columns` for every `real`/`double precision` column in `public` (`bin/rails runner`, 2026-10-28):

```
{"table_name"=>"photos",     "column_name"=>"classification_confidence",  "data_type"=>"double precision", "numeric_precision"=>53}
{"table_name"=>"properties", "column_name"=>"ai_community_confidence",    "data_type"=>"double precision", "numeric_precision"=>53}
{"table_name"=>"properties", "column_name"=>"ai_neighborhood_confidence", "data_type"=>"double precision", "numeric_precision"=>53}
count=21   (the other 18 rows are pg_stat_statements' own columns)
```

`activerecord-8.1.4 postgresql_adapter.rb:696–697` registers `float4` as `Type::Float.new(limit: 24)` and `float8` as `Type::Float.new` — only `real` would dump a `limit:`; none is. §8 item 16 is answered. The dumper itself between 8.0.5.1 and 8.1.4 (`diff` of `schema_dumper.rb`, `postgresql/schema_dumper.rb`, `abstract/schema_dumper.rb`): a `relation_name` indirection that is the identity for the default schema, a `within_each_schema` loop (this database dumps `public` only; `ActiveRecord.dump_schemas` unset), the `add_foreign_key` line assembled from parts but printed identically, `enabled:` only for adapters that support disabled indexes (MySQL), and `column.fetch_cast_type` in place of the connection lookup. 8.1.4's CHANGELOG: "Revert alphabetical sorting of table columns inside `schema.rb`." and "Revert stable sorting of columns and indexes in serialized schema caches." (the 8.1.0 sort that §4.4 item 1 makes 8.1.4 the floor for) and "Column defaults are no longer eagerly deserialized." The schema has 62 tables, 114 indexes, 53 foreign keys, 37 `t.decimal`, 0 enums, no `id: false` table. **Prediction: the diff is the header, `ActiveRecord::Schema[7.2]` → `[8.1]`, and nothing else.** UNVERIFIED until the dump runs — it is a `rails db:*` sequence, which this session may not run; Dan runs it on the branch after commit 4, bracketed by the control dump on `master` and the round-trip load after commit 5 (addition B, decision 6).

**`/up` and `remote_ip`** (development runner, both copies, `Rack::MockRequest` through `Rails.application` and through `ActionDispatch::RemoteIp` alone):

```
                                  8.0.5.1                                     8.1.4
/up                               200 text/html  <!DOCTYPE html>…green        200 text/html  (same)
/up.json                          200 text/html  (the HTML page)              200 application/json  {"status":"up","timestamp":"2026-10-28T14:33:07Z"}
remote_ip XFF="203.0.113.7"                         "203.0.113.7"             "203.0.113.7"
remote_ip XFF="203.0.113.7:1234"                    "10.0.0.1"  (REMOTE_ADDR) "203.0.113.7"
remote_ip XFF="203.0.113.7:1234, 10.0.0.1"          "10.0.0.1"                "203.0.113.7"
remote_ip XFF="[2001:db8::1]:443"                   "10.0.0.1"                "2001:db8::1"
```

`railties-8.1.4/lib/rails/health_controller.rb:45–50` — `respond_to` with `format.json { render json: { status: "up", timestamp: … } }`; S1 gains the JSON read. `actionpack-8.1.4 remote_ip.rb:179–196` — the port is stripped before `IPAddr` validation (8.0 discarded the whole entry). For `transactions_controller.rb:55`, Stripe's `client_ip` changes only for a forwarded entry that carries a port; whether Heroku's router ever writes one is UNVERIFIED (ASSUMPTION: it does not — the router's `X-Forwarded-For` is bare addresses); informational either way (§5 "watched, lower").

**The 8.1 defaults under `load_defaults 7.2`** (8.1.4 development runner; the values the contract spec pins until slice 5b): `ActionController::Base.escape_json_responses` → `true` (`renderers.rb:44`; the writer deprecates only a `true` *assignment*, `:31–34`, and nothing assigns it); `ActiveSupport.escape_js_separators_in_json` → `true`; `ActiveRecord.raise_on_missing_required_finder_order_columns` → `false`; `ActionController::Base.action_on_path_relative_redirect` → `:log`; `strict_freshness` → `false`; `Regexp.timeout` → `nil`; `loaded_config_version` → `7.2`; `permanent_connection_checkout` → `true` (so `Model.connection` stays silent, `connection_handling.rb:277–283`); `config.yjit` → `true` on both versions (unchanged). JSON bytes do not change in this slice (§4.4: only under `load_defaults 8.1`).

**Routes.** `bin/rails routes` → 583 lines on both copies, byte-identical (`diff` empty); the full set including internal routes → 591 on both.

**P3 on 8.1.4** (`probe` copy, `bundle exec sidekiq -c 1 -q slice3_p3 -e development`, Redis `redis:6379`): `Booted Rails 8.1.4 application in development environment`; property 1964 enqueued with `.set(queue: "slice3_p3")` → `start` → `[PropertyDataLookupWorker] Property#1964 already has property data, skipping` → `done` (`elapsed=0.211`). `Sidekiq::Status::status(jid)` → `nil` (§8 item 10, recorded, not asserted). Sidekiq 7.3.10's railtie boots on 8.1.4 — §3.1's UNVERIFIED, verified in development; production is S2.

**P-PROD on 8.1.4** (`probe` copy, slice 2's wrapper, `RAILS_ENV=production HONEYBADGER_REPORT_DATA=false`, the reader line replaced by the `key?` probe):

```
"8.1.4"
true
true
[["Rails", [:notify]], ["GlobalID", [:notify]], ["Lograge", [:notify]]]
I, [2026-10-28T14:35:03 #45172]  INFO -- honeybadger: ** [Honeybadger] Reporting error id=e77b98cf-… level=1 pid=45172
true
false        (config.active_support.key?(:to_time_preserves_timezone))
7.2
583
false        (Honeybadger report_data)
true         (ActionController::Base.escape_json_responses)
--- DEPRECATION lines: 0 ---
```

The only production-mode boot of 8.1.4 before the push: eager load on, routes drawn, the deprecators `[:notify]`, the honeybadger railtie loaded, the `DeprecationReporter` wired, and no deprecation at boot.

**CHANGELOG checks against the installed 8.1.x gems** (headlines, 9 gems, `scratchpad/changelogs/*.txt`; first sentences): the three floor claims of §4.4 item 1 are in `activerecord-8.1.4/CHANGELOG.md` ("Revert alphabetical sorting of table columns inside `schema.rb`.", "Revert stable sorting of columns and indexes in serialized schema caches.", "Column defaults are no longer eagerly deserialized.") and `actionmailer-8.1.4/CHANGELOG.md` ("Fix `ActionMailer::Base.mail` not returning a `MessageDelivery` in Rails 8.1+." — the 18 `deliver_now` sites in `app/` and `lib/`); Action Pack 8.1.0 "Raise `AbstractController::DoubleRenderError` if `head` is called after rendering.", "`remote_ip` will no longer ignore IPs in X-Forwarded-For headers if they …", "Add JSON support to the built-in health controller.", "The JSON renderer doesn't escape HTML entities or Unicode line separators anymore." (behind the 8.1 flag); Active Support 8.1.0 "Remove deprecated support for `to_time` to preserve the system local time. …", "Deprecate `config.active_support.to_time_preserves_timezone`.", "Deprecate `String#mb_chars` and `ActiveSupport::Multibyte::Chars`.", "Deprecate `ActiveSupport::Configurable`", "Remove deprecated `Benchmark.ms` method."; Active Record 8.1.0 "Raise `ActiveRecord::MissingRequiredOrderError` when order dependent finder methods …" (every table has an `id` primary key — no `id: false`, notes), "`:class_name` is now invalid in polymorphic `belongs_to` associations." (no `polymorphic: true` in `app/models`), "Deprecate using `insert_all`/`upsert_all` with unpersisted records in associations.", "Deprecate usage of unsupported methods in conjunction with `update_all`" (18 `update_all` sites, none chained with `limit`/`order`/`distinct`/`group` on its line); "Introduce new database configuration options `keepalive`, `max_age`, and `min_connections` -- and rename `pool` to `max_connections`" (the key still reads, P-PROD). Greps over `app/`, `lib/`, `config/`: `ActiveSupport::Configurable` 0, `Benchmark.ms` 0, `mb_chars` 0, `to_query` 0, `ignore_leading_brackets` 0, `.since(` 0, `insert_all|upsert_all` 1 (`lib/tasks/marketing_source.rake:41`, class-level). Active Storage 8.1.3.1/8.1.4 (libvips loaders; "Warn instead of aborting boot when `image_processing` 2.x is installed without `ruby-vips`") — unreachable, routes off, no `ruby-vips`.

### What the survey changes

1. **The `application.rb` line is deleted, inside the bump commit** (§4.4 item 3 decided; its commit 4 disappears). Open question 2.
2. **The contract spec's `to_time` setting example is rewritten** to pin that no `to_time_preserves_timezone` key is set, because the reader itself deprecates on 8.1.4. Open question 4.
3. **A `fix:` commit joins the slice, first in the sequence**: the five double-`head` setters, with request specs. §4.4's "two `head` sites" undercounted; the fix is a no-op on 8.0.5.1 and prevents 500s on 8.1.4. Open question 3.
4. **`action_text-trix` enters the lock**, forced by Action Text 8.1 through `rails/all`. Open question 1.
5. **`app:update` 8.1 deltas**: `bin/rails`/`bin/rake` identical; `bin/rubocop` one comment (accept — open question 5); `content_security_policy.rb` comment-only (reject); `config/ci.rb`, `bin/ci` as §4.4 says, plus `bin/dev`/`bin/setup`/`puma.rb` as slice 2 ruled.
6. **No production or pre-deploy command may read `ActiveSupport.to_time_preserves_timezone` on 8.1.4** — S3's second line and P-PROD's reader line become the `config.active_support.key?` probe. A trap for the runbook and for slice 5.
7. **Slice 5a must not uncomment `new_framework_defaults_8_0.rb:18`** (`to_time_preserves_timezone = :zone`): on 8.1 any value warns, and 8.2 removes the knob. v6 marks §4.3's shim row and §4.6's "rows 2–3 flipped in 5a" accordingly; the 8.0 shim keeps the line commented until 5b deletes the file.
8. **The three `t.float` columns are `double precision`** — §4.4 item 4's UNVERIFIED and §8 item 16 close; the dump prediction is header-only.
9. The `.or` request specs: no count changed (gap 4 closed by the suite); S11 stays as a capture, not a detector.
10. **Calendar**: slice 2's SH closes Thu 2026-10-29 05:53 PT; §2.4 forbids Thursday and Friday; the first legal morning is **Mon 2026-11-02**, with Tue 11-03 and Wed 11-04 as the only fallbacks before Sat 11-07 (§1.3). Open question 8.
11. **The head enumeration is exhaustive** (addition A): 127 methods read, no sixth new site; two pre-existing cases (`download_files`, `set_notification_audience`) and the nil-order `show` template error recorded for §8, with `find_instance`'s contract (addition C).
12. **Two spec additions**: unauthenticated and bogus-token requests pin which paths the auth layer answers first (three of five) and that raw photos is reachable without a token; `raw_photos_controller.rb:60` is decided below, not at implementation.
13. **A control dump and a round-trip load bracket the 8.1 dump** (addition B): three `db:*` sequences, all Dan's. **The control dump ran**: besides the header, 8.0's dumper re-qualifies `plpgsql` as `pg_catalog.plpgsql`, so "header-only" (§4.4 item 4, OD7) becomes "the header and the extension hunk" for this slice; v6 amends OD7's rule and the `db/schema.rb:15–16` notes row.
14. `.rubocop.yml` does not exist in the repo (`ls`), so `bin/rubocop` — current or templated, both pass `--config ../.rubocop.yml` — cannot run as a check for commit 3; the diff itself (one comment line) is the check. Lint in the loop is `bundle exec rubocop <files>` with rubocop's defaults.

No STOP on the prompt's four gaps. Items 1–3 were the decisions that needed Dan before implementation; all are answered above.

---

## Phase 1 — plan

### Gaps pinned (the prompt's four)

1. **The schema diff outcome.** Rule: the predicted header-only diff is the only commit (commit 5); anything else is a STOP with the diff pasted (OD7). The float columns are `double precision` (query above), so a `limit:` is not expected; the dumper diff between versions changes no output for this schema. Three `db:*` sequences bracket it, all Dan's (the session may not run `rails db:*`), each with no spec run in flight (the suite's `maintain_test_schema!` would otherwise reload the file mid-dump):

   - **Control dump, on `master` 03e270c6, before the branch is cut** (addition B). The committed file has never been re-dumped under 8.0, so this separates 8.1's lines from pre-existing drift:

     ```bash
     cd /workspace/apps/insgt-api && git status --short          # must be clean
     RAILS_ENV=test bin/rails db:drop db:create db:schema:load
     RAILS_ENV=test bin/rails db:schema:dump
     git diff db/schema.rb
     git checkout -- db/schema.rb                                 # discard: the [8.0] header is never committed
     ```

     Expected: one changed line, `ActiveRecord::Schema[7.2]` → `ActiveRecord::Schema[8.0]`, nothing else. Anything else is pre-existing and is understood (and recorded in this plan) before the 8.1 STOP rule means anything; it is not slice 3's to fix unless the dumper itself is the cause.

     **Result (Dan, 2026-10-28, `master` 03e270c6, clean tree):**

     ```
     -ActiveRecord::Schema[7.2].define(version: 2026_10_07_120001) do
     +ActiveRecord::Schema[8.0].define(version: 2026_10_07_120001) do
        # These are extensions that must be enabled in order to support this database
     +  enable_extension "pg_catalog.plpgsql"
        enable_extension "pg_stat_statements"
     -  enable_extension "plpgsql"
     ```

     Two hunks, the second not predicted. **The dumper is the cause**, not the database: Active Record 8.0 "Include schema name in `enable_extension` statements in `db/schema.rb`. The schema dumper will now include the schema name in generated `enable_extension` statements if they differ from the current schema." (`activerecord-8.0.5.1/CHANGELOG.md:747–766`); `plpgsql` lives in `pg_catalog`, so it becomes `pg_catalog.plpgsql` and sorts ahead of `pg_stat_statements` (`postgresql/schema_dumper.rb:29`, `extensions.sort`). The same section makes `enable_extension` accept the schema-qualified name on load (`CREATE EXTENSION IF NOT EXISTS … SCHEMA …`; the extension already exists, so a load is a no-op — the round-trip proves it). Line count unchanged (15–16 swap content), so the account-classification notes' `db/schema.rb` line ranges still hold; the notes row for `db/schema.rb:15–16` is rewritten in v6. Discarded, as planned.
   - **The 8.1 dump, on the branch after commit 4** (the same four commands minus the discard): **exactly the two hunks above with `[8.1]` in place of `[8.0]`** → commit 5, whose body names the extension hunk as 8.0's dumper change verified by the control dump; any third hunk → STOP with the diff.
   - **The round-trip load, after commit 5**: the same `db:drop db:create db:schema:load` (now loading the committed `[8.1]` file under 8.1's compatibility class), `db:schema:dump`, `git diff db/schema.rb` → **empty**. P1 then runs again on the final tree, against the test database this load produced — the only time the suite runs against a database built from the new file; with no CI, the next such load is a fresh developer setup.

2. **The two `head`-after-render traces.** `application_controller.rb:303` is reachable after a *render* at one caller (`orders#download_files`, pre-existing on every version, §8) and after a *`head`* at five (the probe); `orders_controller.rb:597` is the first statement of its action and unreachable after any render. The exhaustive read of all 127 head-producing methods (addition A) found nothing else. Rule: the five setters are fixed in commit 1, each proved by a request spec that is red on 8.1.4 (`DoubleRenderError`) and green on both versions after the fix; `:597` gets no new spec — the trace is the proof, and a `PUT /orders/:id/order_event` example would need the completion-authorization fixtures for a path the change cannot reach.
```
$ git diff db/schema.rb | tee /tmp/control-dump-8.0.diff
diff --git a/db/schema.rb b/db/schema.rb
index de091b72..59a3856c 100644
--- a/db/schema.rb
+++ b/db/schema.rb
@@ -10,10 +10,10 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[7.2].define(version: 2026_10_07_120001) do
+ActiveRecord::Schema[8.0].define(version: 2026_10_07_120001) do
   # These are extensions that must be enabled in order to support this database
+  enable_extension "pg_catalog.plpgsql"
   enable_extension "pg_stat_statements"
-  enable_extension "plpgsql"
 
   create_table "account_metrics", force: :cascade do |t|
     t.bigint "account_id", null: false
```
3. **The `application.rb` line on 8.1.4.** Rule: **delete `config/application.rb:14–20`** (the comment and the line) in commit 2, the bump. Deliberate-break evidence: the line re-added on 8.1.4 → the boot raise at `railtie.rb:145` (pasted above; pasted again from the branch at implementation). Keep: impossible, every value warns at boot (`active_support.rb:131–137`) and production would notify a `RailsDeprecation` on each process boot. Replace: nothing to replace it with — `to_time` is unconditional (`time_with_zone.rb:501–503`) and the knob is removed in 8.2.
4. **The `.or` search request specs' before/after counts.** None changed: every file is inside the 2,045 green examples on 8.1.4, as it was on 8.0.5.1 (the fix is 7.2.3's). Rule: no code change, no new spec; S11 captures one production search before and after the push for the record.

### Decisions beyond the gaps

- **The double-`head` fix idiom.** `return if performed?` directly after each `find_instance` call in the five setters (`orders_controller.rb:688`, `transactions_controller.rb:74`, `raw_photos_controller.rb:54`, `listing_rooms_controller.rb:30`, `listing_property_features_controller.rb:30`). **`raw_photos_controller.rb:60`, decided:** it stays, as the only guard for the no-credentials path (`GET /orders/0/raw_photos` with neither JWT nor token heads once there — probed, 204 on both versions); lines `:55` and `:58` become `return render_no_content if …` so that `:60` is reached only with `@order` present or with no credentials. Without the `:58` change a bogus `access_token` heads at `:58` and again at `:60` (probed: `DoubleRenderError` on 8.1.4 — the one path reachable without a token). **The trailing guards' `blank?` halves are provably dead once the return is in** — `find_instance` either set the ivar or headed and returned — at `orders:689`, `transactions:75`, `raw_photos:55`, `listing_rooms:31`, `listing_property_features:31`; they stay textually, because the `can_access?` half still needs the guard at four of them and trimming the condition is a refactor in an upgrade commit (trap 4). The commit body says so. `performed?` is the Rails predicate for "this request already has a response" (`response_body || response.committed?`), the codebase's own comment at `accounts_users_controller.rb:35–37` names it as the thing a trailing guard should have checked, and the early return is the house idiom (`return render_unauthorized unless …`). Rejected: `return unless find_instance(…)` (correct — the helper returns `false` from `render_no_content` or the instance — but reads as a predicate the helper was not written to be); narrowing the second guard to `present? && !can_access?` (leaves `raw_photos_controller.rb:60` double-heading); making `render_no_content` itself idempotent (`return false if performed?` — one line fixes all five, but it would also hide every future render-then-head, which 8.1 wants surfaced, and it changes the outcome of a render-then-head path from "the head wins" to "the render wins"). The fix is commit 1, **before the bump**: on 8.0.5.1 it is behaviour-preserving (the second head overwrote an identical 204), so the commit is green on both versions and bisects cleanly.
- **The request specs** live in one file, `spec/requests/missing_record_guards_spec.rb` — one invariant ("a missing record answers once — 204, or the auth layer's 401 — never a 500"), eleven examples, the header comment in `accounts_destroy_spec.rb`'s shape (which already documents the 204-on-miss contract of `find_instance`). With `jwt_headers_for(create(:user))`: `GET /orders/0`, `GET /orders/0/transactions`, `GET /orders/0/raw_photos`, `GET /listing_rooms/0`, `GET /listing_property_features/0` → `204` (the five reds on 8.1.4). With no credentials (addition A): `/orders/0/transactions`, `/listing_rooms/0`, `/listing_property_features/0` → `401` (the auth layer answers before the setter); `/orders/0/raw_photos` → `204` (no auth gate; one head at `:60`). With `access_token=bogus`: `/orders/0` → `204` (one head at `:686`, unchanged); `/orders/0/raw_photos` → `204` (red on 8.1.4 before the `:58` change). Not pinned: `GET /orders/0` with no credentials — a pre-existing `ActionView::Template::Error` (§8), not this slice's to fix or to enshrine.
- **Contract spec changes** (extend, do not restructure; one `describe` per section): the floor → `8.1.4`; the `:23–25` example becomes "sets no `to_time` configuration on 8.1" — `expect(Rails.application.config.active_support).not_to have_key(:to_time_preserves_timezone)` (the `OrderedOptions` answers `key?`; the probe used it) with the comment rewritten (reader and writer deprecate; behaviour unconditional; knob gone in 8.2); the three behaviour examples stay as they are (green on 8.1.4, values above); the "draws none" example (`:84–88`) first asserts a known route — `recognize_path('/up')` → `rails/health#show` — then the absence (§8 item 20, Codex's nit from slice 2); the "other 8.0 defaults stay off" example (`:111–118`) is extended to the 8.1 flags — `ActionController::Base.escape_json_responses` `true`, `ActiveSupport.escape_js_separators_in_json` `true`, `ActiveRecord.raise_on_missing_required_finder_order_columns` `false`, `ActionController::Base.action_on_path_relative_redirect` `:log` — with its title and comment naming both shims and slices 5a/5b.
- **Commit 2 carries three things that cannot be separated**: the Gemfile/lock bump, the `application.rb:14–20` deletion, and the two contract examples (floor, no-config) that are red on 8.0.5.1 and green on 8.1.4. The body states the lock movement (`action_text-trix`, `benchmark`, `json`), the boot mechanism in both directions, and why §4.4's commit 4 is folded in.
- **`bin/rubocop` accepted as commit 3** (one comment line; keeps the binstubs in step with the template, as slice 2 did for `bin/rails`/`bin/rake`); `content_security_policy.rb` rejected (above). If Dan prefers no commit for a comment, commit 3 is dropped and the file left alone (open question 5).
- **P-PROD** is slice 2's wrapper with `p ActiveSupport.to_time_preserves_timezone` **replaced** by `p Rails.application.config.active_support.key?(:to_time_preserves_timezone)` and `p ActionController::Base.escape_json_responses` added; expected output as pasted above with the branch's version. **S3** prints `Rails.version` and the same `key?` probe — never the reader, in any environment on 8.1.4.
- **P1 runs twice** (plain and `CI=1`); the count is reported, not a criterion (ESTIMATE 2,056: 2,045 plus the eleven request examples; the contract file's example count is unchanged). It runs once more after the round-trip load (addition B), on the final tree, against the database that load produced.
- **P3** on its own queue (`slice3_p3`), exactly as run in the survey.
- **Runbook** `docs/runbooks/deploy-rails-upgrade-3.md` in slice 2's shape (Summary, Where the commands run, Deploy window, Prerequisites, Pre-deploy, Deploy, Within 30 minutes, One hour, 24 hours, Rollback, Known, After the deploy, Deploy log). Deploy window: **Mon 2026-11-02, 09:00–11:30 PT**; the slippage rule: review and merge not complete by 09:00 PT → Tue 11-03, then Wed 11-04; **Wed 11-04 is the last morning before 8.0's security end date (Sat 11-07)** — a slip past it is a §7 decision, not a slot change; nobody pushes after 11:30 to make a window. Prerequisites carry slice 2's SH result (closes Thu 05:53 PT) and the OD7 dump outcome. `Draft` in this session, `Ready` after the review. Its Summary places this push in the remaining schedule in one line: slice 4 (Mon 11-09), 5a (Tue 11-10), 5b (Wed 11-11), the quiet week to Wed 11-18, then the Render rehearsal (§6). Its 24-hour section notes that DST ended Sun 11-01: S9 is judged in UTC, and a time-zone-shaped error in SH is a DST suspect before it is an 8.1 suspect.
- **Traps added to the runbook and the review** (beyond the prompt's): a call to `ActiveSupport.to_time_preserves_timezone` anywhere (spec, probe, runbook); `new_framework_defaults_8_0.rb:18` uncommented; a `return if performed?` outside the enumerated sites (scope creep — `download_files` included, which is pre-existing and goes on its own branch); a `head`/`render_no_content` removed instead of guarded; a trailing guard's condition trimmed.
- **Branches**: insgt-api `chore/rails-upgrade-slice-3` off `master` 03e270c6; platform `docs/rails-upgrade-slice-3` (this plan, the runbook, the write-back). Dan merges both. If `master` moves before the push, the suite runs on the merge first (slices 1 and 2's practice).
- **Codex review** on an rsync copy without `.git` and `.env`, two rounds; findings folded into the commit they belong to on the unpushed branch by cherry-pick rebuild (not `--autosquash`).
- **Write-back (v6) items, so the next slice reads the document, not this file**: §3.1 gains the `action_text-trix` row; §4.4 as built (item 3 decided, the five-site `head` finding, the folded commit, the dump outcome, the `key?` probe, the `/up.json` and `remote_ip` facts, the float types); §4.0 S3 and P-PROD reworded for 8.1 (no reader call); §4.3's shim row and §4.6's 5a row (the 8.0 `to_time` line stays commented); §4.6's 5b row gains the six 8.1 flags as generated; §6 the calendar as it went; **§4.3 as deployed** (v663; S7, S9 and SH pass; the `orders#show` triage — slice 2's status line and its §4.3/§6 paragraphs went into v5 on 2026-10-29 without a version bump, the way slice 1's SH pass did; slice 2's runbook step 7 has the triage); §8 items 2 (CSP comment delta), 10, 16 (closed), 20 (done), and four new items — **`find_instance`'s contract** (addition C: it renders as a side effect and returns false-or-instance, so its 55 callers guard defensively; make the return value the idiom, or move the miss to a `rescue_from` → 204), `OrdersController#download_files`' render-after-head on a missing order (pre-existing `DoubleRenderError`; one `return if performed?`), `NotificationAudiencesController#set_notification_audience`'s `NoMethodError` (its fix must also guard with `performed?`, or it becomes a double head), and `OrdersController#show`'s template error without credentials; the notes file (the five sites, the enumeration, the 8.1.4 sources, the probe copies); the slice 4 and 5 prompts annotated.

### Approach, one unit of work per commit

**1. `fix: stop heading twice when a guarded record is missing`** — `spec/requests/missing_record_guards_spec.rb` first, eleven examples; on 8.0.5.1 they are green before the fix (the second head was invisible), so the red comes from the probe copy on 8.1.4 and is pasted into this commit's loop record (and again in commit 2's, with the fix temporarily reverted). The fix: `return if performed?` after the five `find_instance` calls; `raw_photos_controller.rb:55` and `:58` → `return render_no_content if …`; `:60` unchanged; nothing else. `bin/rails routes` unchanged. Deliberate break on 8.1.4 (probe copy): revert one site → that example red with `DoubleRenderError`; revert the `:58` change alone → the bogus-token example red; restore. Lint the five controllers and the spec. `bundle exec rspec spec/requests` and the five controllers' existing specs. Body: Action Pack 8.1.0's `head` change, `head.rb:28`, the five sites, why the trailing guards' `blank?` halves are dead once the return is in and why they stay, the enumeration that found no sixth (and the two pre-existing cases it did find, left for §8), the idiom and the rejected alternatives in one line each.

**2. `build: upgrade rails to 8.1.4`** — contract examples first: the floor `>= 8.1.4` (red on 8.0.5.1) and "sets no `to_time` configuration" (red on 8.0.5.1: the key is set). `Gemfile:29` → `'~> 8.1.4'`; `bundle update rails --conservative`; `git diff Gemfile.lock` must equal the scratch diff line for line (a difference is a STOP); delete `config/application.rb:14–20`; green. Evidence pasted in the loop: (a) the line re-added → the boot raise at `railtie.rb:145`; (b) the floor at `8.1.5` → red; (c) commit 1's five sites reverted → `missing_record_guards_spec.rb` red with `DoubleRenderError` (the 8.1 red for commit 1); restore all. Then `bundle exec rspec` and `CI=1 bundle exec rspec` (0 failures, 0 deprecation lines), `bin/rails zeitwerk:check`, `bin/rails routes` diffed against a capture taken on `master` (empty). Body: the 13 gems, `action_text-trix` (what it is, why it is inert, §8 item 7), `benchmark`/`json`, the `to_time` mechanism in both directions and why §4.4's commit 4 is folded in, the `.or`/autosave fixes being 7.2.3's (no count moved).

**3. `chore: apply the rails 8.1 app:update binstubs`** — `bin/rubocop`'s comment line from the captured diff; `bin/rubocop --version` runs. No spec. (Dropped if open question 5 says so.)

**4. `chore: add the rails 8.1 framework defaults shim`** — the extended "defaults stay off" contract example first (green already; its break: uncomment `escape_json_responses = false` in the new shim → red; restore) and the "draws none" example's known-route assertion (break: expect `rails/health#index` → red; restore). Add `config/initializers/new_framework_defaults_8_1.rb` verbatim; green. Body (tier 2): the six flags stay commented until 5b; the rejected files, one line each, pointing at this plan's table (`config/ci.rb`, `bin/ci`, `bin/dev`, `bin/setup`, `config/puma.rb`, `config/application.rb`, `config/environment.rb`, the three environments, `cors.rb`, `filter_parameter_logging.rb`, `content_security_policy.rb`); `active_storage:update` copied nothing.

**5. `chore: re-dump schema.rb under rails 8.1`** — after Dan's 8.1 dump; `git diff db/schema.rb` pasted in the body with the control dump's result for contrast; header-only or STOP. No spec. No DDL. Then Dan's round-trip load (empty diff) and P1 once more on the final tree.

Then once for the slice: P1 (twice) to P8 and P-PROD with `8.1.4`; the runbook as `Draft`; `predeploy-review-rails` twice; the verification STOP with the spot-check table filled from development and the pre-push captures listed for the Mac.

### Spec plan — boundary cases by name

`spec/architecture/rails_upgrade_spec.rb` (extended; `type: :model`):

| Section | Example | Pinned value | Deliberate break |
| :-- | :-- | :-- | :-- |
| §1.2 | the framework runs at least the version the document names for the latest slice | `Rails.gem_version >= Gem::Version.new('8.1.4')` | floor to `8.1.5` → red |
| §4.4 item 3 | sets no `to_time` configuration on 8.1 (rewrites `:23–25`) | `config.active_support` has no `:to_time_preserves_timezone` key | re-add `application.rb:20` → boot raise (the suite cannot run; the raise is the red) |
| §4.2 item 2, §4.3 | the Pacific offset, the Pacific zone, DST arithmetic (unchanged, `:29–54`) | `-25_200`; zone object / `PST` / `-28_800` / not DST; `-28_800` | — (seen red in slices 1 and 2; the behaviour is unconditional on 8.1 and no config can break it) |
| §4.2 item 3, OD8 | the deprecation gate (unchanged) | `:raise`; every registered deprecator raises | — |
| §3.3, OD2, §8 item 20 | draws a known route and none of Active Storage's (extends `:84–88`) | `recognize_path('/up')` → `controller: 'rails/health', action: 'show'`; `grep(/active_storage/)` empty | expect `action: 'index'` → red |
| §4.3 as built | the carts and headshots member routes (unchanged) | as slice 2 | — |
| §4.3 item 6, §4.4, §4.6 | the 8.0 and 8.1 defaults stay off until slice 5 (extends `:111–118`) | `strict_freshness` `false`; `Regexp.timeout` `nil`; `escape_json_responses` `true`; `escape_js_separators_in_json` `true`; `raise_on_missing_required_finder_order_columns` `false`; `action_on_path_relative_redirect` `:log`; `loaded_config_version` `7.2` | uncomment `escape_json_responses = false` in the 8.1 shim → red |

`spec/requests/missing_record_guards_spec.rb` (new; `type: :request`):

| Example | Request | Expected (both versions, after commit 1) | Red (8.1.4, before commit 1) |
| :-- | :-- | :-- | :-- |
| orders | `GET /orders/0` with a JWT | `204` | `DoubleRenderError` from `orders_controller.rb:689` (probed) |
| orders, token | `GET /orders/0?access_token=bogus` | `204` | — (one head at `:686`; guards the token branch through the change) |
| order transactions | `GET /orders/0/transactions` with a JWT | `204` | `DoubleRenderError` from `transactions_controller.rb:75` (probed) |
| order transactions, no credentials | `GET /orders/0/transactions` | `401` | — (the auth layer answers first; probed on both versions) |
| raw photos | `GET /orders/0/raw_photos` with a JWT | `204` | `DoubleRenderError` from `raw_photos_controller.rb:55` then `:60` (probed) |
| raw photos, token | `GET /orders/0/raw_photos?access_token=bogus` | `204` | `DoubleRenderError` from `:58` then `:60` (probed — reachable without a token) |
| raw photos, no credentials | `GET /orders/0/raw_photos` | `204` | — (one head at `:60`; probed) |
| listing rooms | `GET /listing_rooms/0` with a JWT | `204` | `DoubleRenderError` from `listing_rooms_controller.rb:31` (probed) |
| listing rooms, no credentials | `GET /listing_rooms/0` | `401` | — (probed) |
| listing property features | `GET /listing_property_features/0` with a JWT | `204` | `DoubleRenderError` from `listing_property_features_controller.rb:31` (probed) |
| listing property features, no credentials | `GET /listing_property_features/0` | `401` | — (probed) |

Existing coverage, run by name inside P1 and reported: `spec/requests/properties_spec.rb` (41), the ten `spec/requests/accounts_*` files (96), `phone_numbers_spec.rb`, `users_directory_spec.rb` (the `.or` sites); the four R3 boundary specs; P4 `postal_code_spec.rb -e nearby_cities` (4); P5's four Stripe files; P7's three; `spec/models/transaction*_spec.rb` (the `client_ip` consumers, with a literal IP — `remote_ip` is not exercised by any spec; UNVERIFIED in test, informational in production). All green on 8.1.4 in the survey run.

### Commit sequence

insgt-api, branch `chore/rails-upgrade-slice-3` off `master` 03e270c6 (tiers per `git-commit-messages` in brackets):

1. `fix: stop heading twice when a guarded record is missing` [2]
2. `build: upgrade rails to 8.1.4` [2: the folded deletion and the lock line §4.4 did not name]
3. `chore: apply the rails 8.1 app:update binstubs` [1] — or dropped (open question 5)
4. `chore: add the rails 8.1 framework defaults shim` [2]
5. `chore: re-dump schema.rb under rails 8.1` [2] — after Dan's dump, header-only

Platform repo, branch `docs/rails-upgrade-slice-3`: `docs: add the rails upgrade slice 3 plan` (this file), `docs: add the rails upgrade slice 3 runbook` (before the push); after verification `docs: amend the rails upgrade design to v6 for slice 3` and `docs: update the rails upgrade notes for slice 3`; after the deploy `docs: record the slice 3 deploy in the rails upgrade runbook`.

### Post-deploy verification

**Pre-deploy, on the branch** (§4.0 with `8.1.4`; reasoned now):

| # | Expected |
| :-- | :-- |
| P1 | `N examples, 0 failures` with N reported (ESTIMATE 2,050; not a criterion); `grep -c "DEPRECATION WARNING"` → `0`; the 24 rack warnings unchanged. Then `CI=1 bundle exec rspec` → the same N, `0 failures`, `0`. The pass criteria are `0 failures` and `0` deprecation lines in both runs |
| P2 | `bin/rails zeitwerk:check` → "all is good" |
| P3 | own queue: `Booted Rails 8.1.4 application in development environment`, `start`, `…already has property data, skipping`, `done`; status `nil` recorded |
| P4 | 4 examples, 0 failures |
| P5 | 0 failures across the four files |
| P6 | `SystemError::rails upgrade` (`ActionMailer::Base.mail` returns a `MessageDelivery` on 8.1.4 — the floor's third claim, exercised here and by the two `deliveries` specs in P5) |
| P7 | 0 failures |
| P8 | `200`, `image/jpeg` |
| P-PROD | as pasted above with the branch's version: `"8.1.4"`, `true`, `true`, the three `[:notify]` pairs (**the load-bearing line**), the gem's `Reporting error` line, `true`, **`false`** (no `to_time` key — a `true` means the deletion did not land), `7.2`, `583`, `false`, `true`; `grep -c DEPRECATION` → `0` |
| Routes | `bin/rails routes` identical to the `master` capture (583 lines); `grep -c active_storage` → `0` |
| Dump | control dump on `master` before the branch: **done** — `[7.2]` → `[8.0]` plus `plpgsql` → `pg_catalog.plpgsql` (re-sorted), discarded; the 8.1 dump after commit 4: the same two hunks with `[8.1]`, committed as 5; the round-trip load after commit 5: `git diff db/schema.rb` empty; then P1 again on the final tree |

**On the Mac, before the push** (on v665, so "unchanged" is provable; `RELEASE` set from `heroku releases -n 1` first):

```bash
heroku run --no-tty --app insgtapi rails runner 'puts PostalCode.find_by(zip: "92008").nearby_cities.limit(3).map(&:name).inspect'
heroku run --no-tty --app insgtapi rails runner 't = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-11-02 10:00").to_time; puts t; puts t.strftime("%Z"); puts t.zone.class'
heroku run --no-tty --app insgtapi rails runner 'puts Rails.application.config.loaded_config_version'
heroku run --no-tty --app insgtapi rails runner 'metadata, _accounts = Account.search(status_type: StatusType.active, name: "<a term Dan searches daily in insgt-ops>"); puts metadata.inspect'
curl -sS -o /dev/null -w "%{http_code}\n" https://api.insightphotos.net/up
curl -sS -w "\n%{http_code}\n" https://api.insightphotos.net/up.json | head -c 200
heroku run --no-tty --app insgtapi rails runner "Notifier.send_error_email('rails upgrade slice 3', 'release $RELEASE').deliver_now"
```

Expected before: `["Carlsbad", "Oceanside", "Leucadia"]`; `2026-11-02 10:00:00 -0800`, `PST`, `ActiveSupport::TimeZone`; `7.2`; the metadata hash (whatever it prints is the "before"; S11 compares the whole hash); `200`; the HTML health page and `200` (on 8.0.5.1 `/up.json` renders the HTML); the email arrives. **Do not run `ActiveSupport.to_time_preserves_timezone` in any production runner** — on v665 it is harmless, after the push it reports a `RailsDeprecation`.

**Production spot checks, within 30 minutes of the push:**

| # | Command (from the Mac) | Expected |
| :-- | :-- | :-- |
| S0 | the marker runner with `slice 3` and `$RELEASE` | `UpgradeMarker` gains an occurrence, context `rails: 8.1.4` |
| S2 | `heroku ps`; `heroku logs --ps backgroundworker.1 -n 300 \| grep Booted` | all dynos up; `Booted Rails 8.1.4 application in production environment` |
| S3 | `rails runner 'puts Rails.version; p Rails.application.config.active_support.key?(:to_time_preserves_timezone)'` | `8.1.4`, `false` |
| S8 | the `to_time` runner above | unchanged: `2026-11-02 10:00:00 -0800`, `PST`, `ActiveSupport::TimeZone` |
| S10 | `loaded_config_version` | `7.2` |
| S11 | the `Account.search` runner above | the same metadata hash as the v665 capture |
| S1 | both `curl`s above | `200`; `{"status":"up","timestamp":"…"}` and `200` (the one visible change of this slice); the Honeybadger uptime monitor stays green |
| S4, S5, S6 | as §4.0 (S4 with `map`) | identical to the capture; `true`; `SystemError::rails upgrade slice 3` arrives |
| S-404 | `curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer <a real JWT, from insgt-ops's session>" https://api.insightphotos.net/orders/0` — **included** (decision 7): the only direct production proof of commit 1. Also captured on v665 before the push (expected `204` there too) | `204` (a `500` is commit 1 not having landed) |
| S7 | one hour after: the saved 1,500-line buffer (window, `status=5` count, exception classes) and Papertrail `status=5` for the hour | `0`; no class other than `ActionController::RoutingError`; **`AbstractController::DoubleRenderError` anywhere is a finding** — but only a site someone hits in the hour shows here, which is why the enumeration was made exhaustive rather than left to this watch |
| S9 | the next hourly `import_listings` check-in, **judged in UTC** (DST ended the day before) | on time |
| SH | 24 h later, Honeybadger by error against the slice 0 baseline plus slice 1's S-DEP; the 24 h before the push run on v665 (Ruby 3.4.12), so an error class first seen after the v665 release and before this push is the Ruby bump's, not this slice's | no new error whose backtrace touches the 13 gems, `config/`, the five setters or `head`; **no new `RailsDeprecation`** (one naming `to_time_preserves_timezone` means a reader call survived somewhere; one naming `mb_chars`, `update_all`, `insert_all` or `Configurable` is an 8.1 deprecation on a path the suite does not reach — a STOP for slice 5 under OD8); **no `AbstractController::DoubleRenderError`** (a sixth site the grep did not see — fixed on its own branch, not blocking unless it is a daily path) |

**Rolling deploy**: no migration, no DDL (the dump changes a comment line), no ENV change; a Heroku release swaps all dynos at once. **Build**: the second 8.x slug on this buildpack (the first, v663, built; §2.5's UNVERIFIED is closed for 8.x in general, not for 8.1.4 — a failed build never becomes a release, v665 keeps running). **Rollback**: `heroku rollback` to v665; nothing to undo — commit 1 is a no-op on 8.0.5.1, so a rollback does not need a revert of it.

### Risks

- **R1, a gem at the bump** — Sidekiq 7.3.10 boots on 8.1.4 (P3, pasted); honeybadger loaded and reported through the Null backend in P-PROD; jbuilder, lograge, oj, strong_migrations, string_utils, shoulda-matchers, rspec-rails, factory_bot, geocoder all ran inside the green suite; `action_text-trix`'s engine is inert without an asset pipeline. What the container cannot prove: the Heroku build and the SendGrid/Stripe paths on 8.1 (S5, S6).
- **A double-`head` site the read did not see** — the exposure set is closed (every `head` comes from five known producers) and all 127 methods containing one were read; what the read cannot see is a render performed by something outside `app/controllers` (a concern or a library hook) before one of those methods runs — none is known. S7/SH watch `DoubleRenderError` as the backstop; the fix would be the same one line, on its own branch.
- **The dump** — the control dump (addition B) separates pre-existing drift from 8.1's lines before the STOP rule applies; if the 8.1 diff is still more than the header, the slice STOPs before commit 5 and the deploy keeps the `[7.2]` file (a header is a comment to the loader; nothing breaks). The round-trip load proves the `[8.1]` file loads and reproduces itself, which P1 alone never does.
- **`remote_ip` → Stripe `client_ip`** — only for forwarded entries carrying a port; ASSUMPTION that Heroku's router writes none; informational (§5).
- **A gem-originated deprecation under `:notify`** (OD8) — none fired in 2,045 examples eager-loaded; a production-only path would surface as `RailsDeprecation` in SH.
- **Timing** — SH for slice 2 closes Thu 05:53 PT; the first legal morning is Mon 11-02; two fallbacks remain before Sat 11-07. The branch should be reviewed and `Ready` before Monday so the morning is only the push.

### Open questions for the engineer

All eight answered 2026-10-28 (the Approval section at the top records the decisions and the three additions); kept here as asked.

1. **`action_text-trix (2.1.19)` in the lock** (changes the lock) — a transitive dependency forced by Action Text 8.1 through `rails/all`; inert here. Recommend **accept**, record it in §3.1 and §4.4 (v6), and leave `rails/all` to §8 item 7. Alternative: pull `rails/all` forward into this slice to keep the lock free of it — out of scope by §4.4 and §2.6, and a bigger change than the gem it avoids. **Answered: accept.**
2. **The `application.rb:14–20` deletion rides in the bump commit** — §4.4's commit 4 cannot be a green step in either order (boot evidence above). Recommend **yes**; the commit body carries both mechanisms. **Answered: yes, folded; "keep" is pointless rather than impossible (a version guard was considered and rejected — the body says so).**
3. **The double-`head` fix as commit 1, across five setters, with `return if performed?`** (changes code) — wider than §4.4's "two `head` sites"; without it, 8.1.4 answers every missing-order request from a logged-in user with a 500. Recommend **yes, first in the sequence, with the one-file request spec**. Alternatives recorded above. **Answered: yes, plus the exhaustive read (done, no sixth), the unauthenticated examples, and `:60` decided in the plan.**
4. **The contract example for `to_time`** (changes the spec) — rewrite `:23–25` to pin the absence of the key (recommended) or delete it and rely on the three behaviour examples. The rewrite keeps a guard against a future `config.active_support.to_time_preserves_timezone` line reappearing (which would raise at boot anyway, but the example says why). **Answered: rewrite.**
5. **`bin/rubocop`'s one comment line** — accept as commit 3 (recommended, keeps the binstubs in step) or drop the commit and leave the file. **Answered: accept, its own tier-1 commit.**
6. **The OD7 dump is Dan's step**: after commit 4 lands on the branch, run `RAILS_ENV=test bin/rails db:drop db:create db:schema:load`, then `RAILS_ENV=test bin/rails db:schema:dump`, then `git diff db/schema.rb`, with no spec run in flight, and paste the diff; the session commits it as commit 5 if it is the header only. Confirm this sequencing (the alternative, running the dump on a scratch copy, is still a `rails db:*` command). **Answered: confirmed, bracketed by the control dump on `master` before the branch and the round-trip load after commit 5 — three sequences, all Dan's.**
7. **The runbook's `S-404`** — an optional production read of `GET /orders/0` with a real JWT after the push (the direct proof of commit 1). Include it, or rely on S7/SH's `DoubleRenderError` watch? **Answered: include it.**
8. **When** — build the branch now (ESTIMATE 3–4 h plus two review rounds and the runbook; the survey is done and the suite is known) and push **Mon 2026-11-02 09:00–11:30 PT**, after slice 2's SH closes Thursday and over a weekend of soak for nothing (the branch sits unpushed), or build Monday morning before the window. Recommend **build now, review Thursday, push Monday**; Tue 11-03 and Wed 11-04 are the fallbacks; a slip past Wednesday is a §7 decision against the Sat 11-07 end date. **Answered: build now, review Thursday, push Monday — after the control dump.**

### Unverified

- Heroku's Ruby buildpack building an 8.1.4 slug; the release is the proof (v663 proved 8.0.5.1).
- The 8.1 dump's diff (predicted: the header and the `pg_catalog.plpgsql` hunk, as the control dump showed for 8.0) and the round-trip load (expected empty; it is also the proof that `enable_extension "pg_catalog.plpgsql"` loads).
- A render performed outside `app/controllers` before one of the 127 head-producing methods runs (none known; S7/SH backstop).
- Whether Heroku's router ever writes a port into `X-Forwarded-For` (the `remote_ip` change's only production exposure).
- `Sidekiq::Status` middleware in production (§8 item 10).
- Honeybadger on 8.1.4 beyond the P-PROD boot and the Null-backend report; S0 is the proof.
- Slice 2's SH result (closes 2026-10-29 05:53 PT).
- The 24 rack warnings on 8.1.4 (the survey's log filter dropped `warning:` lines; P1 on the branch counts them unfiltered).

### Next phase, if approved

Dan's control dump on `master` is done (result under "Gaps pinned" 1). **Not started in this session, by Dan's instruction.** When it starts: the branch `chore/rails-upgrade-slice-3` off 03e270c6 and the implementation loop, commits 1 → 4 as above, each red → green → deliberate break → lint → area suite → commit; the STOP for Dan's 8.1 dump, then commit 5; the STOP for Dan's round-trip load, then P1 once more on the final tree; then P1 (twice) to P8 and P-PROD, the runbook as `Draft`, the two-round `predeploy-review-rails`, and the verification STOP with the spot-check table filled in from development and the pre-push captures listed for the Mac. The scratchpad copies (`pristine`, `work`, `probe`, the diff, the logs, the route tables and `head_callers.txt`) stay for the session as the reference evidence.

---

## Implementation record (2026-10-30)

insgt-api `chore/rails-upgrade-slice-3`, cut from `master` f86877f5 (v665, the Ruby 3.4.12 release) as the Status line required — not from 03e270c6. Baseline on f86877f5: **2,048 examples, 0 failures** (61.1 s), 0 `DEPRECATION WARNING` lines, 24 rack warnings; `bin/rails routes` 583 lines (the capture every route diff below compares against).

| # | Commit | Loop record |
| :-- | :-- | :-- |
| 1 | `934abe6b` fix: stop heading twice when a guarded record is missing | spec first: 11/0 on 8.0.5.1 (as predicted); red on 8.1.4 (a fresh probe copy, `bundle update rails --conservative`, `application.rb:14–21` deleted): **11 examples, 6 failures**, all `AbstractController::DoubleRenderError`, from `orders_controller.rb:700`, `transactions_controller.rb:75`, `raw_photos_controller.rb:55` and `:60`, `listing_rooms_controller.rb:31`, `listing_property_features_controller.rb:31`; green 11/0 on both versions; breaks on 8.1.4: the listing_rooms return removed → that example red, raw photos' `:58` return removed → the bogus-token example red; `spec/requests` 579/0; full suite 2,059/0 |
| 2 | `afcd901d` build: upgrade rails to 8.1.4 | contract examples first: 2 red on 8.0.5.1 (floor: got `8.0.5.1`; the key: `has_key?(:to_time_preserves_timezone)` true); `git diff Gemfile.lock` identical line for line to the probe's (the 13 gems, `action_text-trix (2.1.19)`, `benchmark (>= 0.3)` → `json`, `rails (~> 8.1.4)`, the checksums); breaks: (a) the line re-added → `railtie.rb:145 … DEPRECATION WARNING … (ActiveSupport::DeprecationException)` at test boot, (b) floor `8.1.5` → red, (c) commit 1's five files reverted → 11 examples, 6 failures, `DoubleRenderError`; full suite **2,059/0** plain and `CI=1`, 0 deprecation lines, 24 warnings; `zeitwerk:check` all good; routes identical |
| 3 | `223ff89f` chore: apply the rails 8.1 app:update binstubs | the comment line from the installed `railties-8.1.4` template; `bin/rubocop --version` exits 2 ("Configuration file not found") before and after — survey item 14; the plan's "runs" in commit 3 was wrong |
| 4 | `8c9b8bbd` chore: add the rails 8.1 framework defaults shim | `cmp` with `railties-8.1.4/…/new_framework_defaults_8_1.rb.tt` → identical; breaks: `escape_json_responses = false` uncommented → red, `/up` expected at `index` → red; full suite 2,059/0; routes identical |
| 5 | `41b8a546` chore: re-dump schema.rb under rails 8.1 | Dan's dump: exactly the two hunks with `[8.1]`; round-trip load: empty diff |

**Deviations from the plan.**

1. `master` moved past the survey (55c86f1d): `set_order` is split, so commit 1's orders guard is in `set_order_for_current_user` (`orders_controller.rb:699–700`), and `GET /orders/0` with no credential now answers `401` and is pinned by `spec/requests/orders_show_authentication_spec.rb`, so the new spec does not repeat it. The head-producer walk rerun on the branch: **128 methods** (the split adds one), 140 call sites, the same producer counts (`find_instance` 55, `destroy_instance` 51, `find_instance_by_public_id` 1); `set_order` heads at most once per branch. No sixth site.
2. Each `return if performed?` carries a one-line why-comment (`find_instance already answered 204 on a miss; from Rails 8.1 a second head raises`), so the guard is not read as dead code.
3. `config/application.rb:14–21` deleted (the block and its trailing blank line), so one blank line remains under `load_defaults`.
4. Rubocop (defaults; no repo config) reports `RawPhotosController#set_order` over the complexity limits after commit 1 (cyclomatic 8/7, perceived 9/8); `TransactionsController#set_order` already was. Recorded, not refactored. The new spec file's `Metrics/BlockLength` is the usual RSpec one.
5. The count is **2,059** (2,048 + 11), not the ESTIMATE 2,056 — the survey's baseline was 2,045.

**New finding — an Active Storage WARN line at every 8.1.4 boot.** `W, … WARN -- : Generating image variants require the image_processing gem. Please add gem "image_processing", "~> 1.2" to your Gemfile or set config.active_storage.variant_processor = :disabled.` Active Storage 8.1 resolves its variant transformer at boot (`activestorage-8.1.4/lib/active_storage/engine.rb:94–129`, rescuing the `LoadError` and logging it); 8.0.5.1 required `image_processing` only when a variant was generated (`image_processing_transformer.rb:7`). The app has no `image_processing` gem. A production-mode boot of the pristine 8.0.5.1 copy prints no such line; the branch prints it once. Production logs to STDOUT (`production.rb:51`), so it appears on every dyno boot and at the top of every `heroku run … rails runner` output. Not raised, not a deprecation (P-PROD's `DEPRECATION` count `0`), not reported to Honeybadger. The survey's P3 log shows the same line in development (`p3-sidekiq.log`, 14:30:21) but the survey did not report it. **Left as is** — silencing it is one line in `config/application.rb` (`config.active_storage.variant_processor = :disabled`), a change outside this slice's scope; recorded in the runbook's Known and for §8 item 7 in v6.

**Verification (development, on `41b8a546`, after the round-trip load).** P1 2,059/0 plain and `CI=1`, 0 deprecation lines, 24 warnings; P2 all good; P3 `Booted Rails 8.1.4 …`, start, `Property#1964 already has property data, skipping`, done, status `nil`; P4 4/0; P5 86/0; P6 `ActionMailer::MessageDelivery`, `SystemError::rails upgrade`; P7 122/0; P8 photo 661071 → `d2e08hhdrjhri.cloudfront.net`, `200`, `image/jpeg`; P-PROD as expected (runbook step 2) plus the WARN line; routes identical (583). S11's command ran on the dev restore (`Account.search(… name: "realty")` → a metadata hash).

**Commit hashes after the review-round-1 rebuild** (`git diff --stat dadf9375 5ffe92c4` empty): `934abe6b` → `a5bfab70`, `afcd901d` → `3b7780d4`, `223ff89f` → `218b0844`, `8c9b8bbd` → `847a85d6`, `41b8a546` → `5ffe92c4`. The loop records above were taken on the pre-review hashes; the trees differ only by commit 1's spec header comment. The full suite on `5ffe92c4`: `2059 examples, 0 failures` (one earlier run hit the `calculator_spec.rb:965` one-second flake and passed on the rerun).

**Review (`predeploy-review-rails`, two rounds, 2026-10-30).** Codex ran on an rsync copy without `.git` and `.env` (specs could not connect to the database there, so its review is source-only); both rounds left the copy and the tree untouched (`diff -rq` empty, `git status` clean).

| Round | Source | Finding | Disposition |
| :-- | :-- | :-- | :-- |
| 1 | Codex | (first run: "Selected model is at capacity" after ~95k tokens, no output; rerun once on `gpt-6-sol`) | — |
| 1 | Codex, nit | five of the eleven examples pass without the guards; the header should say which are regressions | **fixed** in commit 1 (header names the six regressions and why the other five stay) |
| 1 | Claude, nit | Active Storage WARN at every 8.1.4 boot | recorded (runbook Known; §8 item 7) |
| 1 | Claude, nit | `production.rb:48`, `:101` exempt `/up` only, not `/up.json` | recorded for the Render cutover; S1 uses HTTPS on a listed host |
| 1 | Claude, nit | `RawPhotosController#set_order` over rubocop's default complexity | recorded, not refactored (trap 4) |
| 2 | Codex, should-fix | `/up` answers JSON to `Accept: application/json` on 8.1 | **regraded to already-intentional**: `format.html` is first (`health_controller.rb:46–49`), no client calls `/up`, the uptime check's condition is Success; the plan's S1 change |
| 2 | Codex, nit | assert empty bodies on the six regressions | **declined**: a 204's contract is its status; the regression was the 500 |

No finding remains after round 2; no third round.
