# Esercizi — Lezione 6

Prima del codice costruisci una permission matrix: righe per operazioni, colonne per attori. Ogni
cella deve diventare un test positivo o negativo motivato.

## Percorso base

1. Aggiungi `confirmDelivery()` con test buyer, seller e stranger.
2. Verifica che una call non autorizzata lasci lo stato invariato.
3. Completa l'audit del contratto `BrokenAdmin` mostrato nel testo.

## Percorso intermedio

1. Estendi l'ownership a due fasi con annullamento della proposta.
2. Aggiungi `FEE_MANAGER_ROLE` senza ampliare i suoi privilegi.
3. Collega `paused` a una vera funzione operativa e testa che la pausa sia applicata.

## Percorso avanzato

1. Disegna il permission graph includendo chi può concedere ogni ruolo.
2. Analizza il blast radius di admin, pauser e arbiter compromessi separatamente.
3. Sostituisci consapevolmente le primitive didattiche con una versione OpenZeppelin pinnata e
   confronta API, errori, eventi e assunzioni della supply chain.

La traccia `AccessControlExercises.t.sol` rimane fuori dalla suite predefinita.

