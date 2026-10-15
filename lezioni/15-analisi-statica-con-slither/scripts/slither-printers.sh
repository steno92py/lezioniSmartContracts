#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/slither-env.sh"

"$slither_bin" . \
  --filter-paths "lib|test|script" \
  --print human-summary,entry-points,function-summary,vars-and-auth
