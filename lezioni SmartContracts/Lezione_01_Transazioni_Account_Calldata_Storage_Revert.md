# Smart Contract Security / Solidity Security
## Lezione 1 — Transazioni, account, `msg.sender`, `msg.value`, calldata, storage e revert

> **Ambiente del corso:** esclusivamente didattico, difensivo e locale. Tutti gli esempi sono contratti giocattolo, account di test e fondi fittizi. Non useremo protocolli reali, wallet reali, fork di mainnet o sistemi di terzi in questa lezione.
>
> **Baseline verificata il 21 settembre 2026:** gli esempi sono scritti per **Solidity 0.8.37**, release stabile pubblicata il 10 settembre 2026. Per riproducibilità, nel laboratorio pinniamo esplicitamente questa versione del compilatore.

---

## 1. Obiettivi

Alla fine della lezione dovresti saper leggere una funzione Solidity e rispondere con precisione a queste domande:

- da dove nasce l'esecuzione: transazione top-level, message call o chiamata interna;
- chi è il chiamante visto dal frame corrente e quindi cosa significa davvero `msg.sender`;
- quanta Ether è associata alla chiamata corrente tramite `msg.value`;
- quali dati controlla il chiamante tramite i parametri ABI e `msg.data`;
- cosa finisce in `calldata` e perché questa area è diversa da `memory` e `storage`;
- quali informazioni persistono tra una transazione e la successiva perché sono scritte in `storage`;
- cosa accade allo stato quando l'esecuzione fa `revert`;
- come trasformare requisiti semplici in proprietà verificabili e test negativi;
- come usare Foundry per simulare chiamanti diversi, assegnare fondi fittizi e verificare revert attesi.

L'obiettivo di sicurezza più importante è sviluppare fin da subito questa abitudine:

> **Ogni dato proveniente dal chiamante è non fidato finché il contratto non ne ha verificato le proprietà necessarie.**

Questo comprende non solo i parametri espliciti della funzione, ma anche `msg.sender`, `msg.value` e, più in generale, il contesto della chiamata.

---

## 2. Modello mentale

Pensa a Ethereum come a una macchina a stati globale. Prima di una transazione esiste uno stato `S`; l'EVM esegue le operazioni richieste e, se tutto termina correttamente, produce un nuovo stato `S'`.

```text
stato prima S
    |
    |  transazione autorizzata
    v
+-----------------------------+
| EVM                         |
|                             |
|  call frame del contratto   |
|  ------------------------   |
|  msg.sender                 |
|  msg.value                  |
|  msg.data / parametri       |
|  stack + memory             |
|  letture/scritture storage  |
+-----------------------------+
    |
    +---- successo ----> commit delle modifiche ----> stato S'
    |
    +---- revert ------> annulla le modifiche del frame che fallisce
                         e dei suoi sotto-call non gestiti
```

Tre concetti vanno separati mentalmente.

### Transazione

È l'istruzione top-level che entra nel protocollo Ethereum. Ha, tra le altre cose, un mittente/autorizzazione, un nonce, una destinazione, eventuale `value`, input data e limiti/costi di gas.

### Message call

Durante l'esecuzione, un contratto può chiamarne un altro. Quella chiamata crea un nuovo contesto di esecuzione. In quel nuovo frame, `msg.sender` non indica necessariamente l'account che ha originato la transazione: indica il **chiamante diretto**.

### Chiamata interna Solidity

Una chiamata a una funzione `internal` o a una funzione invocata internamente senza passare da una vera external call non crea lo stesso tipo di confine esterno. Questo diventerà importante più avanti quando studieremo external calls e reentrancy.

### Una nota moderna sugli account: EIP-7702

Per anni si è insegnato il modello semplificato “EOA = account senza codice, contract account = account con codice”. È ancora utile come prima approssimazione, ma dopo Pectra ed **EIP-7702** non è più una distinzione sulla quale costruire proprietà di sicurezza rigide: un EOA può delegare l'esecuzione a codice.

La regola didattica che useremo nel corso è quindi più robusta:

> **Non dedurre capacità o affidabilità di un chiamante soltanto dal fatto che sembri un EOA. Progetta assumendo che un partecipante possa avere comportamento programmabile.**

Questo è anche uno dei motivi per cui `tx.origin == msg.sender` non è una valida protezione generale contro reentrancy o “chiamanti contract”.

---

## 3. Teoria

### 3.1 Una transazione è un input alla macchina a stati

Una transazione Ethereum contiene informazioni sufficienti perché il protocollo possa stabilire chi l'ha autorizzata, in quale ordine relativo all'account va elaborata e quale esecuzione richiede.

Per la sicurezza applicativa, i campi più importanti da tenere in mente sono:

- **destinazione**: quale account/contratto riceve la chiamata;
- **value**: quanta ETH viene trasferita con la chiamata top-level;
- **input data**: i byte che, per una normale chiamata Solidity, contengono selector e argomenti ABI-encoded;
- **nonce**: impedisce che due normali transazioni dello stesso sender abbiano lo stesso numero di sequenza;
- **gas**: limita il lavoro computazionale che l'esecuzione può consumare.

Una transazione verso un contratto non “chiama magicamente una funzione per nome”. All'EVM arrivano byte. Solidity usa l'ABI per dare struttura a quei byte.

---

### 3.2 ABI e calldata: cosa riceve davvero il contratto

Per una chiamata standard a una funzione Solidity, i primi quattro byte della calldata sono il **function selector**. Il selector è ottenuto dai primi quattro byte di `keccak256` della signature canonica della funzione.

Per esempio, la funzione:

```solidity
record(address,bytes)
```

ha una signature composta dal nome e dai tipi, senza nomi delle variabili e senza tipi di ritorno. Dopo i quattro byte del selector arrivano gli argomenti ABI-encoded.

Schema concettuale:

```text
msg.data
|
+-- byte 0..3    : function selector
|
+-- byte 4..     : argomenti ABI-encoded
```

Solidity espone:

```solidity
msg.data   // bytes calldata: l'intera calldata
msg.sig    // bytes4: i primi quattro byte di msg.data
```

Quando scriviamo:

```solidity
function record(address beneficiary, bytes calldata note) external payable
```

`beneficiary` e `note` derivano dalla calldata. Il chiamante sceglie quei valori. Il compilatore/ABI decoder verifica che la forma binaria sia compatibile con la firma della funzione, ma **non può sapere se il valore ha senso per il protocollo**.

Esempi di domande di sicurezza che il tipo da solo non risolve:

```text
address valido sintatticamente  -> ma address(0) è accettabile per il requisito?
uint256 valido                  -> ma zero è permesso? esiste un massimo?
bytes validi                    -> ma la lunghezza deve essere limitata?
msg.value valido                -> ma coincide con quanto la logica si aspetta?
```

Questa separazione è fondamentale:

> **ABI decoding garantisce una certa struttura; la business logic deve garantire la validità semantica.**

#### Perché esiste `calldata`

`calldata` è un'area di dati destinata agli input delle chiamate esterne. È read-only dal punto di vista del codice Solidity eseguito. Per parametri dinamici di funzioni `external`, usare `calldata` permette normalmente di leggere l'input senza doverlo copiare inutilmente in `memory`.

Per la sicurezza, la caratteristica più importante non è “calldata è economica”, ma questa:

> **È il confine di ingresso di dati controllabili dall'esterno.**

Quando fai audit, ogni parametro in `calldata` merita la domanda: “quale proprietà sto assumendo senza verificarla?”.

---

### 3.3 `msg.sender`: il chiamante diretto del frame corrente

La documentazione Solidity definisce `msg.sender` come il sender del **messaggio corrente**.

Considera:

```text
Alice
  |
  | transazione
  v
