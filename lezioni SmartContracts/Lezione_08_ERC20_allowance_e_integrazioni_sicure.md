# Lezione 8 — ERC-20, allowance e integrazioni sicure

> **Obiettivo del corso:** studio difensivo, secure coding, testing e auditing.  
> Tutti gli esempi di questa lezione sono pensati esclusivamente per **Foundry/Anvil in locale**, account di test e token giocattolo.

---

## 1. Obiettivi

Alla fine di questa lezione dovresti saper:

- spiegare che cosa rappresenta un token ERC-20 e che cosa **non** garantisce lo standard;
- distinguere `transfer`, `approve`, `allowance` e `transferFrom`;
- capire che l'**allowance è una autorizzazione persistente**, non un trasferimento;
- analizzare un'integrazione con un token come una **chiamata esterna verso codice non controllato**;
- riconoscere il bug classico di un ritorno `bool` ignorato;
- usare `SafeERC20` di OpenZeppelin;
- distinguere **accounting nominale** e **saldo reale ricevuto**;
- capire perché fee-on-transfer, rebasing e token non standard rompono assunzioni ingenue;
- scrivere test negativi per allowance insufficiente, token che restituisce `false`, deposito zero e trasferimenti con fee;
- formulare proprietà e invarianti utili per un Escrow basato su token;
- leggere una semplice integrazione ERC-20 con mentalità da auditor.

Questa lezione non introduce ancora oracoli, slippage o MEV: saranno il centro della prossima parte del corso.

---

# 2. Modello mentale

Con Ether, il valore nativo appartiene direttamente al modello della EVM.

Con un ERC-20, invece, il "saldo" non è una proprietà nativa dell'account Ethereum.

È **stato dentro un altro smart contract**.

Schema mentale:

```text
Alice
  |
  | chiama transfer()
  v
Token ERC20
  |
  | modifica il proprio storage
  v
balances[Alice] -= amount
balances[Bob]   += amount
```

Quando il nostro Escrow "riceve 100 token", in realtà non entra un oggetto chiamato token dentro l'Escrow.

È il **contratto token** che modifica il proprio storage:

```text
balanceOf(alice)  -> diminuisce
balanceOf(escrow) -> aumenta
```

Questo dettaglio è fondamentale per la sicurezza.

Un protocollo che integra un ERC-20 sta quindi dipendendo da:

```text
nostro contratto
      |
      | external call
      v
contratto token
```

Il contratto token è una **dipendenza esterna**.

Anche quando l'interfaccia è standardizzata, il comportamento concreto può differire.

---

# 3. Teoria

## 3.1 ERC-20: che problema risolve

ERC-20 definisce un'interfaccia comune per token fungibili.

"Fungibile" significa che una unità è intercambiabile con un'altra unità dello stesso token.

L'interfaccia fondamentale comprende concettualmente:

```solidity
totalSupply()
balanceOf(account)

transfer(to, value)

allowance(owner, spender)
approve(spender, value)
transferFrom(from, to, value)
```

e gli eventi:

```solidity
Transfer(...)
Approval(...)
```

La grande utilità dello standard non è dire **come** debba essere implementato internamente il token.

È permettere ai protocolli di interagire tramite una API comune.

---

## 3.2 `balanceOf`

```solidity
token.balanceOf(alice)
```

chiede al contratto token:

> Quante unità di questo token risultano attribuite ad Alice?

Questo valore appartiene allo storage del token.

Non allo storage di Alice.

Non allo storage del nostro Escrow.

---

## 3.3 `transfer`

Supponiamo che Alice chiami:

```solidity
token.transfer(bob, 100);
```

Il chiamante del token è Alice.

Il significato è:

```text
sposta 100 unità
DA msg.sender
A bob
```

Concettualmente:

```text
Alice ------100------> Bob
```

---

# 3.4 Perché esiste `approve`

Molte applicazioni devono spostare token posseduti da un utente.

Esempio:

```text
Alice possiede 1000 TOKEN

Escrow deve acquisirne 100
```

L'Escrow non può semplicemente eseguire:

```solidity
token.transfer(address(this), 100);
```

Perché `transfer()` trasferirebbe token posseduti dal **chiamante**, cioè dall'Escrow stesso.

Serve quindi un meccanismo con cui Alice dica al contratto token:

> autorizzo l'Escrow a spendere fino a X dei miei token.

È l'allowance.

---

# 3.5 `approve`, `allowance`, `transferFrom`

Alice:

```solidity
token.approve(address(escrow), 100);
```

Il token registra qualcosa concettualmente simile a:

```text
allowance[Alice][Escrow] = 100
```

Ora l'Escrow può chiamare:

```solidity
token.transferFrom(alice, address(this), 100);
```

Schema:

```text
Alice
  |
  | approve(Escrow, 100)
  v

Token storage:
allowance[Alice][Escrow] = 100


Escrow
  |
  | transferFrom(Alice, Escrow, 100)
  v

Token storage:
balance[Alice]  -= 100
balance[Escrow] += 100
allowance[Alice][Escrow] -= 100
```

---

# 3.6 L'allowance non trasferisce nulla

Questo è un errore mentale molto comune.

Dopo:

```solidity
approve(escrow, 100)
```

i token sono ancora di Alice.

È cambiato soltanto un diritto di spesa.

Prima:

```text
balance Alice = 1000
allowance Alice->Escrow = 0
```

Dopo `approve(100)`:

```text
balance Alice = 1000
allowance Alice->Escrow = 100
```

Solo dopo `transferFrom`:

```text
balance Alice = 900
balance Escrow = 100
```

---

# 3.7 Perché l'allowance è importante per la sicurezza

Un'allowance è una **capability persistente**.

