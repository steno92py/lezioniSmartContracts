# Lezione 7 — Errori logici e State Machine

> Corso: Smart Contract Security / Solidity Security  
> Ambiente: esclusivamente locale e controllato  
> Strumenti: Solidity, Foundry, Anvil opzionale  
> Obiettivo: riconoscere e prevenire vulnerabilità di business logic e transizioni di stato scorrette

---

## 1. Obiettivi

Alla fine di questa lezione dovresti saper:

- leggere un contratto come una **macchina a stati**;
- distinguere uno stato valido da uno stato raggiungibile;
- identificare transizioni mancanti, duplicate o troppo permissive;
- riconoscere bug di tipo **double execution**, **terminal-state bypass**, **stale state**, **wrong-order checks** e **incomplete transition**;
- trasformare i requisiti di business in proprietà testabili;
- scrivere test Foundry che verifichino non solo singole funzioni, ma **sequenze di azioni**;
- usare test negativi per dimostrare che certe transizioni sono impossibili;
- progettare un Escrow in cui ogni stato abbia un significato preciso e ogni transizione abbia prerequisiti espliciti.

Il punto centrale è questo:

> Un contratto può essere perfettamente protetto contro reentrancy e access control, ma restare vulnerabile se la logica consente una sequenza di azioni che viola le regole del protocollo.

OWASP classifica oggi le **Business Logic Vulnerabilities** come una categoria primaria di rischio: il problema non è necessariamente una primitive tecnica sbagliata, ma il fatto che il contratto consenta stati o sequenze che non dovrebbero esistere.

---

## 2. Modello mentale

Pensa a un Escrow come a un distributore automatico con stati precisi.

Esempio:

```text
Created
   |
   | buyer deposits
   v
Funded
   | \
   |  \ seller completes
   |   \
   |    v
   |  Completed
   |
   | buyer cancels
   v
Cancelled
```

Finché il contratto è in `Created`, alcune azioni sono ammesse e altre no.

Quando passa a `Funded`, cambia l'insieme delle operazioni lecite.

Quando raggiunge `Completed` o `Cancelled`, dovrebbe trovarsi in uno **stato terminale**: il ciclo di vita è finito.

La domanda da auditor non è quindi solo:

> Questa funzione è corretta?

ma:

> Questa funzione è corretta **in ogni stato da cui può essere chiamata** e dopo ogni sequenza lecita di chiamate precedenti?

Questa distinzione è fondamentale.

Un bug logico spesso non vive dentro una singola riga di codice. Vive nella combinazione:

```text
azione A
→ stato intermedio
→ azione B
→ stato inatteso
→ azione C consentita per errore
```

Per questo il testing di sicurezza deve ragionare per **sequenze**, non soltanto per funzioni isolate.

---

## 3. Teoria

### 3.1 Stato logico vs stato EVM

Nel senso EVM, lo **storage** è semplicemente memoria persistente associata al contratto.

Nel senso applicativo, invece, alcune variabili di storage rappresentano lo **stato logico del protocollo**.

Per esempio:

```solidity
enum State {
    Created,
    Funded,
    Completed,
    Cancelled
}

State public state;
```

Il valore di `state` non è solo un numero intero memorizzato nello storage.

Rappresenta una dichiarazione semantica:

```text
state == Funded
```

significa qualcosa come:

> il compratore ha depositato i fondi, l'escrow è attivo e il contratto non è ancora stato completato o cancellato.

Questa frase implica altre proprietà.

Per esempio:

```text
state == Funded
⇒ depositedAmount > 0
```

oppure:

```text
state == Completed
⇒ il payout non può essere eseguito di nuovo
```

Questo è il motivo per cui una state machine aiuta la sicurezza: rende esplicite relazioni che altrimenti resterebbero soltanto nella testa dello sviluppatore.

---

### 3.2 Stato valido non significa stato raggiungibile

Considera:

```solidity
State public state;
```

L'enum contiene quattro valori formalmente validi.

Ma non tutte le transizioni dovrebbero essere possibili.

Per esempio:

```text
Created → Completed
```

potrebbe essere formalmente rappresentabile, ma logicamente impossibile perché manca il deposito.

Allo stesso modo:

```text
Cancelled → Funded
```

potrebbe essere tecnicamente impostabile nel codice, ma dovrebbe essere vietato se `Cancelled` è terminale.

