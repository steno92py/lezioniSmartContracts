# Lezione 12 — Governance, owner, multisig e timelock

> **Scopo:** secure coding, auditing, threat modeling e testing.  
> Tutti gli esempi restano confinati a **Foundry/Anvil locale**, account di test e contratti giocattolo.
>
> Questa lezione non assume che "più governance" significhi automaticamente "più sicurezza". L'obiettivo è capire **quale autorità esiste, chi la controlla, con quale velocità può agire e quale blast radius possiede**.

---

# 1. Obiettivi

Alla fine della lezione dovresti saper:

- distinguere ownership, role-based access control, multisig, timelock e governance;
- spiegare perché una singola chiave admin è un single point of failure;
- capire perché un multisig riduce alcuni rischi ma non elimina il rischio di governance;
- modellare soglia `m-of-n`;
- capire la differenza tra:
  - authorization;
  - approval quorum;
  - execution delay;
- spiegare il ruolo di `TimelockController`;
- distinguere:
  - proposer;
  - executor;
  - canceller;
  - admin;
- capire perché il timelock dovrebbe spesso essere il vero owner/admin del contratto controllato;
- progettare separation of duties;
- separare:
  - operazioni ordinarie;
  - upgrade;
  - pause/emergency;
  - recovery;
- comprendere safety vs liveness nelle chiavi di governance;
- testare localmente:
  - unauthorized admin calls;
  - ownership transfer;
  - scheduling;
  - execution prima/dopo il delay;
  - cancellation;
  - emergency powers;
- costruire una checklist da auditor sulle funzioni privilegiate.

---

# 2. Modello mentale

Nelle lezioni precedenti abbiamo chiesto:

```text
chi può chiamare questa funzione?
```

Ora la domanda diventa più ampia:

```text
chi può cambiare le regole del sistema?
```

Per esempio:

```text
setFee(...)
setOracle(...)
setRouter(...)
pause()
unpause()
upgradeToAndCall(...)
grantRole(...)
revokeRole(...)
```

Tutte queste funzioni possono essere tecnicamente corrette e tuttavia rendere il sistema fragile se il controllo è concentrato male.

Un contratto con ottima business logic ma una singola chiave admin capace di:

```text
upgrade
cambiare oracle
spostare fondi
cambiare ruoli
```

ha un trust model molto diverso da un contratto immutable.

---

# 3. Ownership

Il modello più semplice è:

```text
Contract
   |
   +--> owner
```

e funzioni:

```solidity
function setSomething(...)
    external
    onlyOwner
```

OpenZeppelin 5.x espone:

```solidity
Ownable(initialOwner)
```

Il proprietario iniziale viene quindi scelto esplicitamente.

Esempio:

```solidity
import {
    Ownable
} from
    "@openzeppelin/contracts/access/Ownable.sol";

contract EscrowAdmin is Ownable {
    uint256 public feeBps;

    constructor(
        address initialOwner
    )
        Ownable(initialOwner)
    {}

    function setFee(
        uint256 newFeeBps
    ) external onlyOwner {
        feeBps = newFeeBps;
    }
}
```

---

# 4. Che cosa garantisce `onlyOwner`

Garantisce:

```text
msg.sender == owner
```

Non garantisce:

```text
owner è sicuro
owner è onesto
owner è disponibile
owner è multisig
owner non può essere compromesso
owner non farà errori
```

Quindi:

```text
access control corretto
```

non implica:

```text
governance sicura
```

---

# 5. Single point of failure

Supponiamo:

```text
owner = una singola EOA
```

Se quella chiave:

```text
viene persa
```

potremmo perdere la liveness amministrativa.

Se:

```text
viene compromessa
```

un soggetto non autorizzato dal punto di vista umano potrebbe comunque risultare:

```text
msg.sender == owner
```

per il contratto.

La blockchain non distingue:

```text
legittimo proprietario della chiave
```

da:

```text
chi possiede materialmente la private key.
```

---

# 6. Safety vs liveness della chiave admin

## Safety

Vogliamo impedire:

```text
upgrade malevolo
oracle malevolo
fee arbitraria
drain amministrativo
```

## Liveness

Vogliamo poter:

```text
correggere bug
ruotare ruoli
eseguire upgrade
recuperare da failure
```

Una governance molto rigida può migliorare la safety ma peggiorare la liveness.

Una governance molto rapida può migliorare la risposta alle emergenze ma aumentare il rischio di abuso.

Questo trade-off accompagnerà tutta la lezione.

---

# 7. `Ownable2Step`

Un errore amministrativo classico è trasferire ownership all'indirizzo sbagliato.

Con un trasferimento one-step:

```text
owner
  |
  | transfer ownership
  v
new owner
```

se il destinatario è errato, il controllo può essere perso.

OpenZeppelin offre:

```solidity
Ownable2Step
```

con modello:

```text
current owner
   |
   | transferOwnership(candidate)
   v
pending owner

pending owner
   |
   | acceptOwnership()
   v
new owner
```

Questo riduce il rischio di trasferimento accidentale a un address che non può/sa assumere il ruolo.

---

# 8. Multisig: modello mentale

Un multisig sostituisce concettualmente:

```text
1 chiave -> decisione
```

con:

```text
n owners
+
threshold m
```

Esempio:

```text
3-of-5
```

Significa:

```text
5 owners registrati
almeno 3 approvazioni
per autorizzare l'azione
```

Diagramma:

```text
Owner A ----\
Owner B -----\
Owner C ------> Multisig ----> Target Contract
Owner D -----/
Owner E ----/
```

Il target vede:

```text
msg.sender = address(multisig)
```

Non vede direttamente le singole firme.

---

# 9. Perché un multisig riduce il rischio

Una singola chiave compromessa non basta se:

```text
threshold > 1
```

Con un 3-of-5:

```text
1 chiave compromessa
!=
controllo del multisig
```

Inoltre può ridurre:

```text
errore individuale
insider singolo
device singolo compromesso
```

Ma introduce nuovi problemi.

---

# 10. Un multisig non elimina il trust

Se controlla:

```text
upgrade
pause
oracle
treasury
```

allora il multisig conserva comunque un enorme potere.

La domanda diventa:

```text
quanti firmatari devono colludere
o essere compromessi?
```

In un 3-of-5:

```text
3
```

Quindi il multisig trasforma il modello:

```text
single-key trust
```

in:

```text
threshold trust
```

Non in:

```text
trustless
```

---

# 11. Threshold: trade-off

## 1-of-5

Alta liveness:

```text
basta una firma
```

Bassa resistenza:

```text
una sola chiave compromessa basta
```

## 5-of-5

Alta resistenza alla singola compromissione:

```text
servono tutte le chiavi
```

Ma bassa liveness:

```text
una chiave persa
=> sistema potenzialmente bloccato
```

## 3-of-5

Compromesso classico:

```text
tollera fino a 2 indisponibili
richiede 3 compromessi/collusioni
```

La soglia è parte del threat model.

---

# 12. Non basta contare i signer

