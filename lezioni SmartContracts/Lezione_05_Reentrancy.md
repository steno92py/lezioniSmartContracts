# Lezione 5 — Reentrancy: controllo esterno, stato incoerente, CEI e guard

> **Contesto del laboratorio**  
> Tutto ciò che segue è progettato esclusivamente per apprendimento, secure coding, auditing e testing. I contratti vulnerabili sono giocattoli creati appositamente per questa lezione e vanno eseguiti soltanto in locale con Foundry/Anvil, account di test e fondi fittizi. Non useremo fork di protocolli reali né contratti pubblici.

## 1. Obiettivi

Alla fine di questa lezione dovresti saper:

- spiegare **che cos'è la reentrancy** senza ridurla alla frase “una funzione viene chiamata due volte”;
- individuare il momento preciso in cui un contratto **cede il controllo** a codice esterno;
- capire perché lo stato osservabile durante una callback deve essere già coerente;
- distinguere almeno:
  - single-function reentrancy;
  - cross-function reentrancy;
  - cross-contract reentrancy;
- riconoscere il pattern vulnerabile **interaction prima dell'effect**;
- applicare correttamente **Checks-Effects-Interactions (CEI)**;
- capire cosa fa e cosa **non fa** un `ReentrancyGuard`;
- scrivere un test Foundry che riproduce una reentrancy **solo contro un contratto locale giocattolo**;
- trasformare un requisito contabile in una proprietà verificabile;
- aggiungere un test di regressione dopo la correzione;
- leggere una funzione con mentalità da auditor, chiedendoti non solo “chi la chiama?”, ma anche “chi può essere richiamato da lei prima che finisca?”.

Questa lezione estende direttamente la Lezione 4. Lì abbiamo introdotto `call` e il momento in cui il controllo passa a codice esterno. Qui vediamo cosa può accadere **durante quel passaggio di controllo**.

---

## 2. Modello mentale

Immagina un guardaroba con questa procedura:

1. controlli il biglietto del cliente;
2. gli consegni il cappotto;
3. **solo dopo** segni sul registro che il cappotto è stato ritirato.

Il problema non è semplicemente che il cliente “torna due volte”.

Il problema è che, dopo il punto 2 e prima del punto 3, il tuo registro dice ancora:

> questo cliente ha diritto a un cappotto.

Se la consegna del cappotto gli permette immediatamente di rientrare allo sportello prima che tu aggiorni il registro, il secondo controllo vede uno **stato vecchio ma ancora valido secondo il tuo programma**.

In uno smart contract, una chiamata esterna può creare esattamente questo intervallo:

```text
Contratto A
   |
   | controlla credito = 1 ETH
   |
   |---- invia 1 ETH ----> Contratto B
   |                        |
   |                        | callback
   |<--- richiama A --------|
   |
   | A vede ANCORA credito = 1 ETH
   |
   ...
   |
   | solo alla fine A mette credito = 0
```

La vulnerabilità nasce quindi da una combinazione:

```text
stato critico ancora valido
        +
controllo ceduto a codice esterno
        +
possibilità di rientrare
        =
reentrancy pericolosa
```

La domanda da auditor non è soltanto:

> “questa funzione fa una external call?”

ma:

> “nel momento della external call, quali invarianti sono temporaneamente falsi o quali diritti risultano ancora spendibili?”

Questa seconda domanda è molto più potente.

---

## 3. Teoria

### 3.1 Cosa significa davvero “reentrant”

Una funzione è **reentrant** quando, mentre una sua invocazione non è ancora terminata, il flusso di esecuzione torna nel contratto originario attraverso una nuova chiamata.

Non è necessario che venga richiamata la stessa funzione.

Esempio concettuale:

```text
A.withdraw()
   -> chiama B
      -> B richiama A.claimReward()
         -> A.claimReward() osserva stato intermedio
```

Questa è già una forma di reentrancy anche se `withdraw()` non viene chiamata una seconda volta.

La documentazione Solidity sottolinea che **qualsiasi interazione con un altro contratto** può trasferire il controllo, non soltanto il trasferimento di Ether. Questo è fondamentale: la reentrancy non è un problema esclusivo di `call{value: ...}`.

Può comparire quando interagisci con:

- contratti ERC-20 non completamente fidati;
- callback esplicite;
- token con hook;
- receiver ERC-721/ERC-1155;
- vault e adapter;
- contratti oracle o router;
- proxy/delegate patterns;
- qualunque funzione esterna che, direttamente o indirettamente, possa richiamarti.

### 3.2 La EVM usa un call stack

Quando il contratto A chiama B, A non “finisce” e poi B parte.

Più precisamente:

```text
frame A.withdraw()
    |
    +-- frame B.receive()
            |
            +-- frame A.withdraw()
                    |
                    +-- ...
```

Il primo frame di `A.withdraw()` resta sospeso in attesa del ritorno di B.

Se B richiama A, la nuova chiamata entra in un **nuovo frame**, ma legge lo stesso storage persistente di A.

Questo è il punto chiave.

Se il primo frame non ha ancora aggiornato `credits[msg.sender]`, il secondo frame legge ancora il valore precedente.

### 3.3 Atomicità della transazione non significa assenza di stati intermedi

Ethereum esegue una transazione atomicamente nel senso che, al termine:

- o le modifiche completate vengono committate;
- oppure un revert propagato può annullare le modifiche del relativo percorso di esecuzione.

Ma **durante** l'esecuzione esistono stati intermedi osservabili dalle chiamate annidate.

Quindi questa intuizione è errata:

> “nessun altro può intervenire finché la mia transazione non finisce”.

Un'altra transazione non si inserisce nel mezzo della tua transazione, ma **una chiamata annidata sì**.

La reentrancy avviene nella stessa transazione e nello stesso albero di chiamate.

