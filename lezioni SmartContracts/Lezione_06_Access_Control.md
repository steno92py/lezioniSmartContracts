# Lezione 6 — Access Control in Solidity

> Corso: Smart Contract Security / Solidity Security  
> Ambiente: esclusivamente locale e controllato (Foundry / Anvil, account di test, fondi fittizi)  
> Obiettivo: secure coding, auditing, testing e comprensione difensiva delle vulnerabilità

---

## 1. Obiettivi

Alla fine di questa lezione dovresti saper:

- distinguere **authentication**, **authorization** e **business logic authorization**;
- capire perché `msg.sender` è il punto di partenza naturale per molti controlli di accesso;
- capire perché `tx.origin` non deve essere usato per autorizzare operazioni sensibili;
- riconoscere una funzione privilegiata priva di controllo;
- progettare un semplice schema `owner`;
- capire quando un singolo `owner` è troppo grossolano;
- introdurre un controllo a ruoli con OpenZeppelin `AccessControl`;
- ragionare secondo il principio del **least privilege**;
- scrivere test Foundry che dimostrino non solo che un utente autorizzato può agire, ma anche che un utente non autorizzato **non può**;
- individuare errori frequenti come:
  - modifier mancante;
  - controllo sul soggetto sbagliato;
  - ruolo amministrativo eccessivamente potente;
  - trasferimento di ownership rischioso;
  - dipendenza da `tx.origin`;
- trasformare la policy di autorizzazione in proprietà verificabili.

In questa lezione estenderemo concettualmente l'Escrow delle lezioni precedenti con un attore amministrativo, ma resteremo su un design didattico e volutamente piccolo.

---

## 2. Modello mentale

Un controllo di accesso risponde alla domanda:

> **chi può fare cosa, su quale risorsa e in quali condizioni?**

Questa frase contiene già quasi tutto ciò che un auditor deve cercare.

Immagina un edificio:

```text
persona -> badge -> porta -> stanza -> operazione consentita
```

In uno smart contract il modello può diventare:

```text
msg.sender -> ruolo -> funzione -> stato corrente -> modifica consentita
```

Non basta sapere *chi* sta chiamando.

Per esempio:

- Alice può essere il `buyer`;
- Bob può essere il `seller`;
- Carol può essere l'`arbiter`;
- un multisig può essere l'`admin`.

Ma essere `buyer` non significa poter eseguire ogni funzione del contratto.

Una policy più precisa potrebbe essere:

```text
buyer  -> può finanziare l'escrow
seller -> può ricevere i fondi dopo release
arbiter -> può risolvere una disputa
admin -> può mettere in pausa il protocollo
```

Quindi una domanda da auditor non è soltanto:

> “C'è un `onlyOwner`?”

La domanda corretta è:

> “La funzione è protetta dal soggetto corretto, con il privilegio minimo necessario, e il controllo vale in ogni percorso di esecuzione?”

---

## 3. Teoria

### 3.1 Authentication vs authorization

Nel contesto degli smart contract, questi concetti sono vicini ma non identici.

**Authentication** significa stabilire l'identità del chiamante nel modello disponibile alla EVM.

Molto spesso questa informazione è:

```solidity
msg.sender
```

**Authorization** significa invece decidere se quell'identità possiede il permesso richiesto.

Esempio:

```solidity
if (msg.sender != owner) revert Unauthorized();
```

Qui:

- `msg.sender` identifica il chiamante diretto;
- `owner` contiene l'identità autorizzata;
- il confronto implementa la policy.

Il fatto che la EVM sappia chi è `msg.sender` non implica automaticamente che quell'indirizzo sia autorizzato.

---

### 3.2 `msg.sender`

Durante una chiamata EVM, `msg.sender` è il **caller immediato**.

Considera:

```text
Alice EOA
   |
   v
Contract A
   |
   v
Contract B
```

Dentro `Contract A`:

```text
msg.sender == Alice
```

Dentro `Contract B`, se la chiamata arriva da A:

```text
msg.sender == address(ContractA)
```

Questo dettaglio è fondamentale per:

