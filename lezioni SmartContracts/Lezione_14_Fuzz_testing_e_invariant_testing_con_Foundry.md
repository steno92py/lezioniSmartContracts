# Lezione 14 — Fuzz Testing e Invariant Testing con Foundry

> **Scopo:** testing difensivo, secure coding, auditing e verifica automatizzata di proprietà.
>
> Tutti gli esempi sono confinati a **Foundry/Anvil locale**, account di test e contratti giocattolo. Non usiamo fork pubblici né protocolli reali.

---

# Obiettivi e modello mentale

## 1. Obiettivi

Alla fine della lezione dovresti saper:

- spiegare la differenza tra unit test, fuzz test e invariant test;
- trasformare un requisito in una proprietà adatta al fuzzing;
- usare correttamente `bound()` e `vm.assume()`;
- capire perché troppe assumption impoveriscono il fuzzing;
- interpretare un counterexample Foundry;
- costruire fuzz test per:
  - amount;
  - boundary;
  - access control;
  - scaling;
  - state transitions;
- spiegare che cosa significa **stateful invariant testing**;
- costruire un handler;
- usare ghost variables;
- limitare il dominio delle azioni generate;
- evitare invarianti tautologici;
- scrivere invarianti di:
  - solvibilità;
  - conservation/accounting;
  - terminal state;
  - access control;
- capire perché "la funzione non reverte" non è un buon invariante generale;
- distinguere protocol state da test bookkeeping;
- preparare una suite che possa trovare errori logici attraverso sequenze che non avevi previsto manualmente.

---

## 2. Modello mentale

Nella Lezione 13 abbiamo scelto casi concreti:

```text
deposit(100)
deposit(0)
deposit(1001)
```

Un fuzz test dice invece:

```text
"Foundry, scegli tu molti valori."
```

Schema:

```text
Property
   |
   v
Input generator
   |
   +--> x1
   +--> x2
   +--> x3
   +--> ...
   |
   v
same assertion every time
```

L'invariant testing aggiunge una dimensione.

Non genera soltanto input.

Genera **sequenze di operazioni**:

```text
deposit
release
refund
deposit
...
```

e dopo le sequenze verifica che una proprietà globale resti vera.

Schema:

```text
initial state
    |
    v
action 1
    |
    v
action 2
    |
    v
action 3
    |
    v
...
    |
    v
INVARIANT MUST STILL HOLD
```

---

## 3. Fuzzing vs invariant testing

### Fuzz test

Tipicamente:

```solidity
function testFuzz_Deposit(
    uint256 amount
) public {
    ...
}
```

Ogni esecuzione del caso parte dal setup del test e prova valori differenti.

Domanda tipica:

> Per ogni `amount` valido, la proprietà vale?

---

### Invariant test

Foundry chiama molte funzioni target in sequenza sullo **stesso stato** durante una run.

Domanda:

> Dopo qualunque sequenza consentita di azioni, questa proprietà resta vera?

Questa distinzione è fondamentale.

---

## 4. Perché il fuzzing è utile

Gli umani tendono a scegliere:

```text
0
1
100
MAX
```

ma possono dimenticare:

```text
2^128 - 1
boundary specifiche
valori che causano rounding
combinazioni non intuitive
```

Il fuzzer esplora automaticamente molti input.

Non sostituisce il ragionamento.

Serve a testare una proprietà su un dominio più ampio.

---

# Primo fuzz test: bound e assume

## 5. Primo fuzz test

Contratto giocattolo:

```solidity
contract FeeCalculator {
    uint256 public constant FEE_BPS =
        250;

    function fee(
        uint256 amount
    ) external pure returns (uint256) {
        return amount * FEE_BPS / 10_000;
    }
}
```

Fuzz test:

```solidity
function testFuzz_FeeNeverExceedsAmount(
    uint256 amount
) public {
    uint256 result =
        calculator.fee(amount);

    assertLe(
        result,
        amount
    );
}
```

Proprietà:

```text
fee(amount) <= amount
```

per ogni input per cui la funzione è definita senza overflow.

---

## 6. Attenzione all'overflow dell'espressione di test

In Solidity 0.8+, questa espressione:

```solidity
amount * 250
```

può revertire per valori enormi.

Se il dominio reale del protocollo è limitato, dobbiamo dichiararlo.

Esempio:

```text
amount <= 1e36
```

Non perché vogliamo "aiutare" il test a passare.

Ma perché stiamo esprimendo il dominio reale.

---

## 7. `bound()`

Forge Std offre:

```solidity
bound(x, min, max)
```

Esempio:

```solidity
function testFuzz_Fee(
    uint256 rawAmount
) public {
    uint256 amount =
        bound(
            rawAmount,
            1,
            1_000_000 ether
        );

    uint256 result =
        calculator.fee(amount);

    assertLe(
        result,
        amount
    );
}
```

Ora qualunque `rawAmount` viene mappato nell'intervallo desiderato.

---

## 8. Perché `bound` spesso è preferibile a `assume`

Con:

```solidity
vm.assume(
    x >= min &&
    x <= max
);
```

il fuzzer scarta input finché ne trova uno valido.

Se il dominio valido è piccolo rispetto all'intero `uint256`, puoi scartare moltissimi casi.

Con:

```solidity
x = bound(x, min, max);
```

ogni input viene trasformato in un input valido.

Quindi, quando stai modellando un range continuo:

> **preferisci spesso `bound` a una assumption molto restrittiva.**

---

## 9. `vm.assume()`

`assume` è comunque utile quando il dominio è una proprietà discreta o difficile da rappresentare con `bound`.

Esempio:

```solidity
vm.assume(
    user != address(0)
);

vm.assume(
    user != buyer
);
```

Ora il test esplora caller che non sono il buyer e non sono zero.

---

## 10. Assumption poisoning

Questo è un test apparentemente sofisticato:

```solidity
vm.assume(
    amount == 100 ether
);
```

ma hai praticamente distrutto il fuzzing.

Stai chiedendo a Foundry di generare un numero enorme di valori e accettarne uno solo.

Equivale quasi a un unit test mal scritto.

Altro esempio:

```solidity
vm.assume(
    amount > 100 &&
    amount < 102
);
```

Il dominio utile contiene praticamente un solo intero.

Chiediti sempre:

> Questa assumption rappresenta davvero il dominio del protocollo o serve soltanto a far passare il test?

---

# Fuzzing dell'Escrow e dell'oracle

## 11. Fuzzing dell'Escrow

Prendiamo un Escrow semplificato:

```solidity
contract SimpleEscrow {
    address public immutable buyer;

    uint256 public escrowedAmount;
    bool public funded;

    error OnlyBuyer();
    error ZeroAmount();
    error AlreadyFunded();

    constructor(address buyer_) {
        buyer = buyer_;
    }

    function deposit(
        uint256 amount
    ) external {
        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (funded) {
            revert AlreadyFunded();
        }

        if (amount == 0) {
            revert ZeroAmount();
        }

        escrowedAmount = amount;
        funded = true;
    }
}
```

---

## 12. Fuzz property: accounting

Property:

```text
for every valid amount:
after buyer deposits amount,
escrowedAmount == amount
```

Test:

```solidity
function testFuzz_DepositRecordsAmount(
    uint256 amount
) public {
    amount = bound(
        amount,
        1,
        type(uint128).max
    );

    vm.prank(buyer);

    escrow.deposit(amount);

    assertEq(
        escrow.escrowedAmount(),
        amount
    );

    assertTrue(
        escrow.funded()
    );
}
```

---

## 13. Fuzz negative test: unauthorized caller

```solidity
function testFuzz_NonBuyerCannotDeposit(
    address caller,
    uint256 amount
) public {
    vm.assume(
        caller != buyer
    );

    vm.assume(
        caller != address(0)
    );

    amount = bound(
        amount,
        1,
        type(uint128).max
    );

    vm.prank(caller);

    vm.expectRevert(
        SimpleEscrow
            .OnlyBuyer
            .selector
    );

    escrow.deposit(amount);
}
```

Questa property riguarda:

```text
caller identity
```

non il valore.

---

## 14. Fuzzing e validation order

Se usi:

```text
caller != buyer
amount = 0
```

quale errore deve uscire?

Nel nostro contratto:

```text
OnlyBuyer
```

perché il check dell'authorization viene prima.

Il fuzzing può trovare combinazioni in cui più precondizioni sono false contemporaneamente.

Devi sapere quale comportamento vuoi.

---

## 15. Fuzzing boundary economiche

Dal corso sugli oracle:

```text
maxAge = 1 hour
```

Property:

```text
age <= MAX_AGE -> accepted
age > MAX_AGE -> rejected
```

Possiamo fuzzare due regioni separatamente.

---

## 16. Fuzz test freshness valida

```solidity
function testFuzz_FreshPriceAccepted(
    uint256 age
) public {
    age = bound(
        age,
        0,
        MAX_AGE
    );

    uint256 nowTs =
        1_000_000;

    vm.warp(nowTs);

    oracle.setPrice(
        3000e8,
        nowTs - age
    );

    assertEq(
        consumer.readPrice(),
        3000e8
    );
}
```

---

## 17. Fuzz test stale

```solidity
function testFuzz_StalePriceRejected(
    uint256 extra
) public {
    extra = bound(
        extra,
        1,
        365 days
    );

    uint256 nowTs =
        100_000_000;

    vm.warp(nowTs);

    oracle.setPrice(
        3000e8,
        nowTs
            - MAX_AGE
            - extra
    );

    vm.expectRevert(
        PriceConsumer
            .StalePrice
            .selector
    );

    consumer.readPrice();
}
```

Separare i domini rende la property chiara.

---

# Controesempi, proprietà e configurazione del fuzzing

## 18. Counterexample

Quando un fuzz test fallisce, Foundry cerca tipicamente di trovare un input piccolo/riproducibile che causa il failure.

Immagina:

```text
Property:
fee <= amount
```

e il test fallisce a:

```text
amount = 39
```

Questo è il counterexample.

Non trattarlo come:

```text
"Foundry è strano"
```

Trattalo come:

```text
"esiste una prova concreta
che la mia property o implementazione è sbagliata"
```

---

## 19. Shrinking

Gli strumenti di property testing cercano di ridurre un failing input verso un caso più semplice.

Per esempio:

```text
failing input iniziale:
1876239847

shrunk:
41
```

Un counterexample piccolo rende più semplice capire la causa.

Questa è una delle grandi utilità del fuzzing.

---

## 20. Proprietà sbagliata vs codice sbagliato

Se un fuzz test fallisce, ci sono almeno due possibilità.

### Codice sbagliato

La proprietà era corretta e hai trovato un bug.

### Proprietà sbagliata

Hai scritto un requisito che in realtà non vale.

Esempio:

```text
fee(amount) > 0
for all amount > 0
```

Con integer division può esistere:

```text
small amount
=> fee = 0
```

Il fuzzing aiuta anche a correggere la specification.

---

## 21. Fuzzing di rounding

Per conversioni con decimals:

```text
amount * price / scale
```

il fuzzing è utilissimo.

Proprietà ragionevole:

```text
quote deve essere monotona
```

cioè:

```text
if a <= b
then quote(a) <= quote(b)
```

Possiamo testarla.

---

## 22. Fuzz property monotonicity

```solidity
function testFuzz_QuoteIsMonotonic(
    uint128 a,
    uint128 b
) public {
    uint256 x =
        uint256(a);

    uint256 y =
        uint256(b);

    if (x > y) {
        (
            x,
            y
        ) = (
            y,
            x
        );
    }

    uint256 qx =
        consumer.quote18To6(x);

    uint256 qy =
        consumer.quote18To6(y);

    assertLe(
        qx,
        qy
    );
}
```

Non usiamo:

```solidity
vm.assume(a <= b);
```

necessariamente.

Possiamo normalizzare gli input.

---

## 23. Normalizzare invece di scartare

Pattern utile:

```solidity
if (a > b) {
    (a, b) = (b, a);
}
```

Ora ogni coppia fuzzata diventa utilizzabile.

Questa filosofia è simile a `bound`:

```text
trasforma il dominio
```

piuttosto che:

```text
scarta quasi tutto
```

---

## 24. Fuzzing di access control

Una property utile:

```text
no address other than owner can call adminAction
```

Test:

```solidity
function testFuzz_OnlyOwner(
    address caller
) public {
    vm.assume(
        caller != owner
    );

    vm.assume(
        caller != address(0)
    );

    vm.prank(caller);

    vm.expectRevert();

    target.adminAction();
}
```

Meglio, se conosci l'errore:

```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        OwnableUnauthorizedAccount.selector,
        caller
    )
);
```

quando appropriato alla versione usata.

---

## 25. Fuzzing non sostituisce casi mirati

Continua a mantenere:

```text
0
max
exact boundary
specific historical bug
```

come unit/regression test.

Perché?

