# Lezione 11 — Proxy, `delegatecall` e Upgradeability

> **Scopo:** didattica difensiva, secure coding, auditing e testing.
>
> Tutti gli esempi sono progettati esclusivamente per **Foundry/Anvil locale**, account di test e contratti giocattolo. Il proxy minimale della prima parte è volutamente insicuro e serve solo a capire il meccanismo.

## Obiettivi e modello mentale

### 1. Obiettivi

Alla fine della lezione dovresti saper spiegare `delegatecall`, distinguere code context e storage context, capire perché un proxy può cambiare logica mantenendo address e stato, riconoscere storage collision e initializer mancanti, distinguere ERC-1967/UUPS/Transparent Proxy, analizzare `_authorizeUpgrade`, verificare uno storage layout con Foundry e testare un upgrade preservando le proprietà del protocollo.

In particolare imparerai a verificare queste proprietà:

```text
- solo l'upgrade authority può cambiare implementation;
- initialize non può essere eseguita due volte;
- una V2 non deve reinterpretare lo storage V1;
- lo stato già esistente deve sopravvivere all'upgrade;
- una nuova V2 deve mantenere anche gli invarianti di business;
- il proxy non deve restare inizializzabile da un account arbitrario.
```

---

### 2. Modello mentale

Un normale contratto accoppia:

```text
address
code
storage
```

Un proxy separa invece:

```text
                    +----------------------+
User -------------->| Proxy                |
                    |                      |
                    | address stabile      |
                    | storage persistente  |
                    +----------+-----------+
                               |
                               | delegatecall
                               v
                    +----------------------+
                    | Implementation V1    |
                    | codice               |
                    +----------------------+
```

Dopo un upgrade:

```text
                    +----------------------+
User -------------->| Proxy                |
                    |                      |
                    | STESSO address       |
                    | STESSO storage       |
                    +----------+-----------+
                               |
                               | delegatecall
                               v
                    +----------------------+
                    | Implementation V2    |
                    | NUOVO codice         |
                    +----------------------+
```

La frase fondamentale è:

> **Il proxy conserva lo stato; l'implementation fornisce il codice.**

Questo è possibile grazie a `delegatecall`.

---

## delegatecall e storage layout

### 3. `call` vs `delegatecall`

Con una normale chiamata:

```text
A --call--> B
```

il codice di `B` gira usando:

```text
code    = B
storage = B
address = B
```

Dentro `B`, se il caller diretto è `A`:

```text
msg.sender = A
```

Con:

```text
A --delegatecall--> B
```

succede qualcosa di diverso:

```text
code    = B
storage = A
address = A
```

e il contesto del caller viene preservato.

Nel caso proxy:

```text
Alice
  |
  | CALL
  v
Proxy
  |
  | DELEGATECALL
  v
Implementation
```

durante l'esecuzione della business logic:

```text
msg.sender    = Alice
address(this) = Proxy
storage       = Proxy
code          = Implementation
```

Questa quadrupla è da memorizzare.

---

### 4. Perché `delegatecall` è security-critical

Considera:

```solidity
contract Logic {
    uint256 public value;

    function setValue(uint256 x) external {
        value = x;
    }
}
```

Chiamando direttamente `Logic`:

```text
Logic.storage[slot 0] = x
```

Chiamando la stessa funzione attraverso un proxy con `delegatecall`:

```text
Proxy.storage[slot 0] = x
```

Il bytecode dell'implementation decide quindi **come interpretare gli slot del proxy**.

I nomi Solidity non esistono a runtime.

La EVM vede qualcosa di simile a:

```text
SLOAD(slot)
SSTORE(slot, value)
```

non:

```text
"scrivi la variabile chiamata owner"
```

Per questo lo storage layout diventa parte della sicurezza.

---

### 5. Storage layout

Esempio semplificato:

```solidity
contract V1 {
    uint256 public amount;
    address public owner;
}
```

Concettualmente:

```text
slot 0 -> amount
slot 1 -> owner
```

Il bytecode V1 assume questa interpretazione.

Se V2 diventa:

```solidity
contract BadV2 {
    address public owner;
    uint256 public amount;
}
```

ora il codice interpreta:

```text
slot 0 -> owner
slot 1 -> amount
```

ma i bit persistenti del proxy non si sono spostati.

Quindi V2 legge dati V1 con una semantica differente.

Questo è storage corruption.

---

### 6. Modifiche classiche incompatibili

V1:

```solidity
uint256 public a;
uint256 public b;
```

#### Reorder

```solidity
uint256 public b;
uint256 public a;
```

Pericoloso.

#### Cambio tipo

```solidity
address public a;
uint256 public b;
```

Pericoloso.

#### Inserimento prima

```solidity
uint256 public newValue;
uint256 public a;
uint256 public b;
```

Pericoloso nel layout classico.

#### Rimozione

```solidity
uint256 public b;
```

Pericolosa.

#### Append

```solidity
uint256 public a;
uint256 public b;
uint256 public c;
```

Nel modello classico è la modifica tipicamente compatibile: gli slot già usati non cambiano.

---

### 7. Packing

Non assumere:

```text
una variabile = uno slot
```

Per esempio:

```solidity
uint128 public a;
uint128 public b;
uint256 public c;
```

`a` e `b` possono condividere lo stesso slot.

Usa il compiler invece di indovinare:

```bash
forge inspect MyContract storageLayout
```

oppure:

```bash
forge inspect MyContract storage
```

Guarda almeno:

```text
label
slot
offset
type
```

---

## Laboratorio 1: la collisione di storage

### 8. Laboratorio 1 — proxy volutamente fragile

Prima di usare OpenZeppelin voglio che tu veda il problema direttamente.

