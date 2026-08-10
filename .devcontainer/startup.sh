#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"

echo "Waiting for PostgreSQL..."

until pg_isready \
  -h "${DATABASE_HOST:-db}" \
  -p "${DATABASE_PORT:-5432}" \
  -U "${DATABASE_USERNAME:-postgres}"
do
  sleep 1
done

echo "PostgreSQL is ready."