Finché esiste, lo spender può tentare di usarla.

Per esempio:

```text
Alice balance:     500
allowance Escrow:  500
```

Se l'Escrow o il suo controllo diventano pericolosi, quell'autorizzazione costituisce ancora una superficie di rischio.

Per questo, dal punto di vista del design:

- preferire autorizzazioni limitate quando possibile;
- non assumere che un'approval sia una operazione innocua;
- considerare lifetime e revocabilità dell'allowance;
- evitare di confondere "saldo del wallet" con "saldo effettivamente esposto a spender approvati".

---

# 3.8 Il problema storico nel modificare un'allowance

Supponiamo:

```text
allowance attuale = 100
```

Alice vuole cambiarla a:

```text
50
```

e invia:

```solidity
approve(spender, 50);
```

Esiste un noto problema di ordering/front-running: lo spender può tentare di consumare la vecchia allowance prima che venga aggiornata, e poi beneficiare anche della nuova.

EIP-20 nota esplicitamente il problema lato client e suggerisce alle interfacce di portare prima a `0` l'allowance quando la si cambia da un valore non-zero a un altro valore non-zero.

Per il nostro corso è importante soprattutto il principio:

> **un'allowance non è soltanto un numero: è una autorizzazione attiva che interagisce con ordering e concorrenza delle transazioni.**

Non simuleremo attacchi su mempool reali.

---

# 3.9 `transfer` e `transferFrom` sono chiamate esterne

Nel nostro Escrow:

```solidity
token.transferFrom(msg.sender, address(this), amount);
```

sembra una riga semplice.

Ma dal punto di vista EVM:

```text
Escrow
  |
  | CALL
  v
Token contract
```

Il controllo passa al contratto token.

Questo significa che dobbiamo chiederci:

- il token reverte?
- ritorna `false`?
- non ritorna niente?
- trasferisce esattamente `amount`?
- applica fee?
- esegue callback indirette?
- modifica saldi in modo non convenzionale?
- è upgradeable?
- è un indirizzo controllato da qualcuno?
- il comportamento può cambiare?

Questa è mentalità da auditor:

> ogni dipendenza esterna è anche una assunzione.

---

# 3.10 Il valore di ritorno ERC-20

L'interfaccia standard dichiara tipicamente:

```solidity
function transfer(address to, uint256 value)
    external
    returns (bool);

function transferFrom(address from, address to, uint256 value)
    external
    returns (bool);
```

EIP-20 dice che i chiamanti devono gestire il possibile `false`.

Quindi questo pattern è fragile:

```solidity
token.transferFrom(
    msg.sender,
    address(this),
    amount
);

// nessun controllo del risultato
credits[msg.sender] += amount;
```

Se un token restituisse `false` senza revertire, il contratto potrebbe aggiornare l'accounting anche se il trasferimento non è avvenuto.

Risultato:

```text
crediti interni > token realmente posseduti
```

---

# 3.11 Perché esiste `SafeERC20`

In pratica esistono token con comportamenti legacy/non uniformi.

OpenZeppelin fornisce:

```solidity
SafeERC20
```

Import attuale della linea Contracts 5.x:

```solidity
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
```

Uso:

```solidity
using SafeERC20 for IERC20;
```

poi:

```solidity
token.safeTransferFrom(
    msg.sender,
    address(this),
    amount
);
```

`SafeERC20` gestisce sia operazioni che restituiscono `false`, sia token che non restituiscono un valore ma completano senza revert.

Importante:

> `SafeERC20` rende più robusta la meccanica della chiamata.  
> Non dimostra però che il protocollo abbia ricevuto **esattamente `amount`**.

Questa distinzione ci porta al prossimo problema.

---

# 3.12 Accounting nominale vs saldo reale

Consideriamo:

```solidity
token.safeTransferFrom(
    msg.sender,
    address(this),
    amount
);

credits[msg.sender] += amount;
```

Supponiamo:

```text
amount = 100
```

ma il token applica una fee del 10%.

Il contratto potrebbe ricevere:

```text
90
```

mentre registriamo:

```text
credit = 100
```

Abbiamo creato una passività maggiore degli asset effettivi.

```text
asset reali       = 90
crediti registrati = 100

deficit = 10
```

---

# 3.13 Misurare il saldo prima e dopo

Un approccio difensivo per protocolli che intendono supportare token fee-on-transfer è:

```solidity
uint256 beforeBalance =
    token.balanceOf(address(this));

token.safeTransferFrom(
    msg.sender,
    address(this),
    amount
);

uint256 afterBalance =
    token.balanceOf(address(this));

uint256 received =
    afterBalance - beforeBalance;
```

Ora l'accounting può usare:

```solidity
credits[msg.sender] += received;
```

anziché:

```solidity
credits[msg.sender] += amount;
```

---

# 3.14 Ma anche `balanceBefore/balanceAfter` è un'assunzione

Non dobbiamo trasformare il pattern in un dogma.

Esistono token con caratteristiche più complesse:

- rebasing;
- elastic supply;
- hooks;
- transfer fee;
- blacklist;
- pause;
- proxy upgradeabili;
- saldi che cambiano per ragioni diverse dal singolo trasferimento.

Quindi una domanda di audit migliore è:

> Quali classi di token dichiara di supportare questo protocollo?

E poi:

> Le proprietà del protocollo sono realmente valide per tutte quelle classi?

Spesso la scelta più sicura è restringere esplicitamente il supporto.

Per esempio:

```text
Supportiamo soltanto token ERC-20 selezionati,
senza fee-on-transfer e senza rebasing.
```

oppure progettare l'accounting specificamente per comportamenti diversi.

---

# 3.15 `decimals` non è sicurezza contabile

Un token può avere:

```text
6 decimals
18 decimals
8 decimals
```

`decimals()` serve principalmente alla rappresentazione.

Solidity lavora comunque con interi.

Esempio token a 6 decimals:

```text
1 TOKEN = 1_000_000 unità base
```

token a 18 decimals:

```text
1 TOKEN = 1_000_000_000_000_000_000 unità base
```

Il contratto dovrebbe ragionare in **unità base**.

Problemi seri emergono quando un protocollo combina token con decimals differenti e presume che i numeri siano direttamente confrontabili.

Questo diventerà ancora più importante nella lezione su prezzi/oracoli.

---

# 4. Esempio Solidity

Costruiamo un Escrow locale che custodisce un singolo ERC-20.

Per questa lezione:

- `buyer` deposita;
- `seller` riceve alla release;
- non trattiamo ancora prezzi/oracoli;
- il token è fissato nel constructor;
- usiamo `SafeERC20`.

## `src/TokenEscrow.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {IERC20} from
    "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenEscrow {
    using SafeERC20 for IERC20;

    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    IERC20 public immutable token;
    address public immutable buyer;
    address public immutable seller;

    State public state;
    uint256 public escrowedAmount;

    error OnlyBuyer();
    error InvalidState();
    error ZeroAmount();
    error NothingReceived();

    constructor(
        IERC20 token_,
        address buyer_,
        address seller_
    ) {
        token = token_;
        buyer = buyer_;
        seller = seller_;
        state = State.Created;
    }

    function deposit(uint256 requestedAmount) external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Created) revert InvalidState();
        if (requestedAmount == 0) revert ZeroAmount();

        uint256 beforeBalance =
            token.balanceOf(address(this));

        token.safeTransferFrom(
            buyer,
            address(this),
            requestedAmount
        );

        uint256 afterBalance =
            token.balanceOf(address(this));

        uint256 received =
            afterBalance - beforeBalance;

        if (received == 0) revert NothingReceived();

        escrowedAmount = received;
        state = State.Funded;
    }

    function release() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        uint256 amount = escrowedAmount;

        // Effects prima dell'interazione esterna.
        escrowedAmount = 0;
        state = State.Released;

        token.safeTransfer(seller, amount);
    }

    function refund() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        uint256 amount = escrowedAmount;

        escrowedAmount = 0;
        state = State.Refunded;

        token.safeTransfer(buyer, amount);
    }
}
```

Questo non è codice production-ready.

È un oggetto didattico per ragionare sulle proprietà.

---

# 5. Analisi del codice

## 5.1 Constructor

```solidity
constructor(
    IERC20 token_,
    address buyer_,
    address seller_
)
```

### Chi può chiamarlo?

Solo il deployer, durante la creazione.

### Input controllabili

Il deployer sceglie:

- token;
- buyer;
- seller.

### Stato scritto

```text
token
buyer
seller
state = Created
```

### Chiamate esterne

Nessuna.

### Assunzioni

La più importante:

```text
token_ identifica davvero il token che intendiamo supportare.
```

In un sistema reale dovremmo anche ragionare su:

- `address(0)`;
- token non compatibile;
- token malevolo;
- token upgradeabile;
- governance che sceglie la allowlist.

---

# 5.2 `deposit`

```solidity
function deposit(uint256 requestedAmount)
```

## Chi può chiamarla?

Solo:

```text
buyer
```

grazie a:

```solidity
if (msg.sender != buyer) revert OnlyBuyer();
```

## Quali input controlla il chiamante?

```text
requestedAmount
```

e indirettamente:

- la sua allowance;
- il suo saldo nel token.

## Quale valore nativo entra?

Nessun Ether:

```text
msg.value = 0
```

La funzione non è `payable`.

## Stato letto

- `buyer`
- `state`
- saldo token dell'Escrow

## Stato modificato

- `escrowedAmount`
- `state`

## Chiamate esterne

Tre:

```solidity
token.balanceOf(...)
token.safeTransferFrom(...)
token.balanceOf(...)
```

Anche `balanceOf()` è tecnicamente una chiamata verso un altro contratto.

`view` non significa:

> questa dipendenza è automaticamente affidabile.

## Quando passa il controllo a codice esterno?

Durante tutte le chiamate al token.

La chiamata critica è:

```solidity
safeTransferFrom(...)
```

## Assunzioni

- il saldo dopo deve essere almeno quello precedente;
- il token deve comportarsi in modo compatibile con l'accounting scelto;
- il valore ricevuto è rappresentabile come differenza dei due saldi;
- il token non deve alterare semanticamente l'Escrow in modi inattesi.

---

# 5.3 `release`

## Chi può chiamarla?

Solo il buyer.

## Input del chiamante

Nessun amount.

Questo riduce la superficie di errore: la funzione paga ciò che il contratto ha già registrato.

## Stato letto

```text
state
escrowedAmount
seller
```

## Stato modificato

Prima della chiamata esterna:

```text
escrowedAmount = 0
state = Released
```

## Chiamata esterna

```solidity
token.safeTransfer(seller, amount);
```

## Controllo esterno

Durante il trasferimento il controllo passa al token.

Per questo manteniamo il pattern CEI studiato nella Lezione 4/5.

Se il trasferimento fallisce e `safeTransfer` reverte, l'intera transazione viene revertita, comprese le modifiche precedenti allo stato.

Quindi atomicamente:

```text
o stato Released + pagamento riescono insieme
o nulla cambia
```

---

# 5.4 `refund`

È simmetrica a `release`.

Destinatario:

```text
buyer
```

La proprietà importante diventa:

```text
una posizione Funded può terminare una volta sola:
o Released,
o Refunded.
```

---

# 6. Proprietà e invarianti

Prima dei test, scriviamo le proprietà.

## P1 — Solo il buyer può depositare

```text
caller != buyer
=> deposit deve revertire
```

## P2 — Deposito solo da `Created`

```text
state != Created
=> deposit deve revertire
```

## P3 — Zero non è un deposito valido

```text
requestedAmount == 0
=> revert
```

## P4 — Accounting basato su ricevuto reale

Dopo un deposito riuscito:

```text
escrowedAmount == token ricevuti dall'Escrow
```

non necessariamente:

```text
escrowedAmount == requestedAmount
```

## P5 — Funded deve essere coperto

Nel nostro modello semplice:

```text
state == Funded
=> token.balanceOf(escrow) >= escrowedAmount
```

Questa è una prima proprietà di solvibilità.

## P6 — Released azzera la passività

```text
state == Released
=> escrowedAmount == 0
```

## P7 — Refunded azzera la passività

```text
state == Refunded
=> escrowedAmount == 0
```

## P8 — Stati terminali

Da:

```text
Released
Refunded
```

non deve essere possibile tornare a:

```text
Created
Funded
```

## P9 — Il pagamento non deve essere contabilizzato come riuscito se il token fallisce

```text
token transfer fails
=> state transition must not persist
```

L'atomicità della transazione ci aiuta qui.

---

# 7. Laboratorio Foundry

## 7.1 Struttura

```text
token-escrow/
├── foundry.toml
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── src/
│   └── TokenEscrow.sol
└── test/
    ├── TokenEscrow.t.sol
    └── mocks/
        ├── TestToken.sol
        └── FeeToken.sol
