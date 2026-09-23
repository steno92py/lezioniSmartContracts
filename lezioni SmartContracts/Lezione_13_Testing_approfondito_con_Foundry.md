# Lezione 13 — Testing approfondito con Foundry

> **Scopo:** testing difensivo, secure coding, regressione e preparazione all'audit.
>
> Tutti gli esempi restano confinati a **Foundry/Anvil locale**, account di test e contratti giocattolo.
>
> In questa lezione non introduciamo una nuova grande vulnerabilità. Costruiamo invece una disciplina di test robusta per il protocollo Escrow sviluppato finora.

---

# Obiettivi, modello mentale e categorie di test

## 1. Obiettivi

Alla fine della lezione dovresti saper:

- strutturare una suite Foundry leggibile e manutenibile;
- distinguere:
  - unit test;
  - integration test;
  - regression test;
  - negative test;
  - property-oriented test;
- progettare `setUp()` e fixture senza nascondere troppo contesto;
- usare correttamente:
  - `vm.prank`;
  - `vm.startPrank`;
  - `vm.stopPrank`;
  - `vm.deal`;
  - `makeAddr`;
  - `vm.warp`;
  - `vm.expectRevert`;
  - `vm.expectEmit`;
  - `vm.mockCall`;
- verificare custom error con precisione;
- evitare false confidence derivante da `expectRevert()` troppo generico;
- testare eventi senza usarli come unica prova dello stato;
- testare chiamate esterne e dependency failure;
- organizzare helper e factory per non duplicare codice;
- leggere una trace Foundry per capire il call flow;
- usare `forge coverage` in modo corretto;
- capire perché alta coverage non equivale a alta qualità;
- applicare mutation thinking per valutare la forza della suite;
- costruire una regression matrix requisito → test;
- preparare il terreno per fuzzing e invariant testing delle lezioni successive.

---

## 2. Modello mentale

Il testing di sicurezza non è:

```text
"dimostrare che il contratto funziona"
```

È:

```text
definire proprietà
        |
        v
costruire esempi che le verificano
        |
        v
costruire controesempi che provano a romperle
        |
        v
controllare failure mode
        |
        v
aggiungere regressioni per bug trovati
```

Un buon test non verifica soltanto:

```text
"questa funzione restituisce X"
```

ma cerca di rispondere:

```text
chi poteva chiamarla?
quale stato esisteva prima?
quale stato deve esistere dopo?
cosa NON deve essere cambiato?
quale errore deve emergere?
quale dipendenza esterna è stata coinvolta?
```

---

## 3. Testing e specifica

Consideriamo una proprietà dell'Escrow:

> Solo il buyer può effettuare il funding.

Questa frase genera almeno due test:

```text
buyer -> fund -> success
stranger -> fund -> revert
```

Ma possiamo andare oltre:

```text
buyer -> fund una volta -> success
buyer -> fund di nuovo -> revert
```

Poi:

```text
stranger con moltissimi token
+ allowance sufficiente
-> deve comunque fallire
```

Il punto è importante:

> **Il test nasce dalla proprietà, non dalla funzione.**

---

## 4. Le categorie di test

### Unit test

Isola una piccola unità.

Esempio:

```text
setFee(250)
```

e verifica:

```text
feeBps = 250
```

---

### Negative test

Verifica ciò che deve fallire.

Esempio:

```text
stranger -> setFee
=> revert
```

---

### Regression test

Nasce dopo un bug reale o simulato.

Esempio:

```text
bug:
return value ERC20 ignorato

regression:
false-returning token
non può creare credito
```

---

### Integration test

Verifica l'interazione tra più componenti.

Esempio:

```text
Escrow
+
ERC20
+
Oracle mock
+
Timelock
```

---

### Property-oriented test

Non è ancora fuzzing necessariamente.

È un test scritto attorno a una proprietà generale.

Esempio:

```text
dopo release:
escrowedAmount == 0
```

indipendentemente dal fatto che il test usi un singolo valore concreto.

---

# Anatomia di una suite Foundry

## 5. Anatomia di una suite Foundry

Struttura consigliata:

```text
test/
├── unit/
│   ├── EscrowDeposit.t.sol
│   ├── EscrowRelease.t.sol
│   ├── AccessControl.t.sol
│   └── Governance.t.sol
├── integration/
│   ├── EscrowERC20.t.sol
│   ├── EscrowOracle.t.sol
│   └── UpgradeFlow.t.sol
├── regression/
│   ├── ReentrancyRegression.t.sol
│   ├── FalseReturnTokenRegression.t.sol
│   └── StorageLayoutRegression.t.sol
├── mocks/
│   ├── TestToken.sol
│   ├── FeeToken.sol
│   ├── RevertingNotifier.sol
│   └── MockOracle.sol
└── helpers/
    └── EscrowTestBase.sol
```

Non è obbligatoria.

Il principio è:

```text
la struttura deve rendere chiaro
cosa stai testando e perché
```

---

## 6. `Test.sol`

Il modo standard di scrivere test Foundry è:

```solidity
import {Test} from "forge-std/Test.sol";
```

e:

```solidity
contract EscrowTest is Test {
    ...
}
```

`Test` fornisce:

- assertions;
- cheatcode interface `vm`;
- utility Forge Std;
- logging;
- helper.

Esempio:

```solidity
assertEq(
    escrow.amount(),
    100
);
```

---

## 7. `setUp()`

Foundry esegue:

```solidity
function setUp() public
```

prima di ogni test.

Esempio:

```solidity
contract EscrowTest is Test {
    Escrow escrow;

    address buyer =
        makeAddr("buyer");

    address seller =
        makeAddr("seller");

    function setUp() public {
        escrow =
            new Escrow(
                buyer,
                seller
            );
    }
}
```

Ogni test parte da uno stato pulito derivato dal setup.

---

## 8. Cosa mettere nel `setUp`

