# Lezione 17 — Progetto Finale: Audit dell’Escrow Evoluto

> **Scopo:** applicare l’intero corso in una mini security review end-to-end.
>
> Tutto il laboratorio è confinato a **Foundry/Anvil locale**, account di test, token/oracoli/router giocattolo e fondi fittizi.
>
> Non useremo protocolli reali, fork pubblici o target di terzi.

> **Laboratorio eseguibile:** [`lessons/17-progetto-finale-audit-escrow-evoluto/`](../lessons/17-progetto-finale-audit-escrow-evoluto/README.md).
> Gli snippet in questa lezione illustrano il metodo; i file Solidity mantenuti, compilabili e
> coperti dai test sono nel laboratorio. In particolare, il laboratorio usa interfacce e mock locali
> al posto degli import OpenZeppelin mostrati negli esempi.

---

# 1. Obiettivi

Alla fine di questa lezione dovresti saper:

- definire uno scope di audit;
- ricostruire l’architettura di un protocollo;
- identificare asset, attori e trust boundary;
- formulare invarianti prima di cercare bug;
- inventariare entry point e privilegi;
- fare una review manuale;
- usare Slither come supporto;
- riprodurre localmente finding reali;
- distinguere root cause, impact e preconditions;
- correggere i problemi;
- aggiungere regression test;
- fare retest;
- scrivere un mini report finale.

Questa è la sintesi pratica delle Lezioni 1–16.

---

# 2. Scope del progetto finale

## Repository locale

La struttura semplificata usata negli esempi è:

```text
escrow-final/
├── foundry.toml
├── src/
│   ├── EscrowFinal.sol
│   ├── interfaces/
│   │   ├── IPriceOracle.sol
│   │   └── INotifier.sol
│   └── mocks/
│       ├── TestToken.sol
│       ├── FeeToken.sol
│       ├── MockOracle.sol
│       └── RevertingNotifier.sol
└── test/
```

## In scope

```text
src/EscrowFinal.sol
```

## Support components

```text
Interfacce e libreria ERC-20 locali (gli esempi teorici citano OpenZeppelin Contracts 5.x)
Foundry
toy mocks
```

## Assumptions dichiarate dal protocollo

Il protocollo dichiara:

```text
- buyer e seller sono ruoli fissi;
- owner è governance;
- il token è un ERC-20;
- il protocollo supporta token standard;
- l’oracle restituisce un prezzo USD;
- l’oracle deve essere fresco;
- il notifier è opzionale;
- il protocollo può essere pausato;
- release e refund sono terminali.
```

La nostra review verificherà se il codice rispetta davvero queste promesse.

---

# 3. Architettura

```text
Buyer
  |
  | approve + deposit
  v
+------------------------+
| EscrowFinal            |
|                        |
| state machine          |
| accounting             |
| privileged config      |
+-----+----------+-------+
      |          |
      |          +------> Notifier
      |
      +-----------------> ERC20 token
      |
      +-----------------> Oracle

Governance / Owner
      |
      +-----------------> setOracle
      +-----------------> setFee
      +-----------------> unpause

Emergency Pauser
      |
      +-----------------> pause
```

Asset principali:

```text
ERC-20 custoditi
diritto del seller al payout
diritto del buyer al refund
oracle authority
owner authority
pause authority
```

---

# 4. Il contratto deliberatamente imperfetto

## `src/EscrowFinal.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    IERC20
} from
    "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceOracle {
    function latestPrice()
        external
        view
        returns (
            int256 answer,
            uint256 updatedAt
        );
}

interface INotifier {
    function notifyReleased(
        address seller,
        uint256 amount
    ) external;
}

