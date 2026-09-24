# Lezione 1 — Transazioni, account, calldata, storage e revert

Questo è un sottoprogetto Foundry autonomo e interamente locale. È pensato anche per chi non ha
mai programmato: puoi seguire il percorso base senza conoscere in anticipo Solidity. Chi ha già
esperienza può partire dai test negativi o dal laboratorio su `tx.origin`.

> I contratti sono giocattoli didattici, non software production-ready. Non usarli con fondi reali.

## Risultato della lezione

Alla fine saprai riconoscere:

- il chiamante diretto di una call (`msg.sender`);
- la quantità di ETH associata alla call (`msg.value`);
- gli input esterni read-only (`calldata`);
- lo stato persistente (`storage`);
- l'atomicità di una call che termina con `revert`;
- il motivo per cui `tx.origin` non è una scorciatoia per l'autorizzazione.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_01_Transazioni_Account_Calldata_Storage_Revert.md`](../../lezioni%20SmartContracts/Lezione_01_Transazioni_Account_Calldata_Storage_Revert.md).

## Prima esecuzione

Dalla directory di questo sottoprogetto:

```bash
forge build
forge test
```

Oppure, dalla radice della repository:

```bash
forge build --root lessons/01-transazioni-account-calldata-storage-revert
forge test --root lessons/01-transazioni-account-calldata-storage-revert -vv
```

Per osservare la catena di chiamate del laboratorio `tx.origin`:

```bash
forge test --match-path test/OriginAuthToy.t.sol -vvvv
```

Durante la build sono attesi due warning didattici: `EscrowLesson1` trattiene intenzionalmente
l'ETH perché le uscite arriveranno nelle lezioni successive, mentre `OriginAuthToy` usa
intenzionalmente `tx.origin` per rendere riproducibile il difetto. I test non trattano questi
warning come raccomandazioni di progetto.

Per confrontare, `src/fixed/EscrowLesson1Fixed.sol` è lo stesso contratto con in più `withdraw()`:
il beneficiario ritira il proprio credito e il warning `locked-ether` non compare più. Le aggiunte
sono segnate con `NOVITA'`; per vederle tutte insieme:

```bash
diff src/EscrowLesson1.sol src/fixed/EscrowLesson1Fixed.sol
```

## Mappa dei file

```text
src/EscrowLesson1.sol       contratto principale: input -> storage
src/fixed/EscrowLesson1Fixed.sol  stesso contratto con withdraw(): niente ETH bloccato
src/OriginAuthToy.sol       versione vulnerabile, fix e intermediario
test/EscrowLesson1.t.sol    happy path, boundary e atomicità dei revert
test/OriginAuthToy.t.sol    riproduzione locale e test di regressione
test/EscrowLesson1Fixed.t.sol  prelievo, doppio prelievo e destinatario che rifiuta l'ETH
script/DeployEscrowLesson1.s.sol  deploy locale facoltativo
exercises/                  tracce graduate, escluse dalla suite
```

## Modello mentale minimo

Una transazione può creare più call frame. Ogni frame vede il proprio `msg.sender`, `msg.value` e
`msg.data`. Se la call riesce, le scritture diventano persistenti; se reverte, gli effetti della
call vengono annullati.

```text
calldata + msg.sender + msg.value
              |
              v
       controlli semantici
          /          \
      successo       revert
         |              |
         v              v
   storage aggiornato   stato invariato
```

Nel contratto principale il chiamante può scegliere beneficiario, nota, valore, ordine e momento
della chiamata. Il contratto deve quindi proteggere queste proprietà:

1. beneficiario diverso dall'indirizzo zero;
2. valore maggiore di zero;
3. nota lunga al massimo 256 byte;
4. payer uguale al chiamante diretto;
5. ID e contabilità aggiornati esattamente una volta;
6. nessun effetto persistente dopo una call fallita.

## Tre percorsi

### Base — esegui e osserva

1. Leggi `EscrowLesson1.sol` dall'alto verso il basso.
2. Esegui `forge test -vv`.
3. Nel primo test individua preparazione, chiamata e verifiche.
4. Prosegui con il percorso base in `exercises/README.md`.

### Intermedio — ragiona per proprietà

1. Leggi prima il nome di ogni test e anticipa il risultato.
2. Controlla non solo il revert, ma anche lo stato successivo.
3. Completa gli esercizi sui mapping e sui valori di confine.

### Avanzato — pensa come un auditor

1. Elenca input controllati dal caller e write path prima di leggere l'implementazione.
2. Ispeziona con `-vvvv` il passaggio OWNER -> ForwarderToy -> target.
3. Muta una guardia alla volta e identifica quale test rileva l'errore.

## Calldata con Cast

Questi comandi non contattano alcuna rete:

```bash
cast sig "record(address,bytes)"
cast calldata \
  "record(address,bytes)" \
  0x0000000000000000000000000000000000000B0B \
  0x6f7264696e652d3432
```

Nell'output, i primi quattro byte sono il selector; il resto contiene gli argomenti ABI-encoded.

## Deploy facoltativo su Anvil

Avvia `anvil` in un terminale. In un secondo terminale usa esclusivamente una chiave di test
stampata da Anvil:

```bash
forge script script/DeployEscrowLesson1.s.sol:DeployEscrowLesson1 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

Non riutilizzare mai una chiave reale in questo laboratorio.

## Criterio di completamento

La lezione è completata quando:

- `forge build` e `forge test` terminano senza errori;
- sai spiegare perché nel target chiamato dal forwarder `msg.sender` è il forwarder;
- sai motivare ogni guardia di `record` con una proprietà;
- almeno un tuo test verifica lo stato dopo un revert.