Buoni candidati:

```text
deploy comune
account comuni
mint iniziale standard
configurazione di base
```

Cattivi candidati:

```text
50 operazioni che nascondono
lo stato iniziale reale
```

Un `setUp()` troppo complesso rende difficile capire:

```text
perché questo test passa?
```

---

## 9. Helper espliciti

Meglio:

```solidity
function _fund(
    uint256 amount
) internal {
    vm.prank(buyer);
    escrow.fund(amount);
}
```

che ripetere continuamente:

```solidity
vm.prank(buyer);
escrow.fund(100);
```

Ma non spingere l'astrazione troppo lontano.

Questo è poco leggibile:

```solidity
_prepareScenario(
    3,
    true,
    false,
    2,
    address(0)
);
```

Il test deve restare comprensibile.

---

## 10. Arrange — Act — Assert

Una struttura utile:

```text
Arrange
Act
Assert
```

Esempio:

```solidity
function test_BuyerCanFund()
    public
{
    // Arrange
    uint256 amount = 100;

    // Act
    vm.prank(buyer);
    escrow.fund(amount);

    // Assert
    assertEq(
        escrow.amount(),
        amount
    );

    assertTrue(
        escrow.funded()
    );
}
```

Non è una regola sintattica.

È una disciplina mentale.

---

## 11. Given — When — Then

Per test più orientati alla specifica:

```text
Given
    Escrow is Created

When
    buyer funds 100

Then
    state == Funded
    amount == 100
```

Può aiutare a scrivere nomi di test migliori.

---

## 12. Naming dei test

Preferisci nomi che descrivono la proprietà.

Esempi:

```solidity
test_BuyerCanFund()
test_StrangerCannotFund()
test_CannotFundTwice()
test_ReleaseClearsLiability()
test_StaleOraclePriceReverts()
test_UpgradePreservesBuyer()
```

Evita:

```text
test1
testWorks
testEscrow
```

Il nome è parte della documentazione.

---

# Cheatcodes: identità, fondi e tempo

## 13. `makeAddr`

Forge Std consente:

```solidity
address buyer =
    makeAddr("buyer");
```

Vantaggio:

```text
address deterministic
nome leggibile nelle trace
```

Molto meglio di:

```solidity
address(0x1234)
```

quando stai costruendo scenari di test.

---

## 14. `vm.prank`

`vm.prank(address)` modifica:

```text
msg.sender
```

per la **prossima call**.

Esempio:

```solidity
vm.prank(buyer);

escrow.fund(100);
```

Dentro `fund()`:

```text
msg.sender = buyer
```

Poi l'effetto termina.

---

## 15. Un dettaglio importante su `prank`

Il "next call" è letterale.

Questo può essere pericoloso:

```solidity
vm.prank(buyer);

uint256 x =
    token.balanceOf(buyer);

escrow.deposit(100);
```

Il prank può applicarsi alla `balanceOf`, non alla call che avevi mentalmente associato.

Quindi mantieni:

```solidity
vm.prank(buyer);
escrow.deposit(100);
```

vicine.

---

## 16. `startPrank`

Per più chiamate consecutive:

```solidity
vm.startPrank(buyer);

token.approve(
    address(escrow),
    100
);

escrow.deposit(100);

vm.stopPrank();
```

Durante l'intervallo:

```text
msg.sender = buyer
```

per le call interessate.

---

## 17. Non dimenticare `stopPrank`

Questo test è pericoloso:

```solidity
vm.startPrank(owner);

adminAction1();
adminAction2();

// stopPrank mancante

userAction();
```

`userAction()` viene ancora eseguita come owner.

La suite può produrre falsi positivi.

Buona abitudine:

```solidity
vm.startPrank(x);

// blocco breve e coeso

vm.stopPrank();
```

---

## 18. Testare caller e `tx.origin`

Foundry permette anche di configurare:

```text
msg.sender
tx.origin
```

con overload di `prank`.

Ma per la maggior parte dei test di authorization basta controllare:

```text
msg.sender
```

Non introdurre `tx.origin` se non stai testando esplicitamente quella semantica.

---

## 19. `vm.deal`

Per assegnare Ether a un account di test:

```solidity
vm.deal(
    buyer,
    10 ether
);
```

Poi:

```solidity
assertEq(
    buyer.balance,
    10 ether
);
```

Questo modifica lo stato del test locale.

Non crea una transazione reale.

---

## 20. `hoax`

Forge Std offre utility come `hoax` che combinano:

```text
deal
+
prank
```

Sono comode.

Ma durante l'apprendimento preferisco spesso separare esplicitamente:

```solidity
vm.deal(...)
vm.prank(...)
```

così è chiaro quale proprietà stiamo manipolando.

---

## 21. `vm.warp`

Per testare tempo:

```solidity
vm.warp(
    block.timestamp + 2 days
);
```

Usato per:

```text
oracle freshness
timelock
deadline
vesting
cooldown
```

Ricorda:

```text
warp cambia il timestamp locale del test
```

Non è "attendere realmente".

---

# Boundary, revert precisi e stato dopo il revert

## 22. Boundary tests

Ogni volta che vedi:

```solidity
if (x > limit)
```

testa almeno:

```text
limit - 1
limit
limit + 1
```

Esempio:

```text
fee <= 1000
```

Test:

```text
999  -> success
1000 -> success
1001 -> revert
```

Molti bug logici sono:

```text
>
vs
>=
```

---

## 23. `expectRevert()`

La forma più generica:

```solidity
vm.expectRevert();

escrow.fund(100);
```

significa:

```text
la prossima call deve revertire
per qualsiasi motivo
```

È utile per esplorazione.

Ma è debole come regression test.

---

## 24. Perché `expectRevert()` generico può nascondere bug

Supponiamo di voler verificare:

```text
stranger non può fund
```

Scriviamo:

```solidity
vm.prank(stranger);
vm.expectRevert();
escrow.fund(100);
```

