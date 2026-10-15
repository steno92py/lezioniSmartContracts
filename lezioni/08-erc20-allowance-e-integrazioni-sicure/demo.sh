#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  allowance  Distinguere autorizzazione e movimento
  residuo  Osservare allowance residue e caller
  false-return  Rifiutare il successo contabile senza asset
  no-return  Gestire un token senza valore di ritorno
  netto  Accreditare la quantità realmente ricevuta
  payout  Annullare il terminale se il payout fallisce
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  allowance) args=( --match-contract '^AllowanceFlowTest$' --match-test '^(test_ApproveChangesAuthorizationButMovesNoTokens|test_TransferFromConsumesExactAllowance)\(' -vvvv) ;;
  residuo) args=( --match-test '^(test_LargerAllowancePersistsAfterPartialSpend|test_RevertWhen_StrangerHasTokensAndAllowance)\(' -vvvv) ;;
  false-return) args=( --match-contract '^TokenCompatibilityTest$' --match-test '^(test_Vulnerable_FalseReturnCreatesUnbackedCredit|test_SafeEscrowRejectsFalseReturnWithoutChangingState)\(' -vvvv) ;;
  no-return) args=( --match-contract '^TokenCompatibilityTest$' --match-test '^(test_SafeEscrowSupportsSuccessfulNoReturnToken)\(' -vvvv) ;;
  netto) args=( --match-contract '^TokenCompatibilityTest$' --match-test '^(test_FeeTokenAccountsForActualAmountReceived|test_FeeTokenPayoutPolicyLeavesSecondFeeToSeller)\(' -vvvv) ;;
  payout) args=( --match-contract '^TokenCompatibilityTest$' --match-test '^(test_FailedPayoutRollsBackEffectsAndState)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
