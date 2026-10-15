#!/usr/bin/env bash
# Caricato dagli script: preferisce l'ambiente isolato della lezione.
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$lesson_dir/.venv-slither/bin/slither" ]]; then
  slither_bin="$lesson_dir/.venv-slither/bin/slither"
elif command -v slither >/dev/null 2>&1; then
  slither_bin="$(command -v slither)"
else
  echo "Slither non trovato. Installa requirements-slither.txt in .venv-slither con Python >= 3.10 (vedi README)." >&2
  exit 127
fi
cd "$lesson_dir"
