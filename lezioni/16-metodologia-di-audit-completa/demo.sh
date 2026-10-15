#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  baseline  Scrivere proprietà e verificare la baseline
  poc  Riprodurre causa e conseguenza
  policy  Valutare governance freshness e liveness
  retest  Ritestare senza cancellare la prova originale
  invariant  Concludere con evidenze e limitazioni
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  baseline) args=( --match-contract '^AuditEscrowFindingsTest$' --match-test '^(test_Baseline_HappyPathWorks)\(' -vvvv) ;;
  poc) args=( --match-contract '^AuditEscrowFindingsTest$' --match-test '^(test_AUD01_ReentrantTokenPaysSameLiabilityTwice|test_AUD02_FeeTokenCreatesInsolventNominalLiability)\(' -vvvv) ;;
  policy) args=( --match-contract '^AuditEscrowFindingsTest$' --match-test '^(test_AUD03_GuardianCanBypassGovernanceAndForceSettlement|test_AUD04_ExactStalenessBoundaryIsAccepted|test_OBS01_RevertingOptionalNotifierBlocksSettlement)\(' -vvvv) ;;
  retest) args=( --match-contract '^RemediationRetestTest$' --match-test '^(test_Regression_AUD01_ReentrantCallbackCannotPayTwice|test_Regression_AUD02_FeeTokenRejectedAtomically|test_Regression_AUD03_GuardianCannotSetOracle|test_Regression_AUD04_ExactStalenessBoundaryRejected|test_Regression_OBS01_NotifierFailureDoesNotBlockSettlement)\(' -vvvv) ;;
  invariant) args=( --match-contract '^RemediatedInvariantTest$' -vv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
