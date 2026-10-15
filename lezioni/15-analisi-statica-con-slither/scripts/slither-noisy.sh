#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/slither-env.sh"

"$slither_bin" . \
  --filter-paths "lib|test|script|src/fixed|src/context|src/mocks"