```

---

# 7.2 Setup

```bash
forge init token-escrow
cd token-escrow

forge install OpenZeppelin/openzeppelin-contracts
```

Gli import usati in questa lezione seguono OpenZeppelin Contracts 5.x:

```solidity
@openzeppelin/contracts/token/ERC20/IERC20.sol
@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol
```

Se il progetto usa il layout standard della dependency installata da Foundry, puoi aggiungere una remapping nel `foundry.toml`:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]

remappings = [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/"
]
```

Verifica poi:

```bash
forge build
```

---

# 7.3 Token giocattolo standard

## `test/mocks/TestToken.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {ERC20} from
    "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor()
        ERC20("Test Token", "TEST")
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
```

È intenzionalmente permissivo:

```solidity
mint(...)
```

può essere chiamata da chiunque.

Va bene perché è esclusivamente un mock locale.

---

# 7.4 Test base

## `test/TokenEscrow.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/Test.sol";

import {TestToken} from "./mocks/TestToken.sol";
import {TokenEscrow} from "../src/TokenEscrow.sol";

contract TokenEscrowTest is Test {
    TestToken token;
    TokenEscrow escrow;

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address stranger = makeAddr("stranger");

    function setUp() public {
        token = new TestToken();

        escrow = new TokenEscrow(
            token,
            buyer,
            seller
        );

        token.mint(buyer, 1_000 ether);
    }

    function _deposit(uint256 amount) internal {
        vm.startPrank(buyer);

        token.approve(
            address(escrow),
            amount
        );

        escrow.deposit(amount);

        vm.stopPrank();
    }

    function test_DepositMovesTokens() public {
        _deposit(100 ether);

        assertEq(
            token.balanceOf(address(escrow)),
            100 ether
        );

        assertEq(
            escrow.escrowedAmount(),
            100 ether
        );

        assertEq(
            uint256(escrow.state()),
            uint256(TokenEscrow.State.Funded)
        );
    }

    function test_ReleasePaysSeller() public {
        _deposit(100 ether);

        vm.prank(buyer);
        escrow.release();

        assertEq(
            token.balanceOf(seller),
            100 ether
        );

        assertEq(
            escrow.escrowedAmount(),
            0
        );

        assertEq(
            uint256(escrow.state()),
            uint256(TokenEscrow.State.Released)
        );
    }

    function test_RefundPaysBuyer() public {
        uint256 beforeBalance =
            token.balanceOf(buyer);

        _deposit(100 ether);

        vm.prank(buyer);
        escrow.refund();

        assertEq(
            token.balanceOf(buyer),
            beforeBalance
        );

        assertEq(
            escrow.escrowedAmount(),
            0
        );
    }
}
```

Esegui:

```bash
forge test -vv
```

---

# 8. Test negativi

L'happy path non basta.

---

## 8.1 Deposito senza allowance

```solidity
function test_RevertWithoutAllowance() public {
    vm.prank(buyer);

    vm.expectRevert();

    escrow.deposit(100 ether);
}
```

Perché deve fallire?

Il buyer possiede token, ma:

```text
balance != authorization
```

Avere token non autorizza automaticamente l'Escrow a muoverli.

---

## 8.2 Allowance insufficiente

```solidity
function test_RevertWithInsufficientAllowance() public {
    vm.startPrank(buyer);

    token.approve(
        address(escrow),
        50 ether
    );

    vm.expectRevert();

    escrow.deposit(100 ether);

    vm.stopPrank();
}
```

Proprietà:

```text
allowance < requested amount
=> deposito non può riuscire
```

---

## 8.3 Chiamante non autorizzato

```solidity
function test_StrangerCannotDeposit() public {
    token.mint(stranger, 100 ether);

    vm.startPrank(stranger);

    token.approve(
        address(escrow),
        100 ether
    );

    vm.expectRevert(
        TokenEscrow.OnlyBuyer.selector
    );

    escrow.deposit(100 ether);

    vm.stopPrank();
}
```

Notare:

```text
stranger ha saldo
stranger ha approvato l'Escrow
```

ma non ha il ruolo corretto.

Questo collega la Lezione 6 alla Lezione 8:

```text
authorization ERC20
!=
authorization business logic
```

L'allowance autorizza l'Escrow nel **token**.

Il controllo `buyer` autorizza il chiamante nell'**Escrow**.

Sono due livelli diversi.

---

## 8.4 Zero amount

```solidity
function test_ZeroDepositReverts() public {
    vm.prank(buyer);

    vm.expectRevert(
        TokenEscrow.ZeroAmount.selector
    );

    escrow.deposit(0);
}
```

Questa scelta è di design.

ERC-20 permette normalmente trasferimenti zero, ma alcune integrazioni/token possono comportarsi diversamente.

Definire esplicitamente:

```text
deposit(0) non ha significato
```

riduce ambiguità.

---

# 9. Vulnerabilità 1 — return value ignorato

Costruiamo un contratto vulnerabile minimo.

## `src/VulnerableTokenVault.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