contract EscrowFinal {
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    IERC20 public immutable token;

    address public immutable buyer;
    address public immutable seller;

    address public owner;
    address public emergencyPauser;

    IPriceOracle public oracle;
    INotifier public notifier;

    State public state;

    uint256 public escrowedAmount;
    uint256 public feeBps;

    bool public paused;

    uint256 public constant MAX_ORACLE_AGE =
        1 hours;

    error OnlyBuyer();
    error OnlyOwner();
    error OnlyPauser();
    error InvalidState();
    error ZeroAmount();
    error Paused();
    error InvalidPrice();
    error FeeTooHigh();

    event Deposited(
        uint256 requestedAmount,
        uint256 creditedAmount
    );

    event Released(
        uint256 grossAmount,
        uint256 fee
    );

    event Refunded(
        uint256 amount
    );

    constructor(
        IERC20 token_,
        address buyer_,
        address seller_,
        address owner_,
        address emergencyPauser_,
        IPriceOracle oracle_,
        INotifier notifier_
    ) {
        token = token_;
        buyer = buyer_;
        seller = seller_;
        owner = owner_;
        emergencyPauser =
            emergencyPauser_;
        oracle = oracle_;
        notifier = notifier_;

        state = State.Created;
    }

    function deposit(
        uint256 amount
    ) external {
        if (paused) {
            revert Paused();
        }

        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (state != State.Created) {
            revert InvalidState();
        }

        if (amount == 0) {
            revert ZeroAmount();
        }

        // FINDING CANDIDATE #1:
        // return value ignored and nominal
        // amount is credited.
        token.transferFrom(
            buyer,
            address(this),
            amount
        );

        escrowedAmount = amount;
        state = State.Funded;

        emit Deposited(
            amount,
            amount
        );
    }

    function release()
        external
    {
        if (paused) {
            revert Paused();
        }

        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (state != State.Funded) {
            revert InvalidState();
        }

        (
            int256 price,
            uint256 updatedAt
        ) = oracle.latestPrice();

        // FINDING CANDIDATE #2:
        // checks sign only, ignores staleness.
        if (price <= 0) {
            revert InvalidPrice();
        }

        // Silence warning in toy code:
        updatedAt;

        uint256 gross =
            escrowedAmount;

        uint256 fee =
            gross * feeBps / 10_000;

        uint256 payout =
            gross - fee;

        escrowedAmount = 0;
        state = State.Released;

        // FINDING CANDIDATE #3:
        // IERC20 return value ignored.
        token.transfer(
            seller,
            payout
        );

        // Optional notifier:
        // FINDING CANDIDATE #4:
        // low-level call result ignored.
        address(notifier).call(
            abi.encodeCall(
                INotifier.notifyReleased,
                (
                    seller,
                    payout
                )
            )
        );

        emit Released(
            gross,
            fee
        );
    }

    function refund()
        external
    {
        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (state != State.Funded) {
            revert InvalidState();
        }

        uint256 amount =
            escrowedAmount;

        escrowedAmount = 0;
        state = State.Refunded;

        token.transfer(
            buyer,
            amount
        );

        emit Refunded(
            amount
        );
    }

    function setFee(
        uint256 newFeeBps
    ) external {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }

        if (newFeeBps > 1_000) {
            revert FeeTooHigh();
        }

        feeBps = newFeeBps;
    }

    function setOracle(
        IPriceOracle newOracle
    ) external {
        // FINDING CANDIDATE #5:
        // missing owner authorization.
        oracle = newOracle;
    }

    function pause()
        external
    {
        if (
            msg.sender
                != emergencyPauser
        ) {
            revert OnlyPauser();
        }

        paused = true;
    }

    function unpause()
        external
    {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }

        paused = false;
    }
}
```

Questo contratto è volutamente imperfetto.

Non correggerlo subito.

Prima facciamo l’audit.

---

# 5. Invarianti del protocollo

Scriviamo prima le proprietà.

## I-01 — Buyer-only funding

```text
caller != buyer
=> deposit revert
```

## I-02 — Single settlement

```text
Funded
=> può terminare una volta sola
in Released XOR Refunded
```

## I-03 — Terminality

```text
Released/Refunded
=> nessun ritorno a Created/Funded
```

## I-04 — Solvibilità

```text
state == Funded
=> token balance of escrow
   >= escrowedAmount
```

## I-05 — Accounting reale

```text
escrowedAmount
deve riflettere asset effettivamente ricevuti
```

## I-06 — Release price validity

```text
release price:
positive
fresh
from configured oracle
```

## I-07 — Privileged oracle configuration

```text
solo governance autorizzata
può cambiare oracle
```

## I-08 — Failed token transfer must not look successful

```text
token movement fails
=> terminal state must not persist
```

## I-09 — Optional notifier

```text
notifier failure
!= settlement failure
```

Questa è una policy dichiarata.

## I-10 — Fee bounds

```text
feeBps <= 1000
```

## I-11 — Pause authority

```text
solo emergencyPauser può pause
```

## I-12 — Unpause authority

```text
solo owner può unpause
```

---

# 6. Entry-point review

| Function | Caller | Critical Writes | External Calls |
|---|---|---|---|
| `deposit` | buyer | `escrowedAmount`, `state` | token |
| `release` | buyer | `state`, liability | oracle, token, notifier |
| `refund` | buyer | `state`, liability | token |
| `setFee` | owner | `feeBps` | none |
| `setOracle` | **anyone** | `oracle` | none |
| `pause` | pauser | `paused` | none |
| `unpause` | owner | `paused` | none |

La tabella evidenzia subito un’anomalia:

```text
setOracle:
caller = anyone
```

---

# 7. Finding F-01 — Accounting nominale ERC-20

## Observation

`deposit()` esegue:

```solidity
token.transferFrom(
    buyer,
    address(this),
    amount
);