### 3.4 Stato locale al frame vs storage del contratto

Considera:

```solidity
uint256 amount = credit[msg.sender];
(bool ok,) = msg.sender.call{value: amount}("");
credit[msg.sender] = 0;
```

`amount` è una variabile locale di quella specifica invocazione.

`credit[msg.sender]`, invece, vive nello storage del contratto.

Durante la external call:

- il primo frame conserva localmente `amount`;
- il mapping nello storage vale ancora il vecchio credito;
- una nuova invocazione può leggere proprio quello storage non ancora aggiornato.

### 3.5 Il vero problema: l'invariante è temporaneamente rotto

Supponiamo che il sistema prometta:

> ogni credito registrato deve essere coperto da Ether custodito dal contratto.

Formalmente, in un esempio semplice:

```text
address(this).balance >= totalCredits
```

Nel pattern vulnerabile:

1. `totalCredits` o il credito individuale è ancora registrato;
2. il contratto invia Ether;
3. il saldo ETH diminuisce;
4. il credito non è ancora diminuito.

Nel mezzo della funzione puoi quindi avere:

```text
balance < liabilities
```

La callback non crea magicamente il bug: **sfrutta una finestra in cui il contratto ha già prodotto un effetto esterno ma non ha ancora reso coerente il proprio accounting**.

Questa è una maniera molto più generale di riconoscere la reentrancy.

### 3.6 Single-function reentrancy

È la forma didatticamente più semplice:

```text
withdraw()
  -> external call
      -> withdraw()
```

La stessa funzione viene richiamata prima che la prima invocazione abbia completato l'aggiornamento dello stato.

### 3.7 Cross-function reentrancy

Il callback entra in una funzione diversa che condivide lo stesso stato.

Esempio concettuale:

```solidity
function withdraw() external {
    uint256 amount = credit[msg.sender];
    (bool ok,) = msg.sender.call{value: amount}("");
    credit[msg.sender] = 0;
}

function transferCredit(address to, uint256 amount) external {
    require(credit[msg.sender] >= amount);
    credit[msg.sender] -= amount;
    credit[to] += amount;
}
```

Se `withdraw()` effettua la call prima di azzerare il credito, il destinatario potrebbe tentare di rientrare attraverso `transferCredit()` e usare un credito che logicamente è già in fase di pagamento.

Un guard applicato soltanto a `withdraw()` non protegge automaticamente una seconda entry point se quella funzione non partecipa allo stesso locking model.

### 3.8 Cross-contract reentrancy

La situazione può coinvolgere più contratti:

```text
Vault A
  -> Adapter B
       -> Token/Hook C
            -> richiama Vault A
```

Oppure la callback modifica un altro contratto da cui A dipende.

Questo è uno dei motivi per cui l'auditing richiede un **call graph** e non una lettura funzione-per-funzione isolata.

### 3.9 Checks-Effects-Interactions

Il pattern CEI ordina la funzione in tre fasi:

```text
1. CHECKS
   verificare autorizzazioni, input e precondizioni

2. EFFECTS
   rendere coerente lo stato interno

3. INTERACTIONS
   chiamare il mondo esterno
```

Per un withdrawal:

```solidity
uint256 amount = credit[msg.sender];  // check/input derivation
if (amount == 0) revert NoCredit();   // check

credit[msg.sender] = 0;               // effect

(bool ok,) = msg.sender.call{value: amount}(""); // interaction
if (!ok) revert TransferFailed();
```

Durante la callback, una seconda invocazione vede già:

```text
credit[msg.sender] == 0
```

La cosa importante non è memorizzare “metti la call per ultima” come formula magica.

Devi chiederti:

> prima di cedere il controllo, ho consumato o invalidato tutti i diritti che questa operazione sta utilizzando?

### 3.10 “Ma se la call fallisce dopo che ho azzerato il credito?”

Ottima domanda.

Nel codice:

```solidity
credit[msg.sender] = 0;
(bool ok,) = msg.sender.call{value: amount}("");
if (!ok) revert TransferFailed();
```

se la call fallisce e il contratto esegue `revert`, il revert annulla anche l'`SSTORE` precedente nello stesso percorso transazionale.

Quindi il credito non resta perso.

La sequenza logica è:

```text
credito = amount
   ↓
credito = 0
   ↓
external call fallisce
   ↓
revert
   ↓
stato della chiamata viene ripristinato
   ↓
credito torna = amount
```

Questo è precisamente ciò che rende spesso naturale CEI in Solidity.

### 3.11 ReentrancyGuard

OpenZeppelin fornisce un modulo `ReentrancyGuard` che espone il modifier `nonReentrant`.

Concettualmente mantiene uno stato del tipo:

```text
NOT_ENTERED -> ENTERED -> NOT_ENTERED
```

Se una funzione protetta viene richiamata mentre il guard è già in stato `ENTERED`, la nuova invocazione viene rifiutata.

Uso concettuale:

```solidity
function withdraw() external nonReentrant {
    ...
}
```

Nella documentazione OpenZeppelin 5.x corrente, il path storage-based è:

```solidity
import {ReentrancyGuard} from
    "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
```

La documentazione corrente segnala inoltre `ReentrancyGuardTransient`, basato su transient storage, per reti in cui EIP-1153 è disponibile. Per questa lezione useremo il `ReentrancyGuard` classico perché rende il concetto più facilmente osservabile e resta una API chiara per il laboratorio.

> Nota di versione: nella documentazione OpenZeppelin 5.x corrente il `ReentrancyGuard` storage-based è indicato come deprecato in prospettiva della v6, a favore della variante transient dove supportata. Questo è un buon esempio del motivo per cui un auditor deve verificare la documentazione della **versione realmente usata dal progetto** e non ricordare a memoria un import di anni prima.

### 3.12 CEI e guard non sono equivalenti

