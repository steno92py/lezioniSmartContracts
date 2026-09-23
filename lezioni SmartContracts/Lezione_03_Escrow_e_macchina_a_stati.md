# Smart Contract Security / Solidity Security
## Lezione 3 — Escrow e macchina a stati: progettare le transizioni prima del codice

> **Ambiente del corso:** esclusivamente didattico, difensivo e locale. Gli esempi usano contratti giocattolo, account di test e fondi fittizi. Non useremo fork di mainnet, protocolli reali, wallet reali o RPC pubblici.
>
> **Baseline verificata il 21 settembre 2026:** gli esempi usano **Solidity 0.8.37**, release stabile del 10 settembre 2026 che include correzioni di bug del compilatore. La documentazione corrente di Solidity descrive `enum`, state variables, `immutable`, events e custom errors; la documentazione Foundry corrente conferma `forge test`, `forge-std/Test.sol`, cheatcode e livelli di trace. OWASP Smart Contract Security 2026 tratta esplicitamente le vulnerabilità di business logic e le sequenze di stato non valide come una classe importante di rischio.
>
> **Importante:** il contratto di questa lezione è volutamente incompleto e **non è production-ready**. Può ricevere Ether con `fund()`, ma non implementa ancora alcun payout. L'obiettivo è isolare e testare la **macchina a stati**. Il trasferimento dell'Ether, le chiamate esterne, `receive`, `fallback` e Checks-Effects-Interactions saranno oggetto della Lezione 4. **Non distribuire questo contratto con fondi reali.**

---

## 1. Obiettivi

Alla fine di questa lezione dovresti saper:

- spiegare perché uno smart contract è spesso meglio pensato come una **state machine** che come un insieme di funzioni indipendenti;
- distinguere **stato**, **transizione**, **guardia**, **azione** e **stato terminale**;
- tradurre una specifica informale di Escrow in un grafo di stati;
- identificare ruoli, asset, superfici di input e trust boundary;
- usare un `enum` Solidity per rappresentare stati discreti;
- usare variabili `immutable` per parametri fissati alla costruzione;
- applicare controlli di ruolo e di stato prima di modificare lo storage;
- riconoscere un bug di business logic dovuto a una transizione consentita nel momento sbagliato;
- trasformare le transizioni lecite e illecite in proprietà verificabili;
- scrivere test Foundry per il percorso corretto e per i percorsi proibiti;
- verificare che un `revert` non lasci uno stato parzialmente modificato;
- costruire una prima **transition matrix** da auditor;
- separare le proprietà della macchina a stati dalle future proprietà economiche e di payout.

Il principio guida della lezione è:

> **Non chiederti soltanto “questa funzione è corretta?”. Chiediti “da quali stati è raggiungibile, da chi, e quali stati rende raggiungibili dopo di sé?”.**

---

## 2. Modello mentale

### 2.1 Uno smart contract non è solo una raccolta di funzioni

Immagina un distributore automatico molto semplice.

Non basta sapere che esistono le funzioni:

```text
insertCoin()
selectProduct()
refund()
```

La domanda di sicurezza è anche **quando** ciascuna operazione è consentita.

Per esempio:

```text
nessuna moneta inserita -> selectProduct() NON deve funzionare
moneta inserita         -> selectProduct() può funzionare
prodotto erogato        -> selectProduct() NON deve funzionare di nuovo
```

La stessa funzione può quindi essere:

- corretta in uno stato;
- errata in un altro stato;
- pericolosa se può essere ripetuta;
- pericolosa se rende raggiungibile uno stato che la specifica considerava impossibile.

Uno smart contract è particolarmente sensibile a questo problema perché il suo stato è persistente tra transazioni diverse.

```text
Tx 1  -> modifica storage
Tx 2  -> parte dallo storage lasciato da Tx 1
Tx 3  -> parte dallo storage lasciato da Tx 2
...
```

La sicurezza dipende quindi non soltanto dal singolo input, ma anche dalla **sequenza di chiamate**.

OWASP Smart Contract Security classifica proprio le vulnerabilità di business logic come difetti nei quali regole, incentivi o transizioni permettono di raggiungere comportamenti non previsti, anche quando primitive come type safety o access control sembrano corrette.

---

### 2.2 La state machine dell'Escrow di oggi

Costruiamo una versione molto piccola dell'Escrow.

I ruoli sono:

```text
BUYER   = chi crea l'Escrow e deposita il prezzo
SELLER  = controparte designata
OUTSIDER = qualunque altro indirizzo
```

L'asset è:

```text
ETH fittizio nell'EVM locale di Foundry
```

Gli stati sono:

```text
Created
Funded
ReleaseApproved
Cancelled
```

Le sole transizioni valide sono:

```text
                     buyer: fund(price)
          +------------------------------------+
          |                                    v
      +---------+                          +---------+
      | Created |                          | Funded  |
      +---------+                          +---------+
          |                                    |
          | buyer: cancelBeforeFunding()       | buyer: approveRelease()
          v                                    v
     +-----------+                       +-----------------+
     | Cancelled |                       | ReleaseApproved |
     +-----------+                       +-----------------+
       terminale                              terminale
```

In forma ancora più compatta:

```text
Created -> Funded -> ReleaseApproved
    |
    +-------> Cancelled
```

Tutto ciò che **non compare** in questo grafo deve essere considerato proibito.

Per esempio:

```text
Funded -> Cancelled          NON consentito
Created -> ReleaseApproved   NON consentito
Cancelled -> Funded          NON consentito
ReleaseApproved -> Funded    NON consentito
Funded -> Funded             NON consentito
```

Questa osservazione è molto importante per l'audit:

> Una specifica di state machine è definita tanto dalle frecce presenti quanto dalle frecce assenti.

---

### 2.3 Stato, guardia e azione

Ogni transizione può essere vista come:

```text
(current state, caller, inputs, value)
                |
                v
             GUARDIE
                |
        se tutte vere
                v
             AZIONI
                |
                v
            new state
```

Per `fund()`:

```text
stato attuale = Created
caller        = buyer
msg.value     = price esatto
        |
        v
 tutte le guardie passano
        |
        v
state = Funded
```

Se una guardia fallisce:

```text
revert
```

La transazione non deve lasciare effetti parziali.

---

### 2.4 “Chi?” e “quando?” sono due dimensioni diverse

Un errore comune è pensare che l'access control risolva tutto.

Esempio:

```solidity
function approveRelease() external {
    require(msg.sender == buyer);
    state = State.ReleaseApproved;
}
```