Contract A
  |
  | external call
  v
Contract B
```

Dentro `A`:

```text
msg.sender = Alice
```

Dentro `B`:

```text
msg.sender = address(A)
```

Quindi `msg.sender` può cambiare lungo la call chain.

Questo non è un dettaglio marginale: l'access control è spesso una condizione su `msg.sender`.

```solidity
if (msg.sender != owner) revert NotOwner();
```

La domanda corretta non è soltanto “chi è l'owner?”, ma anche:

> “Quale entità deve essere il **chiamante diretto** di questa operazione?”

#### `tx.origin` non è un sostituto di `msg.sender`

`tx.origin` identifica l'origine della transazione lungo la call chain. Proprio perché non cambia quando un contratto intermedio effettua ulteriori call, è pericoloso usarlo come meccanismo generale di autorizzazione.

Dopo EIP-7702 è inoltre esplicitamente scorretto assumere che `tx.origin` rappresenti necessariamente un account “non programmabile”.

Regola del corso:

> **Per autorizzazione ordinaria, ragiona sul chiamante appropriato del frame e usa `msg.sender` o un meccanismo esplicito di ruoli/autenticazione. Non usare `tx.origin` come scorciatoia.**

Studieremo access control in profondità più avanti; oggi ci interessa fissare il modello di chiamata.

---

### 3.4 `msg.value`: ETH associata alla chiamata corrente

`msg.value` è un `uint256` espresso in **wei** e rappresenta la quantità di ETH inviata con il messaggio corrente.

```text
1 ether = 10^18 wei
```

Una funzione che deve accettare ETH deve essere `payable`:

```solidity
function deposit() external payable {
    // msg.value contiene i wei ricevuti con questa call
}
```

Se una funzione pubblica/esterna non è `payable`, una chiamata che tenta di inviarle ETH fallisce.

Dal punto di vista di threat modeling:

> **Il chiamante controlla `msg.value` entro i limiti del proprio saldo e della transazione. Il contratto non deve assumere che il valore sia “quello giusto” senza verificarlo.**

Esempio:

```solidity
if (msg.value == 0) revert ZeroValue();
```

In protocolli più complessi potresti dover verificare uguaglianze, minimi, massimi o coerenza tra `msg.value` e altri campi della richiesta.

#### `msg.value` appartiene al call frame

Come `msg.sender`, anche `msg.value` appartiene al contesto della chiamata corrente. Quando in futuro un contratto effettuerà una call a un altro contratto, potrà associare a quella call una quantità di ETH specifica. Il callee vedrà quel valore come proprio `msg.value`.

Questo sarà centrale nella lezione sulle external calls.

---

### 3.5 `storage`: lo stato persistente del contratto

Le state variables Solidity vivono, salvo casi particolari, nello **storage** del contratto. Lo storage persiste tra una transazione e la successiva ed è parte dello stato Ethereum.

Esempio:

```solidity
uint256 public nextId;
mapping(address => uint256) public credited;
```

Se una chiamata aggiorna con successo `nextId`, la chiamata successiva vedrà il nuovo valore.

Mentalmente:

```text
calldata  -> input read-only della call corrente
memory    -> area temporanea della call corrente
storage   -> stato persistente associato al contratto
```

La EVM lavora con word da 256 bit e lo storage è organizzato in slot da 32 byte. Solidity applica regole di layout: variabili di dimensione minore possono essere packed nello stesso slot, mentre mapping e array dinamici usano regole basate su hashing per localizzare i propri dati.

Non serve memorizzare oggi tutte le formule di storage layout. La proprietà di sicurezza essenziale è:

> **Una scrittura in storage cambia la fonte di verità persistente del protocollo.**

Quindi, durante un audit, una state-changing function va letta chiedendosi:

```text
quale storage legge?
quale storage modifica?
quale relazione tra variabili deve rimanere vera dopo la modifica?
chi può causare quella modifica?
quali input controlla?
```

Queste domande diventeranno il nucleo della nostra metodologia di audit.

---

### 3.6 Il valore di default conta

Le variabili Solidity hanno valori iniziali di default. Per esempio:

```text
uint256  -> 0
address  -> address(0)
bool     -> false
bytes32  -> 0x00...00
```

Questo crea spesso stati “non inizializzati” che, se non considerati esplicitamente, possono confondersi con valori legittimi.

Esempio: se `id == 0` è un ID valido, non puoi usare semplicemente `deposits[id].amount == 0` per decidere in ogni protocollo se il deposito esiste, perché zero potrebbe anche essere un valore significativo in altri design.

Nel contratto di oggi useremo `id < nextId` come criterio di esistenza.

---

### 3.7 `revert`: atomicità e fallimento esplicito

Quando Solidity esegue un revert, le modifiche di stato effettuate nel contesto che viene annullato non vengono committate.

Esempio concettuale:

```solidity
nextId = nextId + 1;