Quindi distinguiamo:

- **valid state**: un valore appartenente al dominio dell'enum;
- **reachable state**: uno stato ottenibile attraverso una sequenza consentita;
- **valid transition**: passaggio esplicitamente previsto dalla specifica;
- **invalid transition**: passaggio non previsto o vietato.

Un audit serio deve verificare la raggiungibilità.

---

### 3.3 Stati terminali

Uno stato terminale è uno stato dal quale il protocollo non dovrebbe più progredire.

Nel nostro Escrow:

```text
Completed
Cancelled
```

sono buoni candidati.

La proprietà desiderata potrebbe essere:

> Una volta che l'Escrow entra in `Completed` o `Cancelled`, nessuna funzione può riportarlo in uno stato operativo.

Questa proprietà è più importante di qualunque singolo `require`.

Può essere espressa anche così:

```text
terminal(state_t)
⇒
forall future calls:
state_{t+n} == state_t
```

Naturalmente possono ancora esistere funzioni `view` o operazioni amministrative non legate al ciclo economico, ma il ciclo dell'Escrow non deve riaprirsi accidentalmente.

---

### 3.4 Double execution

Uno dei bug logici più comuni è eseguire due volte un'operazione che dovrebbe essere unica.

Esempio concettuale:

```solidity
function complete() external {
    require(msg.sender == seller);
    sellerCredit += amount;
}
```

Manca una verifica sullo stato.

Se `complete()` può essere richiamata:

```text
prima chiamata  → sellerCredit += amount
seconda chiamata → sellerCredit += amount
terza chiamata  → sellerCredit += amount
```

Non serve reentrancy.

Non serve bypassare access control.

Il venditore è autorizzato.

La vulnerabilità nasce dal fatto che un'azione legittima può essere eseguita **più volte**.

Questa è una tipica business logic vulnerability.

---

### 3.5 Check corretto, stato sbagliato

Un'altra classe di bug si verifica quando una funzione controlla qualcosa di vero ma insufficiente.

Esempio:

```solidity
require(msg.sender == buyer);
```

Il caller è corretto.

Ma manca:

```solidity
require(state == State.Funded);
```

Quindi un buyer autorizzato potrebbe chiamare una funzione nel momento sbagliato.

Questo porta a una distinzione importante:

```text
Authorization:
"chi può eseguire questa azione?"

State validity:
"quando può eseguirla?"
```

Entrambe devono essere vere.

---

### 3.6 Ordine delle operazioni

Una state transition sicura dovrebbe spesso seguire questo schema mentale:

```text
1. valida caller
2. valida input
3. valida stato corrente
4. calcola effetti
5. aggiorna lo stato
6. effettua interazioni esterne, se necessarie
```

Non è una regola assoluta, ma è un'ottima base.

In particolare, lo stato deve essere aggiornato in modo che un'operazione conclusa non possa sembrare ancora disponibile durante una successiva chiamata.

Questo si collega direttamente alla lezione sulla reentrancy, ma qui il problema è più generale: anche senza callback esterne, una state machine incompleta può permettere una seconda esecuzione.

---

### 3.7 Path dependence

Una proprietà può essere vera dopo una singola operazione ma falsa dopo una sequenza.

Esempio:

```text
Created → deposit → Funded
```

funziona.

```text
Funded → cancel → Cancelled
```

funziona.

Ma se il contratto permette anche:

```text
Cancelled → complete
```

allora il protocollo può raggiungere uno stato impossibile.

La correttezza dipende quindi dal **path**, cioè dal cammino seguito attraverso la state machine.

Questo è uno dei motivi per cui fuzzing e invariant testing diventeranno così importanti nelle lezioni successive.

---

## 4. Esempio Solidity vulnerabile

