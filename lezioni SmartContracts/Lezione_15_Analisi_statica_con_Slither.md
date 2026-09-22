# Lezione 15 — Analisi statica con Slither

> **Scopo:** secure coding, auditing, triage e integrazione tra analisi automatica e review manuale.
>
> Tutti gli esempi restano confinati a contratti giocattolo locali. Non useremo Slither per cercare bersagli pubblici o protocolli reali.

---

# 1. Obiettivi

Alla fine della lezione dovresti saper:

- spiegare che cos'è l'analisi statica;
- distinguere analisi statica da testing dinamico;
- installare ed eseguire Slither su un progetto Foundry;
- usare:
  - detector;
  - printer;
  - call graph;
  - function summary;
  - vars-and-auth;
  - JSON/SARIF output;
- classificare finding per:
  - impact;
  - confidence;
  - reachability;
  - exploitability;
  - business relevance;
- distinguere:
  - vero positivo;
  - falso positivo;
  - finding informativo;
  - design risk;
- capire perché un detector non sostituisce l'audit manuale;
- usare il compilatore Solidity come primo static analyzer;
- trasformare un finding Slither in:
  1. ipotesi;
  2. riproduzione locale;
  3. remediation;
  4. regression test;
- integrare Slither in una pipeline Foundry/CI.

---

# 2. Modello mentale

Nel testing dinamico facciamo:

```text
input
  |
  v
esecuzione
  |
  v
assertion
```

L'analisi statica invece prova a ragionare sul codice senza dover eseguire ogni possibile scenario.

Schema:

```text
source code
   |
   v
AST / IR / control flow / data flow
   |
   v
rules + analyses
   |
   v
candidate findings
```

La parola importante è:

> **candidate**

Un finding non è automaticamente una vulnerabilità confermata.

È una domanda prioritaria da investigare.

---

# 3. Analisi statica vs testing

## Testing

Può dimostrare:

```text
per questo input/sequenza:
la proprietà passa o fallisce
```

## Analisi statica

Può trovare pattern come:

```text
external call prima dello state update
unchecked low-level call
unprotected upgrade
state variable mai inizializzata
authorization sospetta
```

senza conoscere necessariamente un input concreto.

Le due tecniche sono complementari.

---

# 4. Primo static analyzer: il compilatore

Prima ancora di Slither:

```bash
forge build
```

Il compilatore Solidity produce:

```text
error
warning
info
```

La documentazione Solidity raccomanda esplicitamente di prendere sul serio i warning.

Non adottare il mindset:

```text
"compila, quindi va bene"
```

Piuttosto:

```text
"perché il compiler mi sta avvisando?"
```

---

# 5. Warning != vulnerability

Esempio:

```text
unused variable
```

può essere innocuo.

Ma può anche indicare:

```text
controllo dimenticato
return value ignorato
logic path incompleto
```

Quindi il warning è:

```text
segnale da capire
```

non:

```text
verdetto
```

---

# 6. Che cos'è Slither

Slither è uno static analyzer per Solidity/Vyper sviluppato da Trail of Bits.

Tra le sue capacità:

```text
detector di vulnerabilità/pattern rischiosi
call graph
CFG
inheritance graph
state-variable analysis
authorization summary
data dependency
upgradeability tooling
JSON/SARIF export
```

Per un progetto Foundry, il comando base è:

```bash
slither .
```

Slither usa il framework di compilazione sottostante, tramite `crytic-compile`, per risolvere import e build.

---

# 7. Installazione

L'installazione può avvenire con Python tooling, per esempio in ambiente isolato.

Una possibilità comune:

```bash
pipx install slither-analyzer
```

Poi:

```bash
slither --version
```

e nel progetto:

```bash
slither .
```

Poiché toolchain e dipendenze evolvono, verifica sempre la documentazione ufficiale del repository Slither per il metodo raccomandato nella tua piattaforma.

---

# 8. Progetto Foundry

Struttura:

```text
slither-lab/
├── foundry.toml
├── src/
│   ├── GoodEscrow.sol
│   ├── UnsafeCaller.sol
│   └── ToyVault.sol
└── test/
```

Prima:

```bash
forge build
```

Poi:

```bash
slither .
```

Se Slither non compila il progetto, il problema iniziale non è necessariamente Slither.

Verifica:

```text
solc version
remappings
dependency paths
foundry config
```

---

# 9. Slither esegue molti detector di default

Comando:

```bash
slither .
```

esegue la suite di detector abilitati.

Puoi vedere l'elenco:

```bash
slither --list-detectors
```

La documentazione corrente classifica i detector con:

```text
impact
confidence
```

Non leggere questa classificazione come severity finale del tuo audit.

Serve per prioritizzare.

---

# 10. Impact vs confidence

Esempio concettuale:

```text
Impact: High
Confidence: Low
```

significa:

```text
se il pattern è realmente sfruttabile,
l'impatto può essere alto,
ma l'analisi non è molto certa.
```

Viceversa:

```text
Impact: Low
Confidence: High
```

può essere un problema reale ma poco grave.

L'auditor deve aggiungere:

```text
context
reachability
asset impact
privileges
business semantics
```

---

# 11. Triage

Per ogni finding chiediti:

```text
1. è raggiungibile?
2. da chi?
3. in quale stato?
4. con quali input?
5. quali asset/ruoli coinvolge?
6. esiste una mitigazione già presente?
7. è intenzionale?
8. posso costruire un test che dimostri il problema?
```

Questa è la fase di triage.

---

# 12. Un finding non è ancora un report finding

Pipeline corretta:

```text
Slither finding
      |
      v
manual review
      |
      v
threat model
      |
      v
local reproduction
      |
      v
confirmed issue
      |
      v
remediation
      |
      v
regression test
```

Oppure:

```text
Slither finding
      |
      v
manual review
      |
      v
not exploitable / intended
      |
      v
documented false positive
```

---

# 13. Primo laboratorio — unchecked low-level call

## `src/UnsafeCaller.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract UnsafeCaller {
    bool public completed;

    function execute(
        address target,
        bytes calldata data
    ) external {
        target.call(data);

        completed = true;
    }
}
```

Il problema:

```text
target.call(data)
```

restituisce:

```text
(bool success, bytes memory returndata)
```

ma il risultato viene ignorato.

---

# 14. Perché è pericoloso

Se il target reverte:

```text
external action failed
```

ma poi:

```solidity
completed = true;
```

il contratto registra un falso successo.

Property violata:

> `completed == true` deve implicare che l'azione esterna richiesta abbia avuto successo.

---

# 15. Static finding vs business meaning

Slither può individuare un unchecked low-level call.

Ma il tool non conosce necessariamente la semantica di:

```text
completed
```

L'auditor sì.

Quindi la severity reale deriva dall'invariante di business.

---

# 16. Riproduzione Foundry

Mock:

```solidity
contract RevertingTarget {
    function run() external pure {
        revert("nope");
    }
}
```

Test:

```solidity
function test_UncheckedCallCreatesFalseSuccess()
    public
{
    RevertingTarget target =
        new RevertingTarget();

    UnsafeCaller caller =
        new UnsafeCaller();

    bytes memory data =
        abi.encodeCall(
            target.run,
            ()
        );

    caller.execute(
        address(target),
        data
    );

    assertTrue(
        caller.completed()
    );
}
```

Il test conferma il finding.

---

# 17. Remediation

Versione semplice:

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

completed = true;
```

Oppure, quando possibile:

```text
usa una high-level interface
```

invece di arbitrary low-level call.

---

# 18. Regression test

```solidity
function test_FailedExternalCallCannotMarkCompleted()
    public
{
    ...

    vm.expectRevert();

    caller.execute(
        address(target),
        data
    );

    assertFalse(
        caller.completed()
    );
}
```

Ora abbiamo trasformato:

```text
static warning
```

in:

```text
permanent executable security property
```

---

# 19. Printers

Slither non serve soltanto a trovare bug.

I **printers** aiutano a capire il sistema.

Elenco:

```bash
slither --list-printers
```

Alcuni molto utili:

```text
human-summary
contract-summary
function-summary
entry-points
vars-and-auth
call-graph
inheritance-graph
cfg
```

Questi strumenti sono particolarmente utili all'inizio di un audit.

---

# 20. `human-summary`

Comando:

```bash
slither . \
  --print human-summary
```

Serve per ottenere un overview.

Può aiutare a vedere:

```text
numero contratti
complessità generale
external calls
inheritance
```

È una mappa iniziale, non una conclusione.

---

# 21. `contract-summary`

```bash
slither . \
  --print contract-summary
```

Aiuta a vedere:

```text
funzioni
modifiers
state variables
inheritance
```

Utile per costruire l'inventario del protocollo.

---

# 22. `function-summary`

```bash
slither . \
  --print function-summary
```

Molto utile durante manual review.

Per ogni funzione puoi ragionare su:

```text
visibility
state reads
state writes
internal/external calls
modifiers
```

Questo si collega direttamente alla struttura che usiamo da inizio corso:

```text
chi chiama?
cosa legge?
cosa scrive?
dove passa il controllo?
```

---

# 23. `vars-and-auth`

Comando:

```bash
slither . \
  --print vars-and-auth
```

Questo printer è molto utile per access control.

L'obiettivo è vedere:

```text
quali funzioni scrivono quali variabili
+
quale authorization è associata
```

Durante audit puoi usarlo per il nostro metodo:

```text
critical state variable
    |
    v
all write paths
    |
    v
all authorities
```

---

# 24. Esempio: oracle write paths

Supponiamo:

```solidity
address public oracle;

function setOracle(...)
    external onlyOwner;

function emergencySetOracle(...)
    external onlyGuardian;
```

Il problema non è:

```text
setOracle ha onlyOwner?
```

La domanda è:

```text
quali funzioni possono cambiare oracle?
```

`vars-and-auth` può aiutarti a scoprire percorsi dimenticati.

---

# 25. `entry-points`

Un audit manuale parte spesso dalle funzioni raggiungibili dall'esterno.

Printer:

```bash
slither . \
  --print entry-points
```

Costruisci una lista:

```text
deposit
withdraw
release
refund
setOracle
pause
upgrade...
```

Poi classificale:

```text
user
admin
governance
callback
view
```

---

# 26. Call graph

Comando:

```bash
slither . \
  --print call-graph
```

Produce grafi, tipicamente in formato DOT.

Serve a vedere:

```text
function A
  |
  +--> internal B
  |
  +--> external C
```