- access control;
- router;
- multisig;
- proxy;
- meta-transactions;
- account abstraction;
- composability.

Un contratto non deve assumere che `msg.sender` sia sempre una persona o un EOA.

Può essere perfettamente un altro smart contract.

---

### 3.3 Perché `tx.origin` è diverso

`tx.origin` identifica l'account che ha originato la transazione più esterna.

Usando lo stesso schema:

```text
Alice
  |
  v
Contract A
  |
  v
Contract B
```

Dentro `Contract B`:

```text
tx.origin  == Alice
msg.sender == ContractA
```

Questa differenza rende `tx.origin` pericoloso per autorizzazione.

Una funzione come:

```solidity
require(tx.origin == owner);
```

non sta verificando chi la sta chiamando direttamente.

Sta verificando chi ha iniziato l'intera catena di chiamate.

Quindi un contratto intermedio può eseguire la chiamata mentre `tx.origin` resta il proprietario originale.

La documentazione Solidity e OWASP sconsigliano esplicitamente l'uso di `tx.origin` per authorization.

---

### 3.4 Access control come matrice

Un metodo utile in audit è scrivere una **permission matrix** prima ancora di leggere i modifier.

Per un Escrow didattico:

| Operazione | Buyer | Seller | Arbiter | Admin | Pubblico |
|---|---:|---:|---:|---:|---:|
| fund | sì | no | no | no | no |
| confirmDelivery | sì | no | no | no | no |
| release | dipende dal design | no | forse | no | no |
| openDispute | sì | sì | no | no | no |
| resolveDispute | no | no | sì | no | no |
| pause | no | no | no | sì | no |
| view state | sì | sì | sì | sì | sì |

Questa tabella è molto più informativa di una lista di modifier.

Ti permette di confrontare:

```text
policy desiderata
        vs
codice effettivo
```

L'errore nasce quando le due cose divergono.

---

### 3.5 Ownership

Il modello più semplice è avere un solo amministratore:

```solidity
address public owner;
```

poi proteggere le operazioni:

```solidity
modifier onlyOwner() {
    if (msg.sender != owner) revert Unauthorized();
    _;
}
```

Questo schema è semplice da capire, ma ha una conseguenza architetturale importante:

```text
owner compromesso
      |
      v
tutte le funzioni onlyOwner compromesse
```

Per questo, da auditor devi sempre chiedere:

> Qual è il blast radius di una chiave privilegiata compromessa?

---

### 3.6 OpenZeppelin `Ownable`

OpenZeppelin Contracts 5.x fornisce `Ownable` con import:

```solidity
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
```

L'owner iniziale viene passato esplicitamente al costruttore:

```solidity
constructor(address initialOwner) Ownable(initialOwner) {}
```

Una funzione privilegiata può usare:

```solidity
onlyOwner
```

OpenZeppelin fornisce anche `Ownable2Step`, utile perché il trasferimento di proprietà richiede:

1. proposta del nuovo owner;
2. accettazione da parte del nuovo owner.

Questo riduce il rischio di trasferire accidentalmente il controllo a un indirizzo errato o incapace di accettarlo.

---

### 3.7 Role-Based Access Control

Quando un singolo owner diventa troppo potente, possiamo separare responsabilità.

Per esempio:

```text
PAUSER_ROLE
ARBITER_ROLE
FEE_MANAGER_ROLE
```

Questo è un esempio di **Role-Based Access Control (RBAC)**.

OpenZeppelin `AccessControl` usa identificatori `bytes32` per rappresentare i ruoli.

Tipicamente:

```solidity
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
```

Poi una funzione può essere protetta con:

```solidity
onlyRole(PAUSER_ROLE)
```

Il vantaggio principale non è solo estetico.

Permette di ridurre i privilegi.

Invece di:

```text
owner può fare tutto
```

possiamo avere:

```text
pauser      -> può solo mettere in pausa
arbiter     -> può solo risolvere dispute
fee manager -> può solo cambiare fee
```

Questo è il principio del **least privilege**:

> ogni soggetto dovrebbe avere soltanto i permessi strettamente necessari al proprio compito.

---

### 3.8 Il ruolo amministratore è anch'esso un privilegio

