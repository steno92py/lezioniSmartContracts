#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  trasferimento  Trasferire un potere in due fasi
  quorum  Contare approvazioni indipendenti
  tempo  Attendere il confine corretto
  cancellazione  Cancellare e gestire un tentativo fallito
  pausa  Fermare subito e riaprire con controllo
  flusso  Verificare la catena dei privilegi
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  trasferimento) args=( --match-contract '^OwnershipTwoStepTest$' --match-test '^(test_CandidateMustAcceptOwnership|test_CurrentOwnerRetainsAuthorityUntilAcceptance)\(' -vvvv) ;;
  quorum) args=( --match-contract '^ToyMultisigTest$' --match-test '^(test_RevertWhen_ThresholdIsNotReached|test_RevertWhen_OwnerApprovesTwice|test_TwoApprovalsExecuteTransaction)\(' -vvvv) ;;
  tempo) args=( --match-contract '^TimelockGovernanceTest$' --match-test '^(test_RevertWhen_ExecutingBeforeDelay|test_ExecuteExactlyAtDelayBoundary)\(' -vvvv) ;;
  cancellazione) args=( --match-contract '^TimelockGovernanceTest$' --match-test '^(test_CancelledOperationCannotExecute|test_UnderlyingFailureLeavesOperationReadyForReview)\(' -vvvv) ;;
  pausa) args=( --match-contract '^TimelockGovernanceTest$' --match-test '^(test_EmergencyPauserCanStopButCannotReconfigureOrRestart|test_PauseBlocksNewActionButPreservesExit)\(' -vvvv) ;;
  flusso) args=( --match-test '^(test_TwoSignersScheduleThenTimelockExecutesAfterDelay|test_ProposerCannotBypassTimelockOwnership)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