Passa.

Ora immagina che `OnlyBuyer` sia stato accidentalmente rimosso, ma la funzione revirti per:

```text
division by zero
```

Il test continua a passare.

La proprietà di authorization è rotta, ma non lo sappiamo.

---

## 25. Custom error preciso

Contratto:

```solidity
error OnlyBuyer();
```

Test:

```solidity
vm.prank(stranger);

vm.expectRevert(
    Escrow.OnlyBuyer.selector
);

escrow.fund(100);
```

Ora il test verifica:

```text
fallimento
+
causa attesa
```

È molto più forte.

---

## 26. Custom error con argomenti

Contratto:

```solidity
error Unauthorized(
    address caller
);
```

Test:

```solidity
vm.prank(stranger);

vm.expectRevert(
    abi.encodeWithSelector(
        Escrow.Unauthorized.selector,
        stranger
    )
);

escrow.adminAction();
```

Così verifichi anche il payload.

---

## 27. `expectPartialRevert`

Foundry corrente espone anche:

```solidity
vm.expectPartialRevert(
    CustomError.selector
);
```

Utile quando vuoi controllare il selector del custom error senza imporre l'intero payload.

Usalo consapevolmente.

Se gli argomenti fanno parte della proprietà, preferisci verificarli.

---

## 28. Footgun di `expectRevert`

Foundry documenta un dettaglio importante:

```text
expectRevert riguarda la prossima call
al call depth appropriato
```

Esempio fragile:

```solidity
vm.expectRevert();

escrow.deposit(
    token.balanceOf(user)
);
```

La prima external/static call potrebbe essere:

```text
token.balanceOf(user)
```

non:

```text
escrow.deposit(...)
```

Meglio:

```solidity
uint256 amount =
    token.balanceOf(user);

vm.expectRevert();

escrow.deposit(amount);
```

Questo aumenta la precisione.

---

## 29. Testare lo stato dopo un revert

Non fermarti a:

```text
reverted
```

Verifica che lo stato sia rimasto corretto.

Esempio:

```solidity
uint256 beforeAmount =
    escrow.amount();

vm.prank(stranger);

vm.expectRevert(
    Escrow.OnlyBuyer.selector
);

escrow.fund(100);

assertEq(
    escrow.amount(),
    beforeAmount
);
```

Questo verifica anche l'atomicità della failure path.

---

## 30. State delta thinking

Per ogni funzione pensa:

```text
state before
        |
        v
call
        |
        v
state after
```

Testa:

```text
cosa deve cambiare
+
cosa non deve cambiare
```

Esempio `release()`:

```text
state:
Funded -> Released

amount:
100 -> 0

seller balance:
0 -> 100

buyer:
unchanged

oracle:
unchanged
```

---

# Eventi, assertion e helper

## 31. Event testing

Gli eventi sono importanti per:

```text
indexing
monitoring
frontend
audit trail
```

Foundry permette:

```solidity
vm.expectEmit(...);
```

Poi emetti nel test l'evento atteso:

```solidity
emit FeeUpdated(
    oldFee,
    newFee
);
```

e chiami il contratto.

---

## 32. Esempio `expectEmit`

Contratto:

```solidity
event FeeUpdated(
    uint256 oldFee,
    uint256 newFee
);
```

Test:

```solidity
function test_SetFeeEmitsEvent()
    public
{
    vm.expectEmit();

    emit FeeUpdated(
        0,
        250
    );

    vm.prank(owner);

    escrow.setFee(250);
}
```

In casi reali puoi configurare quali topic/data confrontare.

---

## 33. Evento != stato

Questo test è insufficiente:

```text
evento FeeUpdated(0, 250) emesso
```

perché una implementation buggy potrebbe fare:

```solidity
emit FeeUpdated(
    feeBps,
    newFee
);

// BUG:
feeBps non cambia
```

Quindi:

```solidity
assertEq(
    escrow.feeBps(),
    250
);
```

deve accompagnare il test dell'evento.

Regola:

> Eventi descrivono ciò che il contratto dichiara; lo storage dimostra ciò che è realmente persistito.

---

## 34. Testare balance delta

Ether:

```solidity
uint256 beforeBalance =
    seller.balance;

vm.prank(buyer);
escrow.release();

assertEq(
    seller.balance,
    beforeBalance + amount
);
```

Token:

```solidity
uint256 beforeToken =
    token.balanceOf(seller);

...

assertEq(
    token.balanceOf(seller),
    beforeToken + amount
);
```

Preferisci delta a valori assoluti quando lo stato iniziale può cambiare.

---

## 35. `assertEq`, `assertTrue`, `assertFalse`

Test precisi:

```solidity
assertEq(
    escrow.amount(),
    100
);

assertTrue(
    escrow.funded()
);

assertFalse(
    escrow.paused()
);
```

Una assertion dovrebbe corrispondere a una proprietà comprensibile.

---

## 36. Assert con messaggio

Puoi usare:

```solidity
assertEq(
    actual,
    expected,
    "amount must be preserved"
);
```

Utile quando una failure potrebbe essere ambigua.

Ma nomi di test e variabili leggibili spesso riducono la necessità di lunghi messaggi.

---

## 37. Test helper base

Possiamo creare:

### `test/helpers/EscrowTestBase.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from
    "forge-std/Test.sol";

import {
    TestToken
} from "../mocks/TestToken.sol";

import {
    TokenEscrow
} from "../../src/TokenEscrow.sol";