Creiamo volutamente un Escrow con un errore logico.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract LogicBugEscrow {
    enum State {
        Created,
        Funded,
        Completed,
        Cancelled
    }

    address public immutable buyer;
    address public immutable seller;

    State public state;
    uint256 public depositedAmount;
    uint256 public sellerCredit;
    uint256 public buyerCredit;

    error OnlyBuyer();
    error OnlySeller();
    error WrongState();
    error WrongAmount();

    constructor(address _buyer, address _seller) {
        buyer = _buyer;
        seller = _seller;
        state = State.Created;
    }

    function deposit() external payable {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Created) revert WrongState();
        if (msg.value == 0) revert WrongAmount();

        depositedAmount = msg.value;
        state = State.Funded;
    }

    function complete() external {
        if (msg.sender != seller) revert OnlySeller();

        // BUG LOGICO:
        // manca il controllo state == State.Funded
        // e manca una transizione a Completed.
        sellerCredit += depositedAmount;
    }

    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert WrongState();

        buyerCredit += depositedAmount;
        state = State.Cancelled;
    }
}
```

Questo contratto non contiene alcuna chiamata esterna.

Non c'è reentrancy.

Non c'è `delegatecall`.

Non c'è un access control bypass evidente.

Eppure è vulnerabile.

---

## 5. Analisi del codice

### `constructor`

```solidity
constructor(address _buyer, address _seller)
```

**Chi può chiamarla?**

Solo il deployer durante la creazione del contratto.

**Input controllati dal chiamante**

- `_buyer`
- `_seller`

**Stato letto**

Nessuno.

**Stato modificato**

- `buyer`
- `seller`
- `state`

**Chiamate esterne**

Nessuna.

**Assunzioni**

Il contratto assume implicitamente che buyer e seller siano indirizzi sensati.

In un design più robusto potremmo vietare `address(0)` e, a seconda dei requisiti, persino `buyer == seller`.

---

### `deposit()`

```solidity
function deposit() external payable
```

**Chi può chiamarla?**

Solo `buyer`.

**Input controllati dal chiamante**

Il caller controlla:

- `msg.sender` tramite l'account da cui invia;
- `msg.value`.

**Valore in ingresso**

Ether tramite `msg.value`.

**Stato letto**

- `buyer`
- `state`

**Stato modificato**

- `depositedAmount`
- `state`

**Chiamate esterne**

Nessuna.

**Assunzioni**

- il deposito avviene una sola volta;
- `Created` è l'unico stato da cui è consentito finanziare l'Escrow.

Questa funzione implementa correttamente la transizione:

```text
Created → Funded
```

---

### `complete()`

```solidity
function complete() external
```

**Chi può chiamarla?**

Solo `seller`.

**Input controllati dal chiamante**

Nessun parametro esplicito.

Il caller controlla soltanto quando effettuare la chiamata.

Questo dettaglio è importante: **il timing della chiamata è anch'esso input controllato dall'utente**.

**Valore in ingresso**

Nessuno.

**Stato letto**

- `seller`
- `depositedAmount`

**Stato modificato**

- `sellerCredit`

**Chiamate esterne**

Nessuna.

**Assunzioni implicite errate**

La funzione sembra assumere che:

- venga chiamata solo dopo `deposit()`;
- venga chiamata una volta sola;
- non venga chiamata dopo `cancel()`.

Ma nessuna di queste proprietà è imposta dal codice.

Il contratto si affida quindi a una sequenza “educata” di utilizzo.

In sicurezza, questo è un errore.

---

### `cancel()`

```solidity
function cancel() external
```

**Chi può chiamarla?**

Solo il buyer.

**Input controllati dal chiamante**

Il momento della chiamata.

**Stato letto**

- `buyer`
- `state`
- `depositedAmount`

**Stato modificato**

- `buyerCredit`
- `state`

**Chiamate esterne**

Nessuna.

**Assunzioni**

La funzione implementa:

```text
Funded → Cancelled
```

correttamente.

Il problema nasce quando altre funzioni ignorano il fatto che `Cancelled` dovrebbe essere terminale.

---

## 6. Proprietà e invarianti

Trasformiamo la specifica in frasi verificabili.

### Proprietà P1 — deposito unico

> Il deposito può avvenire soltanto nello stato `Created`.

Formalmente:

```text
state != Created
⇒ deposit() reverts
```

---

### Proprietà P2 — completamento soltanto da Funded

> L'Escrow può essere completato soltanto se è stato prima finanziato.

```text
complete() succeeds
⇒ previous state == Funded
```

---

### Proprietà P3 — completamento unico

> Uno stesso Escrow non può essere completato più di una volta.

```text
Completed
⇒ complete() always reverts afterwards
```

---

### Proprietà P4 — cancellazione unica

> Dopo la cancellazione, l'Escrow non può essere cancellato di nuovo.

---

### Proprietà P5 — stati terminali irreversibili

> `Completed` e `Cancelled` sono terminali.

Quindi:

```text
Completed !→ Funded
Completed !→ Cancelled
Cancelled !→ Funded
Cancelled !→ Completed
```

---

### Proprietà P6 — credito esclusivo

Nel nostro modello, il capitale economico dovrebbe essere assegnato o al seller o al buyer, mai a entrambi.

Una possibile proprietà:

```text
sellerCredit > 0
⇒ buyerCredit == 0
```

oltre a:

```text
buyerCredit > 0
⇒ sellerCredit == 0
```

---

### Proprietà P7 — nessuna creazione contabile di valore

Poiché in questa versione non effettuiamo ancora payout:

```text
sellerCredit + buyerCredit <= depositedAmount
```

Il contratto vulnerabile può rompere facilmente questa proprietà.

Se `depositedAmount == 1 ether` e `complete()` viene chiamata tre volte:

```text
sellerCredit == 3 ether
```

quindi:

```text
sellerCredit > depositedAmount
```

Abbiamo creato un credito contabile non coperto.

Questo è un esempio di **accounting invariant**.

---

## 7. Laboratorio Foundry

### Struttura

```text
logic-state-machine/
├── foundry.toml
├── src/
│   ├── LogicBugEscrow.sol
│   └── SafeEscrow.sol
└── test/
    └── EscrowLogic.t.sol
