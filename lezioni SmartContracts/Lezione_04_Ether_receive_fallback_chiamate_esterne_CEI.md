# Smart Contract Security / Solidity Security
## Lezione 4 — Ether, `receive`, `fallback`, chiamate esterne e Checks-Effects-Interactions

> **Ambiente del corso:** esclusivamente didattico, difensivo e locale. Tutti gli esempi usano contratti giocattolo, account Foundry e fondi fittizi. Nessun fork di mainnet, nessun protocollo reale, nessun wallet reale e nessun RPC pubblico sono necessari.
>
> **Baseline verificata il 21 settembre 2026:** gli esempi continuano a usare **Solidity 0.8.37**, release stabile del 10 settembre 2026. La documentazione Solidity corrente indica `send()` e `transfer()` come deprecati e pianificati per la rimozione; per i trasferimenti di Ether useremo quindi `call{value: amount}("")`, controllandone sempre il risultato. La documentazione ufficiale raccomanda inoltre il pattern **Checks-Effects-Interactions (CEI)** quando una funzione effettua interazioni esterne.
>
> **Importante:** l'Escrow di questa lezione è ancora un contratto didattico e **non production-ready**. Introduciamo una vera interazione esterna verso il seller, ma rimandiamo alla Lezione 5 l'analisi completa della reentrancy, inclusi callback ricorsivi, cross-function reentrancy e relative difese aggiuntive.

---

# Collegamento con la Lezione 3

Nella Lezione 3 abbiamo costruito una macchina a stati deliberatamente incompleta:

```text
Created -> Funded -> ReleaseApproved
    |
    +-------> Cancelled
```

`ReleaseApproved` non trasferiva Ether: serviva per imparare a ragionare sulle transizioni prima di introdurre una **trust boundary** esterna.

Ora evolviamo il progetto.

La state machine diventa:

```text
                     buyer: fund(price)
          +------------------------------------+
          |                                    v
      +---------+                          +---------+
      | Created |                          | Funded  |
      +---------+                          +---------+
          |                                    |
          | buyer: cancelBeforeFunding()       | buyer: release()
          v                                    v
     +-----------+                         +----------+
     | Cancelled |                         | Released |
     +-----------+                         +----------+
       terminale                            terminale
```

La differenza cruciale è che la transizione:

```text
Funded -> Released
```

ora include:

```text
Escrow -> CALL con Ether -> seller
```

Per la prima volta nel progetto il controllo può uscire dall'Escrow ed entrare in codice che l'Escrow non controlla.

Questa è una delle soglie concettuali più importanti della sicurezza EVM.

---

# 1. Obiettivi

Alla fine della lezione dovresti saper:

- spiegare come Ether entra ed esce da un contratto;
- distinguere il balance nativo dell'account dal bookkeeping interno del protocollo;
- spiegare cosa rende una funzione `payable`;
- descrivere quando Solidity esegue una funzione nominata, `receive()` o `fallback()`;
- ricordare che `receive()` può essere invocata anche con `msg.value == 0` se la calldata è vuota;
- spiegare perché una chiamata esterna è un **trasferimento di controllo**, non soltanto un trasferimento di denaro;
- distinguere high-level external calls da low-level `call`;
- usare correttamente:

```solidity
(bool success, bytes memory returnData) = target.call{value: amount}(data);
```

- spiegare perché `success == true` non dimostra automaticamente che sia avvenuta l'azione applicativa che avevi in mente;
- spiegare perché il risultato di una low-level call deve essere controllato;
- applicare il pattern **Checks-Effects-Interactions**;
- capire perché CEI riduce la finestra di reentrancy ma non sostituisce una threat analysis completa;
- verificare con Foundry che un destinatario contract possa eseguire codice durante un payout;
- verificare che un payout rifiutato faccia revert senza lasciare uno stato incoerente;
- distinguere "saldo fisico dell'indirizzo" da "Ether contabilizzato dal protocollo";
- dimostrare in locale che un contratto può ricevere Ether senza eseguire il proprio `receive()`;
- riconoscere l'anti-pattern **unchecked external call**;
- leggere una funzione con la domanda da auditor:

> **In quale punto il controllo può lasciare questo contratto, e quali invarianti devono essere già veri prima che ciò accada?**

---

# 2. Modello mentale

## 2.1 Ether non è un ERC-20

Ether è la valuta nativa della EVM.

Ogni account ha un balance mantenuto direttamente dallo stato Ethereum:

```text
address A -> ETH balance
address B -> ETH balance
address C -> ETH balance
```

In Solidity puoi leggerlo con:

```solidity
address(someAccount).balance
```

o, per il contratto corrente:

```solidity
address(this).balance
```

Un ERC-20 funziona diversamente: il saldo è normalmente una voce in uno storage mapping di un altro contratto.

Concettualmente:

```text
ETH:
Ethereum state
  address -> balance

ERC-20:
Token contract storage
  balances[address] -> amount
```

Questa differenza avrà molta importanza quando arriveremo ai token.

---

## 2.2 `msg.value` è valore associato alla call corrente

Quando una transazione o una `CALL` EVM porta Ether a una funzione, quel frame di esecuzione vede:

```solidity
msg.value
```

Esempio:

```solidity
function fund() external payable {
    // msg.value = Ether associato a QUESTA chiamata
}
```

Se il buyer chiama:

```solidity
escrow.fund{value: 5 ether}();
```

all'interno di `fund()`:

```text
msg.sender = buyer
msg.value  = 5 ether
```

`msg.value` non significa:

> "quanto Ether possiede il buyer"

né:

> "quanto Ether possiede il contratto"

Significa:

> **quanto valore nativo è associato al message call corrente.**

---

## 2.3 `payable` è una porta che può accettare valore

Questa funzione non accetta Ether:

```solidity
function f() external {
    // nonpayable
}
```

Una chiamata a `f()` con `msg.value > 0` viene rifiutata.

Questa invece può riceverlo:

```solidity
function f() external payable {
    // msg.value può essere > 0
}
```

Attenzione alla formulazione:

```text
payable != deve ricevere Ether
payable  = può essere chiamata con Ether
```

Puoi quindi chiamare una funzione `payable` anche con:

```text
msg.value = 0
```

---

## 2.4 Inviare Ether può significare eseguire codice altrui

È facile immaginare un trasferimento come:

```text
Escrow balance -= 5 ETH
Seller balance += 5 ETH
```

Ma se `seller` è un contratto, il modello è più simile a:

```text
Escrow.release()
      |
      | CALL(value = 5 ETH)
      v
Seller.receive()
      |
      | può eseguire codice
      | può leggere stato
      | può scrivere storage
      | può chiamare altri contratti
      | può tentare una callback verso Escrow
      v
ritorno a Escrow.release()
```

Quindi:

> **un trasferimento di Ether verso un indirizzo deve essere trattato come un possibile trasferimento di controllo.**

Questo rimane un buon modello mentale anche quando il destinatario sembra "un normale account utente". Dopo EIP-7702, un EOA può avere una delegazione di codice eseguibile; in generale è sempre più fragile basare la sicurezza sull'assunzione "questo indirizzo non eseguirà mai codice".

---

## 2.5 Ogni external call crea un nuovo frame

Immagina una transaction che chiama A, che chiama B, che chiama C:

```text
Transaction
   |
   v
+------------------+
| frame A          |
| msg.sender=user  |
|                  |
| CALL B ----------+------+
+------------------+      |
                          v
                   +------------------+
                   | frame B          |
                   | msg.sender=A     |
                   |                  |
                   | CALL C ----------+------+
                   +------------------+      |
                                             v
                                      +------------------+
                                      | frame C          |
                                      | msg.sender=B     |
                                      +------------------+
```

Quando C ritorna, si torna a B.

Quando B ritorna, si torna ad A.