if (badCondition) {
    revert BadCondition();
}
```

Se il revert annulla l'intera call, l'incremento di `nextId` non rimane nello stato persistente.

Questo è il motivo per cui i test negativi non devono limitarsi a controllare “la funzione fallisce”. Devono chiedere anche:

> **Dopo il fallimento, lo stato è davvero rimasto invariato nelle parti che dovevano essere atomiche?**

Solidity offre vari modi per causare fallimento:

```solidity
require(condition);
require(condition, "reason");
revert CustomError(...);
assert(internalInvariant);
```

Per il nostro stile useremo spesso **custom errors**:

```solidity
error ZeroValue();

if (msg.value == 0) revert ZeroValue();
```

Sono espliciti, strutturati e normalmente più efficienti delle lunghe revert string.

#### `require` vs `assert`

Una distinzione utile:

- condizioni su input, autorizzazione o componenti esterni: `require` o `revert` con custom error;
- condizioni che rappresentano proprietà interne che il programma considera impossibili da violare se il codice è corretto: `assert`.

Non useremo `assert` come sostituto di una validazione utente.

#### Revert non significa “transazione gratuita”

Il revert annulla gli effetti di stato dell'esecuzione interessata, ma il lavoro computazionale già eseguito consuma gas. In una vera transazione on-chain, fallire non riporta semplicemente il mondo allo stato precedente “a costo zero”.

---

### 3.8 Il primo threat model: cosa controlla un chiamante ostile?

Prima ancora di scrivere test, prendiamo una funzione e separiamo ciò che il protocollo controlla da ciò che il chiamante controlla.

Per questa firma:

```solidity
function record(address beneficiary, bytes calldata note)
    external
    payable