Utile per:

```text
composability
reentrancy surface
deep call chains
unexpected external calls
```

---

# 27. Call graph e reentrancy

Se una funzione:

```text
release()
```

chiama:

```text
_internalAccounting()
externalTokenTransfer()
_notify()
```

il call graph aiuta a non perdere un external edge annidato.

Ricorda:

> una external call può essere nascosta dietro più livelli di funzioni interne.

---

# 28. CFG

Control Flow Graph:

```bash
slither . \
  --print cfg
```

Mostra i branch di una funzione.

Molto utile per funzioni con:

```text
molte require
if/else
early return
multiple external calls
```

Puoi confrontarlo con la test coverage:

```text
quali branch esistono?
quali abbiamo testato?
```

---

# 29. Data dependency

Slither espone analisi di dipendenza dati.

La domanda è:

```text
il valore di X può dipendere da Y?
```

Esempio:

```solidity
uint256 public price;
uint256 public payout;

function setPrice(
    uint256 userInput
) external {
    price = userInput;
}

function compute() external {
    payout = price * 2;
}
```

A livello contratto:

```text
payout
dipende transitivamente da
userInput
```

Questo è potente per taint/data-flow reasoning.

---

# 30. Perché data-flow conta in audit

Supponiamo:

```text
user input
   |
   v
amount
   |
   v
external call value
```

oppure:

```text
oracle result
   |
   v
collateral value
   |
   v
withdraw limit
```

La domanda:

```text
da dove arriva questo valore critico?
```

è una domanda di data dependency.

---

# 31. Source → Sink thinking

Modello utile:

```text
SOURCE
  |
  v
transformations
  |
  v
SINK
```

Possibili source:

```text
msg.sender
msg.value
calldata
oracle
storage admin-controlled
external return
```

Possibili sink:

```text
ETH transfer
ERC20 transfer
delegatecall target
upgrade implementation
storage critical write
authorization decision
```

L'audit spesso consiste nel seguire questo flusso.

---

# 32. Secondo laboratorio — arbitrary target

```solidity
contract FlexibleExecutor {
    function execute(
        address target,
        bytes calldata data
    ) external {
        (
            bool ok,
        ) = target.call(data);

        require(ok);
    }
}
```

Questa volta il return value è controllato.

Quindi:

```text
unchecked-call fixed
```

Ma esiste ancora una domanda enorme:

```text
chi controlla target e data?
```

Il caller.

Quindi la funzione offre:

```text
arbitrary external call capability
```

---

# 33. Static detector non vede sempre tutta la severity

Il low-level call può essere "checked".

Ma il design resta potenzialmente potentissimo.

Se il contratto detiene:

```text
token
ETH
allowances
privileges
```

una arbitrary call può avere blast radius enorme.

Questo è un ottimo esempio di:

```text
no obvious detector alert
!=
safe design
```

---

# 34. Tool finding vs threat modeling

Slither cerca pattern.

Il threat model chiede:

```text
che cosa può fare un attacker
dato questo pattern
e gli asset reali?
```

Servono entrambi.

---

# 35. Detector selection

Puoi eseguire solo alcuni detector:

```bash
slither . \
  --detect detector1,detector2
```

Per esempio:

```bash
slither . \
  --detect reentrancy-eth,\
unchecked-lowlevel
```

I nomi precisi disponibili dipendono dalla versione.

Controlla:

```bash
slither --list-detectors
```

---

# 36. Exclude detector

```bash
slither . \
  --exclude naming-convention
```

Puoi anche escludere categorie informative/low.

Ma all'inizio di un audit è spesso utile vedere il rumore almeno una volta.

Un finding "low" può indicare:

```text
code smell
maintenance risk
future bug surface
```

---

# 37. Filtering dependencies

In un progetto con OpenZeppelin potresti ricevere finding principalmente dalle dependency.

Puoi filtrare path.

Esempio concettuale:

```bash
slither . \
  --filter-paths \
  "lib/openzeppelin-contracts"
```

Usalo con cautela.

Se il problema deriva dalla **tua integrazione** con una dependency, non vuoi nasconderlo accidentalmente.

---

# 38. Non ignorare una directory solo perché è `lib/`

Le dependency vendored fanno parte del bytecode o del build.

Domande:

```text
versione?
modificata?
fork custom?
patch locale?
```

Se è una dependency standard non modificata, puoi ridurre il rumore.

Ma devi sapere perché.

---

# 39. JSON output

Per automation:

```bash
slither . \
  --json slither-report.json
```

Questo rende possibile:

```text
CI parsing
finding tracking
custom dashboards
```

È meglio di parsare output testuale colorato.

---

# 40. SARIF

Slither supporta output adatto a strumenti di code scanning.

Il formato SARIF è utile per:

```text
GitHub code scanning
IDE integrations
security pipelines
```

Il workflow preciso dipende dall'ambiente CI.

L'idea importante è:

```text
static findings become tracked artifacts
```

---

# 41. Triage mode

Slither offre una modalità di triage:

```bash
slither . \
  --triage-mode
```

Può memorizzare risultati da nascondere in run successive.

Questo è utile per mantenere segnale/rumore.

Ma non usare il triage come:

```text
"hide anything annoying"
```

Per ogni finding nascosto dovrebbe esistere una ragione documentata.

