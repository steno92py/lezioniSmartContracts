# Esercizi — Lezione 12

Prima del codice disegna il governance graph. Ogni edge deve indicare potere, threshold, delay,
revocabilità e impatto della compromissione.

## Percorso base

1. Confronta owner singolo, 2-of-3 e 3-of-3 in termini di safety e liveness.
2. Testa threshold insufficiente, esatta e approvazione duplicata.
3. Testa timelock a `delay - 1`, `delay` e `delay + 1`.

## Percorso intermedio

1. Aggiungi revoca di una approval non ancora eseguita.
2. Modella fast-pause e slow-unpause mantenendo l'uscita disponibile.
3. Cerca tutti i write path verso oracle, fee, paused e implementation.

## Percorso avanzato

1. Progetta un timelock self-admin e analizza il deadlock dell'unico proposer.
2. Aggiungi una procedura di recovery con il minimo privilegio possibile.
3. Costruisci una blast-radius table per signer, quorum, pauser, admin e timelock.

La traccia `GovernanceExercises.t.sol` resta fuori dalla suite predefinita.