```

il chiamante può scegliere almeno:

```text
msg.sender       -> identità del chiamante diretto compatibile con il flusso di call
msg.value        -> ETH allegata alla call
beneficiary      -> address passato come input
note             -> bytes arbitrari entro i limiti pratici della transazione
momento/ordine   -> quando chiamare e in quale sequenza rispetto ad altre chiamate
```

Il contratto controlla invece le regole con cui questi input diventano stato persistente.

È qui che nasce la sicurezza applicativa: non nell'impedire input ostili, ma nel garantire che **anche input ostili non possano rompere le proprietà dichiarate**.

---

## 4. Esempio Solidity

Il progetto conduttore sarà un Escrow. In questa prima lezione non implementiamo ancora release, refund o chiamate esterne: sarebbe troppo presto. Costruiamo soltanto il **registro locale dei depositi** che ci permette di esercitare `msg.sender`, `msg.value`, calldata, storage e revert.

Il contratto non è production-ready e non va usato per custodire fondi reali.

### `src/EscrowLesson1.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto giocattolo per la Lezione 1.
/// @dev Non è un escrow completo e non è production-ready.
contract EscrowLesson1 {
    uint256 public constant MAX_NOTE_BYTES = 256;

    error ZeroBeneficiary();
    error ZeroValue();
    error NoteTooLong(uint256 actualLength);
    error UnknownDeposit(uint256 id);

    struct Deposit {
        address payer;
        address beneficiary;
        uint256 amount;
        bytes32 noteHash;
    }

    uint256 public nextId;
    uint256 public totalRecorded;

    mapping(uint256 => Deposit) private _deposits;
    mapping(address => uint256) public credited;

    event DepositRecorded(
        uint256 indexed id,
        address indexed payer,
        address indexed beneficiary,
        uint256 amount,
        bytes32 noteHash
    );

    /// @notice Registra un deposito locale e accredita contabilmente il beneficiary.
    /// @dev L'ETH resta nel contratto: non esiste ancora una funzione di uscita.
    function record(address beneficiary, bytes calldata note)
        external
        payable
        returns (uint256 id)
    {
        if (beneficiary == address(0)) revert ZeroBeneficiary();
        if (msg.value == 0) revert ZeroValue();
        if (note.length > MAX_NOTE_BYTES) revert NoteTooLong(note.length);

        id = nextId;
        nextId = id + 1;

        bytes32 noteHash = keccak256(note);

        _deposits[id] = Deposit({
            payer: msg.sender,
            beneficiary: beneficiary,
            amount: msg.value,
            noteHash: noteHash
        });

        credited[beneficiary] += msg.value;
        totalRecorded += msg.value;

        emit DepositRecorded(
            id,
            msg.sender,
            beneficiary,
            msg.value,
            noteHash
        );
    }

    function getDeposit(uint256 id)
        external
        view
        returns (Deposit memory deposit_)
    {
        if (id >= nextId) revert UnknownDeposit(id);
        deposit_ = _deposits[id];
    }
}
```

### Perché memorizziamo l'hash della nota e non la nota intera?

`note` è input controllato dal chiamante. Potremmo salvare `bytes` in storage, ma in questa fase non abbiamo alcun requisito che richieda di conservare l'intero contenuto on-chain.

Salvare soltanto `keccak256(note)` ci permette di verificare in seguito che una certa nota corrisponda a quella originaria senza rendere lo storage proporzionale alla dimensione della nota.

Inoltre imponiamo:

```solidity
MAX_NOTE_BYTES = 256
```

perché un input dinamico senza bound è una superficie di costo e complessità. Non esiste un “numero universalmente sicuro”: **256 è una scelta di progetto didattica**. In un sistema reale il bound deve derivare dal requisito.

---

## 5. Analisi del codice

### 5.1 `record(address beneficiary, bytes calldata note)`

**Chi può chiamarla?**

Qualunque account/contratto in grado di effettuare la call. Non esiste access control: è intenzionale, perché “chiunque può creare un deposito” è il requisito di questo giocattolo.

**Quali input controlla il chiamante?**

Il chiamante controlla:

```text
beneficiary
note
msg.value
il proprio ruolo come msg.sender nella call corrente
ordine e momento della chiamata
```

**Quale valore entra?**

`msg.value` wei. La funzione rifiuta `0`.

**Quale stato viene letto?**

- `nextId`;
- implicitamente i valori correnti di `credited[beneficiary]` e `totalRecorded` per gli incrementi.

**Quale stato viene modificato?**

- `nextId`;
- `_deposits[id]`;
- `credited[beneficiary]`;
- `totalRecorded`;
- il saldo ETH del contratto aumenta perché la call è `payable` e ha `msg.value > 0`.

**Quali chiamate esterne vengono effettuate?**

Nessuna.

**Quando il controllo passa a codice esterno?**

Mai dentro il corpo di `record`.

Questa è una proprietà importante: in questa versione non abbiamo ancora il problema “ho aggiornato metà stato, poi cedo il controllo a un destinatario arbitrario”. Quel problema arriverà quando introdurremo external calls.

**Quali assunzioni vengono fatte?**

- `address(0)` non è un beneficiary valido;
- un deposito deve avere valore positivo;
- la nota può essere arbitraria nel contenuto ma non superiore a 256 byte;
- l'identità del payer è il chiamante diretto, quindi viene registrato `msg.sender`;
- non serve conservare la nota, soltanto il suo hash;
- l'aritmetica checked di Solidity 0.8.x è sufficiente per evitare wrap silenzioso degli incrementi.

Un auditor deve distinguere tra “assunzione documentata e verificata” e “assunzione implicita non protetta”. Le prime tre sono trasformate in check; l'ultima è fornita dal comportamento standard di Solidity 0.8.x fuori da blocchi `unchecked`.

### 5.2 `getDeposit(uint256 id)`

**Chi può chiamarla?**

Chiunque.

**Quali input controlla il chiamante?**

`id`.

**Quale valore entra?**

Nessuna ETH: la funzione non è `payable`.

**Quale stato viene letto?**

- `nextId` per stabilire se l'ID esiste;
- `_deposits[id]` se valido.

**Quale stato viene modificato?**

Nessuno: è `view`.

**Quali chiamate esterne vengono effettuate?**

Nessuna.

**Quali assunzioni vengono fatte?**

Usiamo `id < nextId` come definizione di deposito esistente, perché gli ID vengono creati consecutivamente a partire da zero e non esiste ancora una funzione di cancellazione.

Se in futuro introducessimo cancellazioni o ID non consecutivi, questa assunzione dovrebbe essere rivalutata.

### 5.3 Getter automatici

Queste dichiarazioni:

```solidity
uint256 public nextId;
uint256 public totalRecorded;
mapping(address => uint256) public credited;
```

fanno generare al compilatore funzioni getter esterne di sola lettura.

Durante un audit, `public` non significa “chiunque può modificare”: significa che esiste un getter pubblico per leggere quel valore. La mutabilità dipende dalle funzioni che scrivono lo storage.

---

## 6. Proprietà e invarianti

Prima di testare, trasformiamo il comportamento desiderato in frasi falsificabili.

### Proprietà P1 — niente deposito a valore zero

> Se `msg.value == 0`, `record` deve revertire e non deve creare alcun deposito.

### Proprietà P2 — niente beneficiary nullo

> Se `beneficiary == address(0)`, `record` deve revertire e non modificare la contabilità.

### Proprietà P3 — bound sulla calldata dinamica

> Se `note.length > 256`, `record` deve revertire.

### Proprietà P4 — identità del payer

> Dopo una `record` riuscita, `deposit.payer` deve essere esattamente il `msg.sender` della call riuscita.

### Proprietà P5 — valore registrato

> Dopo una `record` riuscita, `deposit.amount` deve essere esattamente il `msg.value` della call.

### Proprietà P6 — progressione degli ID

> Ogni `record` riuscita incrementa `nextId` esattamente di uno; una `record` fallita non lo incrementa.

### Proprietà P7 — contabilità del beneficiary

> Una `record` riuscita aumenta `credited[beneficiary]` esattamente di `msg.value`.

### Proprietà P8 — totale contabilizzato

> Una `record` riuscita aumenta `totalRecorded` esattamente di `msg.value`; una call fallita non lo modifica.

### Proprietà P9 — atomicità del fallimento

> Se `record` reverte, nessuna delle sue scritture contabili deve rimanere persistente e l'ETH della call fallita non deve restare nel contratto come effetto di quella call.

### Proprietà P10 — hash della nota

> Per un deposito riuscito, `noteHash == keccak256(note)`.

### Una quasi-invariante da NON formulare male

Potresti essere tentato di scrivere:

```text
address(escrow).balance == totalRecorded
```

Nel nostro laboratorio ordinario questa uguaglianza apparirà vera, ma come proprietà generale di un contratto Ethereum è fragile: non sempre un contratto può impedire in assoluto che ETH gli venga accreditata da meccanismi che non passano per la sua normale funzione `record`.

Una proprietà più prudente, se il design lo richiedesse, sarebbe ragionare sulla relazione tra **contabilità interna** e fondi necessari a soddisfarla, non assumere che ogni wei del saldo abbia necessariamente attraversato il percorso applicativo previsto.

Questa distinzione tra “saldo osservato” e “accounting interno” diventerà molto importante nel corso.

---

## 7. Laboratorio Foundry

### 7.1 Installazione

La documentazione ufficiale Foundry raccomanda Foundryup. Al momento della verifica, la pagina principale espone:

```bash
curl -L https://getfoundry.sh/install | bash && foundryup
```

Dopo l'installazione verifica:

```bash
forge --version
cast --version
anvil --version
```

Tutto il laboratorio seguente resta locale.

### 7.2 Crea il progetto

```bash
forge init solidity-security-course
cd solidity-security-course
```

Puoi eliminare i file `Counter` creati dal template e usare questa struttura:

```text
solidity-security-course/
├── foundry.toml
├── lib/
│   └── forge-std/
├── src/
│   ├── EscrowLesson1.sol
│   └── OriginAuthToy.sol
└── test/
    ├── EscrowLesson1.t.sol
    └── OriginAuthToy.t.sol
