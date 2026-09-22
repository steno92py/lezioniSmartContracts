# Lezione 4 — Ether, receive, fallback, chiamate esterne e CEI

Questa lezione evolve la macchina a stati precedente introducendo una vera trust boundary:
l'Escrow paga il seller tramite una low-level call controllata e applica
Checks-Effects-Interactions.

> Ambiente esclusivamente locale. I contratti e `SELFDESTRUCT` sono strumenti didattici: non usare
> fondi o chiavi reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_04_Ether_receive_fallback_chiamate_esterne_CEI.md`](../../lezioni%20SmartContracts/Lezione_04_Ether_receive_fallback_chiamate_esterne_CEI.md).

## Evoluzione dello stato

```text
Created --fund(price)--> Funded --release() + payout--> Released
   |
   +--cancelBeforeFunding()---------------------------> Cancelled
```

La funzione `release()` segue:

```text
CHECKS                      buyer + stato Funded
   |
EFFECTS                     state = Released + emit Released
   |
INTERACTION                 seller.call{value: price}("")
   |
ENFORCE FAILURE             se success == false, revert e rollback
```

L'evento è emesso prima della trust boundary per mantenere ordinati anche i log rispetto a quelli
del receiver. Se il payout fallisce, il revert annulla sia lo stato sia il log.

CEI riduce la finestra di stato incoerente, ma non rende automaticamente corretta una call esterna:
il risultato deve comunque essere interpretato secondo la specifica.

## Prima esecuzione

Dalla directory della lezione:

```bash
forge build
forge test -vv
```

Dalla radice:

```bash
forge build --root lessons/04-ether-receive-fallback-chiamate-esterne-cei
forge test --root lessons/04-ether-receive-fallback-chiamate-esterne-cei -vv
```

Il compilatore segnala intenzionalmente `SELFDESTRUCT` come deprecato: compare soltanto nel test
helper che dimostra come il raw balance possa aumentare senza eseguire `receive()`.
Il lint segnala inoltre l'evento emesso dopo la call nel solo `UncheckedCallEscrow`: anche questo
warning appartiene al contratto volutamente difettoso, non alla versione corretta.

## Mappa dei file

```text
src/EscrowWithPayout.sol             Escrow corretto con payout CEI
src/labs/UncheckedCallEscrow.sol     risultato della call volutamente ignorato
test/helpers/EtherReceivers.sol      receiver accettante, rifiutante e ForceEther
test/EscrowWithPayout.t.sol          dispatch, payout, rollback ed Ether inatteso
test/UncheckedCallEscrow.t.sol       riproduzione dello stato Released falso
script/DeployEscrowWithPayout.s.sol  deploy locale facoltativo
exercises/                           attività graduate escluse dalla suite
```

## I quattro esperimenti centrali

### 1. Il destinatario esegue codice

```bash
forge test --match-test test_ReleaseToContractExecutesReceiverCode -vvvv
```

La trace contiene `EscrowWithPayout::release()` → `AcceptingSeller::receive()` e quest'ultimo
aggiorna il proprio storage.

### 2. Il payout rifiutato viene rollbackato

```bash
forge test --match-test test_RejectingSellerMakesReleaseRevertAtomically -vvvv
```

Dopo il revert lo stato è ancora `Funded`, l'Escrow conserva `price` e il receiver non riceve ETH.

### 3. Receive e fallback sono entry point distinti

La calldata vuota seleziona `receive()` anche con zero wei. Un selector sconosciuto seleziona
`fallback()`. Entrambi vengono rifiutati perché non appartengono all'API economica dell'Escrow.

### 4. Raw balance non significa diritto economico

`ForceEther` aggiunge un surplus senza chiamare il recipient. La release paga soltanto `price`, non
`address(this).balance`, e lascia il surplus nel contratto giocattolo.

## Laboratorio vulnerabile

```bash
forge test --match-contract UncheckedCallEscrowTest -vvvv
```

Il test passa dimostrando il difetto: il receiver rifiuta ETH, ma la transaction non reverte,
`state == Released` e i fondi restano bloccati. CEI è presente; manca l'enforcement del risultato.

## Tre percorsi

### Base — capire l'ingresso e l'uscita di Ether

1. Distingui `msg.value`, balance dell'utente e `address(this).balance`.
2. Verifica il dispatch con calldata vuota e selector sconosciuto.
3. Segui una call riuscita e una fallita nelle trace.

### Intermedio — ragionare sull'atomicità

1. Identifica Checks, Effects e Interaction in `release()`.
2. Verifica stato e balance dopo il payout rifiutato.
3. Confronta obligation `price` e surplus nel raw balance.

### Avanzato — auditare la trust boundary

1. Evidenzia ogni punto che può eseguire codice esterno.
2. Chiediti quali callback sono possibili durante il payout.
3. Ridisegna il flusso come pull payment e confronta failure e liveness.

## Deploy facoltativo su Anvil

Con `anvil` già avviato e usando esclusivamente una sua chiave di test:

```bash
forge script script/DeployEscrowWithPayout.s.sol:DeployEscrowWithPayout \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

Il deploy usa `address(0xB0B)` e `5 ether` come parametri didattici.

## Criterio di completamento

- sai spiegare perché una call con ETH può eseguire codice;
- sai distinguere `receive()` da `fallback()`;
- sai spiegare perché `success == true` è solo successo EVM;
- sai ricostruire il rollback di un payout rifiutato;
- sai distinguere raw balance e protocol accounting;
- sai mostrare perché CEI non basta se il risultato della call viene ignorato.
