#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  accounting  Dimostrare il debito senza copertura
  payout  Seguire falso payout e dati scaduti
  policy  Motivare privilegi e osservabilità
  retest  Verificare fix e confini senza cambiare i requisiti
  verifica-finale  Chiudere modello governance e report
  invariant  campagna stateful finale
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  accounting) args=( --match-contract '^TargetFindingsTest$' --match-test '^(test_F01_NominalAccountingExceedsReceivedAssets)\(' -vvvv) ;;
  payout) args=( --match-contract '^TargetFindingsTest$' --match-test '^(test_F03_FalseReturnCreatesFalseTerminalSuccess|test_F02_StaleOracleStillAllowsRelease)\(' -vvvv) ;;
  policy) args=( --match-contract '^TargetFindingsTest$' --match-test '^(test_F04_StrangerCanReplaceOracle|test_F05_NotifierFailureIsSilentButSettlementContinues)\(' -vvvv) ;;
  retest) args=( --match-contract '^FixedRegressionTest$' --match-test '^(test_F01_DepositUsesActualReceived|test_F02_ExactMaxAgeAccepted|test_F03_FalseReturnTransferCannotFinalize|test_F04_StrangerCannotReplaceOracle|test_F05_NotifierFailureDoesNotBlockReleaseAndIsObservable|test_RefundRemainsAvailableWhilePaused)\(' -vvvv) ;;
  verifica-finale) args=( --match-test '^(testFuzz_DepositTracksActualStandardTokenBalance|testFuzz_FeeBoundary|testFuzz_OracleFreshnessBoundary|testFuzz_UnauthorizedAccountCannotSetOracle|test_ProposerCannotDirectlyChangeOracle|test_TimelockCannotExecuteBeforeDelay|test_TimelockExecutesOracleChangeAfterDelay)\(' -vv) ;;
  invariant) args=( --match-contract '^FinalInvariantTest$' -vv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