Il fuzzer potrebbe non visitare ogni valore che ti interessa in ogni run.

Un caso di regressione noto va codificato esplicitamente.

---

## 26. Configurazione fuzz

Foundry consente di configurare il numero di run.

In `foundry.toml`, concettualmente:

```toml
[profile.default.fuzz]
runs = 256
```

Per CI più intensa puoi avere un profilo differente.

Esempio:

```toml
[profile.ci.fuzz]
runs = 5000
```

Poi:

```bash
FOUNDRY_PROFILE=ci forge test
```

Il valore ottimale dipende da velocità e complessità.

---

## 27. Più run non correggono una property debole

Se la tua assertion è:

```solidity
assertTrue(true);
```

puoi fare:

```text
1 milione di run
```

senza imparare nulla.

La qualità della property viene prima della quantità di input.

---

# Invarianti e stateful fuzzing

## 28. Passiamo agli invarianti

Ora introduciamo il concetto più potente.

Supponiamo un vault/escrow con più utenti.

Property:

> Il contratto deve sempre possedere abbastanza token da coprire tutti i crediti registrati.

Formalmente:

```text
token.balanceOf(escrow)
>=
sum(all credits)
```

Questa proprietà deve valere dopo:

```text
deposit
withdraw
release
refund
```

in qualunque ordine consentito.

Questo è un invariante.

---

## 29. Che cos'è un invariante

Un invariante è una proprietà che deve restare vera per ogni stato raggiungibile ammesso dal modello.

Non significa:

```text
"non cambia mai"
```

Significa:

```text
"resta vera anche se lo stato cambia"
```

Esempio:

```text
balance >= liabilities
```

Balance e liabilities cambiano.

La relazione deve rimanere vera.

---

## 30. Invariante vs postcondition

### Postcondition

Dopo `deposit(x)`:

```text
credit[user] increased by x
```

### Invariante

In ogni stato valido:

```text
assets >= liabilities
```

Le postcondition locali aiutano a dimostrare l'invariante globale.

---

## 31. Stateful fuzzing

Foundry invariant testing genera call ripetute a funzioni target.

Esempio:

```text
Run 1:

deposit(Alice, 17)
deposit(Bob, 3)
withdraw(Alice, 2)
deposit(Carol, 100)
withdraw(Bob, 1)

check invariant
```

Altra run:

```text
withdraw
deposit
deposit
release
...
```

L'obiettivo è esplorare sequenze che un umano potrebbe non scrivere.

---

## 32. Problema: chiamare direttamente il protocollo

Se lasci Foundry chiamare liberamente il protocollo con qualsiasi input/caller, potresti ottenere moltissimi revert inutili.

Esempio:

```text
release prima del funding
refund da stranger
deposit amount 0
```

A volte è utile.

Ma spesso vogliamo un modello di azioni più controllato.

Qui entra l'**handler**.

---

## 33. Handler

Un handler è un contratto test-side che espone azioni fuzzabili verso il protocollo.

Schema:

```text
Foundry
  |
  | random handler function
  v
Handler
  |
  | normalized valid interaction
  v
Escrow
```

L'handler può:

- normalizzare input;
- scegliere caller;
- mantenere ghost variables;
- registrare quanto è avvenuto;
- evitare azioni totalmente prive di significato.

---

## 34. Contratto per invariant lab

Creiamo un vault token multiutente molto semplice.

### `src/invariant/CreditVault.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    IERC20
} from
    "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    SafeERC20
} from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CreditVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    mapping(address => uint256)
        public credit;

    uint256 public totalCredit;

    error ZeroAmount();
    error InsufficientCredit();

    constructor(
        IERC20 token_
    ) {
        token = token_;
    }

    function deposit(
        uint256 amount
    ) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        token.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        credit[msg.sender] += amount;
        totalCredit += amount;
    }

    function withdraw(
        uint256 amount
    ) external {
        if (
            amount == 0 ||
            amount > credit[msg.sender]
        ) {
            revert InsufficientCredit();
        }

        credit[msg.sender] -= amount;
        totalCredit -= amount;

        token.safeTransfer(
            msg.sender,
            amount
        );
    }
}
```

Per questo laboratorio usiamo un token standard senza fee/rebase.

La policy dell'asset è quindi:

```text
exact-transfer ERC20 mock
```

---

## 35. Invariante principale

Per il vault:

```text
token.balanceOf(vault)
==
totalCredit
```

In questo modello specifico possiamo usare `==`, non solo `>=`, perché:

- il token standard trasferisce esattamente l'amount;
- non inviamo token al vault fuori dalle funzioni del modello;
- non esistono fee;
- non esistono donation nella nostra action space.

Questa precisione è importante.

Se ammettessimo donation dirette:

```text
balance >= totalCredit
```

sarebbe l'invariante corretto.

---

## 36. Il modello determina l'invariante

Questo è un punto fondamentale.

```text
balance == liabilities
```

non è universalmente più forte di:

```text
balance >= liabilities
```

Può essere semplicemente **falso** in un protocollo che accetta donation.

Quindi:

> Prima definisci gli stati raggiungibili. Poi scegli la relazione.

---

# Handler e ghost variables

## 37. Handler base

### `test/invariant/handlers/VaultHandler.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from
    "forge-std/Test.sol";

import {
    CreditVault
} from "../../../src/invariant/CreditVault.sol";

import {
    TestToken
} from "../../mocks/TestToken.sol";