Cinque signer su:

```text
stesso laptop
stesso password manager
stessa persona
stesso cloud account
```

non equivalgono necessariamente a cinque domini di sicurezza indipendenti.

Da auditor operativo chiedi:

```text
chi controlla le chiavi?
su quali dispositivi?
con quali procedure?
sono organizzativamente indipendenti?
```

Questo esce dal puro bytecode ma rientra nella sicurezza del sistema.

---

# 13. Multisig locale nel corso

Non abbiamo bisogno di usare un wallet pubblico reale.

Possiamo modellare un multisig giocattolo.

## `src/governance/ToyMultisig.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract ToyMultisig {
    address[] public owners;
    mapping(address => bool)
        public isOwner;

    uint256 public immutable threshold;

    struct Transaction {
        address target;
        uint256 value;
        bytes data;
        uint256 approvals;
        bool executed;
    }

    mapping(uint256 => Transaction)
        public transactions;

    mapping(
        uint256 =>
        mapping(address => bool)
    )
        public approvedBy;

    uint256 public nextId;

    error NotOwner();
    error AlreadyApproved();
    error ThresholdNotReached();
    error AlreadyExecuted();
    error InvalidThreshold();
    error CallFailed();

    constructor(
        address[] memory owners_,
        uint256 threshold_
    ) {
        if (
            threshold_ == 0 ||
            threshold_ > owners_.length
        ) {
            revert InvalidThreshold();
        }

        threshold = threshold_;

        for (
            uint256 i;
            i < owners_.length;
            ++i
        ) {
            address owner =
                owners_[i];

            require(
                owner != address(0),
                "zero owner"
            );

            require(
                !isOwner[owner],
                "duplicate"
            );

            isOwner[owner] = true;
            owners.push(owner);
        }
    }

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) {
            revert NotOwner();
        }

        _;
    }

    function submit(
        address target,
        uint256 value,
        bytes calldata data
    )
        external
        onlyOwner
        returns (uint256 id)
    {
        id = nextId++;

        Transaction storage txn =
            transactions[id];

        txn.target = target;
        txn.value = value;
        txn.data = data;
    }

    function approve(
        uint256 id
    ) external onlyOwner {
        if (approvedBy[id][msg.sender]) {
            revert AlreadyApproved();
        }

        approvedBy[id][msg.sender] = true;
        transactions[id].approvals += 1;
    }

    function execute(
        uint256 id
    ) external onlyOwner {
        Transaction storage txn =
            transactions[id];

        if (txn.executed) {
            revert AlreadyExecuted();
        }

        if (
            txn.approvals < threshold
        ) {
            revert ThresholdNotReached();
        }

        txn.executed = true;

        (
            bool ok,
        ) = txn.target.call{
            value: txn.value
        }(txn.data);

        if (!ok) {
            revert CallFailed();
        }
    }

    receive() external payable {}
}
```

Questo contratto è deliberatamente semplice.

Non è un sostituto di Safe.

Serve a modellare:

```text
proposal
approval
threshold
execution
```

---

# 14. Analisi del ToyMultisig

## `submit`

### Caller

Solo owner.

### Input controllati

```text
target
value
data
```

Questi input sono potentissimi.

Il multisig è praticamente un executor generico.

### Stato scritto

```text
nuova transaction
```

### External call

Nessuna.

### Assunzione

Gli owner useranno il multisig soltanto per target/action appropriate.

---

## `approve`

### Caller

Solo owner.

### Input

```text
id
```

### Stato

Marca:

```text
approvedBy[id][owner] = true
```

e incrementa approvals.

### Proprietà

Un owner non può contare due volte.

---

## `execute`

### Caller

Solo owner nel toy model.

### Precondizione

```text
approvals >= threshold
```

### Stato

```text
executed = true
```

prima della call.

### External call

```solidity
target.call(...)
```

### CEI

Segniamo eseguita prima della call per evitare re-execution via callback.

Se la call reverte, l'intera transazione reverte e quindi anche:

```text
executed = true
```

torna al valore precedente.

---

# 15. Multisig come owner

Se il nostro Escrow è:

```solidity
Ownable
```

possiamo impostare:

```text
owner = ToyMultisig
```

o, in sistemi reali, un Safe.

Diagramma:

```text
Signers
   |
   v
Multisig
   |
   | onlyOwner call
   v
Escrow
```

Dal punto di vista dell'Escrow:

```text
owner = multisig address
```

---

# 16. Limite del multisig senza timelock

Se 3 firmatari approvano:

```text
upgrade
```

l'esecuzione può avvenire immediatamente.

Gli utenti possono scoprire la modifica soltanto quando è già stata eseguita.

Quindi il multisig protegge principalmente:

```text
CHI deve approvare
```

Non necessariamente:

```text
QUANTO TEMPO deve passare prima dell'effetto
```

Qui entra il timelock.

---

# 17. Timelock: modello mentale

Con timelock:

```text
Governance / Multisig
        |
        | schedule
        v
+-------------------+
| Timelock          |
|                   |
| WAIT Δt           |
+---------+---------+
          |
          | execute
          v
      Target Contract
```

La proprietà è:

```text
azione approvata
!=
azione immediatamente eseguibile
```

Serve un periodo minimo.

---

# 18. Perché il delay è una security property

Un delay può dare tempo per:

```text
review della modifica
monitoring
allerta utenti
exit dal protocollo
reazione operativa
```

OpenZeppelin descrive precisamente questo uso: un `TimelockController` posto come owner/admin/controller introduce un ritardo tra la decisione e la sua applicazione.

---

# 19. Il timelock non impedisce una decisione malevola

Supponiamo governance compromessa.

Può comunque programmare:

```text
upgrade malevolo
```

Il timelock non dice:

```text
"questa proposta è buona"
```

Dice:

```text
"questa proposta non diventa efficace prima di Δt"
```

Quindi trasforma il rischio:

```text
instantaneous governance risk
```

in:

```text
observable delayed governance risk
```

Se gli utenti non possono uscire durante il delay, il beneficio può essere molto minore.

---

# 20. Delay e exit path

Un timelock è particolarmente utile quando:

```text
utente osserva proposta
        |
        v
non è d'accordo
        |
        v
può ritirare / uscire
        |
        v
prima dell'esecuzione
```

Se invece:

```text
withdraw è già bloccato
```

o:

```text
l'azione può sequestrare asset prima dell'exit
```

il semplice delay non risolve il problema.

---

# 21. `TimelockController`

OpenZeppelin Contracts 5.x espone:

```solidity
import {
    TimelockController
} from
    "@openzeppelin/contracts/governance/TimelockController.sol";