Il controllo risponde alla domanda:

> “Chi può chiamare?”

ma non risponde alla domanda:

> “In quale stato può chiamare?”

Il buyer è il soggetto giusto, ma se può chiamare `approveRelease()` quando l'Escrow è ancora `Created`, la state machine è comunque sbagliata.

La sicurezza richiede entrambe le dimensioni:

```text
AUTORIZZAZIONE: chi può fare l'azione?
SEQUENZIAMENTO: quando può farla?
```

---

## 3. Teoria

### 3.1 Formalizzare una macchina a stati

Una state machine finita può essere pensata come l'insieme di:

```text
S = insieme degli stati
T = insieme delle transizioni consentite
G = guardie che abilitano ciascuna transizione
A = azioni effettuate durante la transizione
```

Per il nostro Escrow:

```text
S = {
    Created,
    Funded,
    ReleaseApproved,
    Cancelled
}
```

Le transizioni sono:

```text
T1: Created -> Funded
T2: Funded  -> ReleaseApproved
T3: Created -> Cancelled
```

Le guardie principali sono:

```text
T1:
- msg.sender == buyer
- msg.value == price
- state == Created

T2:
- msg.sender == buyer
- state == Funded

T3:
- msg.sender == buyer
- state == Created
```

Questa forma ci aiuta perché separa la **specifica** dall'implementazione Solidity.

Prima decidiamo cosa deve essere vero; poi scriviamo il codice.

---

### 3.2 Perché i bug di sequenza sono difficili da vedere

Una funzione isolata può sembrare innocua:

```solidity
state = State.ReleaseApproved;
```

Il problema emerge soltanto considerando la cronologia:

```text
deploy
  |
  v
Created
  |
  | approveRelease()   <-- se manca il controllo di stato
  v
ReleaseApproved
```

Abbiamo raggiunto uno stato che semanticamente significa:

> “Il buyer ha approvato il rilascio di fondi già messi in escrow.”

ma non è mai avvenuto alcun funding.

Questa contraddizione tra **significato dello stato** e **storia realmente avvenuta** è una forma classica di errore logico.

Da auditor, ogni stato dovrebbe suggerirti una domanda:

> “Quali eventi devono necessariamente essere già avvenuti affinché questo stato sia valido?”

Per `ReleaseApproved` la risposta è almeno:

```text
il contratto deve essere stato Funded in precedenza
```

Se trovi un percorso che evita quel prerequisito, hai trovato una violazione della specifica.

---

### 3.3 `enum`: perché esiste e perché aiuta la sicurezza

Solidity permette di definire un tipo enumerato:

```solidity
enum State {
    Created,
    Funded,
    ReleaseApproved,
    Cancelled
}
```

Un `enum` rappresenta un insieme finito di valori validi.

Potremmo usare numeri:

```solidity
uint8 state;
// 0 = Created
// 1 = Funded
// 2 = ReleaseApproved
// 3 = Cancelled
```

ma questo rende il codice più difficile da leggere e revisionare.

Con un enum:

```solidity
state == State.Funded
```

esprime direttamente l'intenzione.

Questo è importante per la sicurezza perché audit e code review sono attività umane: ridurre l'ambiguità aiuta a individuare errori.

Un enum **non rende automaticamente corretta** la state machine. È soltanto una rappresentazione più sicura e leggibile del dominio degli stati.

Il compilatore non sa, per esempio, che:

```text
Created -> ReleaseApproved
```

è semanticamente sbagliato.

Quella regola deve essere codificata nelle guardie e nei test.

---

### 3.4 Storage persistente e significato dello stato

La variabile:

```solidity
State public state;
```

è una state variable ordinaria.

Il suo valore vive nello **storage persistente** del contratto.

Ciò significa che:

```text
Tx A termina con state = Funded

Tx B inizia e legge ancora state = Funded
```

Questo è il motivo per cui la state machine esiste tra transazioni diverse.

Nel nostro contratto useremo invece `immutable` per:

```solidity
address public immutable buyer;
address public immutable seller;
uint256 public immutable price;
```

Questi valori vengono fissati nel constructor e non possono essere modificati successivamente.

La documentazione Solidity distingue `immutable` dalle normali variabili di storage: il valore viene determinato durante la costruzione e incorporato nel runtime code invece di occupare un normale storage slot come una state variable mutabile.

Dal punto di vista del threat model questo è utile:

```text
buyer, seller, price
```

non possono essere cambiati accidentalmente da una futura funzione amministrativa che non esiste.

Naturalmente l'immutabilità non rende automaticamente corretta la scelta iniziale: se il constructor riceve un seller sbagliato, l'errore resta permanente. Per questo validiamo gli input del constructor.

---

### 3.5 Constructor come prima transizione concettuale

Anche la creazione del contratto fa parte del modello.

Prima del deployment il contratto non esiste.

Dopo il constructor:

```text
buyer  = msg.sender del deployment
seller = seller scelto
price  = prezzo scelto
state  = Created
```

Il constructor deve quindi stabilire gli invarianti iniziali.

Per esempio:

```text
seller != address(0)
price > 0
seller != buyer
state == Created
```

Un invariant che non è vero subito dopo la costruzione non potrà essere “salvato” dai test delle funzioni successive.

---

### 3.6 Modificatori: utili, ma non magici

Useremo due modifier:

```solidity
modifier onlyBuyer() { ... }
modifier onlyState(State expected) { ... }
```

La loro funzione è centralizzare guardie ripetute.

Mentalmente:

```solidity
function f() external onlyBuyer onlyState(State.Created) {
    BODY
}
```

può essere letto come:

```text
1. verifica buyer
2. verifica stato Created
3. esegui body
```

I modifier migliorano leggibilità e consistenza, ma hanno anche rischi:

- una funzione può dimenticare il modifier;
- l'ordine dei modifier può essere significativo;
- un modifier può contenere logica complessa e nascondere effetti;
- il nome può promettere più di ciò che il codice effettivamente verifica.

Regola da auditor:

> Non fidarti del nome `onlyX`: apri sempre il modifier e leggi cosa controlla davvero.

In questa lezione manteniamo i modifier piccoli e senza side effect, oltre al possibile `revert`.

---

### 3.7 Custom errors e fallimenti strutturati

Definiremo errori come:

```solidity
error Unauthorized(address caller);
error WrongState(State expected, State actual);
error WrongValue(uint256 expected, uint256 actual);
```

Poi useremo:

```solidity
if (msg.sender != buyer) {
    revert Unauthorized(msg.sender);
}
```

I custom errors hanno due vantaggi didattici e pratici:

1. danno un nome preciso alla proprietà violata;
2. possono includere dati utili senza affidarsi a lunghe stringhe di revert.

La documentazione Solidity specifica che un revert annulla le modifiche allo stato della call corrente e restituisce error data al chiamante.

Per il corso questo crea un legame diretto:

```text
PROPRIETÀ VIOLATA
      |
      v
CUSTOM ERROR
      |
      v
TEST expectRevert
```

---

### 3.8 `payable` e `msg.value` nella state transition

`fund()` sarà `payable`:

```solidity
function fund() external payable ...
```

Questo permette alla call di portare Ether.

La guardia economica minima sarà:

```solidity
if (msg.value != price) {
    revert WrongValue(price, msg.value);
}
```

Quindi la transizione non dipende soltanto da caller e state:

```text
Created + buyer + price esatto -> Funded
```

ma:

```text
Created + buyer + 0 ETH        -> revert
Created + buyer + price - 1    -> revert
Created + buyer + price + 1    -> revert
Created + outsider + price     -> revert
Funded  + buyer + price        -> revert
```

Questo è già un piccolo esempio di **input space** multidimensionale.

---

### 3.9 Ricevere Ether non è una chiamata esterna fatta dal contratto

Quando il buyer chiama:

```solidity
escrow.fund{value: PRICE}();
```

il controllo passa:

```text
BUYER/test harness
      |
      | CALL con value
      v
ESCROW.fund()
```

All'interno di `fund()` il contratto **non chiama nessun altro contratto**.

Questa distinzione diventerà cruciale nella Lezione 4.

Oggi il call graph è semplice:

```text
external caller -> Escrow
```

Non abbiamo:

```text
Escrow -> seller
Escrow -> token
Escrow -> arbitrary address
```

Quindi non esiste ancora un punto nel body delle nostre funzioni in cui l'Escrow ceda il controllo a codice esterno.

Questo ci permette di studiare la state machine senza introdurre contemporaneamente la reentrancy.

---

### 3.10 Stato terminale

`Cancelled` e `ReleaseApproved` saranno stati terminali nella versione di oggi.

Terminale significa:

```text
non esiste alcuna transizione di uscita valida
```

Quindi, una volta raggiunti:

```text
Cancelled
```

o:

```text
ReleaseApproved
```

ogni funzione state-changing del nostro piccolo protocollo deve fallire.

Gli stati terminali sono un ottimo posto dove cercare bug.

Domande da auditor:

```text
- esiste qualche funzione dimenticata che può “riaprire” l'Escrow?
- si può finanziare dopo la cancellazione?
- si può approvare due volte?
- si può cambiare ruolo o prezzo dopo la chiusura?
```

---

### 3.11 Transition matrix

Una rappresentazione utile in audit è una tabella stato × funzione.

| Stato corrente | `fund()` | `approveRelease()` | `cancelBeforeFunding()` |
|---|---|---|---|
| `Created` | buyer + prezzo esatto: **OK → Funded** | **REVERT** | buyer: **OK → Cancelled** |
| `Funded` | **REVERT** | buyer: **OK → ReleaseApproved** | **REVERT** |
| `ReleaseApproved` | **REVERT** | **REVERT** | **REVERT** |
| `Cancelled` | **REVERT** | **REVERT** | **REVERT** |

Questa tabella è quasi una specifica eseguibile.

Ogni cella dovrebbe idealmente avere almeno un test o essere coperta da una proprietà più generale.

---

### 3.12 Threat model della versione V1

Prima del codice identifichiamo cosa stiamo proteggendo.

#### Asset

1. **Ether custodito** dal contratto dopo `fund()`.
2. **Integrità dello stato**: il contratto non deve dichiarare `Funded` o `ReleaseApproved` se la sequenza corretta non è avvenuta.
3. **Identità dei ruoli**: buyer e seller devono rimanere quelli stabiliti al deployment.
4. **Prezzo concordato**: deve rimanere quello iniziale.

#### Attori

```text
buyer     -> autorizzato a fund, approveRelease, cancelBeforeFunding
seller    -> passivo in questa versione
outsider  -> nessuna funzione privilegiata
```

#### Input controllati dal chiamante

```text
msg.sender
msg.value
quale funzione viene chiamata
ordine delle chiamate nel tempo
```

#### Assunzioni deliberate della lezione

- il contratto gira solo in Foundry/Anvil locale;
- non esistono ancora payout;
- non esistono token;
- non esiste arbitro;
- non esiste timeout;
- non esiste upgradeability;
- non esistono oracoli;
- non modelliamo ancora Ether forzato nel contratto da meccanismi esterni;
- `ReleaseApproved` è una **autorizzazione contabile**, non un trasferimento.

Ogni assunzione sarà riesaminata quando aggiungeremo nuove capacità.

---

## 4. Esempio Solidity

Crea `src/EscrowStateMachine.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title EscrowStateMachine
/// @notice Contratto didattico locale. NON production-ready.
/// @dev In questa versione il contratto può ricevere ETH ma NON effettua payout.
contract EscrowStateMachine {
    enum State {
        Created,
        Funded,
        ReleaseApproved,
        Cancelled
    }

    error ZeroSeller();
    error BuyerEqualsSeller();
    error ZeroPrice();
    error Unauthorized(address caller);
    error WrongState(State expected, State actual);
    error WrongValue(uint256 expected, uint256 actual);

    event Funded(address indexed buyer, uint256 amount);
    event ReleaseApproved(address indexed buyer);
    event Cancelled(address indexed buyer);

    address public immutable buyer;
    address public immutable seller;
    uint256 public immutable price;

    State public state;

    constructor(address seller_, uint256 price_) {
        if (seller_ == address(0)) revert ZeroSeller();
        if (seller_ == msg.sender) revert BuyerEqualsSeller();
        if (price_ == 0) revert ZeroPrice();

        buyer = msg.sender;
        seller = seller_;
        price = price_;
        state = State.Created;
    }

    modifier onlyBuyer() {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyState(State expected) {
        if (state != expected) revert WrongState(expected, state);
        _;
    }

    /// @notice Deposita esattamente il prezzo concordato.
    function fund()
        external
        payable
        onlyBuyer
        onlyState(State.Created)
    {
        if (msg.value != price) revert WrongValue(price, msg.value);

        state = State.Funded;

        emit Funded(msg.sender, msg.value);
    }

    /// @notice Il buyer autorizza il futuro payout al seller.
    /// @dev Il payout non viene ancora eseguito in questa lezione.
    function approveRelease()
        external
        onlyBuyer
        onlyState(State.Funded)
    {
        state = State.ReleaseApproved;

        emit ReleaseApproved(msg.sender);
    }

    /// @notice Cancella l'Escrow solo prima che venga finanziato.
    function cancelBeforeFunding()
        external
        onlyBuyer
        onlyState(State.Created)
    {
        state = State.Cancelled;

        emit Cancelled(msg.sender);
    }
}
```