---

# 42. Inline suppressions

Slither supporta commenti per disabilitare detector specifici su righe/sezioni.

Questo può essere utile per falsi positivi noti.

Ma ogni suppression dovrebbe spiegare:

```text
perché è safe
```

Esempio concettuale:

```solidity
// slither-disable-next-line DETECTOR
// Safe because ...
```

La suppression senza razionale crea debito di sicurezza.

---

# 43. False positive

Definizione pratica:

> Il detector ha identificato un pattern, ma nel contesto reale la proprietà vulnerabile non è raggiungibile o non esiste.

Esempio:

```text
external call segnalata come reentrancy risk
```

ma:

```text
funzione non modifica stato critico
+
callee è trusted immutable contract
+
property non può essere violata
```

Potrebbe essere un falso positivo.

Devi dimostrarlo, non dichiararlo.

---

# 44. False negative

Più pericoloso:

```text
bug reale
ma tool non segnala nulla
```

Esempio:

```text
wrong economic formula
wrong oracle pair
insufficient slippage
governance bypass
business state-machine bug
```

Gli static analyzer non possono comprendere automaticamente tutta la specification.

Per questo l'assenza di finding non è una prova di sicurezza.

---

# 45. Severity reale

Quando confermi un finding, valuta:

```text
asset at risk
privileges required
preconditions
repeatability
user interaction
recoverability
scope
```

Il rating del detector è solo input.

Non copiare automaticamente:

```text
Slither: High
=> audit finding: High
```

---

# 46. Reentrancy detector

Slither ha detector per differenti pattern di reentrancy.

Ma il risultato va letto con CEI e invariant mindset.

Domande:

```text
external call dove?
state write prima/dopo?
same-function?
cross-function?
shared state?
callee controllabile?
```

Una reentrancy warning è l'inizio della review.

---

# 47. Reentrancy e trusted contract

Anche se oggi:

```text
callee = trusted contract
```

chiediti:

```text
immutable?
upgradeable?
proxy?
governance-controlled?
```

Una trust assumption può cambiare nel tempo.

Lezione 10 e 11 si applicano qui.

---

# 48. Uninitialized state

Slither può segnalare variabili di stato mai inizializzate.

Esempio:

```solidity
address public oracle;
```

usato prima che:

```solidity
oracle = ...
```

sia garantito.

Nel mondo proxy è particolarmente importante:

```text
initializer missing
```

può lasciare ruoli/config a zero.

---

# 49. Unprotected upgrade

Slither include detector relativi a upgradeability.

Un UUPS/proxy con upgrade authorization errata è ad alto impatto.

Ma anche qui:

```text
tool sees pattern
```

l'auditor deve verificare:

```text
actual proxy architecture
initializer
admin path
role graph
timelock
```

---

# 50. `vars-and-auth` per upgrade authority

Nel nostro Escrow UUPS:

```text
implementation slot
```

non è una normale variabile Solidity applicativa, ma puoi comunque usare la review combinata:

```text
_authorizeUpgrade
owner
role graph
```

con printer e source review.

La domanda è:

```text
chi può portare execution path fino all'upgrade?
```

---

# 51. Call graph per governance

Per:

```text
Timelock
-> Proxy
-> Implementation
->_authorizeUpgrade
```

un graph aiuta a vedere i componenti.

Ma non mostra necessariamente:

```text
off-chain multisig threshold
operational ownership
```

La governance completa richiede anche config review.

---

# 52. Third lab — apparent reentrancy

Contratto:

```solidity
contract NotifierExample {
    bool public done;

    function finish(
        INotifier notifier
    ) external {
        done = true;

        notifier.notify();
    }
}
```

External call dopo state update.

Slither può comunque evidenziare pattern a seconda del contesto.

Manual review:

```text
done set prima
notifier untrusted
callback possible
ma quale property potrebbe rompersi?
```

Se non esiste funzione che sfrutta `done` in modo pericoloso, il finding potrebbe non essere vulnerabilità.

---

# 53. Il metodo corretto con finding reentrancy

Scrivi:

```text
External call:
    notifier.notify()

State touched before:
    done = true

State touched after:
    none

Cross-function shared state:
    ?

Possible callback:
    ?

Invariant:
    ?
```

Se non sai scrivere l'invariante violabile, non hai ancora confermato il bug.

---

# 54. Compiler warning + Slither + test

Un workflow molto forte:

```text
forge build
  |
  v
compiler warnings
  |
  v
slither .
  |
  v
triage
  |
  v
forge regression test
```

Static analysis suggerisce dove guardare.

Dynamic test dimostra la proprietà.

---

# 55. Analisi manuale prima dei detector?

Durante un audit professionale conviene non dipendere completamente dai tool.

Una strategia utile:

```text
1. overview architetturale
2. critical invariants
3. manual first pass
4. static tooling
5. compare findings
```

Così Slither non "ancora" tutta la tua attenzione sui pattern che sa riconoscere.

---

# 56. Oppure tool-first?

Per codebase grandi, puoi usare printer/tooling all'inizio per costruire rapidamente una mappa:

```text
contracts
entry points
call graph
inheritance
```

Poi fare manual review.

Quindi:

```text
printer-first
```

è diverso da:

```text
detector-first
```

I printer sono ottimi per orientation.

---

# 57. Inheritance graph

