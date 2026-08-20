# Enable headless Cypress runs in the devcontainer

## Context

Four apps in this workspace have Cypress e2e suites — `insgt-ops` (v15.19.0, port 4300), `insgt-app` (v15.8.1, 4200), `insgt-photographers` (v14.5.1, 4400), `insgt-disclosure-gallery` (v15.8.1, 4500) — but **none of them can run inside this container today**. The devcontainer image installs only Ruby/Rails build dependencies; nothing for Electron/Chromium. Three concrete blockers, all verified live:

1. **25 missing shared libraries.** `ldd ~/.cache/Cypress/15.19.0/Cypress/Cypress` reports `libgtk-3.so.0`, `libnss3.so`, `libgbm.so.1`, `libasound.so.2`, `libX11.so.6` and 20 others as `not found`. The binary cannot start.
2. **No Xvfb.** Cypress spawns an X server for `cypress run` on Linux even in headless mode; without it the run aborts with `Your system is missing the dependency: Xvfb`.
3. **`/dev/shm` is 64M** (the Docker default). Even once Cypress launches, Chromium/Electron will crash mid-run with "Your Test tab crashed" at the 1280×720 viewports these suites use.
4. **`ELECTRON_RUN_AS_NODE=1` leaks in from the VS Code extension host** *(found during implementation, not during planning)*. With this set, Cypress's Electron binary starts as plain Node, which rejects Cypress's own flags: `bad option: --no-sandbox`, `bad option: --smoke-test`. Confirmed by running the binary directly — `Cypress --version` printed `v22.19.0`, the Node version. This blocks Cypress even with every library present, and no amount of apt work fixes it.

Outcome: `npm run test:e2e` (and the equivalent script in each app) works from a container terminal against a locally-running `ng serve`, with no host-side setup.

**Scope decisions (confirmed with user):** Electron only — no Chromium/Chrome install. Container capability only — no runner scripts or npm-script changes in the app repos. Workflow stays "start `ng serve` in one terminal, run Cypress in another."

**Platform constraint:** this image is **Debian 13 (trixie) on aarch64**. The Cypress docs' copy-paste apt line targets bullseye/bookworm and will fail here — several packages were renamed in the 64-bit `time_t` transition (`libasound2` → `libasound2t64`, `libgtk-3-0` → `libgtk-3-0t64`, etc.), and `libgtk2.0-0` is neither present nor needed by Cypress 10+.

---

## Changes

### 1. `.devcontainer/Dockerfile` — add Electron runtime libraries

Append a `USER root` → install → `USER vscode` block **after** the existing `RUN eval "$(mise activate bash)" ...` layer (line 36–39), before `WORKDIR /workspace`.

Placement matters for two reasons:
- The Dockerfile switches to `USER vscode` at line 24 and never switches back, so an `apt-get install` appended naively fails on permissions.
- Adding to the *existing* apt block at line 4 would invalidate the cache for the mise/Ruby/Node/gem layers and force a full slow rebuild. Appending at the end adds one layer and leaves everything above cached.

```dockerfile
# Cypress/Electron runtime dependencies (Debian 13 trixie — note t64 package names)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    xauth \
    libgtk-3-0t64 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libasound2t64 \
    libxtst6 \
    libgbm1 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libatspi2.0-0t64 \
    libcups2t64 \
    libdrm2 \
    libdbus-1-3 \
    libglib2.0-0t64 \
    libcairo2 \
    libpango-1.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libxfixes3 \
    libxext6 \
    libx11-xcb1 \
    libxkbcommon0 \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*
USER vscode

# Mount points must exist and be vscode-owned so the named volumes inherit ownership
RUN mkdir -p /home/vscode/.cache/Cypress /home/vscode/.claude
```

The `mkdir` is load-bearing, not cosmetic: Docker creates a missing mount point as `root`, which would leave both directories unwritable by `vscode`. Creating them in the image as `vscode` makes each fresh volume inherit that ownership.