```

Creazione progetto:

```bash
forge init logic-state-machine
cd logic-state-machine
```

Sostituisci i file generati con quelli di questa lezione.

---

## 8. Test negativi sul contratto vulnerabile

Crea `test/EscrowLogic.t.sol`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/Test.sol";
import {LogicBugEscrow} from "../src/LogicBugEscrow.sol";

contract EscrowLogicTest is Test {
    LogicBugEscrow internal escrow;

    address internal buyer = makeAddr("buyer");
    address internal seller = makeAddr("seller");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        escrow = new LogicBugEscrow(buyer, seller);
        vm.deal(buyer, 10 ether);
    }

    function testDepositMovesCreatedToFunded() public {
        vm.prank(buyer);
        escrow.deposit{value: 1 ether}();

        assertEq(
            uint256(escrow.state()),
            uint256(LogicBugEscrow.State.Funded)
        );

        assertEq(escrow.depositedAmount(), 1 ether);
    }

    function testNonBuyerCannotDeposit() public {
        vm.deal(stranger, 1 ether);

        vm.expectRevert(LogicBugEscrow.OnlyBuyer.selector);
        vm.prank(stranger);
        escrow.deposit{value: 1 ether}();
    }

    function testSecondDepositReverts() public {
        vm.startPrank(buyer);

        escrow.deposit{value: 1 ether}();

        vm.expectRevert(LogicBugEscrow.WrongState.selector);
        escrow.deposit{value: 1 ether}();

        vm.stopPrank();
    }
}
```

Esegui:

```bash
forge test -vv
```

Questi test dovrebbero passare.

Ma non abbiamo ancora testato la parte vulnerabile.

---

## 9. Riproduzione locale del bug logico

Aggiungiamo:

```solidity
function testBug_CompleteCanRunBeforeDeposit() public {
    vm.prank(seller);
    escrow.complete();

    // Nessun revert.
    // depositedAmount è zero, quindi il bug non produce credito,
    // ma la transizione illegale è comunque accettata.
    assertEq(escrow.sellerCredit(), 0);
}
```

Questo test dimostra una prima violazione semantica:

```text
Created → complete()
```

è consentita.

La conseguenza economica più evidente emerge dopo il deposito.

```solidity
function testBug_CompleteCanBeCalledMultipleTimes() public {
    vm.prank(buyer);
    escrow.deposit{value: 1 ether}();

    vm.startPrank(seller);

    escrow.complete();
    escrow.complete();
    escrow.complete();

    vm.stopPrank();

    assertEq(escrow.depositedAmount(), 1 ether);
    assertEq(escrow.sellerCredit(), 3 ether);
}
```

Il test passa.

Ed è proprio questo il problema.

Il protocollo ha ricevuto:

```text
1 ETH
```

ma registra:

```text
3 ETH di credito
```

La proprietà:

```text
sellerCredit + buyerCredit <= depositedAmount
```

è stata violata.

---

### Bug ancora più grave: complete dopo cancel