CEI protegge soprattutto la **coerenza logica dello stato**.

Il guard protegge dall'**ingresso annidato nelle funzioni protette**.

In un contratto piccolo puoi spesso usare entrambi:

```text
CHECKS
EFFECTS
INTERACTION
+
nonReentrant come barriera aggiuntiva
```

Ma non devi arrivare alla conclusione:

> “ho messo `nonReentrant`, quindi non devo più ragionare sull'ordine dello stato”.

Un guard:

- non corregge accounting sbagliato;
- non corregge autorizzazioni errate;
- non protegge funzioni non incluse nel locking model;
- non impedisce che una external call provochi effetti pericolosi in contratti terzi;
- non sostituisce le invarianti;
- non rende automaticamente sicuro un protocollo composable.

### 3.13 Il caveat dei modifier `nonReentrant`

OpenZeppelin documenta che le funzioni protette dallo stesso `ReentrancyGuard` non possono normalmente chiamarsi direttamente l'una con l'altra come entry point `nonReentrant`, perché il lock è già attivo.

Una struttura tipica è:

```solidity
function withdraw() external nonReentrant {
    _withdraw(msg.sender);
}

function _withdraw(address user) private {
    // logica condivisa
}
```

In questo modo la barriera sta sull'entry point esterna e la logica interna non tenta di acquisire nuovamente il lock.

---

## 4. Esempio Solidity: contratto vulnerabile minimo

Creiamo intenzionalmente un piccolo vault locale.

**Non è codice production-ready. È vulnerabile apposta.**

File:

```text
src/reentrancy/VulnerableVault.sol
```

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract VulnerableVault {
    mapping(address user => uint256 amount) public credit;
    uint256 public totalCredits;

    error ZeroDeposit();
    error NoCredit();
    error TransferFailed();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        credit[msg.sender] += msg.value;
        totalCredits += msg.value;
    }

    function withdraw() external {
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        // VULNERABILE:
        // cediamo il controllo prima di consumare il credito.
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        // Troppo tardi: durante la callback il credito era ancora valido.
        credit[msg.sender] = 0;
        totalCredits -= amount;
    }
}
```

Il bug è piccolo ma concettualmente profondo:

```text
CHECKS
INTERACTION   <-- controllo esterno mentre il diritto è ancora valido
EFFECTS
```

invece di:

```text
CHECKS
EFFECTS
INTERACTION
```

---

## 5. Analisi del codice

### 5.1 `deposit()`

```solidity
function deposit() external payable
```

**Chi può chiamarla?**  
Qualunque account o contratto.

**Quali input controlla il chiamante?**

- `msg.sender` indirettamente, scegliendo quale account/contratto invia la transazione o effettua la call;
- `msg.value`;
- il momento in cui deposita.

**Quale valore entra?**  
Ether pari a `msg.value`.

**Quale stato viene letto?**

- `credit[msg.sender]`;
- `totalCredits`.

**Quale stato viene modificato?**

```solidity
credit[msg.sender] += msg.value;
totalCredits += msg.value;
```

**Chiamate esterne?**  
Nessuna.

**Assunzioni?**

- ogni wei accettato viene registrato sia nel credito individuale sia nelle passività totali;
- non esistono altre funzioni che modificano questi valori in modo incoerente.

### 5.2 `withdraw()` vulnerabile

```solidity
function withdraw() external
```

**Chi può chiamarla?**  
Qualunque address con credito.

Questo include **contratti**, non soltanto utenti umani.

**Quali input controlla il chiamante?**

Non esistono parametri ABI espliciti, ma il chiamante controlla qualcosa di molto importante:

```text
il codice eseguito da msg.sender quando riceve Ether
```

Se `msg.sender` è un contratto, il suo `receive()` o `fallback()` può eseguire codice.

**Quale valore entra?**  
Nessun `msg.value` previsto; la funzione invia valore verso l'esterno.

**Quale stato viene letto?**

```solidity
credit[msg.sender]
```

**Quale stato viene modificato?**

```solidity
credit[msg.sender] = 0;
totalCredits -= amount;
```

Ma queste modifiche accadono soltanto **dopo** l'interazione.

**Quali chiamate esterne vengono effettuate?**

```solidity
msg.sender.call{value: amount}("")
```

**Quando passa il controllo all'esterno?**  
Esattamente in quella riga.

Il contratto chiamato può eseguire codice prima che `call` restituisca.

**Quali assunzioni implicite sono pericolose?**

Il codice si comporta come se presumesse:

> “dopo aver inviato Ether, tornerò subito alla riga successiva senza che nessuno possa usare nuovamente questo credito”.

Questa assunzione è falsa.

### 5.3 Traccia concreta di una chiamata reentrante

Supponiamo:

```text
Vault balance:        5 ETH
credit[attacker]:     1 ETH
totalCredits:         5 ETH
```

L'attacker contract chiama `withdraw()`.

Primo frame:

```text
amount = 1 ETH
credit[attacker] = 1 ETH
```

Il vault invia 1 ETH.

Prima di eseguire:

```solidity
credit[msg.sender] = 0;
```

il `receive()` dell'attacker richiama `withdraw()`.

Il secondo frame legge ancora:

```text
credit[attacker] = 1 ETH
```

Quindi un diritto che doveva essere consumato una sola volta risulta ancora spendibile.

Il pattern può ripetersi finché ci sono fondi e gas sufficienti oppure fino al limite scelto dal nostro contratto giocattolo.

---

## 6. Proprietà e invarianti

Prima di scrivere il contratto di test, definiamo cosa dovrebbe garantire il vault.

### Proprietà P1 — un credito non è riutilizzabile durante il payout

> Una volta iniziato il pagamento di un credito, nessuna callback deve poter spendere nuovamente quello stesso credito.

### Proprietà P2 — solvibilità contabile

Nel modello giocattolo, se tutto l'Ether è entrato tramite `deposit()`:

```text
address(vault).balance >= totalCredits
```

Idealmente, nel nostro modello semplificato senza Ether forzato e senza altre fonti:

```text
address(vault).balance == totalCredits
```

Ma per auditing reale è spesso più robusto formulare la proprietà come copertura delle passività:

```text
assets >= liabilities
```

perché il balance può crescere anche per ragioni non contabilizzate separatamente.

### Proprietà P3 — withdrawal singolo

> Dopo un withdrawal riuscito, `credit[user] == 0`.

Questa proprietà da sola **non basta**.

Sul contratto vulnerabile, alla fine dell'intera transazione il credito può risultare comunque zero anche se il contratto ha già pagato più volte.

È un punto importantissimo:

> una post-condition locale può risultare vera mentre una proprietà economica globale è stata violata.

### Proprietà P4 — conservazione del valore contabilizzato

Per un singolo utente, se non esistono nuovi depositi:

```text
payout totale dell'utente <= credito legittimamente assegnato
```

### Proprietà P5 — callback-safe accounting

> Ogni stato osservabile durante una external call deve già rappresentare il fatto che il credito corrente è stato consumato.

Questa non è soltanto una proprietà “alla fine della transazione”: riguarda lo stato in corrispondenza di un **interaction boundary**.

---

## 7. Laboratorio Foundry

### 7.1 Prerequisiti

Assumiamo un progetto Foundry già disponibile dalle lezioni precedenti.

Per un progetto nuovo:

```bash
forge init solidity-security-course
cd solidity-security-course
```

Verifica:

```bash
forge --version
```

Per questa lezione usiamo:

```solidity
pragma solidity 0.8.37;
```

Solidity 0.8.37 è stato pubblicato il 10 settembre 2026 ed è una bugfix release con correzioni di sicurezza rilevanti rispetto alle versioni precedenti.

### 7.2 Struttura dei file

```text
solidity-security-course/
├── foundry.toml
├── lib/
│   └── forge-std/
├── src/
│   └── reentrancy/
│       ├── VulnerableVault.sol
│       ├── SafeVaultCEI.sol
│       └── SafeVaultGuarded.sol
└── test/
    └── reentrancy/
        └── Reentrancy.t.sol