contract VaultHandler is Test {
    CreditVault public immutable vault;
    TestToken public immutable token;

    address[] internal actors;

    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;

    constructor(
        CreditVault vault_,
        TestToken token_
    ) {
        vault = vault_;
        token = token_;

        actors.push(
            makeAddr("alice")
        );

        actors.push(
            makeAddr("bob")
        );

        actors.push(
            makeAddr("carol")
        );

        for (
            uint256 i;
            i < actors.length;
            ++i
        ) {
            token.mint(
                actors[i],
                1_000_000 ether
            );

            vm.prank(actors[i]);

            token.approve(
                address(vault),
                type(uint256).max
            );
        }
    }

    function deposit(
        uint256 actorSeed,
        uint256 amount
    ) external {
        address actor =
            _actor(actorSeed);

        amount = bound(
            amount,
            1,
            1000 ether
        );

        vm.prank(actor);

        vault.deposit(amount);

        ghostDeposited += amount;
    }

    function withdraw(
        uint256 actorSeed,
        uint256 amount
    ) external {
        address actor =
            _actor(actorSeed);

        uint256 available =
            vault.credit(actor);

        if (available == 0) {
            return;
        }

        amount = bound(
            amount,
            1,
            available
        );

        vm.prank(actor);

        vault.withdraw(amount);

        ghostWithdrawn += amount;
    }

    function _actor(
        uint256 seed
    ) internal view returns (address) {
        return actors[
            seed % actors.length
        ];
    }
}
```

---

## 38. Perché l'handler ritorna invece di usare `assume`

In `withdraw`:

```solidity
if (available == 0) {
    return;
}
```

Potremmo usare assumption.

Ma qui la condizione dipende dallo stato corrente.

Un ritorno no-op è spesso semplice e leggibile.

La domanda da porsi è:

```text
quanti no-op sta generando il fuzzer?
```

Se quasi tutte le action diventano no-op, l'action space è progettato male.

---

## 39. Actor selection

Usiamo:

```solidity
actors[
    seed % actors.length
]
```

Così qualunque `actorSeed` genera uno degli actor validi.

Questo è meglio di:

```solidity
vm.assume(
    caller == alice ||
    caller == bob ||
    caller == carol
);
```

che scarterebbe quasi ogni address casuale.

---

## 40. Ghost variables

Nel handler:

```solidity
uint256 public ghostDeposited;
uint256 public ghostWithdrawn;
```

non appartengono al protocollo.

Sono contabilità del test.

Servono a verificare proprietà che il protocollo non memorizza direttamente.

Per esempio:

```text
net deposits
=
ghostDeposited - ghostWithdrawn
```

---

## 41. Perché si chiamano "ghost"

Sono variabili concettualmente esterne alla business logic.

Non influenzano il contratto reale.

Esistono soltanto per aiutare la verifica.

Esempi:

```text
total expected liabilities
number of successful deposits
number of releases
cumulative fees
```

Non devono diventare una seconda implementazione complessa del protocollo, altrimenti rischi di duplicare lo stesso bug.

---

## 42. Invariant test contract

### `test/invariant/CreditVaultInvariant.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    StdInvariant
} from
    "forge-std/StdInvariant.sol";

import {Test} from
    "forge-std/Test.sol";

import {
    CreditVault
} from
    "../../src/invariant/CreditVault.sol";

import {
    TestToken
} from "../mocks/TestToken.sol";

import {
    VaultHandler
} from
    "./handlers/VaultHandler.sol";

contract CreditVaultInvariant is
    StdInvariant,
    Test
{
    TestToken token;
    CreditVault vault;
    VaultHandler handler;

    function setUp() public {
        token =
            new TestToken();

        vault =
            new CreditVault(token);

        handler =
            new VaultHandler(
                vault,
                token
            );

        targetContract(
            address(handler)
        );
    }

    function invariant_VaultIsSolvent()
        public
        view
    {
        assertEq(
            token.balanceOf(
                address(vault)
            ),
            vault.totalCredit()
        );
    }
}
```

Foundry fuzzera le funzioni esterne del handler target.

---

## 43. Perché targettiamo l'handler

Se facessimo:

```solidity
targetContract(
    address(vault)
);
```

Foundry genererebbe call direttamente a:

```text
deposit
withdraw
```

da caller/input generati secondo il framework.

Questo può essere utile in alcuni test.

Ma con handler possiamo modellare:

```text
actors
approvals
valid amount ranges
ghost accounting
```

e ottenere sequenze più significative.

---

## 44. Invariant: ghost accounting

Possiamo aggiungere:

```solidity
function invariant_GhostAccounting()
    public
    view
{
    assertEq(
        handler.ghostDeposited()
            - handler.ghostWithdrawn(),
        vault.totalCredit()
    );
}
```

Questa proprietà verifica il protocollo da un secondo punto di vista.

---

## 45. Due invarianti indipendenti

Ora abbiamo:

```text
A:
token balance == totalCredit

B:
ghost deposits - ghost withdrawals
== totalCredit
```

Se entrambi falliscono, indizio.

Se solo uno fallisce, l'analisi può dirci se è:

```text
protocol bug
handler bookkeeping bug
```

Più osservabili indipendenti possono migliorare la diagnosi.

---

## 46. Ma attenzione a duplicare la stessa formula

Se `ghostDeposited` viene aggiornato copiando esattamente la stessa logica buggy del protocollo, potresti avere:

```text
bug nel protocollo
+
stesso bug nel ghost model
=
test passa
```

Le ghost variables dovrebbero preferibilmente registrare **eventi fattuali**:

```text
"deposit successful amount x"
```

non replicare tutta la business logic.

---

## 47. Invariante di solvibilità

Per un protocollo più generale:

```text
assets >= liabilities
```

è spesso una delle proprietà più preziose.

Esempi:

```text
ETH balance
>=
sum credits

ERC20 balance
>=
total claimable
```

È una proprietà economica.

Non riguarda soltanto l'assenza di revert.

---

## 48. Invariante terminal state

Per un singolo Escrow:

```text
Released
Refunded
```

sono terminali.

Una property potrebbe essere:

```text
once terminal,
never returns to Funded/Created
```

Ma per verificarla serve ricordare se il terminal state è stato raggiunto.

Ghost variable:

```solidity
bool public ghostTerminalSeen;
```

Quando handler osserva release/refund riuscita:

```solidity
ghostTerminalSeen = true;
```

Poi invariante:

```text
ghostTerminalSeen
=>
current state is terminal
```

---

## 49. Perché serve il ghost

Se guardi soltanto lo stato corrente:

```text
state == Funded
```

non sai se in passato il contratto era:

```text
Released
```

e poi è tornato illegalmente indietro.

Serve memoria storica lato test.

Questa è una delle funzioni più potenti delle ghost variables.

---

# Handler avanzati e configurazione invariant

## 50. Handler per state machine

Immagina:

```solidity
function deposit(uint256 amount)
function release()
function refund()
```

L'handler può avere:

```text
deposit(seed)
release(seed)
refund(seed)
```

e scegliere caller autorizzati/non autorizzati.

Puoi decidere se modellare:

```text
solo valid actions
```

oppure anche:

```text
invalid adversarial actions
```

Sono due strategie diverse.

---

## 51. Bounded handler

Un bounded handler prova soprattutto sequenze **valide**.

Esempio:

```text
deposit solo se Created
release solo se Funded
refund solo se Funded
```

Vantaggio:

```text
più profondità nel reachable state
```

Svantaggio:

```text
testa meno failure path
```

---

## 52. Adversarial handler

Un adversarial handler può tentare:

```text
release da Created
refund due volte
stranger deposit
```

e verificare che i revert siano innocui.

Vantaggio:

```text
test failure handling
```

Svantaggio:

```text
molte call possono revertire/no-op
```

Spesso conviene avere:

```text
unit/negative fuzz tests
+
stateful handler orientato agli stati validi
```

e un secondo handler/adversarial suite se serve.

---

## 53. `fail_on_revert`

Foundry invariant configuration consente di decidere come trattare i revert durante l'esplorazione.

Concettualmente:

```text
fail_on_revert = false
```

permette sequenze in cui alcune action revertano senza considerare automaticamente l'invariante fallito.

```text
fail_on_revert = true
```

trasforma ogni revert inatteso in failure.

La scelta dipende dal modello.

Se il tuo handler dovrebbe generare solo azioni valide:

```text
fail_on_revert = true
```

può rivelare bug dell'handler/protocollo.

---

## 54. Configurazione invariant

Esempio concettuale `foundry.toml`:

```toml
[profile.default.invariant]
runs = 256
depth = 64
fail_on_revert = false
```

`runs`:

```text
quante sequenze indipendenti
```

`depth`:

```text
quante call circa per sequenza
```

Controlla sempre la reference della versione Foundry installata per i nomi/opzioni correnti.

---

## 55. Depth

Con:

```text
depth = 5
```

potresti esplorare:

```text
deposit
withdraw
deposit
withdraw
deposit
```

Con:

```text
depth = 100
```

puoi raggiungere stati più profondi.

Ma più depth significa anche più costo computazionale.

Non sostituisce un action model ben progettato.

---

## 56. Target selectors

A volte non vuoi che Foundry chiami tutte le funzioni esterne del handler.

Puoi restringere i selector target.

Concettualmente:

```solidity
bytes4[] memory selectors =
    new bytes4[](2);

