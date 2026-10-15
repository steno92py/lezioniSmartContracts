#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  esatta  Preparare un esperimento indipendente
  importi  Provare entrambi i lati della fee
  doppia  Bloccare la ripetizione
  indipendenza  Verificare indipendenza ed eventi
  tesoreria  Aggiungere un’uscita con prove dedicate
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  esatta) args=( --match-contract '^FixedFeeRegistryTest$' --match-test '^(test_InitialState|test_Register_SucceedsWithExactFee)\(' -vvvv) ;;
  importi) args=( --match-contract '^FixedFeeRegistryTest$' --match-test '^(test_RevertWhen_FeeIsZero|test_RevertWhen_FeeIsTooLow|test_RevertWhen_FeeIsTooHigh)\(' -vvvv) ;;
  doppia) args=( --match-contract '^FixedFeeRegistryTest$' --match-test '^(test_RevertWhen_AccountRegistersTwice)\(' -vvvv) ;;
  indipendenza) args=( --match-contract '^FixedFeeRegistryTest$' --match-test '^(test_Register_TwoDifferentAccountsRemainIndependent|test_Register_EmitsRegisteredEvent)\(' -vvvv) ;;
  tesoreria) args=( --match-contract '^FixedFeeRegistryFixedTest$' --match-test '^(test_TreasuryWithdrawsFees|test_RevertWhenCallerIsNotTreasury|test_RevertOnSecondWithdraw)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
