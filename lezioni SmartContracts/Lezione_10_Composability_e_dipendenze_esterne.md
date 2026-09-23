# Lezione 10 — Composability e dipendenze esterne

> **Scopo:** secure coding, auditing, threat modeling e testing.  
> Tutti gli esempi e i contratti di questa lezione sono giocattolo e destinati esclusivamente a Foundry/Anvil in locale.

## 1. Obiettivi

Alla fine della lezione dovresti saper:

- spiegare che cosa significa **composability** in Ethereum;
- trattare ogni contratto esterno come una **trust boundary**;
- distinguere compatibilità ABI da affidabilità semantica;
- capire come un revert esterno si propaga al chiamante;
- usare `try/catch` quando il protocollo ha una vera strategia di recovery;
- comprendere la differenza tra high-level call e low-level `call`;
- riconoscere il rischio di ignorare il booleano restituito da `call`;
- analizzare target configurabili dall'utente o dall'admin;
- capire perché un dependency address immutabile riduce alcune superfici ma non elimina il rischio;
- comprendere il rischio di dipendenze proxy/upgradeabili;
- progettare fail-open vs fail-closed in modo esplicito;
- testare dipendenze che funzionano, revertano, restituiscono valori inattesi o cambiano comportamento;
- formulare invarianti che restino validi anche quando una dipendenza fallisce.

---

## 2. Modello mentale

Ethereum incoraggia la composability.

Un contratto può usare un altro contratto come componente:

```text
Escrow
  |
  +--> ERC20
  |
  +--> Oracle
  |
  +--> Router
```

Questa è una delle caratteristiche più potenti dell'ecosistema, ma ogni componente aggiunge anche:

```text
codice che non controlli
stato che non controlli
governance che non controlli
failure mode che devi comprendere
```

Il modello mentale corretto non è:

```text
"chiamo una funzione"
```

ma:

```text
"cedo temporaneamente il controllo a un altro componente
 e assumo che rispetti una certa semantica"
```

---

## 3. Teoria

### 3.1 Che cos'è la composability

Ethereum.org descrive gli smart contract come componenti pubblici e riusabili, analoghi ad API aperte. Un protocollo può quindi comporre token, DEX, oracle, lending protocol e vault in un sistema più grande.

Il vantaggio è enorme:

```text
riuso
interoperabilità
modularità
innovazione
```

Dal punto di vista security, però:

```text
più composizione = più assunzioni
```

### 3.2 External call = codice sconosciuto

Una formulazione molto utile viene anche dal modello del Solidity SMTChecker: per default, una external call viene trattata come chiamata a codice sconosciuto.

Anche se hai un'interfaccia:

```solidity
interface IRouter {
    function swap(
        uint256 amountIn,
        uint256 minOut
    ) external returns (uint256);
}
```

non hai ancora dimostrato che il contratto a quell'indirizzo:

- sia quello che pensi;
- continui a esserlo;
- abbia la semantica attesa;
- non faccia callback;
- non revirti;
- non restituisca valori economicamente assurdi.

### 3.3 ABI compatibility != semantic compatibility

Supponiamo:

```solidity
interface IRateProvider {
    function rate()
        external
        view
        returns (uint256);
}
```

Tre contratti possono implementare la stessa ABI:

```text
Provider A -> prezzo con 18 decimals
Provider B -> prezzo con 8 decimals
Provider C -> restituisce sempre 0
```

Tutti possono essere ABI-compatible.

Ma non sono semanticamente intercambiabili.

Quindi:

```text
ABI compatibility
```

significa soltanto:

```text
"so come codificare la call e decodificare il return"
```

non:

```text
"questa dipendenza soddisfa le proprietà del mio protocollo"
```

### 3.4 High-level external call

Esempio:

```solidity
uint256 out = router.swap(
    amountIn,
    minOut
);
```

Dal punto di vista EVM è una message call:

```text
Escrow
  |
  | CALL
  v
Router
```