selectors[0] =
    VaultHandler.deposit.selector;

selectors[1] =
    VaultHandler.withdraw.selector;
```

Poi configuri il target selector tramite `StdInvariant`.

Questo rende l'action space esplicito.

---

## 57. Perché limitare selectors

Un handler può contenere helper esterni per:

```text
debug
view
configuration
```

che non vuoi fuzzare come actions.

L'action set deve rappresentare:

```text
operazioni che il fuzzer deve esplorare
```

non:

```text
ogni external function esistente
```

---

## 58. Target sender

Foundry permette anche di controllare sender/target in invariant testing.

Con handler, spesso preferiamo gestire gli actor internamente:

```solidity
vm.prank(actor)
```

perché ci dà controllo esplicito sul modello degli utenti.

Ma in altri casi il sender stesso può essere parte dello spazio fuzzato.

---

## 59. `targetContract` non è una security property

Scrivere:

```solidity
targetContract(address(handler));
```

non dimostra nulla.

Serve soltanto a definire l'action source.

La qualità dell'invariant test dipende da:

```text
invariant quality
+
handler quality
+
state reachability
+
action distribution
```

---

# Invarianti forti, deboli e mutation test

## 60. Invariante non tautologico

Questo è inutile:

```solidity
function invariant_TotalCreditEqualsItself()
    public
    view
{
    assertEq(
        vault.totalCredit(),
        vault.totalCredit()
    );
}
```

Ovviamente passa.

Più sottilmente inutile:

```solidity
assertEq(
    vault.totalCredit(),
    helper.readTotalCreditFromVault()
);
```

se l'helper legge lo stesso valore.

Vuoi fonti indipendenti.

---

## 61. Esempi di invarianti forti

### Solvibilità

```text
asset >= liabilities
```

### Conservation

```text
initial + deposits
=
vault balance + withdrawals
```

### Authorization state

```text
owner changes only through authorized path
```

### Terminality

```text
once terminal, never non-terminal
```

### Supply consistency

```text
sum tracked balances
=
total tracked supply
```

quando il modello lo consente.

---

## 62. Esempi di invarianti deboli

```text
balance >= 0
```

per `uint256` è tautologico.

```text
state <= 3
```

se enum Solidity rende comunque impossibili altri valori attraverso il normale codice.

```text
contract address != 0
```

dopo deployment è quasi irrilevante.

Un buon invariante protegge una proprietà che potrebbe realisticamente rompersi.

---

## 63. Mutation test degli invarianti

Prendi il vault corretto:

```solidity
totalCredit -= amount;
```

Mutalo in:

```solidity
// totalCredit non diminuisce
```

Ora:

```text
token balance
<
totalCredit
```

dopo un withdrawal.

L'invariante di solvibilità deve trovare la violazione.

Se non la trova:

```text
handler non raggiunge withdrawal
```

o:

```text
invariante è sbagliato
```

---

## 64. Mutation: doppio credito

Mutazione:

```solidity
credit[msg.sender] += amount;
totalCredit += amount * 2;
```

L'invariant test dovrebbe fallire molto rapidamente:

```text
vault balance < totalCredit
```

Questo è un buon sanity check della suite.

---

## 65. Mutation: withdraw troppo

Vulnerable change:

```solidity
if (
    amount > credit[msg.sender] * 2
) revert;
```

Se l'handler usa sempre:

```text
amount <= available
```

non troverà mai questo bug.

Questo dimostra un limite dei bounded handlers.

Per quella property serve anche un adversarial test che tenta:

```text
available + 1
```

---

## 66. Invariant testing non sostituisce negative testing

Questa è una regola importante:

```text
bounded stateful invariant
```

ottimizza l'esplorazione degli stati validi.

I test negativi verificano:

```text
l'impossibilità degli stati invalidi
```

Servono entrambi.

---

# Copertura degli handler e invarianti di protocollo

## 67. Handler coverage

Aggiungi ghost counters:

```solidity
uint256 public callsDeposit;
uint256 public callsWithdraw;
```

Nel handler:

```solidity
callsDeposit++;
```

e:

```solidity
callsWithdraw++;
```

Durante debugging puoi vedere:

```text
il fuzzer sta davvero raggiungendo entrambe le azioni?
```

Questo è utilissimo.

---

## 68. No-op ratio

Se:

```text
withdraw called = 10,000
successful withdraw = 12
```

il fuzzer sta sprecando gran parte delle call.

Puoi migliorare l'handler:

```text
scegli actor con credito
bound amount al credito
```

L'obiettivo non è eliminare tutti i revert.

È aumentare la quantità di state exploration utile.

---

## 69. Actor set

Tre actor possono bastare per molte proprietà:

```text
Alice
Bob
Carol
```

Perché non 10.000?

Più actor ampliano il dominio, ma possono rendere più difficile raggiungere stati profondi per ciascuno.

Scegli in base alla property.

Per:

```text
cross-user accounting
```

almeno due actor sono importanti.

---

## 70. Invariante cross-user

Property:

```text
totalCredit
=
credit[Alice]
+ credit[Bob]
+ credit[Carol]
```

Se l'handler limita gli utenti a tre, puoi verificarla.

```solidity
function invariant_TotalCreditMatchesUsers()
    public
    view
{
    uint256 sum =
        vault.credit(alice)
        + vault.credit(bob)
        + vault.credit(carol);

    assertEq(
        sum,
        vault.totalCredit()
    );
}
```

Ma devi esporre gli actor dal handler oppure con getter.

---

## 71. Ghost model vs on-chain sum

Un mapping non è enumerabile nativamente.

Per sapere:

```text
sum(all credit)
```

hai opzioni:

```text
1. limitare actor set;
2. tenere ghost total;
3. protocollo mantiene totalCredit;
```

Questa è una ragione per cui `totalCredit` può essere utile anche per invarianti operativi.

---

## 72. Handler actor getter

Nel handler:

```solidity
function actor(
    uint256 i
) external view returns (address) {
    return actors[i];
}
```

oppure getter specifici.

Così l'invariant contract può leggere gli utenti modellati.

---

## 73. Conservation law

Supponiamo che inizialmente il vault abbia zero token.

Ghost:

```text
deposited
withdrawn
```

Property:

```text
deposited - withdrawn
=
current vault token balance
```

e:

```text
deposited - withdrawn
=
totalCredit
```

Quindi:

```text
vault balance
=
totalCredit
```

otteniamo tre relazioni collegate.

---

## 74. Evitare underflow nelle ghost assertions

Se sai che il bookkeeping corretto implica:

```text
ghostDeposited >= ghostWithdrawn
```

puoi prima verificarlo:

```solidity
assertGe(
    handler.ghostDeposited(),
    handler.ghostWithdrawn()
);
```

poi sottrarre.

Se questa prima property fallisce, hai trovato un problema nel modello o nel protocollo.

---

## 75. Invariant di access control

È più difficile di una normale assertion.

Per esempio:

```text
fee può cambiare solo dopo governance
```

Serve spesso ghost bookkeeping.

Il handler registra:

```text
last authorized fee
```

e ogni action governance aggiorna il ghost.

Poi:

```text
escrow.feeBps == ghostExpectedFee
```

Se una funzione non autorizzata modifica fee, l'invariante diverge.

---

## 76. Stateful governance testing

Handler actions potrebbero essere:

```text
scheduleFee
warpToReady
executeFee
cancelFee
pause
unpause
```

Gli invarianti:

```text
fee changes only after executed operation

