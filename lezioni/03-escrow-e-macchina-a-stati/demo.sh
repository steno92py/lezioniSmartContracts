#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  funding  Disegnare la transizione iniziale
  sequenza  Separare ruolo e momento
  salto  Riprodurre una freccia vietata
  terminali  Proteggere terminalità e ripetizioni
  autorizzazione  Rifiutare caller e importi senza effetti
  payout  Distinguere approvazione e payout
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  funding) args=( --match-contract '^EscrowStateMachineTest$' --match-test '^(test_BuyerCanFundExactPrice|test_BuyerCanCancelBeforeFunding)\(' -vvvv) ;;
  sequenza) args=( --match-contract '^EscrowStateMachineTest$' --match-test '^(test_BuyerCanApproveAfterFunding|test_RevertWhen_ApproveHappensBeforeFunding)\(' -vvvv) ;;
  salto) args=( --match-contract '^BadEscrowStateMachineTest$' --match-test '^(test_DemonstratesInvalidCreatedToReleaseApprovedTransition)\(' -vvvv) ;;
  terminali) args=( --match-contract '^EscrowStateMachineTest$' --match-test '^(test_CancelledStateIsTerminalForFunding|test_ReleaseApprovedStateIsTerminalForApprove|test_RevertWhen_FundingTwice)\(' -vvvv) ;;
  autorizzazione) args=( --match-contract '^EscrowStateMachineTest$' --match-test '^(test_RevertWhen_OutsiderFunds|test_RevertWhen_SellerApprovesRelease|test_RevertedFundingLeavesNoPartialEffects)\(' -vvvv) ;;
  payout) args=( --match-contract '^EscrowStateMachineFixedTest$' --match-test '^(test_SellerReleasesAfterApproval|test_RevertWhen_ReleaseBeforeApproval|test_RevertWhen_SellerRejectsEther)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