#### `src/lab/SimpleProxy.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract SimpleProxy {
    // VOLUTAMENTE FRAGILE:
    // lo slot 0 collide con una normale
    // prima variabile dell'implementation.
    address public implementation;

    constructor(address implementation_) {
        implementation = implementation_;
    }

    function upgradeTo(address newImplementation)
        external
    {
        // VOLUTAMENTE INSICURO:
        // nessun access control.
        implementation = newImplementation;
    }

    fallback() external payable {
        address impl = implementation;

        assembly {
            calldatacopy(
                0,
                0,
                calldatasize()
            )

            let result := delegatecall(
                gas(),
                impl,
                0,
                calldatasize(),
                0,
                0
            )

            returndatacopy(
                0,
                0,
                returndatasize()
            )

            switch result
            case 0 {
                revert(
                    0,
                    returndatasize()
                )
            }
            default {
                return(
                    0,
                    returndatasize()
                )
            }
        }
    }
}
```

Questo proxy ha almeno due difetti intenzionali:

```text
1. implementation occupa slot 0;
2. chiunque può cambiare implementation.
```

Non è production-ready.

---

### 9. Implementation giocattolo

#### `src/lab/LogicV1.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract LogicV1 {
    uint256 public value;

    function setValue(uint256 newValue)
        external
    {
        value = newValue;
    }
}
```

Anche `value` usa concettualmente:

```text
slot 0
```

Quindi:

```text
Proxy slot 0 -> implementation
Logic slot 0 -> value
```

ma durante `delegatecall` esiste un solo storage attivo:

```text
quello del Proxy.
```

---

### 10. Collisione passo per passo

Prima:

```text
Proxy slot 0 =
address(LogicV1)
```

Poi l'utente tratta il proxy come se avesse l'ABI di `LogicV1`:

```solidity
LogicV1(address(proxy))
    .setValue(123);
```

Il proxy delega la call.

Il codice `LogicV1` esegue semanticamente:

```text
SSTORE(slot 0, 123)
```

ma quel `slot 0` è quello del proxy.

Risultato:

```text
implementation =
address(uint160(123))
```

L'indirizzo dell'implementation è stato corrotto.

---

### 11. Test Foundry della collisione

#### `test/SimpleProxy.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/Test.sol";
import {
    SimpleProxy
} from "../src/lab/SimpleProxy.sol";
import {
    LogicV1
} from "../src/lab/LogicV1.sol";

contract SimpleProxyTest is Test {
    function test_StorageCollision() public {
        LogicV1 impl =
            new LogicV1();

        SimpleProxy proxy =
            new SimpleProxy(
                address(impl)
            );

        LogicV1 proxied =
            LogicV1(address(proxy));

        proxied.setValue(123);

        assertEq(
            uint256(
                uint160(
                    proxy.implementation()
                )
            ),
            123
        );
    }
}
```

Questo laboratorio dimostra soltanto il meccanismo localmente.

---

### 12. Perché ERC-1967 esiste

Usare normali slot applicativi per:

```text
implementation
admin
beacon
```

crea collisioni.

ERC-1967 standardizza slot particolari per i metadata del proxy.

Per esempio, lo slot dell'implementation è derivato da:

```text
keccak256(
    "eip1967.proxy.implementation"
) - 1
```

L'obiettivo è separare:

```text
proxy metadata
```

da:

```text
ordinary application storage
```

Questo evita una classe di collisioni.

Non evita invece una V2 applicativa con layout incompatibile con V1.

---

### 13. Due collisioni diverse

#### Tipo A — Proxy metadata vs application

```text
proxy implementation slot
vs
value/owner/etc.
```

Mitigazione tipica:

```text
ERC-1967
```

#### Tipo B — V1 vs V2

```text
vecchio application layout
vs
nuovo application layout
```

Mitigazioni:

```text
storage discipline
ERC-7201 quando applicabile
storage gaps quando applicabile
validation tooling
manual review
regression tests
```

Non confondere i due problemi.

---

## ERC-1967, UUPS e inizializzazione

### 14. `ERC1967Proxy`

OpenZeppelin Contracts 5.x espone:

```solidity
import {
    ERC1967Proxy
} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
```

Il proxy usa gli slot ERC-1967.

Il constructor riceve:

```solidity
constructor(
    address implementation,
    bytes memory data
)
```

I `data` possono essere delegati all'implementation durante il deploy, tipicamente per inizializzare immediatamente lo storage del proxy.

È una caratteristica importante:

```text
deploy
+
initialize
```

possono avvenire nello stesso flusso.

---

### 15. Transparent Proxy e UUPS

Sono due famiglie comuni.

#### Transparent Proxy

Concettualmente:

```text
Users
  |
  | business calls
  v
Transparent Proxy
  |
  v
Implementation

ProxyAdmin
  |
  | upgrade
  v
Transparent Proxy
```

Il pattern separa le chiamate dell'admin dalla normale dispatch verso l'implementation.

Nella OpenZeppelin 5.x corrente gli upgrade di un `TransparentUpgradeableProxy` passano tramite un `ProxyAdmin`.

#### UUPS

Con UUPS:

```text
ERC1967Proxy
    |
    | delegatecall
    v
UUPS Implementation
    |
    +--> business logic
    |
    +--> upgrade mechanism