```

Il constructor corrente segue concettualmente:

```solidity
TimelockController(
    minDelay,
    proposers,
    executors,
    admin
)
```

Il contratto gestisce operazioni con stati:

```text
Unset
Waiting
Ready
Done
```

---

# 22. Ruoli del timelock

I ruoli principali includono:

```text
PROPOSER_ROLE
EXECUTOR_ROLE
CANCELLER_ROLE
DEFAULT_ADMIN_ROLE
```

## Proposer

Può schedulare operazioni.

## Executor

Può eseguire operazioni diventate ready.

## Canceller

Può cancellare operazioni pending.

## Admin

Può gestire i ruoli.

Questa separazione è importante.

---

# 23. Proposer != Executor

Il fatto che qualcuno possa dire:

```text
"propongo di eseguire X"
```

non implica necessariamente che debba essere anche chi materialmente esegue X.

Puoi avere:

```text
Multisig = proposer

EOA/operator = executor
```

Dopo il delay, l'executor non può cambiare la proposta.

Può soltanto eseguire ciò che era stato schedulato.

---

# 24. Executor aperto

OpenZeppelin permette di assegnare `EXECUTOR_ROLE` a:

```text
address(0)
```

per rendere l'esecuzione aperta a chiunque una volta che l'operazione è ready.

Questo può migliorare la liveness:

```text
non dipendo da un singolo executor
```

Ma va scelto consapevolmente.

La capacità di schedulare resta distinta dalla capacità di eseguire una proposta già approvata.

---

# 25. Canceller

Il canceller può impedire l'esecuzione di una operazione già schedulata ma non ancora completata.

Questo potere è utile per:

```text
errore scoperto durante il delay
compromissione sospetta
proposta superata
```

Ma può essere usato anche per:

```text
denial of service
```

se assegnato troppo ampiamente.

Da auditor:

```text
chi può cancellare?
```

è importante quanto:

```text
chi può proporre?
```

---

# 26. Admin del timelock

Il ruolo admin è estremamente sensibile perché può:

```text
grant
revoke
```

gli altri ruoli.

OpenZeppelin raccomanda spesso che, dopo il setup, il timelock possa diventare **self-administered**.

In quel modello:

```text
anche modificare i ruoli
deve passare dal timelock
```

Questo evita un admin esterno capace di aggirare il ritardo cambiando direttamente la governance.

Ma introduce un rischio di liveness:

```text
se proposer/executor diventano indisponibili
potresti bloccare il sistema
```

---

# 27. Ownership al timelock

Immagina:

```text
Escrow.owner = Multisig
```

Il multisig può chiamare:

```text
setFee()
upgrade()
setOracle()
```

immediatamente.

Con timelock:

```text
Escrow.owner = Timelock
```

e:

```text
Multisig = proposer
```

Ora il multisig non chiama direttamente l'Escrow.

Schedula una call nel timelock.

Schema:

```text
Signers
   |
   v
Multisig
   |
   | schedule
   v
Timelock
   |
   | wait
   |
   | execute
   v
Escrow
```

Questo è un pattern estremamente importante.

---

# 28. Chi deve essere owner?

Per una funzione:

```solidity
onlyOwner
```

se vuoi imporre davvero il delay, l'owner deve essere:

```text
Timelock
```

non:

```text
Multisig
```

Se il multisig conserva ownership diretta dell'Escrow, potrebbe bypassare il timelock.

Questa è una delle domande principali da audit:

> **Esiste un percorso amministrativo alternativo che aggira il delay?**

---

# 29. Bypass path

Configurazione apparentemente sicura:

```text
Timelock può upgrade
```

ma anche:

```text
EOA admin può upgrade
```

Allora:

```text
timelock
```

non è realmente enforcement.

È solo un percorso opzionale.

Security property reale:

```text
tutte le operazioni sensibili devono attraversare
il controllo previsto
```

---

# 30. Separation of duties

Non dare necessariamente alla stessa entità tutti i poteri.

Esempio:

```text
UPGRADER
    -> multisig + timelock

PAUSER
    -> security council rapido

UNPAUSER
    -> governance/timelock

ORACLE_ADMIN
    -> operazioni dedicate

TREASURY
    -> multisig separato
```

Questo riduce il blast radius di una singola compromissione.

---

# 31. Emergency powers

Un timelock di 48 ore è ottimo per:

```text
upgrade ordinario
fee change
dependency replacement
```

ma potrebbe essere troppo lento per:

```text
fermare depositi durante un exploit attivo
```

Da qui nasce spesso:

```text
fast emergency role
```

Esempio:

```solidity
function pause()
    external
    onlyRole(PAUSER_ROLE)
```

ma:

```solidity
function unpause()
    external
    onlyOwner
```

con owner = Timelock.

---

# 32. Perché pause e unpause possono avere autorità diverse

Il threat model può scegliere:

```text
pause quickly
unpause slowly
```

Perché:

```text
pause
```

riduce spesso una superficie di rischio,

mentre:

```text
unpause
```

riabilita operazioni e quindi può meritare review più lenta.

Non è una regola universale.

È una possibile separation of duties.

---

# 33. Emergency role può diventare DoS

Se il pauser può bloccare:

```text
deposit
withdraw
refund
```

allora una chiave compromessa può causare denial of service.

Quindi bisogna definire:

```text
che cosa viene pausato?
```

Una buona emergency design spesso cerca di mantenere:

```text
user exit
```

quando possibile.

Per esempio:

```text
pause deposits
pause new positions
allow withdrawals/refunds
```

---

# 34. Escrow amministrabile

Costruiamo un contratto giocattolo.

## `src/governance/GovernedEscrow.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {
    Ownable
} from
    "@openzeppelin/contracts/access/Ownable.sol";

contract GovernedEscrow is Ownable {
    uint256 public feeBps;
    address public oracle;

    bool public paused;

    address public immutable emergencyPauser;

    error FeeTooHigh();
    error ZeroAddress();
    error OnlyPauser();
    error Paused();

    event FeeUpdated(
        uint256 oldFee,
        uint256 newFee
    );

    event OracleUpdated(
        address oldOracle,
        address newOracle
    );

    event PausedBy(
        address indexed caller
    );

    event Unpaused();

    constructor(
        address initialOwner,
        address emergencyPauser_
    )
        Ownable(initialOwner)
    {
        if (
            emergencyPauser_
                == address(0)
        ) {
            revert ZeroAddress();
        }

        emergencyPauser =
            emergencyPauser_;
    }

    function setFee(
        uint256 newFeeBps
    ) external onlyOwner {
        if (newFeeBps > 1_000) {
            revert FeeTooHigh();
        }

        uint256 oldFee =
            feeBps;

        feeBps = newFeeBps;

        emit FeeUpdated(
            oldFee,
            newFeeBps
        );
    }

    function setOracle(
        address newOracle
    ) external onlyOwner {
        if (
            newOracle == address(0)
        ) {
            revert ZeroAddress();
        }

        address oldOracle =
            oracle;

        oracle = newOracle;

        emit OracleUpdated(
            oldOracle,
            newOracle
        );
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

        emit PausedBy(
            msg.sender
        );
    }

    function unpause()
        external
        onlyOwner
    {
        paused = false;

        emit Unpaused();
    }

    function sensitiveAction()
        external
        view
    {
        if (paused) {
            revert Paused();
        }

        // placeholder
    }
}
```

Questo design dice esplicitamente:

```text
emergencyPauser:
    può fermare