```bash
slither . \
  --print inheritance-graph
```

Molto utile con:

```text
OwnableUpgradeable
UUPSUpgradeable
AccessControl
Pausable
custom bases
```

L'inheritance influenza:

```text
modifiers
storage
override
initializer chain
```

---

# 58. Upgradeable code review

Per upgradeable contracts, static review deve includere:

```text
constructor
_disableInitializers
initializer
reinitializer
inheritance
storage layout
_authorizeUpgrade
```

Slither può aiutare, ma integra anche:

```text
OpenZeppelin validateUpgrade
forge inspect storageLayout
```

Tool specializzati hanno responsabilità diverse.

---

# 59. Slither-check-upgradeability

Il progetto Slither include strumenti dedicati all'upgradeability, oltre ai detector generici.

Questi tool possono aiutare a revisionare pattern `delegatecall`/proxy.

Nel nostro corso:

```text
Slither
+
OpenZeppelin validation
+
manual storage review
```

è più forte di uno solo.

---

# 60. Static analyzer disagreement

Due tool possono produrre risultati diversi.

Non è necessariamente un bug.

Possono avere:

```text
regole diverse
IR diverso
assunzioni diverse
trade-off precision/recall diversi
```

La decisione finale deve tornare alla property e al codice.

---

# 61. SlithIR

Slither usa una representation intermedia, SlithIR, per molte analisi.

Non devi dominarla per usare il tool.

Ma il concetto è utile:

```text
source Solidity
  |
  v
representation più semplice
  |
  v
analisi di control/data flow
```

Questo spiega come detector complessi possano ragionare oltre la semplice regex.

---

# 62. Regex scanner vs static analyzer

Un grep può trovare:

```text
.call(
```

ma non sa necessariamente:

```text
chi controlla target
quale stato viene scritto
data dependency
function visibility
inheritance
```

Slither analizza la struttura del programma.

È molto più potente di text search.

Ma anche più complesso e non infallibile.

---

# 63. Search manuale resta utile

Usa:

```bash
rg "\.call" src/
rg "delegatecall" src/
rg "onlyOwner" src/
rg "approve" src/
rg "transferFrom" src/
```

insieme a Slither.

Text search è ottimo per:

```text
inventario rapido
```

Slither per:

```text
relazioni strutturali
```

---

# 64. Audit query: tutte le external call

Una tecnica manuale:

```text
cerca:
call
delegatecall
staticcall
transfer
safeTransfer
safeTransferFrom
external interface calls
```

Poi per ognuna annota:

```text
callee
controllabilità
state before
state after
return handling
callback risk
```

Slither call graph/function summary può accelerare.

---

# 65. Audit query: tutti i privileged writes

Cerca:

```text
onlyOwner
onlyRole
_authorizeUpgrade
grantRole
transferOwnership
```

Poi usa:

```text
vars-and-auth
```

per collegarli agli state writes.

Questo crea una mappa di governance.

---

# 66. Audit query: user-controlled addresses

Cerca funzioni con:

```solidity
address target
address token
address router
address oracle
```

Poi data-flow:

```text
user input
  |
  v
external call target?
storage config?
allowance spender?
```

Address input sono spesso più pericolosi di semplici `uint256`.

---

# 67. Triage worksheet

Per ogni finding crea:

```text
ID:
Detector:
Location:
Static description:

Reachable from:
Privileges required:
User-controlled inputs:
External calls:
Critical state:
Asset impact:
Invariant potentially violated:

Reproduction:
Status:
    confirmed / false positive / informational

Remediation:
Regression test:
```

Questo rende il processo ripetibile.

---

# 68. Esempio triage completo

Finding:

```text
unchecked-lowlevel
UnsafeCaller.execute
```

Reachable:

```text
public external
```

Caller:

```text
anyone
```

Input:

```text
target
data
```

State:

```text
completed
```

Invariant:

```text
completed => call success
```

Reproduction:

```text
RevertingTarget
```

Status:

```text
confirmed
```

Fix:

```text
check success + bubble revert
```

Regression:

```text
failed call cannot mark completed
```

---

# 69. Falso positivo documentato

Supponiamo detector:

```text
reentrancy warning
```

Triage:

```text
callee immutable trusted library-like contract
state update before call
no state writes after call
no shared mutable state usable by callback
```

Puoi concludere:

```text
not exploitable under stated trust assumptions
```

Ma documenta l'assunzione:

```text
callee must remain immutable/non-upgradeable
```

Se in futuro diventa proxy, la conclusione cambia.

---

# 70. Tool findings cambiano con la codebase

Una suppression valida oggi può non esserlo domani.

Per esempio:

```text
external call previously harmless
```

ma V2 aggiunge:

```text
state write after call
```

Il vecchio triage potrebbe diventare obsoleto.

Per questo suppressions e false-positive decisions vanno reviewate nei diff.

---

# 71. Baseline

In una codebase esistente con molti finding, puoi creare una baseline:

```text
known findings
```

e in CI fallire soltanto su:

```text
new findings
```

Questo aiuta ad adottare static analysis gradualmente.

Ma il backlog storico resta debito di sicurezza.

---

# 72. CI

Pipeline concettuale:

```text
forge fmt --check
forge build
forge test
forge coverage
slither .
```

Poi:

```text
upgrade validation
fuzz/invariant deep profile
```

a seconda del progetto.

Slither può esportare JSON/SARIF per CI.

---

# 73. Fail CI su quale severity?

Non esiste una soglia universale.

Possibile policy:

```text
High/Medium new findings -> fail
Low/Info -> review
```

Ma:

```text
severity tool
```

non equivale sempre a:

```text
severity business
```

Meglio combinare CI gating con baseline/triage disciplinato.

---

# 74. Compiler version

La documentazione Solidity raccomanda di usare versioni recenti del compiler per beneficiare dei warning e fix più recenti.

Ma un progetto production deve anche gestire:

```text
reproducible builds
audited compiler version
dependency compatibility
```

Non aggiornare compiler in modo casuale senza test/regression.

---

# 75. Known compiler bugs

La documentazione Solidity mantiene informazioni sui bug noti del compiler.

Per review avanzata:

```text
solc version usata
```

fa parte del threat model.

Un audit serio deve sapere:

```text
con quale compiler è stato prodotto il bytecode?
```

---

# 76. Static analysis e inline assembly

Assembly/Yul può ridurre la capacità degli analyzer di ragionare con precisione.

Quando trovi:

```solidity
assembly {
    ...
}
```

aumenta l'attenzione manuale.

Domande:

```text
memory safety?
storage slot?
returndata?
delegatecall?
revert bubbling?
```

Non assumere che un tool comprenda ogni semantica custom.

---

# 77. Custom detectors

Slither espone API per scrivere analisi custom in Python.

Questo è molto potente per protocolli grandi con regole specifiche.

Esempio:

```text
"ogni funzione che modifica oracle
deve avere modifier X"
```

Un detector custom può automatizzare una policy organizzativa.

Non lo implementiamo oggi, ma è importante sapere che static analysis può essere protocol-specific.

---

# 78. Protocol-specific rule

Immagina requisito:

```text
ogni setOracle deve:
- essere onlyRole(ORACLE_ADMIN)
- emettere OracleUpdated
- rifiutare zero
```

I detector generici non conoscono questa policy.

Puoi:

```text
testarla
reviewarla
creare detector custom
```

Security automation diventa più forte quando incorpora la specification.

---

# 79. Slither non conosce il "giusto prezzo"

Può vedere:

```solidity
price = oracle.latestAnswer();
```

ma non sa automaticamente che:

```text
feed ETH/USD
```

è stato sostituito con:

```text
BTC/USD
```

La semantica economica resta responsabilità dell'audit manuale.

---

# 80. Slither non conosce il "giusto threshold"

Può vedere:

```text
multisig
timelock
roles
```

ma non può decidere automaticamente che:

```text
1-of-5
```

sia troppo debole per il tuo threat model.

Questa è governance analysis.

---

# 81. Slither non conosce la specification completa

Quindi:

```text
no findings
```

significa:

```text
nessun pattern noto rilevato
nelle analisi eseguite
```

non:

```text
contratto sicuro
```

Questa frase va ricordata.

---

# 82. Static analysis + fuzzing

Ottima combinazione:

```text
Slither:
"questa area sembra rischiosa"

Fuzz/invariant:
"proviamo molte condizioni"
```

Esempio:

```text
Slither segnala reentrancy-like path
```

poi scrivi:

```text
stateful invariant assets >= liabilities
```

per verificare la proprietà.

---

# 83. Static analysis + coverage

Call graph/CFG:

```text
quali path esistono?
```

Coverage:

```text
quali path abbiamo eseguito?
```

Confrontando i due puoi trovare:

```text
branch critici non testati
```

---

# 84. Static analysis + mutation testing

Detector:

```text
authorization present
```

Mutation:

```text
rimuovi onlyOwner
```

Regression test:

```text
deve fallire
```

Tre angoli diversi sulla stessa proprietà.

---

# 85. Audit workflow integrato

Per il nostro Escrow:

```text
1. forge build
2. compiler warnings
3. slither --print human-summary
4. slither --print entry-points
5. slither --print vars-and-auth
6. slither --print call-graph
7. slither .
8. manual triage
9. forge reproduction tests
10. fix
11. regression
12. fuzz/invariant rerun
```

Questo è già un workflow molto vicino a un audit reale.

---

# 86. Laboratorio: progetto intentionally noisy

Crea:

## `src/static/StaticLab.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract StaticLab {
    address public admin;

    bool public completed;

    constructor(address admin_) {
        admin = admin_;
    }

    function unsafeExecute(
        address target,
        bytes calldata data
    ) external {
        target.call(data);

        completed = true;
    }

    function arbitraryExecute(
        address target,
        bytes calldata data
    ) external {
        (
            bool ok,
        ) = target.call(data);

        require(ok);
    }

    function setAdmin(
        address newAdmin
    ) external {
        // INTENZIONALMENTE SENZA AUTH
        admin = newAdmin;
    }
}
```

Non usare fuori dal lab.

---

# 87. Prima run

```bash
forge build
slither .
```

Non correggere subito.

Per ogni finding:

```text
copialo nel triage worksheet
```

Poi classifica.

---

# 88. Possibile finding 1 — unchecked call

```text
unsafeExecute
```

Conferma con test.

---

# 89. Possibile finding 2 — access control

```text
setAdmin
```

La variabile:

```text
admin
```

sembra security-critical.

Ma il tool può o non può rappresentare esattamente la tua intended policy.

Manual property:

```text
solo current admin può cambiare admin
```

Test negativo:

```text
stranger cannot setAdmin
```

---

# 90. Possibile finding 3 — arbitrary external call

`arbitraryExecute` controlla `success`.

Quindi non è unchecked.

Ma:

```text
target/data user-controlled
```

crea comunque una capability enorme.

Questo finding potrebbe emergere con detector specifici o dalla manual review.

È un esempio didattico per non affidarsi solo alla lista Slither.

---

# 91. Fix `setAdmin`

```solidity
error OnlyAdmin();

