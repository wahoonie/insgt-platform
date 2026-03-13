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

echo "✅ Setup complete!"