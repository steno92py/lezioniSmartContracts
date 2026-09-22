# Lezione 16 — Metodologia di Audit Completa per Smart Contract

> **Scopo:** auditing manuale, threat modeling, secure review e validazione tecnica.
>
> Tutti gli esempi e le riproduzioni restano confinati a **Foundry/Anvil locale**, account di test, mock e contratti giocattolo.

---

## 1. Obiettivi

Alla fine della lezione dovresti saper:

- definire correttamente scope, commit e configurazione di un audit;
- distinguere in-scope, out-of-scope, assumptions e trust boundaries;
- costruire un threat model;
- derivare invarianti dal protocol design;
- inventariare entry point, ruoli, asset, storage critico, external call, dependency e upgrade path;
- eseguire una review manuale strutturata;
- usare Slither e Foundry come strumenti di supporto;
- distinguere osservazione, ipotesi e finding confermato;
- riprodurre localmente un finding;
- valutare impatto e prerequisiti;
- scrivere un finding tecnico di qualità;
- fare retest della remediation;
- produrre una checklist finale da auditor.

---

## 2. Modello mentale

Un audit non è:

```text
apro il codice
cerco reentrancy
cerco access control
scrivo report
```

È:

```text
scope
  |
  v
architecture understanding
  |
  v
assets + trust
  |
  v
properties / invariants
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
findings
  |
  v
reproduction
  |
  v
severity / impact reasoning
  |
  v
remediation
  |
  v
retest
```

La parte più importante viene prima dei detector:

> **capire che cosa il protocollo promette.**

---

## 3. Scope prima del codice

Prima di leggere una funzione, devi sapere quale sistema stai auditando.

Registra almeno:

```text
Repository:
Commit:
Compiler:
Foundry version:
OpenZeppelin version:
Chains intended:
Proxy pattern:
Upgradeable? yes/no
External protocols:
External tokens:
Oracle providers:
Admin model:
Known assumptions:
Excluded components:
```

Un audit senza commit stabile è ambiguo: se il codice cambia, devi almeno revieware il diff e rieseguire le verifiche rilevanti.

---

## 4. Build riproducibile

Prima fase:

```bash
forge build
forge test
```

Registra:

```text
solc version
optimizer settings
evm_version
via_ir
remappings
```

Il bytecode dipende dalla configurazione di compilazione.

Non basta sapere quale sorgente hai davanti.

---

## 5. Dependency inventory

Elenca:

```text
OpenZeppelin
oracle libraries
token interfaces
proxy libraries
math libraries
external protocol interfaces
```

Per ciascuna:

```text
versione
source
modificata?
vendored?
runtime o compile-time?
upgradeable?
```

Ricorda:

```text
compile-time dependency != runtime dependency
```

ma entrambe fanno parte del threat model.

---

## 6. Architecture pass

Prima passata:

```text
capire il sistema
```

non cercare ancora bug.

Disegna:

```text
Buyer
  |
  v
Escrow
  |   |  \--> Oracle
  |
  +-----> Token
  |
  +-----> Router

Governance
  |
  v
Timelock
  |
  v
Proxy
  |
  v
Implementation
```

Se non sai disegnare il sistema, la review dettagliata è prematura.

---

## 7. Asset inventory

Domanda:

> Che cosa vale qualcosa?

Non soltanto token.

Esempi:

```text
ETH
ERC20
NFT
claim
minting authority
upgrade authority
oracle authority
governance votes
allowances
locked collateral
future withdrawal rights
```

Una chiave admin può essere un asset più importante di un saldo.

---

## 8. Actor inventory

Elenca:

```text
buyer
seller
owner
pauser
upgrader
oracle admin
multisig
timelock
external token
external router
unprivileged user
malicious contract
```

Per ciascuno:

```text
quali funzioni può chiamare?
quale stato può influenzare?
quali dipendenze controlla?
```

---

## 9. Trust assumptions

Esempio:

```text
Token:
exact-transfer ERC20
no rebase
no fee

Oracle:
fresh within 1h
8 decimals
ETH/USD

Governance:
3-of-5 multisig
48h timelock

Router:
allowlisted
upgradeable by external governance
```

Un audit deve distinguere:

```text
bug
```

da:

```text
assumption
```

Se l'assumption è fragile, può diventare un finding di design.

---

## 10. Threat model

