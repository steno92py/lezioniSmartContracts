# Lezione 3 — Escrow e macchina a stati

Questa lezione introduce l'Escrow conduttore del corso. L'obiettivo non è ancora trasferire ETH al
seller, ma progettare e verificare la sequenza delle transizioni prima di aggiungere chiamate
esterne.

> Contratti esclusivamente didattici e locali. L'ETH depositata non può essere recuperata in questa
> versione: non usare fondi reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_03_Escrow_e_macchina_a_stati.md`](../../lezioni%20SmartContracts/Lezione_03_Escrow_e_macchina_a_stati.md).

## Modello

```text
                     buyer: fund(price)
      Created --------------------------------> Funded
         |                                         |
         | buyer: cancelBeforeFunding()            | buyer: approveRelease()
         v                                         v
     Cancelled                               ReleaseApproved
     terminale                                  terminale
```

Una funzione deve superare due dimensioni indipendenti:

```text
CHI?     autorizzazione del caller
QUANDO?  guardia sullo stato corrente
```

Il buyer corretto nello stato sbagliato deve comunque ricevere un revert.

## Transition matrix

| Stato corrente | `fund()` | `approveRelease()` | `cancelBeforeFunding()` |
| --- | --- | --- | --- |
| `Created` | buyer + prezzo: `Funded` | revert | buyer: `Cancelled` |
| `Funded` | revert | buyer: `ReleaseApproved` | revert |
| `ReleaseApproved` | revert | revert | revert |
| `Cancelled` | revert | revert | revert |

Tutte le frecce assenti fanno parte della specifica: rappresentano il comportamento proibito.

## Prima esecuzione

Dalla directory della lezione:

```bash
forge build
forge test -vv
```

Dalla radice della repository:

```bash
forge build --root lessons/03-escrow-e-macchina-a-stati
forge test --root lessons/03-escrow-e-macchina-a-stati -vv
```

I warning `locked-ether` sono intenzionali: il payout verrà introdotto nella Lezione 4.

Per confrontare, `src/fixed/EscrowStateMachineFixed.sol` è lo stesso contratto con in più lo stato
`Released` e la funzione `release()`: dopo `approveRelease()` il seller incassa il prezzo e il
warning `locked-ether` non compare più. La Lezione 4 sviluppa il payout per intero. Le aggiunte
sono segnate con `NOVITA'`; per vederle tutte insieme:

```bash
diff src/EscrowStateMachine.sol src/fixed/EscrowStateMachineFixed.sol
```

## Mappa dei file

```text
src/EscrowStateMachine.sol              macchina a stati corretta
src/fixed/EscrowStateMachineFixed.sol   stesso contratto con release(): niente ETH bloccato
src/labs/BadEscrowStateMachine.sol      guardia di stato volutamente assente
test/EscrowStateMachine.t.sol           percorsi validi e negative space
test/BadEscrowStateMachine.t.sol        riproduzione locale del bug
test/EscrowStateMachineFixed.t.sol      payout, caller e stato sbagliati, seller che rifiuta l'ETH
script/DeployEscrowStateMachine.s.sol   deploy facoltativo su Anvil
exercises/                              attività graduate escluse dalla suite
```

## Cosa osservare nei test

- `setUp()` ricrea un esperimento indipendente prima di ogni test;
- `makeAddr` crea identità leggibili, mentre `vm.deal` assegna soltanto fondi fittizi;
- ogni transizione valida controlla lo stato finale;
- ogni transizione vietata controlla anche l'assenza di effetti persistenti;
- `expectPartialRevert(selector)` controlla il tipo di custom error parametrizzato, mentre
  `expectRevert(abi.encodeWithSelector(...))` può verificarne anche tutti gli argomenti;
- gli stati terminali non devono poter essere riaperti;
- `ReleaseApproved` deve raccontare una storia che include un funding precedente.

Per seguire una transizione nella trace:

```bash
forge test --match-test test_BuyerCanFundExactPrice -vvvv
```

## Laboratorio vulnerabile

Esegui:

```bash
forge test --match-contract BadEscrowStateMachineTest -vvvv
```

Il test passa, ma dimostra un bug: `Created -> ReleaseApproved` è raggiungibile senza funding. Una
suite verde non implica sicurezza; conta la proprietà che l'esperimento dimostra.

Confronta poi il regression test del contratto corretto:

```bash
forge test --match-test test_RevertWhen_ApproveHappensBeforeFunding -vvvv
```

## Tre percorsi

### Base — leggere una state machine

1. Segui il percorso `Created -> Funded -> ReleaseApproved`.
2. Segui separatamente `Created -> Cancelled`.
3. Completa la transition matrix senza leggere il contratto.

### Intermedio — esplorare il negative space

1. Classifica i revert per caller, valore, stato e ripetizione.
2. Verifica saldi e stato dopo le call fallite.
3. Completa gli esercizi sui caller e sugli stati terminali.

### Avanzato — auditare la storia

1. Cerca percorsi che saltano una fase o riaprono uno stato terminale.
2. Confronta il grafo progettato con quello realmente implementato.
3. Applica una mutazione alla volta e identifica il regression test corrispondente.

## Deploy facoltativo su Anvil

Con `anvil` già avviato e usando esclusivamente una sua chiave di test:

```bash
forge script script/DeployEscrowStateMachine.s.sol:DeployEscrowStateMachine \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

Il deploy locale usa `address(0xB0B)` come seller e `5 ether` come prezzo didattico.

## Criterio di completamento

- sai spiegare la differenza tra autorizzazione e sequenziamento;
- sai ricostruire il grafo senza guardare Solidity;
- sai indicare perché `Created -> ReleaseApproved` viola una proprietà storica;
- almeno un tuo test prova una freccia assente;
- sai distinguere un assert di scenario sul balance da un invariante universale.