interface IERC20Like {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract VulnerableTokenVault {
    IERC20Like public immutable token;

    mapping(address => uint256)
        public credit;

    constructor(IERC20Like token_) {
        token = token_;
    }

    function deposit(uint256 amount) external {
        // BUG:
        // risultato ignorato.
        token.transferFrom(
            msg.sender,
            address(this),
            amount
        );

        credit[msg.sender] += amount;
    }
}
```

---

# 9.1 Token locale che restituisce `false`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract FalseReturnToken {
    mapping(address => uint256)
        public balanceOf;

    function mint(
        address to,
        uint256 amount
    ) external {
        balanceOf[to] += amount;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure returns (bool) {
        // Simulazione locale:
        // nessun trasferimento avviene.
        return false;
    }
}
```

---

# 9.2 Riproduzione locale

```solidity
function test_VulnerableVaultCreatesFakeCredit()
    public
{
    FalseReturnToken bad =
        new FalseReturnToken();

    VulnerableTokenVault vault =
        new VulnerableTokenVault(
            IERC20Like(address(bad))
        );

    bad.mint(buyer, 100 ether);

    vm.prank(buyer);
    vault.deposit(100 ether);

    assertEq(
        bad.balanceOf(address(vault)),
        0
    );

    assertEq(
        vault.credit(buyer),
        100 ether
    );
}
```

Abbiamo:

```text
asset reali = 0
passività   = 100
```

La vulnerabilità non è:

```text
"ERC-20 è insicuro"
```

La vulnerabilità è l'assunzione:

```text
ho chiamato transferFrom()
=> quindi deve essere avvenuto
```

che non è stata verificata.

---

# 9.3 Correzione con `SafeERC20`

```solidity
using SafeERC20 for IERC20;

token.safeTransferFrom(
    msg.sender,
    address(this),
    amount
);
```

Un `false` viene trattato come fallimento.

Perciò l'accounting successivo non viene applicato.

---

# 9.4 Test di regressione

Per un contratto corretto:

```solidity
function test_FalseReturnCannotCreateCredit()
    public
{
    // deploy del token che ritorna false
    // deploy del vault corretto

    vm.prank(buyer);

    vm.expectRevert();

    vault.deposit(100 ether);

    assertEq(
        vault.credit(buyer),
        0
    );
}
```

La proprietà di regressione è:

```text
se il movimento degli asset fallisce,
l'accounting non può dichiararlo riuscito.
```

---

# 10. Vulnerabilità 2 — Fee-on-transfer e accounting nominale

Consideriamo:

```solidity
safeTransferFrom(
    user,
    address(this),
    100
);

credit[user] += 100;
```

Questa riga controlla la riuscita della chiamata, ma non dimostra ancora che siano arrivati 100 token.

---

# 10.1 Token con fee giocattolo

## `test/mocks/FeeToken.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {ERC20} from
    "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FeeToken is ERC20 {
    uint256 public constant FEE_BPS = 1000;
    // 10%

    constructor()
        ERC20("Fee Token", "FEE")
    {}

    function mint(
        address to,
        uint256 amount
    ) external {
        _mint(to, amount);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Non tassiamo mint/burn nel mock.
        if (
            from == address(0) ||
            to == address(0)
        ) {
            super._update(from, to, value);
            return;
        }

        uint256 fee =
            value * FEE_BPS / 10_000;

        uint256 received =
            value - fee;

        super._update(
            from,
            address(0xdead),
            fee
        );

        super._update(
            from,
            to,
            received
        );
    }
}
```

Questo contratto esiste soltanto per il laboratorio.

---

# 10.2 Cosa succede con un deposito di 100

```text
buyer manda nominalmente: 100
fee:                      10
Escrow riceve:            90
```

Se il protocollo scrive:

```solidity
escrowedAmount = 100;
```

diventa insolvente rispetto alla propria contabilità.

---

# 10.3 Il nostro Escrow misura il ricevuto

Ricordiamo:

```solidity
uint256 beforeBalance =
    token.balanceOf(address(this));

token.safeTransferFrom(
    buyer,
    address(this),
    requestedAmount
);

uint256 afterBalance =
    token.balanceOf(address(this));

uint256 received =
    afterBalance - beforeBalance;

escrowedAmount = received;
```

Quindi:

```text
requestedAmount = 100
received        = 90
escrowedAmount  = 90
```

---

# 10.4 Test

```solidity
function test_FeeTokenAccountsActualReceived()
    public
{
    FeeToken feeToken =
        new FeeToken();

    TokenEscrow feeEscrow =
        new TokenEscrow(
            feeToken,
            buyer,
            seller
        );

    feeToken.mint(
        buyer,
        100 ether
    );

    vm.startPrank(buyer);

    feeToken.approve(
        address(feeEscrow),
        100 ether
    );

    feeEscrow.deposit(
        100 ether
    );

    vm.stopPrank();

    assertEq(
        feeToken.balanceOf(
            address(feeEscrow)
        ),
        90 ether
    );

    assertEq(
        feeEscrow.escrowedAmount(),
        90 ether
    );
}
```

---

# 10.5 Ma attenzione al payout

Con un fee-on-transfer token, anche:

```solidity
token.safeTransfer(seller, 90 ether);
```

può far ricevere al seller meno di 90.

Quindi dobbiamo definire semanticamente il requisito.

Possibili policy:

```text
A. Il seller riceve ciò che il token trasferisce dopo le proprie fee.