function setAdmin(
    address newAdmin
) external {
    if (
        msg.sender != admin
    ) {
        revert OnlyAdmin();
    }

    admin = newAdmin;
}
```

Poi regression:

```solidity
function test_StrangerCannotSetAdmin()
    public
{
    vm.prank(stranger);

    vm.expectRevert(
        StaticLab
            .OnlyAdmin
            .selector
    );

    lab.setAdmin(stranger);
}
```

---

# 92. Rerun

Dopo fix:

```bash
forge test
slither .
```

Una remediation completa deve:

```text
ridurre finding
+
mantenere behavior corretto
+
non introdurre regressioni
```

---

# 93. Triage dei low/info findings

Non ignorarli automaticamente.

Categorie utili:

```text
style
maintainability
dead code
complexity
future security risk
```

Esempio:

```text
state variable unused
```

potrebbe essere solo pulizia.

Oppure:

```text
un intended guard variable
mai letto
```

potrebbe indicare feature security incompleta.

---

# 94. Complexity

Codice complesso è più difficile da auditare.

La documentazione Solidity raccomanda di mantenere i contratti piccoli e modulari.

Static metrics possono aiutare a individuare:

```text
funzioni troppo grandi
inheritance profonda
troppi branches
```

Non sono vulnerabilità da sole.

Sono risk multipliers.

---

# 95. Modularità vs composability

Separare codice in moduli può migliorare la leggibilità.

Ma se trasformi funzioni interne in:

```text
external contracts
```

aumenti anche:

```text
trust boundaries
external calls
upgrade risks
```

Quindi "modularità" non significa automaticamente "più contratti esterni".

---

# 96. Review del diff

Slither è utile anche su modifiche.

Per una PR:

```text
quali finding nuovi?
quali suppressions nuove?
quali privileged writes nuovi?
quali external calls nuove?
```

Il diff di sicurezza è spesso più importante di rileggere sempre tutto da zero.

---

# 97. Security review di una nuova external call

Quando il diff aggiunge:

```solidity
router.execute(...)
```

chiedi immediatamente:

```text
chi controlla router?
return value?
revert policy?
state before?
state after?
callback?
allowance?
upgradeable target?
```

Slither può segnalarne alcuni aspetti.

La checklist completa resta manuale.

---

# 98. Checklist da auditor — static analysis

```text
[ ] forge build pulito?
[ ] compiler warnings compresi?
[ ] Slither compila il progetto?
[ ] human-summary esaminato?
[ ] entry points inventariati?
[ ] inheritance graph compreso?
[ ] call graph esaminato?
[ ] vars-and-auth esaminato?
[ ] detector run completo?
[ ] high/medium triaged?
[ ] low/info campionati e compresi?
[ ] dependencies filtrate con criterio?
[ ] false positive documentati?
[ ] suppressions motivate?
[ ] JSON/SARIF salvato in CI?
[ ] finding confermati riprodotti in test?
[ ] fix accompagnati da regressioni?
[ ] upgradeability verificata con tool dedicati?
[ ] business logic ancora reviewata manualmente?
```

---

# 99. Checklist per ogni finding

```text
Detector:
Location:

Reachable?
Caller?
Privileges?
Inputs controlled?
State read?
State written?
External calls?
Asset impact?
Dependency assumptions?
Invariant violated?
Reproduction possible?
Confirmed?
False positive?
Remediation?
Regression test?
```

Se non riesci a compilare questa scheda, il finding non è ancora sufficientemente analizzato.

---

# 100. Esercizi

## Esercizio 1 — Inventory

Sul progetto Escrow:

```bash
slither . --print entry-points
```

Classifica ogni entry point:

```text
user
admin
governance
view
callback
```

---

## Esercizio 2 — Vars and auth

Esegui:

```bash
slither . --print vars-and-auth
```

Scegli:

```text
oracle
fee
owner
state
escrowedAmount
```

e identifica ogni write path.

---

## Esercizio 3 — Call graph

Genera il call graph.

Trova tutte le funzioni che possono raggiungere:

```text
ERC20 transfer
oracle call
router call
delegatecall
```

---

## Esercizio 4 — Confirm a finding

Usa `UnsafeCaller`.

1. esegui Slither;
2. identifica il finding;
3. riproducilo con Foundry;
4. correggi;
5. aggiungi regression test;
6. rilancia Slither.

---

## Esercizio 5 — False positive analysis

Crea una funzione:

```solidity
state = DONE;
trustedNotifier.notify();
```

Valuta un eventuale warning di reentrancy.

Scrivi in prosa:

```text
quale invariant potrebbe essere violato?
```

Se nessuno, giustifica il triage.

---

## Esercizio 6 — User-controlled target

Analizza:

```solidity
function execute(
    address target,
    bytes calldata data
) external {
    (
        bool ok,
    ) = target.call(data);

    require(ok);
}
```

Elenca almeno dieci domande di threat modeling che Slither da solo non può risolvere.

---

## Esercizio 7 — Suppression

Scegli un finding realmente non applicabile.

Aggiungi una suppression locale con commento che spieghi:

```text
perché il pattern è safe
quale assumption lo rende safe
```

Poi chiediti:

```text
cosa renderebbe obsoleta questa assumption?
```

---

## Esercizio 8 — CI artifact

Genera:

```bash
slither . \
  --json slither-report.json