```

### 7.3 Pinna il compilatore

`foundry.toml` minimo:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.37"
```

Foundry supporta `solc_version` come versione semver stretta. Il pin ci evita che una futura release del compilatore cambi silenziosamente l'ambiente della lezione.

Controlla la configurazione risolta con:

```bash
forge config
```

### 7.4 Inserisci il contratto

Copia il file `EscrowLesson1.sol` mostrato nella sezione 4 in:

```text
src/EscrowLesson1.sol
```

### 7.5 Test principale

Crea `test/EscrowLesson1.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {EscrowLesson1} from "../src/EscrowLesson1.sol";

contract EscrowLesson1Test is Test {
    EscrowLesson1 internal escrow;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        escrow = new EscrowLesson1();
        vm.deal(alice, 10 ether);
    }

    function test_RecordBindsSenderValueAndCalldataToStorage() public {
        bytes memory note = bytes("ordine-42");

        vm.prank(alice);
        uint256 id = escrow.record{value: 1 ether}(bob, note);

        assertEq(id, 0);
        assertEq(escrow.nextId(), 1);
        assertEq(escrow.totalRecorded(), 1 ether);
        assertEq(escrow.credited(bob), 1 ether);
        assertEq(address(escrow).balance, 1 ether);

        EscrowLesson1.Deposit memory deposit_ = escrow.getDeposit(id);

        assertEq(deposit_.payer, alice);
        assertEq(deposit_.beneficiary, bob);
        assertEq(deposit_.amount, 1 ether);
        assertEq(deposit_.noteHash, keccak256(note));
    }

    function test_RevertWhenValueIsZero() public {
        bytes memory note = bytes("zero-value");

        vm.expectRevert(EscrowLesson1.ZeroValue.selector);
        vm.prank(alice);
        escrow.record(bob, note);

        assertEq(escrow.nextId(), 0);
        assertEq(escrow.totalRecorded(), 0);
        assertEq(escrow.credited(bob), 0);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhenBeneficiaryIsZero() public {
        bytes memory note = bytes("bad-beneficiary");

        vm.expectRevert(EscrowLesson1.ZeroBeneficiary.selector);
        vm.prank(alice);
        escrow.record{value: 1 ether}(address(0), note);

        assertEq(escrow.nextId(), 0);
        assertEq(escrow.totalRecorded(), 0);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhenNoteIsTooLong() public {
        bytes memory tooLong = new bytes(257);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowLesson1.NoteTooLong.selector,
                uint256(257)
            )
        );

        vm.prank(alice);
        escrow.record{value: 1 ether}(bob, tooLong);

        assertEq(escrow.nextId(), 0);
        assertEq(escrow.totalRecorded(), 0);
        assertEq(escrow.credited(bob), 0);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertRollsBackStateAndIncomingValue() public {
        vm.prank(alice);
        escrow.record{value: 1 ether}(bob, bytes("first"));

        uint256 nextIdBefore = escrow.nextId();
        uint256 totalBefore = escrow.totalRecorded();
        uint256 bobCreditBefore = escrow.credited(bob);
        uint256 balanceBefore = address(escrow).balance;

        bytes memory tooLong = new bytes(257);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowLesson1.NoteTooLong.selector,
                uint256(257)
            )
        );

        vm.prank(alice);
        escrow.record{value: 2 ether}(bob, tooLong);

        assertEq(escrow.nextId(), nextIdBefore);
        assertEq(escrow.totalRecorded(), totalBefore);
        assertEq(escrow.credited(bob), bobCreditBefore);
        assertEq(address(escrow).balance, balanceBefore);
    }

    function test_RevertWhenReadingUnknownDeposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowLesson1.UnknownDeposit.selector,
                uint256(0)
            )
        );

        escrow.getDeposit(0);
    }
}
```

