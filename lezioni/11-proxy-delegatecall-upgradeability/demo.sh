#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  contesto  Separare codice e contesto
  collisione  Vedere la collisione nello storage
  inizializzazione  Inizializzare il proxy senza finestre aperte
  autorita  Proteggere il potere di upgrade
  upgrade  Conservare lo stato e rendere atomica la migrazione
  layout-errato  Distinguere slot standard e layout compatibile
  layout  layout V1, V2 e versione incompatibile
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  contesto) args=( --match-contract '^DelegatecallContextTest$' --match-test '^(test_DelegatecallUsesLogicCodeWithProxyContext)\(' -vvvv) ;;
  collisione) args=( --match-contract '^SimpleProxyTest$' --match-test '^(test_Vulnerable_ApplicationWriteCorruptsImplementationSlot|test_Vulnerable_StrangerCanUpgrade)\(' -vvvv) ;;
  inizializzazione) args=( --match-contract '^UpgradeableEscrowTest$' --match-test '^(test_Vulnerable_UninitializedProxyCanBeClaimedByStranger|test_DeploymentAtomicallyInitializesProxyStorage|test_ImplementationInstanceIsLocked|test_RevertWhen_ProxyInitializeRunsTwice)\(' -vvvv) ;;
  autorita) args=( --match-contract '^UpgradeableEscrowTest$' --match-test '^(test_RevertWhen_StrangerAttemptsUpgrade|test_RevertWhen_UpgradeIsCalledDirectlyOnImplementation|test_RevertWhen_NewImplementationIsNotUUPSCompatible|test_RevertWhen_ProxiableUUIDUsesWrongSlot)\(' -vvvv) ;;
  upgrade) args=( --match-contract '^UpgradeableEscrowTest$' --match-test '^(test_AuthorizedUpgradePreservesStateAndRunsMigration|test_FailedMigrationRollsBackImplementationUpgrade|test_RevertWhen_V2InitializerRunsTwice)\(' -vvvv) ;;
  layout-errato) args=( --match-contract '^UpgradeableEscrowTest$' --match-test '^(test_Vulnerable_IncompatibleLayoutReinterpretsExistingState|test_PostUpgradeBusinessAuthorizationStillWorks)\(' -vvvv) ;;
  layout)
    for contract in UpgradeableEscrowV1 UpgradeableEscrowV2 UnsafeLayoutV2; do
      printf "\n%s\n" "$contract"
      forge inspect --root "$lesson_dir" --offline "$contract" storageLayout
    done
    exit 0 ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