owner:
    può modificare configurazione
    può riaprire
```

---

# 35. Analisi dei privilegi

## `setFee`

Caller:

```text
owner
```

Effetto:

```text
cambia economics
```

Rischio:

```text
fee aggressiva / errore configurazione
```

Buon candidato per timelock.

---

## `setOracle`

Caller:

```text
owner
```

Effetto:

```text
cambia una trust boundary
```

Rischio:

```text
oracle malevolo
wrong feed
wrong decimals
```

Ottimo candidato per timelock.

---

## `pause`

Caller:

```text
emergencyPauser
```

Effetto:

```text
ferma sensitiveAction
```

Rischio:

```text
DoS
```

Ma risposta rapida può essere desiderabile.

---

## `unpause`

Caller:

```text
owner
```

Se owner = Timelock:

```text
riapertura ritardata
```

Questo può essere un design deliberato:

```text
fast stop
slow restart
```

---

# 36. Deploy del Timelock locale

Nel test:

```solidity
address proposer =
    makeAddr("proposer");

address executor =
    makeAddr("executor");

address admin =
    makeAddr("admin");

address[] memory proposers =
    new address[](1);

proposers[0] = proposer;

address[] memory executors =
    new address[](1);

executors[0] = executor;

TimelockController timelock =
    new TimelockController(
        2 days,
        proposers,
        executors,
        admin
    );
```

Poi:

```solidity
GovernedEscrow escrow =
    new GovernedEscrow(
        address(timelock),
        emergencyPauser
    );
```

Ora:

```text
owner(Escrow) = Timelock
```

---

# 37. Scheduling

Per eseguire:

```solidity
escrow.setFee(250);
```

prepariamo:

```solidity
bytes memory data =
    abi.encodeCall(
        escrow.setFee,
        (250)
    );
```

Poi il proposer schedula.

Concettualmente:

```solidity
timelock.schedule(
    address(escrow),
    0,
    data,
    bytes32(0),
    salt,
    delay
);
```

Parametri principali:

```text
target
ETH value
calldata
predecessor
salt
delay
```

---

# 38. Operation ID

Il timelock identifica una operazione tramite hash dei suoi contenuti.

Quindi cambiare:

```text
target
value
data
predecessor
salt
```

produce una operazione differente.

Il `salt` aiuta anche a distinguere operazioni altrimenti identiche.

---

# 39. Stato della operazione

Schema:

```text
schedule()
   |
   v
Waiting
   |
   | passa minDelay
   v
Ready
   |
   | execute()
   v
Done
```

Prima di `Ready`:

```text
execute -> revert
```

Questa è la proprietà centrale.

---

# 40. Laboratorio Foundry — test setup

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from
    "forge-std/Test.sol";

import {
    TimelockController
} from
    "@openzeppelin/contracts/governance/TimelockController.sol";

import {
    GovernedEscrow
} from
    "../src/governance/GovernedEscrow.sol";

contract GovernanceTest is Test {
    TimelockController timelock;
    GovernedEscrow escrow;

    address proposer =
        makeAddr("proposer");

    address executor =
        makeAddr("executor");

    address admin =
        makeAddr("admin");

    address emergencyPauser =
        makeAddr("emergencyPauser");

    uint256 constant DELAY =
        2 days;

    function setUp() public {
        address[] memory proposers =
            new address[](1);

        proposers[0] = proposer;

        address[] memory executors =
            new address[](1);

        executors[0] = executor;

        timelock =
            new TimelockController(
                DELAY,
                proposers,
                executors,
                admin
            );

        escrow =
            new GovernedEscrow(
                address(timelock),
                emergencyPauser
            );
    }
}
```

---

# 41. Test negativo — EOA non può bypassare timelock

```solidity
function test_RandomUserCannotSetFee()
    public
{
    address stranger =
        makeAddr("stranger");

    vm.prank(stranger);

    vm.expectRevert();

    escrow.setFee(250);
}
```

Più interessante:

```solidity
function test_ProposerCannotDirectlySetFee()
    public
{
    vm.prank(proposer);

    vm.expectRevert();

    escrow.setFee(250);
}
```

Il proposer ha autorità nel timelock.

Non è owner dell'Escrow.

Quindi:

```text
governance role
!=
direct target privilege
```

---

# 42. Test — schedule

```solidity
function _scheduleFee(
    uint256 fee,
    bytes32 salt
)
    internal
    returns (bytes memory data)
{
    data =
        abi.encodeCall(
            escrow.setFee,
            (fee)
        );

    vm.prank(proposer);

    timelock.schedule(
        address(escrow),
        0,
        data,
        bytes32(0),
        salt,
        DELAY
    );
}
```

---

# 43. Test negativo — execute troppo presto

```solidity
function test_CannotExecuteBeforeDelay()
    public
{
    bytes32 salt =
        keccak256("fee-250");

    bytes memory data =
        _scheduleFee(
            250,
            salt
        );

    vm.prank(executor);

    vm.expectRevert();

    timelock.execute(
        address(escrow),
        0,
        data,
        bytes32(0),
        salt
    );

    assertEq(
        escrow.feeBps(),
        0
    );
}
```

---

# 44. Test — execution dopo il delay

```solidity
function test_ExecuteAfterDelay()
    public
{
    bytes32 salt =
        keccak256("fee-250");

    bytes memory data =
        _scheduleFee(
            250,
            salt
        );

    vm.warp(
        block.timestamp
        + DELAY
    );

    vm.prank(executor);

    timelock.execute(
        address(escrow),
        0,
        data,
        bytes32(0),
        salt
    );

    assertEq(
        escrow.feeBps(),
        250
    );
}
```

Ora:

```text
msg.sender visto da Escrow
=
Timelock
```

quindi `onlyOwner` passa.

---

# 45. Test di boundary temporale

Se una operazione diventa ready esattamente a:

```text
scheduledAt + delay
```

scrivi test per:

```text
delay - 1
delay
delay + 1
```

Non affidarti a intuizioni.

Verifica la semantica esatta della versione usata.

Questo principio lo abbiamo già applicato a:

```text
oracle freshness
deadlines
state transitions
```

---

# 46. Cancellation

Una operazione pending può essere cancellata da chi possiede il ruolo appropriato.

Test concettuale:

```text
schedule
cancel
warp
execute
=> revert
```

Questa proprietà permette recovery prima che l'azione diventi effettiva.

Ma ricorda:

```text
canceller compromesso
=>
governance DoS
```

---

# 47. Test del pause rapido

```solidity
function test_EmergencyPauserCanPauseImmediately()
    public
{
    vm.prank(emergencyPauser);

    escrow.pause();

    assertTrue(
        escrow.paused()
    );
}
```

Non serve timelock.

Questo è intenzionale.

---

# 48. Test negativo — altri non possono pausare