Non nasce una nuova transazione: è una sub-call della transazione corrente.

### 3.5 Revert propagation

Supponiamo:

```text
User -> Escrow -> Router
```

Se `Router` reverte, una normale high-level call propaga il fallimento:

```text
Router reverts
   |
   v
Escrow reverts
   |
   v
transaction reverts
```

Le modifiche di stato della call tree vengono annullate.

Questa atomicità è spesso utile, ma introduce una domanda di liveness:

```text
se la dependency reverte sempre,
la nostra funzione può diventare inutilizzabile
```

### 3.6 Fail-closed vs fail-open

**Fail-closed**:

```text
dependency fails
=> operation fails
```

Esempio: un oracle necessario alla solvibilità non è disponibile.

**Fail-open**:

```text
dependency fails
=> protocollo continua con percorso alternativo
```

Esempio: una notifica accessoria fallisce ma il pagamento principale può comunque completarsi.

La domanda corretta non è:

```text
"try/catch è più sicuro?"
```

ma:

```text
"se questa dipendenza fallisce,
 quale proprietà del protocollo deve prevalere?"
```

---

## 4. Esempio Solidity: dependency accessoria

### `src/NotificationEscrow.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

interface INotifier {
    function notifyReleased(
        address seller,
        uint256 amount
    ) external;
}

contract NotificationEscrow {
    INotifier public immutable notifier;

    address public immutable buyer;
    address public immutable seller;

    uint256 public amount;
    bool public released;

    event NotificationFailed(bytes reason);

    error OnlyBuyer();
    error AlreadyReleased();

    constructor(
        INotifier notifier_,
        address buyer_,
        address seller_,
        uint256 amount_
    ) {
        notifier = notifier_;
        buyer = buyer_;
        seller = seller_;
        amount = amount_;
    }

    function release() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (released) revert AlreadyReleased();

        released = true;

        try notifier.notifyReleased(
            seller,
            amount
        ) {
            // notifica riuscita
        } catch (bytes memory reason) {
            emit NotificationFailed(reason);
        }
    }
}
```

Qui scegliamo esplicitamente:

```text
notifier failure != release failure
```

Questa scelta è corretta soltanto se la notifica è davvero accessoria.

---

## 5. Analisi del codice

### `release()`

**Chi può chiamarla?**

Solo `buyer`.

**Input controllati dal caller?**

Nessun parametro diretto.

**Stato letto**

```text
buyer
released
seller
amount
notifier
```

**Stato modificato**

```solidity
released = true;
```

**External call**

```solidity
notifier.notifyReleased(...)
```

**Quando passa il controllo fuori?**

Durante il `try`.

**Assunzione critica**

```text
la notifica è opzionale
```

Se questa assunzione fosse falsa, il `catch` creerebbe un bug di business logic.

---

## 6. `try/catch` non deve nascondere errori importanti

Questo pattern può essere pericoloso:

```solidity
try oracle.read()
    returns (uint256 price) {
    usePrice(price);
}
catch {
    // continua come se niente fosse
}
```

Domanda:

```text
con quale prezzo continui?
```

Se il catch introduce un valore arbitrario o usa indefinitamente un dato vecchio, il failure esplicito è stato trasformato in stato ambiguo.

Ogni `catch` dovrebbe rispondere a:

```text
1. cosa è fallito?
2. cosa facciamo ora?
3. quale proprietà resta valida?
4. possiamo ritentare?
5. dobbiamo mettere in pausa?
```

---

## 7. Low-level `call`

Forma:

```solidity
(
    bool success,
    bytes memory returndata
) = target.call(data);
```

A differenza della normale high-level call, un revert del callee non viene automaticamente propagato: ottieni `success = false` e devi gestirlo.

### Vulnerabilità classica: unchecked call

```solidity
function invoke(
    address target,
    bytes calldata data
) external {
    target.call(data);
    completed = true;
}
```

Qui il codice può dichiarare successo anche se la dipendenza ha revertito.

---

## 8. Vulnerabilità locale: falso successo

### `src/UncheckedDependency.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract UncheckedDependency {
    bool public completed;

    function run(
        address target,
        bytes calldata data
    ) external {
        target.call(data);
        completed = true;
    }
}
```

### `src/mocks/RevertingDependency.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract RevertingDependency {
    error DependencyFailure();

    function execute() external pure {
        revert DependencyFailure();
    }
}
```

### Perché è vulnerabile

Il chiamante assume implicitamente:

```text
ho eseguito call
=> quindi l'azione è riuscita
```

ma low-level `call` restituisce l'esito invece di propagarlo automaticamente.

La conseguenza è una incoerenza semantica:

```text
dependency action = fallita
completed         = true
```

### Correzione minimale

```solidity
(
    bool success,
    bytes memory returndata
) = target.call(data);