La transaction è una sola, ma al suo interno possono esserci molti **message calls** e molti frame di esecuzione.

Questo è essenziale per capire la reentrancy nella prossima lezione.

---

# 3. Teoria

## 3.1 Le principali strade con cui Ether può arrivare a un contratto

Nel modello normale di chiamata, Ether può arrivare tramite una funzione `payable` nominata:

```solidity
fund{value: 5 ether}()
```

oppure tramite una call con calldata vuota, che può arrivare a:

```solidity
receive() external payable
```

oppure tramite calldata che non corrisponde a una funzione esistente, che può arrivare a:

```solidity
fallback() external payable
```

Ma questo elenco non è sufficiente per un invariant sul **balance assoluto**.

Esistono meccanismi EVM che possono far aumentare il balance senza eseguire `receive()` o `fallback()`. Un caso didatticamente importante è un trasferimento dovuto a `SELFDESTRUCT`. EIP-6780 ha modificato profondamente la semantica di `SELFDESTRUCT`, ma mantiene il trasferimento del balance al beneficiary.

Quindi:

```text
"receive() fa revert"
```

NON implica:

```text
"address(this).balance non potrà mai aumentare in altro modo"
```

Questa distinzione è importante per gli invarianti contabili.

---

## 3.2 Dispatch: funzione normale, `receive` o `fallback`?

La domanda utile è:

> Quando arriva una call a un contratto, quale entry point viene eseguito?

Una semplificazione utile è:

```text
                 CALL al contratto
                        |
                        v
              calldata è vuota?
                /               \
              sì                 no
              |                   |
              v                   v
       esiste receive()?     selector corrisponde
           /      \          a una funzione?
         sì        no          /          \
         |          |        sì            no
         v          v         |              |
      receive    fallback     v              v
                 se esiste   funzione      fallback
```

Ci sono poi le regole `payable`/`nonpayable` quando `msg.value > 0`.

### Matrice pratica

| Calldata | `msg.value` | Entry point tipico |
|---|---:|---|
| vuota | 0 | `receive()` se presente; altrimenti `fallback()` se presente |
| vuota | > 0 | `receive()` se presente; altrimenti `fallback()` se `payable` |
| selector valido | 0 | funzione corrispondente |
| selector valido | > 0 | funzione corrispondente solo se `payable` |
| selector sconosciuto | 0 | `fallback()` |
| selector sconosciuto | > 0 | `fallback()` solo se `payable` |

Due dettagli da ricordare:

1. `receive()` è selezionata dalla **calldata vuota**, non dalla condizione `msg.value > 0`.
2. `fallback()` è anche una rete di sicurezza per chiamate con selector non riconosciuti.

---

## 3.3 `receive()`

Forma canonica:

```solidity
receive() external payable {
    // ...
}
```

Vincoli importanti:

- può essercene al massimo una;
- non ha nome;
- non ha parametri;
- non ritorna valori;
- deve essere `external`;
- deve essere `payable`.

Un uso legittimo può essere accettare plain Ether transfers.

Ma nel nostro Escrow la specifica dice:

> Il funding deve avvenire soltanto tramite `fund()`, perché vogliamo applicare controlli su ruolo, stato e importo.

Quindi un `receive()` permissivo sarebbe una seconda porta economica che aggira quel percorso.

Per rendere esplicita la policy useremo:

```solidity
receive() external payable {
    revert DirectEtherNotAccepted();
}
```

Questa scelta non impedisce ogni possibile aumento del raw balance, ma impedisce le normali plain calls con calldata vuota.

---

## 3.4 `fallback()`

Forma semplice:

```solidity
fallback() external payable {
    // ...
}
```

La forma moderna può anche ricevere la calldata completa e restituire bytes:

```solidity
fallback(bytes calldata input)
    external
    payable
    returns (bytes memory output)
{
    // ...
}
```

Non ne abbiamo bisogno in questa lezione.

Nel nostro Escrow vogliamo che una call a una funzione inesistente sia rumorosamente rifiutata:

```solidity
fallback() external payable {
    revert UnknownCall(msg.sig);
}
```

Questo rende esplicito che il contratto non considera il fallback una API generica.

---

## 3.5 `receive` e `fallback` non sono un sistema di accounting

Immagina di tenere un contatore:

```solidity
uint256 public accountedEther;

receive() external payable {
    accountedEther += msg.value;
}
```

Potresti essere tentato di assumere:

```text
accountedEther == address(this).balance
```

Ma questa uguaglianza non è una proprietà generale dell'EVM.

Se Ether arriva senza eseguire il `receive`, allora:

```text
address(this).balance aumenta
accountedEther       non aumenta
```

Per questo un protocollo serio deve separare:

```text
RAW BALANCE
= quanti wei si trovano fisicamente all'indirizzo
```

contro:

```text
PROTOCOL ACCOUNTING
= quanti wei il protocollo considera appartenenti a quali obbligazioni/crediti
```

Questa distinzione tornerà continuamente in vault, lending e token accounting.

---

## 3.6 Inviare Ether con `call`

La sintassi che useremo è:

```solidity
(bool success, bytes memory returnData) = recipient.call{value: amount}("");
```

Con payload vuoto:

```solidity
""
```

stiamo chiedendo una plain call con valore.

Se `recipient` è un contratto e possiede `receive()`, normalmente entreremo lì.

Il punto più importante è il return value:

```solidity
bool success
```

Una low-level call che fallisce non deve essere trattata come se il payout fosse riuscito.

Pattern minimo:

```solidity
(bool success,) = recipient.call{value: amount}("");
if (!success) revert EtherTransferFailed();
```

---

## 3.7 Perché non useremo `transfer()` come "difesa dalla reentrancy"

Storicamente si vede spesso:

```solidity
recipient.transfer(amount);
```

oppure:

```solidity
bool ok = recipient.send(amount);
```

Queste primitive erano associate a uno stipend di 2300 gas.

L'idea implicita in molto vecchio codice era:

> "se inoltro poco gas, il receiver non potrà fare abbastanza lavoro per diventare pericoloso".

Questo è un fragile confine di sicurezza perché i costi del gas degli opcode possono cambiare.

La documentazione Solidity corrente marca sia `send()` sia `transfer()` come **deprecated e scheduled for removal**.

Useremo quindi:

```solidity
call{value: amount}("")
```

accettando la conseguenza corretta:

> **il recipient può ricevere una quantità significativa di gas ed eseguire codice; la sicurezza deve venire dalla progettazione del nostro stato e non dall'aspettativa che il receiver sia troppo “povero di gas” per comportarsi in modo complesso.**

---

## 3.8 `call` inoltra controllo

Considera:

```solidity
(bool success,) = seller.call{value: price}("");
```

Prima della riga, l'Escrow ha il controllo.

Durante la riga:

```text
controllo -> seller
```

Il seller può essere:

```text
EOA semplice
contract con receive
contract con fallback
account con comportamento delegato
```

Se esegue codice, quel codice può a sua volta effettuare chiamate esterne.

Solidity documenta espressamente che qualsiasi interazione con un altro contratto introduce un potenziale pericolo e che un trasferimento di Ether può eseguire codice del recipient.

---

## 3.9 High-level call e low-level call

### High-level external call

Esempio:

```solidity
IERC20(token).transfer(to, amount);
```

Il compilatore conosce la firma ABI della funzione.

In generale hai:

- type checking;
- ABI encoding gestito dal compilatore;
- decode del valore di ritorno atteso;
- normale propagazione dei revert, salvo costrutti specifici come `try/catch`.

### Low-level call

Esempio:

```solidity
(bool success, bytes memory data) = target.call(payload);
```

Qui lavori più vicino alla primitive EVM `CALL`.

Il compilatore non sa semanticamente quale funzione pensi di invocare.

Per questo una low-level call richiede più responsabilità:

```text
costruzione calldata
interpretazione returndata
controllo success
validazione del target quando necessaria
ragionamento sui callback
```

Per inviare plain Ether, `call{value: amount}("")` è oggi la primitive appropriata, ma non va generalizzato in:

> "usiamo `.call()` per tutto".

Per invocare funzioni note di contratti noti, una interfaccia tipizzata è normalmente più leggibile e più sicura.

---

## 3.10 `success == true` significa successo EVM, non successo di business

Questo punto è sottile.

Immagina:

```solidity
(bool success,) = target.call(
    abi.encodeWithSignature("doSomething()")
);
```

Se `target` non ha la funzione ma possiede un fallback permissivo che non reverte, la call può ritornare:

```text
success = true
```

anche se la funzione di business che avevi in mente non è stata eseguita.

Quindi:

```text
success == true
```

significa grossolanamente:

> il frame di chiamata non è terminato con una failure/revert EVM.

Non significa automaticamente:

> la semantica applicativa attesa è stata soddisfatta.

Nel nostro caso specifico vogliamo soltanto trasferire Ether al seller con calldata vuota, quindi il criterio applicativo è più semplice:

```text
CALL con value non reverte
```

Ma quando useremo token e altri protocolli dovremo essere molto più precisi.

---

## 3.11 Atomicità e revert attraverso una external call

La nostra `release()` farà:

```solidity
state = State.Released;

(bool success,) = seller.call{value: price}("");

if (!success) {
    revert EtherTransferFailed(seller, price);
}
```

Potrebbe sembrare strano:

> "Ma se impostiamo `Released` prima e poi il payout fallisce, non resta uno stato falso?"

No, se eseguiamo `revert` nello stesso percorso di transaction.

Un revert annulla gli effetti persistenti di quel percorso di esecuzione.

Quindi:

```text
state = Released
        |
        v
external call fallisce
        |
        v
revert EtherTransferFailed
        |
        v
rollback della transaction
        |
        v
state torna Funded
balance torna quello precedente
```

Questa proprietà permette di applicare CEI senza accettare uno stato finale incoerente quando l'interazione fallisce.

---

## 3.12 Checks-Effects-Interactions

Il pattern CEI organizza una funzione così:

```text
1. CHECKS
2. EFFECTS
3. INTERACTIONS
```

### Checks

Verifica precondizioni:

```text
chi sta chiamando?
lo stato corrente permette l'azione?
gli input sono validi?
l'importo è valido?
```

### Effects

Aggiorna lo stato interno:

```text
state variables
balances interni
crediti
nonce
flag
```

### Interactions

Solo alla fine cedi il controllo:

```text
CALL
external contract function
ETH transfer
token callback
hook
```

Schema:

```text
CHECKS
   |
   v
EFFECTS
   |
   |  a questo punto lo stato locale descrive già
   |  l'operazione come consumata/completata
   v
INTERACTION ----------------------+
   |                              |
   | controllo esterno            | eventuale callback
   v                              |
callee                            |
   |                              |
   +------------------------------+
```

L'idea difensiva è:

> Se il codice esterno tenta di rientrare, dovrebbe osservare lo stato **già aggiornato**, non quello vecchio che permetteva l'azione originale.

---

## 3.13 CEI non è una formula magica

CEI è un pattern molto importante, non una prova matematica che "la funzione è sicura".

Devi ancora chiederti:

- sono stati aggiornati **tutti** gli effetti critici prima dell'interazione?
- esistono altre funzioni che il callback può chiamare?
- lo stato di altri contratti rimane coerente?
- ci sono callback indirette?
- una dipendenza esterna può richiamare un modulo diverso?
- esistono hook token?
- ci sono invariant che coinvolgono più contratti?
- l'external call può fallire e bloccare il flusso?

Nella Lezione 5 vedremo esattamente perché.

Per oggi il punto è:

```text
external call = trust boundary
```

quindi lo stato interno deve essere preparato **prima** di attraversarla.

---

## 3.14 Push payment e pull payment

Ci sono due famiglie concettuali.

### Push

Il protocollo invia direttamente il denaro durante un'azione:

```text
buyer -> release()
          |
          +----> Escrow paga seller immediatamente
```

Vantaggio didattico:

- rende evidente la external call.

Problema progettuale:

- se il recipient rifiuta Ether, quella action può fallire;
- il recipient entra direttamente nel control flow della funzione.

### Pull

Il protocollo registra un credito:

```text
release()
   |
   v
claimable[seller] += amount
```

poi il seller ritira in una action separata:

```text
seller -> withdraw()
```

Questo riduce il coupling tra una state transition e il payout.

OWASP e la documentazione Solidity raccomandano spesso design di tipo withdrawal/pull quando appropriato.

**In questa lezione usiamo intenzionalmente un push payout** perché vogliamo osservare chiaramente la trust boundary. Non è una dichiarazione che il push sia sempre la scelta migliore per un protocollo reale.

---

# 4. Esempio Solidity

Crea:

```text
src/EscrowWithPayout.sol
```

