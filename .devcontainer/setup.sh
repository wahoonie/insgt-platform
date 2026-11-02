#!/bin/bash
set -e

export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"

echo "🔧 Allowing git to operate on /workspace and the repos under it..."
# Docker Desktop's VirtioFS reports the bind-mount root (/workspace) as root:root, while
# every directory inside it maps to vscode and stays writable. Git 2.35+ refuses to touch a
# repo whose worktree looks like it belongs to another user, so a repo dies with "dubious
# ownership" once the kernel refreshes its cached attributes for that inode — usually
# partway through a session, not at startup. The share root does this every time; the nested
# repos have done it too (apps/insgt-virtual-tour, 2026-11-02, twice within long bundler
# sessions), so every repo in the tree is whitelisted. The trailing "/*" entries need
# git 2.46+ (the container has 2.52) and cover repos added later. This lives here because
# ~/.gitconfig is copied fresh from the Mac on every container create.
for safe_directory in /workspace '/workspace/apps/*' '/workspace/lib/*' '/workspace/functions/*'; do
  git config --global --get-all safe.directory | grep -qxF "$safe_directory" \
    || git config --global --add safe.directory "$safe_directory"
done

echo "💎 Installing Ruby dependencies..."
for dir in /workspace/apps/insgt-*/; do
  if [ -f "$dir/Gemfile" ]; then
    echo "  → $(basename $dir)"
    cd "$dir"
    # tmp/ is under the host bind mount, so bootsnap's load-path cache outlives the container.
    # It records which directory holds each gem's compiled .so and never rescans gem
    # directories, so after a rebuild that changes the Ruby build it can point at a file that
    # no longer exists (mise's precompiled Ruby keeps extensions out of each gem's lib/) and
    # the app dies in config/boot.rb with a LoadError. Bootsnap regenerates it on first boot.
    rm -f "$dir/tmp/cache/bootsnap/load-path-cache"
    bundle install
  fi
done

echo "🅰️ Installing Node dependencies..."
for dir in /workspace/apps/insgt-*/; do
  if [ -f "$dir/package.json" ] && [ ! -f "$dir/Gemfile" ]; then
    echo "  → $(basename $dir)"
    cd "$dir"
    npm install --legacy-peer-deps
  fi
done

for dir in /workspace/functions/insgt-*/; do
  if [ -f "$dir/package.json" ]; then
    echo "  → $(basename $dir)"
    cd "$dir"
    npm install --legacy-peer-deps
  fi
done

echo "🌲 Installing Cypress binaries..."
# npm's postinstall hook cannot be relied on to fetch these. node_modules/ lives under the
# host bind mount, so the tree is usually already populated (from the Mac, whose Cypress
# binary cache the container cannot see) and npm skips reinstalling cypress — taking its
# postinstall download with it. Ask Cypress directly instead. The cache is a named volume,
# so this is a sub-second no-op once warm; each app pins its own version and needs its own
# ~200MB binary.
for dir in /workspace/apps/insgt-*/; do
  if [ -d "$dir/node_modules/cypress" ]; then
    echo "  → $(basename $dir)"
    cd "$dir"
    # Don't let a flaky CDN fetch abort postCreate after everything above succeeded.
    npx cypress install \
      || echo "  ⚠️  Cypress download failed — rerun 'npx cypress install' in $(basename $dir)"
  fi
done

echo "✅ Setup complete!"