abstract contract EscrowTestBase
    is Test
{
    TestToken internal token;
    TokenEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal stranger;

    function setUp()
        public
        virtual
    {
        buyer =
            makeAddr("buyer");

        seller =
            makeAddr("seller");

        stranger =
            makeAddr("stranger");

        token =
            new TestToken();

        escrow =
            new TokenEscrow(
                token,
                buyer,
                seller
            );

        token.mint(
            buyer,
            1_000 ether
        );
    }

    function _approveAndDeposit(
        uint256 amount
    ) internal {
        vm.startPrank(buyer);

        token.approve(
            address(escrow),
            amount
        );

        escrow.deposit(amount);

        vm.stopPrank();
    }
}
```

Ora più file possono ereditare il setup comune.

---

## 38. Attenzione agli helper che fanno troppe cose

Questo helper:

```solidity
_preparePerfectScenario()
```

potrebbe:

```text
mint
approve
deposit
warp
set oracle
schedule governance
```

Il test perde leggibilità.

Meglio piccoli helper semantici:

```text
_approveAndDeposit()
_scheduleUpgrade()
_makeOracleFresh()
_pause()
```

---

# Mock, dipendenze e regression test

## 39. Unit test vs integration test

### Unit

Puoi isolare:

```text
PriceConsumer
```

da un vero mock oracle.

### Integration

Puoi testare:

```text
TokenEscrow
+
real TestToken
+
real TimelockController
+
mock oracle
```

La distinzione non è:

```text
mock = unit
no mock = integration
```

È:

```text
quante boundary del sistema
stai verificando insieme?
```

---

## 40. Mock contract

Esempio:

```solidity
contract RevertingOracle {
    function latestPrice()
        external
        pure
        returns (
            int256,
            uint256
        )
    {
        revert("oracle down");
    }
}
```

Utile quando vuoi modellare:

```text
behavior
state
callback
revert
```

---

## 41. `vm.mockCall`

Foundry permette anche:

```solidity
vm.mockCall(
    target,
    calldata,
    returndata
);
```

Esempio:

```solidity
vm.mockCall(
    address(oracle),
    abi.encodeCall(
        IPriceOracle.latestPrice,
        ()
    ),
    abi.encode(
        int256(3000e8),
        block.timestamp
    )
);
```

Poi una call compatibile riceverà quel risultato.

---

## 42. Quando preferire `mockCall`

Utile per:

```text
unit test molto isolato
return deterministico
failure injection semplice
```

Preferisci un mock contract quando vuoi:

```text
stato interno
sequenze
modalità dinamiche
reentrancy/callback
più funzioni coordinate
```

---

## 43. `mockCalls`

Foundry supporta anche risposte sequenziali.

Esempio concettuale:

```text
prima balanceOf -> 100
seconda balanceOf -> 90
```

utile per testare pattern:

```text
before balance
after balance
```

senza implementare un token completo.

Ma fai attenzione:

> Un mock troppo artificiale può verificare la tua assunzione invece della vera integrazione.

Per ERC-20 importanti, mantieni anche integration test con un vero mock token.

---

## 44. Reverting dependency test

Quando una dipendenza critica deve bloccare l'operazione:

```solidity
vm.expectRevert();

consumer.refresh();
```

Poi verifica:

```text
lastGoodValue unchanged
```

Se invece la dependency è best-effort:

```text
consumer action succeeds
event failure emitted
state main action correct
```

Il test deriva dalla failure policy.

---

## 45. Testing reentrancy regression

Dopo aver corretto una vulnerabilità, non eliminare il contratto attacker locale.

Tienilo nella suite regression.

Esempio:

```text
VulnerableEscrow
-> test dimostra exploit locale

FixedEscrow
-> stesso callback non rompe invariant
```

Il test di regressione deve restare per tutta la vita del codice.

---

## 46. Regression naming

Puoi nominare:

```text
test_Regression_ReentrancyCannotDrainBacking
test_Regression_FalseReturnCannotCreateCredit
test_Regression_StalePriceRejected
test_Regression_UpgradePreservesStorage
```

Questo racconta la storia della sicurezza del protocollo.

---

# Access control, state machine e casi limite

## 47. Testing di access control

Per ogni privileged function:

```text
authorized caller
unauthorized caller
```

Ma non basta.

Verifica anche:

```text
authorized caller
+
invalid state
=> still revert
```

Authorization non deve bypassare la state machine.

Esempio:

```text
owner può chiamare
ma non può release una posizione già Refunded
```

---

## 48. Combinatorial thinking

Due condizioni:

```text
role
state
```

generano matrice:

```text
             valid state   invalid state
authorized      success       revert
unauthorized    revert        revert
```

Tre dimensioni:

```text
role
state
amount
```

creano ancora più combinazioni.

Non scriveremo ogni combinazione manualmente per sempre.

Il fuzzing ci aiuterà nella prossima lezione.

Ma la matrice deve essere pensata già ora.

---

## 49. Table-driven thinking

Puoi progettare mentalmente:

```text
caller      state       amount      expected
------------------------------------------------
buyer       Created     100         success
buyer       Created     0           revert Zero
buyer       Funded      100         revert State
stranger    Created     100         revert Auth
```

Solidity test non ha bisogno di essere formalmente parametrico per beneficiare di questo modello.

---

## 50. Test delle transizioni di stato

Per una state machine:

```text
Created
Funded
Released
Refunded
```

costruisci una transition matrix.

```text
From        Action       To          Allowed?
------------------------------------------------
Created     deposit      Funded      yes
Created     release      -           no
Created     refund       -           no
Funded      release      Released    yes
Funded      refund       Refunded    yes
Released    deposit      -           no
Released    refund       -           no
Refunded    release      -           no
```

Ogni riga importante può diventare un test.

---

## 51. Test terminal state

Stato terminale significa:

```text
nessuna transizione successiva
```

Test:

```solidity
_deposit(100);

vm.prank(buyer);
escrow.release();

vm.prank(buyer);

vm.expectRevert(
    Escrow.InvalidState.selector
);