```

La logica necessaria a effettuare l'upgrade è nella implementation.

OpenZeppelin 5.x indica UUPS come pattern generalmente più leggero e versatile rispetto al Transparent Proxy.

---

### 16. `_authorizeUpgrade`

Con OpenZeppelin UUPS devi implementare:

```solidity
function _authorizeUpgrade(
    address newImplementation
) internal override;
```

Questa funzione risponde alla domanda:

> **Chi può cambiare il codice futuro del protocollo?**

Esempio:

```solidity
function _authorizeUpgrade(
    address
) internal override onlyOwner {}
```

Ora l'owner è anche upgrade authority.

Questo potere è enorme.

Una nuova implementation può cambiare:

```text
access control
withdrawal logic
fee
oracle
token handling
state machine
```

Perciò in un protocollo upgradeable il threat model non è:

```text
solo business logic corrente
```

ma:

```text
business logic
+
upgrade mechanism
+
upgrade authority
+
governance del potere di upgrade
```

---

### 17. Constructor vs initializer

Considera:

```solidity
contract Escrow {
    address public owner;

    constructor() {
        owner = msg.sender;
    }
}
```

Il constructor viene eseguito quando deployi l'**implementation**.

Quindi scrive:

```text
Implementation.storage
```

Non:

```text
Proxy.storage
```

Ma gli utenti lavorano normalmente con il proxy.

Per inizializzare lo storage del proxy serve una normale funzione eseguita tramite `delegatecall`.

Da qui nasce:

```text
initialize(...)
```

---

### 18. `Initializable`

OpenZeppelin fornisce:

```solidity
import {
    Initializable
} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
```

e il modifier:

```solidity
initializer
```

Esempio:

```solidity
function initialize(
    address owner_
) public initializer {
    ...
}
```

L'obiettivo è rendere lo step iniziale utilizzabile una volta.

---

### 19. Proxy non inizializzato

Se fai:

```text
deploy proxy
```

ma non chiami subito `initialize`, potresti lasciare una finestra in cui un altro account esegue:

```solidity
initialize(attacker)
```

e ottiene i ruoli iniziali.

La remediation è progettare:

```text
deploy proxy
+
initialize proxy
```

come operazione unica o comunque atomicamente controllata.

OpenZeppelin consiglia di passare l'encoded initializer durante la costruzione/deployment del proxy quando possibile.

---

### 20. Implementation non inizializzata

L'implementation è anch'essa un contratto deployato e possiede uno storage proprio.

Normalmente non vuoi lasciarla utilizzabile come istanza inizializzabile.

OpenZeppelin raccomanda:

```solidity
constructor() {
    _disableInitializers();
}
```

Questo blocca gli initializer sull'implementation.

Importante:

```text
constructor sull'implementation
```

non configura il proxy.

Serve soltanto, in questo caso, a rendere sicura l'istanza implementation.

---

## Escrow upgradeable: V1, V2 e compatibilità

### 21. UUPS Escrow V1

#### `src/upgrade/EscrowV1.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    Initializable
} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {
    OwnableUpgradeable
} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {
    UUPSUpgradeable
} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract EscrowV1 is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    address public buyer;
    address public seller;

    uint256 public amount;
    bool public funded;

    error OnlyBuyer();
    error AlreadyFunded();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address buyer_,
        address seller_
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        buyer = buyer_;
        seller = seller_;
    }

    function fund(uint256 amount_)
        external
    {
        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (funded) {
            revert AlreadyFunded();
        }

        amount = amount_;
        funded = true;
    }

    function version()
        external
        pure
        virtual
        returns (uint256)
    {
        return 1;
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
```

`amount` è soltanto accounting didattico.

Non spostiamo fondi reali in questa lezione.

---

### 22. Analisi di `initialize`

#### Chi può chiamarla?

Qualunque caller può **tentare** la call sul proxy.

Ma il modifier:

```text
initializer
```

permette lo step previsto una sola volta.

#### Input controllati

```text
initialOwner
buyer
seller
```

#### Stato modificato

Se chiamata tramite proxy:

```text
storage del proxy
```

inclusi:

```text
Ownable state
initialization state
buyer
seller
```

#### External calls

Non verso protocolli arbitrari.

Gli initializer parent vengono eseguiti nel medesimo contesto.

#### Assunzione critica

La prima initialization deve essere quella legittima.

Il modifier non decide **chi debba essere il primo caller**: impedisce la ripetizione.

---

### 23. Analisi di `_authorizeUpgrade`

```solidity
function _authorizeUpgrade(
    address
) internal override onlyOwner {}
```

#### Caller effettivo

La procedura UUPS deve arrivare qui nel contesto del proxy.

#### Controllo

```text
msg.sender deve essere owner
```

#### Stato scritto direttamente

Nessuno in questa funzione.

#### Effetto possibile

Permettere al meccanismo di cambiare l'implementation.

Quindi:

```text
funzione minuscola
!=
impatto minuscolo
```

È una funzione ad altissimo impatto.

---

### 24. V2 compatibile

#### `src/upgrade/EscrowV2.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    EscrowV1
} from "./EscrowV1.sol";

contract EscrowV2 is EscrowV1 {
    uint256 public feeBps;

    error FeeTooHigh();

    function initializeV2(
        uint256 feeBps_
    ) external reinitializer(2) {
        if (feeBps_ > 1_000) {
            revert FeeTooHigh();
        }

        feeBps = feeBps_;
    }

    function version()
        external
        pure
        override
        returns (uint256)
    {
        return 2;
    }
}
```

Nel layout applicativo aggiungiamo:

```text
feeBps
```

dopo lo stato già esistente.

---

### 25. `reinitializer(2)`

Una nuova implementation può introdurre nuovo stato che deve essere configurato.

Non vuoi ripetere:

```text
initialize V1
```

Usi invece uno step versionato:

```solidity
reinitializer(2)
```

Modello:

```text
initialization version 1
        |
        | già consumata
        v
upgrade V2
        |
        v
initialization version 2
        |
        | una volta
        v