```

### 7.3 Contratto vulnerabile

`src/reentrancy/VulnerableVault.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract VulnerableVault {
    mapping(address user => uint256 amount) public credit;
    uint256 public totalCredits;

    error ZeroDeposit();
    error NoCredit();
    error TransferFailed();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        credit[msg.sender] += msg.value;
        totalCredits += msg.value;
    }

    function withdraw() external {
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        credit[msg.sender] = 0;
        totalCredits -= amount;
    }
}
```

### 7.4 Contratto di laboratorio che provoca la callback

Non è un “exploit” da usare su sistemi reali. È una fixture locale destinata esclusivamente a dimostrare il comportamento del contratto vulnerabile creato sopra.

Lo inseriamo direttamente nel file di test.

```solidity
interface IVault {
    function deposit() external payable;
    function withdraw() external;
}

contract LocalReentrantReceiver {
    IVault public immutable vault;
    uint256 public callbacks;
    uint256 public immutable maxCallbacks;

    constructor(IVault _vault, uint256 _maxCallbacks) {
        vault = _vault;
        maxCallbacks = _maxCallbacks;
    }

    function depositIntoVault() external payable {
        vault.deposit{value: msg.value}();
    }

    function startWithdrawal() external {
        vault.withdraw();
    }

    receive() external payable {
        // Limite artificiale: manteniamo il laboratorio piccolo e deterministico.
        if (callbacks < maxCallbacks && address(vault).balance >= 1 ether) {
            callbacks++;
            vault.withdraw();
        }
    }
}
```

Osserva un dettaglio importante:

```solidity
receive() external payable {
    ...
    vault.withdraw();
}
```

Quando il vault esegue:

```solidity
msg.sender.call{value: amount}("")
```

il `msg.sender` è `LocalReentrantReceiver`.

Il receiver ottiene il controllo e può quindi eseguire una nuova chiamata verso il vault.

### 7.5 Test completo del comportamento vulnerabile

`test/reentrancy/Reentrancy.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {VulnerableVault} from "../../src/reentrancy/VulnerableVault.sol";

interface IVault {
    function deposit() external payable;
    function withdraw() external;
}

contract LocalReentrantReceiver {
    IVault public immutable vault;
    uint256 public callbacks;
    uint256 public immutable maxCallbacks;

    constructor(IVault _vault, uint256 _maxCallbacks) {
        vault = _vault;
        maxCallbacks = _maxCallbacks;
    }

    function depositIntoVault() external payable {
        vault.deposit{value: msg.value}();
    }

    function startWithdrawal() external {
        vault.withdraw();
    }

    receive() external payable {
        if (callbacks < maxCallbacks && address(vault).balance >= 1 ether) {
            callbacks++;
            vault.withdraw();
        }
    }
}