Con `AccessControl`, un ruolo può avere un ruolo amministratore capace di assegnarlo o revocarlo.

Questo significa che devi analizzare non solo:

```text
chi possiede PAUSER_ROLE?
```

ma anche:

```text
chi può concedere PAUSER_ROLE?
```

Una permission graph può essere più utile di una lista.

```text
DEFAULT_ADMIN_ROLE
      |
      +--> assegna PAUSER_ROLE
      |
      +--> assegna ARBITER_ROLE
      |
      +--> assegna FEE_MANAGER_ROLE
```

Se `DEFAULT_ADMIN_ROLE` è compromesso, tutti i ruoli amministrati da esso possono essere alterati.

OpenZeppelin segnala esplicitamente che l'amministrazione dei ruoli è un elemento centrale del modello di access control.

---

## 4. Esempio Solidity

Costruiamo prima una versione volutamente vulnerabile.

### 4.1 Versione vulnerabile

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract EscrowAdminVulnerable {
    address public buyer;
    address public seller;
    address public admin;

    bool public paused;

    constructor(address _buyer, address _seller) {
        buyer = _buyer;
        seller = _seller;
        admin = msg.sender;
    }

    // BUG: manca il controllo di accesso.
    function setPaused(bool value) external {
        paused = value;
    }
}
```

Il contratto memorizza un `admin`, ma questo non produce alcuna protezione da solo.

Questa è una lezione importante:

> dichiarare un ruolo non significa applicarlo.

L'autorizzazione deve essere verificata nel percorso di esecuzione della funzione sensibile.

---

### 4.2 Versione corretta minimale

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract EscrowAdmin {
    error Unauthorized();

    address public immutable buyer;
    address public immutable seller;
    address public admin;

    bool public paused;

    constructor(address _buyer, address _seller, address _admin) {
        buyer = _buyer;
        seller = _seller;
        admin = _admin;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    function setPaused(bool value) external onlyAdmin {
        paused = value;
    }
}
```

Ora la policy è esplicita:

```text
setPaused -> solo admin
```

---

## 5. Analisi del codice

Analizziamo `setPaused` nella versione corretta.

```solidity
function setPaused(bool value) external onlyAdmin {
    paused = value;
}
```

### Chi può chiamarla?

Tecnicamente chiunque può inviare una call alla funzione `external`.

Ma soltanto chi supera:

```solidity
msg.sender == admin
```

può completarla.

Questo è un concetto importante:

```text
external/public != autorizzato
```

La visibility e l'access control sono due meccanismi diversi.

---

### Quali input controlla il chiamante?

Il chiamante controlla:

```solidity
bool value
```

quindi può scegliere:

```text
true  -> pausa
false -> riprendi
```

Ma solo se è autorizzato.

---

### Quale valore entra?

Nessun Ether deve entrare.

La funzione non è `payable`.

---

### Quale stato viene letto?

Il modifier legge:

```solidity
admin
```

per confrontarlo con:

```solidity
msg.sender
```

---

### Quale stato viene modificato?

La funzione modifica:

```solidity
paused
```

---

### Ci sono chiamate esterne?

No.

Non viene ceduto controllo a codice esterno.

Questo riduce il rischio di reentrancy per questa specifica funzione.

---

### Quali assunzioni vengono fatte?

Almeno queste:

1. `admin` è l'identità corretta;
2. la chiave/entità che controlla `admin` è gestita correttamente;
3. cambiare `paused` è davvero un privilegio amministrativo;
4. non esiste un'altra funzione che modifica `paused` senza controllo;
5. `paused` viene effettivamente rispettato dalle funzioni che dovrebbero essere bloccate.

Il punto 5 è spesso dimenticato.

Una funzione `setPaused()` perfettamente protetta non serve se le funzioni operative ignorano `paused`.

---

## 6. Proprietà e invarianti

Trasformiamo la policy in proprietà verificabili.

### Proprietà P1 — solo admin può cambiare la pausa

> Per ogni indirizzo `x` diverso da `admin`, una chiamata a `setPaused` deve revertire.

Formalmente:

```text
x != admin
=>
setPaused(x) reverts
```