escrow.refund();
```

Poi:

```text
state remains Released
```

---

## 52. Test idempotence quando richiesta

Alcune funzioni dovrebbero essere idempotenti.

Esempio possibile:

```text
pause()
pause()
```

Può:

```text
success entrambe
```

oppure:

```text
seconda call revert
```

Dipende dalla specification.

Non assumere.

Scrivi esplicitamente il comportamento desiderato.

---

## 53. Test di zero address

Ogni volta che un address entra come config:

```text
owner
oracle
seller
feeRecipient
router
```

chiedi:

```text
address(0) è valido?
```

Se no:

```solidity
vm.expectRevert(
    ZeroAddress.selector
);
```

Questo è un test di configuration safety.

---

## 54. Test di `address(this)`

Per proxy/composability a volte è importante verificare:

```text
quale address vede la logica?
```

Puoi aggiungere una funzione giocattolo:

```solidity
function self()
    external
    view
    returns (address)
{
    return address(this);
}
```

tramite proxy dovrebbe restituire:

```text
proxy
```

È un test didattico utile per `delegatecall`.

---

## 55. Test di call forwarding

Per un proxy:

```text
caller -> proxy -> implementation
```

verifica:

```text
msg.sender preservato
storage proxy modificato
```

Non soltanto:

```text
function returned correct number
```

---

# Diagnostica: trace, filtri e isolamento

## 56. Call traces

Comandi:

```bash
forge test -vv
forge test -vvv
forge test -vvvv
```

Aumentando verbosity puoi vedere più dettagli sulle trace.

Utile per:

```text
capire call chain
vedere revert
seguire external call
debuggare msg.sender
```

Non imparare la trace come testo.

Usala per ricostruire:

```text
chi ha chiamato chi?
con quale calldata?
dove è avvenuto il revert?
```

---

## 57. Filtrare i test

Esempi:

```bash
forge test --match-test test_StrangerCannotFund
```

Oppure:

```bash
forge test --match-contract EscrowDepositTest
```

Oppure:

```bash
forge test --match-path "test/regression/*"
```

Questo rende il feedback loop più rapido durante sviluppo/audit.

---

## 58. Riprodurre un singolo failure

Quando un test fallisce:

```text
1. esegui solo quel test;
2. aumenta verbosity;
3. riduci il setup;
4. stampa solo se necessario;
5. identifica il primo punto in cui stato/aspettativa divergono.
```

Non modificare subito il contratto finché non hai capito il failure.

---

## 59. Logging

Puoi usare:

```solidity
console2.log(...)
```

per debugging.

Ma non trasformare il test in:

```text
guardo manualmente i log
e decido che sembra corretto
```

Il test automatico deve avere assertion.

Log:

```text
diagnostic
```

Assertion:

```text
verification
```

---

## 60. Snapshot / state reset

Foundry fornisce cheatcode per snapshot dello stato EVM e rollback locale.

Sono utili in test avanzati quando vuoi:

```text
preparare stato costoso
provare ramo A
rollback
provare ramo B
```

Ma non usarli per nascondere setup poco chiari.

La maggior parte dei test semplici beneficia della naturale isolation di Foundry tra test.

---

## 61. Test isolation

Ogni test Foundry parte dalla situazione derivata da `setUp`.

Quindi:

```text
test A
```

non deve dipendere da:

```text
test B eseguito prima
```

I test order-dependent sono un antipattern.

Un test deve poter essere eseguito singolarmente.

---

# Mutation testing e coverage

## 62. Mutation thinking

Supponiamo di avere:

```solidity
if (msg.sender != buyer) {
    revert OnlyBuyer();
}
```

Mutation:

```solidity
// rimuovi temporaneamente check
```

Il test:

```text
StrangerCannotFund
```

deve fallire.

Se continua a passare:

```text
il test non sta realmente provando quella proprietà
```

---

## 63. Altre mutation utili

Modifica temporaneamente:

```text
>  -> >=
```

oppure:

```text
received -> requestedAmount
```

oppure:

```text
state = Released
```

rimuovila.

Oppure:

```text
safeTransferFrom -> transferFrom ignorando return
```

La suite dovrebbe rilevare queste regressioni.

---

## 64. Mutation testing automatico

La documentazione Foundry corrente include anche una guida sul mutation testing.

Il concetto è:

```text
strumento genera varianti mutate del codice
```

e misura:

```text
quante vengono uccise dai test?
```

Mutante sopravvissuto:

```text
la suite non distingue
il codice corretto
da quella modifica
```

Non useremo ancora tool automatici in profondità.

Ma il mindset è già essenziale.

---

## 65. Coverage

Comando:

```bash
forge coverage
```

Può produrre una sintesi di coverage per:

```text
lines
statements
branches
functions
```

A seconda della configurazione/versione.

È utile per scoprire:

```text
ramo mai visitato
funzione mai testata
failure path dimenticata
```

---

## 66. Coverage alta non significa sicurezza

Contratto:

```solidity
function withdraw()
    external
{
    balances[msg.sender] = 0;

    payable(msg.sender).call{
        value: 1 ether
    }("");
}
```

Un test happy path può visitare:

```text
100% delle linee
```

senza verificare:

```text
correct amount
return value
reentrancy
insolvency
authorization
```

Quindi:

```text
coverage
=
where tests went
```

non:

```text
whether tests proved the right things
```

---

## 67. Coverage come mappa di domande

Usa coverage per chiedere:

```text
perché questo ramo non è testato?
```

Poi decidi:

```text
è dead code?
è failure path?
è emergency path?
è impossibile per design?
manca un test?
```

Questo è molto più utile di inseguire:

```text
100%
```

come obiettivo astratto.

---

## 68. Branch coverage

Considera:

```solidity
if (amount == 0) {
    revert ZeroAmount();
}