escrowedAmount = amount;
```

## Root cause

Il contratto assume:

```text
requested amount
==
received amount
```

e ignora il boolean return.

OpenZeppelin raccomanda `SafeERC20` proprio per gestire token che ritornano `false` o non ritornano dati; ma anche `SafeERC20` non dimostra che sia stato ricevuto esattamente l’importo nominale.

## Property violata

```text
escrowedAmount
<=
actual token balance backing
```

---

# 8. PoC locale F-01 con fee-on-transfer token

## `src/mocks/FeeToken.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    ERC20
} from
    "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FeeToken is ERC20 {
    uint256 public constant FEE_BPS =
        1000; // 10%

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
        uint256 amount
    ) internal override {
        if (
            from == address(0) ||
            to == address(0)
        ) {
            super._update(
                from,
                to,
                amount
            );
            return;
        }

        uint256 fee =
            amount * FEE_BPS / 10_000;

        super._update(
            from,
            address(0xdead),
            fee
        );

        super._update(
            from,
            to,
            amount - fee
        );
    }
}
```

---

# 9. Regression test che deve inizialmente fallire

```solidity
function test_F01_DepositMustUseActualReceived()
    public
{
    FeeToken feeToken =
        new FeeToken();

    MockOracle oracle =
        new MockOracle();

    EscrowFinal escrow =
        _deployWithToken(
            IERC20(address(feeToken)),
            oracle
        );

    feeToken.mint(
        buyer,
        100 ether
    );

    vm.startPrank(buyer);

    feeToken.approve(
        address(escrow),
        100 ether
    );

    escrow.deposit(
        100 ether
    );

    vm.stopPrank();

    assertEq(
        feeToken.balanceOf(
            address(escrow)
        ),
        90 ether
    );

    // Questa assertion fallisce sul codice vulnerabile:
    assertEq(
        escrow.escrowedAmount(),
        90 ether
    );
}
```

Sul contratto originale:

```text
actual balance = 90
liability      = 100
```

Insolvenza contabile.

---

# 10. Remediation F-01

Usiamo:

```solidity
SafeERC20
```

e balance delta.

```solidity
using SafeERC20 for IERC20;

uint256 beforeBalance =
    token.balanceOf(
        address(this)
    );

token.safeTransferFrom(
    buyer,
    address(this),
    amount
);

uint256 afterBalance =
    token.balanceOf(
        address(this)
    );

uint256 received =
    afterBalance - beforeBalance;

if (received == 0) {
    revert ZeroAmount();
}

escrowedAmount =
    received;
```

Ora:

```text
credit = actual received
```

per la classe di token compatibile con questo modello.

---

# 11. Finding F-02 — Oracle stale accettato

## Observation

`release()` verifica:

```solidity
if (price <= 0) {
    revert InvalidPrice();
}
```

ma ignora:

```solidity
updatedAt
```

## Root cause

Il protocollo controlla:

```text
syntactic validity
```

ma non:

```text
freshness
```

## Property violata

```text
release price age <= MAX_ORACLE_AGE
```

---

# 12. Mock oracle

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract MockOracle {
    int256 public answer;
    uint256 public updatedAt;

    function setPrice(
        int256 answer_,
        uint256 updatedAt_
    ) external {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestPrice()
        external
        view
        returns (
            int256,
            uint256
        )
    {
        return (
            answer,
            updatedAt
        );
    }
}
```

---

# 13. PoC locale F-02

```solidity
function test_F02_StalePriceMustBlockRelease()
    public
{
    _fundEscrow(100 ether);

    vm.warp(
        1_000_000
    );

    oracle.setPrice(
        3000e8,
        block.timestamp
            - 2 hours
    );

    vm.prank(buyer);

    vm.expectRevert(
        EscrowFinal
            .StalePrice
            .selector
    );

    escrow.release();
}
```

Sul codice vulnerabile questo test non può ancora compilare se `StalePrice` non esiste; questa è un’indicazione naturale della remediation da introdurre.

---

# 14. Remediation F-02

Aggiungiamo:

```solidity
error InvalidTimestamp();
error StalePrice();
```

poi:

```solidity
if (price <= 0) {
    revert InvalidPrice();
}

if (
    updatedAt == 0 ||
    updatedAt > block.timestamp
) {
    revert InvalidTimestamp();
}

if (
    block.timestamp
        - updatedAt
        > MAX_ORACLE_AGE
) {
    revert StalePrice();
}
```

Boundary test:

```text
age == MAX_ORACLE_AGE
=> accepted

age == MAX_ORACLE_AGE + 1
=> revert
```

---

# 15. Finding F-03 — Token payout return ignorato

## Observation

`release()`:

```solidity
token.transfer(
    seller,
    payout
);
```

Il boolean return viene ignorato.

## Root cause

Il contratto assume:

```text
call did not revert
=>
transfer succeeded
```

ma l’interfaccia ERC-20 può restituire `false`.

OpenZeppelin `SafeERC20` gestisce questo caso.

## Property violata

```text
state == Released
=> payout transfer succeeded
```

---

# 16. False-return token giocattolo

```solidity
contract FalseReturnToken {
    mapping(address => uint256)
        public balanceOf;

    mapping(
        address =>
        mapping(address => uint256)
    )
        public allowance;

    function approve(
        address spender,
        uint256 amount
    ) external returns (bool) {
        allowance[msg.sender][spender] =
            amount;

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        if (
            allowance[from][msg.sender]
                < amount
        ) {
            return false;
        }

        if (
            balanceOf[from]
                < amount
        ) {
            return false;
        }

        allowance[from][msg.sender] -=
            amount;

        balanceOf[from] -=
            amount;

        balanceOf[to] +=
            amount;

        return true;
    }

    function transfer(
        address,
        uint256
    ) external pure returns (bool) {
        // Deliberatamente:
        // nessun movimento.
        return false;
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        balanceOf[to] +=
            amount;
    }
}
```

---

# 17. PoC F-03

Dopo funding valido:

```text
state = Funded
```

poi:

```solidity
vm.prank(buyer);

escrow.release();
```