Several entries are transitive dependencies of `libgtk-3-0t64`; listing them explicitly is deliberate — it documents what Cypress needs and survives GTK repackaging. `--no-install-recommends` keeps the layer near ~200MB.

**Validate the package names before editing** (they are the one fragile part). In the current running container:

```bash
sudo apt-get update && sudo apt-get install -s xvfb xauth libgtk-3-0t64 libnotify4 \
  libnss3 libxss1 libasound2t64 libxtst6 libgbm1 libatk1.0-0t64 libatk-bridge2.0-0t64 \
  libatspi2.0-0t64 libcups2t64 libdrm2 libdbus-1-3 libglib2.0-0t64 libcairo2 \
  libpango-1.0-0 libxcomposite1 libxdamage1 libxrandr2 libxfixes3 libxext6 \
  libx11-xcb1 libxkbcommon0 fonts-liberation
```

`-s` simulates only — nothing is installed. Any `Unable to locate package` names get corrected (drop or re-add the `t64` suffix) before they go in the Dockerfile.

Note the file has **no trailing newline** on `WORKDIR /workspace`; add one so the diff stays clean.

### 2. `.devcontainer/docker-compose.yml` — shm size and two persistent volumes

On the `app` service:

```yaml
    shm_size: 2gb
```

and add to its `volumes:` list:

```yaml
      - cypress-cache:/home/vscode/.cache/Cypress
      - claude-home:/home/vscode/.claude
```

then register both under the top-level `volumes:` block alongside the existing two:

```yaml
  cypress-cache:
    name: insgt-platform-cypress-cache
  claude-home:
    name: insgt-platform-claude-home
```

`cypress-cache` earns its keep immediately: three distinct Cypress versions (15.19.0, 15.8.1, 14.5.1) are in play at ~200MB each, and today they live in the container's writable layer and are re-downloaded on every rebuild.

`claude-home` fixes the problem this change surfaced — `~/.claude` (plans, session transcripts, the memory dir, user `settings.json`) is currently unmounted and wiped on every rebuild. Note it does **not** rescue the current contents: a new named volume is seeded from the image, not from the running container's writable layer, so the manual copy in step 2 below is still needed for *this* rebuild. From the next rebuild onward, state persists automatically.

This file also lacks a trailing newline.

### 3. No change to `devcontainer.json`, `setup.sh`, or `startup.sh`

> **Correction (2026-08-06): the `setup.sh` half of this was wrong, and has since been fixed.**
> `npm install` does *not* reliably trigger Cypress's postinstall binary download here. `node_modules/`
> sits under the `/workspace` bind mount and is shared with the Mac, so the tree is normally already
> populated — and npm only runs a package's `postinstall` when it actually installs that package.
> Cypress is skipped, and the linux-arm64 binary is never fetched; the Mac's copy lives in the host's
> `~/Library/Caches/Cypress`, which the container cannot see. This is exactly why `insgt-app` still had
> no binary. `setup.sh` now ends with an explicit `npx cypress install` loop over every app that has
> Cypress in `node_modules`. The `startup.sh` half below is unchanged and still correct.

Cypress manages Xvfb itself for `cypress run`, so no `DISPLAY` export or Xvfb launcher belongs in `startup.sh` — adding one would only be needed for headed/`cypress open` mode, which is out of scope here.

---

## Execution sequence (rebuild is destructive — read first)

Only `/workspace` and `/host-data` are bind-mounted, plus the single file `/home/vscode/.claude.json`. The **`~/.claude/` directory is not mounted** — it lives in the container's writable layer. A restart keeps it; a **rebuild destroys it**, taking this plan file, this conversation's transcript, the `~/.claude/projects/-workspace/memory/` dir, and the four other plan files in `~/.claude/plans/` with it.

The edits in this plan are unaffected — `.devcontainer/*` is in `/workspace`, which is on the host.

Run it in this order:

1. **Make all edits** to `.devcontainer/Dockerfile` and `.devcontainer/docker-compose.yml` (steps 1–2 above). These land on the host immediately.