```

Apri il JSON e identifica:

```text
detector
impact
confidence
source mapping
description
```

---

## Esercizio 9 — Compiler warnings

Introduci volontariamente un warning innocuo in un contratto locale.

Osserva:

```bash
forge build
```

Poi elimina il warning.

L'obiettivo è sviluppare la disciplina:

```text
warning = investigare
```

non:

```text
warning = ignorare
```

---

## Esercizio 10 — Audit challenge

Analizza:

```solidity
contract Manager {
    address public router;
    address public owner;

    constructor(
        address router_,
        address owner_
    ) {
        router = router_;
        owner = owner_;
    }

    function setRouter(
        address newRouter
    ) external {
        router = newRouter;
    }

    function execute(
        bytes calldata data
    ) external {
        router.call(data);
    }
}
```

Trova:

```text
static-analysis findings plausibili
+
business/security findings che richiedono manual review
```

Separali in due colonne.

---

# 101. Cosa devo ricordare

### 1. Slither trova candidati, non emette verità assolute

Ogni finding richiede triage.

---

### 2. Static analysis e testing sono complementari

```text
static -> dove guardare
dynamic -> dimostra behavior
```

---

### 3. Il compiler è parte della security toolchain

Non ignorare warning senza capirli.

---

### 4. Printer come `entry-points`, `vars-and-auth` e `call-graph` sono strumenti da auditor

Non servono solo i detector.

---

### 5. Impact e confidence del tool non sono la severity finale

Il contesto economico decide la gravità reale.

---

### 6. L'assenza di finding non dimostra sicurezza

Business logic, oracle semantics e governance possono essere sbagliati senza alert statici.

---

### 7. Segui source → sink

Input utente, oracle e ruoli devono essere tracciati fino a:

```text
asset transfer
critical state write
external target
upgrade
```

---

### 8. Ogni finding confermato deve diventare un test di regressione

---

### 9. Documenta i falsi positivi

Una suppression senza spiegazione è debito di sicurezza.

---

### 10. Static analysis è parte di un audit workflow, non il suo sostituto

---

# 102. Workflow consigliato

Per il nostro progetto:

```text
forge fmt --check
       |
       v
forge build
       |
       v
compiler warnings
       |
       v
Slither printers
       |
       v
Slither detectors
       |
       v
manual triage
       |
       v
Foundry reproduction
       |
       v
fix
       |
       v
regression
       |
       v
fuzz + invariant
```

Questo workflow comincia a unire quasi tutti i concetti studiati finora.

---

# 103. Fonti della lezione

Fonti tecniche consultate il **22 settembre 2026**:

1. **Slither — repository ufficiale Trail of Bits / Crytic**  
   Feature, detector, printer, integrazione con Foundry e tool aggiuntivi.  
   https://github.com/crytic/slither

2. **Slither Wiki — Usage**  
   Uso di `slither .`, selezione/esclusione detector, printer, path filtering, JSON output, triage mode e configurazione.  
   https://github.com/crytic/slither/wiki/Usage

3. **Slither — detector catalog**  
   Elenco corrente dei detector con impact e confidence.  
   Disponibile dal repository ufficiale e tramite:
   ```bash
   slither --list-detectors
   ```

4. **Slither — Printers**  
   `human-summary`, `contract-summary`, `entry-points`, `function-summary`, `vars-and-auth`, `call-graph`, `cfg`, `inheritance-graph`.  
   Repository/documentazione ufficiale Crytic.

5. **Slither — Data Dependency**  
   Analisi delle dipendenze dati a livello di funzione/contratto e dipendenze transitive.  
   https://github.com/crytic/slither/wiki/Data-dependency

6. **Solidity Documentation — Security Considerations**  
   Raccomandazione ufficiale di prendere sul serio i compiler warning, mantenere il codice piccolo/modulare e considerare le external call come security-sensitive.  
   https://docs.soliditylang.org/en/latest/security-considerations.html

7. **Solidity Documentation — Using the Compiler**  
   Tipi di messaggio del compiler (`Warning`, `Info`, errori) e comportamento della toolchain.  
   https://docs.soliditylang.org/en/latest/using-the-compiler.html

8. **Foundry Documentation**  
   Build, test, regression, filtering e integrazione del workflow locale usato per confermare i finding.  
   https://getfoundry.sh/

---

## Fine Lezione 15

La **Lezione 16** non è inclusa in questo file.

Prossimo argomento:

**Metodologia di audit completa: scoping, threat model, invarianti, attack surface, privileged paths, external dependencies, manual review, static analysis, testing, severity, finding writing e final checklist.**