Nel codice vulnerabile:

```text
token.transfer(...) -> false

ma:

state = Released
escrowedAmount = 0
```

Possibile risultato:

```text
seller unpaid
state terminal
```

La state machine racconta un successo falso.

---

# 18. Remediation F-03

Usare:

```solidity
token.safeTransfer(
    seller,
    payout
);
```

con CEI:

```solidity
escrowedAmount = 0;
state = State.Released;

token.safeTransfer(
    seller,
    payout
);
```

Se `safeTransfer` reverte:

```text
entire tx reverts
```

quindi:

```text
state torna Funded
escrowedAmount torna al valore precedente
```

Atomicità preservata.

---

# 19. Finding F-04 — `setOracle` senza authorization

## Observation

```solidity
function setOracle(
    IPriceOracle newOracle
) external {
    oracle = newOracle;
}
```

Chiunque può chiamarla.

## Root cause

Manca completamente il controllo:

```text
msg.sender == owner/governance
```

## Property violata

```text
only governance may change
a critical pricing dependency
```

## Impact

Un caller non privilegiato può sostituire la sorgente di prezzo.

Questo rompe direttamente il threat model.

---

# 20. PoC locale F-04

```solidity
function test_F04_StrangerCannotReplaceOracle()
    public
{
    MockOracle attackerOracle =
        new MockOracle();

    vm.prank(stranger);

    vm.expectRevert(
        EscrowFinal
            .OnlyOwner
            .selector
    );

    escrow.setOracle(
        attackerOracle
    );
}
```

Sul codice vulnerabile la call riesce.

---

# 21. Remediation F-04

```solidity
function setOracle(
    IPriceOracle newOracle
) external {
    if (msg.sender != owner) {
        revert OnlyOwner();
    }

    if (
        address(newOracle)
            == address(0)
    ) {
        revert ZeroAddress();
    }

    oracle = newOracle;
}
```

In un sistema reale:

```text
owner = Timelock
```

se la policy richiede ritardo di governance.

---

# 22. Finding F-05 — Notifier low-level call ignorata

## Observation

```solidity
address(notifier).call(
    abi.encodeCall(...)
);
```

Slither può segnalare un unchecked low-level call.

Ma qui dobbiamo fare **triage**.

## Specification

Il protocollo dichiara:

```text
notifier è opzionale
```

Quindi:

```text
notification failure
non deve impedire settlement
```

Ignorare completamente il risultato è però poco osservabile.

---

# 23. F-05 è una vulnerabilità critica?

Non necessariamente.

Se il notifier è davvero best-effort, il corretto comportamento può essere:

```text
release succeeds
notification failure logged
```

Quindi il problema è soprattutto:

```text
silent failure / observability
```

non:

```text
fund loss
```

Questo è un ottimo esempio di finding statico che richiede contesto.

---

# 24. Remediation F-05

Meglio:

```solidity
event NotificationFailed(
    bytes reason
);
```

e:

```solidity
try notifier.notifyReleased(
    seller,
    payout
) {
}
catch (
    bytes memory reason
) {
    emit NotificationFailed(
        reason
    );
}
```

Ora la policy è esplicita:

```text
best effort
+
observable
```

---

# 25. Slither pass

Sul codice vulnerabile:

```bash
slither .
```

Poi:

```bash
slither . \
  --print entry-points

slither . \
  --print vars-and-auth

slither . \
  --print call-graph
```

Cerchiamo almeno:

```text
unchecked low-level call
unprotected state write
external call ordering
authorization anomalies
```

Ricorda:

```text
Slither finding
!=
confirmed audit issue
```

---

# 26. Triage worksheet

Per F-04:

```text
Detector / Observation:
critical state write without auth

Location:
setOracle

Reachable:
yes

Caller:
any address

State:
oracle

Asset impact:
price-sensitive release path

Invariant:
oracle changes only by governance

Status:
confirmed

PoC:
stranger setOracle succeeds

Fix:
OnlyOwner + zero-address check

Regression:
test_F04_StrangerCannotReplaceOracle
```

Questo è il formato da auditor.

---

# 27. Versione corretta — `EscrowFinalFixed.sol`

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

interface IPriceOracleFixed {
    function latestPrice()
        external
        view
        returns (
            int256 answer,
            uint256 updatedAt
        );
}

interface INotifierFixed {
    function notifyReleased(
        address seller,
        uint256 amount
    ) external;
}

