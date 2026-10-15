#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  deposito  Leggere gli input della chiamata
  evento  Distinguere memoria storage e log
  confini  Rendere espliciti i limiti
  rollback  Osservare il rollback
  identita  Seguire l’identità fra due contratti
  prelievo  Separare credito e prelievo
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  deposito) args=( --match-contract '^EscrowLesson1Test$' --match-test '^(test_RecordBindsSenderValueAndCalldataToStorage)\(' -vvvv) ;;
  evento) args=( --match-contract '^EscrowLesson1Test$' --match-test '^(test_EmitsDepositRecorded)\(' -vvvv) ;;
  confini) args=( --match-contract '^EscrowLesson1Test$' --match-test '^(test_AcceptsNoteAtExactBoundary|test_RevertWhenNoteIsTooLong|test_RevertWhenValueIsZero)\(' -vvvv) ;;
  rollback) args=( --match-contract '^EscrowLesson1Test$' --match-test '^(test_RevertRollsBackStateAndIncomingValue|test_RevertWhenReadingUnknownDeposit)\(' -vvvv) ;;
  identita) args=( --match-contract '^OriginAuthToyTest$' --match-test '^(test_Vulnerable_TxOriginAcceptsIntermediaryCall|test_Fixed_MsgSenderRejectsIntermediaryCall|test_Fixed_OwnerCanCallDirectly)\(' -vvvv) ;;
  prelievo) args=( --match-contract '^EscrowLesson1FixedTest$' --match-test '^(test_BeneficiaryWithdrawsCredit|test_RevertWhenPayerTriesToWithdraw|test_RevertWhenRecipientRejectsEther)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