### 7.6 Esegui

```bash
forge build
forge test
```

Per vedere più dettagli:

```bash
forge test -vvv
```

Per concentrarti sul test di rollback e vedere una trace molto più dettagliata:

```bash
forge test \
  --match-test test_RevertRollsBackStateAndIncomingValue \
  -vvvvv
```

La reference Foundry corrente documenta che livelli di verbosity più alti mostrano trace più dettagliate; `-vvvvv` include anche storage changes nelle trace EVM.

### 7.7 Leggere selector e calldata con Cast

Non serve una blockchain per calcolare il selector:

```bash
cast sig "record(address,bytes)"
```

E puoi costruire la calldata ABI-encoded:

```bash
cast calldata \
  "record(address,bytes)" \
  0x0000000000000000000000000000000000000B0B \
  0x6f7264696e652d3432
```

`0x6f7264696e652d3432` è la codifica UTF-8 esadecimale di `ordine-42`.

Osserva l'output:

```text
0x[4-byte selector][ABI encoding degli argomenti...]
```

L'esercizio importante non è memorizzare l'hex, ma riconoscere che il contratto riceve **byte controllati dal chiamante** e li interpreta secondo l'ABI.

### 7.8 Estensione facoltativa: vera transazione su Anvil, sempre locale

Questa parte è facoltativa. Serve solo a vedere la differenza tra i test Forge e una transazione inviata a un nodo locale.

Terminale 1:

```bash
anvil
```

Anvil crea account di test prefinanziati e stampa le relative chiavi di sviluppo. Non usare queste chiavi fuori dal nodo locale.

Terminale 2, dalla directory del progetto:

```bash
forge create src/EscrowLesson1.sol:EscrowLesson1 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_TEST_STAMPATA_DA_ANVIL>
```

Prendi l'indirizzo del contratto appena deployato e invia una transazione locale:

```bash
cast send <INDIRIZZO_CONTRATTO> \
  "record(address,bytes)" \
  0x0000000000000000000000000000000000000B0B \
  0x6f7264696e652d3432 \
  --value 1ether \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_TEST_STAMPATA_DA_ANVIL>
```

Poi leggi lo stato senza inviare una nuova transazione state-changing:

```bash
cast call <INDIRIZZO_CONTRATTO> \
  "nextId()(uint256)" \
  --rpc-url http://127.0.0.1:8545
```

Risultato atteso: `nextId` vale `1`.

Questa estensione rimane confinata a `127.0.0.1` e usa soltanto fondi fittizi di Anvil.

---

## 8. Test negativi

L'happy path dimostra soltanto che almeno un input valido funziona. La sicurezza richiede di provare sistematicamente gli input che devono essere rifiutati.

Nel laboratorio abbiamo già coperto quattro classi:

```text
msg.value = 0
beneficiary = address(0)
note.length > MAX_NOTE_BYTES
id inesistente in getDeposit
```

Ma il punto più importante è **come** abbiamo scritto i test.

Non ci siamo fermati a:

```solidity
vm.expectRevert(...);
escrow.record(...);
```

Abbiamo controllato anche lo stato dopo il revert:

```solidity
assertEq(escrow.nextId(), 0);
assertEq(escrow.totalRecorded(), 0);
assertEq(escrow.credited(bob), 0);
assertEq(address(escrow).balance, 0);
```

Questa è già mentalità da auditor: il fallimento corretto non è “è comparso un errore”, ma “la transizione di stato proibita non è avvenuta”.

---

## 9. Errore di progettazione: usare `tx.origin` per autorizzare

Questa non è una lezione completa sull'access control; facciamo però un micro-laboratorio perché chiarisce in modo concreto la differenza tra origine della transazione e chiamante diretto.

### 9.1 Versione vulnerabile giocattolo

Crea `src/OriginAuthToy.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface ISetter {
    function setValue(uint256 newValue) external;
}

/// @notice Esempio volutamente errato: NON usare come pattern.
contract OriginAuthToy is ISetter {
    error NotOwner();

    address public immutable owner;
    uint256 public value;

    constructor(address owner_) {
        owner = owner_;
    }

    function setValue(uint256 newValue) external {
        // VULNERABILE: autorizza l'origine della transazione,
        // non il chiamante diretto di questa funzione.
        if (tx.origin != owner) revert NotOwner();
        value = newValue;
    }
}

/// @notice Versione corretta per questo semplice requisito.
contract SenderAuthToy is ISetter {
    error NotOwner();

    address public immutable owner;
    uint256 public value;

    constructor(address owner_) {
        owner = owner_;
    }

    function setValue(uint256 newValue) external {
        if (msg.sender != owner) revert NotOwner();
        value = newValue;
    }
}

/// @notice Intermediario locale usato solo per mostrare la call chain.
contract ForwarderToy {
    function forward(ISetter target, uint256 newValue) external {
        target.setValue(newValue);
    }
}
```