contract EscrowFinalFixed {
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

    address public owner;
    address public emergencyPauser;

    IPriceOracleFixed public oracle;
    INotifierFixed public notifier;

    State public state;

    uint256 public escrowedAmount;
    uint256 public feeBps;

    bool public paused;

    uint256 public constant MAX_ORACLE_AGE =
        1 hours;

    error OnlyBuyer();
    error OnlyOwner();
    error OnlyPauser();
    error InvalidState();
    error ZeroAmount();
    error ZeroAddress();
    error Paused();
    error InvalidPrice();
    error InvalidTimestamp();
    error StalePrice();
    error FeeTooHigh();

    event Deposited(
        uint256 requestedAmount,
        uint256 receivedAmount
    );

    event Released(
        uint256 grossAmount,
        uint256 fee
    );

    event Refunded(
        uint256 amount
    );

    event NotificationFailed(
        bytes reason
    );

    constructor(
        IERC20 token_,
        address buyer_,
        address seller_,
        address owner_,
        address emergencyPauser_,
        IPriceOracleFixed oracle_,
        INotifierFixed notifier_
    ) {
        if (
            address(token_)
                == address(0) ||
            buyer_
                == address(0) ||
            seller_
                == address(0) ||
            owner_
                == address(0) ||
            emergencyPauser_
                == address(0) ||
            address(oracle_)
                == address(0)
        ) {
            revert ZeroAddress();
        }

        token = token_;
        buyer = buyer_;
        seller = seller_;
        owner = owner_;
        emergencyPauser =
            emergencyPauser_;
        oracle = oracle_;
        notifier = notifier_;

        state = State.Created;
    }

    function deposit(
        uint256 requestedAmount
    ) external {
        if (paused) {
            revert Paused();
        }

        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (state != State.Created) {
            revert InvalidState();
        }

        if (requestedAmount == 0) {
            revert ZeroAmount();
        }

        uint256 beforeBalance =
            token.balanceOf(
                address(this)
            );

        token.safeTransferFrom(
            buyer,
            address(this),
            requestedAmount
        );

        uint256 afterBalance =
            token.balanceOf(
                address(this)
            );

        uint256 received =
            afterBalance
                - beforeBalance;

        if (received == 0) {
            revert ZeroAmount();
        }

        escrowedAmount =
            received;

        state =
            State.Funded;

        emit Deposited(
            requestedAmount,
            received
        );
    }

    function release()
        external
    {
        if (paused) {
            revert Paused();
        }

        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (state != State.Funded) {
            revert InvalidState();
        }

        (
            int256 price,
            uint256 updatedAt
        ) = oracle.latestPrice();

        if (price <= 0) {
            revert InvalidPrice();
        }

        if (
            updatedAt == 0 ||
            updatedAt > block.timestamp
        ) {
            revert InvalidTimestamp();
        }

        if (
            block.timestamp
                - updatedAt
                > MAX_ORACLE_AGE
        ) {
            revert StalePrice();
        }

        uint256 gross =
            escrowedAmount;

        uint256 fee =
            gross
                * feeBps
                / 10_000;

        uint256 payout =
            gross - fee;

        escrowedAmount = 0;
        state = State.Released;

        token.safeTransfer(
            seller,
            payout
        );

        if (
            address(notifier)
                != address(0)
        ) {
            try notifier.notifyReleased(
                seller,
                payout
            ) {
            }
            catch (
                bytes memory reason
            ) {
                emit NotificationFailed(
                    reason
                );
            }
        }

        emit Released(
            gross,
            fee
        );
    }

    function refund()
        external
    {
        if (msg.sender != buyer) {
            revert OnlyBuyer();
        }

        if (state != State.Funded) {
            revert InvalidState();
        }

        uint256 amount =
            escrowedAmount;

        escrowedAmount = 0;
        state = State.Refunded;

        token.safeTransfer(
            buyer,
            amount
        );

        emit Refunded(
            amount
        );
    }

    function setFee(
        uint256 newFeeBps
    ) external {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }

        if (newFeeBps > 1_000) {
            revert FeeTooHigh();
        }

        feeBps =
            newFeeBps;
    }

    function setOracle(
        IPriceOracleFixed newOracle
    ) external {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }

        if (
            address(newOracle)
                == address(0)
        ) {
            revert ZeroAddress();
        }

        oracle =
            newOracle;
    }

    function pause()
        external
    {
        if (
            msg.sender
                != emergencyPauser
        ) {
            revert OnlyPauser();
        }

        paused = true;
    }

    function unpause()
        external
    {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }

        paused = false;
    }
}
```

Questa è una versione **migliorata per il laboratorio**, non una certificazione production-ready.

---

# 28. Regression suite minima

Dopo le correzioni, la suite deve includere almeno:

```text
test_BuyerCanDeposit
test_StrangerCannotDeposit
test_ZeroDepositReverts
test_DoubleDepositReverts

test_F01_DepositUsesActualReceived
test_F02_StaleOracleRejected
test_F02_ExactMaxAgeAccepted
test_F03_FalseReturnTransferCannotFinalize
test_F04_StrangerCannotReplaceOracle
test_F05_NotifierFailureDoesNotBlockRelease

test_ReleaseClearsLiability
test_RefundClearsLiability
test_DoubleReleaseReverts
test_RefundAfterReleaseReverts