---

## 5. Analisi del codice

Ora leggiamo il contratto come farebbe un auditor.

Non basta capire “cosa sembra fare”. Per ogni entry point chiediamo:

```text
CHI può chiamare?
QUALI input controlla?
QUANTO valore può portare?
QUALE stato legge?
QUALE stato modifica?
FA chiamate esterne?
QUANDO cede il controllo?
QUALI assunzioni fa?
```

---

### 5.1 `constructor(address seller_, uint256 price_)`

#### Chi può chiamarlo?

Il constructor viene eseguito durante la creazione del contratto.

Nel nostro laboratorio il deployer viene trattato come buyer:

```solidity
buyer = msg.sender;
```

#### Input controllati dal chiamante

```text
seller_
price_
```

Il deployer controlla entrambi.

#### Valore in ingresso

Il constructor non è `payable`, quindi il nostro design non prevede funding al deployment.

Questo è intenzionale: separiamo:

```text
creazione
```

da:

```text
funding
```

in due transizioni concettualmente distinte.

#### Stato letto

Nessuno stato precedente del contratto: il contratto è in costruzione.

#### Stato modificato

```text
buyer
seller
price
state = Created
```

`buyer`, `seller` e `price` sono immutable.

#### Chiamate esterne

Nessuna.

#### Quando passa il controllo a codice esterno?

Mai durante il body del constructor.

#### Assunzioni

- `msg.sender` è l'identità che vogliamo come buyer;
- seller e buyer devono essere distinti;
- seller zero non ha significato valido per questo laboratorio;
- un Escrow a prezzo zero non appartiene alla specifica.

#### Domanda da auditor

Perché `buyer` non è un parametro?

Perché la specifica di questa versione dice:

> il creatore del contratto è il buyer.

Questa è una **scelta di protocol design**, non una legge di Solidity.

---

### 5.2 `fund()`

```solidity
function fund()
    external
    payable
    onlyBuyer
    onlyState(State.Created)
```

#### Chi può chiamarla?

Solo `buyer`.

Il controllo effettivo è:

```solidity
msg.sender == buyer
```

#### Input controllati dal chiamante

Non ci sono parametri ABI espliciti, ma il chiamante controlla comunque:

```text
msg.sender
msg.value
momento/ordine della chiamata
```

Un audit che guarda soltanto i parametri della funzione perde una parte importante dell'input space.

#### Valore in ingresso

`msg.value` deve essere esattamente `price`.

Non accettiamo:

```text
price - 1
price + 1
0
```

Perché usare uguaglianza esatta?

Perché la specifica di oggi definisce un prezzo fisso. Accettare “almeno price” introdurrebbe la domanda:

```text
che cosa succede all'eccesso?
```

che richiederebbe nuova logica e nuove proprietà.

#### Stato letto

```text
buyer
state
price
```

#### Stato modificato

```solidity
state = State.Funded;
```

Inoltre il balance ETH del contratto aumenta per effetto della call con value.

#### Chiamate esterne

Nessuna.

#### Quando passa il controllo a codice esterno?

Non passa a codice esterno dopo l'ingresso.

Quindi il body non presenta ancora una superficie di reentrancy dovuta a outbound call.

#### Assunzioni

- `price` è corretto e immutabile;
- un singolo funding esatto è il solo percorso valido verso `Funded`;
- nessun altro percorso deve poter assegnare `state = Funded`.

#### Proprietà derivata

> Se `state == Funded` per un'esecuzione raggiungibile attraverso le API previste, allora `fund()` è stata completata con successo dal buyer con `msg.value == price`.

Questa è una proprietà storica: lo stato finale implica qualcosa sul percorso precedente.

---

### 5.3 `approveRelease()`

#### Chi può chiamarla?

Solo il buyer.

#### Input controllati dal chiamante

Nessun parametro ABI e nessun `msg.value`, ma il buyer controlla **quando** effettuare la chiamata.

#### Valore in ingresso

La funzione non è `payable`; non appartiene al design inviare Ether qui.

#### Stato letto

```text
buyer
state
```

#### Stato modificato

```text
state = ReleaseApproved
```

#### Chiamate esterne

Nessuna.

#### Quando passa il controllo a codice esterno?

Mai.

#### Assunzioni

La più importante è:

```text
ReleaseApproved ha senso solo se lo stato precedente è Funded
```

Per questo il modifier:

```solidity
onlyState(State.Funded)
```

è una parte **semantica** della funzione, non soltanto un controllo difensivo accessorio.

Se lo togliamo, cambiamo il protocollo.

---

### 5.4 `cancelBeforeFunding()`

#### Chi può chiamarla?

Solo il buyer.

#### Input controllati dal chiamante

Il momento della chiamata.

#### Valore in ingresso

Nessuno.

#### Stato letto

```text
buyer
state
```

#### Stato modificato

```text
state = Cancelled
```

#### Chiamate esterne

Nessuna.

#### Quando passa il controllo a codice esterno?

Mai.

#### Assunzioni

La cancellazione è consentita soltanto finché non esistono fondi depositati tramite il normale percorso.

Per questo:

```text
Created -> Cancelled
```

è valido, mentre:

```text
Funded -> Cancelled
```

non lo è.

Nella versione futura, quando introdurremo refund veri, questa parte del modello cambierà.

---

### 5.5 Getter automatici `buyer()`, `seller()`, `price()`, `state()`

Poiché le variabili sono `public`, Solidity genera getter esterni.

Questi getter:

- leggono dati;
- non modificano lo stato;
- permettono ai test e agli utenti di osservare la configurazione.

Dal punto di vista del threat model, la leggibilità on-chain **non è segretezza**. Dati come buyer, seller e price non vanno considerati segreti soltanto perché non esiste una funzione esplicita che li restituisce: lo stato blockchain e il bytecode sono comunque osservabili.

---

## 6. Proprietà e invarianti

Ora trasformiamo il design in frasi verificabili.

### 6.1 Invarianti di configurazione