contract ReentrancyTest is Test {
    VulnerableVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vault = new VulnerableVault();

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_NormalWithdrawWorks() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        uint256 beforeBalance = alice.balance;

        vm.prank(alice);
        vault.withdraw();

        assertEq(vault.credit(alice), 0);
        assertEq(alice.balance, beforeBalance + 1 ether);
        assertEq(address(vault).balance, 0);
        assertEq(vault.totalCredits(), 0);
    }

    function test_ReentrantCallbackBreaksAccounting() public {
        // Quattro depositanti onesti lasciano 4 ETH nel vault.
        address[4] memory users = [
            makeAddr("u1"),
            makeAddr("u2"),
            makeAddr("u3"),
            makeAddr("u4")
        ];

        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 1 ether);
            vm.prank(users[i]);
            vault.deposit{value: 1 ether}();
        }

        // Il receiver locale deposita soltanto 1 ETH di credito legittimo.
        LocalReentrantReceiver receiver =
            new LocalReentrantReceiver(IVault(address(vault)), 4);

        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{value: 1 ether}();

        assertEq(address(vault).balance, 5 ether);
        assertEq(vault.credit(address(receiver)), 1 ether);
        assertEq(vault.totalCredits(), 5 ether);

        // La callback rientra nel contratto vulnerabile.
        receiver.startWithdrawal();

        // Il receiver possedeva 1 ETH di credito,
        // ma ha ricevuto ripetutamente lo stesso pagamento.
        assertGt(address(receiver).balance, 1 ether);

        // Nel caso scelto, il vault viene svuotato.
        assertEq(address(vault).balance, 0);

        // Eppure parte delle passività degli utenti onesti resta registrata.
        assertGt(vault.totalCredits(), address(vault).balance);
    }
}
```

### 7.6 Perché questo test è più utile di `assertEq(receiver.balance, 5 ether)`

Un test scritto solo sull'importo esatto può essere fragile rispetto a dettagli del fixture.

La proprietà importante è:

```solidity
assertGt(address(receiver).balance, 1 ether);
```

Il receiver aveva diritto a 1 ETH; riceverne di più dimostra il riutilizzo del credito.

E ancora più importante:

```solidity
assertGt(vault.totalCredits(), address(vault).balance);
```

Questo mostra la violazione economica globale:

```text
liabilities > assets
```

Il contratto non è più in grado di onorare ciò che il suo stesso storage promette.

### 7.7 Esecuzione

```bash
forge test --match-path test/reentrancy/Reentrancy.t.sol -vv
```

Per una trace più dettagliata:

```bash
forge test \
  --match-test test_ReentrantCallbackBreaksAccounting \
  -vvvv
```

Nella trace cerca una struttura concettualmente simile a:

```text
VulnerableVault.withdraw()
  -> LocalReentrantReceiver.receive()
      -> VulnerableVault.withdraw()
          -> LocalReentrantReceiver.receive()
              -> VulnerableVault.withdraw()
                  ...
```

Quella forma annidata è il fenomeno che stiamo studiando.

---

## 8. Test negativi

Un corso di security non può fermarsi al test “deposito e ritiro funzionano”.

### 8.1 Zero deposit deve fallire

```solidity
function test_RevertWhen_DepositIsZero() public {
    vm.prank(alice);
    vm.expectRevert(VulnerableVault.ZeroDeposit.selector);
    vault.deposit{value: 0}();
}
```

### 8.2 Withdrawal senza credito deve fallire

```solidity
function test_RevertWhen_NoCredit() public {
    vm.prank(alice);
    vm.expectRevert(VulnerableVault.NoCredit.selector);
    vault.withdraw();
}
```

### 8.3 Un secondo withdrawal normale deve fallire

```solidity
function test_RevertWhen_WithdrawnTwiceSequentially() public {
    vm.prank(alice);
    vault.deposit{value: 1 ether}();

    vm.prank(alice);
    vault.withdraw();

    vm.prank(alice);
    vm.expectRevert(VulnerableVault.NoCredit.selector);
    vault.withdraw();
}
```

Questo test passa persino sul contratto vulnerabile.

Ed è proprio qui una lezione metodologica:

```text
withdraw #1 finisce
↓
credito viene azzerato
↓
withdraw #2 in una chiamata successiva fallisce
```

Il bug non vive tra due transazioni separate.

Vive **dentro la prima**, prima che `withdraw #1` abbia terminato.

Quindi il test sequenziale non copre la proprietà di callback-safety.

---

## 9. Vulnerabilità e correzione

## 9.1 Versione vulnerabile

La sequenza è:

```solidity
uint256 amount = credit[msg.sender];
if (amount == 0) revert NoCredit();

(bool ok,) = msg.sender.call{value: amount}(""); // INTERACTION
if (!ok) revert TransferFailed();

credit[msg.sender] = 0;                           // EFFECT
```

Il diritto viene consumato dopo l'uso.

## 9.2 Correzione 1: CEI

`src/reentrancy/SafeVaultCEI.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract SafeVaultCEI {
    mapping(address user => uint256 amount) public credit;
    uint256 public totalCredits;

    error ZeroDeposit();
    error NoCredit();
    error TransferFailed();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        credit[msg.sender] += msg.value;
        totalCredits += msg.value;
    }

    function withdraw() external {
        // CHECKS
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        // EFFECTS
        credit[msg.sender] = 0;
        totalCredits -= amount;

        // INTERACTIONS
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
```

Durante la callback:

```text
credit[receiver] == 0
```

Quindi una nuova `withdraw()` incontra:

```solidity
if (amount == 0) revert NoCredit();
```

### 9.3 Un dettaglio sottile: la callback può far fallire tutto il payout

Nel nostro primo `LocalReentrantReceiver`, il `receive()` tenta direttamente:

```solidity
vault.withdraw();
```

Contro `SafeVaultCEI`, la chiamata reentrant reverte con `NoCredit()`.

Se quel revert non viene catturato dal receiver, allora reverte anche `receive()`, la low-level call del vault restituisce `false` e il vault reverte `TransferFailed()`.

Questo non è furto, ma può essere un comportamento scomodo per il test.

Per verificare bene la remediation, usiamo un receiver che **cattura** il fallimento della reentrancy.

