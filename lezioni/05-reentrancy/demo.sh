#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  sequenziale  Distinguere ripetizione e rientro
  attacco  Seguire il callback e il danno
  cei  Consumare il credito prima della call
  guard  Aggiungere una guardia con un perimetro chiaro
  rifiuto  Conservare il diritto dopo un payout fallito
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  sequenziale) args=( --match-contract '^VulnerableVaultTest$' --match-test '^(test_NormalWithdrawWorks|test_RevertWhen_WithdrawnTwiceSequentially)\(' -vvvv) ;;
  attacco) args=( --match-contract '^VulnerableVaultTest$' --match-test '^(test_DemonstratesReentrantCallbackBreakingAccounting)\(' -vvvv) ;;
  cei) args=( --match-contract '^SafeVaultsTest$' --match-test '^(test_CEI_PreventsReuseOfCredit)\(' -vvvv) ;;
  guard) args=( --match-contract '^SafeVaultsTest$' --match-test '^(test_GuardAndCEI_BlockReentry)\(' -vvvv) ;;
  rifiuto) args=( --match-contract '^SafeVaultsTest$' --match-test '^(test_CEI_RestoresAccountingWhenReceiverRejectsPayout)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
