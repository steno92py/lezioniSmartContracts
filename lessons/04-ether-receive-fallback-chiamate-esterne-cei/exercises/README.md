# Esercizi — Lezione 4

Questa unità introduce una trust boundary reale. Prima di ogni prova, segna la riga esatta in cui
il controllo lascia l'Escrow e scrivi quali invarianti devono essere già veri.

## Percorso base

1. Costruisci il `DispatchProbe` e verifica la matrice `foo` / `receive` / `fallback`.
2. Confronta una funzione payable e una nonpayable.
3. Segui con `-vvvv` il payout verso `AcceptingSeller.receive()`.

## Percorso intermedio

1. Implementa un receiver che rifiuta ETH con custom error.
2. Forza `13 ether` nel contratto e verifica che l'obbligazione resti `5 ether`.
3. Spiega perché inviare `address(this).balance` confonde raw balance e accounting.

## Percorso avanzato

1. Analizza ordering, amount, trust boundary e test mancanti nella variante difettosa proposta.
2. Disegna un modello pull-payment con `claimable` e `withdraw`.
3. Elenca le funzioni richiamabili dal seller durante il payout: prepara la threat analysis della
   Lezione 5 senza ancora implementare un attacco reentrante.

La traccia iniziale è in `EtherAndCallsExercises.t.sol` e resta fuori dalla suite predefinita.