---

### Proprietà P2 — una chiamata non autorizzata non deve modificare lo stato

> Dopo una chiamata non autorizzata, `paused` deve conservare il valore precedente.

```text
paused_before == paused_after
```

---

### Proprietà P3 — admin può modificare la pausa

> L'admin deve poter passare `paused` da `false` a `true` e viceversa.

---

### Proprietà P4 — buyer e seller non ricevono implicitamente privilegi amministrativi

> Essere partecipante dell'Escrow non implica essere admin.

Questo è un esempio di separazione dei ruoli.

---

### Proprietà P5 — la policy deve valere per ogni entry point equivalente

Se esistessero:

```solidity
pause()
unpause()
setPaused(bool)
```

non sarebbe sufficiente proteggere soltanto una di esse.

L'invariante concettuale è:

> nessun percorso esterno deve permettere a un soggetto non autorizzato di modificare lo stato di pausa.

---

## 7. Laboratorio Foundry

Tutto il laboratorio è locale.

### 7.1 Struttura

```text
access-control-lab/
├── foundry.toml
├── src/
│   ├── EscrowAdminVulnerable.sol
│   ├── EscrowAdmin.sol
│   └── TxOriginVault.sol
└── test/
    └── AccessControl.t.sol
```

Se parti da zero:

```bash
forge init access-control-lab
cd access-control-lab
```

---

### 7.2 Contratto vulnerabile

`src/EscrowAdminVulnerable.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract EscrowAdminVulnerable {
    address public immutable buyer;
    address public immutable seller;
    address public admin;

    bool public paused;

    constructor(address _buyer, address _seller, address _admin) {
        buyer = _buyer;
        seller = _seller;
        admin = _admin;
    }

    // VULNERABILITÀ DIDATTICA:
    // nessun controllo su msg.sender.
    function setPaused(bool value) external {
        paused = value;
    }
}
```

---

### 7.3 Contratto corretto

`src/EscrowAdmin.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract EscrowAdmin {
    error Unauthorized();

    address public immutable buyer;
    address public immutable seller;
    address public admin;

    bool public paused;

    constructor(address _buyer, address _seller, address _admin) {
        buyer = _buyer;
        seller = _seller;
        admin = _admin;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    function setPaused(bool value) external onlyAdmin {
        paused = value;
    }
}
```

---

### 7.4 Test

`test/AccessControl.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/Test.sol";
import {EscrowAdminVulnerable} from "../src/EscrowAdminVulnerable.sol";
import {EscrowAdmin} from "../src/EscrowAdmin.sol";

contract AccessControlTest is Test {
    address internal buyer = makeAddr("buyer");
    address internal seller = makeAddr("seller");
    address internal admin = makeAddr("admin");
    address internal stranger = makeAddr("stranger");

    EscrowAdminVulnerable internal vulnerable;
    EscrowAdmin internal secureEscrow;

    function setUp() public {
        vulnerable = new EscrowAdminVulnerable(
            buyer,
            seller,
            admin
        );

        secureEscrow = new EscrowAdmin(
            buyer,
            seller,
            admin
        );
    }

    function test_Vulnerable_StrangerCanPause() public {
        assertFalse(vulnerable.paused());

        vm.prank(stranger);
        vulnerable.setPaused(true);

        assertTrue(vulnerable.paused());
    }

    function test_AdminCanPause() public {
        vm.prank(admin);
        secureEscrow.setPaused(true);

        assertTrue(secureEscrow.paused());
    }

    function test_RevertWhen_StrangerTriesToPause() public {
        vm.prank(stranger);
        vm.expectRevert(EscrowAdmin.Unauthorized.selector);

        secureEscrow.setPaused(true);
    }

    function test_UnauthorizedCallDoesNotChangeState() public {
        assertFalse(secureEscrow.paused());

        vm.prank(stranger);
        vm.expectRevert(EscrowAdmin.Unauthorized.selector);
        secureEscrow.setPaused(true);

        assertFalse(secureEscrow.paused());
    }

    function test_BuyerIsNotImplicitlyAdmin() public {
        vm.prank(buyer);
        vm.expectRevert(EscrowAdmin.Unauthorized.selector);

        secureEscrow.setPaused(true);
    }

    function test_SellerIsNotImplicitlyAdmin() public {
        vm.prank(seller);
        vm.expectRevert(EscrowAdmin.Unauthorized.selector);

        secureEscrow.setPaused(true);
    }
}
```

