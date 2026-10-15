#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  ripetizione  Ripetere un’azione autorizzata
  conflitto  Creare crediti incompatibili
  correzione  Chiudere la transizione nella stessa chiamata
  booleani  Evitare combinazioni contraddittorie
  payout  Riscuotere il credito una volta sola
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  ripetizione) args=( --match-contract '^LogicBugEscrowTest$' --match-test '^(test_Vulnerable_CompleteBeforeDepositIsAccepted|test_Vulnerable_CompleteCanCreateUnbackedCredit)\(' -vvvv) ;;
  conflitto) args=( --match-contract '^LogicBugEscrowTest$' --match-test '^(test_Vulnerable_CompleteAfterCancelCreatesConflictingCredits)\(' -vvvv) ;;
  correzione) args=( --match-contract '^SafeEscrowTest$' --match-test '^(test_CompleteMovesFundedToCompleted|test_CompletedIsTerminalForComplete|test_CompletedIsTerminalForCancel|test_CancelledIsTerminalForComplete)\(' -vvvv) ;;
  booleani) args=( --match-test '^(test_Vulnerable_AllMutuallyExclusiveFlagsCanBeTrue|test_FailedTransitionLeavesStateAndAccountingUnchanged)\(' -vvvv) ;;
  payout) args=( --match-contract '^SafeEscrowFixedTest$' --match-test '^(test_SellerWithdrawsAfterComplete|test_BuyerWithdrawsAfterCancel|test_RevertOnSecondWithdraw)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