B. Il protocollo garantisce un importo netto preciso.

C. I fee-on-transfer token non sono supportati.
```

Sono tre design diversi.

Non esiste una correzione universale senza conoscere il requisito.

Questa è una lezione fondamentale di smart contract security:

> **la sicurezza non nasce dal pattern di codice; nasce da requisiti precisi che il codice deve mantenere.**

---

# 11. `approve` non appartiene normalmente al deposito dell'Escrow

Flusso tipico:

```text
1. buyer -> token.approve(escrow, amount)

2. buyer -> escrow.deposit(amount)

3. escrow -> token.transferFrom(
       buyer,
       escrow,
       amount
   )
```

Notare i caller:

```text
approve:
    msg.sender nel Token = buyer

deposit:
    msg.sender nell'Escrow = buyer

transferFrom:
    msg.sender nel Token = escrow
```

Diagramma:

```text
         approve
Buyer  -----------> Token
                      |
                      | allowance[Buyer][Escrow]
                      v

         deposit
Buyer  -----------> Escrow
                      |
                      | transferFrom
                      v
                    Token
```

Comprendere esattamente chi è `msg.sender` in ogni hop è essenziale per l'audit.

---

# 12. Allowance e trust boundary

Consideriamo questa situazione:

```text
Token
  ^
  |
Escrow
```

L'Escrow è contemporaneamente:

1. un **caller** del token;
2. uno **spender autorizzato** dal buyer.

Sono due trust boundary distinti.

Dal punto di vista del buyer:

```text
"mi fido che questo Escrow usi la sua allowance correttamente"
```

Dal punto di vista dell'Escrow:

```text
"mi fido che questo token abbia il comportamento supportato"
```

Diagramma:

```text
BUYER
  |
  | trust: spender authorization
  v
ESCROW
  |
  | trust: token semantics
  v
TOKEN
```

La composability crea sicurezza bidirezionale.

---

# 13. Un errore concettuale frequente: controllare solo l'allowance

Codice del tipo:

```solidity
require(
    token.allowance(
        msg.sender,
        address(this)
    ) >= amount,
    "allowance"
);

token.safeTransferFrom(
    msg.sender,
    address(this),
    amount
);
```

spesso aggiunge poco.

Perché?

`transferFrom` deve comunque verificare l'allowance nel token.

Il controllo preliminare:

```solidity
allowance(...)
```

non rende atomicamente vero che la successiva operazione riuscirà.

Tra requisiti più importanti ci sono:

- risultato effettivo della call;
- accounting;
- compatibilità del token;
- stato del protocollo.

Regola generale:

> non confondere un controllo preliminare con una garanzia sul risultato della chiamata esterna.

---

# 14. Token configurabile dall'utente: superficie enorme

Questo pattern merita attenzione:

```solidity
function deposit(
    address token,
    uint256 amount
) external {
    IERC20(token).safeTransferFrom(
        msg.sender,
        address(this),
        amount
    );
}
```

Qui il chiamante controlla:

```text
token
```

cioè l'indirizzo del codice esterno che il protocollo invocherà.

Dal punto di vista di security review:

```text
input utente
   |
   v
indirizzo chiamato esternamente
```

è una superficie molto più sensibile di:

```text
uint256 amount
```

Il "token" non è solo un asset identifier.

È anche:

```text
un indirizzo di codice.
```

Una policy comune nei protocolli è quindi mantenere asset supportati esplicitamente, anziché accettare qualunque indirizzo.

---

# 15. Invariant testing: prima formulazione

Non faremo ancora un corso completo sugli invariant test — arriverà più avanti — ma iniziamo a pensare nel modo giusto.

Per un Escrow con singola posizione:

```text
INV-1:
se state == Funded,
token.balanceOf(escrow) >= escrowedAmount
```

Possiamo già tradurla come assertion.

```solidity
function assertEscrowSolvent() internal view {
    if (
        escrow.state()
            == TokenEscrow.State.Funded
    ) {
        assertGe(
            token.balanceOf(
                address(escrow)
            ),
            escrow.escrowedAmount()
        );
    }
}
```

Nei test:

```solidity
_deposit(100 ether);

assertEscrowSolvent();
```

Più avanti Foundry chiamerà automaticamente sequenze di operazioni e verificherà invarianti dopo ogni sequenza.

Per ora voglio che il principio sia chiaro:

```text
test unitario:
    "questa specifica operazione produce X"

invariante:
    "questa proprietà non deve mai diventare falsa"
