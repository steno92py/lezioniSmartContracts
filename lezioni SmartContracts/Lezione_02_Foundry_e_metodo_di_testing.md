# Smart Contract Security / Solidity Security
## Lezione 2 — Foundry e metodo di testing: dai requisiti alle proprietà verificabili

> **Ambiente del corso:** esclusivamente didattico, difensivo e locale. Tutti gli esempi usano contratti giocattolo, account di test e fondi fittizi. In questa lezione non useremo fork di mainnet, protocolli reali, wallet reali o RPC pubblici.
>
> **Baseline verificata il 21 settembre 2026:** continuiamo a compilare gli esempi con **Solidity 0.8.37** per coerenza con la Lezione 1. La documentazione corrente di Foundry conferma l'uso di `forge test`, dei test Solidity con prefisso `test`, di `setUp()`, di `forge-std/Test.sol`, dei cheatcode `vm.prank`, `vm.deal` e `vm.expectRevert`, delle trace tramite livelli di verbosità e del debugger integrato.

---

## 1. Obiettivi

Alla fine di questa lezione dovresti saper:

- creare e organizzare un progetto Foundry minimale;
- capire la differenza tra **contratto sotto test** e **test harness**;
- usare `forge build`, `forge test`, filtri, verbosity, trace e debugger;
- scrivere test Solidity ereditando da `forge-std/Test.sol`;
- usare `setUp()` per costruire uno stato iniziale ripetibile;
- simulare chiamanti diversi con `vm.prank`;
- assegnare Ether fittizia ad account di test con `vm.deal`;
- verificare fallimenti attesi con `vm.expectRevert`;
- distinguere happy path, test negativi e proprietà di sicurezza;
- verificare non solo che un'operazione fallisca, ma anche che **non lasci effetti parziali**;
- leggere una trace per capire chiamante, valore, call boundary e revert;
- valutare la qualità di una suite chiedendoti quali bug riuscirebbe realmente a scoprire;
- trasformare una specifica in test prima di considerare il contratto “corretto”.

La disciplina che iniziamo oggi sarà la base di tutto il corso:

> **Specifica → proprietà → implementazione → test positivi → test negativi → tentativo di violazione → correzione → test di regressione.**

---

## 2. Modello mentale

Un test non è una dimostrazione astratta che “il contratto è sicuro”.

Un test è un esperimento ripetibile che prova una proprietà in uno scenario concreto.

Immagina tre livelli distinti:

```text
REQUISITO
"Un indirizzo può registrarsi una sola volta pagando esattamente 1 ETH"
        |
        v
PROPRIETÀ VERIFICABILI
P1: 1 ETH esatto + nuovo utente -> successo
P2: meno di 1 ETH -> revert
P3: più di 1 ETH -> revert
P4: secondo tentativo dello stesso utente -> revert
P5: dopo un revert lo stato contabile non cambia
        |
        v
TEST FOUNDRY
una funzione Solidity per ogni comportamento importante
```

Il punto cruciale è che i test derivano dalla specifica, non viceversa.

Se scrivi prima il contratto e poi inventi test che confermano ciò che il contratto fa già, rischi di testare l'implementazione contro se stessa.

Un auditor deve ragionare in modo opposto:

```text
Cosa DEVE essere vero?
        |
        v
Quali stati o input potrebbero renderlo falso?
        |
        v
Quale test distingue l'implementazione corretta da quella sbagliata?
```

### Il test come macchina degli esperimenti

Foundry esegue il contratto in una EVM locale controllata dal framework.

Il test può:

- distribuire contratti;
- assegnare bilanci;
- scegliere `msg.sender` per la prossima chiamata;
- effettuare chiamate con `msg.value`;
- controllare storage tramite getter;
- aspettarsi un revert preciso;
- ispezionare trace;
- confrontare valore atteso e valore osservato.

Non stiamo “fingendo” il comportamento Solidity: il bytecode viene compilato ed eseguito secondo la semantica EVM gestita da Foundry.

### Test indipendenti

La funzione `setUp()` viene eseguita prima di ogni test case.

Mentalmente considera quindi ogni test come un esperimento separato:

```text
setUp()
  |
  +--> test A

setUp()
  |
  +--> test B

setUp()
  |
  +--> test C
```

Un test non dovrebbe dipendere dal fatto che un altro sia stato eseguito prima.

Questa indipendenza è essenziale per la sicurezza perché rende i fallimenti riproducibili e riduce le assunzioni nascoste.

---

## 3. Teoria

### 3.1 Cos'è Foundry

Foundry è una toolchain per sviluppo Ethereum. I componenti che incontreremo nel corso sono principalmente:

- **Forge**: build, test, fuzzing, invariant testing, script, debug;
- **Anvil**: nodo Ethereum locale;
- **Cast**: interazione da CLI con ABI, RPC, chiamate e transazioni;
- **Chisel**: REPL Solidity.