if (msg.sender != buyer) {
    revert OnlyBuyer();
}
```

Happy path visita:

```text
false branch
false branch
```

Ma devi testare:

```text
true branch di amount == 0
true branch di unauthorized
```

La sicurezza vive spesso proprio nei rami di failure.

---

## 69. Coverage report LCOV

Foundry può generare output:

```text
lcov
```

utilizzabile con strumenti esterni di visualizzazione.

La documentazione corrente di Foundry include workflow dedicati per code coverage e per-test attribution.

Nel corso ci basta:

```bash
forge coverage
```

e, quando utile:

```bash
forge coverage --report lcov
```

Verifica sempre le opzioni con:

```bash
forge coverage --help
```

per la versione installata.

---

# Test come security code: matrici, Ether e privilegi

## 70. Test gas vs security test

Foundry può anche produrre gas report.

È utile per performance.

Ma evita questa mentalità:

```text
meno gas
= più sicuro
```

A volte:

```text
un controllo aggiuntivo
```

costa gas ma protegge una proprietà importante.

Ottimizzazione e sicurezza sono dimensioni differenti.

---

## 71. Regression matrix

Costruiamo una matrice semplice.

| Requirement | Positive Test | Negative Test | Regression |
|---|---|---|---|
| Solo buyer deposita | BuyerCanDeposit | StrangerCannotDeposit | auth mutation |
| Amount > 0 | PositiveDeposit | ZeroDepositReverts | boundary |
| No double funding | FirstDepositWorks | DoubleDepositReverts | state machine |
| Release clears debt | ReleasePaysSeller | ReleaseBeforeFundingReverts | liability regression |
| Oracle fresh | FreshPriceAccepted | StalePriceReverts | timestamp mutation |
| Upgrade owner-only | OwnerCanUpgrade | StrangerCannotUpgrade | auth mutation |
| State survives upgrade | UpgradePreservesState | bad layout rejected | storage regression |

Questa tabella è estremamente utile durante audit e code review.

---

## 72. Requirement traceability

La domanda:

```text
"questa funzione è testata?"
```

è meno utile di:

```text
"quale requisito protegge questo test?"
```

e:

```text
"quale test protegge questo requisito?"
```

Vuoi una relazione bidirezionale:

```text
requirement -> tests
tests -> requirement
```

---

## 73. Test code è security code

Un test sbagliato può dare più fiducia di nessun test.

Esempio:

```solidity
vm.expectRevert();
target.foo();
```

se il revert è dovuto a:

```text
setup sbagliato
```

non stai testando la proprietà prevista.

Quindi il test stesso va reviewato.

---

## 74. Error-path precision

Per una funzione:

```solidity
deposit()
```

potrebbero esistere:

```text
OnlyBuyer
InvalidState
ZeroAmount
TokenTransferFailed
```

Ogni failure path dovrebbe avere test dedicato.

Questo evita che un solo:

```text
expectRevert()
```

copra falsamente quattro proprietà diverse.

---

## 75. Test ordering delle precondizioni

Supponiamo:

```solidity
if (msg.sender != buyer)
    revert OnlyBuyer();

if (amount == 0)
    revert ZeroAmount();
```

Con:

```text
stranger
amount = 0
```

l'errore atteso è:

```text
OnlyBuyer
```

perché viene controllato prima.

Questo può essere importante se:

```text
l'ordine delle validation
```

ha valore semantico o privacy/security.

Non serve testare ogni combinazione sempre, ma capisci il comportamento.

---

## 76. External call expectation

Foundry offre strumenti per verificare anche che certe call esterne avvengano.

Questo tipo di test verifica:

```text
interaction
```

Per esempio:

```text
Escrow deve chiamare notifier
```

Ma ricorda:

```text
expectCall
```

non verifica automaticamente:

```text
correttezza economica
```

Interaction test e state test sono complementari.

---

## 77. Event vs call vs state

Tre tipi di evidenza:

```text
event:
    cosa viene annunciato

external call:
    cosa viene invocato

state:
    cosa persiste
```

Una suite robusta può usare tutti e tre dove opportuno.

---

## 78. Testing Ether sends

Per una funzione:

```solidity
(bool ok,) =
    recipient.call{
        value: amount
    }("");
```

testa:

```text
recipient balance delta
contract balance delta
internal accounting
failure recipient
reentrant recipient
```

Non soltanto:

```text
call returns success
```

---

## 79. Recipient che reverte

Mock:

```solidity
contract RejectEther {
    receive() external payable {
        revert();
    }
}
```

Poi verifica la policy:

```text
payout revert?
credit remains?
state rolls back?
alternative withdrawal?
```

Il test deriva dal design.

---

## 80. Test di reentrancy callback

Mantieni:

```text
attacker mock
```

molto piccolo.

Il suo scopo è:

```text
richiamare la funzione
durante la callback
```

Non deve diventare un framework offensivo.

Poi verifica una proprietà:

```text
assets >= liabilities
```

oppure:

```text
credit cannot be withdrawn twice
```

---

## 81. Test di dependency upgrade

Per componenti upgradeabili, prepara:

```text
state before
upgrade
state after
```

e non verificare solo:

```text
version = 2
```

Ma:

```text
owner
roles
balances
liabilities
state machine
```

---

## 82. Test di timelock

Suite minima:

```text
unauthorized proposer -> fail
schedule -> success
execute too early -> fail
execute ready -> success
cancel -> success
cancelled execute -> fail
```

Poi:

```text
target state changed exactly once
```

---

## 83. Test di emergency controls

Per `pause`:

```text
authorized pauser -> success
stranger -> fail
sensitive action while paused -> fail
allowed exit while paused -> success
unpause authority -> correct
```

Questo è importante perché un `pause()` può accidentalmente bloccare anche il recovery path.

---

# Disciplina: local-first, CI, determinismo e regole di scrittura

## 84. Local-first testing

Per questa fase del corso:

```text
forge test
```

è sufficiente.

Non serve:

```text
mainnet fork
testnet
RPC pubblico
```

Un ambiente locale offre:

```text
determinismo
velocità
controllo dello stato
nessun asset reale
```

Fork testing può essere utile più avanti per compatibility testing, ma non è necessario per capire le proprietà fondamentali.

---

## 85. Anvil

Anvil è utile quando vuoi osservare più realisticamente:

```text
transaction
receipt
block
nonce
eth_getLogs
```

ma non sostituisce Forge unit testing.

Modello:

```text
Forge
-> test automatici

