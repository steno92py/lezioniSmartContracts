# Esercizi — Lezione 9

Scrivi le unità prima della formula: asset base, asset quote, decimals dell'importo, decimals del
prezzo e decimals desiderati in uscita.

## Percorso base

1. Deriva la conversione per input a 8, feed a 18 e output a 6 decimals.
2. Testa prezzo zero, negativo, futuro, scaduto e al limite esatto di freshness.
3. Testa `deadline - 1`, `deadline` e `deadline + 1`.

## Percorso intermedio

1. Aggiungi un circuit breaker con `minPrice` e `maxPrice`.
2. Scrivi un fuzz test sull'età del dato usando `bound()`.
3. Calcola `amountOutMin` per tolleranze dello 0,5%, 1% e 5%.

## Percorso avanzato

1. Definisci la policy quando oracle primario e secondario divergono.
2. Confronta spot, TWAP e freshness come proprietà indipendenti.
3. Analizza chi determina `minOut` e quanto danno economico autorizza quella scelta.

La traccia `OracleAndSlippageExercises.t.sol` resta fuori dalla suite predefinita.