### 9.2 Perché è vulnerabile

Supponi:

```text
owner = Alice
```

Alice chiama `ForwarderToy.forward`, che poi chiama `OriginAuthToy.setValue`.

Nel secondo frame:

```text
tx.origin  = Alice
msg.sender = ForwarderToy
```

Il contratto vulnerabile controlla `tx.origin`, quindi considera autorizzata un'operazione richiesta direttamente dal forwarder soltanto perché l'origine della transazione è Alice.

Il problema concettuale è:

> **L'autorizzazione che volevamo era “solo Alice può chiamare direttamente setValue”, ma il codice verifica una proprietà diversa: “la call chain deve essere iniziata da Alice”.**

Sono requisiti diversi.

### 9.3 Riproduzione esclusivamente locale

Crea `test/OriginAuthToy.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {
    OriginAuthToy,
    SenderAuthToy,
    ForwarderToy
} from "../src/OriginAuthToy.sol";

contract OriginAuthToyTest is Test {
    address internal owner = address(0xA11CE);

    function test_Vulnerable_TxOriginAcceptsIntermediaryCall() public {
        OriginAuthToy target = new OriginAuthToy(owner);
        ForwarderToy forwarder = new ForwarderToy();

        // Foundry imposta sia msg.sender sia tx.origin per la call successiva.
        vm.prank(owner, owner);
        forwarder.forward(target, 777);

        // Il target ha accettato una call il cui msg.sender era il forwarder.
        assertEq(target.value(), 777);
    }

    function test_Fixed_MsgSenderRejectsIntermediaryCall() public {
        SenderAuthToy target = new SenderAuthToy(owner);
        ForwarderToy forwarder = new ForwarderToy();

        vm.expectRevert(SenderAuthToy.NotOwner.selector);
        vm.prank(owner, owner);
        forwarder.forward(target, 777);

        assertEq(target.value(), 0);
    }

    function test_Fixed_OwnerCanCallDirectly() public {
        SenderAuthToy target = new SenderAuthToy(owner);

        vm.prank(owner);
        target.setValue(777);

        assertEq(target.value(), 777);
    }
}
```

Esegui soltanto questo file:

```bash
forge test --match-path test/OriginAuthToy.t.sol -vvv
```

### 9.4 Prima / dopo

```text
PRIMA
-----
if (tx.origin != owner) revert NotOwner();

Proprietà realmente verificata:
"la transazione è stata originata da owner"

DOPO
----
if (msg.sender != owner) revert NotOwner();

Proprietà realmente verificata:
"il chiamante diretto di questa funzione è owner"
```

Questo test è anche un **regression test**: se qualcuno reintroducesse `tx.origin` nella versione fixed, il test `test_Fixed_MsgSenderRejectsIntermediaryCall` smetterebbe di proteggere il requisito atteso.

### 9.5 Nota EIP-7702

Storicamente alcuni pattern hanno usato:

```solidity
require(msg.sender == tx.origin);
```

per tentare di bloccare chiamate da contratti. La documentazione Ethereum su EIP-7702 avverte che questa assunzione non è più affidabile: un account che origina una transazione può avere comportamento programmabile tramite delegation.

Quindi non useremo questa uguaglianza come primitive di sicurezza.

---

## 10. Checklist da auditor

Quando leggi una state-changing function, usa questa sequenza compatta:

1. **Caller:** chi può arrivare qui? Il controllo usa `msg.sender`, ruoli, firme o nessuna autorizzazione?
2. **Value:** la funzione è `payable`? Quali valori di `msg.value` sono validi? Zero è previsto?
3. **Calldata:** quali parametri controlla l'esterno? Sono validati semanticamente, non soltanto tipizzati?
4. **Storage reads:** quali decisioni dipendono dallo stato corrente?
5. **Storage writes:** quali variabili persistenti cambiano? Devono cambiare insieme?
6. **Failure:** se una condizione fallisce, il revert avviene prima che lo stato possa rimanere incoerente?
7. **External control:** esistono external calls? Se sì, in quale punto il controllo passa fuori? In questa lezione il nostro Escrow non ne ha.
8. **Assumptions:** il codice assume che un address sia EOA, che un saldo equivalga all'accounting interno o che un input sia “ragionevole” senza verificarlo?
9. **Negative path:** esiste almeno un test che provi ogni rifiuto importante e controlli anche lo stato dopo il revert?
10. **Property:** riesci a descrivere in una frase verificabile ciò che deve restare vero dopo ogni successo e ogni fallimento?

Se non riesci a rispondere a una voce, hai trovato un punto da investigare, non necessariamente una vulnerabilità.

---

## 11. Esercizi

Non ci sono soluzioni qui: l'obiettivo è farti formulare prima le proprietà e poi il codice.

### Esercizio 1 — Due depositi, stesso beneficiary

Scrivi un test in cui Alice registra `1 ether` per Bob e poi un secondo account registra `2 ether` per Bob.

Verifica almeno:

```text
nextId == 2
credited[bob] == 3 ether
totalRecorded == 3 ether
payer del deposito 0 != payer del deposito 1
```

Prima di scrivere il test, formula la proprietà in italiano.

### Esercizio 2 — Due beneficiary diversi

Registra valori diversi per Bob e Carol. Verifica che la modifica del credito di Carol non alteri il credito di Bob.

Domanda da auditor:

> quale relazione tra mapping key diverse stai verificando implicitamente?

### Esercizio 3 — Boundary della nota

Scrivi due test:

```text
note.length == 256  -> deve riuscire
note.length == 257  -> deve revertire
```

Questo è un classico boundary test.

### Esercizio 4 — Atomicità dopo stato già esistente

Crea due depositi validi, poi tenta un terzo deposito invalido.

Verifica che il fallimento non modifichi:

```text
nextId
totalRecorded
credited del beneficiary
saldo del contratto
depositi precedenti
```

### Esercizio 5 — Analisi della funzione prima del test

Senza eseguire codice, compila per `record` questa tabella:

```text
caller controllabile da:
input espliciti:
input impliciti:
storage letto:
storage scritto:
external calls:
assunzioni:
revert possibili:
proprietà post-successo:
proprietà post-fallimento:
```

Poi confrontala con la sezione 5.

### Esercizio 6 — Calldata con Cast

Calcola:

```bash
cast sig "record(address,bytes)"
```

poi genera calldata con una nota diversa. Individua visivamente:

```text
selector
address codificato
head/tail dell'argomento bytes dinamico
```

Non serve ancora ricostruire a memoria tutte le regole ABI: prova a collegare l'output alla specifica ABI ufficiale.

### Esercizio 7 — Threat modeling di una scelta di design

Immagina di rimuovere:

```solidity
if (note.length > MAX_NOTE_BYTES) revert NoteTooLong(note.length);
```

Non limitarti a dire “è meno sicuro”. Scrivi:

```text
quale input diventa non bounded?
quali costi crescono con la sua dimensione?
quale proprietà del protocollo vorresti definire prima di decidere il bound?
```

### Esercizio 8 — `msg.sender` e intermediario

Modifica `ForwarderToy` affinché emetta un evento con il proprio `msg.sender` prima di chiamare il target. Poi usa le trace di Forge per seguire la call chain e annota, per ogni frame, `msg.sender` e `tx.origin`.

---

## 12. Cosa devo ricordare

Se tra qualche giorno ricordi soltanto sei idee, devono essere queste:

1. **Una transazione avvia l'esecuzione, ma dentro la transazione possono esistere più call frame.**
2. **`msg.sender` è il chiamante diretto del frame corrente, non necessariamente l'origine della transazione.**
3. **`msg.value` e la calldata sono input controllabili dall'esterno e vanno validati secondo i requisiti del protocollo.**
4. **`storage` è stato persistente: ogni scrittura deve preservare proprietà esplicite del sistema.**
5. **Un revert corretto non deve lasciare una transizione parziale dello stato che si voleva rendere atomica.**
6. **La sicurezza parte da proprietà verificabili: definisci cosa deve essere vero, poi testa anche ciò che non deve essere possibile.**

---

## 13. Fonti della lezione

Fonti tecniche effettivamente consultate per questa lezione, verificate il 21 settembre 2026:

- **Solidity 0.8.37 Release Announcement** — release corrente usata come baseline e relativi bugfix:  
  https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/

- **Solidity — Units and Globally Available Variables** — `msg.sender`, `msg.value`, `msg.data`, `msg.sig`, `tx.origin`, error handling:  
  https://docs.soliditylang.org/en/latest/units-and-global-variables.html

- **Solidity — Contract ABI Specification** — function selector e codifica degli argomenti:  
  https://docs.soliditylang.org/en/latest/abi-spec.html

- **Solidity — Expressions and Control Structures** — `require`, `revert`, `assert`, custom errors e semantica del revert:  
  https://docs.soliditylang.org/en/latest/control-structures.html

- **Solidity — Layout of State Variables in Storage and Transient Storage** — storage slot, packing, mapping e array dinamici:  
  https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html

- **ethereum.org — Ethereum Virtual Machine (EVM)** — EVM come state transition function, transazioni, storage e contesto di esecuzione:  
  https://ethereum.org/developers/docs/evm/

- **ethereum.org — Transactions** — struttura concettuale delle transazioni Ethereum:  
  https://ethereum.org/developers/docs/transactions/

- **ethereum.org — Pectra EIP-7702 guidelines** e **EIP-7702** — account delegation e implicazioni di sicurezza sulle assunzioni EOA/`tx.origin`:  
  https://ethereum.org/roadmap/pectra/7702/  
  https://eips.ethereum.org/EIPS/eip-7702

- **Foundry — Installation / Configuration / Forge Std / Cheatcodes** — installazione, `solc_version`, `Test.sol`, `vm.prank`, `vm.expectRevert`:  
  https://getfoundry.sh/getting-started/installation  
  https://www.getfoundry.sh/config/index.html  
  https://getfoundry.sh/reference/forge-std/overview  
  https://getfoundry.sh/reference/cheatcodes/prank/  
  https://getfoundry.sh/cheatcodes/expect-revert

- **Foundry — Cast reference** — `cast sig`, `cast calldata` e strumenti ABI:  
  https://getfoundry.sh/cast/reference/cast/

- **OWASP Smart Contract Security — SCSVS-AUTH-2 / SCWE-018 / SC05:2026** — uso di `msg.sender` per authorization, rischio di `tx.origin`, validazione degli input:  
  https://scs.owasp.org/SCSVS/controls/SCSVS-AUTH-2/  
  https://scs.owasp.org/SCWE/SCSVS-AUTH/SCWE-018/  
  https://scs.owasp.org/sctop10/SC05-LackOfInputValidation/

---

**Fine della Lezione 1.**