con questo contenuto:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title EscrowWithPayout
/// @notice Contratto didattico locale. NON production-ready.
/// @dev Introduce payout ETH e una external call verso il seller.
contract EscrowWithPayout {
    enum State {
        Created,
        Funded,
        Released,
        Cancelled
    }

    error ZeroSeller();
    error BuyerEqualsSeller();
    error ZeroPrice();
    error Unauthorized(address caller);
    error WrongState(State expected, State actual);
    error WrongValue(uint256 expected, uint256 actual);
    error EtherTransferFailed(address recipient, uint256 amount);
    error DirectEtherNotAccepted();
    error UnknownCall(bytes4 selector);

    event Funded(address indexed buyer, uint256 amount);
    event Released(
        address indexed buyer,
        address indexed seller,
        uint256 amount
    );
    event Cancelled(address indexed buyer);

    address public immutable buyer;
    address payable public immutable seller;
    uint256 public immutable price;

    State public state;

    constructor(address payable seller_, uint256 price_) {
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

    /// @notice Conclude l'Escrow e paga il seller.
    /// @dev Checks -> Effects -> Interactions.
    function release()
        external
        onlyBuyer
        onlyState(State.Funded)
    {
        // EFFECT:
        // consumiamo la transizione prima di cedere controllo.
        state = State.Released;

        // INTERACTION:
        // il controllo può ora passare al seller.
        (bool success,) = seller.call{value: price}("");

        // Una low-level call non propaga automaticamente la failure.
        // Convertiamo il false in un revert esplicito.
        if (!success) {
            revert EtherTransferFailed(seller, price);
        }

        emit Released(buyer, seller, price);
    }

    /// @notice Consente al buyer di cancellare solo prima del funding.
    function cancelBeforeFunding()
        external
        onlyBuyer
        onlyState(State.Created)
    {
        state = State.Cancelled;

        emit Cancelled(msg.sender);
    }

    /// @notice Il funding diretto senza chiamare fund() non è parte dell'API.
    receive() external payable {
        revert DirectEtherNotAccepted();
    }

    /// @notice Selector sconosciuti non fanno parte dell'API.
    fallback() external payable {
        revert UnknownCall(msg.sig);
    }
}
```

---

# 5. Analisi del codice

Applichiamo la checklist richiesta dal corso.

---

## 5.1 `fund()`

### Chi può chiamarla?

Solo:

```text
buyer
```

grazie a:

```solidity
onlyBuyer
```

### Quali input controlla il chiamante?

Non ci sono parametri ABI, ma il caller controlla:

```text
msg.value
```

Quindi `msg.value` è un vero input di sicurezza.

### Quale valore entra?

Esattamente:

```text
price
```

perché:

```solidity
if (msg.value != price) revert WrongValue(price, msg.value);
```

### Quale stato legge?

```solidity
buyer
state
price
```

### Quale stato modifica?

```solidity
state = State.Funded;
```

Il balance ETH dell'Escrow aumenta automaticamente come parte della call riuscita.

### Chiamate esterne?

Nessuna.

### Quando passa il controllo a codice esterno?

Mai, all'interno della funzione.

### Assunzioni

- `price` è stato validato nel constructor;
- il buyer deve avere abbastanza ETH per la call;
- il funding legittimo è un solo deposito esatto.

---

## 5.2 `release()`

È la funzione più importante della lezione.

```solidity
function release()
    external
    onlyBuyer
    onlyState(State.Funded)
{
    state = State.Released;

    (bool success,) = seller.call{value: price}("");

    if (!success) {
        revert EtherTransferFailed(seller, price);
    }

    emit Released(buyer, seller, price);
}
```

### Chi può chiamarla?

Solo il buyer.

### Quali input controlla il chiamante?

Non ci sono parametri della funzione.

Il caller controlla però **quando** tenta la call.

Questa è una reminder importante:

> la sequenza temporale delle entry point è essa stessa un input al protocollo.

### Quale valore entra?

La funzione è nonpayable.

Il buyer non deve inviare Ether a `release()`.

### Quale stato legge?

```text
buyer
state
seller
price
```

### Quale stato modifica?

Prima dell'interazione:

```solidity
state = State.Released;
```

### Quali chiamate esterne effettua?

```solidity
seller.call{value: price}("")
```

### Quando il controllo passa a codice esterno?

Esattamente su questa riga:

```solidity
(bool success,) = seller.call{value: price}("");
```

Questa riga dovrebbe attirare immediatamente l'occhio di un auditor.

### Quali assunzioni fa?

Non assume che il seller sia un EOA innocuo.

Il design deve sopravvivere al fatto che il seller:

- sia un contratto;
- esegua `receive()`;
- scriva storage;
- faccia altre external calls;
- faccia revert.

Il comportamento ricorsivo sarà analizzato nella Lezione 5.

---

## 5.3 Perché `state = Released` viene prima della call?

Per CEI.

Prima della external call, la macchina a stati deve già dire:

```text
questa release è stata consumata
```

Se durante il callback qualcuno prova a osservare il contratto, non deve vedere ancora:

```text
Funded
```

come se la transizione non fosse iniziata.

Schema:

```text
prima:
state = Funded

release()
   |
   | checks
   v
state = Released     <-- EFFECT PRIMA DELLA TRUST BOUNDARY
   |
   | external call
   v
seller code
```

---

## 5.4 Ma se il seller rifiuta Ether?

La call ritorna:

```text
success = false
```

Il nostro codice fa:

```solidity
revert EtherTransferFailed(seller, price);
```

Quindi l'intera operazione viene annullata.

Stato finale:

```text
state           = Funded
Escrow balance  = price
seller balance  invariato
```

Questo è esattamente il comportamento che vogliamo per questa semplice specifica.

---

## 5.5 `cancelBeforeFunding()`

### Chi può chiamarla?

Solo buyer.

### Input controllati?

Nessun parametro, ma il caller sceglie il timing.

### Valore?

Nessun Ether: funzione nonpayable.

### Stato letto?

```text
buyer
state
```

### Stato modificato?

```solidity
state = State.Cancelled;
```

### External calls?

Nessuna.

### Assunzioni?

È consentita soltanto in `Created`, quindi non deve rimborsare alcun funding legittimo.

---

## 5.6 `receive()`

```solidity
receive() external payable {
    revert DirectEtherNotAccepted();
}
```

### Chi può chiamarla?

Qualunque indirizzo può tentare una plain call con calldata vuota.

### Input controllati?

```text
msg.sender
msg.value
```

sono controllati dal contesto della call.

### Stato letto/modificato?

Nessuno.

### External calls?

Nessuna.

### Assunzione critica

Questa funzione implementa una **policy di API**, non un invariant assoluto sul raw balance.

Non dobbiamo scrivere una proprietà del tipo:

> "se `receive()` reverte, il balance non può aumentare".

Sarebbe una proprietà falsa dell'ambiente EVM.

---

## 5.7 `fallback()`

```solidity
fallback() external payable {
    revert UnknownCall(msg.sig);
}
```

### Chi può chiamarla?

Qualunque account che invii calldata non riconosciuta.

### Input controllati?

L'intera calldata è scelta dal caller.

Nel nostro corpo osserviamo:

```solidity
msg.sig
```

### Valore?

Poiché è `payable`, una call con selector sconosciuto può anche includere Ether, ma il body fa revert.

### Stato modificato?

Nessuno.

### External calls?

Nessuna.

### Assunzione

Selector sconosciuti non hanno semantica valida nel nostro protocollo.

---

# 6. Proprietà e invarianti

La parte più importante non è il codice: sono le proprietà che vogliamo difendere.

---

## 6.1 Proprietà di autorizzazione

> Solo il buyer può chiamare con successo `fund()`.

> Solo il buyer può chiamare con successo `release()`.

> Solo il buyer può chiamare con successo `cancelBeforeFunding()`.

---

## 6.2 Proprietà di state machine

> `fund()` può riuscire soltanto da `Created`.

> `release()` può riuscire soltanto da `Funded`.

> `cancelBeforeFunding()` può riuscire soltanto da `Created`.

> Una release riuscita rende lo stato `Released`.

> `Released` è terminale per le funzioni esposte in questa versione.

> `Cancelled` è terminale per le funzioni esposte in questa versione.

---

## 6.3 Proprietà economiche

> Un funding riuscito richiede esattamente `price` come `msg.value`.

> Una release riuscita trasferisce esattamente `price` al seller.

> Il seller non deve ricevere due payout tramite due `release()` riuscite.

Quest'ultima diventerà particolarmente importante nella Lezione 5.

---

## 6.4 Proprietà sul fallimento del payout

> Se il seller rifiuta il payout, `release()` deve revertire.

> Se `release()` reverte perché il payout fallisce, lo stato deve rimanere `Funded`.

> Se `release()` reverte perché il payout fallisce, i `price` wei devono rimanere nell'Escrow.

Queste sono proprietà di **atomicità applicativa**.

---

## 6.5 Proprietà sulle call dirette

> Una plain call con calldata vuota non è un percorso di funding autorizzato e deve fallire.

> Una call con selector sconosciuto deve fallire.

Ma NON scriviamo:

> "il balance dell'Escrow può aumentare soltanto tramite `fund()`".

Perché l'EVM permette trasferimenti di Ether che non passano attraverso il normale dispatch del recipient.

---

## 6.6 Invariant contabile robusto contro Ether inatteso

Un invariant ingenuo sarebbe:

```text
state == Funded  =>  address(escrow).balance == price
```

Questo può essere rotto da Ether forzato senza che la logica del protocollo sia stata violata.

Una formulazione più robusta per **questa versione** è:

```text
se state == Funded,
il protocollo deve essere in grado di pagare almeno price
```

che possiamo approssimare localmente come:

```text
state == Funded
    =>
address(escrow).balance >= price
```

Ancora più importante è separare il concetto:

```text
protocol liability = price
```

contro:

```text
raw balance = address(escrow).balance
```

Un surplus inatteso non deve creare un nuovo credito per il seller.

---

# 7. Threat model della nuova trust boundary

Con il payout introduciamo una nuova boundary:

```text
+-----------------------+
| Escrow                |
| stato che controlliamo|
+-----------+-----------+
            |
            | CALL + ETH
            v
+-----------------------+
| seller address        |
| comportamento esterno |
| potenzialmente arbitr.|
+-----------------------+
```

Domande da threat model:

```text
1. Il seller può essere un contract?
   Sì.

2. Il seller può rifiutare Ether?
   Sì.

3. Il seller può eseguire codice durante il payout?
   Sì.

4. Il seller può effettuare altre calls?
   Sì.

5. Il seller deve essere trusted perché il protocollo sia corretto?
   Idealmente no per gli invariant fondamentali.

6. Se il seller reverte, cosa succede?
   La nostra release reverte e resta Funded.

7. Cosa vede il seller se effettua una callback durante release?
   State.Released, perché applichiamo Effects prima dell'Interaction.
```

Il punto 7 è la porta d'ingresso alla Lezione 5.

---

# 8. Laboratorio Foundry

Tutto il laboratorio gira sulla EVM locale di Forge.

Non serve:

```text
RPC
fork
mainnet
wallet reale
fondi reali
```

---

## 8.1 Struttura dei file

Se stai continuando il progetto delle lezioni precedenti:

```text
smart-contract-security-course/
├── foundry.toml
├── lib/
│   └── forge-std/
├── src/
│   └── EscrowWithPayout.sol
└── test/
    └── EscrowWithPayout.t.sol
```

Un `foundry.toml` minimale può essere:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.37"
```

Se il progetto Foundry è già quello della Lezione 2/3, non è necessario inizializzarne uno nuovo.

---

## 8.2 Test helpers

Nel file di test creeremo tre piccoli contratti giocattolo.

### Receiver che accetta Ether ed esegue codice

```solidity
contract AcceptingSeller {
    uint256 public totalReceived;

    receive() external payable {
        totalReceived += msg.value;
    }
}
```

Questo dimostra che il payout non è solo un aggiornamento di balance: il recipient può eseguire un `SSTORE`.

### Receiver che rifiuta Ether

```solidity
contract RejectingSeller {
    receive() external payable {
        revert("REJECT_ETH");
    }
}
```

### Helper che trasferisce Ether tramite `SELFDESTRUCT`

```solidity
contract ForceEther {
    constructor() payable {}

    function force(address payable target) external {
        selfdestruct(target);
    }
}
```

`SELFDESTRUCT` è deprecato e non va preso come pattern applicativo da usare. Qui compare **solo** come strumento didattico locale per dimostrare una proprietà dell'ambiente EVM: il recipient non ha sempre l'opportunità di eseguire e rifiutare `receive()`.

EIP-6780 ha modificato il comportamento di distruzione dell'account, ma mantiene il trasferimento del balance al target.

---

## 8.3 Test suite completa

Crea:

```text
test/EscrowWithPayout.t.sol
```

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {EscrowWithPayout} from "../src/EscrowWithPayout.sol";

contract AcceptingSeller {
    uint256 public totalReceived;

    receive() external payable {
        // Dimostrazione: la external call può eseguire codice e scrivere storage.
        totalReceived += msg.value;
    }
}

contract RejectingSeller {
    receive() external payable {
        revert("REJECT_ETH");
    }
}

contract ForceEther {
    constructor() payable {}

    function force(address payable target) external {
        // SOLO LABORATORIO LOCALE.
        // SELFDESTRUCT è deprecato.
        selfdestruct(target);
    }
}

contract EscrowWithPayoutTest is Test {
    EscrowWithPayout internal escrow;

    address internal buyer;
    address payable internal seller;
    address internal outsider;

    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = payable(makeAddr("seller"));
        outsider = makeAddr("outsider");

        vm.deal(buyer, 100 ether);
        vm.deal(outsider, 100 ether);

        vm.prank(buyer);
        escrow = new EscrowWithPayout(seller, PRICE);
    }

    function testInitialState() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.price(), PRICE);
        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Created)
        );
        assertEq(address(escrow).balance, 0);
    }

    function testBuyerCanFundExactPrice() public {
        vm.prank(buyer);
        escrow.fund{value: PRICE}();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Funded)
        );
        assertEq(address(escrow).balance, PRICE);
    }

    function testReleasePaysEOASeller() public {
        _fund(escrow);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        escrow.release();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Released)
        );
        assertEq(address(escrow).balance, 0);
        assertEq(seller.balance, sellerBalanceBefore + PRICE);
    }

    function testReleaseToContractExecutesReceiverCode() public {
        AcceptingSeller receiver = new AcceptingSeller();

        vm.prank(buyer);
        EscrowWithPayout contractSellerEscrow = new EscrowWithPayout(
            payable(address(receiver)),
            PRICE
        );

        _fund(contractSellerEscrow);

        assertEq(receiver.totalReceived(), 0);

        vm.prank(buyer);
        contractSellerEscrow.release();

        assertEq(receiver.totalReceived(), PRICE);
        assertEq(
            uint256(contractSellerEscrow.state()),
            uint256(EscrowWithPayout.State.Released)
        );
        assertEq(address(contractSellerEscrow).balance, 0);
    }

    function testRejectingSellerMakesReleaseRevertAtomically() public {
        RejectingSeller receiver = new RejectingSeller();

        vm.prank(buyer);
        EscrowWithPayout rejectingEscrow = new EscrowWithPayout(
            payable(address(receiver)),
            PRICE
        );

        _fund(rejectingEscrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.EtherTransferFailed.selector,
                address(receiver),
                PRICE
            )
        );
        vm.prank(buyer);
        rejectingEscrow.release();

        // L'effetto State.Released è stato rollbackato.
        assertEq(
            uint256(rejectingEscrow.state()),
            uint256(EscrowWithPayout.State.Funded)
        );

        // Anche il valore resta nell'Escrow.
        assertEq(address(rejectingEscrow).balance, PRICE);
        assertEq(address(receiver).balance, 0);
    }

    function testOutsiderCannotRelease() public {
        _fund(escrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.Unauthorized.selector,
                outsider
            )
        );
        vm.prank(outsider);
        escrow.release();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Funded)
        );
        assertEq(address(escrow).balance, PRICE);
    }

    function testCannotReleaseBeforeFunding() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Funded,
                EscrowWithPayout.State.Created
            )
        );
        vm.prank(buyer);
        escrow.release();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Created)
        );
        assertEq(address(escrow).balance, 0);
    }

    function testCannotReleaseTwice() public {
        _fund(escrow);

        vm.prank(buyer);
        escrow.release();

        uint256 sellerBalanceAfterFirstRelease = seller.balance;

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Funded,
                EscrowWithPayout.State.Released
            )
        );
        vm.prank(buyer);
        escrow.release();

        assertEq(seller.balance, sellerBalanceAfterFirstRelease);
        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Released)
        );
    }

    function testPlainEtherTransferIsRejected() public {
        uint256 amount = 1 ether;

        vm.prank(outsider);
        (bool success,) = address(escrow).call{value: amount}("");

        // Low-level call: il revert del receiver arriva come success=false.
        assertFalse(success);
        assertEq(address(escrow).balance, 0);
        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Created)
        );
    }

    function testUnknownSelectorIsRejected() public {
        bytes memory unknownCall = hex"deadbeef";

        vm.prank(outsider);
        (bool success,) = address(escrow).call(unknownCall);

        assertFalse(success);
        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Created)
        );
    }

    function testForcedEtherBypassesReceive() public {
        uint256 forcedAmount = 1 ether;

        // Finanziamo il test contract con fondi fittizi Foundry.
        vm.deal(address(this), forcedAmount);

        ForceEther force = new ForceEther{value: forcedAmount}();

        // Non chiama fund().
        // Non esegue receive() dell'Escrow.
        force.force(payable(address(escrow)));

        assertEq(address(escrow).balance, forcedAmount);

        // La state machine non è cambiata.
        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Created)
        );
    }

    function testForcedEtherDoesNotIncreaseSellerEntitlement() public {
        uint256 forcedAmount = 1 ether;

        vm.deal(address(this), forcedAmount);
        ForceEther force = new ForceEther{value: forcedAmount}();
        force.force(payable(address(escrow)));

        // Il funding legittimo aggiunge PRICE sopra il surplus inatteso.
        _fund(escrow);

        assertEq(address(escrow).balance, PRICE + forcedAmount);

        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.release();

        // Il seller riceve soltanto l'importo contrattuale.
        assertEq(seller.balance, sellerBefore + PRICE);

        // Il surplus raw rimane nel contratto didattico.
        assertEq(address(escrow).balance, forcedAmount);

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Released)
        );
    }

    function testCannotCancelAfterFunding() public {
        _fund(escrow);

        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowWithPayout.WrongState.selector,
                EscrowWithPayout.State.Created,
                EscrowWithPayout.State.Funded
            )
        );
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        assertEq(
            uint256(escrow.state()),
            uint256(EscrowWithPayout.State.Funded)
        );
        assertEq(address(escrow).balance, PRICE);
    }

    function _fund(EscrowWithPayout target) internal {
        vm.prank(buyer);
        target.fund{value: PRICE}();
    }
}
```

---

## 8.4 Eseguire i test

```bash
forge test
```

Per vedere il call trace completo del payout verso un contract receiver:

```bash
forge test \
  --match-test testReleaseToContractExecutesReceiverCode \
  -vvvv