Dopo una costruzione riuscita:

> `buyer` è il deployer.

> `seller != address(0)`.

> `seller != buyer`.

> `price > 0`.

> `state == Created`.

Poiché buyer, seller e price sono immutable:

> buyer, seller e price non cambiano durante la vita del contratto.

---

### 6.2 Proprietà di access control

> Un indirizzo diverso dal buyer non può finanziare l'Escrow tramite `fund()`.

> Un indirizzo diverso dal buyer non può approvare il release.

> Un indirizzo diverso dal buyer non può cancellare l'Escrow.

Nota importante:

Queste proprietà non dicono ancora che il buyer possa sempre compiere tali azioni.

L'autorizzazione è necessaria ma non sufficiente: serve anche lo stato corretto.

---

### 6.3 Proprietà della state machine

> `fund()` può riuscire soltanto da `Created`.

> `approveRelease()` può riuscire soltanto da `Funded`.

> `cancelBeforeFunding()` può riuscire soltanto da `Created`.

> `ReleaseApproved` è raggiungibile soltanto passando da `Funded`.

> `Cancelled` è terminale.

> `ReleaseApproved` è terminale nella versione di questa lezione.

> L'Escrow non può essere finanziato due volte.

> Un Escrow cancellato non può essere finanziato.

> Un Escrow finanziato non può essere cancellato tramite `cancelBeforeFunding()`.

---

### 6.4 Proprietà sul valore

> Un funding riuscito accetta esattamente `price` wei.

> Un funding con valore inferiore a `price` deve fallire.

> Un funding con valore superiore a `price` deve fallire.

> Se `fund()` reverte, la state machine non deve passare a `Funded`.

> Se `fund()` reverte, il trasferimento di `msg.value` non deve restare accreditato al contratto come effetto parziale di quella call.

Quest'ultima proprietà deriva dall'atomicità del revert.

---

### 6.5 Una proprietà che NON vogliamo ancora dichiarare come invariant universale

Potresti essere tentato di scrivere:

> `address(escrow).balance == price` se e solo se `state == Funded || state == ReleaseApproved`.

Come prima approssimazione dei normali percorsi API può essere utile, ma non è un buon invariant universale per Ethereum.

Il balance ETH di un contratto può essere influenzato da meccanismi che non richiedono l'esecuzione della sua normale funzione `receive`/`fallback`.

Studieremo meglio questo punto nella lezione sull'Ether.

Per oggi usiamo il balance nei test del **percorso osservato**, ma non confondiamo:

```text
assert di scenario
```

con:

```text
invariant universale del protocollo
```

Questa distinzione è molto importante quando passeremo all'invariant testing.

---

### 6.6 Invarianti come storia compressa

Uno stato può essere visto come una compressione della storia.

Se leggiamo:

```text
state == ReleaseApproved
```

stiamo implicitamente affermando che la storia sia stata:

```text
Created
  -> Funded
  -> ReleaseApproved
```

Se il codice permette:

```text
Created
  -> ReleaseApproved
```

lo stato non rappresenta più fedelmente la storia del protocollo.

Questo è un potente modello mentale per auditare lending, staking, vesting, governance, bridge e molte altre applicazioni.

---

## 7. Laboratorio Foundry

Tutto il laboratorio resta locale.

Non serve alcun fork.

Non serve alcun RPC pubblico.

Non servono chiavi reali.

### 7.1 Struttura dei file

Partendo dal progetto Foundry delle lezioni precedenti:

```text
smart-contract-security-course/
├── foundry.toml
├── lib/
│   └── forge-std/
├── src/
│   ├── EscrowStateMachine.sol
│   └── labs/
│       └── BadEscrowStateMachine.sol
└── test/
    ├── EscrowStateMachine.t.sol
    └── BadEscrowStateMachine.t.sol
```

Se stai creando un progetto nuovo solo per il laboratorio:

```bash
forge init escrow-state-machine-lab
cd escrow-state-machine-lab
```

Per rendere esplicita la versione del compilatore, il `foundry.toml` può contenere:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.37"
```

La documentazione Foundry corrente usa `foundry.toml` per configurare, tra le altre cose, versione del compilatore e comportamento dei test.

---

### 7.2 Contratto sotto test

Usa il file mostrato sopra:

```text
src/EscrowStateMachine.sol
```

---

### 7.3 Test suite completa

Crea `test/EscrowStateMachine.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {EscrowStateMachine} from "../src/EscrowStateMachine.sol";