test_OnlyPauserCanPause
test_OnlyOwnerCanUnpause
test_FeeUpperBound
```

---

# 29. Invariant suite

Per il Fixed Escrow:

## INV-01

```text
state == Funded
=>
token.balanceOf(escrow)
>=
escrowedAmount
```

## INV-02

```text
state == Released
=>
escrowedAmount == 0
```

## INV-03

```text
state == Refunded
=>
escrowedAmount == 0
```

## INV-04

```text
terminal state
=>
never returns to Funded/Created
```

## INV-05

```text
feeBps <= 1000
```

---

# 30. Esempio invariant

```solidity
function invariant_FundedIsBacked()
    public
    view
{
    if (
        escrow.state()
            ==
        EscrowFinalFixed
            .State
            .Funded
    ) {
        assertGe(
            token.balanceOf(
                address(escrow)
            ),
            escrow
                .escrowedAmount()
        );
    }
}
```

---

# 31. Fuzz suite

Esempi:

```text
deposit amount
fee boundary
oracle age
unauthorized callers
```

## Fee

```solidity
function testFuzz_FeeBound(
    uint256 fee
) public {
    fee = bound(
        fee,
        0,
        1000
    );

    vm.prank(owner);

    escrow.setFee(
        fee
    );

    assertEq(
        escrow.feeBps(),
        fee
    );
}
```

## Oracle freshness

```text
age <= MAX -> accepted
age > MAX -> rejected
```

---

# 32. Governance extension

Per una versione reale del progetto finale:

```text
owner
```

non dovrebbe necessariamente essere una singola EOA.

Possiamo impostare:

```text
owner = TimelockController
```

con:

```text
Multisig -> proposer
Timelock -> owner
```

OpenZeppelin [documenta questo pattern](https://docs.openzeppelin.com/contracts/5.x/access-control): il Timelock, quando è owner/admin/controller del target, applica un ritardo alle operazioni `onlyOwner`; un multisig o DAO può essere il proposer. Nel laboratorio usiamo un timelock giocattolo locale.

Regression property:

```text
proposer cannot directly setOracle
timelock execute before delay fails
timelock execute after delay succeeds
```

---

# 33. Upgradeable extension

Se trasformiamo `EscrowFinalFixed` in UUPS:

```text
ERC1967Proxy
+
UUPSUpgradeable
+
_authorizeUpgrade
```

OpenZeppelin [documenta](https://docs.openzeppelin.com/contracts/5.x/api/proxy) l'implementazione UUPS, la funzione `_authorizeUpgrade` e il controllo di compatibilità tramite ERC-1822.

Aggiungiamo invarianti:

```text
unauthorized upgrade -> revert
state preserved after upgrade
initializer cannot repeat
storage layout compatible
```

E ricordiamo:

```text
major OpenZeppelin versions
non vanno assunte storage-compatible
```

per upgrade live, come indica la [guida di compatibilità OpenZeppelin](https://docs.openzeppelin.com/contracts/5.x/backwards-compatibility).

---

# 34. Slither final pass

Esegui:

```bash
slither .
```

Poi:

```bash
slither . \
  --print human-summary

slither . \
  --print entry-points

slither . \
  --print vars-and-auth

slither . \
  --print call-graph
```

La [documentazione dei printer di Slither](https://github.com/crytic/slither/wiki/Printer-documentation) descrive `entry-points`, `call-graph`, `function-summary` e `vars-and-auth`.

La [guida d'uso di Slither](https://github.com/crytic/slither/wiki/Usage) descrive detector, selezione, filtri, JSON e triage.

---

# 35. Esempio di finding report — F-01

# F-01 — Nominal ERC-20 accounting can create unbacked liabilities

**Severity:** Medium nel laboratorio didattico; in un sistema reale dipenderebbe dagli asset supportati e dall’impatto economico.

## Summary

`deposit()` credits the caller-supplied amount without verifying the amount of tokens actually received.

A fee-on-transfer token can therefore cause `escrowedAmount` to exceed the token balance backing that liability.

## Impact

The escrow can become insolvent relative to its own accounting:

```text
actual assets < recorded liability
```

Later settlement can fail or pay less than the protocol claims is owed.

## Root Cause

The implementation assumes:

```text
requestedAmount == receivedAmount
```

and does not reconcile the transfer against the escrow’s token balance.

## Local Reproduction

Using the toy 10% `FeeToken`:

```text
requested = 100
received  = 90
credited  = 100
```

## Recommendation

Use `SafeERC20` for transfer mechanics and, if fee-on-transfer tokens are intentionally supported, compute credit using a before/after balance delta.

Otherwise explicitly reject/support only exact-transfer assets.

## Regression Test

```text
test_F01_DepositUsesActualReceived
```

---

# 36. Esempio di finding report — F-04

# F-04 — Any account can replace the price oracle

**Severity:** High nel modello del laboratorio, perché l’oracle influenza una transizione economica critica.

## Summary

`setOracle()` lacks authorization.

Any account can replace the configured oracle.

## Impact

An unprivileged caller can redirect price reads to arbitrary code and thereby influence release validation.

## Root Cause

The function writes a critical dependency without checking `msg.sender`.

## Local Reproduction

```text
stranger
-> setOracle(attackerOracle)
-> oracle changed
```

## Recommendation

Restrict the function to governance/owner and reject the zero address.

If the system promises delayed governance, ownership must be held by the timelock or all alternate paths must enforce the same delay.

## Regression Test

```text
test_F04_StrangerCannotReplaceOracle
```

---

# 37. Severity table

| ID | Finding | Core property |
|---|---|---|
| F-01 | Nominal token accounting | assets >= liabilities |
| F-02 | Stale oracle accepted | price freshness |
| F-03 | Token transfer return ignored | terminal state implies settlement |
| F-04 | Oracle setter unprotected | privileged config |
| F-05 | Notifier failure silent | observability / optional dependency |

La severity finale di un audit reale dipende da:

```text
asset value
reachability
permissions
recovery
repeatability
production configuration
```

Non copiare meccanicamente il rating di un detector.

---

# 38. Retest checklist

Dopo remediation:

- [ ] F-01 PoC no longer violates solvency
- [ ] F-02 stale price reverts
- [ ] F-03 false-return token cannot finalize
- [ ] F-04 stranger cannot change oracle
- [ ] F-05 notifier failure is observable
- [ ] full unit suite passes
- [ ] fuzz suite passes
- [ ] invariant suite passes
- [ ] Slither rerun
- [ ] coverage reviewed

Se il contratto è upgradeable:

- [ ] storage validation passes
- [ ] migration tested
- [ ] old state preserved

---

# 39. Final audit workflow

```text
1. lock scope + commit