if (!success) {
    assembly ("memory-safe") {
        revert(
            add(returndata, 32),
            mload(returndata)
        )
    }
}
```

Quando possibile, una high-level interface è spesso più chiara.

OpenZeppelin fornisce anche helper come:

```solidity
Address.functionCall(...)
```

che verificano il successo e fanno bubbling del revert data.

---

## 9. Una sottigliezza: `success == true` non basta

Le low-level call operano a un livello più primitivo.

Solidity documenta che una low-level call verso un account inesistente può restituire `true` secondo la semantica EVM.

Quindi:

```text
success == true
```

non significa automaticamente:

```text
"ho chiamato il contratto corretto"
```

E neppure:

```text
"la semantica dell'operazione era corretta"
```

---

## 10. Target controllabile dall'utente

Considera:

```solidity
function execute(
    address router,
    bytes calldata data
) external {
    router.call(data);
}
```

Il chiamante controlla:

```text
router
data
```

Quindi controlla praticamente:

```text
codice invocato
funzione invocata
argomenti
```

Da auditor devi immediatamente chiederti:

```text
quali asset e allowance possiede questo contratto?
```

Questa è una superficie molto più ampia di un semplice parametro numerico.

---

## 11. Allowlist delle dipendenze

Un approccio possibile:

```solidity
mapping(address => bool)
    public allowedRouter;
```

con:

```solidity
if (!allowedRouter[router]) {
    revert RouterNotAllowed();
}
```

Questo riduce la superficie, ma introduce governance:

```text
chi aggiorna l'allowlist?
quanto rapidamente?
con quale review?
```

Una mitigation può creare una nuova trust boundary.

---

## 12. Immutable address != immutable behavior

```solidity
IRouter public immutable router;
```

riduce il rischio di sostituzione da parte del consumer.

Ma se `router` è un proxy upgradeabile:

```text
Consumer
   |
   v
Proxy address (stabile)
   |
   v
Implementation (mutabile)
```

l'indirizzo resta lo stesso ma la logica può cambiare.

Quindi:

```text
immutable address != immutable behavior
```

Questa sarà centrale nella Lezione 11.

---

## 13. Failure propagation e dipendenze transitive

Considera:

```text
Escrow
  |
  v
Router
  |
  v
Pool
  |
  v
Token
```

Se `Token` reverte, il failure può risalire tutta la call chain.

Una dipendenza indiretta può quindi rompere il nostro contratto anche se il nostro codice non la chiama direttamente.

Threat model:

```text
direct dependencies
+
transitive dependencies
```

---

## 14. Return valido ma semanticamente pericoloso

Un router può non revertire e restituire:

```text
out = 1
```

quando ti aspettavi circa:

```text
out = 1000
```

Il livello EVM dice:

```text
call riuscita
```

Il protocollo deve ancora verificare:

```text
risultato economicamente accettabile
```

Questo collega direttamente la Lezione 9:

```text
technical success != economic success
```

---

## 15. Mock semanticamente scorretto

### `src/mocks/WeirdRouter.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