contract EscrowStateMachineTest is Test {
    EscrowStateMachine internal escrow;

    address internal buyer;
    address internal seller;
    address internal outsider;

    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        outsider = makeAddr("outsider");

        vm.deal(buyer, 100 ether);
        vm.deal(outsider, 100 ether);

        vm.prank(buyer);
        escrow = new EscrowStateMachine(seller, PRICE);
    }

    function testInitialConfiguration() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.price(), PRICE);
        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Created)
        );
    }

    function testBuyerCanFundExactPrice() public {
        vm.prank(buyer);
        escrow.fund{value: PRICE}();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Funded)
        );
        assertEq(address(escrow).balance, PRICE);
    }

    function testBuyerCanApproveAfterFunding() public {
        _fund();

        vm.prank(buyer);
        escrow.approveRelease();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.ReleaseApproved)
        );
        assertEq(address(escrow).balance, PRICE);
    }

    function testBuyerCanCancelBeforeFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Cancelled)
        );
        assertEq(address(escrow).balance, 0);
    }

    function testOutsiderCannotFund() public {
        vm.startPrank(outsider);

        vm.expectRevert(EscrowStateMachine.Unauthorized.selector);
        escrow.fund{value: PRICE}();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Created)
        );
        assertEq(address(escrow).balance, 0);
    }

    function testSellerCannotApproveRelease() public {
        _fund();

        vm.startPrank(seller);

        vm.expectRevert(EscrowStateMachine.Unauthorized.selector);
        escrow.approveRelease();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Funded)
        );
    }

    function testCannotFundWithTooLittleValue() public {
        uint256 tooLittle = PRICE - 1;

        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongValue.selector);
        escrow.fund{value: tooLittle}();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Created)
        );
        assertEq(address(escrow).balance, 0);
    }

    function testCannotFundWithTooMuchValue() public {
        uint256 tooMuch = PRICE + 1;

        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongValue.selector);
        escrow.fund{value: tooMuch}();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Created)
        );
        assertEq(address(escrow).balance, 0);
    }

    function testCannotApproveBeforeFunding() public {
        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongState.selector);
        escrow.approveRelease();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Created)
        );
    }

    function testCannotFundTwice() public {
        _fund();

        uint256 balanceBefore = buyer.balance;

        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongState.selector);
        escrow.fund{value: PRICE}();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Funded)
        );
        assertEq(address(escrow).balance, PRICE);
        assertEq(buyer.balance, balanceBefore);
    }

    function testCannotCancelAfterFunding() public {
        _fund();

        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongState.selector);
        escrow.cancelBeforeFunding();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Funded)
        );
        assertEq(address(escrow).balance, PRICE);
    }

    function testCancelledStateIsTerminalForFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        uint256 balanceBefore = buyer.balance;

        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongState.selector);
        escrow.fund{value: PRICE}();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Cancelled)
        );
        assertEq(address(escrow).balance, 0);
        assertEq(buyer.balance, balanceBefore);
    }

    function testReleaseApprovedStateIsTerminalForApprove() public {
        _fund();

        vm.prank(buyer);
        escrow.approveRelease();

        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongState.selector);
        escrow.approveRelease();

        vm.stopPrank();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.ReleaseApproved)
        );
    }

    function testRevertedFundingLeavesNoPartialEffects() public {
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 escrowBalanceBefore = address(escrow).balance;

        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.WrongValue.selector);
        escrow.fund{value: PRICE - 1}();

        vm.stopPrank();

        assertEq(buyer.balance, buyerBalanceBefore);
        assertEq(address(escrow).balance, escrowBalanceBefore);
        assertEq(
            uint256(escrow.state()),
            uint256(EscrowStateMachine.State.Created)
        );
    }

    function testConstructorRejectsZeroSeller() public {
        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.ZeroSeller.selector);
        new EscrowStateMachine(address(0), PRICE);

        vm.stopPrank();
    }

    function testConstructorRejectsBuyerAsSeller() public {
        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.BuyerEqualsSeller.selector);
        new EscrowStateMachine(buyer, PRICE);

        vm.stopPrank();
    }

    function testConstructorRejectsZeroPrice() public {
        vm.startPrank(buyer);

        vm.expectRevert(EscrowStateMachine.ZeroPrice.selector);
        new EscrowStateMachine(seller, 0);

        vm.stopPrank();
    }

    function _fund() internal {
        vm.prank(buyer);
        escrow.fund{value: PRICE}();
    }
}
```

---

### 7.4 Eseguire i test

Formatta:

```bash
forge fmt
```

Compila:

```bash
forge build
```

Esegui tutta la suite:

```bash
forge test
```

Per concentrarti solo sul contratto di questa lezione:

```bash
forge test --match-contract EscrowStateMachineTest
```

Per vedere una trace dettagliata del funding:

```bash
forge test \
  --match-test testBuyerCanFundExactPrice \
  -vvvv
```

La documentazione corrente di Foundry indica che aumentando la verbosity si ottengono progressivamente log e execution traces più dettagliate; `-vvvv` è utile per vedere le trace anche dei test riusciti.

---

### 7.5 Cosa osservare nella trace

Per `testBuyerCanFundExactPrice` cerca concettualmente:

```text
buyer
  |
  | value: 5 ether
  v
EscrowStateMachine::fund()
  |
  +-- controllo onlyBuyer
  +-- controllo state == Created
  +-- controllo msg.value == price
  +-- SSTORE / modifica state
  +-- LOG / evento Funded
  v
return
```

Non dovresti vedere una call dal contratto Escrow verso il seller.

Questo dettaglio sarà il punto di confronto con la prossima lezione.

---

### 7.6 Perché `vm.deal` non è una “feature del protocollo”

Nel test scriviamo:

```solidity
vm.deal(buyer, 100 ether);
```

Questo è un cheatcode del test environment.

Non significa che il contratto possa creare Ether.

Stiamo preparando una precondizione del laboratorio:

```text
buyer.balance >= PRICE
```

I cheatcode fanno parte dell'harness, non dell'applicazione che verrebbe distribuita.

Questa separazione è essenziale quando leggi test di sicurezza:

```text
CHEATCODE = potere del tester
CONTRACT API = potere dell'utente reale
```

---

## 8. Test negativi

Una suite che verifica solo:

```text
Created -> Funded -> ReleaseApproved
```

è insufficiente.

Il vero lavoro di sicurezza sta spesso nelle frecce che **non devono esistere**.

### 8.1 Classificare i fallimenti

Possiamo raggruppare i test negativi in quattro categorie.

#### A. Caller sbagliato

```text
outsider -> fund        REVERT
seller   -> approve     REVERT
outsider -> cancel      REVERT
```

#### B. Value sbagliato

```text
PRICE - 1 -> REVERT
PRICE + 1 -> REVERT
```

#### C. Stato sbagliato

```text
Created  -> approve     REVERT
Funded   -> fund        REVERT
Funded   -> cancel      REVERT
Cancelled -> fund       REVERT
```

#### D. Ripetizione

```text
fund due volte           REVERT
approve due volte        REVERT
cancel due volte         REVERT
```

Queste categorie sono riutilizzabili durante un audit.

---

### 8.2 Testare anche l'assenza di effetti

Considera:

```solidity
vm.expectRevert(...);
escrow.fund{value: PRICE - 1}();
```

Il test non dovrebbe fermarsi a:

```text
“ha revertito”
```

Dovremmo anche verificare:

```text
state ancora Created
balance escrow invariato
balance buyer invariato rispetto all'inizio della call fallita
```

Perché?

Perché la proprietà vera è:

> L'operazione non valida non deve avere effetti persistenti.

Questo modo di pensare sarà molto utile quando le funzioni diventeranno più complesse.

---

### 8.3 Negative space

In sicurezza, la specifica comprende un “negative space”:

```text
insieme di comportamenti che NON devono essere possibili
```

Per la nostra macchina:

```text
Valid paths:
Created -> Funded -> ReleaseApproved
Created -> Cancelled