---

### 7.5 Esecuzione

```bash
forge test -vv
```

Risultato concettuale atteso:

```text
test_Vulnerable_StrangerCanPause               PASS

test_AdminCanPause                             PASS
test_RevertWhen_StrangerTriesToPause           PASS
test_UnauthorizedCallDoesNotChangeState        PASS
test_BuyerIsNotImplicitlyAdmin                 PASS
test_SellerIsNotImplicitlyAdmin                PASS
```

Attenzione al primo test.

Il fatto che passi non significa che il contratto sia sicuro.

Significa che il test ha correttamente dimostrato la vulnerabilità.

Questa distinzione è fondamentale nel security testing:

```text
PASS del test
!=
contratto sicuro
```

Dipende da cosa il test sta cercando di dimostrare.

---

## 8. Test negativi

Un buon test di access control deve quasi sempre includere il caso non autorizzato.

Un anti-pattern comune è testare solo:

```solidity
function test_AdminCanPause() public {
    ...
}
```

Questo dimostra soltanto che la funzione funziona per l'admin.

Non dimostra che gli altri siano esclusi.

La coppia corretta è:

```text
authorized actor succeeds
unauthorized actor fails
```

Per ogni funzione privilegiata, chiediti quindi:

```text
positive authorization test?
negative authorization test?
```

---

### 8.1 Test con attori distinti

Usare account nominati aiuta la leggibilità:

```solidity
address buyer = makeAddr("buyer");
address seller = makeAddr("seller");
address admin = makeAddr("admin");
address stranger = makeAddr("stranger");
```

Poi:

```solidity
vm.prank(stranger);
```

imposta il `msg.sender` della chiamata successiva.

Questo rende i test molto vicini al threat model.

---

## 9. Vulnerabilità o errore di progettazione

### 9.1 Vulnerabilità: missing access control

Versione vulnerabile:

```solidity
function setPaused(bool value) external {
    paused = value;
}
```

Requisito desiderato:

```text
solo admin può cambiare paused
```

Implementazione reale:

```text
chiunque può cambiare paused
```

La vulnerabilità nasce quindi da una divergenza tra:

```text
policy
  vs
implementation
```

---

### 9.2 Riproduzione locale

Il test:

```solidity
vm.prank(stranger);
vulnerable.setPaused(true);
```

non attacca alcun protocollo reale.

Serve esclusivamente a dimostrare, sul nostro contratto giocattolo locale, che una entry point sensibile non impone la policy richiesta.

---

### 9.3 Correzione

Aggiungiamo:

```solidity
modifier onlyAdmin() {
    if (msg.sender != admin) revert Unauthorized();
    _;
}
```

poi:

```solidity
function setPaused(bool value) external onlyAdmin {
    paused = value;
}
```

---

### 9.4 Test di regressione

Il test fondamentale è:

```solidity
function test_RevertWhen_StrangerTriesToPause() public {
    vm.prank(stranger);
    vm.expectRevert(EscrowAdmin.Unauthorized.selector);

    secureEscrow.setPaused(true);
}
```

Questo test deve restare nella suite.

Se in futuro qualcuno rimuove accidentalmente `onlyAdmin`, il test fallisce.

Il test diventa quindi una barriera contro la regressione.

---

## 10. Micro-lab: perché `tx.origin` non va usato per authorization

Creiamo un esempio esclusivamente locale.

`src/TxOriginVault.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract TxOriginVault {
    error Unauthorized();

    address public immutable owner;
    uint256 public protectedValue;

    constructor(address _owner) {
        owner = _owner;
    }

    // VULNERABILE: usa tx.origin.
    function setProtectedValue(uint256 value) external {
        if (tx.origin != owner) revert Unauthorized();
        protectedValue = value;
    }
}

contract Forwarder {
    function forwardSet(
        TxOriginVault target,
        uint256 value
    ) external {
        target.setProtectedValue(value);
    }
}
```

