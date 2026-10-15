# Esercizi — Lezione 7

Disegna prima il grafo degli stati. Ogni arco deve dichiarare stato iniziale, azione, caller,
condizioni e stato finale; ogni arco assente deve corrispondere ad almeno un test negativo.

## Percorso base

1. Ricostruisci a mano le due sequenze terminali di `SafeEscrow`.
2. Aggiungi un test per il secondo deposito e uno per il completamento anticipato.
3. Spiega perché `complete()` vulnerabile non ha bisogno di reentrancy per creare credito.

## Percorso intermedio

1. Aggiungi lo stato `Disputed`, raggiungibile da `Funded` per buyer e seller.
2. Introduci un arbiter che possa risolvere la disputa una sola volta.
3. Verifica che `Completed` e `Cancelled` restino terminali dopo l'estensione.

## Percorso avanzato

1. Verifica `buyerCredit + sellerCredit <= depositedAmount` su almeno tre sequenze.
2. Esegui il mutation test rimuovendo la guardia di `complete()` e annota i test rossi.
3. Riprogetta `funded`, `completed`, `cancelled` e `disputed` evitando combinazioni impossibili.

La traccia `StateMachineExercises.t.sol` resta fuori dalla suite predefinita.

