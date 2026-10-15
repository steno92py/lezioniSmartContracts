#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  deposito  Partire dal requisito
  errore  Rifiutare per la ragione corretta
  confini  Testare i confini e gli eventi
  integrazione  Usare mock coerenti con la domanda
  regressione  Conservare il bug come regressione
  workflow  Leggere copertura e limiti
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  deposito) args=( --match-contract '^DepositTest$' --match-test '^(test_BuyerCanDepositAndStateDeltaIsCorrect)\(' -vvvv) ;;
  errore) args=( --match-contract '^DepositTest$' --match-test '^(test_StrangerCannotDepositAndStateIsUnchanged|test_PreconditionOrderChecksCallerBeforeAmount)\(' -vvvv) ;;
  confini) args=( --match-contract '^AdministrationTest$' --match-test '^(test_FeeBoundary999Succeeds|test_FeeBoundary1000Succeeds|test_FeeBoundary1001RevertsAndPreservesOldFee|test_OwnerUpdatesFeeWithEventAndState)\(' -vvvv) ;;
  integrazione) args=( --match-contract '^OracleIntegrationTest$' --match-test '^(test_MockCallCanIsolateOracleReturnValue|test_RevertingDependencyPropagatesAndPreservesState|test_PriceExactlyAtFreshnessBoundaryIsAccepted|test_PriceOneSecondPastFreshnessBoundaryIsRejected)\(' -vvvv) ;;
  regressione) args=( --match-test '^(test_Regression_FeeOnTransferCannotCreateUnbackedLiability|test_Regression_FailedPayoutRollsBackTerminalState|test_Regression_ReentrantCallbackCannotWithdrawTwice)\(' -vvvv) ;;
  workflow) args=( --match-contract '^WorkflowIntegrationTest$' --match-test '^(test_FullDepositAndReleaseWorkflowPreservesEconomicAccounting|test_EachTestStartsFromSetUpState)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
