#!/usr/bin/env bash
set -euo pipefail

if ! command -v slither >/dev/null 2>&1; then
  echo "Slither non trovato. Installa requirements-slither.txt in un venv locale." >&2
  exit 127
fi

slither . --filter-paths "lib|test|script|src/EscrowFinal.sol|src/mocks|src/extensions"