cancelled op cannot affect fee

paused flag changes only through authorized path
```

È potente ma complesso.

Costruiscilo soltanto dopo avere unit test solidi.

---

## 77. Non partire dall'invariant test più complesso

Progressione consigliata:

```text
1. unit tests
2. negative tests
3. fuzz individual functions
4. simple invariant
5. handler
6. ghost variables
7. multi-contract invariants
```

Altrimenti quando fallisce non sai dove guardare.

---

## 78. Invariant testing di reentrancy

Non serve necessariamente generare "attacchi reali".

Puoi includere un receiver locale che durante callback prova:

```text
withdraw di nuovo
```

e verificare:

```text
assets >= liabilities
```

Il callback è soltanto una action locale nel modello.

La property resta difensiva.

---

## 79. Invariant testing di token anomali

Puoi avere handler/mocks con modalità:

```text
normal
return false
fee
revert
```

Ma non mischiare tutte le classi di token nello stesso invariante se la specification non le supporta.

Prima dichiara:

```text
asset policy
```

Poi testa quella policy.

---

## 80. Asset policy e invarianti

Se supporti soltanto exact-transfer token:

```text
balance == totalCredit
```

Se supporti donation:

```text
balance >= totalCredit
```

Se supporti fee-on-transfer con balance-delta accounting:

```text
credited == received
```

Se supporti rebase:

la property potrebbe essere completamente differente.

Questo mostra quanto invariant testing dipenda dalla specification.

---

# Failure, riproducibilità e suite in CI

## 81. Test di invariant failure

Quando un invariante fallisce, Foundry fornisce informazioni sulla sequenza che ha portato allo stato problematico.

Il workflow è:

```text
1. leggi la failing sequence;
2. riproducila come regression test deterministico;
3. identifica la property violata;
4. correggi;
5. mantieni sia invariant sia regression.
```

Questo trasforma una scoperta automatica in un test permanente semplice.

---

## 82. Perché creare una regression dopo il fuzz failure

L'invariant test può trovare una sequenza come:

```text
deposit Alice 17
withdraw Alice 16
deposit Bob 2
withdraw Alice 1
...
```

Dopo la correzione, vuoi un test piccolo:

```text
specific bug sequence
```

che fallisca immediatamente se il bug torna.

Invariant test:

```text
discovery
```

Regression:

```text
permanent guardrail
```

---

## 83. Seed e riproducibilità

Foundry permette di riprodurre fuzz failures attraverso informazioni stampate/output e opzioni di test.

Quando trovi un failure:

```text
non limitarti a rilanciare sperando
```

Conserva:

```text
counterexample
sequence
seed/config se utile
```

e crea un regression test esplicito.

---

## 84. Fuzz dictionary

I fuzz engine moderni possono apprendere/utilizzare valori interessanti dal bytecode/calldata e dai risultati.

Per noi il punto concettuale è:

```text
branch boundaries
constants
selectors
```

possono aiutare l'esplorazione.

Ma non affidarti al fuzzer per sostituire test mirati a:

```text
0
MAX_FEE
MAX_FEE + 1
```

---

## 85. Dynamic test linking

Alcune modalità avanzate di Foundry possono migliorare il comportamento dei test che coinvolgono librerie/bytecode dinamico.

Non è necessario per questo laboratorio.

Il principio del corso resta:

```text
usa la feature più semplice
che verifica bene la property
```

---

## 86. Invariant test file structure

Suggerimento:

```text
test/
└── invariant/
    ├── CreditVaultInvariant.t.sol
    ├── EscrowStateInvariant.t.sol
    └── handlers/
        ├── VaultHandler.sol
        └── EscrowHandler.sol
```

Tenere handler separati migliora la leggibilità.

---

## 87. Configurazione separata CI

Esempio:

```toml
[profile.default.fuzz]
runs = 256