```

Cerca mentalmente una struttura del tipo:

```text
EscrowWithPayout::release()
  -> AcceptingSeller::receive()
```

Questo trace è la prova concreta del modello mentale:

```text
"inviare Ether" può significare "eseguire codice del destinatario"
```

---

## 8.5 Tracciare il payout che fallisce

```bash
forge test \
  --match-test testRejectingSellerMakesReleaseRevertAtomically \
  -vvvv
```

Il percorso concettuale è:

```text
buyer
  |
  v
Escrow.release()
  |
  | state = Released
  |
  v
RejectingSeller.receive()
  |
  | revert
  v
success = false
  |
  v
Escrow reverts EtherTransferFailed
  |
  v
rollback completo
  |
  +--> state = Funded
  +--> balance = PRICE
```

---

## 8.6 Tracciare Ether forzato

```bash
forge test \
  --match-test testForcedEtherBypassesReceive \
  -vvvv
```

Il risultato da capire non è un exploit contro il nostro Escrow.

È una proprietà della piattaforma:

```text
receive() non è l'unico modo in cui il raw balance può aumentare
```

Per un auditor questo cambia come si scrivono gli invariant.

---

# 9. Test negativi

Gli happy path sono solo metà del lavoro.

Per questa lezione dobbiamo dimostrare almeno che:

```text
outsider release             -> revert
release prima di funding     -> revert
release due volte             -> revert
cancel dopo funding           -> revert
plain ETH transfer            -> failure
selector sconosciuto          -> failure
seller che rifiuta ETH        -> release revert
payout fallito                -> state resta Funded
payout fallito                -> ETH resta nell'Escrow
Ether forzato                 -> non cambia la state machine
Ether forzato                 -> non aumenta il payout dovuto
```

Questa lista è già più utile di una metrica astratta come:

```text
"abbiamo 90% code coverage"
```

Coverage può dirti quali righe sono state eseguite.

Non dimostra che hai formulato le proprietà giuste.

---

# 10. Vulnerabilità / errore di progettazione: unchecked external call

In questa lezione non costruiamo ancora un exploit di reentrancy completo; quello sarà il laboratorio della Lezione 5.

Studiamo però un errore già sufficiente a corrompere la state machine:

> **ignorare il fallimento della external call.**

---

## 10.1 Versione difettosa minima

Crea solo per il laboratorio locale:

```text
src/UncheckedCallEscrow.sol
```

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice CONTRATTO DELIBERATAMENTE DIFETTOSO.
/// @dev Solo laboratorio locale.
contract UncheckedCallEscrow {
    enum State {
        Created,
        Funded,
        Released
    }

    address public immutable buyer;
    address payable public immutable seller;
    uint256 public immutable price;

    State public state;

    event PayoutAttempted(bool success);

    constructor(address payable seller_, uint256 price_) {
        buyer = msg.sender;
        seller = seller_;
        price = price_;
        state = State.Created;
    }

    function fund() external payable {
        require(msg.sender == buyer, "NOT_BUYER");
        require(state == State.Created, "WRONG_STATE");
        require(msg.value == price, "WRONG_VALUE");

        state = State.Funded;
    }

    function release() external {
        require(msg.sender == buyer, "NOT_BUYER");
        require(state == State.Funded, "WRONG_STATE");

        // L'ordine CEI da solo non basta.
        state = State.Released;

        (bool success,) = seller.call{value: price}("");

        // BUG LOGICO:
        // registriamo soltanto il risultato, ma non facciamo revert.
        emit PayoutAttempted(success);
    }
}
```