configured V2
```

Questo riduce il rischio di inizializzare accidentalmente più volte lo stesso modulo.

---

### 26. ERC-7201 Namespaced Storage

OpenZeppelin Contracts Upgradeable 5.x usa, per molti componenti, il pattern ERC-7201.

Invece di affidarsi soltanto a una sequenza globale di state variables ereditate, un modulo può usare un namespace di storage dedicato.

Concettualmente:

```text
Ownable namespace
    |
    +--> owner

Initializable namespace
    |
    +--> initialized state

Application
    |
    +--> buyer
    +--> seller
    +--> amount
    +--> funded
```

Questo rende più robusti alcuni cambiamenti nell'inheritance hierarchy quando tutti i componenti coinvolti seguono correttamente il pattern.

Non significa:

```text
"il layout non conta più"
```

Significa:

```text
"il layout viene isolato in namespace"
```

e deve comunque essere validato.

---

### 27. Storage gaps

Un altro pattern storico/importante è:

```solidity
uint256[49] private __gap;
```

Serve a riservare slot in una base class.

Se in futuro aggiungi una variabile da uno slot:

```text
__gap[49]
```

può diventare:

```text
newVariable
__gap[48]
```

Gli OpenZeppelin Upgrades Plugins riconoscono convenzioni `__gap`.

Da auditor devi capire se il progetto usa:

```text
storage gaps
ERC-7201
un layout custom
```

e verificare il pattern reale, non quello che supponi.

---

### 28. V2 incompatibile

Esempio giocattolo:

```solidity
contract EscrowBadV2 {
    uint256 public amount;
    address public seller;
    address public buyer;
    bool public funded;
}
```

rispetto a V1:

```text
buyer
seller
amount
funded
```

ha cambiato ordine.

Non useremo questa implementation contro alcun deployment pubblico.

La useremo solo perché il tooling segnali l'incompatibilità.

---

## Strumenti: ispezione, validation e deploy

### 29. Ispezione con Foundry

Dopo:

```bash
forge build
```

esegui:

```bash
forge inspect EscrowV1 storageLayout
forge inspect EscrowV2 storageLayout
forge inspect EscrowBadV2 storageLayout
```

Confronta:

```text
slot
offset
type
label
```

Questa review va fatta **prima** dell'upgrade.

---

### 30. OpenZeppelin Foundry Upgrades

La documentazione corrente per nuovi deployment con OpenZeppelin Contracts v5 indica:

```bash
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-foundry-upgrades
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
```

Il plugin offre funzioni come:

```text
deployUUPSProxy
deployTransparentProxy
upgradeProxy
validateImplementation
validateUpgrade
prepareUpgrade
getImplementationAddress
```

La parte importante è che il plugin esegue validation per:

```text
upgrade safety
storage compatibility
```

prima di procedere.

---

### 31. Remappings

La guida ufficiale corrente del Foundry Upgrades plugin per OpenZeppelin v5 propone remapping coerenti con la copia transitiva di Contracts installata insieme a `contracts-upgradeable`.

Per esempio:

```text
@openzeppelin/contracts/=lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/
@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
```

Se necessario:

```text
openzeppelin-foundry-upgrades/=lib/openzeppelin-foundry-upgrades/src/
```

Controlla il tuo setup con:

```bash
forge remappings
```

Non mescolare casualmente copie diverse delle librerie.

---

### 32. Configurazione della validation

Il plugin Foundry può richiedere build metadata come:

```toml
ffi = true
ast = true
build_info = true
extra_output = ["storageLayout"]
```

a seconda del workflow/versione.

Usa la configurazione indicata dalla documentazione installata.

Principio security:

> Non disabilitare una validation solo perché impedisce all'upgrade di passare.

Prima capisci **perché** viene segnalata l'incompatibilità.

---

### 33. Deploy UUPS con initialization atomica

Il plugin corrente espone:

```solidity
Upgrades.deployUUPSProxy(
    contractName,
    initializerData
);
```

Esempio:

```solidity
address proxy =
    Upgrades.deployUUPSProxy(
        "EscrowV1.sol",
        abi.encodeCall(
            EscrowV1.initialize,
            (
                owner,
                buyer,
                seller
            )
        )
    );
```

Poi:

```solidity
EscrowV1 escrow =
    EscrowV1(proxy);
```

Questa riga significa:

```text
ABI che usiamo = EscrowV1
address chiamato = proxy
```

---

### 34. Perché l'initialization nel deploy è importante

Flusso desiderato:

```text
deploy implementation
        |
        v
deploy proxy
        |
        +--> delegatecall initialize(...)
        |
        v
proxy già configurato
```

Non:

```text
deploy proxy

[proxy non inizializzato]

più tardi:
initialize()
```

La finestra intermedia è un rischio inutile.

---

## Laboratorio Foundry: test e mutation lab dell'upgrade

### 35. Test Foundry — setup

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from
    "forge-std/Test.sol";

import {Upgrades} from
    "openzeppelin-foundry-upgrades/Upgrades.sol";

import {
    EscrowV1
} from "../src/upgrade/EscrowV1.sol";

import {
    EscrowV2
} from "../src/upgrade/EscrowV2.sol";

contract EscrowUpgradeTest is Test {
    address owner =
        makeAddr("owner");

    address buyer =
        makeAddr("buyer");

    address seller =
        makeAddr("seller");

    address stranger =
        makeAddr("stranger");

    address proxy;
    EscrowV1 escrow;

    function setUp() public {
        proxy =
            Upgrades.deployUUPSProxy(
                "EscrowV1.sol",
                abi.encodeCall(
                    EscrowV1.initialize,
                    (
                        owner,
                        buyer,
                        seller
                    )
                )
            );

        escrow =
            EscrowV1(proxy);
    }
}
```

Il path passato a `contractName` può richiedere qualificazione diversa a seconda della struttura del progetto.

Segui il formato accettato dalla versione installata.

---

