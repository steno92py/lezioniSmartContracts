# Esercizi — Lezione 14

Prima di aumentare `runs` o `depth`, scrivi la proprietà e il dominio su cui deve valere.

## Percorso base

1. Completa `FuzzExercises.t.sol` usando `bound` per amount e fee.
2. Usa `assume` soltanto per escludere buyer e address zero dal caller fuzzato.
3. Normalizza due amount scambiandoli invece di scartare tutte le coppie con `a > b`.
4. Mantieni test deterministici per zero, boundary esatto e bug storici.

## Percorso intermedio

1. Completa `InvariantExercises.t.sol` con solvibilità e somma dei tre actor.
2. Aggiungi ghost counter per capire quante azioni hanno avuto successo e quanti withdraw erano
   no-op.
3. Rimuovi temporaneamente `totalCredit -= amount`: l'invariante deve trovare un counterexample.
4. Trasforma la sequenza ridotta in un regression test, poi ripristina il contratto corretto.

## Percorso avanzato

1. Aggiungi una donation action e correggi l'invariante da `==` a `>=`, motivando il cambio.
2. Crea una suite separata per un token fee-on-transfer con balance-delta accounting.
3. Aggiungi un handler avversario che prova caller non autorizzati senza nascondere revert inattesi.
4. Confronta il rapporto no-op/success prima e dopo una modifica dell'handler.

Non aumentare indiscriminatamente le capability dell'handler: ogni capability modifica il threat
model e può rendere falsa una proprietà prima valida.