Osserva una cosa importante.

Questa funzione fa apparentemente:

```text
Effects -> Interaction
```

quindi rispetta l'ordine CEI.

Ma è comunque sbagliata.

Perché?

Perché CEI protegge una classe di problemi di sequencing, ma non trasforma una call fallita in una call riuscita.

La state machine dice:

```text
Released
```

anche se il seller non ha ricevuto nulla.

---

## 10.2 Proprietà violata

Avevamo definito:

> Una `release()` riuscita deve trasferire esattamente `price` al seller.

Nel contratto difettoso la transaction `release()` può avere successo a livello del caller anche quando:

```text
seller payout = 0
Escrow balance = price
state = Released
```

Quindi lo stato racconta una storia falsa.

---

## 10.3 Riproduzione locale

Aggiungi al test file:

```solidity
import {UncheckedCallEscrow} from "../src/UncheckedCallEscrow.sol";
```

Poi:

```solidity
function testUncheckedCallCreatesFalseReleasedState() public {
    RejectingSeller receiver = new RejectingSeller();

    vm.prank(buyer);
    UncheckedCallEscrow broken = new UncheckedCallEscrow(
        payable(address(receiver)),
        PRICE
    );

    vm.prank(buyer);
    broken.fund{value: PRICE}();

    vm.prank(buyer);
    broken.release();

    // La transaction non è revertita...
    assertEq(
        uint256(broken.state()),
        uint256(UncheckedCallEscrow.State.Released)
    );

    // ...ma il seller non è stato pagato.
    assertEq(address(receiver).balance, 0);

    // I fondi sono ancora bloccati nel contratto.
    assertEq(address(broken).balance, PRICE);
}
```

Esegui:

```bash
forge test \
  --match-test testUncheckedCallCreatesFalseReleasedState \
  -vvvv
```

---

## 10.4 Root cause

La causa non è:

```text
"call è cattiva"
```

La causa è:

```text
external call può fallire
        +
risultato non viene fatto rispettare
        +
stato applicativo considera l'operazione completata
```

In forma da audit finding:

```text
The low-level ETH transfer result is not enforced.
A reverting recipient leaves the escrow in Released state
while the seller receives no funds and the ETH remains locked.
```

---

## 10.5 Correzione

La nostra versione corretta usa:

```solidity
state = State.Released;

(bool success,) = seller.call{value: price}("");

if (!success) {
    revert EtherTransferFailed(seller, price);
}
```

Se la call fallisce:

```text
revert
  |
  +--> rollback state
  +--> rollback value transfer
```

---

## 10.6 Test di regressione

Il test di regressione è proprio:

```solidity
function testRejectingSellerMakesReleaseRevertAtomically() public
```

Non basta correggere il codice.

La disciplina che stiamo costruendo è:

```text
1. proprietà
2. bug riprodotto
3. fix
4. regression test
```

Se in futuro qualcuno rimuove accidentalmente il check su `success`, il test deve diventare rosso.

---

# 11. Prima/dopo

## Prima: risultato ignorato

```solidity
state = State.Released;
(bool success,) = seller.call{value: price}("");
emit PayoutAttempted(success);
```

Possibile risultato:

```text
state          = Released
seller paid    = no
escrow balance = price
transaction    = success
```

Lo stato applicativo è incoerente.

---

## Dopo: risultato enforce-ato