Il punto non è costruire un attacco reale.

Vogliamo osservare una proprietà della EVM.

```text
owner -> Forwarder -> TxOriginVault
```

Nel vault:

```text
tx.origin  = owner
msg.sender = Forwarder
```

Se il controllo usa `tx.origin`, il forwarder viene accettato indirettamente.

### Test locale

Aggiungi:

```solidity
import {
    TxOriginVault,
    Forwarder
} from "../src/TxOriginVault.sol";
```

poi:

```solidity
function test_TxOriginAllowsIndirectCall() public {
    TxOriginVault vault = new TxOriginVault(admin);
    Forwarder forwarder = new Forwarder();

    vm.prank(admin);
    forwarder.forwardSet(vault, 123);

    assertEq(vault.protectedValue(), 123);
}
```

Il test mostra:

```text
caller diretto del vault != admin
```

ma la funzione riesce comunque perché:

```text
tx.origin == admin
```

Per un access control diretto, ciò che volevamo invece verificare era:

```text
msg.sender == admin
```

---

## 11. Variante con OpenZeppelin `Ownable`

Installazione:

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

Contratto:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract EscrowOwnable is Ownable {
    bool public paused;

    constructor(address initialOwner)
        Ownable(initialOwner)
    {}

    function setPaused(bool value)
        external
        onlyOwner
    {
        paused = value;
    }
}
```

Nota importante per OpenZeppelin Contracts 5.x:

```solidity
Ownable(initialOwner)
```

riceve esplicitamente l'owner iniziale.

Non assumere quindi automaticamente pattern di versioni precedenti.

Quando integri una libreria, verifica sempre la documentazione della versione installata.

---

## 12. Variante RBAC con OpenZeppelin `AccessControl`

Esempio didattico:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    AccessControl
} from "@openzeppelin/contracts/access/AccessControl.sol";

contract EscrowRoles is AccessControl {
    bytes32 public constant PAUSER_ROLE =
        keccak256("PAUSER_ROLE");

    bytes32 public constant ARBITER_ROLE =
        keccak256("ARBITER_ROLE");

    bool public paused;

    constructor(
        address admin,
        address pauser,
        address arbiter
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(ARBITER_ROLE, arbiter);
    }

    function setPaused(bool value)
        external
        onlyRole(PAUSER_ROLE)
    {
        paused = value;
    }

    function resolveDispute()
        external
        onlyRole(ARBITER_ROLE)
    {
        // logica didattica da introdurre nelle lezioni successive
    }
}
```

Ora l'actor che può pausare non deve per forza essere lo stesso che decide le dispute.

Questo riduce il blast radius di una singola credenziale compromessa.

---

## 13. Ragionamento da auditor

Quando trovi:

```solidity
function setFee(uint256 newFee) external onlyOwner
```

non fermarti a:

```text
"c'è onlyOwner, quindi è sicura"
```

Fai invece almeno queste domande.

### 13.1 Chi controlla l'owner?

Potrebbe essere:

- un EOA;
- un multisig;
- un timelock;
- un governance contract;
- un altro smart contract.

La semantica operativa cambia molto.

---

### 13.2 Quanto potere ha?

Può:

```text
cambiare fee?
ritirare fondi?
aggiornare implementation?
pausare?
modificare oracle?
assegnare ruoli?
```

Più poteri sono concentrati, maggiore è il blast radius.

---

### 13.3 Esistono percorsi alternativi?

Forse `setFee()` è protetta ma esiste:

```solidity
configure(...)
initialize(...)
updateConfig(...)
```

che modifica la stessa variabile senza controllo equivalente.

Devi analizzare **tutti gli entry point**.

---

### 13.4 Il modifier è corretto?

Anche un modifier presente può essere sbagliato.

Esempio assurdo ma istruttivo:

```solidity
modifier onlyAdmin() {
    if (msg.sender == admin) revert Unauthorized();
    _;
}
```

Qui la condizione è invertita.

Il nome del modifier non è una prova.