Aggiungiamo:

```solidity
function testBug_CompleteAfterCancelCreatesConflictingCredits() public {
    vm.prank(buyer);
    escrow.deposit{value: 1 ether}();

    vm.prank(buyer);
    escrow.cancel();

    assertEq(escrow.buyerCredit(), 1 ether);

    vm.prank(seller);
    escrow.complete();

    assertEq(escrow.buyerCredit(), 1 ether);
    assertEq(escrow.sellerCredit(), 1 ether);
}
```

Ora entrambi risultano creditori dello stesso deposito.

Abbiamo:

```text
1 ETH depositato
```

ma:

```text
buyerCredit  = 1 ETH
sellerCredit = 1 ETH
```

Totale obbligazioni:

```text
2 ETH
```

Backing:

```text
1 ETH
```

Questo è un bug di state machine, non un bug di arithmetic overflow.

---

## 10. Correzione

Creiamo `src/SafeEscrow.sol`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract SafeEscrow {
    enum State {
        Created,
        Funded,
        Completed,
        Cancelled
    }

    address public immutable buyer;
    address public immutable seller;

    State public state;
    uint256 public depositedAmount;
    uint256 public sellerCredit;
    uint256 public buyerCredit;

    error OnlyBuyer();
    error OnlySeller();
    error WrongState(State expected, State actual);
    error WrongAmount();
    error ZeroAddress();
    error SameParty();

    constructor(address _buyer, address _seller) {
        if (_buyer == address(0) || _seller == address(0)) {
            revert ZeroAddress();
        }

        if (_buyer == _seller) {
            revert SameParty();
        }

        buyer = _buyer;
        seller = _seller;
        state = State.Created;
    }

    function deposit() external payable {
        if (msg.sender != buyer) revert OnlyBuyer();
        _requireState(State.Created);
        if (msg.value == 0) revert WrongAmount();

        depositedAmount = msg.value;
        state = State.Funded;
    }

    function complete() external {
        if (msg.sender != seller) revert OnlySeller();
        _requireState(State.Funded);

        // Effetti atomici della transizione.
        sellerCredit = depositedAmount;
        state = State.Completed;
    }

    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        _requireState(State.Funded);

        buyerCredit = depositedAmount;
        state = State.Cancelled;
    }

    function _requireState(State expected) internal view {
        if (state != expected) {
            revert WrongState(expected, state);
        }
    }
}
```

Osserva la differenza fondamentale.

Prima:

```solidity
sellerCredit += depositedAmount;
```

Ora:

```solidity
sellerCredit = depositedAmount;
state = State.Completed;
```

Il punto non è soltanto usare `=` invece di `+=`.

La vera correzione è la combinazione:

```text
require Funded
+
assegna credito
+
passa a Completed
```

In altre parole, **l'operazione economica e la transizione di stato formano un'unica azione logica**.

---

## 11. Test di regressione

Importa anche `SafeEscrow`:

```solidity
import {SafeEscrow} from "../src/SafeEscrow.sol";
```

Aggiungiamo una nuova test suite.

```solidity
contract SafeEscrowTest is Test {
    SafeEscrow internal escrow;

    address internal buyer = makeAddr("buyer");
    address internal seller = makeAddr("seller");

    function setUp() public {
        escrow = new SafeEscrow(buyer, seller);
        vm.deal(buyer, 10 ether);
    }

    function _fund() internal {
        vm.prank(buyer);
        escrow.deposit{value: 1 ether}();
    }

    function testCompleteMovesFundedToCompleted() public {
        _fund();

        vm.prank(seller);
        escrow.complete();

        assertEq(
            uint256(escrow.state()),
            uint256(SafeEscrow.State.Completed)
        );

        assertEq(escrow.sellerCredit(), 1 ether);
        assertEq(escrow.buyerCredit(), 0);
    }

    function testCannotCompleteBeforeDeposit() public {
        vm.expectRevert();
        vm.prank(seller);
        escrow.complete();
    }

    function testCannotCompleteTwice() public {
        _fund();

        vm.prank(seller);
        escrow.complete();

        vm.expectRevert();
        vm.prank(seller);
        escrow.complete();
    }

    function testCannotCompleteAfterCancel() public {
        _fund();

        vm.prank(buyer);
        escrow.cancel();

        vm.expectRevert();
        vm.prank(seller);
        escrow.complete();
    }

    function testCannotCancelAfterComplete() public {
        _fund();

        vm.prank(seller);
        escrow.complete();

        vm.expectRevert();
        vm.prank(buyer);
        escrow.cancel();
    }

    function testCreditsNeverExceedDepositAfterComplete() public {
        _fund();

        vm.prank(seller);
        escrow.complete();

        uint256 totalCredits =
            escrow.sellerCredit() + escrow.buyerCredit();

        assertLe(totalCredits, escrow.depositedAmount());
    }
}
```

Esegui:

```bash
forge test -vv
```

---

## 12. Perché i test negativi contano più di quanto sembra

Uno sviluppatore potrebbe scrivere solo:

```solidity
function testComplete() public {
    deposit();
    complete();
    assertEq(state, Completed);
}
```

Questo dimostra solo che una sequenza valida funziona.

Non dimostra che le sequenze invalide falliscano.

In sicurezza servono entrambe.

La matrice mentale è:

```text
                     EXPECTED
                success     revert
             +----------------------