### 36. Test — stato iniziale

```solidity
function test_InitializedState()
    public
{
    assertEq(
        escrow.owner(),
        owner
    );

    assertEq(
        escrow.buyer(),
        buyer
    );

    assertEq(
        escrow.seller(),
        seller
    );

    assertEq(
        escrow.version(),
        1
    );
}
```

Stiamo leggendo lo storage **attraverso il proxy**.

---

### 37. Test negativo — initialize due volte

```solidity
function test_CannotInitializeTwice()
    public
{
    vm.expectRevert();

    escrow.initialize(
        stranger,
        stranger,
        stranger
    );
}
```

Proprietà:

> Dopo la configurazione iniziale, nessuno deve poter ridefinire i ruoli richiamando `initialize()`.

---

### 38. Stato prima dell'upgrade

```solidity
function test_StateBeforeUpgrade()
    public
{
    vm.prank(buyer);
    escrow.fund(100);

    assertEq(
        escrow.amount(),
        100
    );

    assertTrue(
        escrow.funded()
    );
}
```

---

### 39. Upgrade con il plugin

La API corrente espone:

```solidity
Upgrades.upgradeProxy(...)
```

e nei test permette anche di specificare un `tryCaller` per il caller che deve superare l'authorization UUPS.

Esempio:

```solidity
Upgrades.upgradeProxy(
    proxy,
    "EscrowV2.sol",
    abi.encodeCall(
        EscrowV2.initializeV2,
        (250)
    ),
    owner
);
```

Nel nostro esempio:

```text
250 bps = 2.5%
```

---

### 40. Test — preservare lo stato

```solidity
function test_UpgradePreservesState()
    public
{
    vm.prank(buyer);
    escrow.fund(100);

    Upgrades.upgradeProxy(
        proxy,
        "EscrowV2.sol",
        abi.encodeCall(
            EscrowV2.initializeV2,
            (250)
        ),
        owner
    );

    EscrowV2 upgraded =
        EscrowV2(proxy);

    assertEq(
        upgraded.owner(),
        owner
    );

    assertEq(
        upgraded.buyer(),
        buyer
    );

    assertEq(
        upgraded.seller(),
        seller
    );

    assertEq(
        upgraded.amount(),
        100
    );

    assertTrue(
        upgraded.funded()
    );

    assertEq(
        upgraded.feeBps(),
        250
    );

    assertEq(
        upgraded.version(),
        2
    );
}
```

Questa è la proprietà centrale:

```text
nuovo codice
+
vecchio stato intatto
```

---

### 41. Test negativo — upgrade non autorizzato

Proprietà:

```text
caller != upgrade authority
=> upgrade deve fallire
```

Concettualmente:

```solidity
function test_StrangerCannotUpgrade()
    public
{
    vm.expectRevert();

    Upgrades.upgradeProxy(
        proxy,
        "EscrowV2.sol",
        "",
        stranger
    );
}
```

Nel progetto reale, se il custom error è stabile nella versione usata, rendi `expectRevert` più preciso.

---

### 42. Test negativo — V2 initializer due volte

Dopo aver eseguito l'upgrade con:

```text
initializeV2(250)
```

prova:

```solidity
vm.expectRevert();

EscrowV2(proxy)
    .initializeV2(300);
```

Proprietà:

```text
reinitializer(2)
=> eseguibile una volta
```

---

### 43. Validare senza eseguire l'upgrade

Il plugin espone:

```solidity
Upgrades.validateUpgrade(...)
```

La nuova implementation deve avere un riferimento alla precedente, per esempio tramite:

```text
@custom:oz-upgrades-from ...
```

oppure:

```solidity
Options memory opts;

opts.referenceContract =
    "EscrowV1.sol";
```

Poi:

```solidity
Upgrades.validateUpgrade(
    "EscrowV2.sol",
    opts
);
```

Utilissimo per:

```text
CI
release pipeline
pre-deployment review
```

---

### 44. La validation non dimostra la correttezza logica

Questa V2 potrebbe avere un layout perfettamente compatibile:

```solidity
function fund(
    uint256
) external {
    amount = 0;
    funded = true;
}
```

Il validator storage non può sapere che la business logic è sbagliata.

Servono:

```text
layout validation
+
unit testing
+
negative testing
+
invariant testing
+
manual audit
```

---

### 45. Mutation lab — layout

Parti da:

```solidity
contract EscrowV2 is EscrowV1 {
    uint256 public feeBps;
}
```

Poi crea volutamente una implementation separata che ridefinisce le variabili V1 in ordine differente.

Esegui:

```text
validateUpgrade
```

La validation deve rifiutare la mutation.

Non forzare l'upgrade.

---

### 46. Mutation lab — authorization

Cambia temporaneamente:

```solidity
function _authorizeUpgrade(
    address
) internal override onlyOwner {}
```

in:

```solidity
function _authorizeUpgrade(
    address
) internal override {}
```

Ora il test:

```text
stranger cannot upgrade
```

deve fallire.

Questo verifica che il regression test copra davvero il controllo critico.

---

### 47. Mutation lab — proxy non inizializzato

Nel laboratorio locale:

```text
1. deploy proxy senza initializer data;
2. usa stranger per chiamare initialize;
3. osserva che stranger diventa owner;
4. correggi il deployment;
5. verifica che initialize non sia più disponibile.
```

Il principio è il nostro metodo standard:

```text
proprietà
-> violazione controllata
-> causa
-> remediation
-> regression test
```

---

## Rischi di upgrade, invarianti e migration plan

### 48. `upgradeToAndCall`

Nella linea OpenZeppelin 5.x corrente il meccanismo UUPS usa:

```solidity
upgradeToAndCall(
    address newImplementation,
    bytes data
)
```

