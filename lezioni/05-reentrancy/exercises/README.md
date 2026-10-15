# Esercizi — Lezione 5

Lavora soltanto contro i contratti giocattolo locali. Prima di scrivere un receiver, formula la
proprietà economica che vuoi falsificare o proteggere.

## Percorso base

1. Ricostruisci tre frame della trace reentrant su carta.
2. Segna il valore del credito prima, durante e dopo ogni callback.
3. Confronta un secondo withdrawal sequenziale con uno annidato nella stessa transaction.

## Percorso intermedio

1. Crea un receiver che rifiuta il payout e verifica il rollback CEI.
2. Aggiungi `moveCredit()` e studia una cross-function reentrancy locale.
3. Scrivi il regression test minimo usando `assets >= liabilities`.

## Percorso avanzato

1. Definisci lo scope corretto del lock quando due entry point condividono accounting.
2. Trasforma lo scenario in un fuzz test con credito, liquidità e callback bounded.
3. Compila il threat model completo della variante guarded senza assumere che il modifier risolva
   autorizzazione, accounting o dipendenze esterne.

La traccia `ReentrancyExercises.t.sol` rimane fuori dalla suite predefinita.

