#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  dominio  Definire il dominio del fuzzing
  confini  Conservare i confini deterministici
  vault  Confrontare saldo credito e memoria del test
  stato-terminale  Ricordare che uno stato era terminale
  regressione  Trasformare una sequenza in regressione
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  dominio) args=( --match-contract '^FeeMathFuzzTest$' --match-test '^(testFuzz_FeeNeverExceedsAmount|testFuzz_FeeIsMonotonicInAmount)\(' -vvvv) ;;
  confini) args=( --match-contract '^OracleFuzzTest$' --match-test '^(test_Regression_ExactFreshnessBoundaryIsAccepted|test_Regression_FutureTimestampIsRejected|test_Regression_ZeroPriceIsRejected)\(' -vvvv) ;;
  vault) args=( --match-contract '^CreditVaultInvariantTest$' -vv) ;;
  stato-terminale) args=( --match-contract '^LifecycleInvariantTest$' -vv) ;;
  regressione) args=( --match-contract '^InvariantDiscoveryRegressionTest$' --match-test '^(test_Regression_MinimalSequencePreservesAccounting|test_Regression_OverWithdrawalPreservesAllAccounting)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