[profile.default.invariant]
runs = 128
depth = 64

[profile.ci.fuzz]
runs = 5000

[profile.ci.invariant]
runs = 1000
depth = 128
```

I numeri sono esempi didattici, non valori universali.

Misura i tempi della tua suite.

---

## 88. Unit suite + fuzz suite + invariant suite

Una pipeline robusta:

```text
forge test
        |
        +--> unit
        +--> negative
        +--> regression
        +--> fuzz
        +--> invariant
```

Puoi filtrare per path/contract durante sviluppo.

---

# Progettare proprietà e modelli realistici

## 89. Una property può valere solo sotto precondizioni

Esempio:

```text
quote monotonic
```

può dipendere da:

```text
price > 0
oracle fresh
no overflow
```

Scrivi queste precondizioni chiaramente.

Il fuzz test non deve "scoprire" ogni volta che la funzione non è definita fuori dal dominio.

---

## 90. Evitare test oracle-dependent inconsapevoli

Se il fuzz test riguarda:

```text
amount scaling
```

fissa il price del mock.

Non fuzzare contemporaneamente:

```text
amount
price
age
decimals
```

se non stai testando una property che coinvolge tutte queste dimensioni.

Riduci il numero di variabili per isolare il problema.

---

## 91. Incremental dimensionality

Progressione:

```text
fuzz amount

poi:
fuzz amount + price

poi:
fuzz amount + price + decimals
```

Ogni dimensione aumenta lo spazio.

Aggiungila solo quando la property lo richiede.

---

## 92. Differential thinking

Puoi confrontare:

```text
implementation contract
```

contro:

```text
reference model
```

Esempio fee:

```solidity
uint256 expected =
    amount / 10_000 * feeBps
    + ...
```

Ma attento a non copiare esattamente la stessa formula.

Un reference model dovrebbe essere concettualmente indipendente quando possibile.

Approfondiremo il differential testing in contesti appropriati.

---

## 93. Invariant testing e external calls

Se il protocollo chiama mock esterni, questi fanno parte dello stato della run.

Puoi fuzzare anche la dependency state.

Esempio handler:

```text
setOracleFresh
setOracleStale
deposit
release
```

Poi property:

```text
stale oracle never permits price-sensitive transition
```

Questo è un esempio di multi-contract invariant testing.

---

## 94. Ma attenzione alle action irrealistiche

Se il tuo real system non consente a chiunque di:

```text
setOraclePrice
```

non dare al fuzzer quel potere senza rappresentare il ruolo corretto.

Altrimenti potresti trovare stati:

```text
impossibili nel threat model reale
```

Un invariant test vale quanto il suo state-transition model.

---

## 95. Adversarial capability deve essere realistica

Puoi modellare:

```text
unprivileged user
compromised admin
malicious token
```

ma sono threat model diversi.

Mantieni suite separate:

```text
normal user invariants
admin-compromise analysis
malicious dependency analysis
```

Non confondere tutte le capabilities in un unico handler.

---

## 96. Liveness invariants

Le safety properties sono più semplici:

```text
bad thing never happens
```

Liveness:

```text
good thing eventually can happen
```

è più difficile da esprimere con invarianti semplici.

Esempio:

```text
funded user can eventually withdraw
```

richiede ragionare sulle azioni disponibili.

Possiamo testare reachability e absence of permanent lock in scenari mirati, ma non confondere questo con una semplice `assert`.

---

## 97. Invariant of no stuck liability

Una property pratica per Escrow potrebbe essere:

```text
terminal state
=> escrowedAmount == 0
```

Questo è safety.

Più complessa:

```text
Funded
=> esiste almeno una transizione autorizzata
verso Release o Refund
```

è una property di liveness/reachability.

La seconda richiede metodologia più sofisticata.

---

# Checklist, laboratorio e chiusura

## 98. Checklist da auditor — fuzz tests

Quando leggi fuzz test:

- [ ] property dichiarata chiaramente?
- [ ] dominio realistico?
- [ ] bound appropriato?
- [ ] assumptions troppo restrittive?
- [ ] zero/boundary conservati come regression?
- [ ] caller fuzzato quando rilevante?
- [ ] revert preciso?
- [ ] counterexample riproducibile?
- [ ] input normalizzati senza cambiare la property?
- [ ] overflow del test stesso considerato?
- [ ] reference model indipendente?

---

## 99. Checklist da auditor — invariant tests

- [ ] invariante economicamente significativo?
- [ ] non tautologico?
- [ ] state space realistico?
- [ ] handler raggiunge stati interessanti?
- [ ] troppe call sono no-op?
- [ ] actor set adeguato?
- [ ] selectors corretti?
- [ ] ghost variables affidabili?
- [ ] fail_on_revert scelto consapevolmente?
- [ ] runs/depth ragionevoli?
- [ ] external dependencies modellate?
- [ ] donation/rebase/fee policy definita?
- [ ] terminal states verificati?
- [ ] solvibilità verificata?
- [ ] ogni failure diventa regression?

---

## 100. Laboratorio completo

Struttura:

```text
fuzz-invariant-lab/
├── foundry.toml
├── src/
│   └── invariant/
│       └── CreditVault.sol
└── test/
    ├── fuzz/
    │   ├── EscrowFuzz.t.sol
    │   └── OracleFuzz.t.sol
    ├── invariant/
    │   ├── CreditVaultInvariant.t.sol
    │   └── handlers/
    │       └── VaultHandler.sol
    └── mocks/
        └── TestToken.sol
```

Comandi:

```bash
forge test
```

Solo fuzz:

```bash
forge test \
  --match-path "test/fuzz/*"
```

Solo invariant:

```bash
forge test \
  --match-path "test/invariant/*"
```

Con trace:

```bash
forge test -vvvv \
  --match-contract CreditVaultInvariant
```

---

## 101. Config di laboratorio

Esempio:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]

[profile.default.fuzz]
runs = 256

[profile.default.invariant]
runs = 128
depth = 64
fail_on_revert = false
```

Poi prova un profilo più intenso:

```toml
[profile.deep.fuzz]
runs = 5000

[profile.deep.invariant]
runs = 1000
depth = 128
fail_on_revert = false
```

Esegui:

```bash
FOUNDRY_PROFILE=deep forge test
```

---

## 102. Esercizi

### Esercizio 1 — Deposit fuzz

Scrivi:

```solidity
testFuzz_DepositRecordsAmount
```

per:

```text
1 <= amount <= 1e24
```