interface IRouter {
    function swap(
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256);
}

contract WeirdRouter is IRouter {
    function swap(
        uint256,
        uint256
    ) external pure returns (uint256) {
        return 1;
    }
}
```

ABI corretta.

Semantica incompatibile con un consumer che pretende un output minimo.

### Consumer più robusto

```solidity
contract BoundedIntegrator {
    IRouter public immutable router;
    uint256 public lastOutput;

    error InsufficientOutput();

    constructor(IRouter router_) {
        router = router_;
    }

    function execute(
        uint256 amountIn,
        uint256 minOut
    ) external {
        uint256 out = router.swap(
            amountIn,
            minOut
        );

        if (out < minOut) {
            revert InsufficientOutput();
        }

        lastOutput = out;
    }
}
```

Anche se il router *dovrebbe* rispettare `minOut`, il consumer verifica nuovamente una proprietà che appartiene al proprio protocollo.

---

## 16. Dipendenza che cambia comportamento

### `src/mocks/MutableDependency.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract MutableDependency {
    enum Mode {
        Normal,
        RevertAlways,
        ReturnZero
    }

    Mode public mode;

    error Disabled();

    function setMode(
        Mode newMode
    ) external {
        mode = newMode;
    }

    function value()
        external
        view
        returns (uint256)
    {
        if (mode == Mode.RevertAlways) {
            revert Disabled();
        }

        if (mode == Mode.ReturnZero) {
            return 0;
        }

        return 100;
    }
}
```

Consumer:

```solidity
interface IValueProvider {
    function value()
        external
        view
        returns (uint256);
}

contract DependencyConsumer {
    IValueProvider public immutable provider;
    uint256 public lastGoodValue;

    error InvalidValue();

    constructor(
        IValueProvider provider_
    ) {
        provider = provider_;
    }

    function refresh() external {
        uint256 value = provider.value();

        if (value == 0) {
            revert InvalidValue();
        }

        lastGoodValue = value;
    }
}
```

Qui:

```text
provider revert -> fail-closed
provider zero   -> explicit validation
```

Ma resta una trust assumption:

```text
il significato di value() non cambia
```

---

## 17. Cache e stale data

Se introduci:

```solidity
lastGoodValue
lastUpdatedAt
```

per sopravvivere temporaneamente a un failure, devi definire anche:

```text
maxAge
```

altrimenti la cache può diventare valida per sempre.

Proprietà:

```text
cached value usable
=> block.timestamp - lastUpdatedAt <= maxAge
```

Questo collega la Lezione 9 sugli oracle.

---

## 18. Safety vs liveness

**Safety**:

```text
qualcosa di proibito non deve accadere
```

Esempio:

```text
non pagare due volte
non accettare output sotto minOut
```

**Liveness**:

```text
qualcosa di desiderato deve poter accadere
```

Esempio:

```text
un utente deve poter ritirare
un Escrow deve poter completare
```

Una dipendenza può compromettere la liveness anche senza sottrarre fondi.

---

## 19. Esempio di liveness bug

Design fragile:

```solidity
function withdraw() external {
    notifier.notify(msg.sender);
    _pay(msg.sender);
}
```

Se `notifier` reverte sempre:

```text
withdrawal impossibile
```

La dependency accessoria ha acquisito potere sui fondi.

Se la notifica è davvero opzionale, un design più resiliente può usare un `try/catch` best-effort.

---

## 20. Dependency-aware state machine

Supponiamo:

```text
Created
Funded
Released
Refunded
```

Aggiungiamo un external settlement.

Il requisito deve definire:

```text
quando lo stato diventa Released?
prima o dopo la chiamata?
cosa significa Released esattamente?
```

Questo è fragile:

```solidity
state = State.Released;