In questa lezione useremo quasi esclusivamente **Forge**.

Il laboratorio resta interamente locale e non richiede RPC esterni.

---

### 3.2 Struttura minima di un progetto

Una struttura tipica è:

```text
lesson-02/
├── foundry.toml
├── src/
│   └── FixedFeeRegistry.sol
├── test/
│   └── FixedFeeRegistry.t.sol
└── lib/
    └── forge-std/
```

Per convenzione i file di test terminano spesso in `.t.sol`.

Forge considera test le funzioni il cui nome inizia con `test`.

Esempi:

```solidity
function test_Register() public { ... }
function test_RevertWhen_FeeIsWrong() public { ... }
```

La documentazione Foundry suggerisce esplicitamente naming leggibili del tipo:

```text
test_RevertIf_Condition
test_RevertWhen_Condition
```

Il nome del test dovrebbe dirti già quale requisito protegge.

---

### 3.3 `forge-std/Test.sol`

Un test Foundry normalmente eredita da `Test`:

```solidity
import {Test} from "forge-std/Test.sol";

contract ExampleTest is Test {
    // ...
}
```

`Test` mette a disposizione:

- assertion come `assertEq`, `assertTrue`, `assertFalse`;
- l'istanza `vm`, attraverso la quale invochiamo i cheatcode;
- utility della standard library di Foundry.

Il termine **cheatcode** non significa “comportamento che esiste on-chain”.

È un'API speciale disponibile nell'ambiente di test per configurare o osservare la EVM di testing.

Esempio:

```solidity
vm.deal(alice, 10 ether);
```

non chiama una funzione del nostro contratto e non rappresenta un meccanismo disponibile a un utente sulla blockchain.

Dice al test runner:

> imposta il saldo ETH di `alice` a 10 ether nello stato locale di test.

Questa distinzione è fondamentale: **mai confondere capacità del test harness con capacità reali di un attaccante**.

---

### 3.4 Arrange → Act → Assert

Un test leggibile può essere pensato in tre fasi.

```text
ARRANGE
preparo contratto, account, bilanci, stato

ACT
eseguo l'operazione che voglio verificare

ASSERT
verifico le proprietà risultanti
```

Esempio:

```solidity
function test_Register_SucceedsWithExactFee() public {
    // Arrange
    vm.deal(ALICE, 10 ether);

    // Act
    vm.prank(ALICE);
    registry.register{value: FEE}();

    // Assert
    assertTrue(registry.registered(ALICE));
}
```

Non è una regola sintattica. È una disciplina di leggibilità.

Un test di sicurezza deve rendere evidente:

1. quale stato iniziale stiamo costruendo;
2. quale identità controlla la chiamata;
3. quale input viene inviato;
4. cosa dovrebbe succedere;
5. cosa non deve cambiare.

---

### 3.5 `vm.prank`: controllare il chiamante nel laboratorio

Nella Lezione 1 abbiamo visto che `msg.sender` è il chiamante diretto del frame corrente.

In un test, se invochi semplicemente:

```solidity
registry.register();
```

il chiamante visto dal contratto sarà normalmente il contratto di test stesso.

Per simulare Alice:

```solidity
vm.prank(ALICE);
registry.register{value: 1 ether}();
```

`vm.prank(address)` modifica `msg.sender` per la **prossima chiamata rilevante**.

Questo permette di testare una proprietà essenziale:

> il comportamento deve essere corretto per identità diverse, non solo per il test contract.

Più avanti useremo anche `startPrank` / `stopPrank` quando una stessa identità deve effettuare più chiamate consecutive.

Per ora `prank` è preferibile perché rende il perimetro dell'impersonazione molto chiaro.

---

### 3.6 `vm.deal`: creare fondi fittizi

Per inviare Ether, l'account di test deve avere saldo sufficiente.

```solidity
vm.deal(ALICE, 10 ether);
```

La firma corrente del cheatcode è concettualmente:

```solidity
function deal(address account, uint256 newBalance) external;
```

Il saldo viene impostato al valore specificato.

Non è un faucet reale, non crea ETH su Ethereum e non interagisce con alcun wallet.

È modifica controllata dello stato locale usata per costruire il caso di test.

---

### 3.7 `vm.expectRevert`: un revert è un risultato atteso

Un test negativo non è un test che “fallisce”.

È un test che passa quando il contratto rifiuta correttamente un'operazione invalida.

Per esempio:

```solidity
vm.expectRevert();
registry.register{value: 0}();
```

significa:

> mi aspetto che la prossima chiamata rilevante faccia revert.

Ma un audit serio preferisce, quando possibile, verificare **quale** errore è avvenuto.

Con un custom error senza argomenti:

```solidity
vm.expectRevert(FixedFeeRegistry.AlreadyRegistered.selector);
```

Con un custom error parametrico possiamo verificare l'intero revert data:

```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        FixedFeeRegistry.ExactFeeRequired.selector,
        sent,
        FEE
    )
);
```

Questo è più forte di un generico “qualcosa ha revertito”.

Perché?

Perché un test troppo generico potrebbe passare per la ragione sbagliata.

Esempio: volevi verificare `ExactFeeRequired`, ma il contratto reverte prima per un bug completamente diverso. Un semplice `expectRevert()` potrebbe comunque dichiarare il test riuscito.

---

### 3.8 Test positivo, test negativo, test di regressione

Questi tre concetti vanno distinti.

#### Test positivo

Verifica che un comportamento valido sia possibile.

```text
Alice paga esattamente 1 ETH -> registrazione riuscita
```

#### Test negativo

Verifica che un comportamento vietato non sia possibile.

```text
Alice paga 0.5 ETH -> revert
Alice paga 2 ETH -> revert
Alice prova a registrarsi due volte -> revert
```

#### Test di regressione

Nasce dopo aver identificato un bug specifico.

Prima riproduce il bug; poi, dopo la correzione, resta nella suite per impedire che la vulnerabilità venga reintrodotta.

Schema:

```text
bug osservato
    |
    v
scrivo test che fallisce
    |
    v
correggo il contratto
    |
    v
lo stesso test passa
    |
    v
il test rimane nella suite
```

Questa disciplina sarà ricorrente in tutte le lezioni sulle vulnerabilità.

---

### 3.9 Un test deve controllare anche gli effetti collaterali

Supponiamo che una chiamata debba revertire.

Non basta verificare solo il revert.

Dobbiamo anche chiederci:

- il contatore è rimasto invariato?
- il mapping è rimasto invariato?
- la contabilità è rimasta invariata?
- l'ETH è stata effettivamente restituita dal revert?

Questo deriva dall'atomicità EVM già introdotta nella Lezione 1.

Un buon test negativo verifica sia:

```text
l'operazione NON ha avuto successo
```

sia:

```text
lo stato dopo il fallimento è quello atteso
```

---

### 3.10 Coverage: utile, ma non equivalente a sicurezza

La code coverage ci dice quali linee, statement o branch sono stati eseguiti dalla suite.

È utile per trovare aree mai esercitate.

Ma:

```text
100% coverage != 100% correttezza
100% coverage != 100% sicurezza
```

Puoi eseguire ogni riga del contratto senza aver verificato le proprietà giuste.

Esempio:

```solidity
if (msg.value < 1 ether) revert();
```

Puoi coprire sia il branch che reverte sia quello che continua, ma se il requisito era **esattamente 1 ETH**, potresti non aver mai testato `2 ether`.

Il codice è “coperto”, ma il requisito non è verificato.

La coverage è quindi una metrica di supporto, non una prova di sicurezza.

---

## 4. Esempio Solidity

Useremo un contratto giocattolo molto semplice.

### Requisito informale

Un indirizzo può registrarsi una sola volta pagando **esattamente 1 ether**.

Il contratto conserva:

- se un indirizzo è registrato;
- il numero di registrazioni riuscite;
- il totale delle fee contabilizzate dal protocollo.

Non esistono prelievi né chiamate esterne in questa lezione: li introdurremo più avanti.

