#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  pausa  Applicare il ruolo dichiarato
  partecipanti  Separare partecipazione e amministrazione
  identita  Controllare il chiamante immediato
  ruoli  Separare ruoli operativi
  assegnazioni  Verificare concessione e revoca
  ownership  Trasferire ownership con accettazione
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  pausa) args=( --match-contract '^AccessControlTest$' --match-test '^(test_Vulnerable_StrangerCanPause|test_RevertWhen_StrangerTriesToPause|test_AdminCanPauseAndUnpause)\(' -vvvv) ;;
  partecipanti) args=( --match-contract '^AccessControlTest$' --match-test '^(test_BuyerIsNotImplicitlyAdmin|test_SellerIsNotImplicitlyAdmin)\(' -vvvv) ;;
  identita) args=( --match-contract '^TxOriginVaultTest$' --match-test '^(test_Vulnerable_TxOriginAllowsIndirectCall|test_Fixed_MsgSenderRejectsIndirectCall|test_Fixed_OwnerCanCallDirectly)\(' -vvvv) ;;
  ruoli) args=( --match-contract '^EscrowRolesTest$' --match-test '^(test_PauserCanPauseButCannotResolveDispute|test_ArbiterCanResolveButCannotPause|test_AdminDoesNotImplicitlyHaveOperationalRoles)\(' -vvvv) ;;
  assegnazioni) args=( --match-contract '^EscrowRolesTest$' --match-test '^(test_AdminCanGrantAndRevokeRole|test_RevertWhen_NonAdminGrantsRole)\(' -vvvv) ;;
  ownership) args=( --match-contract '^Ownable2StepLiteTest$' --match-test '^(test_TransferDoesNotChangeOwnerBeforeAcceptance|test_OnlyPendingOwnerCanAccept|test_AcceptanceMovesPrivilegeAndClearsPendingOwner)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
