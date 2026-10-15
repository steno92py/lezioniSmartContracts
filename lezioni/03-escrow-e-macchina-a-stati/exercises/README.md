# Esercizi — Lezione 3

Prima di modificare il contratto, disegna sempre il grafo e aggiorna la matrice delle transizioni.
Le soluzioni non sono incluse nella suite distribuita.

## Percorso base

1. Completa a mano tutte le dodici celle della matrice stato × funzione.
2. Collega ogni test esistente a una freccia valida o proibita.
3. Aggiungi il test in cui un outsider prova a cancellare l'Escrow.

## Percorso intermedio

1. Dimostra che `Cancelled` è terminale anche rispetto ad `approveRelease()`.
2. Verifica l'intero payload di `WrongValue(expected, actual)`.
3. Rimuovi una guardia da `fund()` e identifica le lacune della suite.

## Percorso avanzato

1. Introduci su carta uno stato `Accepted` e il ruolo attivo del seller.
2. Formula e testa la proprietà storica di `ReleaseApproved`.
3. Aggiungi al threat model un arbitro, i suoi poteri e i possibili abusi.

La traccia iniziale è in `EscrowStateMachineExercises.t.sol`. Copiala sotto `test/` soltanto
quando inizi a implementare gli esercizi.