Leggi sempre il corpo.

---

### 13.5 Il controllo avviene sul soggetto giusto?

Esempio sospetto:

```solidity
require(tx.origin == owner);
```

oppure:

```solidity
require(user == owner);
```

quando `user` è un parametro controllato dal chiamante.

Questa funzione:

```solidity
function adminAction(address user) external {
    require(user == owner);
    ...
}
```

non autentica il chiamante.

Chiunque può passare `owner` come parametro.

---

## 14. Errori ricorrenti

### Errore A — modifier mancante

```solidity
function pause() external {
    paused = true;
}
```

---

### Errore B — parametro usato come identità

```solidity
function pause(address caller) external {
    require(caller == admin);
    paused = true;
}
```

Il chiamante controlla `caller`.

---

### Errore C — uso di `tx.origin`

```solidity
require(tx.origin == owner);
```

Il controllo segue l'origine della transazione e non il caller immediato.

---

### Errore D — ruolo troppo potente

```text
owner:
- pause
- upgrade
- withdraw treasury
- change oracle
- mint
- resolve disputes
```

Anche se tecnicamente corretto, il design concentra un enorme potere.

---

### Errore E — admin del ruolo ignorato

Il contratto protegge bene:

```solidity
onlyRole(PAUSER_ROLE)
```

ma un account poco protetto possiede:

```text
DEFAULT_ADMIN_ROLE
```

ed è quindi in grado di auto-assegnarsi il ruolo.

---

### Errore F — ownership transfer non considerato nel threat model

Il contratto è sicuro oggi, ma:

```text
owner A -> transfer -> owner B
```

può modificare radicalmente la trust assumption.

---

## 15. Checklist da auditor

Quando analizzi access control, usa questa checklist compatta.

- Quali funzioni modificano stato sensibile?
- Quali funzioni muovono asset?
- Quali funzioni cambiano configurazione?
- Quali funzioni assegnano o revocano privilegi?
- Chi può chiamare ciascuna funzione?
- Il controllo usa `msg.sender` o una semantica equivalente appropriata?
- Compare `tx.origin` in un controllo di authorization?
- Un parametro controllato dall'utente viene scambiato per identità affidabile?
- Tutti i percorsi equivalenti hanno lo stesso livello di protezione?
- Il modifier è davvero implementato correttamente?
- Chi controlla l'owner/admin?
- Chi può cambiare l'owner/admin?
- Chi amministra ciascun ruolo?
- I ruoli rispettano il least privilege?
- Esistono privilegi eccessivi o combinazioni pericolose?
- Una funzione di pausa viene realmente rispettata dalle funzioni operative?
- Ci sono initializer o setup function richiamabili impropriamente?
- Esistono test negativi per caller non autorizzati?
- Esistono eventi utili per osservare cambi di privilegi?

---

## 16. Esercizi

Non leggere soluzioni: implementali e testali.

### Esercizio 1 — `onlyBuyer`

Aggiungi al nostro Escrow:

```solidity
function confirmDelivery()
```

Requisito:

> soltanto il buyer può chiamarla.

Scrivi:

- test positivo buyer;
- test negativo seller;
- test negativo stranger.

---

### Esercizio 2 — trasferimento admin

Aggiungi:

```solidity
function transferAdmin(address newAdmin)
```

Definisci prima le proprietà.

Pensa almeno a:

```text
chi può trasferire?
newAdmin può essere address(0)?
quando il vecchio admin perde i privilegi?
```

Poi scrivi i test.

---

### Esercizio 3 — due-step admin transfer

Implementa:

```text
admin -> pendingAdmin
pendingAdmin -> acceptAdmin
```

Proprietà:

> il controllo non cambia finché `pendingAdmin` non accetta.

---

### Esercizio 4 — RBAC

Usa OpenZeppelin `AccessControl` e crea:

```text
PAUSER_ROLE
ARBITER_ROLE
```

Requisiti:

- il pauser può cambiare lo stato di pausa;
- l'arbiter non può farlo;
- il pauser non può risolvere dispute;
- l'arbiter può risolverle.

---

### Esercizio 5 — audit manuale