```solidity
contract LocalReentrantProbe {
    IVault public immutable vault;
    bool public attemptedReentry;
    bool public reentrySucceeded;

    constructor(IVault _vault) {
        vault = _vault;
    }

    function depositIntoVault() external payable {
        vault.deposit{value: msg.value}();
    }

    function startWithdrawal() external {
        vault.withdraw();
    }

    receive() external payable {
        if (!attemptedReentry) {
            attemptedReentry = true;

            (bool ok,) = address(vault).call(
                abi.encodeCall(IVault.withdraw, ())
            );

            reentrySucceeded = ok;
        }
    }
}
```

Questo receiver osserva:

```text
il callback è avvenuto?
il tentativo di reentry è riuscito?
```

senza trasformare automaticamente il fallimento della chiamata reentrant in fallimento del payout principale.

### 9.4 Test di regressione CEI

Aggiungiamo l'import:

```solidity
import {SafeVaultCEI} from "../../src/reentrancy/SafeVaultCEI.sol";
```

Poi:

```solidity
function test_CEI_PreventsReuseOfCredit() public {
    SafeVaultCEI safe = new SafeVaultCEI();

    // Aggiungiamo liquidità appartenente ad altri utenti.
    address u1 = makeAddr("safe-u1");
    address u2 = makeAddr("safe-u2");

    vm.deal(u1, 1 ether);
    vm.deal(u2, 1 ether);

    vm.prank(u1);
    safe.deposit{value: 1 ether}();

    vm.prank(u2);
    safe.deposit{value: 1 ether}();

    LocalReentrantProbe receiver =
        new LocalReentrantProbe(IVault(address(safe)));

    vm.deal(address(this), 1 ether);
    receiver.depositIntoVault{value: 1 ether}();

    assertEq(address(safe).balance, 3 ether);
    assertEq(safe.credit(address(receiver)), 1 ether);

    receiver.startWithdrawal();

    // La callback è stata realmente tentata.
    assertTrue(receiver.attemptedReentry());

    // Ma non ha potuto riutilizzare il credito.
    assertFalse(receiver.reentrySucceeded());

    // Il receiver riceve esattamente il proprio credito.
    assertEq(address(receiver).balance, 1 ether);

    // Restano coperti i 2 ETH degli altri depositanti.
    assertEq(address(safe).balance, 2 ether);
    assertEq(safe.totalCredits(), 2 ether);
    assertEq(address(safe).balance, safe.totalCredits());
}
```

Questa è la **regressione** che vogliamo mantenere.

Non testiamo semplicemente che la funzione “funzioni”.

Testiamo esplicitamente che il vecchio scenario patologico non rompa più la proprietà.

---

## 9.5 Correzione 2: CEI + OpenZeppelin ReentrancyGuard

Per usare OpenZeppelin Contracts in Foundry, la documentazione corrente raccomanda di installare una release pubblicata/taggata e configurare il remapping, evitando di basarsi sul branch di sviluppo come dipendenza di produzione.

Per il laboratorio:

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

`remappings.txt`:

```text
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
```

> Per un progetto reale, **pin della versione**, review del lock/dependency state e policy di upgrade sono parte del threat model della supply chain. Qui ci interessa il meccanismo didattico.

`src/reentrancy/SafeVaultGuarded.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ReentrancyGuard} from
    "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SafeVaultGuarded is ReentrancyGuard {
    mapping(address user => uint256 amount) public credit;
    uint256 public totalCredits;

    error ZeroDeposit();
    error NoCredit();
    error TransferFailed();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        credit[msg.sender] += msg.value;
        totalCredits += msg.value;
    }

    function withdraw() external nonReentrant {
        // CHECKS
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        // EFFECTS
        credit[msg.sender] = 0;
        totalCredits -= amount;

        // INTERACTIONS
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
```

Nota la scelta intenzionale:

```solidity
nonReentrant
+
CEI
```

Non abbiamo spostato di nuovo gli effects dopo la call solo perché “tanto c'è il guard”.

Manteniamo lo stato logicamente coerente **e** aggiungiamo una barriera di reentry.

### 9.6 Test di regressione con il guard

```solidity
import {SafeVaultGuarded} from
    "../../src/reentrancy/SafeVaultGuarded.sol";
```

Test:

```solidity
function test_GuardAndCEI_BlockReentry() public {
    SafeVaultGuarded safe = new SafeVaultGuarded();

    address u1 = makeAddr("guard-u1");
    vm.deal(u1, 2 ether);

    vm.prank(u1);
    safe.deposit{value: 2 ether}();

    LocalReentrantProbe receiver =
        new LocalReentrantProbe(IVault(address(safe)));

    vm.deal(address(this), 1 ether);
    receiver.depositIntoVault{value: 1 ether}();

    receiver.startWithdrawal();

    assertTrue(receiver.attemptedReentry());
    assertFalse(receiver.reentrySucceeded());

    assertEq(address(receiver).balance, 1 ether);
    assertEq(safe.credit(address(receiver)), 0);

    assertEq(address(safe).balance, 2 ether);
    assertEq(safe.totalCredits(), 2 ether);
}
```

---

## 9.7 Prima e dopo

### Vulnerabile

```text
withdraw()
│
├─ CHECK credito = 1 ETH
│
├─ CALL 1 ETH ────────────────┐
│                             │
│                        receive()
│                             │
│                        withdraw()
│                             │
│                 credito è ANCORA 1 ETH
│                             │
│                        CALL ancora
│                             │
└─ EFFECT credito = 0 <───────┘
```

### Corretto con CEI

```text
withdraw()
│
├─ CHECK credito = 1 ETH
│
├─ EFFECT credito = 0
│
├─ CALL 1 ETH ────────────────┐
│                             │
│                        receive()
│                             │
│                        withdraw()
│                             │
│                    credito == 0
│                             │
│                       REVERT
│                             │
└─ ritorno <──────────────────┘
```

### Corretto con CEI + guard

