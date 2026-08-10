#!/bin/bash
set -e

export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"

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