```solidity
state = State.Released;
(bool success,) = seller.call{value: price}("");

if (!success) {
    revert EtherTransferFailed(seller, price);
}
```

Se il payout fallisce:

```text
state          = Funded
seller paid    = no
escrow balance = price
transaction    = revert
```

Se il payout riesce:

```text
state          = Released
seller paid    = yes, price
escrow balance = eventuale surplus inatteso
transaction    = success
```

Quest'ultima riga sul balance è intenzionale: non assumiamo che il raw balance iniziale fosse esattamente `price`.

---

# 12. Lettura da auditor: come marcare le trust boundary

Quando apri un contratto, evidenzia subito tutte le operazioni che possono cedere controllo.

Esempi:

```solidity
target.call(...)
target.delegatecall(...)
target.staticcall(...)
IContract(target).someFunction(...)
IERC20(token).transfer(...)
IERC721(...).safeTransferFrom(...)
IERC1155(...).safeTransferFrom(...)
```

Non tutte hanno la stessa semantica, ma tutte meritano una domanda:

```text
può eseguire codice che non controllo?
```

Poi guarda ciò che viene scritto **dopo** la chiamata.

Pattern sospetto:

```solidity
externalInteraction();

balances[user] = 0;
state = Completed;
used[id] = true;
```

Domanda:

> Perché queste Effects avvengono dopo aver ceduto il controllo?

Non significa automaticamente che esista una vulnerabilità, ma è un punto da investigare.

---

# 13. Checklist da auditor

Quando trovi Ether o external calls, usa questa checklist.

## Ingresso di Ether

- Quali funzioni sono `payable`?
- Il contratto definisce `receive()`?
- Definisce `fallback()`?
- Il fallback è `payable`?
- L'Ether inviato direttamente ha una semantica definita o viene rifiutato?
- La logica assume erroneamente che tutto l'Ether debba passare da una funzione specifica?
- Esistono invariant fragili del tipo `address(this).balance == accounting`?

## Uscita di Ether

- Dove viene effettuato il value transfer?
- Viene usata una low-level call?
- Il return value viene controllato?
- Se il recipient fa revert, quale stato resta?
- Il recipient può bloccare una transizione importante?
- È più appropriato un pull payment?

## Controllo esterno

- Qual è l'ultima modifica di storage prima della external call?
- Tutti gli effetti critici sono già stati applicati?
- Il callback può osservare stato intermedio?
- Può chiamare un'altra funzione del contratto?
- Può attraversare altri contratti e tornare indietro?

## API surface

- Selector sconosciuti vengono accettati o rifiutati?
- `receive()` e `fallback()` fanno più lavoro del necessario?
- Esiste una seconda strada accidentale per depositare fondi?

## Testing

- Hai testato un recipient EOA?
- Hai testato un recipient contract?
- Hai testato un recipient che fa revert?
- Hai verificato il rollback dello stato?
- Hai verificato il raw balance dopo un fallimento?
- Hai testato Ether inatteso/forzato quando gli invariant dipendono dal balance?

---

# 14. Esercizi

Non includo le soluzioni complete: provaci prima.

---

## Esercizio 1 — Dispatch matrix

Senza eseguire il codice, predici quale entry point viene selezionato per ciascuna call a un contratto con:

```solidity
function foo() external payable {}
receive() external payable {}
fallback() external payable {}
```

Casi:

```text
A. calldata vuota, value = 0
B. calldata vuota, value = 1 wei
C. selector di foo(), value = 0
D. selector di foo(), value = 1 wei
E. 0xdeadbeef, value = 0
F. 0xdeadbeef, value = 1 wei
```

Poi crea un contratto strumentato con eventi e verifica la previsione con Foundry.

---

## Esercizio 2 — Nonpayable

Rendi `foo()` nonpayable:

```solidity
function foo() external {}
```

Scrivi due test:

```text
foo() con 0 wei -> success
foo() con 1 wei -> revert
```

Spiega **dove** avviene il rifiuto rispetto al body della funzione.

---

## Esercizio 3 — Payout rifiutato

Partendo dall'Escrow corretto, crea un altro receiver che faccia revert con custom error invece di una stringa.

Verifica che:

```text
release reverte
state == Funded
escrow balance == PRICE
receiver balance == 0
```

---

## Esercizio 4 — Ether inatteso

Estendi il test `testForcedEtherDoesNotIncreaseSellerEntitlement()` con:

```text
forcedAmount = 13 ether
PRICE        = 5 ether
```

Domanda:

> Perché sarebbe pericoloso implementare `release()` come “manda al seller `address(this).balance`” invece di mandare l'obbligazione definita dalla specifica?

Non pensare solo alla sicurezza contro un attacker: pensa anche a accounting e fondi inviati per errore.

---

## Esercizio 5 — Trova il bug

Analizza:

```solidity
function release() external onlyBuyer {
    require(state == State.Funded);

    (bool ok,) = seller.call{value: address(this).balance}("");
    require(ok);

    state = State.Released;
}
```

Scrivi almeno quattro osservazioni da auditor.

Una deve riguardare:

```text
ordering
```

una deve riguardare:

```text
amount
```

una deve riguardare:

```text
trust boundary
```

una deve riguardare:

```text
test negativo mancante
```

---

## Esercizio 6 — Pull design

Senza implementarlo ancora completamente, ridisegna l'Escrow in pseudocodice affinché `release()` non paghi immediatamente il seller ma crei un credito:

```text
claimable[seller] = PRICE
```

Poi immagina una funzione separata:

```text
withdraw()
```

Scrivi:

- nuove proprietà;
- nuovi stati o variabili necessarie;
- quale funzione contiene la trust boundary esterna;
- quali nuovi edge case introduci.

Questo esercizio prepara la Lezione 5.

---

# 15. Mini review guidata

Leggi questa funzione come se non l'avessi scritta tu:

```solidity
function release()
    external
    onlyBuyer
    onlyState(State.Funded)
{
    state = State.Released;

    (bool success,) = seller.call{value: price}("");

    if (!success) {
        revert EtherTransferFailed(seller, price);
    }

    emit Released(buyer, seller, price);
}
```

## Passo 1 — entry point

È `external`.

Surface pubblica.

## Passo 2 — authorization

```solidity
onlyBuyer
```

## Passo 3 — state guard

```solidity
onlyState(State.Funded)
```

## Passo 4 — effects

```solidity
state = State.Released;
```

## Passo 5 — trust boundary

```solidity
seller.call{value: price}("")
```

Metti mentalmente un grande segnale:

```text
========== EXTERNAL CONTROL ==========
```

## Passo 6 — failure semantics

Il risultato viene controllato.

## Passo 7 — rollback reasoning

Se `success == false`, il revert annulla anche `state = Released`.

## Passo 8 — domande residue

Un auditor non dovrebbe fermarsi qui.

Chiederebbe:

```text
Cosa può fare il seller durante la call?
Può richiamare release()?
Può chiamare altre funzioni?
Lo stato Released basta a bloccare ogni percorso pericoloso?
Ci sono invariant cross-function?
```

Queste sono esattamente le domande della prossima lezione.

---

# 16. Errori concettuali comuni

## Errore 1

> "`receive()` viene chiamata solo se `msg.value > 0`."

No.

La discriminante principale è la calldata vuota. Una call con calldata vuota e value zero può comunque selezionare `receive()`.

---

## Errore 2

> "Se `receive()` reverte, il contratto non può ricevere Ether."

Troppo forte.

Può rifiutare normali message calls che passano dal dispatch, ma il raw balance può aumentare con meccanismi che non eseguono `receive()`.

---

## Errore 3

> "Trasferire Ether è solo spostare numeri tra balance."

No.

Una `CALL` verso un contract può eseguire codice.

---

## Errore 4

> "Uso `transfer()`, quindi la reentrancy è risolta."

