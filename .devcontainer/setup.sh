#!/bin/bash
set -e

export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"

echo "🔧 Allowing git to operate on /workspace..."
# Docker Desktop's VirtioFS reports the bind-mount root (/workspace) as root:root, while
# every directory inside it maps to vscode correctly and stays writable. Git 2.35+ refuses
# to touch a repo whose worktree looks like it belongs to another user, so the platform
# repo itself dies with "dubious ownership" once the kernel refreshes its cached attributes
# for that inode — usually partway through a session, not at startup. Only the share root
# misreports, so the nested app repos are unaffected and need no exception. This lives here
# because ~/.gitconfig is copied fresh from the Mac on every container create.
git config --global --get-all safe.directory | grep -qx /workspace \
  || git config --global --add safe.directory /workspace

echo "💎 Installing Ruby dependencies..."
for dir in /workspace/apps/insgt-*/; do
  if [ -f "$dir/Gemfile" ]; then
    echo "  → $(basename $dir)"
    cd "$dir"
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