Questo permette semanticamente:

```text
upgrade
+
migration/reinitializer
```

nello stesso flusso.

È utile perché una V2 che richiede configurazione non dovrebbe restare attiva in uno stato intermedio non inizializzato.

Le API storiche come un separato `upgradeTo` non vanno date per scontate nella versione corrente.

---

### 49. ERC-1822 e UUPS

UUPS deriva dal concetto formalizzato da ERC-1822.

Una implementation compatibile espone il concetto di:

```text
proxiableUUID
```

OpenZeppelin usa controlli di compatibilità UUPS per evitare alcuni upgrade che eliminerebbero accidentalmente il meccanismo previsto.

Ma:

```text
UUPS-compatible
```

non significa:

```text
business logic corretta
```

Sono proprietà diverse.

---

### 50. Transparent + UUPS: non mischiarli a caso

Transparent Proxy e UUPS usano entrambi lo slot ERC-1967 dell'implementation.

OpenZeppelin avverte che usare una implementation UUPS dietro a un Transparent Proxy senza comprenderne le conseguenze può creare comportamenti di upgrade indesiderati.

Regola pratica:

> Scegli consapevolmente un pattern e applicalo coerentemente.

Non comporre meccanismi di upgrade per tentativi.

---

### 51. Bricking risk

Un upgrade può rendere un sistema inutilizzabile anche senza rubare fondi.

Esempi:

```text
withdraw reverte sempre
initializer non eseguito
dependency sbagliata
storage corrotto
upgrade authorization impossibile
```

Quindi upgradeability riduce:

```text
rischio di bug non correggibile
```

ma introduce:

```text
rischio di upgrade errato
rischio di upgrade ostile
rischio di governance
```

Non è automaticamente "più sicura".

---

### 52. Upgrade authority e governance

Con:

```solidity
_authorizeUpgrade(...)
    onlyOwner
```

la domanda successiva è:

```text
chi è owner?
```

Può essere:

```text
EOA
multisig
timelock
governance
```

e il threat model cambia drasticamente.

Approfondiremo questo nella Lezione 12.

Per ora conserva questa equivalenza concettuale:

> **Upgrade authority = capacità di cambiare le regole future del sistema.**

---

### 53. Post-upgrade invariant testing

Non basta:

```solidity
assertEq(
    upgraded.version(),
    2
);
```

Testa le proprietà reali.

Per il nostro Escrow:

```text
owner invariato
buyer invariato
seller invariato
amount invariato
funded invariato
onlyBuyer ancora valido
initializer V1 ancora bloccato
initializer V2 non ripetibile
```

Quando in futuro aggiungeremo asset veri:

```text
asset balance
liabilities
terminal state
withdrawal rights
```

dovranno anch'essi sopravvivere correttamente.

---

### 54. Proprietà e invarianti

#### U1 — Upgrade authorization

```text
caller non autorizzato
=> implementation non cambia
```

#### U2 — V1 initialization

```text
proxy già inizializzato
=> initialize() reverte
```

#### U3 — V2 initialization

```text
initializeV2 già eseguito
=> initializeV2 reverte
```

#### U4 — State preservation

Per ogni campo che non deve essere migrato:

```text
before == after
```

#### U5 — Business invariants

Se prima valeva:

```text
funded == true
=> amount = valore registrato
```

l'upgrade deve preservare la semantica dichiarata.

#### U6 — Implementation locked

Quando usiamo il pattern OpenZeppelin:

```text
implementation diretta
=> initializer bloccato
```

#### U7 — Incompatible layout rejected

```text
BadV2
=> validation failure
```

#### U8 — Upgrade migration atomica quando necessaria

Se V2 non è valida senza una configurazione:

```text
upgrade
+
initializeV2
```

devono essere trattati come un'unica transizione logica.

---

### 55. Test matrix per ogni upgrade

Una buona checklist di test V1 → V2:

- [ ] stato V1 preparato
- [ ] unauthorized upgrade fallisce
- [ ] authorized upgrade riesce
- [ ] storage V1 preservato
- [ ] funzioni V1 ancora corrette
- [ ] nuova funzione V2 corretta
- [ ] nuovo reinitializer eseguito
- [ ] reinitializer non ripetibile
- [ ] invarianti economici ancora veri
- [ ] invalid layout rifiutato
- [ ] ruoli e ownership preservati
- [ ] failure della migration testato

---

### 56. Migration plan

Scrivi sempre esplicitamente:

```text
V1 state
   |
   v
upgrade implementation
   |
   v
migration / reinitializer
   |
   v
V2 state
```

Domande:

```text
quali nuove variabili esistono?
chi le inizializza?
con quali valori?
l'operazione può fallire?
se fallisce, l'upgrade viene revertito?
è possibile finire in una V2 parzialmente configurata?
```

La migration è business logic.

Va auditata.

---

### 57. Major version delle librerie

OpenZeppelin documenta che le major release vanno considerate incompatibili per storage upgradeability.

Quindi non assumere sicuro un salto del tipo:

```text
OpenZeppelin 4.x
->
OpenZeppelin 5.x
```

in una implementation live solo perché:

```text
i nomi delle classi sembrano simili.
```

Un dependency upgrade può essere uno storage-layout upgrade.

---

### 58. Non usare opzioni `unsafe` come scorciatoia

Il Foundry Upgrades package espone anche primitive `UnsafeUpgrades`.

La documentazione avverte che non effettuano le normali validation di upgrade safety/storage compatibility.

Il nostro approccio:

```text
validator segnala problema
        |
        v
capisci il problema
        |
        v
correggi layout/design
```

non:

```text
validator segnala problema
        |
        v
disabilita validator
```

Le eccezioni avanzate richiedono una prova rigorosa della sicurezza.

---

