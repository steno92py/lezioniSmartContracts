#!/usr/bin/env bash
set -euo pipefail

if ! command -v slither >/dev/null 2>&1; then
  echo "Slither non trovato. Installa la versione in requirements-slither.txt in un ambiente isolato." >&2
  exit 127
fi

slither . \
  --filter-paths "lib|test|script|src/noisy|src/context|src/mocks" \
  --fail-medium