```

---

# 16. Mutation exercise

Partiamo dal codice sicuro:

```solidity
escrowedAmount = received;
```

Modificalo temporaneamente in:

```solidity
escrowedAmount = requestedAmount;
```

Poi esegui il test con `FeeToken`.

Il test:

```solidity
assertEq(
    feeEscrow.escrowedAmount(),
    90 ether
);
```

deve fallire.

Questo è un esercizio molto utile:

> un buon test deve morire quando introduci volontariamente il bug che dovrebbe intercettare.

Se il test continua a passare dopo la mutation, probabilmente non sta realmente verificando la proprietà desiderata.

---

# 17. Test aggiuntivi da scrivere

Non ti do subito tutte le soluzioni.

## Esercizio A — doppio deposito

Verifica:

```text
deposit
deposit di nuovo
```

Il secondo deve fallire.

---

## Esercizio B — release senza funding

Chiama:

```text
release()
```

nello stato `Created`.

Deve fallire.

---

## Esercizio C — doppia release

Sequenza:

```text
deposit
release
release
```

La seconda release deve fallire.

---

## Esercizio D — refund dopo release

Sequenza:

```text
deposit
release
refund
```

Deve fallire.

---

## Esercizio E — allowance esatta

Imposta:

```text
allowance = 100
deposit   = 100
```

Dopo il deposito verifica la allowance residua del token standard.

---

## Esercizio F — allowance maggiore

```text
approve = 1000
deposit = 100
```

Verifica cosa resta.

Poi rispondi:

> quale rischio rimane per il buyer dopo il deposito se l'allowance è ancora elevata?

---

# 18. Mini threat model dell'Escrow ERC-20

## Asset

```text
token custoditi dall'Escrow
```

## Attori

```text
buyer
seller
token contract
eventuale amministratore futuro
```

## Trust assumptions

```text
buyer:
  deve autorizzare lo spender corretto

Escrow:
  assume una certa semantica del token

seller:
  assume che la release corrisponda
  alla promessa economica
```

## Entry point

```text
deposit
release
refund
```

## External dependency

```text
token
```

## Failure modes

```text
- allowance assente
- saldo insufficiente
- token restituisce false
- token reverte
- token applica fee
- token modifica il proprio comportamento
- token ha decimals inattesi
- token è paused/blacklisted
- accounting usa amount invece del ricevuto
- stato viene aggiornato nel momento sbagliato
```

---

# 19. Audit manuale: lettura per trust boundary

Quando trovi:

```solidity
IERC20(token).transferFrom(...)
```

non limitarti a leggere la funzione.

Annota:

```text
EXTERNAL CALL #1

Target:
    token

Chi controlla target?
    immutable?
    admin?
    utente?
    governance?

Input:
    from
    to
    amount

Return:
    controllato?
    ignorato?

State:
    scritto prima?
    scritto dopo?

Accounting:
    nominale?
    balance delta?

Token assumptions:
    standard?
    fee?
    rebase?
    pause?
    blacklist?
```

Questo piccolo schema è estremamente riutilizzabile.

---

# 20. Checklist da auditor

Quando leggi un'integrazione ERC-20, chiediti:

1. **Quali token sono supportati?** Uno fisso, una allowlist o qualsiasi address?

2. **Chi controlla l'indirizzo del token?** Utente, admin, governance, constructor?

3. Le operazioni usano `SafeERC20` o gestiscono correttamente il return value?

4. Il protocollo assume che:

   ```text
   requested == received
   ```

   senza verificarlo?

5. I fee-on-transfer token sono:
   - supportati;
   - rifiutati;
   - accidentalmente supportati?

6. I rebasing token sono compatibili con l'accounting?

7. `decimals()` viene usato? Se sì, con quali assunzioni?

8. Ci sono allowance persistenti o illimitate?

9. Chi è:
   - owner dell'allowance;
   - spender;
   - recipient?

10. Gli effetti interni avvengono prima delle external calls quando opportuno?

11. Se la chiamata token fallisce, tutto lo stato importante viene revertito?

12. Esiste una proprietà di solvibilità del tipo:

```text
asset reali >= liabilities
```

13. Sono testati token anomali, non soltanto un mock ERC-20 perfetto?

14. Sono testati:
   - zero;
   - allowance insufficiente;
   - saldo insufficiente;
   - `false`;
   - revert;
   - fee?

15. Il codice confonde "token conforme all'interfaccia" con "token economicamente compatibile"?

---

# 21. Approfondimento: allowance e `permit`

Esiste una estensione molto usata, ERC-2612, che introduce:

```text
permit
```

Con `permit`, il proprietario può autorizzare una allowance tramite una firma off-chain basata su typed data, anziché eseguire necessariamente prima una transazione `approve`.

Concettualmente:

```text
approve:
    authorization via transaction

permit:
    authorization via signature + nonce + deadline