(bool ok,) = router.call(data);
// ok ignorato
```

Può produrre:

```text
state = Released
settlement = fallito
```

Lo stato racconta una cosa falsa.

---

## 21. Dipendenza critica vs accessoria

### Critica

Se fallisce:

```text
non posso preservare la correttezza
```

Esempi:

```text
token transfer del payout
oracle necessario a una decisione economica
```

Tipicamente tende al fail-closed.

### Accessoria

Se fallisce:

```text
l'operazione principale resta corretta
```

Esempi possibili:

```text
notifica
hook informativo
```

Può essere best-effort.

Questa classificazione deve essere esplicita.

---

## 22. Proprietà e invarianti

### D1 — Failure non crea falso successo

```text
dependency call fails
=> success state must not persist
```

salvo dependency esplicitamente best-effort.

### D2 — Output critico validato

```text
dependency returns X
=> X soddisfa i bounds del protocollo
```

### D3 — Dependency accessoria non blocca asset recovery

Se notifier è opzionale:

```text
notifier failure != withdrawal failure
```

### D4 — Target non autorizzato non viene invocato

```text
target not allowlisted
=> external call impossible
```

### D5 — Cache fresca

```text
cached value usable
=> age <= maxAge
```

### D6 — Config change autorizzato

```text
unauthorized caller
=> cannot change dependency
```

### D7 — Stato terminale corrisponde all'effetto reale

```text
state == Released
=> settlement condition completed
```

---

## 23. Laboratorio Foundry

Struttura:

```text
dependency-lab/
├── foundry.toml
├── src/
│   ├── DependencyConsumer.sol
│   ├── NotificationEscrow.sol
│   ├── BoundedIntegrator.sol
│   └── mocks/
│       ├── GoodNotifier.sol
│       ├── RevertingNotifier.sol
│       ├── RevertingDependency.sol
│       ├── MutableDependency.sol
│       └── WeirdRouter.sol
└── test/
    ├── DependencyConsumer.t.sol
    ├── NotificationEscrow.t.sol
    └── BoundedIntegrator.t.sol
```

Setup:

```bash
forge init dependency-lab
cd dependency-lab
forge test
```

Non servono fork o RPC esterni.

---

## 24. Mock notifier valido

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract GoodNotifier {
    bool public called;

    function notifyReleased(
        address,
        uint256
    ) external {
        called = true;
    }
}
```