Individua tutti i problemi nel seguente contratto:

```solidity
pragma solidity ^0.8.37;

contract BrokenAdmin {
    address public owner;
    bool public paused;

    constructor() {
        owner = msg.sender;
    }

    function pause(address claimedCaller) external {
        require(claimedCaller == owner);
        paused = true;
    }

    function unpause() external {
        require(tx.origin == owner);
        paused = false;
    }

    function changeOwner(address newOwner) external {
        owner = newOwner;
    }
}
```

Per ogni finding scrivi:

```text
Requirement
Bug
Impact
Fix
Regression test
```

---

## 17. Cosa devo ricordare

1. **`msg.sender` è il caller immediato.**

2. **`tx.origin` non deve essere usato come meccanismo di authorization.**

3. Dichiarare `owner` o un ruolo non protegge nulla finché il controllo non viene applicato alle entry point sensibili.

4. Visibility (`external`, `public`, ecc.) e authorization sono concetti diversi.

5. Per ogni test positivo di una funzione privilegiata dovrebbe quasi sempre esistere almeno un test negativo.

6. Il problema non è soltanto “chi possiede il ruolo”, ma anche “chi può assegnare quel ruolo”.

7. **Least privilege** riduce il blast radius di una credenziale compromessa.

8. Un `onlyOwner` corretto non significa automaticamente che il design amministrativo sia sicuro.

9. In audit devi ricostruire una permission matrix o permission graph, non limitarti a cercare modifier con grep.

10. Una policy di access control va trasformata in proprietà verificabili e mantenuta con test di regressione.

---

## 18. Collegamento con il nostro Escrow

Finora abbiamo introdotto:

```text
transazioni
  ↓
msg.sender / msg.value / calldata / storage
  ↓
Foundry e metodo di testing
  ↓
macchina a stati dell'Escrow
  ↓
Ether e chiamate esterne
  ↓
reentrancy
  ↓
access control
```

Adesso abbiamo due dimensioni di sicurezza che devono convivere:

```text
CHI può eseguire una transizione?

E

IN QUALE STATO quella transizione è lecita?
```

Questa intersezione sarà fondamentale nella prossima lezione sugli **errori logici e sulla correttezza della state machine**.

Non basta quindi avere:

```text
onlyBuyer
```

Se il buyer può chiamare la funzione nello stato sbagliato, il contratto può comunque essere vulnerabile.

La forma corretta diventa:

```text
caller autorizzato
        +
stato autorizzato
        +
input validi
        +
effetti coerenti
```

---

## 19. Fonti della lezione

Fonti tecniche consultate per questa lezione:

1. **OpenZeppelin Contracts 5.x — Access Control**  
   https://docs.openzeppelin.com/contracts/5.x/access-control

2. **OpenZeppelin Contracts 5.x — Access API (`Ownable`, `Ownable2Step`, `AccessControl`, `AccessManager`)**  
   https://docs.openzeppelin.com/contracts/5.x/api/access

3. **Solidity Documentation — Security Considerations (`tx.origin`)**  
   https://docs.soliditylang.org/en/latest/security-considerations.html

4. **Foundry Book — Writing Tests**  
   https://getfoundry.sh/forge/writing-tests

5. **Foundry Book — `expectRevert`**  
   https://getfoundry.sh/cheatcodes/expect-revert

6. **OWASP Smart Contract Security — SC01:2026 Access Control Vulnerabilities**  
   https://scs.owasp.org/sctop10/SC01-AccessControlVulnerabilities/

7. **OWASP SCWE-016 — Insufficient Authorization Checks**  
   https://scs.owasp.org/SCWE/SCSVS-AUTH/SCWE-016/

8. **OWASP SCWE-018 — Use of `tx.origin` for Authorization**  
   https://scs.owasp.org/SCWE/SCSVS-AUTH/SCWE-018/

9. **OWASP SCSVS-AUTH-2 — Authorization Mechanisms**  
   https://scs.owasp.org/SCSVS/controls/SCSVS-AUTH-2/

---

**Fine Lezione 6.**

La lezione successiva non è inclusa qui, come richiesto dal formato del corso.