Per ogni asset chiedi:

```text
chi può rubarlo?
chi può bloccarlo?
chi può svalutarlo?
chi può falsificare il diritto su di esso?
chi può cambiare le regole che lo proteggono?
```

Categorie utili:

```text
Authorization
State machine
Accounting
External calls
Reentrancy
Oracle
Economic assumptions
Governance
Upgradeability
Token integration
DoS/liveness
Configuration
Precision/rounding
MEV/order dependence
```

OWASP SCSVS tratta threat modeling, authorization, secure interactions e oracle validation come aree esplicite di verifica.

---

## 11. Invariants first

Prima della review dettagliata, scrivi proprietà.

Per il nostro Escrow:

```text
I1:
solo buyer può depositare

I2:
Funded può diventare
Released XOR Refunded

I3:
terminal state non torna indietro

I4:
liabilities <= assets

I5:
release non può pagare due volte

I6:
oracle stale non influenza decisioni price-sensitive

I7:
solo governance autorizzata può upgradeare

I8:
upgrade preserva state layout e business invariants
```

Queste proprietà guidano l'audit.

---

## 12. Requirement matrix

| ID | Requirement | Code Path | Test | Status |
|---|---|---|---|---|
| I1 | solo buyer deposita | `deposit` | auth test | review |
| I2 | terminal exclusivity | `release/refund` | state tests | review |
| I4 | solvibilità | token/accounting | invariant test | review |
| I6 | stale price reject | oracle adapter | fuzz test | review |
| I7 | upgrade auth | UUPS | upgrade test | review |

Questa tabella crea tracciabilità:

```text
requirement -> code -> test -> review result
```

---

## 13. Entry-point inventory

Elenca:

```text
external
public
fallback
receive
initializer
reinitializer
upgrade functions
callbacks
```

Classifica:

```text
user
admin
governance
external callback
view
```

Slither può aiutare:

```bash
slither . --print entry-points
```

---

## 14. Function-by-function review

Per ogni funzione critica annota:

```text
Caller:
Inputs:
msg.value:
State reads:
State writes:
External calls:
Control transfer:
Authorization:
Preconditions:
Postconditions:
Assumptions:
Failure modes:
```

Questa è la stessa struttura usata nel corso fin dalla Lezione 1, ora applicata sistematicamente.

---

## 15. Storage-centric review

Non leggere solo per funzione.

Scegli una variabile critica:

```text
oracle
owner
state
escrowedAmount
implementation
feeBps
```

e chiedi:

```text
chi può scriverla?
da quali funzioni?
con quale authorization?
con quali bounds?
```

Questo è il **write-path analysis**.

---

## 16. Esempio: `oracle`

Possibili write path:

```text
initialize()
setOracle()
emergencySetOracle()
upgrade migration?
```

Se uno solo bypassa il timelock, la frase:

```text
"oracle changes are delayed"
```

è falsa.

---

## 17. Privileged-path review

Fai una passata dedicata a:

```text
onlyOwner
onlyRole
_authorizeUpgrade
grantRole
revokeRole
pause
unpause
setOracle
setRouter
setFee
```

Domande:

```text
chi ha il ruolo?
chi può concederlo?
chi può revocarlo?
esiste bypass?
esiste timelock?
```

---

## 18. External-call review

Cerca:

```text
.call
delegatecall
staticcall
safeTransfer
safeTransferFrom
oracle calls
router calls
hooks
callbacks
```

Per ognuna annota:

```text
callee controllabile?
return checked?
state before?
state after?
callback possible?
failure policy?
```

OWASP include secure external interactions, CEI e gestione delle low-level/arbitrary calls tra i controlli rilevanti.

---

## 19. Reentrancy review

Non cercare soltanto il pattern classico:

```text
send ETH
then balance = 0
```

Cerca:

```text
shared state
cross-function interaction
cross-contract callback
read-only assumptions
```

L'invariante da proteggere resta la guida.

---

## 20. Accounting review

Per ogni asset:

```text
balance reale
vs
accounting interno
```

Domande:

```text
quando aumenta?
quando diminuisce?
chi crea liability?
chi la rimuove?
assets >= liabilities?
```

Per ERC20:

```text
requested
vs
received
```

Per oracle:

```text
raw price
vs
economically valid price
```

---

## 21. State-machine review

Disegna:

```text
Created -> Funded -> Released
                 \-> Refunded
```

Poi verifica:

```text
ogni edge lecito implementato?
edge illecito possibile?
stato terminale?
double execution?
```

Molti errori logici sono transizioni inattese.

---

## 22. Boundary review

Ogni constraint:

```text
fee <= 1000
age <= MAX_AGE
amount > 0
threshold >= 2
```

richiede casi:

```text
below
exact
above
```

`>` e `>=` sono differenze di security specification.

---

## 23. Zero / max review

Controlla:

```text
address(0)
amount = 0
price = 0
timestamp = 0
threshold = 0
type(uint256).max
```

Zero può essere:

```text
valido
sentinel
errore
```

ma deve essere intenzionale.

I massimi sono importanti soprattutto in:

```text
multiplication
allowance
fee
deadline
price scaling
```

---

## 24. Token integration review

Per ogni token supportato:

```text
standard return?
false return?
no return?
fee-on-transfer?
rebasing?
pause?
blacklist?
upgradeable?
decimals?
```

Poi confronta con la policy dichiarata dal protocollo.

---

## 25. Oracle review

Checklist:

```text
feed corretto?
pair corretto?
decimals?
price > 0?
updatedAt?
maxAge?
fallback?
admin-set?
multi-source?
```

OWASP SCSVS richiede validazione dei dati oracle, gestione dei failure e affidabilità delle sorgenti.

---

## 26. Economic review

Domande:

```text
price manipulation?
slippage bounds?
liquidity assumptions?
MEV/order dependence?
rounding arbitrage?
fee incentives?
```

Questa è una delle aree meno automatizzabili.

---

## 27. Governance review

Disegna:

```text
signers
  |
  v
multisig
  |
  v
timelock
  |
  v
proxy
```

Cerca bypass:

```text
emergency admin?
direct owner?
guardian?
module?
```

La property:

```text
"all upgrades are timelocked"
```

deve valere per tutti i path.

---

## 28. Upgrade review

Checklist:

```text
proxy type?
implementation slot?
initializer?
_disableInitializers?
_authorizeUpgrade?
storage layout?
reinitializer?
migration?
timelock?
```

Strumenti:

```bash
forge inspect ...
```

più validation OpenZeppelin e review manuale.

---

## 29. Liveness review

Security non significa soltanto prevenire furto.

Domande:

```text
utente può ritirare?
oracle down blocca tutto?
notifier blocca withdrawal?
governance può deadlock?
loop cresce senza bound?
```

Una dipendenza può creare permanent lock senza rubare nulla.

---

## 30. Tool pass

Dopo la comprensione manuale:

```bash
forge build
forge test
forge coverage
slither .
```

Poi:

```bash
slither . --print human-summary
slither . --print vars-and-auth
slither . --print call-graph
```

Slither documenta printer come `human-summary`, `entry-points`, `call-graph`, `function-summary` e `vars-and-auth` specificamente per supportare la review.

---

## 31. Perché non basta il tool

Se parti solo dai detector, cercherai soprattutto:

```text
ciò che il tool sa riconoscere
```

Potresti perdere:

```text
wrong business invariant
wrong oracle pair
economic mismatch
governance bypass
```

Usa il tool per amplificare la review, non per sostituirla.

---

## 32. Hypothesis-driven audit

Quando vedi qualcosa di strano, scrivi una ipotesi.

Esempio:

```text
H1:
Fee-on-transfer token può causare
credit > actual balance.
```

Poi:

```text
leggi codice
costruisci mock
scrivi test
```

Se il test conferma:

```text
finding
```

altrimenti:

```text
ipotesi falsificata
```

---

## 33. Observation → Hypothesis → Evidence → Finding

Esempio:

### Observation

```text
deposit accredita requestedAmount
```

### Hypothesis

```text
un token con fee può creare liability maggiore degli asset
```

### Evidence

```text
local FeeToken:
requested 100
received 90
credit 100
```

### Finding

```text
nominal accounting can create undercollateralized liabilities
```

Questa sequenza è più rigorosa di:

```text
"sembra vulnerabile"
```

---

## 34. Reproduction criteria

Una buona riproduzione deve essere:

```text
minimal
deterministic
authorized
self-contained
```

Non serve mainnet fork se un toy contract dimostra la causa.

Nel nostro corso la PoC serve a dimostrare:

```text
quale proprietà viene violata?
```

---

## 35. Regression immediately

Quando confermi un bug:

```text
aggiungi subito
test_Regression_...
```

Questo stabilizza il finding e facilita il retest.

---

## 36. Severity reasoning

Non copiare la severity di Slither.

Ragiona su:

```text
Impact
+
Preconditions / Likelihood
```

Domande:

```text
loss of funds?
permanent lock?
unauthorized mint?
unauthorized upgrade?
temporary DoS?
privileges required?
user interaction required?
repeatable?
recoverable?
```

---

## 37. Impact examples

Possibili impatti:

```text
fund loss
fund freeze
governance takeover
unauthorized mint
accounting corruption
oracle mispricing
temporary DoS
incorrect off-chain indexing
```

La stessa primitive tecnica può avere gravità molto diverse.

---

## 38. Preconditions

Esempio:

```text
requires compromised owner
```

non significa automaticamente:

```text
not a problem
```

Può essere un governance/centralization risk.

Ma il threat model è diverso da:

```text
any unprivileged caller
```

---

## 39. Writing a finding

Template:

```text
Title

Severity

Summary

Impact

Root Cause

Preconditions

Local Reproduction

Recommendation

Regression Test
```

---

## 40. Titolo

Debole:

```text
Reentrancy
```

Meglio:

```text
External callback before credit update
allows repeated payment of the same liability
```

Il titolo dovrebbe descrivere:

```text
causa + effetto
```

---

## 41. Summary

Deve essere breve e concreta.

Esempio:

```text
withdraw transfers Ether before reducing the caller's
credit. A recipient contract can reenter while the old
credit is still visible, causing the same liability to be
paid multiple times.
```

---

## 42. Impact

Collega sempre alla property.

```text
A user can receive more assets than their recorded credit,
making the contract insolvent and preventing later users
from withdrawing.
```

Meglio di:

```text
"funds at risk"
```

---

## 43. Root Cause

Descrivi perché il bug esiste.

```text
The contract transfers control externally before clearing
the accounting liability.
```

La root cause è più utile del sintomo.

---

## 44. Recommendation

Non scrivere:

```text
"fix reentrancy"
```

Meglio:

```text
clear/decrement the liability before the external transfer,
preserve transaction atomicity, and add a regression test.
A reentrancy guard can be defense in depth.
```

La remediation deve proteggere la property.

---

## 45. Developer questions

A volte il codice non basta.

Domande:

```text
fee-on-transfer supported?
oracle intended to be upgradeable?
guardian intended to bypass timelock?
seller can be a contract?
```

OWASP raccomanda un approccio di review con accesso a documentazione e sviluppatori quando necessario.

---

## 46. Documentation mismatch

Se docs dicono:

```text
all upgrades have 48h delay
```

ma codice permette:

```text
guardian immediate upgrade
```

esiste un mismatch verificabile tra specification e implementation.

---

## 47. Test review

Audita anche la suite:

```text
solo happy path?
expectRevert generici?
no stale oracle test?
no false-return token?
no upgrade state regression?
```

Una suite debole aumenta il rischio.

---

## 48. Fuzz/invariant review

Per fuzzing:

```text
assumptions?
bounds?
property meaningful?
```

Per invariant:

```text
handler realistico?
ghost variables indipendenti?
state space raggiunto?
no-op eccessivi?
```

Non basta vedere `testFuzz_` o `invariant_` nel repository.

---

## 49. Automated tools are insufficient

OWASP specifica che gli strumenti automatizzati da soli non sono sufficienti per una verifica completa: serve evidenza manualmente validata.

Quindi:

```text
Slither clean
```

non implica:

```text
audit clean
```

---

## 50. Checklist frameworks

OWASP SCSVS può essere usato come griglia:

```text
Architecture / Threat Modeling
Business Logic
Governance
Authorization
Secure Communications / Oracles
Token interactions
Cryptography
```

Checklist Secureum/Cyfrin sono ottimi memory aid.

Ma:

```text
checklist != protocol understanding
```

---

## 51. Audit passes

Una metodologia pratica.

### Pass 1 — Understanding

```text
docs
architecture
actors
assets
trust
invariants
```

### Pass 2 — Critical flows

```text
deposit
withdraw
release
refund
upgrade
oracle update
pause
```

### Pass 3 — Adversarial

Per ogni flow:

```text
wrong caller
wrong state
zero
max
reentrant callee
reverting dependency
malicious token
stale oracle
```

### Pass 4 — Privileged

```text
all admin/governance paths
```

### Pass 5 — Tooling

```text
Slither
coverage
fuzz
invariant
storage layout
```

### Pass 6 — Checklist cross-check

```text
OWASP
Secureum
Cyfrin/Solodit
```

### Pass 7 — Findings consolidation

Unisci duplicati e ragiona per root cause.

---

## 52. Root-cause grouping

Se:

```text
setOracle
setRouter
setToken
```

sono tutti non protetti a causa dello stesso design, potresti avere un finding sistemico di access control invece di tre duplicati.

La decisione dipende da:

```text
root cause
impact
remediation
```

---

## 53. False-positive log

Per ogni finding non applicabile:

```text
Finding:
Why false positive:
Assumption:
Evidence:
What future change invalidates this conclusion:
```

Questo è molto utile nei retest.

---

## 54. Work papers

Conserva:

```text
scope
architecture notes
threat model
finding notes
PoC tests
commands
tool output
commit
```

Un audit serio deve essere riproducibile.

---

## 55. Retest

Dopo una remediation:

```text
review diff
run regression
run full suite
rerun Slither
rerun fuzz/invariant rilevanti
```

Non fermarti a:

```text
"developer says fixed"
```

---

## 56. Fix can introduce new bugs

Esempio:

```text
fix reentrancy:
add nonReentrant
```

ma poi:

```text
function A calls function B
both nonReentrant
=> unexpected revert
```

La remediation è nuovo codice e va auditata.

---

## 57. Upgrade remediation

Se il fix richiede un upgrade:

```text
storage compatibility
initializer
migration
governance execution
```

sono parte della sicurezza del fix.

---

## 58. Final report

Una struttura ragionevole:

```text
Executive summary
Scope
Methodology
Architecture / trust assumptions
Findings
Informational observations
Testing/tooling performed
Limitations
Retest status
```

Non promettere:

```text
"no vulnerabilities exist"
```

Meglio:

```text
No additional issues were identified
within the reviewed scope and methodology.
```

---

## 59. Limitations

Esempi:

```text
frontend out of scope
off-chain signer operations not reviewed
oracle provider internals out of scope
third-party protocol behavior assumed as documented
economic simulation limited
```

Essere chiari sulle limitazioni è parte della qualità.

---

## 60. Checklist — Scope

```text
[ ] repository
[ ] commit
[ ] compiler
[ ] config
[ ] in-scope files
[ ] out-of-scope
[ ] dependencies
[ ] chains
[ ] proxy pattern
[ ] deployment assumptions
```

---

## 61. Checklist — Architecture

```text
[ ] architecture diagram
[ ] assets
[ ] actors
[ ] trust boundaries
[ ] dependencies
[ ] governance graph
[ ] upgrade graph
```

---

## 62. Checklist — Invariants

```text
[ ] accounting
[ ] solvency
[ ] authorization
[ ] state machine
[ ] terminality
[ ] oracle freshness
[ ] governance delay
[ ] upgrade preservation
[ ] asset-specific assumptions
```

---

## 63. Checklist — Manual Review

```text
[ ] entry points
[ ] caller control
[ ] calldata
[ ] msg.value
[ ] storage reads
[ ] storage writes
[ ] external calls
[ ] return handling
[ ] CEI
[ ] callbacks
[ ] state transitions
[ ] zero/boundaries
```

---

## 64. Checklist — Dependencies

```text
[ ] tokens
[ ] oracle
[ ] router
[ ] proxies
[ ] admin controllers
[ ] third-party governance
[ ] compile-time libs
[ ] runtime upgradeability
```

---

## 65. Checklist — Governance

```text
[ ] owner
[ ] roles
[ ] role admins
[ ] multisig threshold
[ ] timelock
[ ] bypass paths
[ ] emergency powers
[ ] pause scope
[ ] recovery
```

---

## 66. Checklist — Tooling

```text
[ ] forge build
[ ] forge test
[ ] forge coverage
[ ] fuzz
[ ] invariant
[ ] Slither
[ ] storage layout
[ ] upgrade validation
```

---

## 67. Checklist — Findings

Per ogni finding:

```text
[ ] title
[ ] root cause
[ ] impact
[ ] prerequisites
[ ] reproduction
[ ] severity reasoning
[ ] recommendation
[ ] regression test
```

---

## 68. Checklist — Retest

```text
[ ] fix diff reviewed
[ ] PoC no longer succeeds
[ ] regression passes
[ ] full tests pass
[ ] relevant fuzz rerun
[ ] invariant rerun
[ ] Slither rerun
[ ] upgrade compatibility checked
```

---

## 69. Laboratorio — Mini audit dell'Escrow

Crea:

```text
audit/
├── scope.md
├── architecture.md
├── invariants.md
├── attack-surface.md
├── findings/
└── tests/
```

Non modificare subito il codice.

---

## 70. `scope.md`

Scrivi:

```text
Commit:
Compiler:
In-scope:
Out-of-scope:
Dependencies:
Assumptions:
```

---

## 71. `architecture.md`

Disegna:

```text
buyer
seller
token
escrow proxy
implementation
oracle
router
timelock
multisig
```

Segna:

```text
external calls
upgrade path
admin path
```

---

## 72. `invariants.md`

Scrivi almeno 15 proprietà.

Esempi:

```text
I-01 buyer-only deposit
I-02 no double settlement
I-03 assets >= liabilities
I-04 terminal states final
I-05 stale oracle rejected
I-06 wrong role cannot pause
I-07 upgrade only timelock
I-08 V1 state preserved
```

---

## 73. `attack-surface.md`

| Entry Point | Caller | Writes | External Calls | Risk |
|---|---|---|---|---|
| deposit | buyer | credit/state | token | accounting |
| release | buyer | state | token | callback |
| setOracle | timelock | oracle | none | governance |
| upgrade | timelock | impl slot | delegatecall flow | critical |

---

## 74. Tool pass

Esegui:

```bash
forge build
forge test
forge coverage
slither .
slither . --print entry-points
slither . --print vars-and-auth
```

Salva le note.

---

## 75. Hypothesis pass

Scrivi almeno dieci ipotesi.

Esempio:

```text
H-01:
fee token può rompere equality accounting

H-02:
guardian può bypassare timelock

H-03:
oracle stale boundary off-by-one

H-04:
reinitializer richiamabile due volte
```

Poi prova a falsificarle.

---

## 76. Finding template

```markdown
# [ID] Titolo

Severity:

## Summary

## Impact

## Root Cause

## Preconditions

## Local Reproduction

## Recommendation

## Regression Test
```

Questa sarà la base della Lezione 17.

---

## 77. Audit anti-patterns

### Anti-pattern 1

```text
"Slither non trova niente, siamo sicuri."
```

Falso.

### Anti-pattern 2

```text
"Abbiamo 100% coverage."
```

Non dimostra che le proprietà siano corrette.

### Anti-pattern 3

```text
"Usiamo OpenZeppelin, quindi siamo sicuri."
```

La composizione/configurazione può essere sbagliata.

### Anti-pattern 4

```text
"onlyOwner = safe."
```

Devi sapere chi controlla owner.

### Anti-pattern 5

```text
"ReentrancyGuard ovunque."
```

Non sostituisce accounting e state machine corretti.

### Anti-pattern 6

```text
"Checklist completata = audit completo."
```

Una checklist senza threat model può perdere il bug specifico del protocollo.

---

## 78. Esercizi

### Esercizio 1 — Scope

Prendi una codebase locale di 3-5 contratti e scrivi uno scope formale.

### Esercizio 2 — Assets

Trova almeno dieci asset, senza limitarti ai token.

### Esercizio 3 — Trust graph

Disegna:

```text
owner
pauser
upgrader
timelock
multisig
oracle admin
```

### Esercizio 4 — Invariants

Scrivi venti proprietà prima di usare Slither.

### Esercizio 5 — Write-path

Scegli:

```text
oracle
implementation
feeBps
```

e trova ogni write path.

### Esercizio 6 — External-call table

Per ogni external call annota:

```text
callee
caller-controlled?
return checked?
revert policy?
reentrancy?
```

### Esercizio 7 — Tool finding

Prendi un finding Slither, completa il triage e crea una PoC locale.

### Esercizio 8 — False positive

Documenta:

```text
finding
reason
assumption
evidence
future change that invalidates it
```

### Esercizio 9 — Finding writing

Scrivi un finding completo su un unchecked external call.