valid path   |    ✓           ?
invalid path |    ?           ✓
```

Un test suite robusto deve coprire tutte e quattro le domande:

- la sequenza lecita riesce?
- la sequenza lecita produce lo stato corretto?
- la sequenza illecita fallisce?
- dopo il fallimento lo stato resta invariato?

Quest'ultima domanda è spesso dimenticata.

---

## 13. Test dello stato dopo un revert

Un `revert` EVM annulla le modifiche effettuate dalla chiamata che viene revertita.

Possiamo verificare esplicitamente che una transizione illegale non corrompa lo stato.

```solidity
function testFailedTransitionDoesNotChangeState() public {
    _fund();

    vm.prank(seller);
    escrow.complete();

    SafeEscrow.State beforeState = escrow.state();
    uint256 beforeSellerCredit = escrow.sellerCredit();

    vm.expectRevert();
    vm.prank(seller);
    escrow.complete();

    assertEq(uint256(escrow.state()), uint256(beforeState));
    assertEq(escrow.sellerCredit(), beforeSellerCredit);
}
```

Questo tipo di test è utile soprattutto quando la funzione contiene molte operazioni o chiamate esterne.

---

## 14. Audit manuale della state machine

Quando trovi un `enum State`, non limitarti a leggere i nomi.

Disegna una tabella.

Per il nostro Escrow:

| Stato corrente | Azione | Caller | Stato successivo | Consentita? |
|---|---|---|---|---|
| Created | deposit | buyer | Funded | sì |
| Created | complete | seller | — | no |
| Created | cancel | buyer | — | no |
| Funded | deposit | buyer | — | no |
| Funded | complete | seller | Completed | sì |
| Funded | cancel | buyer | Cancelled | sì |
| Completed | deposit | buyer | — | no |
| Completed | complete | seller | — | no |
| Completed | cancel | buyer | — | no |
| Cancelled | deposit | buyer | — | no |
| Cancelled | complete | seller | — | no |
| Cancelled | cancel | buyer | — | no |

Questa tabella è sorprendentemente potente.

Permette di vedere immediatamente transizioni dimenticate.

Durante un audit reale, è spesso utile costruire questa matrice prima ancora di leggere in dettaglio l'implementazione.

---

## 15. Un altro errore comune: flag indipendenti

Considera questo design:

```solidity
bool public funded;
bool public completed;
bool public cancelled;
```

Sembra semplice.

Ma quanti stati rappresenta?

Tre booleani permettono:

```text
2^3 = 8 combinazioni
```

Tra queste:

```text
funded = true
completed = true
cancelled = true
```

potrebbe essere logicamente impossibile.

Con un enum:

```solidity
enum State {
    Created,
    Funded,
    Completed,
    Cancelled
}
```

hai invece solo quattro stati rappresentabili.

Questo non rende automaticamente il contratto sicuro, ma riduce enormemente lo spazio di stati incoerenti.

Principio utile:

> Quando più booleani descrivono fasi mutuamente esclusive dello stesso processo, valuta se un enum rende gli stati illegali non rappresentabili.

---

## 16. Unreachable states e impossible states

In progettazione sicura è utile distinguere:

### Stato rappresentabile ma indesiderato

Esempio con booleani:

```text
completed = true
cancelled = true
```

Il linguaggio permette di rappresentarlo.

Il protocollo no.

### Stato non rappresentabile

Con enum:

```solidity
State.Completed
```

e

```solidity
State.Cancelled
```

sono mutuamente esclusivi per costruzione.

Questo segue un principio generale di secure design:

> È meglio rendere uno stato invalido impossibile da rappresentare che affidarsi a molti controlli sparsi per impedirlo.

---

## 17. Sequenze, non solo input

Molti fuzz test tradizionali variano un input:

```text
amount = random
```

Ma nelle state machine è spesso più importante variare la **sequenza**:

```text
deposit
cancel
complete
```

oppure:

```text
deposit
complete
cancel
```

oppure:

```text
complete
deposit
complete
```

L'attaccante non controlla soltanto i parametri.

Controlla anche:

- ordine delle chiamate;
- ripetizione delle chiamate;
- account utilizzati;
- quantità inviate;
- timing relativo delle transazioni.

Questo concetto ci porterà direttamente all'invariant testing più avanti nel corso.

---

## 18. Proprietà globale: liability <= backing

Nel nostro Escrow semplificato possiamo definire:

```text
liabilities = sellerCredit + buyerCredit
```

e:

```text
backing = depositedAmount
```

Proprietà:

```text
liabilities <= backing
```

Questa proprietà è molto più potente di un test del tipo:

```text
complete() assegna 1 ETH al seller
```

perché verifica una relazione economica globale.

È proprio questo il tipo di pensiero che distingue un test funzionale da un test di sicurezza.

OWASP raccomanda esplicitamente di ragionare su invarianti che devono rimanere veri prima e dopo ogni funzione state-changing, proprio perché molti bug di business logic emergono dall'incoerenza tra componenti o valori correlati.

---

## 19. Mutation test manuale

Un buon modo per capire se un test suite protegge davvero una proprietà consiste nel introdurre volontariamente una piccola regressione.

Nel contratto sicuro cambia:

```solidity
_requireState(State.Funded);
```

in:

```solidity
// _requireState(State.Funded);
```

all'interno di `complete()`.

Ora esegui:

```bash
forge test
```

Dovrebbero fallire almeno:

```text
testCannotCompleteBeforeDeposit
testCannotCompleteTwice
testCannotCompleteAfterCancel
```

Se nessun test fallisse, significherebbe che il test suite non sta realmente proteggendo la state machine.

Questa tecnica manuale anticipa il concetto di **mutation testing**:

> un buon test non è soltanto verde sul codice corretto; deve diventare rosso quando introduciamo deliberatamente un bug rilevante.

---

## 20. Analisi delle assunzioni

Ogni funzione contiene assunzioni esplicite o implicite.

Per `complete()`:

```text
ASSUNZIONI DESIDERATE

