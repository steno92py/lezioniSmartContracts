#!/usr/bin/env bash
set -euo pipefail

if ! command -v slither >/dev/null 2>&1; then
  echo "Slither non trovato. Installa requirements-slither.txt in un ambiente virtuale." >&2
  exit 127
fi

slither . \
  --filter-paths "lib|audit/tests|script" \
  --print human-summary,entry-points,function-summary,vars-and-auth