Everything else:
forbidden
```

Un auditor prova sistematicamente a trasformare il “forbidden” in “reachable”.

---

## 9. Vulnerabilità / errore di progettazione: transizione senza guardia di stato

Ora costruiamo una versione volutamente vulnerabile **solo per il laboratorio locale**.

Il bug è piccolo e realistico:

```text
la funzione controlla chi chiama,
ma dimentica di controllare lo stato corrente.
```

---

### 9.1 Codice vulnerabile minimo

Crea `src/labs/BadEscrowStateMachine.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto volutamente vulnerabile per laboratorio locale.
contract BadEscrowStateMachine {
    enum State {
        Created,
        Funded,
        ReleaseApproved,
        Cancelled
    }

    error Unauthorized(address caller);
    error WrongState();
    error WrongValue();

    address public immutable buyer;
    uint256 public immutable price;

    State public state;

    constructor(uint256 price_) {
        buyer = msg.sender;
        price = price_;
        state = State.Created;
    }

    function fund() external payable {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Created) revert WrongState();
        if (msg.value != price) revert WrongValue();

        state = State.Funded;
    }

    function approveRelease() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);

        // BUG: manca state == State.Funded
        state = State.ReleaseApproved;
    }
}
```

Il bug non è:

```text
“chiunque può chiamare”
```

perché il controllo del buyer esiste.

Il bug è:

```text
“il buyer può chiamare nel momento sbagliato”
```

---

### 9.2 Perché è vulnerabile

La specifica dice:

```text
ReleaseApproved implica funding precedente
```

Il codice implementa invece:

```text
buyer può assegnare ReleaseApproved da QUALUNQUE stato
```

Il grafo reale diventa:

```text
             fund
Created --------------> Funded
   |
   | approveRelease()   <-- freccia inattesa
   v
ReleaseApproved
```

La macchina implementata non coincide più con la macchina progettata.

---

### 9.3 Riproduzione locale

Crea `test/BadEscrowStateMachine.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {BadEscrowStateMachine} from "../src/labs/BadEscrowStateMachine.sol";

contract BadEscrowStateMachineTest is Test {
    BadEscrowStateMachine internal badEscrow;

    address internal buyer;

    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);

        vm.prank(buyer);
        badEscrow = new BadEscrowStateMachine(PRICE);
    }

    function testDemonstratesInvalidTransition() public {
        assertEq(
            uint256(badEscrow.state()),
            uint256(BadEscrowStateMachine.State.Created)
        );
        assertEq(address(badEscrow).balance, 0);

        // Nessun funding avviene.
        vm.prank(buyer);
        badEscrow.approveRelease();

        // Stato semanticamente impossibile secondo la specifica.
        assertEq(
            uint256(badEscrow.state()),
            uint256(BadEscrowStateMachine.State.ReleaseApproved)
        );

        // Conferma che non è mai entrato alcun ETH.
        assertEq(address(badEscrow).balance, 0);
    }
}
```

Esegui:

```bash
forge test \
  --match-contract BadEscrowStateMachineTest \
  -vvvv
```

Il test **passa**, e proprio questo dimostra il bug.

Non stiamo dicendo:

```text
“la suite è verde, quindi il contratto è sicuro”
```

Stiamo dicendo:

```text
“abbiamo scritto un esperimento che dimostra che il comportamento proibito è raggiungibile”
```

---

### 9.4 La correzione

La versione corretta richiede:

```solidity
onlyState(State.Funded)
```

prima di cambiare stato:

```solidity
function approveRelease()
    external
    onlyBuyer
    onlyState(State.Funded)
{
    state = State.ReleaseApproved;

    emit ReleaseApproved(msg.sender);
}
```

La guardia traduce direttamente la freccia valida:

```text
Funded -> ReleaseApproved
```

---

### 9.5 Test di regressione

Il test fondamentale è già nella suite corretta:

```solidity
function testCannotApproveBeforeFunding() public {
    vm.startPrank(buyer);

    vm.expectRevert(EscrowStateMachine.WrongState.selector);
    escrow.approveRelease();

    vm.stopPrank();

    assertEq(
        uint256(escrow.state()),
        uint256(EscrowStateMachine.State.Created)
    );
}
```

Questo test ha un valore particolare: non serve soltanto oggi.

Serve a impedire che una futura modifica reintroduca il bug.

Questa è la logica di un **regression test**:

```text
bug osservato
    |
    v
fix
    |
    v
