# Esercizi — Lezione 11

Ogni upgrade va descritto come una migrazione di stato, non come semplice sostituzione di bytecode.
Prima del codice elenca layout iniziale, layout finale, authority e configurazione atomica richiesta.

## Percorso base

1. Compila la tabella `msg.sender`, `address(this)`, code e storage durante `delegatecall`.
2. Riproduci la collisione tra slot 0 del proxy fragile e slot 0 della logic.
3. Prevedi il packing di quattro variabili e verifica con `forge inspect`.

## Percorso intermedio

1. Aggiungi una variabile in coda alla V2 e verifica la conservazione V1.
2. Testa una migrazione V2 fallita e il rollback dell'implementation slot.
3. Rimuovi temporaneamente l'authorization e verifica che il test diventi rosso.

## Percorso avanzato

1. Installa in un progetto separato OpenZeppelin Foundry Upgrades e valida i tre layout.
2. Confronta il modello locale con UUPS e Transparent Proxy reali.
3. Progetta upgrade authority, multisig, timelock, monitoraggio e procedura d'emergenza.

La traccia `UpgradeExercises.t.sol` resta fuori dalla suite predefinita.