Anvil
-> nodo EVM locale interattivo
```

Usali per obiettivi differenti.

---

## 86. CI mindset

La suite di regressione dovrebbe essere eseguita:

```text
ad ogni modifica importante
```

Non soltanto prima del deploy.

Pipeline concettuale:

```text
format
build
unit tests
integration tests
regression tests
coverage
static analysis
upgrade validation
```

Più avanti aggiungeremo:

```text
fuzz
invariant
Slither
```

---

## 87. Determinismo

Evita test che dipendono implicitamente da:

```text
ordine di esecuzione
tempo reale del computer
network pubblico
external API
```

Per un test unitario, preferisci controllare:

```text
timestamp
account
balance
dependency response
```

localmente.

---

## 88. Flaky tests

Un test flaky:

```text
a volte passa
a volte fallisce
```

è particolarmente pericoloso nella security engineering.

Il team impara a:

```text
ignorare il rosso
```

e questo distrugge il valore della suite.

Local deterministic testing riduce il problema.

---

## 89. One concept per test

Questo:

```solidity
function test_Everything()
```

che:

```text
deposit
release
pause
upgrade
oracle
timelock
```

e ha 30 assertion è difficile da diagnosticare.

Meglio test piccoli quando stai verificando proprietà isolate.

Integration tests più lunghi hanno senso per workflow end-to-end.

---

## 90. Un test può avere più assertion

"One concept per test" non significa:

```text
una assertion per test
```

Esempio:

```text
release
```

può naturalmente richiedere:

```text
state == Released
amount == 0
seller balance increased
escrow balance decreased
```

Sono tutte parti della stessa proprietà di settlement.

---

## 91. Arrange minima

Evita preparazioni non necessarie.

Per testare:

```text
ZeroAmount
```

non serve:

```text
deploy timelock
upgrade proxy
mock oracle
mint tre token
```

Più piccolo è lo scenario, più facile è interpretare il failure.

---

## 92. Negative tests first

Quando introduci una nuova funzione privileged:

```solidity
setOracle(...)
```

scrivi subito:

```text
stranger cannot call
zero address rejected
authorized valid update succeeds
```

Il negative testing non dovrebbe essere aggiunto "alla fine".

Fa parte dell'implementazione.

---

## 93. Test del rollback

Esempio:

```text
state set
external call
external call reverts
```

Verifica che:

```text
state precedente sia ripristinato
```

Questo rende concreta l'atomicità EVM.

---

## 94. Test di failure propagation

Se dependency critica reverte:

```text
consumer deve revertire
```

Se best-effort:

```text
consumer deve continuare
```

Non testare genericamente:

```text
"dependency can fail"
```

Testa la failure policy.

---

# Checklist, laboratorio finale e chiusura

## 95. Test review checklist

Per ogni test chiediti:

```text
1. quale proprietà verifica?
2. può passare per il motivo sbagliato?
3. il revert è abbastanza preciso?
4. lo stato dopo è verificato?
5. il caller è quello che penso?
6. il setup è minimo?
7. un bug plausibile farebbe fallire il test?
8. il test funziona singolarmente?
```

---

## 96. Checklist da auditor — suite di test

Quando auditi un repository:

- [ ] esiste una suite test?
- [ ] test positivi?
- [ ] test negativi?
- [ ] authorization testata?
- [ ] state machine testata?
- [ ] boundary values?
- [ ] zero address?
- [ ] zero amount?
- [ ] external failure?
- [ ] reentrancy regression?
- [ ] oracle stale/zero/negative?
- [ ] ERC20 false-return?
- [ ] fee-on-transfer?
- [ ] upgrade preservation?
- [ ] unauthorized upgrade?
- [ ] timelock early execution?
- [ ] paused-state behavior?
- [ ] terminal state?
- [ ] event correctness?
- [ ] balance delta?
- [ ] coverage analizzata?
- [ ] test troppo generici?
- [ ] `expectRevert()` generici dove dovrebbero essere precisi?
- [ ] prank lifecycle corretto?
- [ ] helper nascondono troppo?
- [ ] test dipendono dall'ordine?
- [ ] test dipendono da RPC esterno senza motivo?
- [ ] regression test per bug storici?

---

## 97. Laboratorio finale della lezione

Crea questa struttura:

```text
test/
├── unit/
│   ├── Deposit.t.sol
│   ├── Release.t.sol
│   ├── AccessControl.t.sol
│   └── Governance.t.sol
├── integration/
│   ├── ERC20Integration.t.sol
│   ├── OracleIntegration.t.sol
│   └── UpgradeIntegration.t.sol
├── regression/
│   ├── Reentrancy.t.sol
│   ├── FalseReturnToken.t.sol
│   └── StorageUpgrade.t.sol
├── helpers/
│   └── EscrowTestBase.sol
└── mocks/
```

Poi esegui:

```bash
forge test
```

Quindi:

```bash
forge test -vvv
```

su un singolo test:

```bash
forge test \
  --match-test \
  test_Regression_ReentrancyCannotDrainBacking \
  -vvvv
