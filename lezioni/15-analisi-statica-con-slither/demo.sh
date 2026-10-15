#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  falso-successo  Confermare il falso successo
  capability  Seguire input e autorità fino agli asset
  contesto  Motivare il triage contestuale
  correzione  Ridurre la capability e ritestare
  configurazione  Documentare configurazione filtri e assunzioni
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  falso-successo) args=( --match-contract '^NoisyFindingsTest$' --match-test '^(test_Confirmed_UncheckedCallCreatesFalseSuccess)\(' -vvvv) ;;
  capability) args=( --match-contract '^NoisyFindingsTest$' --match-test '^(test_Confirmed_ArbitraryCallCanMoveAssetsHeldByLab|test_Confirmed_AnyoneCanTakeAdminRole)\(' -vvvv) ;;
  contesto) args=( --match-contract '^ContextualTriageTest$' --match-test '^(test_CallbackCannotRepeatTerminalTransition|test_SecondFinishUsesExactTerminalError)\(' -vvvv) ;;
  correzione) args=( --match-contract '^FixedRegressionTest$' --match-test '^(test_Regression_FailedActionCannotMarkCompleted|test_Regression_StrangerCannotExecute|test_Regression_StrangerCannotReplaceAdmin|test_AdminExecutesOnlyImmutableTypedAction)\(' -vvvv) ;;
  configurazione) args=( --match-contract '^NoisyFindingsTest$' --match-test '^(test_Confirmed_UninitializedOracleMakesReadPathUnusable)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