È una difesa obsoleta e fragile. La documentazione Solidity corrente marca `transfer()` e `send()` come deprecati e pianificati per la rimozione.

---

## Errore 5

> "Ho usato CEI, quindi ogni problema di external call è risolto."

No.

Il contratto `UncheckedCallEscrow` rispetta l'ordine Effects -> Interaction ma rimane logicamente rotto perché non enforce-a il fallimento del payout.

---

## Errore 6

> "Se `.call()` restituisce true, la funzione che volevo chiamare è sicuramente stata eseguita."

No.

Una low-level call ragiona sul successo del frame EVM, non sulla tua intenzione applicativa. Selector sconosciuti possono, per esempio, essere accettati da un fallback.

---

## Errore 7

> "Un EOA non esegue codice, quindi posso distinguere i destinatari sicuri con una semplice assunzione account/contract."

È un modello sempre meno affidabile. EIP-7702 consente a un EOA di impostare una delegazione di codice; inoltre esistono da tempo altri motivi per cui euristiche basate sul code size non sono un confine di sicurezza affidabile.

Il modello difensivo migliore è:

> **se cedi controllo a un address, progetta come se quel percorso potesse eseguire codice non fidato.**

---

# 17. Cosa devo ricordare

Se ricordi solo pochi concetti, conserva questi.

## 1. `msg.value` appartiene alla call corrente

Non è il balance dell'utente né il balance del contratto.

## 2. `payable` abilita l'ingresso di Ether su quella call

Non significa che la funzione debba riceverne.

## 3. `receive()` e `fallback()` fanno parte della superficie di attacco

Sono entry point e vanno progettati intenzionalmente.

## 4. Raw balance e protocol accounting non sono la stessa cosa

Non costruire invariant fragili assumendo che ogni wei sia passato dal tuo codice di deposito.

## 5. Una external call è un trasferimento di controllo

```text
call = trust boundary
```

## 6. Le low-level calls vanno controllate

```solidity
(bool success,) = target.call(...);
if (!success) revert ...;
```

## 7. CEI significa

```text
Checks -> Effects -> Interactions
```

Lo stato locale deve essere reso coerente prima di cedere controllo.

## 8. Un revert dopo una interaction fallita può rollbackare gli Effects precedenti

È ciò che permette alla nostra `release()` di tornare correttamente a `Funded` se il seller rifiuta Ether.

## 9. CEI è necessario in molti design, ma non è sufficiente per ogni forma di reentrancy

La Lezione 5 partirà esattamente da questa limitazione.

---

# 18. Checklist personale prima di passare alla Lezione 5

Dovresti riuscire a spiegare senza guardare gli appunti:

- [ ] differenza tra msg.value e address(this).balance
- [ ] cosa significa payable
- [ ] quando scatta receive()
- [ ] quando scatta fallback()
- [ ] perché receive() non è una garanzia sul raw balance
- [ ] cosa restituisce una low-level call
- [ ] perché success va controllato
- [ ] perché una call con Ether può eseguire codice
- [ ] cosa significa trust boundary
- [ ] ordine Checks -> Effects -> Interactions
- [ ] perché il rollback salva lo stato se il payout fallisce
- [ ] perché CEI non equivale a "sicuro per definizione"
- [ ] differenza tra push e pull payments
- [ ] perché address(this).balance non dovrebbe definire automaticamente il payout dovuto

Se uno di questi punti non è chiaro, conviene consolidarlo prima della reentrancy.

---

# 19. Fonti della lezione

Le fonti sotto sono state effettivamente consultate per verificare sintassi e raccomandazioni aggiornate al 21 settembre 2026.

## [S1] Solidity 0.8.37 — Release Announcement

Solidity Team, 10 settembre 2026.

- https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/

Usata per la baseline del compilatore del corso e per verificare che 0.8.37 sia la release stabile corrente considerata nella lezione.

## [S2] Solidity Documentation — Contracts / Special Functions

Sezioni `Receive Ether Function` e `Fallback Function`.

- https://docs.soliditylang.org/en/latest/contracts.html#receive-ether-function
- https://docs.soliditylang.org/en/latest/contracts.html#fallback-function

Usata per verificare:

- sintassi di `receive()`;
- sintassi di `fallback()`;
- dispatch con calldata vuota;
- relazione receive/fallback;
- requisiti `external`/`payable`;
- stato attuale della deprecazione di `send()` e `transfer()`.

## [S3] Solidity Documentation — Units and Globally Available Variables / Address members

- https://docs.soliditylang.org/en/latest/units-and-global-variables.html#members-of-address-types

Usata per verificare:

- `address.balance`;
- semantica di `call`, `send`, `transfer`;
- return values delle low-level calls;
- deprecazione di `send()` e `transfer()`.

## [S4] Solidity Documentation — Security Considerations

- https://docs.soliditylang.org/en/latest/security-considerations.html

Usata per:

- pericoli delle external interactions;
- reentrancy come conseguenza del passaggio di controllo;
- raccomandazione Checks-Effects-Interactions;
- failure modes dei trasferimenti Ether;
- withdrawal/pull pattern come design da considerare.

## [S5] Foundry — Reference e testing

- https://www.getfoundry.sh/reference/
- https://getfoundry.sh/forge/cheatcodes
- https://getfoundry.sh/reference/cheatcodes/prank/
- https://getfoundry.sh/cheatcodes/expect-revert
- https://getfoundry.sh/forge/writing-tests

Usata per verificare l'uso corrente di:

- `forge test`;
- `forge-std/Test.sol`;
- `vm.prank`;
- `vm.expectRevert`;
- comportamento speciale di `expectRevert` con low-level calls, motivo per cui nei test diretti a `receive`/`fallback` controlliamo esplicitamente il boolean `success`.

## [S6] EIP-6780 — SELFDESTRUCT only in same transaction

- https://eips.ethereum.org/EIPS/eip-6780

Usata per verificare la semantica moderna di `SELFDESTRUCT`: fuori dal caso speciale della creazione nella stessa transaction non elimina più normalmente codice/storage, ma continua a trasferire il balance al target. Nel laboratorio viene usato soltanto per dimostrare in locale che il raw ETH balance può cambiare senza eseguire `receive()`.

## [S7] EIP-7702 — Set Code for EOAs

- https://eips.ethereum.org/EIPS/eip-7702

Usata per aggiornare il modello mentale account/contract: un EOA può installare una delegation indicator e, quando chiamato, eseguire codice delegato. Questo rafforza la regola difensiva di non fondare la sicurezza sull'assunzione "questo address non eseguirà codice".

## [S8] OWASP Smart Contract Security 2026

- https://scs.owasp.org/sctop10/
- https://scs.owasp.org/sctop10/SC08-ReentrancyAttacks/
- https://scs.owasp.org/SCWE/SCSVS-GOV/SCWE-102/

Usata per confrontare la lezione con le raccomandazioni correnti su:

- unchecked external calls;
- CEI;
- reentrancy;
- pull-based withdrawals quando appropriati;
- necessità di test focalizzati sulle external interactions.

## [S9] OpenZeppelin Contracts 5.x — Utilities

- https://docs.openzeppelin.com/contracts/5.x/api/utils

Usata come riferimento secondario aggiornato per la gestione di value transfer e per la raccomandazione di considerare CEI / reentrancy protection quando una call inoltra controllo al recipient.

---

# Fine Lezione 4

Quando vorrai continuare, la Lezione 5 partirà dalla riga più importante di oggi:

```solidity
(bool success,) = seller.call{value: price}("");
```

La domanda sarà:

> **Cosa succede se il codice eseguito durante quella call richiama l'Escrow prima che il primo frame abbia terminato?**

Quello sarà il punto di ingresso alla **reentrancy**, sempre e soltanto in un laboratorio Foundry locale con contratti giocattolo.