### `src/FixedFeeRegistry.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract FixedFeeRegistry {
    uint256 public constant REGISTRATION_FEE = 1 ether;

    mapping(address account => bool isRegistered) public registered;

    uint256 public registrationCount;
    uint256 public totalReceived;

    error ExactFeeRequired(uint256 sent, uint256 required);
    error AlreadyRegistered(address account);

    event Registered(address indexed account, uint256 amount);

    function register() external payable {
        if (registered[msg.sender]) {
            revert AlreadyRegistered(msg.sender);
        }

        if (msg.value != REGISTRATION_FEE) {
            revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
        }

        registered[msg.sender] = true;
        registrationCount += 1;
        totalReceived += msg.value;

        emit Registered(msg.sender, msg.value);
    }
}
```

### Perché questo contratto è adatto alla lezione

È abbastanza piccolo da poter ragionare sull'intero stato, ma contiene già:

- `msg.sender`;
- `msg.value`;
- `mapping` in storage;
- variabili persistenti;
- custom errors;
- revert;
- evento;
- una proprietà contabile verificabile;
- casi positivi e negativi non banali.

---

## 5. Analisi del codice

### 5.1 `register()`

```solidity
function register() external payable
```

#### Chi può chiamarla?

Chiunque possa effettuare una call al contratto.

Non c'è access control.

Questo è intenzionale: il requisito dice che qualunque account può registrarsi, purché rispetti le regole.

#### Quali input controlla il chiamante?

Non ci sono parametri Solidity espliciti, ma il chiamante controlla comunque due input fondamentali:

```text
msg.sender
msg.value
```

Nel laboratorio simuleremo entrambi.

#### Quale valore entra?

La funzione è `payable`, quindi può ricevere ETH.

Il requisito accetta soltanto:

```text
msg.value == 1 ether
```

Non “almeno 1 ETH”.

Non “fino a 1 ETH”.

Esattamente.

Questo dettaglio diventerà il centro del mutation lab.

#### Quale stato viene letto?

```solidity
registered[msg.sender]
```

Serve per verificare che il chiamante non sia già registrato.

Viene inoltre letto il valore costante:

```solidity
REGISTRATION_FEE
```

#### Quale stato viene modificato?

In caso di successo:

```solidity
registered[msg.sender] = true;
registrationCount += 1;
totalReceived += msg.value;
```

#### Quali chiamate esterne vengono effettuate?

Nessuna.

L'`emit` produce un log, ma non trasferisce controllo a un altro contratto.

#### Quando il controllo passa a codice esterno?

Mai, all'interno di `register()`.

Questo rende il contratto deliberatamente semplice prima di affrontare external calls e reentrancy nelle lezioni successive.

#### Quali assunzioni vengono fatte?

Le assunzioni principali sono:

```text
A1: una registrazione valida richiede fee esatta
A2: un account può registrarsi una sola volta
A3: ogni registrazione riuscita incrementa il conteggio di uno
A4: ogni registrazione riuscita incrementa totalReceived di 1 ether
A5: un revert non deve lasciare modifiche persistenti
```

La suite deve essere costruita per verificare proprio queste assunzioni.

---

### 5.2 Getter pubblici generati dal compilatore

Le dichiarazioni `public` generano getter esterni.

Per esempio:

```solidity
registered(ALICE)
registrationCount()
totalReceived()
REGISTRATION_FEE()
```

Questi getter non modificano lo stato e sono molto utili nei test perché ci permettono di osservare lo stato risultante senza aggiungere funzioni di test al contratto.

Una buona pratica è evitare di contaminare il contratto applicativo con funzioni inserite soltanto per rendere più facile il testing, se lo stato necessario è già osservabile tramite l'interfaccia appropriata.

---

## 6. Proprietà e invarianti

Prima di scrivere i test, trasformiamo il requisito in proprietà.

### P1 — Fee esatta

> Una registrazione può riuscire soltanto quando `msg.value == REGISTRATION_FEE`.

Conseguenze:

```text
0 ether       -> deve fallire
0.5 ether     -> deve fallire
1 ether       -> può riuscire
2 ether       -> deve fallire
```

Notare che testare solo “troppo poco” non è sufficiente.

---

### P2 — Registrazione unica per indirizzo

> Dopo una registrazione riuscita, lo stesso indirizzo non può registrarsi nuovamente.

---

### P3 — Identità indipendenti

> La registrazione di Alice non deve impedire a Bob di registrarsi.

Questo verifica che lo storage sia indicizzato correttamente per account.

---

### P4 — Contatore coerente

> `registrationCount` aumenta esattamente di uno per ogni registrazione riuscita e non cambia per chiamate revertite.

---

### P5 — Contabilità interna coerente

Dato che ogni registrazione riuscita costa esattamente una fee costante:

```text
totalReceived == registrationCount * REGISTRATION_FEE
```

Questa è una vera proprietà del modello applicativo.

La verificheremo esplicitamente nei test.

---

### P6 — Revert atomico

> Una chiamata invalida non deve lasciare `registered`, `registrationCount` o `totalReceived` in uno stato parzialmente modificato.

---

### Una proprietà che NON useremo come invariant di business

Potrebbe sembrare naturale scrivere:

```text
address(registry).balance == totalReceived
```

Ma è una proprietà più fragile della precedente.

Il saldo ETH grezzo di un address non dovrebbe essere assunto automaticamente come unica sorgente di verità per la contabilità applicativa: nell'EVM esistono meccanismi con cui Ether può arrivare a un address senza percorrere la normale funzione applicativa attesa.

Non approfondiamo ancora il tema in questa lezione; ci interessa la lezione metodologica:

> **un invariant deve derivare dal modello che il contratto controlla realmente, non da un'uguaglianza intuitiva ma più forte delle garanzie EVM.**

Per ora useremo:

```text
totalReceived == registrationCount * fee
```

non:

```text
contract balance == totalReceived
```

---

## 7. Laboratorio Foundry

### 7.1 Installazione / aggiornamento

La documentazione ufficiale corrente mostra:

```bash
curl -L https://getfoundry.sh/install | bash
foundryup
```

Poi verifica l'ambiente:

```bash
forge --version
anvil --version
cast --version
```

Se Foundry è già installato, `foundryup` aggiorna la toolchain gestita da Foundry.

---

### 7.2 Creazione del progetto

```bash
forge init lesson-02
cd lesson-02
```

Il template iniziale include la struttura standard. Sostituisci il contratto e il test di esempio con quelli della lezione.

Per il corso useremo questo `foundry.toml` minimale:

```toml
[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
solc_version = "0.8.37"
optimizer = true
optimizer_runs = 200
```

Puoi controllare la configurazione risolta con:

```bash
forge config
```

---

### 7.3 Contratto

Crea:

```text
src/FixedFeeRegistry.sol
```

con il codice visto nella sezione 4.

---

### 7.4 Test completo

Crea:

```text
test/FixedFeeRegistry.t.sol
```

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {FixedFeeRegistry} from "../src/FixedFeeRegistry.sol";

contract FixedFeeRegistryTest is Test {
    FixedFeeRegistry internal registry;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    uint256 internal constant FEE = 1 ether;

    function setUp() public {
        registry = new FixedFeeRegistry();

        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    function test_InitialState() public view {
        assertFalse(registry.registered(ALICE));
        assertFalse(registry.registered(BOB));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);
        assertEq(registry.REGISTRATION_FEE(), FEE);
    }

    function test_Register_SucceedsWithExactFee() public {
        vm.prank(ALICE);
        registry.register{value: FEE}();

        assertTrue(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 1);
        assertEq(registry.totalReceived(), FEE);

        _assertAccountingProperty();
    }

    function test_Register_TwoDifferentAccountsRemainIndependent() public {
        vm.prank(ALICE);
        registry.register{value: FEE}();

        vm.prank(BOB);
        registry.register{value: FEE}();

        assertTrue(registry.registered(ALICE));
        assertTrue(registry.registered(BOB));
        assertEq(registry.registrationCount(), 2);
        assertEq(registry.totalReceived(), 2 * FEE);

        _assertAccountingProperty();
    }

    function test_RevertWhen_FeeIsZero() public {
        uint256 sent = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                FixedFeeRegistry.ExactFeeRequired.selector,
                sent,
                FEE
            )
        );

        vm.prank(ALICE);
        registry.register{value: sent}();

        assertFalse(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);

        _assertAccountingProperty();
    }

    function test_RevertWhen_FeeIsTooLow() public {
        uint256 sent = 0.5 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                FixedFeeRegistry.ExactFeeRequired.selector,
                sent,
                FEE
            )
        );

        vm.prank(ALICE);
        registry.register{value: sent}();

        assertFalse(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);

        _assertAccountingProperty();
    }

    function test_RevertWhen_FeeIsTooHigh() public {
        uint256 sent = 2 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                FixedFeeRegistry.ExactFeeRequired.selector,
                sent,
                FEE
            )
        );

        vm.prank(ALICE);
        registry.register{value: sent}();

        assertFalse(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);

        _assertAccountingProperty();
    }

    function test_RevertWhen_AccountRegistersTwice() public {
        vm.prank(ALICE);
        registry.register{value: FEE}();

        vm.expectRevert(
            abi.encodeWithSelector(
                FixedFeeRegistry.AlreadyRegistered.selector,
                ALICE
            )
        );

        vm.prank(ALICE);
        registry.register{value: FEE}();

        assertTrue(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 1);
        assertEq(registry.totalReceived(), FEE);

        _assertAccountingProperty();
    }

    function _assertAccountingProperty() internal view {
        assertEq(
            registry.totalReceived(),
            registry.registrationCount() * FEE
        );
    }
}
```

---

### 7.5 Formattazione e build

```bash
forge fmt
forge build
```

`forge fmt` riduce rumore stilistico nelle review.

`forge build` deve terminare senza errori prima di interpretare qualsiasi risultato di test.

---

### 7.6 Esecuzione della suite

```bash
forge test
```

Il risultato atteso è che tutti i test passino.

Foundry mostrerà una suite con test `PASS` e zero failure.

Non memorizzare i numeri di gas del mio esempio: dipendono da versione del compilatore, optimizer e toolchain.

Quello che conta è il comportamento.

---

### 7.7 Eseguire un solo test

```bash
forge test --match-test test_RevertWhen_FeeIsTooHigh
```

Oppure filtrare il contratto di test:

```bash
forge test --match-contract FixedFeeRegistryTest
```

Questo è molto utile durante l'audit: quando stai indagando una proprietà, vuoi un ciclo rapido e mirato.

---

### 7.8 Leggere le trace

Per un test fallito:

```bash
forge test -vvv
```

La documentazione Foundry associa ai livelli di verbosity informazioni progressivamente più dettagliate.

Per vedere trace anche dei test riusciti:

```bash
forge test -vvvv --match-test test_Register_SucceedsWithExactFee
```

Mentalmente cerca nella trace:

```text
FixedFeeRegistryTest
  |
  | vm.prank(ALICE)
  |
  +--> FixedFeeRegistry.register{value: 1 ether}()
          |
          +--> lettura registered[ALICE]
          +--> scritture storage
          +--> emit Registered
          +--> return
```

Per un revert:

```text
FixedFeeRegistryTest
  |
  | vm.expectRevert(...)
  | vm.prank(ALICE)
  |
  +--> FixedFeeRegistry.register{value: 2 ether}()
          |
          +--> fee != expected
          +--> REVERT ExactFeeRequired(...)
```

Allenati a leggere le trace come una call tree, non come semplice output di debug.

Questa abilità diventerà essenziale quando avremo chiamate annidate e reentrancy.

---

### 7.9 Debugger interattivo

Foundry espone anche un debugger:

```bash
forge test --debug --match-test "test_RevertWhen_FeeIsTooHigh"
```

Non è necessario capirne ogni dettaglio oggi.

Usalo però almeno una volta per vedere che il test non è una black box: puoi scendere fino all'esecuzione EVM e osservare il flusso delle istruzioni.

---

### 7.10 Coverage

Esegui:

```bash
forge coverage
```

Usa il report come domanda:

> esistono rami importanti che non ho mai esercitato?

Non usarlo come conclusione:

> ho alta coverage, quindi il contratto è sicuro.

Quella conclusione sarebbe metodologicamente errata.

---

## 8. Test negativi

I test negativi della suite sono intenzionalmente ridondanti rispetto all'happy path.

### Caso 1 — zero Ether

```text
input: 0 ETH
atteso: ExactFeeRequired
stato finale: nessuna registrazione
```

Verifica il confine inferiore più ovvio.

---

### Caso 2 — fee insufficiente

```text
input: 0.5 ETH
atteso: ExactFeeRequired
```

Serve a distinguere `==` da controlli errati che accettano importi troppo bassi.

---

### Caso 3 — fee eccessiva

```text
input: 2 ETH
atteso: ExactFeeRequired
```

Questo caso è particolarmente importante.

Se il requisito è “esattamente”, allora “più del minimo” deve essere esplicitamente testato.

---

### Caso 4 — doppia registrazione

```text
prima call: successo
seconda call: revert AlreadyRegistered
```

Dopo il revert controlliamo:

```text
registrationCount == 1
totalReceived == 1 ether
registered[ALICE] == true
```

Non basta sapere che la seconda call ha fallito.

Vogliamo sapere che non ha corrotto la contabilità.

---

### Caso 5 — separazione tra utenti

Alice registrata non implica Bob registrato.

```text
registered[ALICE] == true
registered[BOB] == false
```

Poi Bob deve poter effettuare la propria registrazione.

Questo è un test semplice contro errori di storage/logica che trasformerebbero uno stato per-account in uno stato globale.

---

## 9. Errore di progettazione: mutation lab locale

Questa sezione non attacca alcun sistema reale.

Modifichiamo intenzionalmente il nostro contratto giocattolo per valutare se la suite riesce a riconoscere un errore.

### 9.1 Versione errata

Sostituisci temporaneamente:

```solidity
if (msg.value != REGISTRATION_FEE) {
    revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
}
```

con:

```solidity
if (msg.value < REGISTRATION_FEE) {
    revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
}
```

Ora la logica significa:

```text
meno di 1 ETH -> rifiuta
1 ETH o più   -> accetta
```

Ma la specifica diceva:

```text
esattamente 1 ETH
```

È quindi un bug di implementazione rispetto al requisito.

---

### 9.2 Quale test deve accorgersene?

Esegui:

```bash
forge test --match-test test_RevertWhen_FeeIsTooHigh -vvvv
```

La call con `2 ether` non reverterà.

Il test fallirà perché aveva dichiarato:

```solidity
vm.expectRevert(...);
```

ma il contratto ha proseguito.

Questa è una dimostrazione molto importante:

> **un test è utile quando esiste almeno una implementazione plausibilmente sbagliata che quel test riesce a distinguere da quella corretta.**

---

### 9.3 Perché il solo happy path non sarebbe bastato

Con la versione errata:

```solidity
if (msg.value < REGISTRATION_FEE) revert ...;
```

il test:

```solidity
test_Register_SucceedsWithExactFee()
```

continuerebbe a passare.

Anche il test “fee troppo bassa” continuerebbe a passare.

Senza il caso “fee troppo alta”, la suite potrebbe non rilevare la differenza tra:

```solidity
msg.value == FEE
```

e:

```solidity
msg.value >= FEE
```

Questa è la ragione per cui i confini devono essere testati da entrambi i lati.

---

### 9.4 Correzione

Ripristina:

```solidity
if (msg.value != REGISTRATION_FEE) {
    revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
}
```

Poi:

```bash
forge test
```

La suite deve tornare verde.

`test_RevertWhen_FeeIsTooHigh` è ora un **test di regressione**: impedisce che in futuro qualcuno sostituisca involontariamente “fee esatta” con “fee minima”.

---

### 9.5 Prima / dopo

```text
REQUISITO
fee == 1 ETH

IMPLEMENTAZIONE ERRATA
fee >= 1 ETH

TEST CHE LA SCOPRE
2 ETH deve revertire

CORREZIONE
fee != 1 ETH -> revert

REGRESSIONE
il test resta permanentemente nella suite
```

Questa sequenza sarà il modello delle future lezioni sulle vulnerabilità vere e proprie.

---

## 10. Checklist da auditor

Quando leggi un contratto e la relativa suite di test, prova a percorrere questa checklist breve.

### Specifica

- Riesco a scrivere in una frase cosa deve garantire ogni funzione importante?
- I termini “esattamente”, “almeno”, “al massimo”, “una sola volta”, “solo owner” sono trasformati in test distinti?

### Caller e valore

- Esistono test con chiamanti differenti?
- I test verificano davvero `msg.sender`, oppure tutte le chiamate partono accidentalmente dal test contract?
- Le funzioni `payable` sono testate con zero, valore valido e valori fuori intervallo?

### Revert

- I casi vietati sono testati?
- Il test verifica l'errore corretto quando è utile?
- Dopo il revert viene verificato che lo stato non sia cambiato?

### Stato

- I contatori e mapping sono controllati dopo ogni transizione importante?
- La suite verifica separazione tra utenti?
- Esistono proprietà contabili che possono essere espresse come uguaglianze?

### Qualità della suite

- Posso immaginare una piccola mutazione sbagliata che tutti i test lascerebbero passare?
- Sto usando coverage come strumento diagnostico o come falsa prova di sicurezza?
- Ogni bug corretto ha un test di regressione?

---

## 11. Esercizi

### Esercizio 1 — Stato invariato dopo revert

Nel test `test_RevertWhen_FeeIsTooHigh`, salva prima della call:

```text
balance ETH di ALICE
balance ETH del registry
```

Poi verifica cosa osservi dopo il revert.

Spiega perché il trasferimento di `msg.value` non resta applicato quando la call reverte.

---

### Esercizio 2 — Test che manca

Aggiungi un test che controlli esplicitamente questo scenario:

```text
Alice prova prima con fee sbagliata -> revert
Alice riprova con fee corretta -> successo
```

Proprietà che stai verificando:

> un tentativo fallito non deve “consumare” il diritto futuro alla registrazione.

---

### Esercizio 3 — Mutazione sulla registrazione

Commenta temporaneamente:

```solidity
registered[msg.sender] = true;
```

Prevedi prima di eseguire Foundry quali test falliranno e quali potrebbero ancora passare.

Poi verifica la previsione.

Questo esercizio serve ad allenare il rapporto:

```text
linea di codice <-> proprietà protetta <-> test che la osserva
```

---

### Esercizio 4 — Mutazione sul contatore

Sostituisci temporaneamente:

```solidity
registrationCount += 1;
```

con:

```solidity
registrationCount += 2;
```

Quali test rilevano il problema?

La helper property:

```solidity
_assertAccountingProperty()
```

aggiunge valore rispetto ai soli assert locali?

Motiva la risposta.

---

### Esercizio 5 — Errore troppo generico

Sostituisci in un test:

```solidity
vm.expectRevert(
    abi.encodeWithSelector(...)
);
```

con:

```solidity
vm.expectRevert();
```

Poi introduci nel contratto un revert precedente e non correlato.

Osserva come un test generico può passare pur non verificando più la causa che volevi proteggere.

---

### Esercizio 6 — Specifica prima del codice

Senza implementarla, definisci proprietà e test per questa nuova regola:

> dopo 100 registrazioni il registry non deve più accettarne altre.

Scrivi soltanto:

1. requisiti;
2. proprietà;
3. nomi dei test;
4. casi di confine.

Non modificare ancora il contratto.

L'obiettivo è abituarti a progettare la suite dalla specifica.

---

### Esercizio 7 — Audit della suite

Supponi che esistano soltanto questi due test:

```text
test_Register_SucceedsWithExactFee
test_RevertWhen_AccountRegistersTwice
```

Elenca almeno tre implementazioni errate che potrebbero plausibilmente non essere scoperte.

Non cercare vulnerabilità esotiche: resta sul requisito della lezione.

---

## 12. Cosa devo ricordare

Se devi portare via pochi concetti da questa lezione, devono essere questi.

### 1. I test nascono dalla specifica

Non chiederti soltanto:

```text
"il codice fa quello che ho scritto?"
```

Chiediti:

```text
"il codice garantisce ciò che il protocollo richiede?"
```

---

### 2. L'happy path è solo l'inizio

Un contratto sicuro deve rifiutare correttamente anche input e transizioni vietate.

I test negativi sono parte centrale della sicurezza.

---

### 3. `vm.prank` e `vm.deal` costruiscono il contesto del laboratorio

Ti permettono di controllare identità e fondi fittizi senza interagire con utenti o reti reali.

---

### 4. Un revert deve essere verificato anche nei suoi effetti

Dopo un fallimento, controlla che lo stato importante sia rimasto coerente.

---

### 5. Preferisci proprietà forti a controlli superficiali

```text
totalReceived == registrationCount * fee
```

è più informativo di controllare soltanto un singolo valore in un singolo scenario.

---

### 6. Coverage non significa sicurezza

La coverage ti dice quali percorsi hai eseguito, non se hai formulato le proprietà corrette.

---

### 7. Un bug corretto deve lasciare un test di regressione

Il fix senza regressione test può essere reintrodotto in futuro.

---

### 8. Una buona domanda sulla suite è: “quale mutazione sbagliata sopravvive?”

Se riesci a cambiare la semantica importante del contratto e tutti i test continuano a passare, hai trovato una lacuna della suite.

---

## 13. Fonti della lezione

Fonti tecniche consultate e verificate per questa lezione il **21 settembre 2026**:

1. **Foundry — sito e installazione ufficiale**  
   https://www.getfoundry.sh/  
   Usato per verificare il comando di installazione corrente e il ruolo di Forge, Anvil, Cast e Chisel.

2. **Foundry — Writing Tests**  
   https://getfoundry.sh/forge/writing-tests  
   Usato per verificare `setUp()`, naming dei test, prefisso `test` e convenzioni sui test che si aspettano revert.

3. **Foundry — Tests / `forge test`**  
   https://getfoundry.sh/forge/tests  
   Usato per verificare esecuzione dei test, filtri `--match-test` / `--match-contract` e livelli di verbosity.

4. **Foundry — Forge Standard Library**  
   https://getfoundry.sh/reference/forge-std/overview  
   Usato per verificare l'uso raccomandato di `forge-std/Test.sol` e dell'istanza `vm`.

5. **Foundry — `prank` cheatcode**  
   https://getfoundry.sh/reference/cheatcodes/prank/  
   Usato per verificare la semantica di `vm.prank(address)` sulla chiamata successiva.

6. **Foundry — `expectRevert` cheatcode**  
   https://getfoundry.sh/cheatcodes/expect-revert  
   Usato per verificare le forme correnti di `expectRevert`, il matching dei custom errors e le note sulla call depth.

7. **Foundry — cheatcode interface / `deal`**  
   https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/spec/src/vm.rs  
   Usato per verificare la firma corrente `deal(address account, uint256 newBalance)`.

8. **Foundry — Debugger**  
   https://getfoundry.sh/forge/debugger  
   Usato per verificare la sintassi `forge test --debug --match-test ...`.

9. **Foundry — Understanding Traces**  
   https://getfoundry.sh/forge/traces  
   Usato per interpretare la struttura delle trace e la relazione tra livelli di verbosity e call tree.

10. **Foundry — Configuration**  
    https://www.getfoundry.sh/config/index.html  
    Usato per verificare `foundry.toml`, `solc_version` e `forge config`.

11. **Ethereum.org — Testing smart contracts**  
    https://ethereum.org/developers/docs/smart-contracts/testing/  
    Usato per il ruolo dei test unitari, della coverage e della combinazione di più tecniche di testing nella sicurezza degli smart contract.

12. **Ethereum.org — Smart contract security**  
    https://ethereum.org/developers/docs/smart-contracts/security/  
    Usato come riferimento per il principio che il testing è necessario ma non sufficiente se isolato da altre tecniche di assurance.

13. **Solidity — Error handling: assert, require, revert and exceptions**  
    https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions  
    Usato per verificare la semantica dei revert e la distinzione tra condizioni esterne e invariant/internal errors.

14. **Solidity — Custom Errors**  
    https://docs.soliditylang.org/en/latest/contracts.html#custom-errors  
    Usato per la rappresentazione e l'impiego dei custom errors nei test.

15. **Solidity 0.8.37 Release Announcement**  
    https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/  
    Usato per verificare la baseline del compilatore adottata nel corso e i bugfix inclusi nella release del 10 settembre 2026.

---

## Fine Lezione 2

La lezione successiva introdurrà il progetto conduttore **Escrow** e la sua **macchina a stati**, ma non viene sviluppata qui: il corso prosegue soltanto quando chiedi esplicitamente la lezione successiva.
