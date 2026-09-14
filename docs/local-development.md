# Local Development

Everything runs from one launcher and one Procfile.

    $ cd /workspace
    $ bin/dev                # the whole stack
    $ bin/dev api ops        # just those (plus sidekiq — see below)
    $ bin/dev --help         # options and the process table

## Processes

| name                 | port | repo                            |
| -------------------- | ---- | ------------------------------- |
| `api`                | 3000 | `apps/insgt-api`                |
| `galleries`          | 3001 | `apps/insgt-galleries`          |
| `virtual_tour`       | 3002 | `apps/insgt-virtual-tour`       |
| `app`                | 4200 | `apps/insgt-app`                |
| `ops`                | 4300 | `apps/insgt-ops`                |
| `photographers`      | 4400 | `apps/insgt-photographers`      |
| `disclosure_gallery` | 4500 | `apps/insgt-disclosure-gallery` |
| `sidekiq`            | —    | `apps/insgt-api`                |
| `site`               | 8080 | `functions/insgt-site-sls`      |

Names may be spelled with hyphens: `bin/dev virtual-tour` and
`bin/dev disclosure-gallery` both work.

## Selecting what to run

`bin/dev` with no names starts everything. With names it starts exactly those,
plus `sidekiq` whenever `api` is selected — an API without its worker enqueues
jobs that never run, which is a failure you notice an hour later, somewhere
else. The resolved set is always echoed before foreman starts:

    $ bin/dev api ops
    ==> starting: api ops sidekiq

Selection is `foreman start -m all=0,<name>=1,…` against `Procfile.dev`. There is
no second Procfile; the old `Procfile.api-*` files and their `bin/api-*`
launchers are gone. For the rare case that wants something the launcher will not
express — `api` without `sidekiq`, say — call foreman directly:

    $ LANG=C.UTF-8 foreman start -f Procfile.dev -e /dev/null -m all=0,api=1

Note that you lose the port preflight and the exit sweep by doing so.

### What replaced each old command

| was                     | now                              |
| ----------------------- | -------------------------------- |
| `bin/api-app`           | `bin/dev api app`                |
| `bin/api-app-ops`       | `bin/dev api app ops`            |
| `bin/api-disclosure`    | `bin/dev api disclosure-gallery` |
| `bin/api-galleries`     | `bin/dev api galleries`          |
| `bin/api-ops`           | `bin/dev api ops`                |
| `bin/api-photographers` | `bin/dev api photographers`      |
| `bin/api-site`          | `bin/dev api site`               |
| `bin/api-virtual-tour`  | `bin/dev api virtual-tour`       |

Two behaviour changes worth knowing: `bin/api-virtual-tour` also started `ops`
(add `ops` if you want that back), and `bin/api-site` was broken — it passed
`--host`/`--port` to `concurrently`, which ignored them.

The `*.code-workspace` files pair with these one-to-one: open
`api+ops.code-workspace` and run `bin/dev api ops`; open
`everything.code-workspace` and run `bin/dev`.

## Ports already in use

`bin/dev` refuses to start if anything is listening on a port belonging to a
process you selected, and prints what is holding it:

    Ports for the selected processes are already in use:
      3000  pid 12345   ruby bin/rails server -b 0.0.0.0 -p 3000

Re-run with `--force` to SIGTERM (then, after 5s, SIGKILL) those first.

Only the selected processes' ports are considered, which is what lets two stacks
coexist:

    terminal 1 $ bin/dev api          # 3000
    terminal 2 $ bin/dev ops          # 4300, does not fight with terminal 1

Quitting terminal 2 sweeps 4300 and leaves 3000 alone.

## Why the launcher is more than `exec foreman`

foreman 0.90 signals only its direct children on teardown (`kill_children`
signals `pids`, not `-pids`), so one process exiting can orphan servers that then
hold ports for days. `Procfile.dev` uses `exec` in every entry so the pid foreman
tracks is the pid that needs to die — **read the header of that file before
editing it.**

`bin/dev` adds the backstop for what `exec` cannot cover, namely foreman being
SIGKILLed or the terminal being closed outright: a port preflight, an exit sweep
on `EXIT INT TERM`, and removal of stale `tmp/pids/server.pid` files that would
otherwise stop Rails booting. That is also why the script does not `exec`
foreman — the sweep only runs if the shell outlives it.

## Adding a process

1. Add the line to `Procfile.dev`, with `exec`, following that file's header.
2. Add it to `PROCESSES`, `DIR`, and — if it listens — `PORT` in `bin/dev`.
   Rails servers also go in `RAILS` so their pid files get cleaned.
3. Add the port to `forwardPorts` and `portsAttributes` in
   `.devcontainer/devcontainer.json`.
4. Add the row to the table above.

`bin/dev` warns on every run if step 2 falls out of sync with step 1, including
when a port changes in one place only.

## Troubleshooting

**`invalid byte sequence in US-ASCII`** from a hand-run `foreman`. `LANG` is
unset container-wide, so Ruby reads `Procfile.dev` as US-ASCII and chokes on the
em dashes in its header. `bin/dev` sets `LANG` itself; for a bare foreman call
use `LANG=C.UTF-8 foreman …`.

**A server survived a hard kill.** `bin/dev --force <names>` clears the ports and
the stale pid files, then starts.

**Two sidekiqs.** `sidekiq` binds no port, so the preflight cannot detect a
second one. Check with `ps -ef | grep sidekiq` if jobs behave strangely.

**`site` leaves a watcher behind.** `npm start` there runs eleventy (8080) and a
postcss watcher that binds nothing, so the sweep reclaims the port but cannot see
the watcher. Kill it by hand if it lingers.