2. build + baseline tests

3. architecture map

4. asset/actor inventory

5. trust assumptions

6. invariants

7. entry-point inventory

8. manual function review

9. storage/write-path review

10. external-call review

11. privileged-path review

12. economic/oracle/token review

13. Slither printers

14. Slither detectors

15. Foundry PoC

16. remediation

17. regression tests

18. fuzz/invariants

19. retest

20. final report
```

Questa è la metodologia che voglio tu conservi dal corso.

---

# 40. Cosa abbiamo imparato dal progetto finale

## 1. Il bug più importante non è sempre quello che “sembra hacker”

Un semplice:

```solidity
escrowedAmount = amount;
```

può essere il punto in cui nasce l’insolvenza.

---

## 2. Lo stesso pattern tecnico può avere severity diverse

Un unchecked low-level call verso notifier opzionale è molto diverso da un unchecked payout.

Il contesto conta.

---

## 3. State machine e accounting devono raccontare la stessa realtà

Non devi poter avere:

```text
state = Released
```

quando il payout è fallito.

---

## 4. Le dipendenze sono parte del protocollo

Token e oracle non sono dettagli esterni.

Il loro comportamento entra direttamente negli invarianti.

---

## 5. Access control e governance sono due livelli

```text
onlyOwner
```

è soltanto il primo.

Devi sapere chi controlla `owner`.

---

## 6. Un finding è una proprietà violata + evidenza

Non un warning.

---

## 7. Ogni remediation deve lasciare un regression test

---

## 8. Static analysis, fuzzing e invariant testing completano la review manuale

Nessuno dei tre sostituisce gli altri.

---

# 41. Checklist finale da auditor

## Scope

- [ ] commit fissato
- [ ] compiler/config fissati
- [ ] files in/out of scope
- [ ] dependencies note

## Architecture

- [ ] diagramma
- [ ] assets
- [ ] actors
- [ ] trust boundaries

## Invariants

- [ ] accounting
- [ ] solvency
- [ ] state machine
- [ ] authorization
- [ ] oracle
- [ ] governance
- [ ] upgrade

## Manual review

- [ ] entry points
- [ ] state writes
- [ ] external calls
- [ ] callback/reentrancy
- [ ] zero/boundary
- [ ] error paths
- [ ] terminal states

## Asset integration

- [ ] ERC20 return values
- [ ] exact vs received
- [ ] decimals
- [ ] fee/rebase policy

## Oracle

- [ ] sign
- [ ] timestamp
- [ ] max age
- [ ] pair
- [ ] decimals
- [ ] admin

## Governance

- [ ] owner
- [ ] role admins
- [ ] multisig threshold
- [ ] timelock
- [ ] bypass
- [ ] emergency powers

## Upgradeability

- [ ] initializer
- [ ] implementation lock
- [ ] storage layout
- [ ] authorize upgrade
- [ ] migration

## Tooling

- [ ] forge build
- [ ] forge test
- [ ] coverage
- [ ] fuzz
- [ ] invariant
- [ ] Slither

## Findings

- [ ] root cause
- [ ] impact
- [ ] reproduction
- [ ] remediation
- [ ] regression

## Retest

- [ ] diff reviewed
- [ ] PoC broken
- [ ] full suite green
- [ ] static tools rerun

---

# 42. Esercizi finali

Non do subito le soluzioni.

## Esercizio 1 — Trova un sesto finding

Rileggi `EscrowFinal`.

Trova almeno un problema o design question non incluso in F-01…F-05.

Suggerimenti:

```text
refund while paused?
zero addresses?
ownership transfer?
fee destination?
actual fee accounting?
notifier address zero?
```

---

## Esercizio 2 — Fee accounting

Nel Fixed contract:

```text
gross = escrowedAmount
fee = gross * feeBps / 10000
payout = gross - fee
```

Domanda:

> Dove vanno i token della fee?

Decidi una specification corretta e modifica il contratto.

---

## Esercizio 3 — Pause semantics

Nel codice attuale:

```text
deposit blocked while paused
release blocked while paused
refund NOT blocked
```

È intenzionale?

Argomenta se questo design:

```text
pause new risk
allow exit
```

è appropriato.

Poi scrivi test.

---

## Esercizio 4 — Timelock governance

Sostituisci `owner` con un `TimelockController` locale.

Testa:

```text
proposer direct setOracle -> fail
execute before delay -> fail
execute after delay -> success
```

---

## Esercizio 5 — UUPS

Converti il Fixed Escrow in una versione upgradeable locale.

Testa:

```text
initializer once
unauthorized upgrade fails
state preserved
V2 field initialized
```

---

## Esercizio 6 — Invariant handler

Costruisci un handler che generi:

```text
deposit
release
refund
pause
unpause
```

con actor realistici.

Verifica:

```text
terminality
solvency
fee bound
```

---

## Esercizio 7 — Mutation campaign

Introduci una per volta:

```text
remove OnlyOwner on setOracle
use requested instead of received
remove stale check
ignore safeTransfer
change fee bound > to >=
```

Ogni mutation deve essere uccisa dalla suite.

---

## Esercizio 8 — Mini report

Scrivi un report di 2–4 pagine con:

```text
Executive Summary
Scope
Architecture
Trust Assumptions
Findings
Retest
Limitations
```

---

# 43. Cosa devi ricordare dall’intero corso

Se devi conservare un’unica metodologia, conserva questa:

> **Prima definiamo ciò che il contratto deve garantire.  
> Poi implementiamo.  
> Poi testiamo.  
> Poi cerchiamo di violare le proprietà in locale.  
> Poi correggiamo.  
> Poi aggiungiamo una regressione.**

E quando fai audit:

```text
specification
   |
   v