```text
withdraw() [lock = ENTERED]
│
├─ CHECK
├─ EFFECT
├─ CALL ──────────────────────┐
│                             │
│                        receive()
│                             │
│                        withdraw()
│                             │
│                    guard già ENTERED
│                             │
│                       REVERT
│                             │
└─ unlock <───────────────────┘
```

---

## 9.8 Non usare `transfer()` come “fix della reentrancy”

Storicamente molti esempi suggerivano `transfer()` perché inoltrava un gas stipend limitato.

Questa non è una buona strategia moderna di sicurezza.

La sicurezza del protocollo non dovrebbe dipendere dal presupposto:

> “al destinatario non resterà abbastanza gas per fare qualcosa di interessante”.

I costi degli opcode e le caratteristiche della piattaforma possono evolvere. La lezione precedente ha già introdotto il motivo per cui oggi si preferisce ragionare esplicitamente su:

- external call;
- stato coerente;
- gestione del fallimento;
- CEI;
- guard quando appropriato.

Il problema va corretto a livello di **logica e invarianti**, non sperando che il callee sia artificialmente incapace di eseguire codice.

---

## 9.9 La reentrancy non richiede necessariamente Ether

Considera:

```solidity
externalProtocol.execute(...);
```

Se `externalProtocol` può richiamare il tuo contratto, c'è un interaction boundary.

Oppure:

```solidity
token.safeTransfer(to, amount);
```

A seconda dello standard, dell'implementazione e della catena di chiamate coinvolta, una apparentemente semplice operazione token può condurre a callback o codice esterno.

La regola mentale deve essere:

```text
external control flow != soltanto ETH transfer
```

Quando fai audit, costruisci la lista di tutte le interazioni esterne.

---

## 9.10 Read-only reentrancy: anticipazione concettuale

Non approfondiamo ancora scenari DeFi complessi, ma devi conoscere l'idea.

Una callback può osservare un contratto mentre alcune variabili sono state aggiornate e altre no.

Anche una funzione `view` può quindi restituire un valore economicamente incoerente durante una fase intermedia; un altro componente potrebbe usare quell'osservazione per prendere una decisione.

Il punto non è “la funzione view modifica lo stato”.

Il punto è:

> la funzione view può **osservare** uno stato transitorio non destinato a essere una rappresentazione valida del sistema.

Questo rafforza ancora una volta la regola fondamentale:

> prima di una external call, rendi coerente l'intero insieme di stato che altri componenti possono osservare.

---

## 9.11 Perché un mutex applicato male può essere insufficiente

Immagina:

```solidity
function withdraw() external nonReentrant {
    ...
}

function claimBonus() external {
    ...
}
```

Se `claimBonus()` legge o modifica lo stesso stato economico vulnerabile ed è raggiungibile durante la callback, proteggere soltanto `withdraw()` può non essere sufficiente.

Quindi quando trovi `nonReentrant`, non smettere l'audit.

Chiedi:

```text
Qual è la risorsa protetta dal lock?
Quali entry point toccano quella risorsa?
Quali di queste sono raggiungibili durante una callback?
Il lock copre davvero il dominio di stato corretto?
```

Questa è la differenza tra riconoscere un modifier e capire una proprietà di sicurezza.

---

## 10. Checklist da auditor

Quando incontri una funzione che effettua chiamate esterne, usa questa checklist compatta.

1. **Dove passa il controllo?**  
   Segna ogni call esterna, invio di Ether, callback, token hook, receiver hook o chiamata indiretta.

2. **Quale stato è ancora “spendibile”?**  
   Prima della call esistono credit, allowance interne, nonce, claim, reward, quote o flag non ancora consumati?

3. **CEI è realmente rispettato?**  
   Non guardare l'ordine estetico delle righe: verifica che *tutti* gli effetti necessari alla coerenza siano completati prima dell'interazione.

4. **Quali funzioni sono raggiungibili in callback?**  
   Cerca single-function e cross-function reentrancy.

5. **Esistono dipendenze cross-contract?**  
   Una callback può modificare un contratto da cui questa funzione legge prezzi, accounting o autorizzazioni?

6. **Il destinatario è davvero trusted?**  
   Anche una dipendenza nota può chiamare codice non noto a valle.

7. **C'è un `nonReentrant`?**  
   Se sì, quali entry point protegge? Condividono il medesimo lock? Esistono percorsi non protetti sullo stesso stato?

8. **Gli invarianti valgono durante l'interaction boundary?**  
   Non limitarti allo stato finale della transazione.

9. **Il fallimento della call è gestito correttamente?**  
   Cosa succede se il destinatario reverte?

10. **Esiste un test con receiver contrattuale?**  
    Testare soltanto EOA può lasciare invisibile il comportamento delle callback.

11. **La solvibilità è testata come proprietà globale?**  
    Per vault/escrow chiediti se assets e liabilities restano coerenti.

12. **La remediation ha un test di regressione?**  
    Una vulnerabilità corretta senza test può essere reintrodotta in futuro.

---

## 11. Esercizi

Non trovi le soluzioni qui: chiedimele quando vuoi confrontare il tuo lavoro.

### Esercizio 1 — Ricostruisci la trace

Per il `VulnerableVault`, scrivi a mano la sequenza dei valori per tre livelli di chiamata:

```text
frame
vault.balance
credit[receiver]
totalCredits
receiver.balance
```

Indica esattamente in quale riga ciascun valore cambia.

### Esercizio 2 — Trova il bug senza eseguire il codice

Analizza:

```solidity
function claim() external {
    uint256 reward = rewards[msg.sender];
    require(reward > 0);

    rewardToken.transfer(msg.sender, reward);
    rewards[msg.sender] = 0;
}
```

Senza assumere nulla sulla specifica implementazione di `rewardToken`, rispondi:

- qual è l'interaction boundary?
- quale diritto è ancora valido in quel momento?
- come riordineresti la funzione?
- quali assunzioni sul token dovresti documentare?