```solidity
function test_StrangerCannotPause()
    public
{
    address stranger =
        makeAddr("stranger");

    vm.prank(stranger);

    vm.expectRevert(
        GovernedEscrow
            .OnlyPauser
            .selector
    );

    escrow.pause();
}
```

---

# 49. Unpause attraverso timelock

Poiché:

```text
owner = Timelock
```

questa call:

```solidity
escrow.unpause();
```

deve essere eseguita dal timelock.

Quindi:

```text
pause:
    immediata

unpause:
    schedulata
    delayed
```

Questo è un esempio di asymmetric emergency governance.

---

# 50. Proprietà e invarianti

## G1 — Solo il controller previsto modifica la config

```text
caller != timelock
=> setFee/setOracle revert
```

## G2 — Nessun bypass del delay

```text
privileged change
=> deve essere eseguibile soltanto
dopo schedule + delay
```

## G3 — Delay boundary

```text
now < readyAt
=> execute revert

now >= readyAt
=> execute può procedere
```

## G4 — Pauser limitato

```text
emergencyPauser
=> può pause

emergencyPauser
=> non può setFee
```

## G5 — Timelock limitato alle sue authority

Il fatto che il timelock sia owner non rende automaticamente ogni altra chiave privileged.

## G6 — Cancellazione effettiva

```text
cancelled operation
=> non può essere eseguita
```

## G7 — Multisig threshold

```text
approvals < threshold
=> no execution
```

## G8 — Una firma conta una volta

```text
same owner
=> cannot increment approvals twice
```

---

# 51. Governance come state machine

Un'azione amministrativa ha essa stessa una macchina a stati.

```text
Unknown
  |
  | proposal
  v
Proposed
  |
  | sufficient approvals
  v
Approved
  |
  | schedule
  v
Waiting
  |
  | time passes
  v
Ready
  |
  | execute
  v
Executed
```

Possibile ramo:

```text
Waiting/Ready
    |
    | cancel
    v
Cancelled
```

Quindi governance security è anche state-machine security.

---

# 52. Proposal != execution

Questa distinzione è essenziale.

Un multisig o DAO può stabilire:

```text
"approviamo X"
```

ma il timelock stabilisce:

```text
"X non può ancora essere eseguito"
```

Quindi abbiamo due proprietà:

```text
authorization threshold
```

e:

```text
temporal delay
```

Sono indipendenti.

---

# 53. AccessControl

Per ruoli multiple OpenZeppelin espone:

```solidity
AccessControl
```

con identificatori:

```solidity
bytes32 public constant PAUSER_ROLE =
    keccak256("PAUSER_ROLE");
```

e controlli:

```solidity
onlyRole(PAUSER_ROLE)
```

Questo permette:

```text
più accounts per ruolo
più ruoli
role admin hierarchy
```

Ma aumenta la complessità.

---

# 54. `DEFAULT_ADMIN_ROLE`

In `AccessControl`, il:

```text
DEFAULT_ADMIN_ROLE
```

è estremamente potente.

Per default può amministrare molti altri ruoli e anche se stesso.

OpenZeppelin fornisce:

```solidity
AccessControlDefaultAdminRules
```

come estensione con regole più rigide per il default admin, inclusi trasferimenti più controllati e delay.

La lezione importante è:

> **Il role-admin graph fa parte del threat model.**

Non guardare soltanto chi ha `PAUSER_ROLE`.

Guarda anche chi può **concederlo**.

---

# 55. Role admin graph

Esempio:

```text
DEFAULT_ADMIN
   |
   +--> grant UPGRADER
   |
   +--> grant PAUSER
   |
   +--> grant ORACLE_ADMIN
```

Anche se:

```text
UPGRADER = multisig
```

ma:

```text
DEFAULT_ADMIN = singola EOA
```

quella EOA potrebbe concedere `UPGRADER_ROLE` a se stessa o ad altri, se la configurazione lo permette.

Quindi:

```text
who can call?
```

deve diventare:

```text
who can obtain permission to call?
```

---

# 56. AccessManager

OpenZeppelin 5.x include:

```text
AccessManager
```

per sistemi più complessi.

L'idea è centralizzare:

```text
roles
permissions
target functions
execution delays
```

per molteplici contratti.

Invece di avere access control frammentato dentro ogni contratto:

```text
Contract A roles
Contract B roles
Contract C roles
```

puoi avere una authority condivisa.

Questo può semplificare la governance di sistemi grandi.

Ma aumenta il blast radius dell'authority centrale.

---

# 57. Quando un AccessManager può aiutare

Immagina:

```text
Escrow
OracleAdapter
FeeController
UpgradeController
```

e vuoi:

```text
role 1 -> pause Escrow
role 2 -> change oracle with delay
role 3 -> update fee with delay
```

Un manager centralizzato può rappresentare queste policy in modo coerente.

Ma da auditor devi chiedere:

```text
chi amministra AccessManager?
```

Perché quella authority diventa sistemica.

---

# 58. Timelock e UUPS

Colleghiamo la Lezione 11.

V1:

```solidity
function _authorizeUpgrade(
    address
)
    internal
    override
    onlyOwner
{}
```

Se:

```text
owner = Timelock
```

allora l'upgrade UUPS deve essere chiamato dal timelock.

Flow:

```text
Multisig
  |
  | schedule upgrade
  v
Timelock
  |
  | wait
  v
Proxy
  |
  | delegatecall
  v
UUPS implementation
  |
  | _authorizeUpgrade
  |
  | msg.sender == Timelock
  v
allowed
```

Questo lega:

```text
proxy security
+
governance security
```

---

# 59. Una configurazione fragile

Supponiamo:

```text
Escrow owner = Timelock
```

ma UUPS `_authorizeUpgrade` controlla:

```text
UPGRADER_ROLE
```

e quel ruolo appartiene a una EOA separata.

Allora:

```text
setFee -> timelocked
upgrade -> immediato via EOA
```

La governance non è uniformemente ritardata.

Non è necessariamente sbagliato.

Ma deve essere intenzionale e documentato.

---

# 60. Emergency upgrade?

Alcuni sistemi desiderano:

```text
upgrade immediato in emergenza
```

Questo migliora response time.

Ma permette anche:

```text
bypass del timelock
```

Quindi un "emergency upgrader" è una authority estremamente potente.

Da auditor chiedi:

```text
chi la possiede?
quando può usarla?
può essere revocata?
è limitata?
può solo pause o può cambiare codice arbitrario?
```

Spesso un emergency pause limitato ha blast radius inferiore a un emergency arbitrary upgrade.

---

# 61. Principle of least authority

Se devi fermare un protocollo, concedi:

```text
pause()
```

non automaticamente:

```text
arbitraryCall(...)
upgrade(...)
transferTreasury(...)
setOracle(...)
```

Il principio:

> **una authority deve avere soltanto i poteri necessari alla sua funzione.**

Vale per:

```text
EOA
multisig
timelock
DAO
contract roles
```

---

# 62. Blast radius table

Costruisci una tabella mentale:

```text
Authority          Compromise impact
---------------------------------------------------
Pauser             blocco parziale
Oracle admin       pricing corruption
Fee admin          economic parameter changes
Upgrader           arbitrary future logic
Default admin      role takeover
Treasury           fund loss
Timelock admin     governance restructuring
Multisig threshold powers depend on assigned roles
```

La sicurezza dipende molto più da questa tabella che dal nome elegante della governance.

---

# 63. Renouncing ownership

`Ownable` permette di rinunciare ownership.

Risultato:

```text
owner = address(0)
```

e le funzioni:

```text
onlyOwner
```

diventano inaccessibili.

Questo può essere desiderato per rendere immutable una configurazione.

Ma è irreversibile salvo meccanismi separati.

Da auditor:

```text
renounceOwnership
```

può rappresentare:

- decentralizzazione deliberata;
- rischio di brick amministrativo.

Dipende dal sistema.

---

# 64. Immutable after setup

Una strategia interessante è:

```text
admin durante setup
        |
        v
configurazione verificata
        |
        v
rinuncia / freeze
```

Così alcune superfici amministrative spariscono.

Esempio:

```text
oracle fisso
router fisso
no upgrade
```

Riduce governance risk.

Ma sacrifica future patch.

Ancora una volta:

```text
immutability
vs
recoverability
```

---

# 65. Timelock delay troppo corto

Se:

```text
minDelay = 1 secondo
```

tecnicamente esiste un timelock.

Ma il beneficio operativo è minimo.

La domanda corretta è:

```text
quanto tempo serve realisticamente
per rilevare, analizzare e reagire?
```

Il delay è una parameter security decision.

---

# 66. Timelock delay troppo lungo

Se:

```text
minDelay = 90 giorni
```

utenti hanno grande preavviso.

Ma correggere un bug urgente può essere impossibile rapidamente.

Possibili architetture:

```text
routine governance -> long delay
emergency pause -> immediate
restart -> delayed
```

Separation of duties serve proprio a gestire trade-off differenti.

---

# 67. Time delay non basta senza monitoring

Un upgrade scheduled 48 ore prima aiuta soltanto se qualcuno può:

```text
osservarlo
```

Quindi eventi e monitoring fanno parte dell'operational security.

Il timelock emette eventi utili sulle operazioni.

Un protocollo serio deve sapere:

```text
quali azioni monitorare?
chi viene allertato?
qual è il response process?
```

---

# 68. Governance operation hashes

In audit, una proposta timelock dovrebbe essere interpretabile.

Non basta vedere:

```text
operation id = 0x...
```

Bisogna decodificare:

```text
target
ETH value
function selector
arguments
predecessor
salt
```

L'azione reale deve corrispondere alla proposta descritta agli utenti.

---

# 69. Batch operations

`TimelockController` supporta anche batch di operazioni.

Questo permette:

```text
upgrade
+
initializeV2
+
setOracle
```

come set coordinato.

Un batch può essere utile per atomicità.

Ma aumenta la superficie di review:

```text
tutte le call del batch
devono essere comprese
```

Una singola call inattesa può cambiare drasticamente l'effetto della proposta.

---

# 70. Predecessor dependency

Il timelock permette anche di modellare dipendenze tra operazioni.

Concettualmente:

```text
Operation B
può dipendere da
Operation A
```

Questo può essere utile per workflow.

Ma aumenta la complessità della governance state machine.

Da auditor:

```text
esiste un predecessor?
è quello atteso?
```

---

# 71. Test del multisig giocattolo

Setup:

```solidity
address alice =
    makeAddr("alice");

address bob =
    makeAddr("bob");

address carol =
    makeAddr("carol");

address[] memory owners =
    new address[](3);

owners[0] = alice;
owners[1] = bob;
owners[2] = carol;

ToyMultisig multisig =
    new ToyMultisig(
        owners,
        2
    );
```

Abbiamo:

```text
2-of-3
```

---

# 72. Test — threshold non raggiunta

```solidity
function test_CannotExecuteWithOneApproval()
    public
{
    // submit da Alice

    vm.prank(alice);

    uint256 id =
        multisig.submit(
            address(target),
            0,
            data
        );

    vm.prank(alice);
    multisig.approve(id);

    vm.prank(alice);

    vm.expectRevert(
        ToyMultisig
            .ThresholdNotReached
            .selector
    );

    multisig.execute(id);
}
```

---

# 73. Test — threshold raggiunta

```text
Alice approve
Bob approve
=> approvals = 2
=> execution allowed
```

Proprietà:

```text
non importa che Carol non abbia approvato
```

perché threshold = 2.

---

# 74. Test negativo — double approval

```solidity
vm.prank(alice);
multisig.approve(id);

vm.prank(alice);

vm.expectRevert(
    ToyMultisig
        .AlreadyApproved
        .selector
);

multisig.approve(id);
```

Una singola identità non deve pesare due volte.

---

# 75. Vulnerabilità concettuale — owners duplicati

Se il constructor permettesse:

```text
owners = [Alice, Alice, Bob]
threshold = 2
```

ma il sistema contasse per indice invece che per address, Alice potrebbe rappresentare due "posti".

Per questo il toy contract verifica:

```text
!isOwner[owner]
```

Una threshold ha senso soltanto se l'insieme dei signer è definito correttamente.

---

# 76. Vulnerabilità concettuale — threshold zero

Se:

```text
threshold = 0
```

un'azione potrebbe risultare immediatamente eseguibile.

Quindi:

```text
threshold > 0
threshold <= number of owners
```

sono invarianti di configurazione.

---

# 77. Vulnerabilità concettuale — timelock bypass

Supponiamo:

```text
Escrow.owner = Timelock
```

ma esiste:

```solidity
function emergencySetOracle(
    address x
) external onlyGuardian
{
    oracle = x;
}
```

Il guardian può cambiare oracle immediatamente.

Quindi dire:

```text
"oracle changes are timelocked"
```

è falso.

Da audit:

> cerca tutti i write path verso lo stesso stato sensibile.

---

# 78. Write-path analysis

Per una variabile:

```text
oracle
```

trova ogni funzione che può modificarla.

Esempio:

```text
setOracle()              -> Timelock
emergencySetOracle()     -> Guardian
initialize()             -> Deployer
migration()              -> Upgrader
```

Poi costruisci:

```text
state variable
    ->
all write paths
    ->
authorities
```

Questo metodo è potentissimo.

---

# 79. Governance graph

Disegna:

```text
Alice/Bob/Carol
      |
      v
   Multisig
      |
      | PROPOSER
      v
   Timelock
      |
      | owner
      +----------> Escrow
      |
      | owner
      +----------> Proxy upgrade authority
      |
      | admin
      +----------> OracleController

Security Council
      |
      | PAUSER
      v
   Escrow
```

Ora puoi vedere:

```text
quale compromissione
colpisce quale componente
```

---

# 80. Esercizio di threat modeling per ogni authority

Per ogni ruolo rispondi:

```text
1. chi controlla la chiave?
2. quante chiavi servono?
3. può agire immediatamente?
4. può cambiare codice?
5. può spostare asset?
6. può assegnare ruoli?
7. può bloccare withdrawal?
8. può essere revocato?
9. chi può revocarlo?
10. il revoker è più potente?
```

Questa è una security review di governance.

---

# 81. Audit dell'upgrade authority

Dalla Lezione 11:

```solidity
_authorizeUpgrade(...)
    onlyOwner
```

Non fermarti lì.

Segui:

```text
owner()
   |
   v
Timelock?
   |
   v
PROPOSER_ROLE?
   |
   v
Multisig?
   |
   v
threshold?
```

L'autorità effettiva può essere distante diversi hop dal proxy.

---

# 82. Recovery

Supponiamo che un signer perda la chiave.

Domande:

```text
può essere sostituito?
chi può sostituirlo?
serve threshold attuale?
se scendiamo sotto threshold siamo bloccati?
```

Supponiamo che un proposer timelock diventi indisponibile.

```text
chi può assegnarne un altro?
```

Se il timelock è completamente self-administered e nessuno può proporre l'operazione necessaria, potresti avere un deadlock.

Questa è liveness governance.

---

# 83. Self-admin timelock: vantaggio

Se:

```text
Timelock
```

amministra se stesso,

allora cambiare:

```text
delay
proposer
executor
```

deve seguire il processo timelock.

Questo impedisce a un admin esterno di fare:

```text
delay = 0
grant proposer a sé stesso
execute immediate
```

---

# 84. Self-admin timelock: rischio

Se tutti i proposers diventano indisponibili:

```text
nessuno può schedulare
```

e anche aggiungere un proposer richiede:

```text
una scheduled operation
```

che nessuno può schedulare.

Risultato:

```text
governance deadlock
```

La decentralizzazione delle authority deve considerare recovery.

---

# 85. `updateDelay`

Nel `TimelockController`, il minimum delay non dovrebbe essere cambiabile direttamente da un account arbitrario.

La gestione è progettata affinché il cambiamento del delay passi attraverso il timelock stesso.

Questo preserva la proprietà:

```text
non posso eliminare istantaneamente
il delay che dovrebbe proteggermi
```

---

# 86. Governance e observability

Eventi importanti:

```text
ownership transferred
role granted
role revoked
operation scheduled
operation cancelled
operation executed
implementation upgraded
paused
unpaused
```

Da audit operativo:

```text
questi eventi vengono monitorati?
```

Uno smart contract non telefona al security team.

Serve infrastruttura off-chain che osservi.

---

# 87. Governance e front-end

Un'interfaccia dovrebbe mostrare chiaramente:

```text
azione programmata
target
calldata decodificata
ready time
```

Non soltanto:

```text
hash opaco
```

Human review è parte del sistema di controllo.

Un multisig con 5 signer che firmano calldata incomprensibile può avere un processo umano debole anche se il contratto è corretto.

---

# 88. Governance non deve diventare un "god mode" non documentato

Esempio:

```solidity
function adminCall(
    address target,
    bytes calldata data
) external onlyOwner {
    target.call(data);
}
```

Questa funzione può rendere irrilevanti molte altre limitazioni.

È un arbitrary call privilege.

Da audit deve essere evidenziata come authority ad altissimo impatto.

Il fatto che sia dietro multisig/timelock riduce alcuni rischi, ma il blast radius resta enorme.

---

# 89. Preferire capacità specifiche

Meglio, quando possibile:

```solidity
setOracle(address)
setFee(uint256)
pause()
```

con bounds e ruoli specifici,

piuttosto che:

```solidity
executeAnything(target, data)
```

se non serve davvero.

API amministrative specifiche rendono più semplice:

```text
review
monitoring
invariant enforcement
```

---

# 90. Test negativi essenziali

Per ogni funzione privilegiata scrivi almeno:

```text
unauthorized caller -> revert
authorized caller -> success
boundary value -> expected behavior
```

Poi per governance temporale:

```text
schedule missing -> execute fails
too early -> fails
ready -> succeeds
cancelled -> fails
```

Per multisig:

```text
below threshold -> fails
threshold -> succeeds
duplicate signer -> doesn't count twice
```

---

# 91. Fuzzing futuro

Più avanti potremo fuzzare proprietà come:

```text
threshold <= owners.length
```

oppure sequenze:

```text
schedule
cancel
execute
reschedule
warp
```

L'invariant testing è particolarmente utile per governance perché lo stato è una macchina a stati con molte sequenze possibili.

---

# 92. Checklist da auditor — ownership

- [ ] chi è owner?
- [ ] EOA o contract?
- [ ] può cambiare?
- [ ] transfer è one-step o two-step?
- [ ] renounce è possibile?
- [ ] renounce può brickare il sistema?
- [ ] owner controlla asset?
- [ ] owner controlla upgrade?
- [ ] owner controlla oracle?
- [ ] owner controlla ruoli?

---

# 93. Checklist — multisig

- [ ] quanti owner?
- [ ] threshold?
- [ ] signer duplicati impossibili?
- [ ] threshold zero impossibile?
- [ ] threshold > owners impossible?
- [ ] signer realmente indipendenti?
- [ ] recovery se una chiave è persa?
- [ ] owner change richiede threshold?
- [ ] module/plugin aggiuntivi?
- [ ] arbitrary execution powers?
- [ ] quali contratti controlla?

Per un Safe reale vanno inoltre revisionati:

```text
owners
threshold
modules
guards
fallback handlers
```

secondo la configurazione effettiva.

---

# 94. Checklist — timelock

- [ ] minDelay?
- [ ] chi è proposer?
- [ ] chi è executor?
- [ ] executor aperto?
- [ ] chi è canceller?
- [ ] chi è admin?
- [ ] timelock self-admin?
- [ ] recovery path?
- [ ] updateDelay passa dal timelock?
- [ ] target ownership realmente al timelock?
- [ ] esistono bypass path?
- [ ] users possono uscire durante delay?
- [ ] monitoring delle scheduled operations?
- [ ] batch operations decodificate?

---

# 95. Checklist — emergency powers

- [ ] chi può pause?
- [ ] cosa viene pausato?
- [ ] withdrawal resta disponibile?
- [ ] chi può unpause?
- [ ] unpause ha delay?
- [ ] emergency role può cambiare codice?
- [ ] può cambiare oracle?
- [ ] può spostare fondi?
- [ ] ruolo revocabile?
- [ ] chi può revocarlo?

---

# 96. Checklist — role-based access control

- [ ] tutti i ruoli documentati?
- [ ] chi possiede ogni ruolo?
- [ ] role admin di ogni ruolo?
- [ ] DEFAULT_ADMIN_ROLE?
- [ ] può auto-amministrarsi?
- [ ] può concedere ruoli critici?
- [ ] esiste delay?
- [ ] role revocation testata?
- [ ] separation of duties reale?

---

# 97. Esercizi