invariants
   |
   v
attack surface
   |
   v
manual review
   |
   +--> static analysis
   +--> unit/negative tests
   +--> fuzzing
   +--> invariant testing
   |
   v
evidence
   |
   v
finding
   |
   v
fix
   |
   v
retest
```

Questa è la mentalità centrale della smart contract security.

---

# 44. Fonti della lezione

Fonti tecniche consultate il **22 settembre 2026**:

1. **Solidity Documentation — Security Considerations**  
   CEI, external calls, reentrancy e raccomandazioni generali di sicurezza. La documentazione corrente sottolinea che la reentrancy può derivare da qualsiasi external call e può coinvolgere più contratti.  
   https://docs.soliditylang.org/en/latest/security-considerations.html

2. **OpenZeppelin Contracts 5.x — ERC20 / SafeERC20**  
   `SafeERC20` gestisce token che ritornano `false` e token che non ritornano dati; resta responsabilità del protocollo definire la semantica economica dell’asset.  
   https://docs.openzeppelin.com/contracts/5.x/api/token/erc20

3. **OpenZeppelin Contracts 5.x — Access Control / Timelock**  
   `TimelockController` introduce ritardo sulle operazioni privilegiate quando è owner/admin/controller del target; multisig o DAO possono fungere da proposer.  
   https://docs.openzeppelin.com/contracts/5.x/access-control  
   https://docs.openzeppelin.com/contracts/5.x/api/governance

4. **OpenZeppelin Contracts 5.x — Proxy / UUPS**  
   UUPS usa `ERC1967Proxy`, `UUPSUpgradeable` e `_authorizeUpgrade`; il meccanismo corrente usa ERC-1822 per verificare compatibilità dell’implementation.  
   https://docs.openzeppelin.com/contracts/5.x/api/proxy

5. **OpenZeppelin Contracts 5.x — Backwards Compatibility**  
   Le major release vanno considerate incompatibili per storage upgradeability; i plugin OpenZeppelin sono raccomandati per verificare storage layout safety.  
   https://docs.openzeppelin.com/contracts/5.x/backwards-compatibility

6. **Trail of Bits — Slither**  
   Static analyzer usato per detector, call graph, entry points e `vars-and-auth`.  
   https://github.com/crytic/slither

7. **Slither Usage / Printer Documentation**  
   Uso di detector, `entry-points`, `call-graph`, `function-summary`, `vars-and-auth`, filtering, JSON e triage.  
   https://github.com/crytic/slither/wiki/Usage  
   https://github.com/crytic/slither/wiki/Printer-documentation

8. **Foundry Documentation**  
   Build, unit testing, fuzzing e invariant testing per riproduzioni e regressioni locali.  
   https://getfoundry.sh/

9. **OWASP Smart Contract Security Verification Standard (SCSVS)**  
   Framework per threat modeling, authorization, oracle integration, business logic e verification methodology.  
   https://scs.owasp.org/SCSVS/

---

# Fine del corso

Con questa lezione si chiude la roadmap principale **1–17**.

Il passo successivo non è una “Lezione 18” automatica.

Da qui puoi usare il materiale in tre modi:

```text
1. rifare l’Escrow da zero senza guardare le soluzioni;

2. scegliere un nuovo protocollo giocattolo e applicare la stessa metodologia;

3. fare mini-audit locali periodici con scope, invarianti, finding e retest.
```

La competenza che conta non è memorizzare una lista di vulnerabilità.

È riuscire a guardare nuovo codice e chiederti, in ordine:

```text
Che cosa deve garantire?
Chi può influenzarlo?
Quale stato è critico?
Dove passa il controllo?
Quali assunzioni eredita?
Come posso provare che la proprietà regge?
Come posso dimostrare localmente che non regge?
```

Questa è la base pratica della Smart Contract Security.