1. caller == seller
2. state == Funded
3. depositedAmount > 0
4. complete non è già stata eseguita
5. cancel non è già stata eseguita
6. l'assegnazione del credito non supera il deposito
```

Ora chiediamoci:

```text
quali di queste sono garantite direttamente?
quali sono conseguenza di altre invarianti?
quali sono solo speranze?
```

Nel contratto corretto:

```text
state == Funded
```

implica già:

```text
non Completed
non Cancelled
```

perché l'enum ha un solo valore alla volta.

Questo riduce il numero di condizioni da mantenere mentalmente.

---

## 21. Checklist da auditor

Quando analizzi una state machine, chiediti:

1. Quali sono tutti gli stati possibili?
2. Qual è lo stato iniziale?
3. Quali stati sono terminali?
4. Per ogni funzione state-changing, da quali stati è callable?
5. Quali stati produce?
6. Una stessa transizione può essere eseguita due volte?
7. È possibile saltare uno stato obbligatorio?
8. È possibile tornare da uno stato terminale?
9. Esistono flag booleani che possono produrre combinazioni incoerenti?
10. Access control e state validation sono controllati separatamente?
11. Il caller può controllare l'ordine delle chiamate per ottenere un risultato inatteso?
12. Dopo ogni transizione, le liabilities restano coperte dagli asset?
13. Una funzione aggiorna tutte le variabili correlate oppure solo una parte?
14. Un revert lascia lo stato precedente intatto?
15. Esistono sequenze valide singolarmente ma pericolose in combinazione?
16. I test coprono esplicitamente le transizioni proibite?
17. Il test suite fallisce se rimuovi intenzionalmente un controllo di stato?

---

## 22. Esercizi

### Esercizio 1 — Disegna la macchina a stati

Aggiungi uno stato:

```text
Disputed
```

Requisiti:

- buyer e seller possono aprire una disputa solo da `Funded`;
- `Disputed` non è terminale;
- un `arbiter` può risolvere la disputa verso `Completed` oppure `Cancelled`.

Disegna prima il diagramma delle transizioni.

Non scrivere ancora Solidity.

---

### Esercizio 2 — Implementazione

Implementa la state machine dell'esercizio 1.

Prova a mantenere tutte le transizioni in funzioni brevi.

---

### Esercizio 3 — Test negativi

Scrivi test che dimostrino che:

- non puoi aprire una disputa da `Created`;
- non puoi aprire una disputa dopo `Completed`;
- un address non autorizzato non può risolverla;
- una disputa non può essere risolta due volte.

---

### Esercizio 4 — Invariante economico

Definisci una proprietà che garantisca che:

```text
buyerCredit + sellerCredit <= depositedAmount
```

in ogni stato.

Scrivi almeno tre test con sequenze diverse che provino questa proprietà.

---

### Esercizio 5 — Bug hunt

Trova il problema:

```solidity
function resolveForSeller() external {
    if (msg.sender != arbiter) revert OnlyArbiter();

    state = State.Completed;
    sellerCredit += depositedAmount;
}
```

Individua tutte le assunzioni mancanti.

---

### Esercizio 6 — Stati impossibili

Riprogetta questo modello:

```solidity
bool funded;
bool completed;
bool cancelled;
bool disputed;
```

usando uno o più enum in modo da ridurre le combinazioni logicamente impossibili.

---

## 23. Cosa devo ricordare

- Una smart contract state machine non è soltanto un `enum`: è l'insieme di **stati, transizioni, prerequisiti e proprietà**.
- Access control risponde a **chi**, la state validation risponde a **quando**.
- Molti bug logici emergono da **sequenze di azioni**, non da una singola chiamata.
- Gli stati terminali devono essere realmente terminali.
- Un'azione economica unica deve essere eseguibile una sola volta.
- Gli invarianti contabili come `liabilities <= backing` sono spesso più potenti dei test del singolo happy path.
- I test negativi devono dimostrare che le transizioni proibite falliscono.
- Quando possibile, progetta i tipi dati in modo che gli stati illegali siano difficili o impossibili da rappresentare.
- Un buon test suite deve fallire quando introduci deliberatamente una regressione significativa.

La domanda da portarti dietro come auditor è:

> **Quale sequenza di chiamate può portare il contratto in uno stato che gli sviluppatori non avevano previsto?**

---

## 24. Fonti della lezione

Fonti tecniche consultate per questa lezione:

- **Solidity Documentation**, documentazione corrente del linguaggio e raccomandazione di utilizzare l'ultima release stabile disponibile:  
  https://docs.soliditylang.org/

- **OWASP Smart Contract Security — SC02:2026 Business Logic Vulnerabilities**, per la classificazione dei bug di business logic, invariant violations, path-dependent state machines e order-of-operations edge cases:  
  https://scs.owasp.org/sctop10/SC02-BusinessLogicVulnerabilities/

- **OWASP Smart Contract Security Verification Standard — Business Logic and Economic Security**, per il modello di verifica della correttezza della logica economica e delle transazioni:  
  https://scs.owasp.org/SCSVS/07-SCSVS-GOV/

- **OWASP SCSVS-GOV-3 — Preventing Reentrancy and Logic Flaws**, in particolare per unique execution, simmetria delle modifiche di stato e integrità del transaction flow:  
  https://scs.owasp.org/SCSVS/controls/SCSVS-GOV-3/

- **OWASP Smart Contract Security — Analysis Techniques**, per la domanda di audit: verificare che un invariante resti vero prima e dopo ogni funzione che modifica lo stato:  
  https://scs.owasp.org/handbooks/04-evm-forensics-defi-recovery/part3-analysis-techniques/

- **Foundry Documentation**, riferimento per struttura dei test e cheatcodes usati nel laboratorio:  
  https://getfoundry.sh/

---

**Fine Lezione 7.**

La prossima lezione non è inclusa qui, come richiesto dal metodo del corso.