test che fallirebbe se il bug tornasse
```

---

### 9.6 Prima / dopo

| Aspetto | Vulnerabile | Corretto |
|---|---|---|
| Controlla il caller | sì | sì |
| Controlla `state == Funded` | **no** | **sì** |
| `Created -> ReleaseApproved` | possibile | revert |
| `Funded -> ReleaseApproved` | possibile | possibile |
| Stato rappresenta correttamente la storia | no | sì, rispetto al modello della lezione |

La lezione importante è:

> Un access control corretto non compensa una state machine errata.

---

## 10. Checklist da auditor

Quando leggi un contratto con stati o fasi, usa questa checklist.

### Modello

- Quali sono tutti gli stati espliciti e impliciti?
- Esiste un diagramma delle transizioni?
- Quali stati sono terminali?
- Quali stati dovrebbero essere irraggiungibili direttamente?

### Entry point

Per ogni funzione state-changing:

- chi può chiamarla?
- in quali stati può essere chiamata?
- quali input decide il caller?
- accetta `msg.value`?
- quali storage variable legge?
- quali storage variable modifica?
- quale nuovo stato rende raggiungibile?
- può essere chiamata due volte?

### Sequenze

- posso saltare una fase?
- posso ripetere una fase?
- posso tornare indietro da uno stato terminale?
- posso chiamare le funzioni nello stesso ordine ma con attori diversi?
- una funzione valida singolarmente diventa invalida dopo un'altra funzione?

### Access control

- la funzione controlla il caller corretto?
- controlla `msg.sender` o qualcosa di meno appropriato?
- un ruolo ha più potere del necessario?
- un modifier manca su qualche entry point parallelo?

### Value

- il valore deve essere esatto, minimo o massimo?
- che cosa succede a valore zero?
- che cosa succede a valore eccessivo?
- un revert lascia davvero tutto invariato?

### Test

- esiste almeno un test per ogni freccia valida?
- esistono test per le frecce proibite importanti?
- esistono test sulle ripetizioni?
- esistono test con caller non autorizzati?
- il test verifica lo stato dopo il revert, non soltanto il revert stesso?

---

## 11. Esercizi

Non trovi le soluzioni qui: chiedimele quando vuoi confrontare il tuo lavoro.

### Esercizio 1 — Transition matrix completa

Completa manualmente una matrice con righe:

```text
Created
Funded
ReleaseApproved
Cancelled
```

colonne:

```text
fund
approveRelease
cancelBeforeFunding
```

Per ogni cella scrivi:

```text
SUCCESS -> stato finale
```

o:

```text
REVERT -> motivo
```

Poi confrontala con i test esistenti e individua quali celle non hanno un test dedicato.

---

### Esercizio 2 — Test mancante sul caller

Aggiungi:

```text
outsider non può chiamare cancelBeforeFunding()
```

Il test deve verificare sia il revert sia che lo stato resti `Created`.

---

### Esercizio 3 — Stato terminale `Cancelled`

Aggiungi un test che dimostri che dopo `Cancelled`:

```text
approveRelease()
```

reverte.

Spiega perché questa call fallisce per lo stato anche se il caller è il buyer corretto.

---

### Esercizio 4 — Testare l'errore completo

Finora molti test usano soltanto il selector:

```solidity
vm.expectRevert(EscrowStateMachine.WrongValue.selector);
```

Modifica un test in modo da verificare l'intero revert payload di:

```solidity
WrongValue(expected, actual)
```

Suggerimento: studia `abi.encodeWithSelector`.

Domanda:

> Qual è il trade-off tra testare soltanto il selector e testare anche tutti gli argomenti dell'errore?

---

### Esercizio 5 — Seller attivo

Estendi la specifica con uno stato:

```text
Accepted
```

Nuove regole:

```text
Created --seller.accept()--> Accepted
Accepted --buyer.fund()-----> Funded
```

Decidi esplicitamente:

- il buyer può cancellare da `Accepted`?
- il seller può revocare l'accettazione?
- `fund()` deve revertire direttamente da `Created`?

Prima disegna il grafo, poi modifica il contratto.

Non iniziare dal codice.

---

### Esercizio 6 — Mutation testing manuale

Nella copia locale del contratto corretto rimuovi temporaneamente:

```solidity
onlyState(State.Created)
```

da `fund()`.

Esegui la suite.

Domande:

1. quali test falliscono?
2. esiste qualche comportamento pericoloso che la suite ancora non rileva?
3. quale nuovo regression test aggiungeresti?

Poi ripristina il contratto corretto.

---

### Esercizio 7 — Proprietà storica

Scrivi in linguaggio naturale una proprietà che inizi con:

> Se lo stato è `ReleaseApproved`, allora in passato...

Poi prova a trasformarla in una sequenza di test deterministici.

Non serve ancora usare invariant testing: ci arriveremo più avanti.

---

### Esercizio 8 — Threat modeling

Aggiungi al threat model un nuovo ruolo:

```text
arbiter
```

senza scrivere codice.

Definisci:

- quando entra in gioco;
- quali stati può modificare;
- quale conflitto risolve;
- quali nuovi abusi introduce;
- quali proprietà di sicurezza dovrebbero limitarne il potere.

Questo esercizio serve a mostrare che ogni nuova capability amplia anche la superficie di attacco.

---

## 12. Cosa devo ricordare

1. **La sequenza è parte della sicurezza.** Una funzione può essere autorizzata per il caller giusto ma comunque eseguibile nello stato sbagliato.

2. **Disegna prima la state machine.** Gli stati e le transizioni dovrebbero nascere dalla specifica, non emergere accidentalmente dal codice.

3. **Le frecce assenti contano.** I test negativi devono provare le transizioni che non devono essere raggiungibili.

4. **Access control e state guard sono dimensioni diverse.** “Chi?” e “quando?” devono essere entrambi corretti.

5. **Uno stato racconta una storia.** Se `ReleaseApproved` è raggiungibile senza funding precedente, il significato dello stato è corrotto.

6. **Un revert va testato anche per l'assenza di effetti persistenti.** Non basta sapere che la call è fallita.

7. **Non confondere test di scenario con invarianti universali.** Un balance osservato in un percorso normale non è automaticamente una verità globale del protocollo.

8. **Il contratto di oggi è volutamente incompleto.** L'Ether rimane custodito e non viene trasferito: serve a separare state machine da external-call security.

---

## 13. Fonti della lezione

Fonti tecniche effettivamente consultate e verificate il **21 settembre 2026**:

1. **Solidity — Solidity 0.8.37 Release Announcement**  
   https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/  
   Usata per verificare la versione stabile corrente e le correzioni di sicurezza/bugfix incluse nella release.

2. **Solidity Documentation — Structure of a Contract**  
   https://docs.soliditylang.org/en/latest/structure-of-a-contract.html  
   Riferimento per state variables, events, errors ed enum.

3. **Solidity Documentation — Contracts**  
   https://docs.soliditylang.org/en/latest/contracts.html  
   Riferimento per state mutability, `immutable`, custom errors e semantica generale dei contratti.

4. **Solidity Documentation — Expressions and Control Structures**  
   https://docs.soliditylang.org/en/latest/control-structures.html  
   Riferimento per `revert`, atomicità delle modifiche e comportamento delle eccezioni.

5. **Solidity Documentation — SMTChecker and Formal Verification**  
   https://docs.soliditylang.org/en/latest/smtchecker.html  
   Consultata per il concetto di state properties e invarianti che coinvolgono sequenze di transazioni.

6. **Ethereum.org — Anatomy of Smart Contracts**  
   https://ethereum.org/developers/docs/smart-contracts/anatomy/  
   Riferimento per storage persistente, state variables e variabili dell'ambiente come `msg.sender`.

7. **Foundry — Configuration**  
   https://www.getfoundry.sh/config/  
   Riferimento corrente per `foundry.toml` e configurazione del compilatore.

8. **Foundry — Reference**  
   https://www.getfoundry.sh/reference/  
   Riferimento per Forge, cheatcodes, forge-std e strumenti di testing.

9. **Foundry — Guides**  
   https://www.getfoundry.sh/guides/  
   Consultata per il workflow di testing e per la continuità verso mutation, fuzz e invariant testing.

10. **OWASP Smart Contract Security — SC02:2026 Business Logic Vulnerabilities**  
    https://scs.owasp.org/sctop10/SC02-BusinessLogicVulnerabilities/  
    Riferimento per vulnerabilità logiche, invarianti e state machine path-dependent.

11. **OWASP Smart Contract Security — SCSVS Authorization Mechanisms**  
    https://scs.owasp.org/SCSVS/controls/SCSVS-AUTH-2/  
    Riferimento per controlli di autorizzazione sulle operazioni che modificano stato o eseguono azioni sensibili.

12. **OWASP Smart Contract Security — SCSVS-GOV-3**  
    https://scs.owasp.org/SCSVS/controls/SCSVS-GOV-3/  
    Consultata per transaction flow security, ripetibilità delle funzioni e integrità delle transizioni.

---

## Fine Lezione 3

