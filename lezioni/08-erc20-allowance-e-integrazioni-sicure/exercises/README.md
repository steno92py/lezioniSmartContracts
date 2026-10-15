# Esercizi — Lezione 8

Prima di scrivere codice, rappresenta separatamente saldo, allowance e credito interno. Sono tre
valori diversi, conservati da contratti diversi e modificati da caller diversi.

## Percorso base

1. Disegna `balanceOf(buyer)`, `balanceOf(escrow)` e `allowance(buyer, escrow)` nei tre passaggi.
2. Testa allowance assente, insufficiente ed esatta con errori specifici.
3. Verifica che `approve` non muova alcun token.

## Percorso intermedio

1. Introduci la mutazione `escrowedAmount = requestedAmount` e osserva il test fee-on-transfer.
2. Crea un token che reverte invece di restituire `false`.
3. Implementa una policy alternativa che rifiuti ogni deposito con `received != requested`.

## Percorso avanzato

1. Scrivi una policy esplicita per fee, rebase, proxy upgradeabili e zero transfer.
2. Ragiona su come un rebase potrebbe rompere `balance >= escrowedAmount` dopo il deposito.
3. Disegna il threat model di `permit`: firma, nonce, deadline, domain separator e replay.

La traccia `TokenIntegrationExercises.t.sol` resta fuori dalla suite predefinita.

