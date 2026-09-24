# Lezione 7 — Errori logici e state machine

Questa lezione studia gli errori che non richiedono primitive esotiche: basta chiamare funzioni
autorizzate **nell'ordine sbagliato o più volte**. Il laboratorio insegna a trasformare requisiti di
business in transizioni esplicite, test negativi e invarianti contabili.

> Tutti i contratti vulnerabili e gli account sono giocattoli locali. Non inviare fondi reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_07_Errori_logici_e_state_machine.md`](../../lezioni%20SmartContracts/Lezione_07_Errori_logici_e_state_machine.md).

## Prima esecuzione

Dalla directory della lezione:

```bash
forge build
forge test -vv
```

Dalla radice della repository:

```bash
forge build --root lessons/07-errori-logici-e-state-machine
forge test --root lessons/07-errori-logici-e-state-machine -vv
```

I warning sono attesi: per isolare la state machine, questi contratti registrano crediti ma non
implementano il prelievo;
`LogicBugEscrow` conserva inoltre la validazione incompleta degli indirizzi del caso vulnerabile.
Il focus è l'integrità della logica.

Per confrontare, `src/fixed/SafeEscrowFixed.sol` è `SafeEscrow` con in più `withdraw()`: buyer o
seller ritira il proprio credito, la state machine resta identica e il warning `locked-ether` non
compare più per questo file. Le aggiunte sono segnate con `NOVITA'`; per vederle tutte insieme:

```bash
diff src/SafeEscrow.sol src/fixed/SafeEscrowFixed.sol
```

## Mappa dei file

```text
src/LogicBugEscrow.sol          complete() ripetibile e priva di transizione
src/SafeEscrow.sol              transizioni atomiche e stati terminali
src/fixed/SafeEscrowFixed.sol   stesso contratto con withdraw(): niente ETH bloccato
src/BooleanStateTrap.sol        combinazioni impossibili rese rappresentabili dai bool
test/                           happy path, percorsi proibiti e regressioni
test/SafeEscrowFixed.t.sol      prelievo, doppio prelievo e destinatario che rifiuta l'ETH
script/DeploySafeEscrow.s.sol   deploy locale della versione corretta
exercises/                      percorso con dispute e mutation test
```

## Dal requisito alla matrice

| Stato corrente | Azione | Caller | Risultato |
| --- | --- | --- | --- |
| `Created` | `deposit` | buyer | `Funded` |
| `Funded` | `complete` | seller | `Completed` |
| `Funded` | `cancel` | buyer | `Cancelled` |
| ogni altro caso | operazione di ciclo | chiunque | revert |

`Completed` e `Cancelled` sono terminali. Authorization e stato rispondono a domande diverse:

```text
chi?    msg.sender == seller
quando? state == Funded
```

Una funzione è valida solo se entrambe le condizioni sono vere.

## Laboratorio: riprodurre il bug

```bash
forge test --match-contract LogicBugEscrowTest -vvvv
```

I test `test_Vulnerable_*` sono verdi proprio perché dimostrano comportamenti proibiti:

```text
deposit(1 ETH) → complete → complete → complete
backing: 1 ETH                    liabilities: 3 ETH
```

Non è reentrancy: il seller esegue tre transazioni normali. La funzione vulnerabile controlla
**chi**, ma non **quando**, e non porta mai il contratto in `Completed`.

## Regressione sulla versione corretta

```bash
forge test --match-contract SafeEscrowTest -vvvv
```

La correzione è un'operazione logica atomica:

```text
richiedi Funded → assegna una sola volta il credito → entra nello stato terminale
```

I test non verificano soltanto il revert: controllano che stato, crediti e saldo restino invariati
dopo una transizione rifiutata.

## Invariante economico

Finché i payout non vengono implementati, la proprietà globale è:

```text
liabilities = buyerCredit + sellerCredit
liabilities <= depositedAmount
liabilities <= address(escrow).balance
```

Un happy path dice che una funzione funziona. L'invariante mette invece in relazione tutte le
variabili economiche e scopre credito contabile non coperto.

## Perché non usare tre booleani

Tre flag indipendenti descrivono otto combinazioni. Tra queste è rappresentabile anche:

```text
funded = true, completed = true, cancelled = true
```

`BooleanStateTrap` rende concreto il problema. Un singolo enum non garantisce transizioni corrette,
ma rende almeno `Completed` e `Cancelled` mutuamente esclusivi per costruzione.

## Tre percorsi

### Base — leggere le transizioni

1. Disegna il grafo prima di leggere l'implementazione.
2. Esegui separatamente test validi e test negativi.
3. Distingui caller autorizzato e momento autorizzato.

### Intermedio — ragionare per sequenze

1. Riproduci double execution e terminal-state bypass.
2. Controlla gli effetti residui dopo ogni revert.
3. Estendi il grafo con lo stato `Disputed`.

### Avanzato — proprietà globali

1. Esprimi liabilities e backing indipendentemente dalla singola funzione.
2. Introduci volontariamente una mutazione e osserva quali test falliscono.
3. Cerca stati rappresentabili ma irraggiungibili o logicamente impossibili.

## Deploy facoltativo su Anvil

```bash
forge script script/DeploySafeEscrow.s.sol:DeploySafeEscrow \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai descrivere una state machine come stati, archi, prerequisiti e proprietà;
- sai distinguere stato valido, raggiungibile e terminale;
- sai trovare double execution e bypass di uno stato terminale;
- sai testare sequenze proibite e assenza di effetti dopo un revert;
- sai spiegare e verificare `liabilities <= backing`;
- sai motivare quando un enum è più sicuro di flag booleani indipendenti.