```

Infine:

```bash
forge coverage
```

---

## 98. Esercizi

### Esercizio 1 — Revert precision

Trova tre test esistenti che usano:

```solidity
vm.expectRevert();
```

e rendili più precisi con:

```text
custom error selector
o
encoded custom error
```

quando appropriato.

---

### Esercizio 2 — State unchanged

Per ogni negative test su `deposit`, verifica anche:

```text
amount unchanged
state unchanged
token balance unchanged
```

---

### Esercizio 3 — Event + state

Per:

```text
setOracle
```

verifica:

```text
evento corretto
storage corretto
```

Non uno soltanto.

---

### Esercizio 4 — Mutation

Rimuovi temporaneamente:

```solidity
if (msg.sender != buyer)
```

La suite deve fallire.

Se non fallisce, aggiungi il regression test mancante.

---

### Esercizio 5 — Boundary

Per:

```text
fee <= 1000
```

scrivi test:

```text
999
1000
1001
```

---

### Esercizio 6 — State matrix

Per:

```text
Created
Funded
Released
Refunded
```

crea una tabella di tutte le azioni principali e indica:

```text
allowed / forbidden
```

Poi implementa almeno quattro negative test mancanti.

---

### Esercizio 7 — Mock strategy

Per un oracle, implementa due test equivalenti:

1. con mock contract;
2. con `vm.mockCall`.

Confronta leggibilità e capacità espressiva.

---

### Esercizio 8 — Coverage gap

Esegui:

```bash
forge coverage
```

Scegli un branch non coperto.

Prima di aggiungere il test, rispondi:

```text
perché questo branch esiste?
è raggiungibile?
quale proprietà rappresenta?
```

Solo dopo scrivi il test.

---

### Esercizio 9 — Regression matrix

Costruisci una tabella con almeno 15 requisiti del nostro Escrow e collega:

```text
positive test
negative test
regression
```

---

### Esercizio 10 — Audit challenge

Analizza questa suite:

```solidity
function testWithdraw() public {
    vm.expectRevert();
    vault.withdraw();

    vm.prank(owner);
    vault.withdraw();

    assertTrue(true);
}
```

Trova almeno **otto problemi** di qualità del test.

Suggerimenti:

```text
revert generico
stato non verificato
balance non verificato
owner semantics
assertTrue(true)
prerequisiti impliciti
failure reason
success path incompleto
```

---

## 99. Cosa devo ricordare

### 1. Un test deve verificare una proprietà, non soltanto eseguire codice

---

### 2. Negative testing è parte del secure coding

```text
ciò che non deve essere possibile
```

è spesso più importante dell'happy path.

---

### 3. Usa revert precisi

```solidity
expectRevert(
    CustomError.selector
)
```

è più forte di:

```solidity
expectRevert()
```

quando conosci la causa attesa.

---

### 4. Verifica lo stato dopo la call

Eventi e return value non bastano.

---

### 5. Mantieni caller e setup espliciti

`prank`, `startPrank` e helper troppo astratti possono nascondere errori.

---

### 6. Coverage è una mappa, non una prova

```text
100% coverage
!=
100% correctness
```

---

### 7. Mutation thinking misura la forza della suite

Se introduci il bug e il test continua a passare, la suite è debole.

---

### 8. Ogni bug trovato deve diventare una regressione permanente

---

### 9. Testa failure propagation e rollback

Le dipendenze esterne sono parte del comportamento.

---

### 10. Testing architecture prepara fuzzing e invarianti

Se non sai formulare proprietà con esempi concreti, sarà difficile scrivere buoni fuzz/invariant test.

---

## 100. Collegamento con il corso

Finora abbiamo costruito:

```text
specifica
   |
   v
business logic
   |
   v
security properties
   |
   v
unit/negative/regression testing
```

Ora siamo pronti a sostituire:

```text
pochi input scelti a mano
```

con:

```text
molti input generati automaticamente
```

e successivamente:

```text
sequenze arbitrarie di azioni
```

Quindi la prossima lezione sarà:

**Lezione 14 — Fuzz testing e invariant testing con Foundry.**

---

## 101. Fonti della lezione

Fonti tecniche consultate il **21 settembre 2026**:

1. **Foundry Documentation — Reference**  
   Riferimento corrente per Forge, Anvil, cheatcode e Forge Std.  
   https://www.getfoundry.sh/reference/

2. **Foundry — Writing Tests**  
   Struttura dei test Solidity, `Test.sol`, `setUp()` e modello di esecuzione dei test Forge.  
   https://getfoundry.sh/forge/writing-tests

3. **Foundry — Forge Standard Library**  
   `Test.sol`, assertions, cheatcode interface e utility Forge Std.  
   https://getfoundry.sh/reference/forge-std/overview

4. **Foundry — `expectRevert`**  
   Semantica corrente di `expectRevert`, overload per selector/revert data, `expectPartialRevert` e note sui call depth / next call.  
   https://getfoundry.sh/cheatcodes/expect-revert

5. **Foundry — `prank`**  
   Semantica corrente di `vm.prank`, inclusi overload per `msg.sender`, `tx.origin` e delegate calls.  
   https://getfoundry.sh/reference/cheatcodes/prank/

6. **Foundry — Mock Calls**  
   `mockCall`/`mockCalls`, matching delle calldata e risposte sequenziali.  
   https://getfoundry.sh/cheatcodes/mock-calls

7. **Foundry — Guides / Code Coverage**  
   Workflow corrente per code coverage, report LCOV e analisi della copertura.  
   https://www.getfoundry.sh/guides/

8. **Foundry — Guides / Mutation Testing**  
   Approccio corrente al mutation testing per valutare la forza di una test suite.  
   https://www.getfoundry.sh/guides/

9. **OpenZeppelin Contracts 5.x**  
   Libreria di riferimento usata nei contratti del corso e raccomandazioni di installazione con release versionate.  
   https://docs.openzeppelin.com/contracts/5.x

10. **OpenZeppelin — Writing Automated Tests**  
    Principi generali su test automatici, revert, eventi e continuous integration.  
    https://docs.openzeppelin.com/contracts/5.x/learn/writing-automated-tests

---

# Fine Lezione 13

Prossimo argomento:

**Fuzz testing e invariant testing con Foundry: input generation, `bound`, `assume`, handlers, ghost variables, target selectors, stateful sequences e invarianti di solvibilità.**
