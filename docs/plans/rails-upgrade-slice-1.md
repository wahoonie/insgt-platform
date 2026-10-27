# Rails upgrade — slice 1: 7.2.4, the deprecation gate, routes off, production deprecation reporting

**Repo:** `insgt-api`. Platform repo for the runbook and the write-back only.
**Contract:** `docs/architecture/rails-upgrade.md` v3 — §4.2 (the slice), §4.0 (the verification kit), §2 (sequencing), §3 (dependency audit, §3.3 the CVE and OD2), §5 R3 (the `to_time` risk). Prompt: `docs/architecture/rails-upgrade-slices/slice-1.md`.
**Skill:** `slice-implementation`. Also `insgt-api`, `git-commit-messages`, `predeploy-review-rails`.
**Status:** Deployed 2026-10-27 08:15:19 -0400 as v662 (`473e2747`, the branch merged into `master` on v661's `d37ae0df`). Implemented and verified in development 2026-10-26 (`chore/rails-upgrade-slice-1`, eight commits, `a5d9b001`; two review rounds). Runbook steps 2–6 pass; step 7 (SH) is due 2026-10-28 08:15 -0400; write-back in progress. The runbook `docs/runbooks/deploy-rails-upgrade-1.md` carries the commits, the verification results and the decisions taken after this plan (to_prepare wiring, raw backtrace, the rescue, `received?`, the deprecator-aware key); the v4 amendment records them in the design document. Plan history: Phase 0 survey and Phase 1 plan approved 2026-10-26 after the log-history results Dan ran from the Mac (gap 2) and open questions 1, 3 and 4. Question 2 (the slice 0 baseline) is answered: recorded in `deploy-rails-upgrade-0.md` on 2026-10-27, before the push.
**Survey date:** 2026-10-26, against insgt-api `master` 992a2ce8 (slice 0 merged, the commit production ran as release v659 that morning; working tree clean — production has since moved to v660, `02dbb78a`, 11:41:37 -0400, adding `b51d97ba` — the slice branch is cut from it — and to **v661**, `d37ae0df`, 16:42:03 -0400, an emergency fix the branch does not contain; it merges cleanly and the suite runs on the merge before the push) and the platform repo `main` 9fcbea7. Rails source citations are the installed gems (`activesupport-7.2.3`, `railties-7.2.3`, `activestorage-7.2.3`, `honeybadger-6.10.0`, `sidekiq-7.3.10`), read today.

Facts are stated with their source. ASSUMPTION, ESTIMATE and UNVERIFIED are labelled. Nothing below "should work": it ran, or it is under Unverified.

## Scope (the prompt's six items, by §4.2 number)

1. `rails` `'~> 7.2.4'` and the lock diff exactly as §4.2 item 1 expects, minitest downgrade included.
2. Delete `config/initializers/new_framework_defaults.rb:15–17`.
3. `config/environments/test.rb:58` → `:raise`.
4. `config.active_storage.draw_routes = false`, the routes assertion, the 404 request spec, the pre-deploy log-history grep with its stated reach.
5. `production.rb:83` → `report_deprecations = true`, `deprecation = :notify`, the production-only subscriber and `DeprecationReporter`.
6. `spec/architecture/rails_upgrade_spec.rb` with the slice 1 invariants; `docs/runbooks/deploy-rails-upgrade-1.md`.

## Out of scope — do not touch

The prompt's four: the 24 `:unprocessable_entity` spec symbols; any other initializer line (the CSRF and `belongs_to` lines of the same shim file); the OD8 callable behaviour; `rails/all`, `config.load_defaults`, any other gem. Plus, found in the survey and left alone: the stale `Gemfile:28` / `Gemfile.lock` line numbers in the notes (corrected in the write-back, not the code); `config/sidekiq_status.rb` (§8 item 10 — P3 is pinned around it, below).

---

## Phase 0 — survey

### Done

Read §4.0–§4.2, §2, §3, §5–§9 of the design document, the slice 1 prompt, the slice 0 prompt and runbook, and the codebase notes; re-verified every notes row this slice depends on against 992a2ce8; read the installed Rails, Active Storage, Honeybadger and Sidekiq source for the five mechanisms the slice relies on; resolved the 7.2.4 lock on a scratch copy of the Gemfile; ran the full suite as the baseline; ran the `to_time`, routes and `direct_uploads` checks in a runner; fetched the 7.2.4 release post and the per-framework changelogs; read the P3 worker and service and the P8 reader; confirmed every spec file the kit names exists.

### Prerequisites — landed (facts)

| Prerequisite (§4.2, prompt) | Evidence |
| :-- | :-- |
| Slice 0 deployed; S0 produces an `UpgradeMarker` | `docs/runbooks/deploy-rails-upgrade-0.md` Deploy log: release **v659**, 2026-10-26 09:51:38 -0400; S0 notice `fbaf2cdc-e75a-41d9-a712-557106c5a058`, confirmed in the dashboard; `Booted Rails 7.2.3 application in production environment` on `backgroundworker.1` |
| `Rails.version` → `7.2.3` | runner today: `Rails.version=7.2.3 loaded_config_version=7.2`; production per the runbook's Booted line |
| `master` at eda99450 or a descendant with a green suite | `git log`: 992a2ce8 (merge of `chore/rails-upgrade-slice-0`) → a641c52b → d4dd6d9e → eda99450; full suite today **2009 examples, 0 failures** (69.5 s) |
| The Honeybadger project exists | runbook Prerequisites, all checked |

**Not yet in place:** the slice 0 **24-hour baseline** (§4.1 item 7, runbook step 5) is due about 2026-10-27 10:00 ET and is not yet written. Slice 1's SH check compares against it, so it must be recorded before the Wed 2026-10-28 push. Not a blocker for implementing; a blocker for calling the deploy done.

### Codebase notes — rows this slice depends on, re-verified

| Notes row | Today | Drift |
| :-- | :-- | :-- |
| `Gemfile:28` `gem 'rails', '~> 7.2.0'` | **`Gemfile:29`** (`honeybadger` was inserted at `:15` by slice 0) | line moved; §4.2 item 1 and the notes say 28 |
| `Gemfile.lock:378` `rails (7.2.3)`; `:295–296` minitest | `:381`; `:298–299` | lines moved by the honeybadger entries |
| `new_framework_defaults.rb:15–17` | the comment pair and `ActiveSupport.to_time_preserves_timezone = false`, exactly | none |
| `test.rb:58` `:stderr`; `:61` `disallowed_deprecation = :raise`; `:64` `[]` | same | none |
| `production.rb:83` `report_deprecations = false` (comment at `:82`) | same | none |
| `application.rb:12` `load_defaults 7.2`; `:36` `api_only` | same | none |
| no `draw_routes` in `config/` | `grep -rn draw_routes config/` → empty (exit 1) | none |
| 9 Active Storage routes of 592 | runner: 9 (listed below); `bin/rails routes \| grep -c .` → 592 | none |
| no `.to_time` in `app/`, `lib/` | `grep -rn '\.to_time\b' app lib` → empty (exit 1) | none |
| `activesupport/lib/active_support.rb:117–125` writer warns `unless value` | reader `:113`, writer `:117–125`, message "Support for the pre-Ruby 2.4 behavior of to_time has been deprecated and will be removed in Rails 8.0." | none |
| `railtie.rb:66–70` `report_deprecations == false` silences | `:66–75`: `false` → `silenced = true`, behaviours `:silence`; else `behavior = config.deprecation` | none |
| `configuration.rb:117` `load_defaults "5.0"` sets `true` | `:111–117` | none |
| `behaviors.rb:37–45` the `:notify` payload | `notify:` instruments `"deprecation.#{gem_name.underscore.tr('/', '_')}"` with `message`, `callstack`, `gem_name`, `deprecation_horizon`; `:raise` at `:14–18` | none |
| `property_data_lookup_worker.rb:30–38` "rescues, logs and swallows" (§4.0 P3, ASSUMPTION) | **wrong.** `:34–39` is `rescue StandardError` → log → `update_all` → **`raise`**. Only `:32–33` (`PropertyDataAlreadyFetchedError`) swallows | P3 re-pinned below; notes row corrected in the write-back |
| `spec/architecture/account_classification_spec.rb` the shape to copy | exists (`:1–14` header: one file, one purpose, one `describe` per section) | none |

Collision greps (all empty): `app/services/deprecation_reporter.rb`, `config/initializers/deprecation_reporting.rb`, `spec/architecture/rails_upgrade_spec.rb`, `spec/services/deprecation_reporter_spec.rb`, `spec/requests/active_storage_routes_spec.rb` do not exist; `grep -rn "DeprecationReporter\|RailsDeprecation" app config lib spec` → empty.

### Fresh facts the plan rests on

**Baseline suite, 2026-10-26** (`bundle exec rspec`, master 992a2ce8): `2009 examples, 0 failures`, 69.5 s; `grep -c "DEPRECATION WARNING"` → **1**:

```
DEPRECATION WARNING: Support for the pre-Ruby 2.4 behavior of to_time has been deprecated and will be removed in Rails 8.0. (called from <top (required)> at /workspace/apps/insgt-api/config/initializers/new_framework_defaults.rb:17)
```

24 `unprocessable_entity` lines (rspec-rails' Ruby warnings, §8 item 1). So `:raise` has exactly one thing to trip on, and commit 2 removes it before commit 3 adds the gate.

**Lock resolution** (scratch copy of `Gemfile` + `Gemfile.lock` with only line 29 changed to `'~> 7.2.4'`; `bundle lock --update rails --conservative`): resolved on the first run **without naming minitest**. The diff against the real lock, in full:

- the 13 gem version lines `7.2.3` → `7.2.4` (actioncable, actionmailbox, actionmailer, actionpack, actiontext, actionview, activejob, activemodel, activerecord, activestorage, activesupport, rails, railties) and their `(= 7.2.3)` pins;
- `minitest (6.0.1)` → `minitest (5.27.0)`; its `prism (~> 1.5)` sub-dependency line goes with it (no `prism (x.y.z)` entry is removed — prism stays through other dependents);
- two **dependency declarations** under `activesupport` change because 7.2.4's gemspec changed them: `connection_pool (>= 2.2.5)` → `(>= 2.2.5, < 3)` and `minitest (>= 5.1)` → `(>= 5.1, < 6)` (the lock holds `connection_pool 2.5.5`, inside the new cap);
- `DEPENDENCIES`: `rails (~> 7.2.0)` → `(~> 7.2.4)`; `CHECKSUMS` for the 13 gems and minitest.

Nothing else moves. §4.2's "thirteen lines, minitest, nothing else" holds for gem versions; the two constraint lines are the explanation §4.2 asks for.

**7.2.4 changelogs** (raw CHANGELOG.md at tag v7.2.4; release post 2026-09-24: "this is the last release of the 7.2.x series"):

| Framework | 7.2.4 entries | This codebase |
| :-- | :-- | :-- |
| Active Support | `number_to_delimited` perf when `delimiter_pattern` unset; silence a Dalli 4 warning; `Inflector.humanize` with international characters | 12 `number_with_delimiter` sites — output unchanged, perf only; no Dalli; `.humanize` in `app/`/`lib/` → 0 |
| Active Record | `method_missing` perf for virtual SELECT alias attributes; hyphenated table names; PostgreSQL adapter resilience to `Timeout.timeout` inside `reconnect!`; `eager_load` of `has_many` with composite primary keys | no hyphenated table (`db/schema.rb` grep 0); `Timeout.timeout` in `app/`/`lib/` → 0; no composite keys; the alias fix is perf only |
| Action Pack | `ActionController::UnknownHttpMethod` → 405 instead of 500 | the one client-visible change, only for a malformed HTTP verb; S7's `status=5` count can only go down |
| Action View | strict locals parsing for multiline definitions | no `<%# locals` in `app/views` |
| Railties | default Dockerfile `vendor/` fix | no Dockerfile |
| Action Mailer, Active Model, Active Storage | "No changes." | — |

No entry touches an app path. 7.2.4 is a drop-in; the behaviour this slice changes is all in items 2–5.

**`to_time` today and after** (runner, development, container `date +%z` → `+0000`):

```
preserves=false
today:      to_time=2026-10-23 17:00:00 +0000  utc_offset=0       zone="UTC"
after=true: to_time=2026-10-23 10:00:00 -0700  utc_offset=-25200  zone=nil
S8:         2026-10-28 10:00:00 -0700 (-25200)
```

Matches §4.2's gap ("`true`, which 8.0 renames `:offset`": a fixed-offset `Time`, `zone` nil) and the S8 expectation verbatim. Under `false` the result is the instant in the system zone, which is why the deliberate break's value is `0` here and would be something else on a Mac.

**Active Storage routes today**: `draw_routes` config is `nil`; the engine draws when `app.config.active_storage.draw_routes != false` (`activestorage/lib/active_storage/engine.rb:98`; default `true` at `lib/active_storage.rb:358`; the routes file ends `end if ActiveStorage.draw_routes`, `config/routes.rb:84`). The nine: `GET blobs/{redirect,proxy,}`, `GET representations/{redirect,proxy,}`, `GET disk/:encoded_key`, `PUT disk/:encoded_token`, `POST direct_uploads`. `POST /rails/active_storage/direct_uploads` through an integration session today → **400** (`ParameterMissing`, no `blob` param), so the 404 request spec is red for the right reason before commit 4.

**Heroku log history** (Dan, from the Mac, 2026-10-26, on v659): `heroku logs -n 1500 --app insgtapi` reaches back to **2026-10-26T13:32:53 UTC** — the oldest of its 1,500 lines, nineteen minutes before the slice 0 push at 13:51 UTC, so the buffer covers the slice 0 release and the hours after it and nothing earlier (the newest line's timestamp was not captured; `tail -1 | cut -c1-32` gives the span next time). `grep -c active_storage` → **0**. `heroku addons --app insgtapi` shows **Papertrail attached**: `papertrail (giving-idly-5477)`, plan `fixa`, about $8.99/month, as `PAPERTRAIL`. The README's `papertrail:choklad` (`README.md:141`) names the 2015 free plan; that add-on list is stale throughout (today: `fixie tricycle`, `heroku-postgresql essential-1`, `rediscloud 100`, `scheduler standard`, `sendgrid silver`; no New Relic add-on). **Papertrail search** (Dan, 2026-10-26): `rails/active_storage` → **"No matching events — Searched back to Oct 12 at 08:00 PM"**, as the UI displays it. That is about **fourteen days** of searchable history, twice the 7-day window the Heroku Elements page lists for `fixa` (read 2026-10-26; the UI is the authority). The displayed time is in the Papertrail account's zone (UNVERIFIED which; Eastern, as the Mac's `heroku` output uses, would make it 2026-10-13 00:00 UTC). The 365-day archive could extend the reach if that were ever wanted; it is not needed for a decided OD2.

**Deprecators and events**: `Rails.application.deprecators` holds 14 Rails deprecators plus `GlobalID` and `Lograge`; under `:notify` they instrument `deprecation.rails`, `deprecation.global_id`, `deprecation.lograge`. The regexp `/\Adeprecation\./` covers all three and anything a later gem adds. `ActiveSupport::Notifications.subscribe` takes a Regexp (`notifications/fanout.rb:72–76`); a one-argument block receives an `Event`. The railtie leaves `disallowed_deprecation` unset in production → the default `:raise` on an empty `disallowed_warnings` list (`behaviors.rb:79–81`, `test.rb:64`'s `[]` is the same default) — inert.

**What the message carries**: `Deprecation#warn` captures `caller_locations(2)` (`reporting.rb:18–21`) and the `:notify` behaviour receives the *full* message, `"DEPRECATION WARNING: <text> (called from <label> at <path>:<line>)"` (`:124–138`), where the frame is the first one outside the Rails gem root and Ruby's lib dir (`extract_callstack` `:140–151`, `ignored_callstack?` `:171–176`) — possibly a gem frame. So a fingerprint on the message is one Honeybadger error per (deprecation, call site), stable across dynos because every dyno's slug lives at `/app`.

**Rails' own definition of an app frame**: `Rails::BacktraceCleaner` (`railties/lib/rails/backtrace_cleaner.rb:8, 13–26`) strips the `Rails.root/` prefix and silences every line not matching `app|config|lib|test`; `config/initializers/backtrace_silencers.rb` is stock (comments only). `Rails.backtrace_cleaner.clean(frames).first` is therefore exactly "the first non-gem frame", root-relative.

**Honeybadger `notify` with a String** (`agent.rb:128–196`): a non-Exception, non-Hash first argument becomes `error_message` (`:142–143`), which satisfies `validate_notify_opts!` (`:658–664`); `error_class`, `tags` (a String is fine, `notice.rb:217`), `context` (merged, `:418–422`), `fingerprint` (a String, SHA1'd again by the gem, `:425–439`) and **`backtrace`** (read from the options before any exception, `exception_attribute`, `notice.rb:326–328`, used at `:211`) are all honoured. `RailsDeprecation` is not in `IGNORE_DEFAULT` (`config/defaults.rb:9–23`). Without `sync:` the notice is queued to the worker thread (`:185–189`); at process exit the gem's `at_exit` calls `Honeybadger.stop` when `send_data_at_exit` is set (`singleton.rb:80–86`; ASSUMPTION: that key defaults to true — the S-check below flushes explicitly so it does not matter). `concurrent-ruby 1.3.6` is in the lock (`Gemfile.lock:125`, an activesupport dependency), so `Concurrent::Map` needs no Gemfile change.

**P3 worker path** (`PropertyDataLookupWorker`, `app/workers/property_data_lookup_worker.rb:30–40`): `perform_async(0)` → `PropertyFactsService.call(0)` → `Property.find(0)` in `initialize` (`property_facts_service.rb:79`) raises `RecordNotFound` → the worker's `rescue StandardError` logs, `update_all`s nothing and **re-raises** (`:39`) → Sidekiq logs `fail` (`sidekiq/job_logger.rb:21`), not `done`. The path that completes with no external call is the already-fetched guard: `guard_already_fetched!` (`:100–104`) raises `PropertyDataAlreadyFetchedError` before any lookup when `property_data_succeeded?` and not forced, and the worker rescues it at `:32–33` with `"…already has property data, skipping"`. On the dev restore 174 properties have `property_data_status = 2` (`Property::PROPERTY_DATA_STATUSES[:succeeded]`, `property.rb:30–36`), ids 1964 … 66237.

**P8 reader**: `Photo#thumb_url` is generated by `has_s3_image_handler` with an empty prefix (`s3_image_handler.rb:18`, `:250–252`; `photo.rb:74–76`). A `Net::HTTP` GET of it from the container today: photo 659058, host `d2e08hhdrjhri.cloudfront.net`, **200**, `image/jpeg`. The ASSUMPTION in §4.0 P8 is confirmed; the plan uses `Net::HTTP` in the runner rather than `curl`.

**Puma shape** (`config/puma.rb:23–24`): threads only, no `workers` line — one process per web dyno. Two web dynos, one Sidekiq dyno, plus one-off dynos: "once per message per process" is at most four notices per distinct deprecation message per release.

**Spec files the kit names** all exist: `spec/models/postal_code_spec.rb`, the four P5 Stripe specs, `spec/requests/users_directory_spec.rb`, `spec/requests/orders_processing_parent_pays_spec.rb`, `spec/workers/` (7 files), and §4.2's boundary four (`orders_processing_release_on_spec.rb`, `accounts_most_recent_shoot_spec.rb`, `marketing_events_rake_spec.rb`, `account_csv_export_service_spec.rb`).

### What the survey changes

1. **P3 uses an already-fetched property, not id 0.** The document's assumption is falsified by `property_data_lookup_worker.rb:39`. v4 amends §4.0 P3 and the notes row.
2. **`Gemfile:29`**, not 28 — §4.2 item 1 and the notes.
3. **The lock diff carries two changed constraint lines** under `activesupport` beside the version lines; §4.2 item 1's "nothing else" is amended to name them.
4. **The slice 0 baseline is a dependency of this slice's deploy**, not of its implementation; the runbook's Prerequisites list it.
5. **`README.md:140–144`'s add-on list is stale** (Papertrail on `fixa`, not `choklad`; SendGrid `silver`, not `starter`; no New Relic). A notes row in the write-back and a README line for a later `docs:` commit in insgt-api, not this slice.

Nothing else disagrees with the document. No STOP.

---

## Phase 1 — plan

### Gaps pinned

1. **`date +%z` in the container** → `+0000` (fact, 2026-10-26). The deliberate break for the `to_time` offset example therefore reads `utc_offset == 0` when line 17 is restored; the spec asserts `-25_200`, so it goes red. The spec does not depend on the system zone when green (a fixed `-0700` offset for a PDT receiver); only the break's observed value does, and the plan records it.
2. **The log-history reach** — pinned from the Mac on 2026-10-26. Facts: the Heroku buffer (1,500 lines) reaches back to **2026-10-26 13:32:53 UTC** and holds **0** `active_storage` lines — minutes to hours of history, as §4.2 item 4 warned, not proof of no traffic. Papertrail **is attached** (`giving-idly-5477`, plan `fixa`) and its search for `rails/active_storage` found **no matching events back to Oct 12 at 08:00 PM** (UI time) — about **fourteen days**, which is the reach this slice states. The 365-day archive could extend it; not needed for a decided OD2. Recorded in: the runbook's "Pre-deploy" section and **commit 4's body**, verbatim: "Heroku buffer: 1,500 lines back to 2026-10-26 13:32:53 UTC, 0 hits. Papertrail (fixa): no matching events, searched back to 2026-10-12 08:00 PM (UI time), about fourteen days." Rule: OD2 is decided — the routes go off whatever the count; the count is zero over the whole searchable window, so there is nothing to attribute. Nothing in the repo or the Angular apps calls these routes (notes, "Active Storage surface").
3. **The first-non-gem-frame rule**: `Rails.backtrace_cleaner.clean(callstack.map(&:to_s)).first || callstack.first.to_s`. Why: the Rails cleaner is the app's existing definition of "our frame" (`app|config|lib|test`, root-relative), already applied to every logged exception; a hand-written gem-path regexp would be a second definition that drifts. The message already carries the first non-*Rails* frame, which for a deprecation triggered inside a gem (sidekiq, lograge, jbuilder calling a deprecated Active Support API) is the gem's own line; the context frame is where in *this* code the call entered the gem. Fallback when no app frame exists (a deprecation entirely inside gems, e.g. at boot): the raw first frame, so the context is never empty. Spec: a callstack of a gem frame then an app frame → the app frame, relative; an all-gem callstack → its first frame verbatim. Decision beyond the document's literal list, **accepted by Dan 2026-10-26**: the notify call also passes `backtrace:` = the full cleaned callstack, so the Honeybadger page shows a stack instead of the subscriber's own line. The v4 amendment adds it to §4.2 item 5.
4. **`bundle update rails --conservative` does not need `minitest` named**: resolved on the scratch copy without it (fact). The implementation runs `bundle update rails --conservative` in the repo and diffs `Gemfile.lock` against the scratch diff above; any difference is a STOP.

### Decisions beyond the gaps

- **Reporter shape.** `app/services/deprecation_reporter.rb`, class `DeprecationReporter` with `.call(payload)` → `new(payload).call` (the repo's service idiom, `property_facts_service.rb:72–75`), `ERROR_CLASS = 'RailsDeprecation'`, `TAGS = 'deprecation'`, and `REPORTED_MESSAGES = Concurrent::Map.new`; `call` returns `false` unless `REPORTED_MESSAGES.put_if_absent(message, true).nil?` (atomic — Puma runs three threads per process), then `Honeybadger.notify(message, error_class:, fingerprint: Digest::SHA256.hexdigest(message), tags:, backtrace:, context: { gem_name:, deprecation_horizon:, callstack: first_app_frame })` and returns the notice id. `.subscribe` does `ActiveSupport::Notifications.subscribe(/\Adeprecation\./) { |event| call(event.payload) }` and returns the subscriber, so the spec can wire and unwire it. ARCHITECTURE NOTES explain once-per-process versus fingerprint-across-processes, why the message is the key, and why there is no rescue: `notify` is asynchronous and the options are fixed, so the only way it raises is a bug, which would surface in Honeybadger as the notifications `InstrumentationSubscriberError` — swallowing would hide that.
- **The initializer is one line of wiring**: `config/initializers/deprecation_reporting.rb` → `DeprecationReporter.subscribe if Rails.env.production?`, with a comment pointing at §4.2/OD8 and at `production.rb`'s `:notify` line (the event exists only where that behaviour is set). The `insgt-api` skill's "no conditionals in initializers" rule bends here because the document says "production-only initializer" and the only alternative, putting the subscription in `production.rb`, is the prompt's trap 2.
- **`deprecation = :notify` alone**, as §4.2 says; `%i[notify log]` considered and not taken: Heroku's 1,500-line buffer loses the line within minutes, and the failure mode "Honeybadger is down" loses every other error too, so the log copy buys nothing the document asked for.
- **Dedupe reset in specs** by `stub_const('DeprecationReporter::REPORTED_MESSAGES', Concurrent::Map.new)` in a `before`; no `reset!` method in production code.
- **Contract spec** `spec/architecture/rails_upgrade_spec.rb`, header in the voice of `account_classification_spec.rb:1–14`, one `describe` per document section; the 404 example lives in `spec/requests/active_storage_routes_spec.rb` because it needs `type: :request`. Each commit appends its own examples (the version floor and `to_time` in commit 2, the `:raise` pin in 3, the routes example in 4).
- **Commit 2 precedes commit 3**: with line 17 still present, `:raise` makes the suite fail at boot — which is also commit 3's deliberate-break evidence.
- **`draw_routes` line placement**: `config/application.rb`, directly after `config.api_only = true` (`:36`), with a why-comment citing §3.3/OD2 and the OrderProcessingNote revisit (§8 item 7).
- **P3 pinned**: start `bundle exec sidekiq -c 1 -e development` (own queue not needed — no other dev Sidekiq is expected to be running; if one is, use `.set(queue:)` as slice 0 did); `bin/rails runner 'id = Property.unscoped.where(property_data_status: 2).order(:id).first.id; jid = PropertyDataLookupWorker.perform_async(id); sleep 5; puts jid; p Sidekiq::Status::status(jid)'`. Asserted: the Sidekiq log shows `Booted Rails 7.2.4 application in development environment`, `PropertyDataLookupWorker JID-<jid> INFO: start`, `[PropertyDataLookupWorker] Property#<id> already has property data, skipping`, `INFO: done: <n> sec`, no `fail`. `Sidekiq::Status::status(jid)` prints `nil` — the known §8 item 10 state, recorded, not asserted. Exercised: Sidekiq boot on 7.2.4, the Rails executor, the Redis round-trip, the job's rescue path.
- **P8 pinned**: `bin/rails runner 'require "net/http"; p = Photo.unscoped.where(status_type: 1).order(:id).last; r = Net::HTTP.get_response(URI(p.thumb_url)); puts p.id, r.code, r["content-type"]'` → `200`, `image/jpeg`.
- **Runbook** `docs/runbooks/deploy-rails-upgrade-1.md` in slice 0's shape (Summary, Where the commands run, Deploy window, Prerequisites, numbered steps with reasoned expectations, Rollback, Known, After the deploy, Deploy log). Written as `Draft` in this session, `Ready` after the review.
- **Branch** `chore/rails-upgrade-slice-1` in insgt-api (mirrors slice 0); the platform-repo write-back on `docs/rails-upgrade-slice-1`. Dan merges both. **Accepted by Dan 2026-10-26.**

### Approach, one unit of work per commit

**1. `build: upgrade rails to 7.2.4`** — `Gemfile:29` → `'~> 7.2.4'`; `bundle update rails --conservative`; `git diff Gemfile.lock` must match the scratch diff line for line. Then `bundle exec rspec` (expected `2009 examples, 0 failures`, still one deprecation line — item 2 has not landed) and `bin/rails zeitwerk:check`. No spec of its own: the contract spec's version floor arrives in commit 2 and is green on arrival; its deliberate break is to raise the floor to `7.2.5` and watch it fail.

**2. `fix: stop forcing the pre-Ruby 2.4 to_time behavior`** — write `spec/architecture/rails_upgrade_spec.rb` first with three examples (below); run it: the `to_time` pair is red (`false`; offset `0`), the version example green. Delete `new_framework_defaults.rb:15–17`. Green. Deliberate break: re-add line 17 → offset `0`, red; remove. `bundle exec rspec` → `0` deprecation lines, example count 2012. Run the R3 boundary specs by name (below). ESTIMATE: no runtime change.

**3. `test: raise on deprecations in the test environment`** — add the contract example that `Rails.application.config.active_support.deprecation == :raise` (red: today `:stderr`); change `test.rb:58`; green. Evidence for the gate itself: with line 17 temporarily restored, `bundle exec rspec` fails at boot with `ActiveSupport::DeprecationException` — paste the first lines — then restore. Full suite green with `:raise`; the 24 rspec-rails warnings remain (Ruby `warn`, not Active Support).

**4. `chore: stop drawing the unused Active Storage routes`** — write the contract example (`Rails.application.routes.routes.none? { |route| route.path.spec.to_s.include?('active_storage') }`) and `spec/requests/active_storage_routes_spec.rb` (`post '/rails/active_storage/direct_uploads'` → `have_http_status(:not_found)`); run: red (9 routes; 400). Add the line to `application.rb`; green. Deliberate break: `= true` → both red. `bin/rails routes | grep -c active_storage` → `0`, total 583. Body: the log-history reach from gap 2.

**5. `feat: report production deprecations to honeybadger once per message`** — write `spec/services/deprecation_reporter_spec.rb` first (red: `NameError`). Add the service, the initializer, and the two `production.rb` lines (`:83` → `true`; a new `config.active_support.deprecation = :notify` beneath it, comment rewritten from "Don't log any deprecations" to say where they go). Green. Deliberate break: drop the `put_if_absent` guard → the `.once` example fails with a second call. Lint; full suite; `zeitwerk:check` (the new service is eager-loaded in production).

Then, once for the slice: P1–P8 with `7.2.4`; the runbook; `predeploy-review-rails` (two rounds, Codex on an rsync copy without `.env`, per the slice 0 practice); fixes folded into the commit they belong to on the unpushed branch; the write-back commits.

### Spec plan — boundary cases by name

`spec/architecture/rails_upgrade_spec.rb` (new; `type: :model` like its sibling):

| Section | Example | Pinned value | Deliberate break |
| :-- | :-- | :-- | :-- |
| §1.2 / §4.2 | the framework runs at least the version the document names for this slice | `Rails.gem_version >= Gem::Version.new('7.2.4')` | floor to `7.2.5` → red |
| §4.2 item 2 | `to_time` preserves the receiver's offset — the setting | `ActiveSupport.to_time_preserves_timezone` is `true` | re-add line 17 → `false` |
| §4.2 item 2 | — the behaviour | `TimeZone['Pacific Time (US & Canada)'].parse('2026-10-23 10:00').to_time.utc_offset == -25_200` | re-add line 17 → `0` in this container |
| §4.2 item 3 | a deprecation is a red suite | `config.active_support.deprecation == :raise` | set `:stderr` → red |
| §3.3 / OD2 | no Active Storage route is drawn | `routes.none? { … 'active_storage' }` | `draw_routes = true` → 9 |

`spec/requests/active_storage_routes_spec.rb` (new): `POST /rails/active_storage/direct_uploads` → 404 (today 400, so red for the right reason; break: `draw_routes = true` → 400 again).

`spec/services/deprecation_reporter_spec.rb` (new; `Honeybadger` stubbed as `scheduler_rake_spec.rb:20, 33` does):

1. notifies once for a payload: `Honeybadger.notify` receives the message with `error_class: 'RailsDeprecation'`, `fingerprint: Digest::SHA256.hexdigest(message)`, `tags: 'deprecation'`, context `gem_name`, `deprecation_horizon`, `callstack` (break: remove the dedupe → `.once` fails on example 2, not this one).
2. does not notify a second time for the same message in the same process (`expect(Honeybadger).to receive(:notify).once`).
3. notifies again for a different message.
4. `callstack` context is the first frame inside the app, root-relative: a callstack `[<gem frame>, "#{Rails.root}/app/models/order.rb:433:in 'urlify'"]` → `"app/models/order.rb:433:in 'urlify'"`; `backtrace:` is the cleaned list.
5. falls back to the raw first frame when no app frame exists.
6. `.subscribe` wires the `deprecation.*` events: a fresh `ActiveSupport::Deprecation.new('9.0', 'SpecGem')` with `behavior = :notify` (not registered with the app, so `:raise` does not apply) → `warn('spec message')` → `notify` receives a message containing `spec message` and `gem_name: 'SpecGem'`; `ensure ActiveSupport::Notifications.unsubscribe(subscriber)`.

Existing coverage run by name (R3 — the `to_time` offset step): `spec/requests/orders_processing_release_on_spec.rb`, `spec/requests/accounts_most_recent_shoot_spec.rb`, `spec/lib/tasks/marketing_events_rake_spec.rb`, `spec/services/account_csv_export_service_spec.rb` — 0 failures each after commit 2.

### Commit sequence

insgt-api, branch `chore/rails-upgrade-slice-1`:

1. `build: upgrade rails to 7.2.4` [1]
2. `fix: stop forcing the pre-Ruby 2.4 to_time behavior` [2] — body: the line was the suite's only deprecation and 8.0 removes the behaviour; `load_defaults 7.2` already sets the value `true`, so deleting the override is the whole change.
3. `test: raise on deprecations in the test environment` [1]
4. `chore: stop drawing the unused Active Storage routes` [2] — body: the log-history reach, verbatim from gap 2 — Heroku buffer 1,500 lines back to 2026-10-26 13:32:53 UTC, 0 hits; Papertrail (fixa) no matching events back to 2026-10-12 08:00 PM, about fourteen days.
5. `feat: report production deprecations to honeybadger once per message` [3, trigger 2] — body: `:notify` + a `deprecation.*` subscriber is the pattern any later deprecator-aware reporting follows; once per message per process, grouped across processes by fingerprint; why the message is the key.

Platform repo, branch `docs/rails-upgrade-slice-1`: `docs: add the rails upgrade slice 1 runbook` (before the push), then after verification `docs: amend the rails upgrade design to v4 for slice 1` and `docs: update the rails upgrade notes for slice 1`; after the deploy `docs: record the slice 1 deploy in the rails upgrade runbook`.

### Post-deploy verification

**Pre-deploy, on the branch** (§4.0 with `7.2.4`):

| # | Expected |
| :-- | :-- |
| P1 | `N examples, 0 failures`, N ≥ 2009 (ESTIMATE 2022: +5 contract, +1 request, +6 reporter … exact count reported); `grep -c "DEPRECATION WARNING"` → `0` |
| P2 | `All is good!` |
| P3 | as pinned above: `Booted Rails 7.2.4 …`, `start`, `…already has property data, skipping`, `done`; status `nil` recorded |
| P4 | 3 examples, 0 failures |
| P5 | 0 failures across the four files |
| P6 | `SystemError::rails upgrade` |
| P7 | 0 failures |
| P8 | `200`, `image/jpeg` via `Net::HTTP` |

**On the Mac, before the push** (the log-history check is done; gap 2): capture S4 (`PostalCode.find_by(zip: "92008").nearby_cities.limit(3).pluck(:name)`) and send S6 on v661 so "unchanged" is provable; `heroku config --app insgtapi | grep -o '^HONEYBADGER_[A-Z_]*'` still lists both variables (nothing new is needed — the reporter uses the slice 0 key).

**Production spot checks, within 30 minutes of the push** (reasoned now, before the code exists):

| # | Command (from the Mac) | Expected |
| :-- | :-- | :-- |
| S0 | the marker runner with `slice 1` and the new `vNNN` | `UpgradeMarker` gains an occurrence, context `rails: 7.2.4` |
| S2 | `heroku ps`; `heroku logs --ps backgroundworker.1 -n 300 \| grep Booted` | `web.1`, `web.2`, `backgroundworker.1` up; `Booted Rails 7.2.4 application in production environment` |
| S3 | `heroku run … rails runner 'puts Rails.version; puts ActiveSupport.to_time_preserves_timezone.inspect'` | `7.2.4`, `true` |
| S8 | `heroku run … rails runner 'puts ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("2026-10-28 10:00").to_time'` | `2026-10-28 10:00:00 -0700` (on v661 it prints `2026-10-28 17:00:00 UTC` — capture that before the push as the "before") |
| S-AS | `curl -sS -o /dev/null -w "%{http_code}" -X POST https://api.insightphotos.net/rails/active_storage/direct_uploads` | `404` (on v661: `400`) |
| S-DEP | `heroku run … rails runner 'ActiveSupport.deprecator.warn("rails upgrade reporter check"); Honeybadger.flush'` | exactly one `RailsDeprecation` error in Honeybadger, message `DEPRECATION WARNING: rails upgrade reporter check (called from …)`, tag `deprecation`, context `gem_name: Rails`, `deprecation_horizon: 8.0`; running it a second time in a *new* one-off dyno adds an occurrence to the same error (fingerprint), not a new error |
| S1, S4, S5, S6, S7 | as §4.0 | `200`; S4 identical to the pre-push capture; `true`; the email arrives; `status=5` count `0` |
| SH | Honeybadger Errors since the push vs the slice 0 baseline | no class absent from the baseline except `RailsDeprecation` from S-DEP; **no other `RailsDeprecation` within 24 h** — one would be a finding (a deprecation on an untested production path; OD8 says it is a STOP for the *next* slice, and this slice's runbook records it) |
| S9 | the next hourly `import_listings` check-in | on time |

**Rolling deploy**: no migration, no schema, no window; a Heroku release swaps all dynos at once. **Rollback**: `heroku rollback` to v661; nothing to undo — the reporter's dedupe is per process and dies with it; the routes return with the old slug.

### Risks

- **R3 (`to_time` offset step)** — the only behaviour change a human could see, and it needs a code path that calls `.to_time` on a zoned value: none in `app/`/`lib/` (grep), so it would be a gem. The four boundary specs and S4/S6/S8 are the pre- and post-deploy reads; the symptom in the wild (an order missing from or extra on a day's list in insgt-ops) has no exception. Likelihood low; cost of a miss: a day-boundary shift for a Pacific user, reverted in seconds.
- **A gem-originated deprecation surfaces in production once reporting is on** — the design intent, not a failure (§5 watched list). It becomes a STOP for slice 2 under OD8 if it is one `:raise` would trip in the suite; a production-only one (SMTP, lograge, puma_worker_killer, the one-off dyno path) is recorded and triaged in slice 2's survey.
- **Honeybadger volume**: at most four processes per release times the number of distinct (message, call-site) pairs; the trial has no stated notice cap that this would approach (UNVERIFIED; §4.1 chose the trial knowing errors are the only feed).
- **Heroku slug build on 7.2.4**: a patch bump of the same minor; the same buildpack path as v659, v660 and v661. The 8.x question (§2.5 UNVERIFIED) is slice 2's.
- **The baseline is missing on deploy morning** (due 2026-10-27 ~10:00 ET; the push is Wed 10-28 09:30 PT): SH would have nothing to compare against. Listed as a runbook prerequisite.
- **Line numbers in the design document are one off** at `Gemfile:28` — cosmetic, fixed in v4; a reviewer reading §4.2 literally must not "correct" line 28.

### Open questions for the engineer

Settled by Dan on 2026-10-26: the Papertrail search (no matching events back to Oct 12 at 08:00 PM — gap 2 closed), `backtrace:` on the notify call (accepted — gap 3), and the two branch names (accepted). One remains:

1. **The slice 0 baseline**: confirm it will be written into `deploy-rails-upgrade-0.md` (step 5) before Wednesday's push; the slice 1 runbook lists it as a prerequisite. Due about 2026-10-27 10:00 ET.

### Unverified

- The time zone Papertrail displays "Oct 12 at 08:00 PM" in (the account's zone; the reach is about fourteen days either way).
- `send_data_at_exit`'s default in honeybadger 6.10.0 (the S-DEP runner flushes explicitly, so the check does not depend on it).
- That the Heroku build of 7.2.4 is uneventful (the release is the proof).
- Sidekiq 7.3.10 on Rails 7.2.4 beyond what P3 exercises in development (§3.1 names P3 as the proof per slice).
- The Honeybadger trial's notice quota.

### Next phase, if approved

The implementation loop, commits 1 → 5 as above, each red → green → deliberate break → lint → area suite → commit; then P1–P8, the runbook as `Draft`, the two-round `predeploy-review-rails`, and the verification STOP with the spot-check table filled in from development and the pre-push captures listed for the Mac.