## 25. Mock notifier che reverte

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract RevertingNotifier {
    error Nope();

    function notifyReleased(
        address,
        uint256
    ) external pure {
        revert Nope();
    }
}
```

---

## 26. Test positivi e negativi

### Notifier valido

```solidity
function test_ReleaseWorksWithNotifier()
    public
{
    GoodNotifier notifier =
        new GoodNotifier();

    NotificationEscrow escrow =
        new NotificationEscrow(
            INotifier(address(notifier)),
            buyer,
            seller,
            100
        );

    vm.prank(buyer);
    escrow.release();

    assertTrue(escrow.released());
    assertTrue(notifier.called());
}
```

### Notifier fallisce ma la release resta valida

```solidity
function test_NotifierFailureDoesNotBlockRelease()
    public
{
    RevertingNotifier notifier =
        new RevertingNotifier();

    NotificationEscrow escrow =
        new NotificationEscrow(
            INotifier(address(notifier)),
            buyer,
            seller,
            100
        );

    vm.prank(buyer);
    escrow.release();

    assertTrue(escrow.released());
}
```

Questo test dimostra una policy precisa:

```text
notification availability
non è una precondizione della release
```

---

## 27. Test del falso successo

```solidity
function test_UncheckedCallCreatesFalseSuccess()
    public
{
    UncheckedDependency consumer =
        new UncheckedDependency();

    RevertingDependency dep =
        new RevertingDependency();

    bytes memory data = abi.encodeCall(
        dep.execute,
        ()
    );

    consumer.run(
        address(dep),
        data
    );

    assertTrue(
        consumer.completed()
    );
}
```

Il test dimostra il bug della versione vulnerabile.

Dopo la correzione, il test di regressione deve invece aspettarsi revert e verificare che `completed` resti `false`.

---

## 28. Test dependency che cambia

```solidity
function test_DependencyCanBecomeUnavailable()
    public
{
    MutableDependency dep =
        new MutableDependency();

    DependencyConsumer consumer =
        new DependencyConsumer(
            IValueProvider(address(dep))
        );

    consumer.refresh();

    assertEq(
        consumer.lastGoodValue(),
        100
    );

    dep.setMode(
        MutableDependency.Mode.RevertAlways
    );

    vm.expectRevert();
    consumer.refresh();

    assertEq(
        consumer.lastGoodValue(),
        100
    );
}
```

Proprietà:

```text
failure del refresh
non corrompe l'ultimo valore valido
```

---

## 29. Test del valore zero

```solidity
function test_ZeroValueCannotReplaceGoodValue()
    public
{
    MutableDependency dep =
        new MutableDependency();

    DependencyConsumer consumer =
        new DependencyConsumer(
            IValueProvider(address(dep))
        );

    consumer.refresh();

    dep.setMode(
        MutableDependency.Mode.ReturnZero
    );

    vm.expectRevert(
        DependencyConsumer
            .InvalidValue
            .selector
    );

    consumer.refresh();

    assertEq(
        consumer.lastGoodValue(),
        100
    );
}
```

---

## 30. Test semantico del router

```solidity
function test_WeirdRouterFailsBound()
    public
{
    WeirdRouter router =
        new WeirdRouter();

    BoundedIntegrator integrator =
        new BoundedIntegrator(
            IRouter(address(router))
        );

    vm.expectRevert(
        BoundedIntegrator
            .InsufficientOutput
            .selector
    );

    integrator.execute(
        1000,
        900
    );
}
```

La call non reverte, ma il risultato viola la proprietà economica.

---

## 31. `vm.mockCall`

Foundry permette anche di mockare chiamate esterne con cheatcode come:

```solidity
vm.mockCall(...)
```

Esempio concettuale:

```solidity
vm.mockCall(
    address(provider),
    abi.encodeCall(
        IValueProvider.value,
        ()
    ),
    abi.encode(uint256(100))
);
```

### Quando preferire un mock contract

Quando vuoi modellare:

```text
stato
modalità diverse
revert
callback
sequenze
```

### Quando preferire `vm.mockCall`

Quando vuoi:

```text
risposta deterministica semplice
test unitario isolato
```

---

## 32. Dependency graph

Durante un audit, disegna il grafo.

```text
                 +--> Token A
                 |
Escrow --> Router+--> Pool
  |              |      |
  |              |      +--> Token B
  |              |
  |              +--> Fee Collector
  |
  +--> Oracle
         |
         +--> Aggregator
```

Poi annota:

```text
ownership
upgradeability
external calls
assets
failure modes
```

Questo rende visibili le dipendenze transitive.

---

## 33. Trust matrix

Esempio:

```text
Dependency     Trust assumption
--------------------------------------------
Token          transfer semantics
Oracle         price correctness + freshness
Router         minOut semantics
Proxy          upgrade governance
Admin          key security
Notifier       availability non critica
```

Poi chiedi:

```text
quali assunzioni sono verificate on-chain?
quali sono soltanto documentate?
```

---

## 34. Blast radius

Per ogni dependency chiedi:

> Se questa dipendenza diventa completamente malevola, che cosa può succedere?

Esempio:

```text
Notifier malevolo
-> dovrebbe al massimo fallire la notifica

Router malevolo
-> può influenzare asset flow

Oracle malevolo
-> può influenzare pricing