### Esercizio 10 — Retest

Introduci un fix locale e poi:

```text
review diff
run regression
run suite
run Slither
```

---

## 79. Cosa devo ricordare

### 1. Scope prima del codice

Devi sapere esattamente che cosa stai auditando.

### 2. Threat model prima dei detector

Asset, attori e trust vengono prima dei tool.

### 3. Invariants guidano la review

Una vulnerabilità è più chiara quando sai quale proprietà rompe.

### 4. Review per funzione e per write-path

Sono due prospettive complementari.

### 5. Privileged paths meritano una passata dedicata

Governance e upgradeability possono dominare il rischio.

### 6. External dependencies ereditano rischio

Token, oracle, router e proxy sono trust boundaries.

### 7. Static analysis genera ipotesi

La conferma richiede contesto ed evidenza.

### 8. Ogni bug confermato deve diventare una regressione

### 9. Severity dipende da impatto e prerequisiti reali

Non copiare il rating del detector.

### 10. Un audit è evidence-driven

Scope, note, test, PoC, diff e retest devono essere riproducibili.

---

## 80. Collegamento con il corso

Ora possiedi tutti i blocchi metodologici:

```text
Solidity / EVM
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
ERC20
     |
     v
oracles / MEV
     |
     v
composability
     |
     v
proxy / upgrades
     |
     v
governance
     |
     v
testing
     |
     v
fuzz / invariants
     |
     v
static analysis
     |
     v
AUDIT METHODOLOGY
```

La prossima lezione sarà il progetto conclusivo:

**Lezione 17 — Audit finale dell'Escrow evoluto.**

---

## 81. Fonti della lezione

Fonti tecniche consultate il **22 settembre 2026**:

1. **OWASP Smart Contract Security Verification Standard (SCSVS)**  
   Framework di requisiti di sicurezza per smart contract EVM.  
   https://scs.owasp.org/SCSVS/

2. **OWASP SCSVS — Architecture, Design and Threat Modeling**  
   Threat identification, risk assessment e mitigazioni.  
   https://scs.owasp.org/SCSVS/05-SCSVS-ARCH/

3. **OWASP SCSVS — Threat Modeling (SCSVS-ARCH-3)**  
   Identificazione, prioritizzazione e verifica delle mitigazioni.  
   https://scs.owasp.org/SCSVS/controls/SCSVS-ARCH-3/

4. **OWASP SCSVS — Authorization Mechanisms**  
   Controlli su `msg.sender`, least privilege e funzioni sensibili.  
   https://scs.owasp.org/SCSVS/controls/SCSVS-AUTH-2/

5. **OWASP SCSVS — Oracle Integrations**  
   Validazione dei dati oracle e failure handling.  
   https://scs.owasp.org/SCSVS/controls/SCSVS-COMM-2/

6. **OWASP SCSVS — Assessment and Certification**  
   Scope esplicito, work papers, evidenza, test scripts e necessità di validazione manuale oltre agli strumenti automatici.  
   https://scs.owasp.org/SCSVS/04-Assessment_and_Certification/

7. **Trail of Bits — Slither**  
   Static analyzer, detector e printer per code understanding.  
   https://github.com/crytic/slither

8. **Slither Usage**  
   Detector, printer, filtering, JSON/SARIF e triage.  
   https://github.com/crytic/slither/wiki/Usage

9. **Cyfrin Updraft — Audit Checklist**  
   Checklist di vulnerability class e domande di review.  
   https://updraft.cyfrin.io/courses/security/bridges/checklist

10. **Cyfrin — Smart Contract Audit Process**  
    Scope, commit hash e processo di review/report.  
    https://www.cyfrin.io/blockchain-security/ethereum-smart-contract-audit

11. **Secureum — Smart Contract Security Checklist**  
    Checklist storica di secure review da reinterpretare alla luce della toolchain moderna.  
    https://secureum.substack.com/p/smart-contract-security-101-secureum

12. **Foundry Documentation**  
    Build, testing, fuzzing, invariant testing e riproduzioni locali.  
    https://getfoundry.sh/

---

## Fine Lezione 16

La **Lezione 17** non è inclusa in questo file.

Prossimo modulo:

**Audit finale dell'Escrow evoluto: scope → threat model → invarianti → manual review → Slither → Foundry PoC → remediation → retest → report finale.**