### 59. Selector clashes

Anche i function selector fanno parte del problema proxy.

Il Transparent Proxy Pattern separa amministrazione e forwarding anche per evitare ambiguità nella dispatch.

OpenZeppelin avverte di non estendere arbitrariamente `TransparentUpgradeableProxy` con nuove external functions perché selector conflicts possono interferire con le funzioni proxy.

Altro motivo per preferire primitive consolidate.

---

## Threat model e checklist da auditor

### 60. Threat model dell'Escrow upgradeable

#### Asset

```text
fondi in custodia
diritti buyer/seller
stato persistente
approval verso token
configurazioni oracle/router
```

#### Nuovi attori

```text
proxy admin / upgrader
owner
multisig futuro
governance futura
```

#### Nuovi entry point

```text
initialize
reinitializer
upgradeToAndCall / upgrade path
```

#### Nuove failure mode

```text
proxy non inizializzato
implementation non bloccata
upgrade non autorizzato
layout incompatibile
migration incompleta
upgrade verso codice buggy
governance compromise
```

---

### 61. Checklist da auditor — proxy

Quando incontri un contratto upgradeable:

1. È davvero un proxy?
2. Quale pattern usa: UUPS, Transparent, Beacon, custom?
3. Dove è memorizzata l'implementation?
4. Usa ERC-1967?
5. Chi può effettuare l'upgrade?
6. Quell'authority è EOA, multisig, timelock o governance?
7. Il proxy è stato inizializzato?
8. L'implementation è bloccata con `_disableInitializers()`?
9. Gli initializer parent sono stati chiamati?
10. Esistono reinitializer?
11. Una V2 cambia lo storage layout?
12. Esiste validation automatica?
13. È stata fatta review manuale del layout?
14. L'upgrade aggiunge nuove variabili non inizializzate?
15. Esiste una migration plan?
16. Upgrade e migration devono essere atomici?
17. Le funzioni V1 sono regression-tested?
18. Gli invarianti economici sono verificati post-upgrade?
19. Il nuovo codice modifica authorization?
20. Il nuovo codice modifica withdrawal/payout?
21. Cambiano dipendenze esterne?
22. Cambia una major version di libreria?
23. Esistono opzioni unsafe/bypass?
24. Perché vengono usate?
25. Il processo di upgrade è monitorabile tramite eventi?
26. È possibile bloccare accidentalmente l'upgrade futuro?
27. È possibile bloccare la liveness degli utenti?

---

### 62. Checklist storage layout

- [ ] nessuna variabile rimossa
- [ ] nessuna variabile riordinata
- [ ] nessun type change incompatibile
- [ ] nessuna insertion incompatibile
- [ ] inheritance controllata
- [ ] packing verificato
- [ ] storage gaps corretti, se usati
- [ ] ERC-7201 namespace corretti, se usati
- [ ] nuove variabili inizializzate
- [ ] validateUpgrade passa
- [ ] forge inspect esaminato

---

### 63. Checklist initializer

- [ ] constructor implementation -> _disableInitializers()
- [ ] initialize -> initializer
- [ ] parent initializers chiamati
- [ ] proxy inizializzato al deploy
- [ ] secondo initialize fallisce
- [ ] reinitializer versionato
- [ ] reinitializer eseguito una volta
- [ ] zero address validati dove richiesto
- [ ] owner/buyer/seller corretti

---

### 64. Checklist authorization upgrade

- [ ] _authorizeUpgrade implementata
- [ ] access control corretto
- [ ] unauthorized upgrade testato
- [ ] authorized upgrade testato
- [ ] owner/upgrader identificato
- [ ] ownership transfer compreso
- [ ] governance process documentato
- [ ] nuovo implementation validato

---

## Laboratorio, esercizi e chiusura

### 65. Laboratorio Foundry — struttura

```text
upgrade-lab/
├── foundry.toml
├── remappings.txt
├── lib/
│   ├── forge-std/
│   ├── openzeppelin-foundry-upgrades/
│   └── openzeppelin-contracts-upgradeable/
├── src/
│   ├── lab/
│   │   ├── SimpleProxy.sol
│   │   └── LogicV1.sol
│   └── upgrade/
│       ├── EscrowV1.sol
│       ├── EscrowV2.sol
│       └── EscrowBadV2.sol
└── test/
    ├── SimpleProxy.t.sol
    └── EscrowUpgrade.t.sol
```

Comandi:

```bash
forge init upgrade-lab
cd upgrade-lab

forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-foundry-upgrades
forge install OpenZeppelin/openzeppelin-contracts-upgradeable

forge build
forge test -vv
```

Ispezione:

```bash
forge inspect EscrowV1 storageLayout
forge inspect EscrowV2 storageLayout
forge inspect EscrowBadV2 storageLayout
```

Tutto resta locale.

---

### 66. Esercizi

#### Esercizio 1 — Execution context

Per:

```text
Bob -> Proxy ->delegatecall-> Logic
```

scrivi:

```text
msg.sender
address(this)
storage usato
bytecode eseguito
```

prima di controllare gli appunti.

#### Esercizio 2 — Collisione

Crea:

```text
Proxy slot 0 = implementation
Logic slot 0 = owner
```

Chiama `setOwner()` tramite proxy e osserva il valore dell'implementation.

#### Esercizio 3 — Packing

Crea:

```solidity
uint128 a;
uint128 b;
address c;
uint96 d;
```

Prevedi il layout e poi controllalo con:

```bash
forge inspect MyContract storageLayout
```

#### Esercizio 4 — Upgrade compatibile

V1:

```text
a
b
```

V2:

```text
a
b
c
```

Scrivi valori in `a` e `b`, fai upgrade e verifica che non cambino.

#### Esercizio 5 — Upgrade incompatibile