Token malevolo
-> può rompere accounting e call flow
```

Il blast radius dovrebbe essere proporzionato alla fiducia assegnata.

---

## 35. Least authority per dipendenze

Il principio del minimo privilegio vale anche tra contratti.

Se un router deve spendere:

```text
100 TOKEN
```

non è automaticamente ideale concedergli per sempre:

```text
type(uint256).max
```

Una allowance residua mantiene una relazione di fiducia futura.

Lezione 8:

```text
allowance = capability persistente
```

Ora aggiungiamo:

```text
spender = dependency
```

Questa è una trust boundary stateful.

---

## 36. Dependency replacement

Supponiamo:

```solidity
function setRouter(
    address newRouter
) external onlyOwner;
```

Questa funzione cambia il trust boundary dell'intero protocollo.

Da auditor chiedi:

```text
chi è owner?
multisig?
timelock?
zero address?
code present?
event emitted?
old approvals revoked?
new approvals granted?
```

---

## 37. Librerie compile-time vs protocolli runtime

Distinzione:

```solidity
import {Math} from "...";
```

non è lo stesso tipo di dipendenza di:

```solidity
oracle.latestPrice();
```

### Library compile-time

Rischi principali:

```text
versioning
supply chain
upgrade della dependency sorgente
```

### External contract runtime

Rischi principali:

```text
runtime behavior
governance
proxy upgrade
revert/callback
state esterno
```

Sono due famiglie di rischio diverse.

---

## 38. Observability

Se scegli fail-open per una dependency accessoria, il failure può diventare invisibile se non emetti nulla.

Eventi utili:

```text
DependencyUpdated
DependencyCallFailed
CircuitBreakerActivated
PriceFeedStale
```

Security engineering non è soltanto prevention:

```text
prevention
detection
response
```

---

## 39. Checklist da auditor

Quando incontri una external dependency, chiediti:

1. Qual è l'indirizzo della dependency?
2. Chi lo controlla?
3. È immutable, aggiornabile o user-supplied?
4. È un proxy?
5. Chi può upgradeare quel proxy?
6. Quali proprietà semantiche assume il consumer?
7. Il return value viene validato?
8. Il revert propaga, viene catturato o ignorato?
9. Se viene catturato, qual è la recovery policy?
10. È fail-open o fail-closed?
11. Questa scelta protegge safety o liveness?
12. La dependency è critica o accessoria?
13. Può fare callback/reentrancy?
14. Possiede allowance?
15. Le allowance restano dopo l'operazione?
16. Il target può cambiare?
17. Un admin compromesso può sostituirlo?
18. La dependency ha dipendenze transitive?
19. Può restituire zero, valori estremi o dati stale?
20. Esiste caching?
21. La cache ha scadenza?
22. Un failure può bloccare withdrawal?
23. Esistono circuit breaker?
24. Gli utenti mantengono un percorso di uscita?
25. I test includono dipendenze ostili?
26. Il protocollo verifica le proprie proprietà o delega tutto al callee?
27. Gli eventi rendono osservabili i failure non revertenti?

---

## 40. Esercizi

### Esercizio 1 — Classifica dipendenze

Per l'Escrow evoluto classifica:

```text
ERC20
oracle
notifier
router
```

come `critical` o `optional`, e giustifica.

### Esercizio 2 — Fail policy

Per ogni dependency scrivi:

```text
failure -> revert?
failure -> continue?
failure -> pause?
failure -> fallback?
```

Non scrivere codice finché non hai deciso la semantica.

### Esercizio 3 — Unchecked call

Correggi:

```solidity
target.call(data);
completed = true;
```

in due modi:

1. high-level interface;
2. low-level call con verifica.

### Esercizio 4 — Mock ostile

Crea un provider che:

```text
prima restituisce 100
poi reverte
poi restituisce 0
poi restituisce type(uint256).max
```

Scrivi un test per ciascun caso.

### Esercizio 5 — Best effort notifier

Aggiungi un evento `NotificationFailed` e usa `vm.expectEmit(...)` per verificarlo.

### Esercizio 6 — Allowlist

Supporta `router A` e `router B`, ma rifiuta `router C`.

Scrivi il test negativo.

### Esercizio 7 — Dependency graph

Disegna tutte le dipendenze dirette e indirette del `TokenEscrow` delle lezioni precedenti.

Per ogni nodo annota:

```text
asset
caller
callee
upgradeability
failure mode
```

### Esercizio 8 — Liveness

Costruisci un Escrow in cui `withdraw()` chiama prima un notifier che reverte.

Dimostra con test che il withdrawal diventa impossibile, poi modifica il design per rendere il notifier best-effort.

### Esercizio 9 — Cache stale

Aggiungi:

```solidity
lastGoodValue
lastUpdatedAt
maxAge
```

Verifica:

```text
cache fresca -> utilizzabile
cache stale  -> revert
```

### Esercizio 10 — Audit challenge

Analizza:

```solidity
function execute(
    address token,
    address router,
    uint256 amount,
    bytes calldata data
) external {
    IERC20(token).approve(
        router,
        type(uint256).max
    );

    router.call(data);

    completed[msg.sender] = true;
}
```

Trova almeno **12 domande di security review** prima di proporre una patch.

---

## 41. Cosa devi ricordare

1. **Composability è potere e rischio.** Ogni componente riusato aggiunge funzionalità e trust assumptions.
2. **Una external call è una trust boundary.** Stai cedendo controllo a codice esterno.
3. **ABI corretta non significa semantica corretta.**
4. **Il revert di una dependency può propagare.** Questo protegge atomicità ma può distruggere liveness.
5. **`try/catch` è una decisione di business logic.** Non usarlo per nascondere errori.
6. **Low-level `call` richiede gestione esplicita.** Ignorare `success` può creare falso successo.
7. **Un address immutabile non implica comportamento immutabile.** Un proxy può cambiare implementazione dietro lo stesso address.
8. **Le dipendenze sono anche transitive.**
9. **Safety e liveness sono proprietà diverse.**
10. **Verifica le proprietà del tuo protocollo.** Non delegare ciecamente al callee ciò che devi garantire tu.

---

## 42. Fonti della lezione

Fonti tecniche consultate il **21 settembre 2026**:

1. **Ethereum.org — Smart contract composability**  
   Smart contract come componenti riusabili/open API e principi della composability.  
   https://ethereum.org/developers/docs/smart-contracts/composability/

2. **Ethereum.org — Introduction to smart contracts**  
   Modello degli smart contract e possibilità per un contratto di invocarne altri.  
   https://ethereum.org/developers/docs/smart-contracts/

3. **Solidity Documentation — Expressions and Control Structures**  
   External calls, propagazione delle eccezioni, atomicità, low-level calls e `try/catch`.  
   https://docs.soliditylang.org/en/latest/control-structures.html

4. **Solidity Documentation — Units and Globally Available Variables**  
   Differenze e caveat delle low-level calls, incluse le particolarità delle chiamate verso indirizzi senza codice.  
   https://docs.soliditylang.org/en/latest/units-and-global-variables.html

5. **Solidity Documentation — SMTChecker and Formal Verification**  
   Modello mentale utile: le external calls sono trattate per default come codice sconosciuto.  
   https://docs.soliditylang.org/en/latest/smtchecker.html

6. **OpenZeppelin Contracts 5.x — Address utilities**  
   `Address.functionCall`, bubbling del revert data e utility per external calls.  
   https://docs.openzeppelin.com/contracts/5.x/api/utils

7. **Foundry Documentation — Reference**  
   Riferimento aggiornato per Forge, Anvil e cheatcode, inclusi strumenti di mocking.  
   https://www.getfoundry.sh/reference/

8. **Ethereum.org — Testing smart contracts**  
   Importanza dell'integration testing in sistemi altamente composabili e uso di blockchain locali per test controllati.  
   https://ethereum.org/developers/docs/smart-contracts/testing/

---

## Fine Lezione 10

La progressione successiva sarà:

**Proxy, `delegatecall` e upgradeability: execution context, storage layout, initializer, admin risk, upgrade authorization e test degli upgrade.**