## Esercizio 1 — Governance graph

Disegna un sistema con:

```text
3-of-5 multisig
Timelock 48h
Escrow UUPS
Emergency Pauser
```

Mostra ogni edge di authority.

---

## Esercizio 2 — Blast radius

Per:

```text
Pauser
Timelock
Multisig signer
Multisig quorum
Oracle admin
Upgrader
```

scrivi l'impatto della compromissione.

---

## Esercizio 3 — Timelock tests

Implementa:

```text
schedule
execute too early
execute exactly at boundary
execute after boundary
```

---

## Esercizio 4 — Cancel

Aggiungi test:

```text
schedule
cancel
warp
execute
=> revert
```

---

## Esercizio 5 — Fast pause / slow unpause

Verifica:

```text
security council -> pause immediata

security council -> unpause fallisce

timelock -> unpause dopo delay
```

---

## Esercizio 6 — Multisig threshold

Con 3 owners e threshold 2:

```text
1 approval -> fail
2 approvals -> success
3 approvals -> success
```

Poi imposta mentalmente:

```text
3-of-3
```

e descrivi il nuovo liveness risk.

---

## Esercizio 7 — Bypass hunting

Dato:

```text
setOracle onlyOwner
emergencySetOracle onlyGuardian
upgrade onlyUpgrader
```

supponi che `owner = Timelock`.

Rispondi:

> Quali cambiamenti possono ancora avvenire senza timelock?

---

## Esercizio 8 — Role graph

Costruisci:

```text
DEFAULT_ADMIN
  -> PAUSER_ROLE
  -> ORACLE_ROLE
  -> UPGRADER_ROLE
```

Poi modifica gli admin dei ruoli in modo che nessun singolo ruolo possa auto-elevarsi arbitrariamente.

---

## Esercizio 9 — Governance deadlock

Progetta una configurazione self-admin timelock in cui:

```text
l'unico proposer perde la chiave
```

Spiega perché il sistema si blocca.

Poi proponi un recovery design con il minimo privilegio possibile.

---

## Esercizio 10 — Audit challenge

Analizza:

```solidity
contract AdminPanel is Ownable {
    address public oracle;
    bool public paused;

    constructor(address owner_)
        Ownable(owner_)
    {}

    function execute(
        address target,
        bytes calldata data
    ) external onlyOwner {
        target.call(data);
    }

    function setOracle(
        address newOracle
    ) external onlyOwner {
        oracle = newOracle;
    }

    function pause()
        external onlyOwner
    {
        paused = true;
    }

    function unpause()
        external onlyOwner
    {
        paused = false;
    }
}
```

Trova almeno **12 domande da audit**.

Non correggere subito.

Analizza prima:

```text
authority
blast radius
bypass
low-level call
return value
timelock
multisig
pause scope
recovery
monitoring
ownership transfer
renounce
```

---

# 98. Cosa devo ricordare

## 1. `onlyOwner` protegge dall'account sbagliato, non da un owner compromesso

L'access control è solo il primo livello.

---

## 2. Un multisig trasforma single-key trust in threshold trust

Non rende il sistema trustless.

---

## 3. Un timelock aggiunge tempo, non giudizio

Una decisione malevola può restare malevola, ma diventa osservabile prima dell'esecuzione.

---

## 4. Per imporre davvero il timelock, il target deve essere controllato dal timelock

Non lasciare bypass amministrativi involontari.

---

## 5. Proposer, executor, canceller e admin sono poteri diversi

Analizzali separatamente.

---

## 6. Separation of duties limita il blast radius

Non dare automaticamente tutte le authority alla stessa chiave.

---

## 7. Emergency power deve essere minimo

Spesso:

```text
pause
```

è più sicuro di:

```text
arbitrary emergency upgrade
```

---

## 8. Safety e liveness sono in tensione

Una governance impossibile da compromettere ma anche impossibile da usare non è necessariamente un buon sistema.

---

## 9. Segui tutti i write path

Per ogni stato critico:

```text
chiunque possa modificarlo
```

fa parte del trust model.

---

## 10. Upgradeability è governance

Se puoi cambiare implementation, puoi spesso cambiare quasi tutte le regole future.

---

# 99. Collegamento con il corso

Ora la catena è:

```text
transactions
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
oracle/economic security
      |
      v
composability
      |
      v
proxy / delegatecall
      |
      v
GOVERNANCE
      |
      +--> owner
      +--> roles
      +--> multisig
      +--> timelock
      +--> emergency powers
```

Le prossime lezioni cambieranno prospettiva:

non aggiungeremo subito un nuovo grande componente al protocollo.

Approfondiremo invece **come dimostrare sistematicamente che le proprietà definite finora reggono**.

La Lezione 13 sarà dedicata al **testing approfondito**.

---

# 100. Fonti della lezione

Fonti tecniche consultate il **21 settembre 2026**:

1. **OpenZeppelin Contracts 5.x — Access Control**  
   Ownership, role-based access control, multisig come owner, `TimelockController`, ruoli proposer/executor e delayed operations.  
   https://docs.openzeppelin.com/contracts/5.x/access-control

2. **OpenZeppelin Contracts 5.x — Access API**  
   API correnti di `Ownable`, `Ownable2Step`, `AccessControl`, `AccessControlDefaultAdminRules`, `AccessManager` e `AccessManaged`.  
   https://docs.openzeppelin.com/contracts/5.x/api/access

3. **OpenZeppelin Contracts 5.x — Governance API**  
   `TimelockController`, operation lifecycle, ruoli, batch, delay e integrazione governance.  
   https://docs.openzeppelin.com/contracts/5.x/api/governance

4. **OpenZeppelin Contracts 5.x — Governance guide**  
   Configurazione del timelock con Governor, responsabilità di proposer/executor/canceller/admin e indicazioni sui ruoli.  
   https://docs.openzeppelin.com/contracts/5.x/governance

5. **Ethereum.org — Smart Contract Security**  
   Raccomandazioni su proper access control, role separation, multisig, emergency stop e governance/timelock.  
   https://ethereum.org/developers/docs/smart-contracts/security/

6. **Ethereum.org — Upgrading Smart Contracts**  
   Rischio di upgrade, multisig per ridurre trust assumptions e timelock per dare tempo agli utenti di reagire/uscire.  
   https://ethereum.org/developers/docs/smart-contracts/upgrading/

7. **Safe Documentation**  
   Documentazione ufficiale sul modello Safe Smart Account, owner e signature threshold.  
   https://docs.safe.global/

8. **OpenZeppelin Contracts 5.x Changelog**  
   Riferimento per il comportamento corrente di `Ownable`, incluso `initialOwner`, e per l'introduzione di `AccessManager` nella linea 5.x.  
   https://docs.openzeppelin.com/contracts/5.x/changelog

---

# Fine Lezione 12

Prossimo argomento:

**Testing approfondito con Foundry: test architecture, fixtures, revert precision, events, storage, prank/broadcast semantics, mocks, differential thinking, coverage e regression suites.**