### Esercizio 3 — Cross-function

Aggiungi al vault vulnerabile:

```solidity
function moveCredit(address to, uint256 amount) external {
    if (credit[msg.sender] < amount) revert();
    credit[msg.sender] -= amount;
    credit[to] += amount;
}
```

Progetta **solo in locale** un test che dimostri se il callback di `withdraw()` può interagire con `moveCredit()` mentre il credito è ancora stale.

Prima di scrivere il test, formula la proprietà che vuoi dimostrare.

### Esercizio 4 — Receiver che reverte

Crea un contratto locale:

```solidity
receive() external payable {
    revert("no ETH");
}
```

Verifica che `SafeVaultCEI.withdraw()`:

- revirti;
- non perda il credito;
- non decrementi permanentemente `totalCredits`.

Spiega perché.

### Esercizio 5 — Regression test minimo

Scrivi il test più piccolo possibile che fallisce su `VulnerableVault` e passa su `SafeVaultCEI`, usando una proprietà economica e non un valore arbitrario del callback counter.

### Esercizio 6 — Threat model

Per `SafeVaultGuarded`, compila questa tabella:

```text
Asset:
Attori:
Trust boundary:
External calls:
Stato critico:
Proprietà da preservare:
Fallimenti ammessi:
Fallimenti non ammessi:
```

### Esercizio 7 — Guard scope

Aggiungi una seconda funzione che legge/modifica `credit`.

Decidi se deve essere protetta dallo stesso locking model.

Non partire dal modifier: parti dalla domanda “può questa funzione osservare o modificare stato transitorio durante un callback?”.

### Esercizio 8 — Test parametrico

Trasforma il test di solvibilità in un fuzz test semplice variando:

```text
credito del receiver
liquidità degli altri utenti
numero massimo di callback del fixture
```

Usa bound ragionevoli per evitare casi irrilevanti o overflow di fondi di test.

Non serve ancora creare una vera invariant test suite: lo faremo nella parte dedicata del corso.

---

## 12. Cosa devo ricordare

Se devi conservare pochi concetti da questa lezione, conserva questi:

**1. Una external call trasferisce controllo.**  
Il chiamato può eseguire codice e, direttamente o indirettamente, richiamarti prima che la prima funzione sia terminata.

**2. Reentrancy non significa soltanto “richiamare la stessa funzione”.**  
Può essere single-function, cross-function o cross-contract.

**3. Cerca diritti ancora validi al momento della call.**  
Credit, claim, reward, nonce logici, quote e accounting devono essere consumati o resi coerenti prima di cedere il controllo.

**4. CEI è prima di tutto un principio di coerenza.**  
Checks → Effects → Interactions significa che il mondo esterno deve osservare uno stato già consistente.

**5. `nonReentrant` è una barriera, non una prova di correttezza.**  
Devi ancora analizzare accounting, scope del lock, altre entry point e dipendenze esterne.

**6. Testa contratti come caller, non soltanto EOA.**  
Molte proprietà di sicurezza emergono soltanto quando `msg.sender` può eseguire una callback.

**7. Una post-condition locale può ingannarti.**  
`credit[user] == 0` alla fine non dimostra che non siano avvenuti payout multipli. Le proprietà economiche globali sono spesso più importanti.

**8. Dopo ogni fix, conserva il controesempio come regression test.**  
Il workflow del corso resta:

```text
requisito
   ↓
proprietà
   ↓
implementazione
   ↓
test
   ↓
controesempio locale
   ↓
remediation
   ↓
regression test
```

---

## 13. Fonti della lezione

Fonti tecniche effettivamente consultate per preparare questa lezione:

1. **Solidity Documentation — Security Considerations / Reentrancy / Checks-Effects-Interactions**  
   https://docs.soliditylang.org/en/latest/security-considerations.html  
   Riferimento principale per il modello di reentrancy, il trasferimento di controllo nelle chiamate esterne e il pattern CEI.

2. **Solidity 0.8.37 Release Announcement — Solidity Team, 10 settembre 2026**  
   https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/  
   Consultata per verificare la versione corrente usata negli esempi e le correzioni recenti del compilatore.

3. **OpenZeppelin Contracts 5.x — Utils / ReentrancyGuard**  
   https://docs.openzeppelin.com/contracts/5.x/api/utils  
   Consultata per API corrente, import path di `ReentrancyGuard`, comportamento di `nonReentrant` e variante `ReentrancyGuardTransient`.

4. **OpenZeppelin Contracts 5.x — installazione e uso con Foundry**  
   https://docs.openzeppelin.com/contracts/5.x  
   Consultata per il path/remapping corrente e le raccomandazioni sulle release pubblicate.

5. **Foundry — Writing Tests**  
   https://getfoundry.sh/forge/writing-tests  
   Consultata per struttura e convenzioni dei test Forge.

6. **Foundry — `expectRevert` cheatcode**  
   https://getfoundry.sh/cheatcodes/expect-revert  
   Consultata per il comportamento corrente dei test negativi con revert.

7. **OWASP Smart Contract Security — SCWE-046: Reentrancy Attacks**  
   https://scs.owasp.org/SCWE/SCSVS-CODE/SCWE-046/  
   Consultata per classificazione, cause tipiche e remediation aggiornate.

8. **OWASP Smart Contract Security Top 10 2026 — Reentrancy**  
   https://scs.owasp.org/sctop10/SC08-ReentrancyAttacks/  
   Consultata per le categorie single-function, cross-function e cross-contract e per il framing moderno della vulnerabilità.

---

## Fine Lezione 5

Fermati qui. Prima della lezione successiva dovresti essere in grado di guardare una external call e chiederti immediatamente:

> **quale stato può osservare o riutilizzare una callback in questo preciso momento?**