```

Questo aggiunge nuove superfici:

```text
signature verification
nonce
deadline
domain separator
chain id
replay protection
```

Non lo implementiamo oggi.

Quando arriveremo a firme e autorizzazioni avanzate, lo analizzeremo come un problema di autenticazione crittografica e replay protection.

Per ora basta ricordare:

> cambiare il meccanismo con cui viene concessa l'allowance non elimina la necessità di ragionare su chi può spendere quanto e per quanto tempo.

---

# 22. Prima/dopo

## Versione fragile

```solidity
function deposit(uint256 amount) external {
    token.transferFrom(
        msg.sender,
        address(this),
        amount
    );

    credit[msg.sender] += amount;
}
```

Assunzioni implicite:

```text
- return value irrilevante
- token conforme
- amount == received
- qualunque comportamento del token è accettabile
```

---

## Versione migliore

```solidity
function deposit(
    uint256 requestedAmount
) external {
    if (requestedAmount == 0) {
        revert ZeroAmount();
    }

    uint256 beforeBalance =
        token.balanceOf(address(this));

    token.safeTransferFrom(
        msg.sender,
        address(this),
        requestedAmount
    );

    uint256 afterBalance =
        token.balanceOf(address(this));

    uint256 received =
        afterBalance - beforeBalance;

    if (received == 0) {
        revert NothingReceived();
    }

    credit[msg.sender] += received;
}
```

Ma ancora:

```text
"migliore"
!=
"universalmente sicuro per ogni token esistente"
```

Serve una specification degli asset supportati.

---

# 23. Esercizi progressivi

## Esercizio 1 — Disegna l'allowance

Senza codice, disegna lo stato di:

```text
buyer balance
escrow balance
allowance[buyer][escrow]
```

nei tre momenti:

```text
prima di approve
dopo approve
dopo transferFrom
```

---

## Esercizio 2 — Analisi funzione

Per `deposit()` compila una tabella con:

```text
caller
input
storage reads
storage writes
external calls
assumptions
failure modes
```

---

## Esercizio 3 — Test allowance insufficiente

Scrivi il test Foundry.

Non usare `expectRevert()` generico se riesci a determinare con precisione l'errore restituito dalla versione di OpenZeppelin utilizzata.

---

## Esercizio 4 — Test saldo insufficiente

Concedi allowance sufficiente:

```text
allowance = 100
```

ma dai al buyer soltanto:

```text
balance = 50
```

Tenta:

```text
deposit(100)
```

e verifica che nessuno stato dell'Escrow venga modificato.

---

## Esercizio 5 — Mutation fee

Sostituisci:

```solidity
escrowedAmount = received;
```

con:

```solidity
escrowedAmount = requestedAmount;
```

Dimostra che il test con `FeeToken` rileva il bug.

---

## Esercizio 6 — Token support policy

Scrivi in linguaggio naturale una policy del tipo:

```text
Questo Escrow supporta soltanto...
```

Definisci esplicitamente:

- fee-on-transfer sì/no;
- rebasing sì/no;
- token upgradeabili sì/no;
- zero transfer sì/no.

Poi identifica quali test servono per dimostrarla.

---

## Esercizio 7 — Solvibilità

Implementa un helper test:

```solidity
_assertSolvent()
```

che verifichi:

```text
state == Funded
=> balance >= escrowedAmount
```

Chiamalo dopo ogni operazione nei test.

---

## Esercizio 8 — Challenge da auditor

Trova almeno **cinque assunzioni** implicite in questo codice:

```solidity
function pay(
    IERC20 token,
    uint256 amount
) external {
    token.transferFrom(
        msg.sender,
        address(this),
        amount
    );

    balances[msg.sender] += amount;
}
```

Non correggerlo subito.

Prima elenca le assunzioni.

Questa disciplina è fondamentale in audit:

```text
prima comprendere,
poi formulare la proprietà,
poi dimostrare il bug,
poi correggere.
```

---

# 24. Cosa devi ricordare

Se devi conservare soltanto pochi concetti, conserva questi.

### 1. Un ERC-20 è un altro smart contract

Interagire con un token significa fare una external call.

---

### 2. `approve` non trasferisce token

Crea una autorizzazione persistente:

```text
owner -> spender -> amount
```

---

### 3. `transferFrom` usa quella autorizzazione

Nel token:

```text
msg.sender = spender
```

non necessariamente il proprietario dei token.

---

### 4. Non ignorare il risultato delle operazioni token

Usa primitive robuste come `SafeERC20` quando appropriato.

---

### 5. `safeTransferFrom` non significa automaticamente "ho ricevuto esattamente amount"

La semantica economica del token può essere diversa.

---

### 6. Accounting nominale e asset reali devono essere riconciliati

La proprietà cruciale è spesso:

```text
assets >= liabilities
```

non:

```text
la chiamata non ha revertito
```

---

### 7. La compatibilità con un token è una scelta di protocollo

Devi definire esplicitamente quali proprietà degli asset esterni assumi.

---

### 8. In auditing, l'indirizzo token è anche un indirizzo di codice

Se è controllabile dall'utente, la superficie di rischio cresce drasticamente.

---

# 25. Collegamento con le lezioni precedenti

Questa lezione ricompone diversi concetti già studiati.

```text
Lezione 1
msg.sender + external execution
        |
        v

Lezione 3/7
state machine
        |
        v

Lezione 4
external calls + CEI
        |
        v

Lezione 5
reentrancy mindset
        |
        v

Lezione 6
authorization
        |
        v

Lezione 8
ERC20 integration
```

La sicurezza non è una collezione di bug indipendenti.

È il risultato della composizione di:

```text
stato
+
autorizzazioni
+
external calls
+
accounting
+
assunzioni sulle dipendenze
```

---

# 26. Fonti della lezione

Le fonti tecniche principali consultate per questa lezione sono:

1. **EIP-20 — Token Standard**  
   Specifica ufficiale ERC-20. In particolare: `transfer`, `approve`, `allowance`, `transferFrom`, gestione del valore booleano di ritorno e nota sul cambio delle allowance.

2. **OpenZeppelin Contracts 5.x — ERC20 / IERC20**  
   Documentazione corrente per l'interfaccia e l'implementazione ERC-20.

3. **OpenZeppelin Contracts 5.x — SafeERC20**  
   Documentazione della utility per interazioni robuste con token che restituiscono `false` o non restituiscono dati.

4. **OWASP Smart Contract Security — Token Implementations / SCSVS**  
   Indicazioni di testing e review su token non standard, amount zero e compatibilità delle integrazioni.

5. **OWASP SCWE-103 — ERC20 Approval Double-Spend / Allowance Race**  
   Riferimento sul noto problema nel modificare allowance non-zero e sulle mitigazioni lato client/protocol design.

6. **OWASP SC06:2026 — Unchecked External Calls**  
   Riferimento sul rischio di assumere il successo o il comportamento di chiamate verso contratti esterni, incluse integrazioni token.

Documentazione verificata il **21 settembre 2026**.

---

## Fine Lezione 8

La prossima lezione non è inclusa qui, come richiesto.

Quando vorrai continuare, la progressione naturale sarà:

**Lezione 9 — Oracoli, prezzi, decimals, slippage e MEV come rischio progettuale.**