Verifica:

```text
amount
funded
```

---

### Esercizio 2 — Unauthorized caller

Fuzza:

```text
caller
amount
```

con:

```text
caller != buyer
```

e verifica `OnlyBuyer`.

---

### Esercizio 3 — Fee boundaries

Per una fee `<= 1000 bps`, fuzza:

```text
0..1000 -> accepted
1001..type(uint16).max -> rejected
```

Scrivi due fuzz test distinti.

---

### Esercizio 4 — Oracle freshness

Fuzza `age` nei due domini:

```text
0..MAX_AGE
MAX_AGE+1 .. MAX_AGE+30 days
```

---

### Esercizio 5 — Monotonicity

Verifica:

```text
a <= b
=> quote(a) <= quote(b)
```

senza usare un'assumption altamente selettiva.

---

### Esercizio 6 — Primo invariant

Implementa:

```text
vault token balance
==
totalCredit
```

con handler `deposit/withdraw`.

---

### Esercizio 7 — Ghost accounting

Aggiungi:

```text
ghostDeposited
ghostWithdrawn
```

e verifica:

```text
ghostDeposited - ghostWithdrawn
==
totalCredit
```

---

### Esercizio 8 — Mutation

Rimuovi temporaneamente:

```solidity
totalCredit -= amount;
```

da `withdraw`.

Il tuo invariant deve fallire.

Salva poi una sequenza minima come regression test.

---

### Esercizio 9 — Actor sum

Con tre actor fissi verifica:

```text
credit[A]
+ credit[B]
+ credit[C]
=
totalCredit
```

---

### Esercizio 10 — Terminal-state invariant

Costruisci un handler per:

```text
Created
Funded
Released
Refunded
```

e una ghost variable che ricordi se è stato raggiunto un terminal state.

Verifica:

```text
once terminal,
never returns to Created/Funded
```

---

### Esercizio 11 — Adversarial withdrawal

Aggiungi un'azione separata che tenta:

```text
withdraw(credit + 1)
```

e verifica che:

```text
credit
totalCredit
vault balance
```

rimangano invariati.

Non sostituire con questo il bounded `withdraw`: servono entrambi.

---

### Esercizio 12 — Audit challenge

Analizza:

```solidity
function testFuzz_Deposit(
    uint256 amount
) public {
    vm.assume(
        amount == 100
    );

    vault.deposit(amount);

    assertTrue(
        vault.totalCredit() >= 0
    );
}
```

Trova almeno **sei problemi**.

---

## 103. Cosa devo ricordare

### 1. Fuzzing testa una proprietà su molti input

Non significa "random testing senza specifica".

---

### 2. `bound` e `assume` modellano il dominio

Usali per descrivere input realistici, non per nascondere failure.

---

### 3. Troppi `assume` possono distruggere l'esplorazione

Preferisci normalizzare quando possibile.

---

### 4. Un fuzz failure produce un counterexample

Trasformalo in un regression test.

---

### 5. Invariant testing è stateful

Foundry prova sequenze di azioni sullo stesso stato.

---

### 6. L'handler definisce il mondo che il fuzzer può esplorare

Se il modello è povero, il test è povero.

---

### 7. Ghost variables aggiungono memoria/verifica indipendente

Ma non devono duplicare tutta la business logic.

---

### 8. Solvibilità è un ottimo invariante economico

```text
assets >= liabilities
```

quando coerente con la specification.

---

### 9. Bounded handler e negative testing hanno ruoli differenti

Uno esplora bene gli stati validi; l'altro prova azioni proibite.

---

### 10. Più run non compensano una property debole

La qualità dell'invariante viene prima del numero di sequenze.

---

## 104. Collegamento con il corso

Abbiamo ora questa pipeline:

```text
requirements
    |
    v
unit tests
    |
    v
negative tests
    |
    v
regression tests
    |
    v
fuzz tests
    |
    v
stateful invariant tests
```

Il prossimo passo sarà cambiare ancora prospettiva.

Finora abbiamo verificato il codice **eseguendolo**.

Nella prossima lezione inizieremo a cercare problemi analizzando anche la sua struttura senza dover conoscere a priori un input che li attivi:

**Lezione 15 — Analisi statica: Slither, compiler warnings, detectors, triage e integrazione con l'audit manuale.**

---

## 105. Fonti della lezione

Fonti tecniche consultate il **21 settembre 2026**:

1. **Foundry Documentation — Fuzz Testing**  
   Riferimento ufficiale per property-based fuzz tests, input generation, failure/counterexamples e configurazione delle fuzz runs.  
   https://getfoundry.sh/forge/advanced-testing/fuzz-testing

2. **Foundry Documentation — Invariant Testing**  
   Riferimento ufficiale per stateful invariant testing, run/depth, target configuration e strategie di invariant testing.  
   https://getfoundry.sh/forge/advanced-testing/invariant-testing

3. **Foundry Documentation — Invariant Testing / Handler-Based Testing**  
   Riferimento per handler, action space, ghost variables e modellazione di sequenze stateful.  
   https://getfoundry.sh/forge/advanced-testing/invariant-testing

4. **Forge Std — `StdInvariant`**  
   Utility Foundry per configurare target contracts, selectors, senders e invariant fuzzing.  
   https://getfoundry.sh/reference/forge-std/std-invariant

5. **Foundry Cheatcodes — `assume`**  
   Semantica delle assumption nel fuzzing e limitazione del dominio degli input.  
   https://getfoundry.sh/reference/cheatcodes/assume

6. **Forge Std — `bound`**  
   Utility per mappare input fuzzati in intervalli validi senza scartare massicciamente casi.  
   https://getfoundry.sh/reference/forge-std/bound

7. **OpenZeppelin Contracts 5.x — Writing Automated Tests**  
   Principi generali di automated testing e valore delle proprietà specifiche nei test smart contract.  
   https://docs.openzeppelin.com/contracts/5.x/learn/writing-automated-tests

8. **OpenZeppelin Contracts 5.x**  
   Riferimento per `IERC20`, `SafeERC20` e le primitive usate nel vault locale.  
   https://docs.openzeppelin.com/contracts/5.x

9. **Foundry Documentation — Configuration**  
   Riferimento per profili e configurazione di fuzz/invariant test in `foundry.toml`.  
   https://getfoundry.sh/config/reference/overview

---

# Fine Lezione 14

Prossimo argomento:

**Analisi statica con Slither: detector, data dependency, call graph, inherited contracts, false positive, triage e combinazione con testing/audit manuale.**
