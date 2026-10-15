#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  pagamento  Vedere il codice del destinatario
  dispatch  Leggere calldata e dispatch
  rifiuto  Ripristinare lo stato se il pagamento fallisce
  falso-successo  Dimostrare una release falsa
  saldo  Separare saldo e importo dovuto
  sequenza  Proteggere caller e ripetizioni
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  pagamento) args=( --match-contract '^EscrowWithPayoutTest$' --match-test '^(test_ReleasePaysEOASeller|test_ReleaseToContractExecutesReceiverCode)\(' -vvvv) ;;
  dispatch) args=( --match-contract '^EscrowWithPayoutTest$' --match-test '^(test_EmptyCalldataWithZeroValueStillReachesReceive|test_UnknownSelectorIsRejected|test_PlainEtherTransferIsRejected)\(' -vvvv) ;;
  rifiuto) args=( --match-contract '^EscrowWithPayoutTest$' --match-test '^(test_RejectingSellerMakesReleaseRevertAtomically)\(' -vvvv) ;;
  falso-successo) args=( --match-contract '^UncheckedCallEscrowTest$' --match-test '^(test_DemonstratesFalseReleasedStateAfterFailedPayout)\(' -vvvv) ;;
  saldo) args=( --match-contract '^EscrowWithPayoutTest$' --match-test '^(test_ForcedEtherBypassesReceive|test_ForcedEtherDoesNotIncreaseSellerEntitlement)\(' -vvvv) ;;
  sequenza) args=( --match-contract '^EscrowWithPayoutTest$' --match-test '^(test_RevertWhen_OutsiderReleases|test_RevertWhen_ReleasingBeforeFunding|test_RevertWhen_ReleasingTwice)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