2. **Rescue `~/.claude` state to the bind mount**, since this one rebuild still wipes it:

   ```bash
   mkdir -p /workspace/docs/claude-state
   cp ~/.claude/plans/update-this-container-so-delightful-possum.md /workspace/docs/claude-state/
   cp -r ~/.claude/projects/-workspace/memory /workspace/docs/claude-state/
   cp ~/.claude/settings.json /workspace/docs/claude-state/
   ```

   The memory dir holds saved facts about you and this project — its loss would be silent and permanent. User `settings.json` comes along because it is small and equally unmounted. After the rebuild, copy `memory/` and `settings.json` back into the (now persistent) `~/.claude`. Your four other plan files are being left behind per your choice.

3. **Rebuild**: Dev Containers → *Rebuild Container*. Only the new apt layer builds; the mise/Ruby/Node layers stay cached.

4. **Reopen a Claude session** in the rebuilt container and work through Verification below, reading from `/workspace/docs/claude-state/`. The prior session history will be gone.

---

## Verification

All commands run from a container terminal after the rebuild.

```bash
# 1. shm is no longer 64M
df -h /dev/shm                                   # expect ~2.0G

# 2. Xvfb present
which Xvfb xauth

# 3. Re-fetch the binary — the fresh cypress-cache volume starts empty
cd /workspace/apps/insgt-ops
npx cypress install                              # ~200MB, one time

# 4. Zero unresolved shared objects (this is the real fix)
ldd ~/.cache/Cypress/*/Cypress/Cypress | grep "not found"   # expect no output

# 5. Cypress self-check passes
npx cypress verify
npx cypress info                                 # see note below
```

Step 4 is the meaningful one — it must be run *after* step 3, or the glob matches nothing and the empty output is a false pass. Prefer naming the version explicitly (`~/.cache/Cypress/15.8.1/...`) over the `*` glob, which silently passes when the cache is empty.

`cypress info` prints **"Detected no known browsers installed"** — that is expected, not a failure. It lists only *external* browsers, and this container deliberately installs none (Electron-only was a scope decision above). The bundled Electron is always available and is what `cypress run` uses by default; the `DevTools listening on ws://...` line in that command's output is the proof it launches.

> **Update (2026-08-06):** the per-app `npx cypress install` step is no longer manual — `setup.sh`
> now runs it for every app with Cypress in `node_modules` on container create (see the correction
> in section 3). `insgt-app`'s 15.8.1 binary was installed and its suite confirmed working:
> `sign-in.cy.ts` passes headless against `ng serve` on :4200. `insgt-photographers` (14.5.1) and
> `insgt-disclosure-gallery` (15.8.1, already cached) will be fetched on the next container create.

End-to-end, in two terminals:

```bash
# terminal 1
cd /workspace/apps/insgt-ops && npm start        # ng serve on 4300, --host 0.0.0.0

# terminal 2 — single spec first, then the suite
cd /workspace/apps/insgt-ops
npx cypress run --spec cypress/e2e/app/dashboard-check.cy.ts
npm run test:e2e
```

A pass on the single spec proves the container fix. Suite-level failures after that are application/fixture issues, not container issues — `insgt-ops` reads credentials from `cypress.env.json` and several specs need the Rails API on 3000.

Finally, confirm the cache survives: rebuild once more and check `ls ~/.cache/Cypress` still lists the downloaded versions.

## Risks

- **Package-name drift on trixie/arm64** — the `t64` suffixes are the only likely build failure. The `apt-get install -s` dry run above catches this before the Dockerfile is touched.
- **First run after rebuild is slow** — the binary cache starts empty, so ~200MB downloads per Cypress version. One-time cost; the volume makes it stick.
- **`--browser chrome` remains unavailable** — no Chromium is installed, and Google Chrome ships no Linux ARM64 build. `apps/insgt-photographers/.github/workflows/cypress.yml` specifies `browser: chrome`, but that runs on GitHub's x86 runners, so it is unaffected by this change. (That workflow is separately stale — it pins Node 18 against an Angular 20 app.)
