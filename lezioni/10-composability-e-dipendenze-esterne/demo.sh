#!/usr/bin/env bash
# Demo locali della lezione 10. Eseguire con bash; non serve Anvil.
set -euo pipefail

lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_name="${1:-help}"

case "$demo_name" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check           tutta la suite, 33 test
  notifica        revert accessorio osservabile, 1 test
  falso-successo  call fallita o target senza codice, 2 test
  correzione      bubbling e rifiuto del target senza codice, 2 test
  router          output sotto il minimo e revert propagato, 2 test
  cache           provider guasto e scadenza della cache, 3 test
  allowlist       target non ammesso e target ammesso che fallisce, 2 test
Le demo usano solo mock locali e la compilazione offline.
Prima della lezione eseguire forge build nella cartella della lezione.
HELP
    exit 0
    ;;
  check)
    args=(-vv)
    ;;
  notifica)
    args=(--match-contract '^NotificationEscrowTest$' --match-test '^test_NotifierFailureIsObservableButDoesNotBlockRelease\(\)$' -vvvv)
    ;;
  falso-successo)
    args=(--match-contract '^LowLevelCallsTest$' --match-test '^test_Vulnerable_(RevertCreatesFalseSuccess|NoCodeStillCreatesFalseSuccess)\(\)$' -vvvv)
    ;;
  correzione)
    args=(--match-contract '^LowLevelCallsTest$' --match-test '^test_CheckedCall(BubblesRevertAndKeepsState|RejectsTargetWithoutCode)\(\)$' -vvvv)
    ;;
  router)
    args=(--match-contract '^BoundedIntegratorTest$' --match-test '^test_(RevertWhen_ABICompatibleRouterReturnsTooLittle|RouterRevertPropagatesAndStateDoesNotChange)\(\)$' -vvvv)
    ;;
  cache)
    args=(--match-contract '^DependencyConsumerTest$' --match-test '^test_(DependencyCanBecomeUnavailableWithoutCorruptingCache|ExactlyMaximumCacheAgeIsAccepted|RevertWhen_CacheIsStale)\(\)$' -vvvv)
    ;;
  allowlist)
    args=(--match-contract '^AllowlistedExecutorTest$' --match-test '^test_(RevertWhen_TargetIsNotAllowed|RevertingAllowedDependencyDoesNotIncrementCounter)\(\)$' -vvvv)
    ;;
  *)
    printf 'Demo sconosciuta: %s. Usa: bash demo.sh help\n' "$demo_name" >&2
    exit 2
    ;;
esac

if ! command -v forge >/dev/null 2>&1; then
  printf 'Forge non disponibile nel PATH. Usa il percorso su carta nel copione.\n' >&2
  exit 127
fi

exec forge test --root "$lesson_dir" --offline "${args[@]}"