Crea una V2:

```text
b
a
```

e usa `validateUpgrade`.

Non bypassare il warning.

#### Esercizio 6 — Initialization takeover

Deploya localmente un proxy volutamente non inizializzato, usa uno `stranger` di Foundry per chiamare `initialize`, osserva il risultato, poi correggi il deploy.

#### Esercizio 7 — Authorization mutation

Rimuovi temporaneamente `onlyOwner` da `_authorizeUpgrade`.

Il test negativo deve rilevare il problema.

#### Esercizio 8 — V2 migration

Aggiungi:

```solidity
address public feeRecipient;
```

e:

```solidity
initializeV2(address)
```

con `address(0)` vietato.

Testa:

```text
address valido
address(0)
seconda initializeV2
```

#### Esercizio 9 — State-preservation helper

Crea:

```solidity
_assertStatePreserved(...)
```

che confronti prima/dopo:

```text
owner
buyer
seller
amount
funded
```

#### Esercizio 10 — Audit challenge

Analizza:

```solidity
contract MyUUPS is
    Initializable,
    UUPSUpgradeable
{
    address public admin;
    uint256 public value;

    function initialize(
        address admin_
    ) external {
        admin = admin_;
    }

    function _authorizeUpgrade(
        address
    ) internal override {}

    function setValue(
        uint256 x
    ) external {
        value = x;
    }
}
```

Trova almeno dieci problemi o domande di audit prima di proporre una patch.

---

### 67. Cosa devo ricordare

#### 1. `delegatecall` esegue il codice dell'implementation usando il contesto del proxy

```text
code = implementation
storage = proxy
address(this) = proxy
msg.sender = caller originale
```

#### 2. Storage layout è una security boundary

La V2 deve interpretare correttamente i bit già persistenti.

#### 3. ERC-1967 protegge i metadata slot del proxy

Non risolve da solo le incompatibilità fra V1 e V2.

#### 4. Constructor e initializer non sono equivalenti

Il constructor configura l'implementation; una initializer via proxy configura lo storage del proxy.

#### 5. Un proxy non inizializzato è pericoloso

La configurazione iniziale va eseguita subito e protetta.

#### 6. Blocca normalmente l'implementation

Con OpenZeppelin:

```solidity
_disableInitializers();
```

#### 7. UUPS rende `_authorizeUpgrade()` security-critical

Chi supera quel controllo può cambiare il codice futuro.

#### 8. Storage compatibility non implica logic correctness

Servono validation **e** regression/invariant testing.

#### 9. Upgradeability introduce governance nel threat model

La domanda finale è:

> **Chi può cambiare le regole future del contratto?**

---

### 68. Collegamento con il corso

La catena ora è:

```text
transaction model
      |
      v
state machine
      |
      v
external calls
      |
      v
reentrancy
      |
      v
access control
      |
      v
ERC-20
      |
      v
oracle / economics
      |
      v
composability
      |
      v
delegatecall / proxy
      |
      v
UPGRADE AUTHORITY
```

La Lezione 12 partirà precisamente da quest'ultimo punto:

```text
owner
multisig
timelock
governance
separation of duties
emergency powers
```

---

### 69. Fonti della lezione

Fonti tecniche consultate il **21 settembre 2026**:

1. **Solidity Documentation** — semantica di external calls, `delegatecall`, storage e execution context.  
   https://docs.soliditylang.org/

2. **OpenZeppelin Contracts 5.x — Proxy** — `ERC1967Proxy`, `TransparentUpgradeableProxy`, `UUPSUpgradeable`, `Initializable`, differenze Transparent/UUPS e API correnti.  
   https://docs.openzeppelin.com/contracts/5.x/api/proxy

3. **OpenZeppelin — Using with Upgrades** — varianti `@openzeppelin/contracts-upgradeable` ed ERC-7201 Namespaced Storage.  
   https://docs.openzeppelin.com/contracts/5.x/upgradeable

4. **OpenZeppelin — Writing Upgradeable Contracts** — initializer, `_disableInitializers`, storage compatibility, storage gaps ed ERC-7201.  
   https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable

5. **OpenZeppelin — Foundry Upgrades** — installazione e workflow corrente per deploy/upgrade/validation con Foundry.  
   https://docs.openzeppelin.com/upgrades-plugins/foundry/foundry-upgrades

6. **OpenZeppelin — Foundry Upgrades API** — `deployUUPSProxy`, `upgradeProxy`, `validateUpgrade`, `prepareUpgrade` e differenza con `UnsafeUpgrades`.  
   https://docs.openzeppelin.com/upgrades-plugins/foundry/api/upgrades

7. **EIP-1967 — Proxy Storage Slots** — slot standardizzati per implementation, beacon e admin.  
   https://eips.ethereum.org/EIPS/eip-1967

8. **ERC-1822 — Universal Upgradeable Proxy Standard** — fondamenti del pattern UUPS e `proxiableUUID`.  
   https://eips.ethereum.org/EIPS/eip-1822

9. **ERC-7201 — Namespaced Storage Layout** — convenzione per storage namespace.  
   https://eips.ethereum.org/EIPS/eip-7201

10. **Foundry — `forge inspect`** — ispezione di `storageLayout` e altri artifact di compilazione.  
    https://getfoundry.sh/forge/reference/forge-inspect/

11. **OpenZeppelin Contracts — Backwards Compatibility** — garanzie di storage layout per release e avvertenza sulle major version.  
    https://docs.openzeppelin.com/contracts/5.x/backwards-compatibility

---

## Fine Lezione 11

Prossimo argomento:

**Governance, owner, multisig e timelock: amministrazione privilegiata, separation of duties, ritardi di sicurezza, emergency powers e threat model delle chiavi.**
