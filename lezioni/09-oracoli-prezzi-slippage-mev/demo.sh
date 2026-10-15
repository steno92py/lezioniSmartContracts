#!/usr/bin/env bash
# Demo locali del corso. Invocare con bash.
set -euo pipefail
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
  help|--help|-h)
    cat <<'HELP'
Uso: bash demo.sh <demo>
  check  suite completa
  vulnerabile  Riconoscere un numero senza contesto
  dato  Validare segno e timestamp
  scala  Derivare la scala prima del codice
  slippage  Esprimere il risultato minimo accettabile
  deadline  Definire la scadenza dell’intento
  ordine  Confrontare lo stesso cambiamento di rate
Demo offline: preparare compilatore e dipendenze con forge build prima della lezione.
HELP
    exit 0 ;;
  check) args=(-vv) ;;
  vulnerabile) args=( --match-contract '^PriceConsumerTest$' --match-test '^(test_Vulnerable_StalePriceIsStillAccepted|test_Vulnerable_RawMultiplicationHasWrongUnits)\(' -vvvv) ;;
  dato) args=( --match-contract '^PriceConsumerTest$' --match-test '^(test_ReadFreshPositivePrice|test_RevertWhen_PriceIsNegative|test_RevertWhen_TimestampIsInFuture|test_RevertWhen_PriceIsStale|test_ExactlyMaxAgeIsAccepted)\(' -vvvv) ;;
  scala) args=( --match-contract '^PriceConsumerTest$' --match-test '^(test_QuoteOneBaseAssetIntoSixDecimalQuote|test_EightAndEighteenDecimalFeedsGiveSameEconomicQuote|test_MulDivHandlesOverflowingIntermediateProduct)\(' -vvvv) ;;
  slippage) args=( --match-contract '^SwapIntentTest$' --match-test '^(test_SwapWithinBounds|test_ExactMinimumOutputIsAccepted|test_RevertWhen_RateFallsBelowMinimum)\(' -vvvv) ;;
  deadline) args=( --match-contract '^SwapIntentTest$' --match-test '^(test_DeadlineMinusOneIsAccepted|test_ExactDeadlineIsAccepted|test_RevertWhen_DeadlineHasPassed)\(' -vvvv) ;;
  ordine) args=( --match-contract '^SwapIntentTest$' --match-test '^(test_Vulnerable_AcceptsNearZeroOutputAfterRateChange|test_SafeIntentRejectsSameAdverseOrderingScenario)\(' -vvvv) ;;
  *) printf "Demo sconosciuta. Usa: bash demo.sh help\n" >&2; exit 2 ;;
esac
command -v forge >/dev/null 2>&1 || { printf "Forge non disponibile nel PATH. Usa il percorso su carta della guida.\n" >&2; exit 127; }
exec forge test --root "$lesson_dir" --offline "${args[@]}"
