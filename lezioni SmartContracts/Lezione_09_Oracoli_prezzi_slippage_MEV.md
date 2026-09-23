# Lezione 9 — Oracoli, prezzi, decimals, slippage e MEV come rischio progettuale

> **Scopo:** secure coding, auditing, threat modeling e testing in ambiente locale.  
> Tutti i contratti, gli oracoli e gli exchange di questa lezione sono **mock giocattolo** destinati esclusivamente a Foundry/Anvil.

---

# 1. Obiettivi

Alla fine della lezione dovresti saper:

- spiegare perché uno smart contract ha bisogno di un **oracle**;
- distinguere il dato on-chain dalla realtà economica esterna;
- trattare un oracle come una **trust boundary**;
- riconoscere price manipulation, stale data, invalid data e configuration risk;
- ragionare correttamente sui `decimals`;
- evitare errori di scaling e precisione nei prezzi;
- capire che `block.timestamp` è utile per freshness ma non è una fonte di verità economica;
- spiegare che cosa significa **slippage**;
- capire perché `amountOutMin = 0` è quasi sempre una specifica economica pericolosa;
- distinguere slippage normale da problemi legati al transaction ordering;
- comprendere MEV, front-running e sandwiching come rischi di progettazione;
- trasformare questi rischi in proprietà verificabili e test Foundry;
- analizzare un consumer di prezzi con metodo da auditor.

Questa lezione **non insegna a manipolare mercati o protocolli reali**.

Le simulazioni avvengono soltanto con prezzi e AMM fittizi locali.

---

# 2. Modello mentale

Uno smart contract non "sa" quanto vale ETH, USDC, BTC o qualsiasi altro asset.

La EVM conosce cose come:

```text
storage
msg.sender
msg.value
block.timestamp
balances
calldata
```

ma non contiene una variabile:

```text
ETH_USD_PRICE
```

Se un contratto deve conoscere un prezzo, quella informazione deve arrivare da qualche parte.

Schema:

```text
Mercati / fonti esterne
        |
        v
      Oracle
        |
        | prezzo
        v
 Smart Contract Consumer
        |
        v
 decisione economica
```

Per esempio:

```text
ETH vale 3.000 USD
        |
        v
collateral value = 2 ETH * 3.000
        |
        v
6.000 USD
```

Il passaggio critico è:

```text
dato esterno
    ->
decisione irreversibile on-chain
```

L'oracle è quindi una **trust boundary**.

---

# 3. Perché gli oracoli esistono

La blockchain raggiunge consenso sullo stato che essa stessa esegue.

Non può ottenere autonomamente consenso su:

- prezzo di un asset su mercati esterni;
- temperatura;
- risultato sportivo;
- tasso FX;
- NAV di un asset reale;
- eventi off-chain.

Questi dati devono essere introdotti tramite un meccanismo esterno.

Per la security review, la domanda non è soltanto:

> l'oracle restituisce un numero?

La domanda vera è:

> **perché dovremmo credere che quel numero sia adatto a questa decisione economica?**

---

# 4. Oracle correctness ha più dimensioni

Supponiamo che un feed restituisca:

```text
3_000_00000000
```

Dire "il feed funziona" non basta.

Dobbiamo controllare almeno:

```text
1. Fonte corretta?
2. Pair corretto?
3. Decimals corretti?
4. Valore positivo?
5. Dato sufficientemente fresco?
6. Feed operativo?
7. Unità coerenti con il consumer?
8. Prezzo economicamente plausibile?
9. Il protocollo sa cosa fare se il feed fallisce?
```

La sicurezza di un oracle consumer è quindi un problema di **validazione semantica**, non soltanto di ABI.

---

# 5. Prezzo e unità

Un prezzo senza unità è quasi privo di significato.

Considera:

```text
3000
```

Potrebbe significare:

```text
3000 USD / ETH
3000 centesimi / ETH
3000 USDC base units / ETH
3000 con 8 decimals
3000 con 18 decimals
```

Per questo dobbiamo sempre annotare:

```text
asset base
asset quote
decimals del prezzo
decimals degli asset
```

---

# 6. Decimals

Supponiamo un oracle con:

```text
price = 300_000_000_000
decimals = 8
```

Il prezzo umano è:

```text
300_000_000_000 / 10^8
= 3000
```

ossia:

```text
3000 USD / ETH
```

Ma Solidity non usa floating point.

Il valore resta:

```solidity
300_000_000_000
```

e il programma deve tenere conto dello scaling.

---

# 7. Esempio di errore sui decimals

Supponiamo:

```text
1 ETH = 3000 USD
```

Asset:

```text
ETH: 18 decimals
USD token: 6 decimals
Oracle: 8 decimals
```

Abbiamo tre scale:

```text
ETH amount:
1e18

price:
3000 * 1e8

USD amount:
? * 1e6
```

Fare semplicemente:

```solidity
value = ethAmount * price;
```

produce un numero scalato in modo errato.

È necessario derivare esplicitamente la formula.

---

# 8. Derivazione della formula

Definiamo:

```text
amountBase = quantità ETH in 18 decimals
price      = USD per ETH in 8 decimals
```

Quindi:

```text
amount ETH = amountBase / 1e18
price USD  = price / 1e8
```

Valore USD reale:

```text
(amountBase / 1e18) * (price / 1e8)
```

Se vogliamo il risultato in unità USD a 6 decimals:

```text
usdBase =
amountBase * price * 1e6
/
(1e18 * 1e8)
```

cioè:

```text
usdBase =
amountBase * price
/
1e20
```

La formula nasce dalle unità.

Non dalla memoria.

Regola pratica:

> **scrivi sempre le unità accanto alle variabili durante una review economica.**

---

# 9. Precisione e overflow intermedio

Anche se il risultato finale entra in `uint256`, l'espressione:

```solidity
x * y / denominator
```

può avere un prodotto intermedio problematico.

OpenZeppelin Contracts 5.x offre:

```solidity
Math.mulDiv(x, y, denominator)
```

che calcola il rapporto con precisione estesa e permette anche di scegliere il rounding.

Questo non elimina la necessità di capire le unità.

Serve a eseguire meglio una formula **già corretta**.

---

# 10. Stale price

Un prezzo può essere autentico ma vecchio.

Esempio:

```text
ultimo aggiornamento: 10:00
ora:                 16:00
```

Se il mercato è cambiato drasticamente, usare ancora quel dato può essere pericoloso.

Definiamo:

```text
MAX_AGE = 1 hour
```

Proprietà:

```text
block.timestamp - updatedAt <= MAX_AGE
```

Se non vale:

```text
revert
```

---

# 11. Perché `block.timestamp` esiste qui

Solidity espone:

```solidity
block.timestamp
```

che rappresenta il timestamp del blocco.

È utile per confrontare l'età di un dato:

```solidity
if (block.timestamp - updatedAt > maxAge) {
    revert StalePrice();
}
```

Non bisogna però confonderlo con una fonte di casualità o con un orologio esterno perfetto.

Per freshness è normalmente una componente del modello temporale on-chain, ma il requisito deve tollerare le caratteristiche del timestamp di blocco.

---

# 12. Oracle giocattolo locale

Creiamo un feed minimale.

## `src/mocks/MockPriceOracle.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract MockPriceOracle {
    uint8 public immutable decimals;

    int256 public answer;
    uint256 public updatedAt;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setPrice(
        int256 newAnswer,
        uint256 newUpdatedAt
    ) external {
        answer = newAnswer;
        updatedAt = newUpdatedAt;
    }

    function latestPrice()
        external
        view
        returns (
            int256,
            uint256
        )
    {
        return (answer, updatedAt);
    }
}
```

È volutamente insicuro.

Chiunque può chiamare:

```solidity
setPrice(...)
```

Questo è accettabile **solo perché è un mock di laboratorio**.

Ci permette di simulare:

- prezzo corretto;
- prezzo zero;
- prezzo negativo;
- stale price;
- variazioni arbitrarie.

Non è un oracle production-ready.

---

# 13. Consumer vulnerabile minimo

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

interface ILooseOracle {
    function latestPrice()
        external
        view
        returns (
            int256 answer,
            uint256 updatedAt
        );
}

contract VulnerableValuation {
    ILooseOracle public immutable oracle;

    constructor(ILooseOracle oracle_) {
        oracle = oracle_;
    }

    function valueOf(
        uint256 amount
    ) external view returns (uint256) {
        (int256 answer,) =
            oracle.latestPrice();

        return amount * uint256(answer);
    }
}
```

---

# 14. Perché è vulnerabile

Il contratto assume:

```text
answer > 0
```

senza verificarlo.

Assume:

```text
dato fresco
```

senza verificarlo.

Assume:

```text
decimals già compatibili
```

senza nemmeno considerarli.

Assume:

```text
moltiplicazione = valore economicamente corretto
```

senza definire l'unità del risultato.

Un bug economico può quindi nascere anche se:

```text
nessun access control è rotto
nessuna reentrancy esiste
nessun overflow avviene
```

Questo è il motivo per cui gli errori oracle sono spesso **business logic vulnerabilities**.

---

# 15. Consumer più robusto

Costruiamo una utility semplice.

## `src/PriceConsumer.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Math} from
    "@openzeppelin/contracts/utils/math/Math.sol";

interface IPriceOracle {
    function decimals()
        external
        view
        returns (uint8);

    function latestPrice()
        external
        view
        returns (
            int256 answer,
            uint256 updatedAt
        );
}

contract PriceConsumer {
    IPriceOracle public immutable oracle;

    uint256 public immutable maxAge;

    error InvalidPrice();
    error InvalidTimestamp();
    error StalePrice();

    constructor(
        IPriceOracle oracle_,
        uint256 maxAge_
    ) {
        oracle = oracle_;
        maxAge = maxAge_;
    }

    function readPrice()
        public
        view
        returns (uint256)
    {
        (
            int256 answer,
            uint256 updatedAt
        ) = oracle.latestPrice();

        if (answer <= 0) {
            revert InvalidPrice();
        }

        if (
            updatedAt == 0 ||
            updatedAt > block.timestamp
        ) {
            revert InvalidTimestamp();
        }

        if (
            block.timestamp - updatedAt
                > maxAge
        ) {
            revert StalePrice();
        }

        return uint256(answer);
    }

    function quote18To6(
        uint256 amount18
    ) external view returns (uint256) {
        uint256 price = readPrice();

        uint8 priceDecimals =
            oracle.decimals();

        uint256 priceScale =
            10 ** uint256(priceDecimals);

        // amount18 / 1e18
        // * price / priceScale
        // * 1e6
        //
        // = amount18 * price * 1e6
        //   / (1e18 * priceScale)
        //
        // Riordiniamo con mulDiv.

        uint256 valueAtPriceScale =
            Math.mulDiv(
                amount18,
                price,
                1e18
            );

        return Math.mulDiv(
            valueAtPriceScale,
            1e6,
            priceScale
        );
    }
}
```

---

# 16. Nota sulla precisione della funzione

La funzione sopra è didattica.

Il doppio `mulDiv` può introdurre rounding nella prima divisione.

In produzione, la formula e l'ordine delle operazioni vanno progettati in base a:

- range degli input;
- precisione richiesta;
- rounding desiderato;
- decimals supportati.

Il punto della lezione è:

```text
unità -> formula -> rounding policy -> implementazione
```

non:

```text
copio una formula e spero che funzioni.
```

---

# 17. Chainlink: modello concettuale

Un consumer Chainlink Data Feed tipicamente legge dati da un feed tramite un'interfaccia standardizzata.

Il concetto rilevante per noi è che il consumer non dovrebbe limitarsi a:

```text
"ho ricevuto un numero"
```

ma deve valutare metadati e configurazione pertinenti, tra cui:

- decimals del feed;
- timestamp dell'ultimo aggiornamento;
- semantica della coppia;
- feed corretto per chain/asset;
- comportamento in condizioni eccezionali;
- eventuali limiti e raccomandazioni del feed specifico.

La documentazione ufficiale Chainlink deve essere consultata per l'integrazione concreta della rete e del feed scelto.

Per evitare che il laboratorio dipenda da indirizzi o feed reali, **non colleghiamo questa lezione ad alcuna mainnet/testnet**.

---

# 18. Integrare un prezzo nell'Escrow

Immaginiamo che il nostro Escrow debba accettare una release solo se il valore depositato è almeno:

```text
1.000 USD
```

Questo introduce una nuova dipendenza:

```text
TokenEscrow
   |
   +----> ERC20 token
   |
   +----> Price Oracle
```

Ora il threat model cresce.

Prima avevamo:

```text
token semantics
```

Ora abbiamo anche:

```text
oracle correctness
oracle freshness
oracle units
oracle availability
```

---

# 19. La disponibilità dell'oracle è parte della sicurezza

Supponiamo:

```solidity
price = oracle.read();
```

Se il feed non è disponibile, cosa deve accadere?

Possibili policy:

```text
A. bloccare tutte le operazioni;
B. bloccare solo operazioni price-sensitive;
C. usare una fonte secondaria;
D. usare ultimo prezzo entro un limite;
E. entrare in emergency mode.
```

Nessuna scelta è universalmente corretta.

Ma una cosa è pericolosa:

```text
fallimento oracle
->
fallback arbitrario non documentato
```

Il failure mode deve essere progettato.

---

# 20. Price manipulation: concetto

Un oracle è manipolabile quando il dato utilizzato dal protocollo può essere spostato abbastanza da alterare una decisione economica.

Esempio astratto:

```text
prezzo corretto = 100
prezzo osservato = 250
```

Il protocollo potrebbe calcolare:

```text
collateral value = 2.5x reale
```

e consentire un'azione che non dovrebbe essere possibile.

Nel nostro corso non manipoliamo mercati veri.

Simuliamo semplicemente:

```solidity
mockOracle.setPrice(...)
```

per vedere se il consumer resiste a dati anomali.

---

# 21. Spot price vs robustezza

Un prezzo spot ricavato da un singolo mercato può essere molto sensibile allo stato immediato di quel mercato.

La domanda da auditor è:

> quanto capitale / quanta influenza serve per muovere la sorgente di prezzo abbastanza da rompere una proprietà del protocollo?

Poi:

> per quanto tempo deve essere mantenuta quella distorsione?

E ancora:

> il protocollo usa il prezzo nello stesso blocco in cui può essere alterata la sorgente?

Queste domande collegano:

```text
oracle design
liquidity
time window
economic security
```

---

# 22. TWAP: intuizione

TWAP significa:

```text
Time-Weighted Average Price
```

Invece di usare soltanto:

```text
prezzo adesso
```

si considera una media su una finestra temporale.

Intuizione:

```text
spot:
        *
        |
--------+------

TWAP:
-----media nel tempo-----
```

Un TWAP può rendere più costosa una manipolazione breve.

Ma:

```text
TWAP != impossibile da manipolare
```

La sicurezza dipende da:

- lunghezza della finestra;
- profondità/liquidità;
- struttura del mercato;
- frequenza di osservazione;
- modalità di calcolo.

---

# 23. Freshness e TWAP non sono la stessa cosa

Sono due proprietà diverse.

```text
Freshness:
"quanto è recente il dato?"

TWAP:
"su quale intervallo è aggregato?"
```

Un TWAP può essere:

```text
vecchio
```

e un prezzo freschissimo può essere:

```text
troppo istantaneo / manipolabile
```

Auditare un oracle richiede distinguere le dimensioni.

---

# 24. Slippage

Supponiamo di voler scambiare:

```text
100 TOKEN_A
```

e ci aspettiamo:

```text
200 TOKEN_B
```

Tra il momento in cui formuliamo l'aspettativa e l'esecuzione, il risultato effettivo può cambiare.

La differenza è slippage.

Per controllarla, una funzione di swap spesso include:

```text
amountOutMin
```

Requisito:

```text
actualOut >= amountOutMin
```

altrimenti:

```text
revert
```

---

# 25. Il bug `amountOutMin = 0`

Considera:

```solidity
router.swap(
    amountIn,
    0
);
```

Semanticamente stiamo dicendo:

> accetto qualsiasi output, anche quasi zero.

Il problema non è sintattico.

Il codice compila perfettamente.

È un bug di **specifica economica**.

---

# 26. Mock AMM locale

Costruiamo un simulatore semplice.

## `src/mocks/MockSwap.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

contract MockSwap {
    uint256 public rateE18 = 2e18;

    error SlippageExceeded();

    function setRate(
        uint256 newRateE18
    ) external {
        rateE18 = newRateE18;
    }

    function quote(
        uint256 amountIn
    ) public view returns (uint256) {
        return amountIn * rateE18 / 1e18;
    }

    function swap(
        uint256 amountIn,
        uint256 amountOutMin
    ) external view returns (uint256) {
        uint256 amountOut =
            quote(amountIn);

        if (amountOut < amountOutMin) {
            revert SlippageExceeded();
        }

        return amountOut;
    }
}
```

Non è un AMM reale.

Non ha riserve.

Non sposta token.

Serve esclusivamente a modellare:

```text
expected output
actual output
slippage bound
```

---

# 27. Consumer vulnerabile allo slippage

```solidity
contract BadSwapConsumer {
    MockSwap public immutable dex;

    constructor(MockSwap dex_) {
        dex = dex_;
    }

    function execute(
        uint256 amountIn
    ) external view returns (uint256) {
        return dex.swap(
            amountIn,
            0
        );
    }
}
```

Se il rate passa:

```text
2.0 -> 0.1
```

il consumer accetta comunque il risultato.

---

# 28. Consumer con bound

```solidity
contract BoundedSwapConsumer {
    MockSwap public immutable dex;

    constructor(MockSwap dex_) {
        dex = dex_;
    }

    function execute(
        uint256 amountIn,
        uint256 amountOutMin
    ) external view returns (uint256) {
        return dex.swap(
            amountIn,
            amountOutMin
        );
    }
}
```

Ora l'utente o il protocollo esprime una proprietà:

```text
non accetto output inferiore a X
```

Questa è la differenza fra:

```text
eseguire uno swap
```

e:

```text
eseguire uno swap entro condizioni economiche definite
```

---

# 29. MEV: modello mentale

Ethereum.org definisce MEV come valore estraibile tramite:

```text
inclusione
esclusione
riordinamento
```

delle transazioni in un blocco, oltre alle normali ricompense/fee.

Per un application developer il punto essenziale è:

> **l'ordine delle transazioni non è una proprietà neutrale su cui basare ingenuamente la sicurezza economica.**

Una transazione può essere osservata e altre transazioni possono finire:

```text
prima
dopo
```

di essa.

---

# 30. Front-running

Modello astratto:

```text
Alice invia TX A

qualcun altro osserva A

invia TX B con interesse
a essere eseguita prima

ordine finale:

B
A
```

Non serve conoscere tecniche offensive per capire il rischio.

Da designer dobbiamo chiederci:

> se qualcuno può cambiare lo stato prima della mia transazione, quali assunzioni diventano false?

---

# 31. Sandwiching: intuizione difensiva

Schema astratto:

```text
TX esterna 1
    |
    v
TX utente
    |
    v
TX esterna 2
```

Se la transazione dell'utente accetta uno slippage enorme, l'esecuzione può avvenire a condizioni significativamente peggiori.

Ethereum.org identifica il sandwich trading come una forma di MEV che può causare maggiore slippage e peggior execution per gli utenti.

Per noi la remediation didattica principale è:

```text
non lasciare la condizione economica non vincolata
```

quindi usare:

- `amountOutMin`;
- deadline sensate;
- oracle/quote model appropriato;
- limiti di price impact;
- design resistente al transaction ordering quando necessario.

---

# 32. Slippage protection non elimina il MEV

Questo è importante.

Se imponiamo:

```text
amountOut >= minOut
```

abbiamo una proprietà locale.

Non abbiamo dimostrato:

```text
nessuno può estrarre valore
```

Abbiamo soltanto definito il peggior risultato accettabile.

Quindi:

```text
slippage limit
!=
MEV elimination
```

È una mitigazione del danno economico entro una soglia.

---

# 33. Deadline

Molti protocolli associano a un'azione anche:

```text
deadline
```

Proprietà:

```text
block.timestamp <= deadline
```

Questo evita che una transazione resti valida indefinitamente quando le condizioni attese erano legate a un momento specifico.

Anche qui:

```text
deadline
!=
price protection
```

Serve a limitare il tempo.

`amountOutMin` limita invece il risultato economico.

Sono due invarianti diversi.

---

# 34. Contratto locale per slippage + deadline

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

interface ISwap {
    function swap(
        uint256 amountIn,
        uint256 amountOutMin
    ) external view returns (uint256);
}

contract SafeSwapIntent {
    ISwap public immutable swapper;

    error Expired();

    constructor(ISwap swapper_) {
        swapper = swapper_;
    }

    function execute(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external view returns (uint256) {
        if (block.timestamp > deadline) {
            revert Expired();
        }

        return swapper.swap(
            amountIn,
            amountOutMin
        );
    }
}
```

Il chiamante ora codifica due condizioni:

```text
tempo massimo
output minimo
```

---

# 35. Analisi funzione-per-funzione

## `PriceConsumer.readPrice()`

### Chi può chiamarla?

Chiunque.

È `view`.

### Input controllati dal caller

Nessuno direttamente.

### Stato letto

```text
oracle
maxAge
block.timestamp
```

### External calls

```text
oracle.latestPrice()
```

### Quando il controllo passa fuori?

Durante la lettura del feed.

### Assunzioni

- `oracle` implementa l'interfaccia prevista;
- `updatedAt` ha la semantica attesa;
- `answer` usa i decimals dichiarati;
- `maxAge` è appropriato all'asset;
- failure/revert dell'oracle è un comportamento accettabile.

---

# 36. `quote18To6()`

## Caller

Chiunque.

## Input

```text
amount18
```

controllato dal chiamante.

## Stato letto

- oracle;
- price;
- decimals.

## Stato modificato

Nessuno.

## External calls

```text
readPrice()
oracle.decimals()
```

## Assunzioni

- input usa 18 decimals;
- output desiderato usa 6 decimals;
- oracle quote corrisponde semanticamente alla conversione;
- decimals non causano scaling inatteso;
- rounding è accettabile.

Da auditor, una funzione come questa va annotata con le unità:

```text
amount18: BASE units, 1e18
price: QUOTE/BASE, 10^oracleDecimals
return: QUOTE units, 1e6
```

---

# 37. `SafeSwapIntent.execute()`

## Caller

Chiunque.

## Input controllati

```text
amountIn
amountOutMin
deadline
```

## Stato letto

```text
block.timestamp
swapper
```

## External call

```text
swapper.swap(...)
```

## Assunzioni

- `swapper` esegue la semantica prevista;
- `amountOutMin` è stato calcolato in modo ragionevole;
- `deadline` non è inutile;
- caller accetta il rischio entro il bound dichiarato.

Una API può essere formalmente sicura e tuttavia permettere all'utente di passare:

```text
amountOutMin = 0
deadline = type(uint256).max
```

Quindi il protocol design deve stabilire chi è responsabile dei bounds.

---

# 38. Proprietà e invarianti

## Oracle

### O1 — Il prezzo deve essere positivo

```text
price <= 0
=> revert
```

### O2 — Timestamp presente

```text
updatedAt == 0
=> revert
```

### O3 — Niente timestamp futuro

```text
updatedAt > block.timestamp
=> revert
```

### O4 — Freshness

```text
block.timestamp - updatedAt <= maxAge
```

### O5 — Unit correctness

Per input noto:

```text
1 ETH @ 3000 USD/ETH
=> 3000e6 USD units
```

### O6 — Scaling coerente per decimals diversi

Lo stesso prezzo economico rappresentato con 8 o 18 decimals deve produrre lo stesso valore economico finale, entro la rounding policy.

---

## Slippage

### S1 — Output insufficiente

```text
actualOut < amountOutMin
=> revert
```

### S2 — Output al limite

```text
actualOut == amountOutMin
=> success
```

### S3 — Deadline

```text
block.timestamp > deadline
=> revert
```

### S4 — Nessuna esecuzione economicamente non limitata

A livello di protocol design potremmo richiedere:

```text
amountOutMin > 0
```

ma va valutato in base all'asset e alla semantica del sistema.

---

# 39. Laboratorio Foundry

Struttura:

```text
oracle-lab/
├── foundry.toml
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── src/
│   ├── PriceConsumer.sol
│   ├── SafeSwapIntent.sol
│   └── mocks/
│       ├── MockPriceOracle.sol
│       └── MockSwap.sol
└── test/
    ├── PriceConsumer.t.sol
    └── SafeSwapIntent.t.sol
```

Installazione:

```bash
forge init oracle-lab
cd oracle-lab

forge install OpenZeppelin/openzeppelin-contracts
```

`foundry.toml`:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]

remappings = [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/"
]
```

---

# 40. Test oracle — setup

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/Test.sol";

import {
    MockPriceOracle
} from "../src/mocks/MockPriceOracle.sol";

import {
    PriceConsumer
} from "../src/PriceConsumer.sol";

contract PriceConsumerTest is Test {
    MockPriceOracle oracle;
    PriceConsumer consumer;

    uint256 constant MAX_AGE = 1 hours;

    function setUp() public {
        oracle =
            new MockPriceOracle(8);

        consumer =
            new PriceConsumer(
                IPriceOracle(address(oracle)),
                MAX_AGE
            );

        vm.warp(1_000_000);

        oracle.setPrice(
            3000e8,
            block.timestamp
        );
    }
}
```

---

# 41. Happy path

```solidity
function test_ReadFreshPrice()
    public
{
    assertEq(
        consumer.readPrice(),
        3000e8
    );
}
```

---

# 42. Test negativo — zero

```solidity
function test_ZeroPriceReverts()
    public
{
    oracle.setPrice(
        0,
        block.timestamp
    );

    vm.expectRevert(
        PriceConsumer.InvalidPrice.selector
    );

    consumer.readPrice();
}
```

---

# 43. Test negativo — prezzo negativo

```solidity
function test_NegativePriceReverts()
    public
{
    oracle.setPrice(
        -1,
        block.timestamp
    );

    vm.expectRevert(
        PriceConsumer.InvalidPrice.selector
    );

    consumer.readPrice();
}
```

Il punto importante è che:

```text
cast int256 -> uint256
```

non deve avvenire prima della validazione.

---

# 44. Test negativo — stale data

```solidity
function test_StalePriceReverts()
    public
{
    oracle.setPrice(
        3000e8,
        block.timestamp
    );

    vm.warp(
        block.timestamp
        + MAX_AGE
        + 1
    );

    vm.expectRevert(
        PriceConsumer.StalePrice.selector
    );

    consumer.readPrice();
}
```

Qui `vm.warp()` modifica il timestamp nell'ambiente Foundry locale.

Non stiamo alterando alcuna blockchain reale.

---

# 45. Boundary test freshness

Il confine è importante.

```solidity
function test_ExactlyMaxAgeIsAccepted()
    public
{
    uint256 t = block.timestamp;

    oracle.setPrice(
        3000e8,
        t
    );

    vm.warp(t + MAX_AGE);

    assertEq(
        consumer.readPrice(),
        3000e8
    );
}
```

Perché?

Il codice reverte quando:

```text
age > maxAge
```

non:

```text
age >= maxAge
```

Questo è un esempio di specifica precisa che evita errori `>` vs `>=`.

---

# 46. Timestamp futuro

```solidity
function test_FutureTimestampReverts()
    public
{
    oracle.setPrice(
        3000e8,
        block.timestamp + 1
    );

    vm.expectRevert(
        PriceConsumer.InvalidTimestamp.selector
    );

    consumer.readPrice();
}
```

---

# 47. Test dei decimals

Per:

```text
1 ETH
3000 USD/ETH
output USD con 6 decimals
```

il risultato atteso è:

```text
3000e6
```

Test:

```solidity
function test_QuoteOneEth()
    public
{
    uint256 result =
        consumer.quote18To6(1 ether);

    assertEq(
        result,
        3000e6
    );
}
```

Questo tipo di test è molto più utile di:

```text
assert(result > 0)
```

perché verifica effettivamente lo scaling.

---

# 48. Test property-based sui decimals

Puoi creare un secondo oracle:

```text
decimals = 18
price = 3000e18
```

e verificare che:

```text
quote(1 ether) == 3000e6
```

come nel feed a 8 decimals.

Proprietà:

```text
stesso prezzo economico
+ diversa rappresentazione
= stesso valore economico
```

---

# 49. Test slippage

Setup:

```solidity
contract SafeSwapIntentTest is Test {
    MockSwap dex;
    SafeSwapIntent consumer;

    function setUp() public {
        dex = new MockSwap();

        consumer =
            new SafeSwapIntent(
                ISwap(address(dex))
            );

        vm.warp(1_000_000);
    }
}
```

---

# 50. Happy path swap

Rate:

```text
2.0
```

Input:

```text
100
```

Output:

```text
200
```

Test:

```solidity
function test_SwapWithinLimit()
    public
{
    uint256 out =
        consumer.execute(
            100 ether,
            190 ether,
            block.timestamp + 5 minutes
        );

    assertEq(
        out,
        200 ether
    );
}
```

---

# 51. Test negativo slippage

```solidity
function test_RevertIfRateFallsTooFar()
    public
{
    dex.setRate(1e18);

    vm.expectRevert(
        MockSwap.SlippageExceeded.selector
    );

    consumer.execute(
        100 ether,
        190 ether,
        block.timestamp + 5 minutes
    );
}
```

Aspettativa:

```text
expected minimo = 190
actual = 100
=> revert
```

---

# 52. Boundary test slippage

```solidity
function test_ExactMinOutPasses()
    public
{
    dex.setRate(19e17);

    uint256 out =
        consumer.execute(
            100 ether,
            190 ether,
            block.timestamp + 5 minutes
        );

    assertEq(
        out,
        190 ether
    );
}
```

Anche qui:

```text
actual < min
```

reverte.

```text
actual == min
```

passa.

---

# 53. Deadline scaduta

```solidity
function test_ExpiredIntentReverts()
    public
{
    uint256 deadline =
        block.timestamp + 5 minutes;

    vm.warp(deadline + 1);

    vm.expectRevert(
        SafeSwapIntent.Expired.selector
    );

    consumer.execute(
        100 ether,
        190 ether,
        deadline
    );
}
```

---

# 54. Vulnerabilità locale — oracle non validato

Contratto:

```solidity
contract BadEscrowValuation {
    MockPriceOracle public oracle;

    constructor(
        MockPriceOracle oracle_
    ) {
        oracle = oracle_;
    }

    function value(
        uint256 amount
    ) external view returns (uint256) {
        (
            int256 price,
        ) = oracle.latestPrice();

        return amount * uint256(price);
    }
}
```

Nel laboratorio:

```text
1. imposta price = valore plausibile;
2. osserva output;
3. imposta price = dato stale o anomalo;
4. osserva che il consumer continua a usarlo.
```

Il problema è l'assenza di policy.

---

# 55. Correzione

Introduci:

```text
positive check
timestamp check
freshness check
decimals-aware scaling
```

e un test di regressione per ciascuna proprietà.

Non basta avere:

```text
un test "bad oracle reverts"
```

È meglio sapere **perché** deve revertire.

Quindi:

```text
zero
negative
stale
future timestamp
wrong scaling
```

sono casi separati.

---

# 56. Circuit breaker

Una strategia difensiva possibile è rifiutare valori fuori da un range previsto.

Esempio concettuale:

```solidity
if (
    price < minPrice ||
    price > maxPrice
) {
    revert PriceOutOfBounds();
}
```

OWASP include la validazione di prezzi anomali e circuit breaker tra le mitigazioni per oracle risk.

Ma bisogna essere prudenti:

```text
range statico mal scelto
```

può bloccare il protocollo durante un vero movimento di mercato.

Quindi il circuit breaker è una **policy di rischio**, non una formula magica.

---

# 57. Deviation check

Un'altra idea è confrontare:

```text
nuovo prezzo
vs
prezzo precedente / fonte secondaria
```

e rifiutare variazioni superiori a una soglia.

Esempio:

```text
old = 100
new = 160
max deviation = 20%
```

Il sistema potrebbe:

```text
pause
revert
richiedere conferma
usare fallback
```

Ancora una volta, la reazione fa parte della specifica.

---

# 58. Multi-source oracle

Un singolo writer:

```text
Admin -> price
```

crea una trust assumption forte.

Più fonti/aggregazione possono ridurre il rischio di un singolo punto di compromissione, ma introducono nuove domande:

```text
quorum?
median?
outlier?
stale source?
source correlation?
governance?
```

"Decentralizzato" non significa automaticamente sicuro.

Da auditor devi capire il meccanismo concreto.

---

# 59. Admin-set price

Questo contratto è una red flag:

```solidity
function setPrice(
    uint256 price
) external onlyOwner {
    currentPrice = price;
}
```

Non è necessariamente sempre sbagliato.

Ma significa:

```text
owner compromise
= price compromise
```

Se quel prezzo controlla:

```text
liquidazioni
mint
redemption
payout
```

la chiave admin fa parte direttamente della sicurezza economica.

OWASP evidenzia esplicitamente il rischio di oracle aggiornabili immediatamente da un singolo admin.

---

# 60. Threat model completo

## Asset

```text
fondi nell'Escrow
token in custodia
diritto economico buyer/seller
```

## Dipendenze

```text
ERC20
oracle
eventuale swap venue
```

## Attori

```text
buyer
seller
oracle operators
admin/governance
block builders / ordering actors
external traders
```

## Input sensibili

```text
price
updatedAt
decimals
amountIn
amountOutMin
deadline
```

## Proprietà economiche

```text
price must be fresh
price must be positive
units must be consistent
execution must respect minOut
expired intent must fail
oracle failure must not silently become success
```

---

# 61. Checklist da auditor — Oracle

Quando vedi un prezzo, chiediti:

1. Da dove arriva?

2. Chi controlla la fonte?

3. L'indirizzo del feed è:
   - immutable?
   - upgradeabile?
   - configurabile da admin?

4. Quale pair rappresenta?

5. Quali decimals usa?

6. Il consumer verifica:
   - valore positivo;
   - timestamp;
   - freshness?

7. Quanto vale `maxAge` e perché?

8. Cosa accade se:
   - feed reverte;
   - feed non aggiorna;
   - valore è zero;
   - valore è negativo;
   - valore è estremo?

9. Esistono min/max o deviation checks?

10. Sono coerenti con la volatilità reale dell'asset?

11. Il prezzo è spot, TWAP o aggregato?

12. Se viene da un mercato on-chain:
    - quanta liquidità ha?
    - quanto costa muoverlo?
    - per quanto tempo?

13. Il consumer usa correttamente le unità?

14. Ci sono divisioni con rounding economicamente importante?

15. Una chiave admin può cambiare immediatamente il prezzo?

---

# 62. Checklist da auditor — Swap / Slippage / MEV

1. Esiste `amountOutMin`?

2. Può essere zero?

3. Chi lo calcola?

4. Deriva da una quote affidabile?

5. Esiste una deadline?

6. È ragionevolmente limitata?

7. La transazione dipende da uno stato di mercato che può cambiare prima dell'inclusione?

8. Un cambiamento di ordering può peggiorare il risultato?

9. Esistono controlli di price impact?

10. Il protocollo esegue swap senza bounds economici?

11. I bounds sono in unità corrette?

12. Decimals dei due token sono gestiti?

13. La funzione accetta qualsiasi router/DEX controllato dall'utente?

14. Il protocollo confonde:
    ```text
    "swap succeeded"
    ```
    con:
    ```text
    "swap succeeded at an acceptable price"
    ```

Questa ultima distinzione è fondamentale.

---

# 63. Esercizi

## Esercizio 1 — Unit analysis

Deriva a mano la formula per:

```text
TOKEN_A decimals = 8
oracle price decimals = 18
output TOKEN_B decimals = 6
```

Non scrivere Solidity finché non hai scritto le unità.

---

## Esercizio 2 — `maxAge`

Modifica il consumer affinché `maxAge == 0` sia vietato nel constructor.

Scrivi il test negativo.

---

## Esercizio 3 — Wrong decimals

Crea:

```text
oracle 8 decimals
```

ma scrivi volontariamente il consumer come se avesse:

```text
18 decimals
```

Costruisci un test che dimostri l'errore di fattore `1e10`.

Poi correggilo leggendo `decimals()`.

---

## Esercizio 4 — Circuit breaker

Aggiungi:

```text
minPrice
maxPrice
```

al consumer.

Testa:

```text
min - 1 -> revert
min     -> pass
max     -> pass
max + 1 -> revert
```

---

## Esercizio 5 — Freshness fuzzing

Scrivi un fuzz test con:

```solidity
function testFuzz_Freshness(
    uint256 age
)
```

e verifica la proprietà:

```text
age <= MAX_AGE
=> accettato

age > MAX_AGE
=> revert
```

Usa `bound()` per evitare timestamp impossibili.

---

## Esercizio 6 — Slippage

Con:

```text
expectedOut = 1000
slippage tolerance = 1%
```

calcola:

```text
amountOutMin
```

Poi prova:

```text
990
989
1000
1100
```

e stabilisci quali devono passare.

---

## Esercizio 7 — Deadline boundary

Testa:

```text
timestamp = deadline - 1
timestamp = deadline
timestamp = deadline + 1
```

Scrivi prima la proprietà in linguaggio naturale.

---

## Esercizio 8 — Audit challenge

Analizza:

```solidity
function buy(
    uint256 amountIn
) external {
    uint256 price =
        uint256(oracle.latestAnswer());

    uint256 minOut = 0;

    router.swap(
        amountIn,
        minOut
    );

    lastPrice = price;
}
```

Trova almeno:

```text
8 domande di sicurezza
```

prima di proporre una patch.

---

# 64. Cosa devi ricordare

## 1. Uno smart contract non conosce autonomamente il prezzo del mondo esterno

Serve un oracle o una sorgente on-chain.

---

## 2. L'oracle è una trust boundary

Il protocollo eredita le assunzioni della fonte.

---

## 3. Un dato può essere autentico ma inutile

Per esempio:

```text
stale
wrong pair
wrong decimals
economically anomalous
```

---

## 4. Le unità fanno parte della sicurezza

Annota sempre:

```text
asset
decimals
numeratore
denominatore
output unit
```

---

## 5. Il successo tecnico non implica correttezza economica

```text
swap succeeded
```

non significa:

```text
swap price acceptable
```

---

## 6. Slippage protection esprime un limite economico

```text
actualOut >= minOut
```

---

## 7. Deadline e minOut proteggono proprietà differenti

```text
deadline -> tempo
minOut   -> risultato economico
```

---

## 8. MEV rende l'ordering una variabile di threat modeling

Non assumere ingenuamente che la tua transazione venga eseguita contro lo stato che hai osservato prima di inviarla.

---

## 9. Price security è business logic security

Puoi avere codice memory-safe, access control corretto e nessuna reentrancy, ma perdere comunque le proprietà economiche a causa di un prezzo sbagliato.

---

# 65. Collegamento con il percorso

Le lezioni iniziano ora a comporsi:

```text
msg.sender / calldata / state
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
  ERC20 accounting
          |
          v
  ORACLE + PRICING
          |
          v
economic security
```

Dalla prossima lezione allargheremo ancora il confine:

```text
il nostro contratto non vive da solo
```

ma dipende da altri contratti, protocolli e assunzioni che possono cambiare.

---

# 66. Fonti della lezione

Fonti tecniche consultate il **21 settembre 2026**:

1. **ethereum.org — Maximal Extractable Value (MEV)**  
   Definizione di MEV, transaction inclusion/exclusion/ordering, generalized front-running, sandwich trading e impatti sull'esecuzione degli utenti.  
   https://ethereum.org/developers/docs/mev/

2. **Solidity Documentation — Units and Globally Available Variables**  
   Semantica di `block.timestamp`, `msg.*`, `tx.*` e avvertenze sulle proprietà del timestamp di blocco.  
   https://docs.soliditylang.org/en/latest/units-and-global-variables.html

3. **OpenZeppelin Contracts 5.x — Math**  
   `Math.mulDiv` e gestione di moltiplicazione/divisione con precisione estesa e rounding esplicito.  
   https://docs.openzeppelin.com/contracts/5.x/api/utils

4. **OWASP Smart Contract Security — SC03:2026 Price Oracle Manipulation**  
   Oracle come trust boundary, manipolazione di spot/TWAP, stale data, deviation/outlier handling e failure modes.  
   https://scs.owasp.org/sctop10/SC03-PriceOracleManipulation/

5. **OWASP Smart Contract Security — SCWE-028 Price Oracle Manipulation**  
   Validazione delle fonti, input validation e circuit breaker.  
   https://scs.owasp.org/SCWE/SCSVS-ORACLE/SCWE-028/

6. **OWASP Smart Contract Security — SCWE-085**  
   Rischi nella gestione di min/max price band e valori limite degli oracle.  
   https://scs.owasp.org/SCWE/SCSVS-ORACLE/SCWE-085/

7. **OWASP Smart Contract Security — SCWE-130**  
   Rischio di oracle con admin writer immediato, single-writer trust e mitigazioni governance/timelock/quorum.  
   https://scs.owasp.org/SCWE/SCSVS-ORACLE/SCWE-130/

8. **Chainlink Developer Documentation — Data Feeds**  
   Documentazione ufficiale da consultare per interfacce, feed address, decimals, metadata e raccomandazioni specifiche della rete/feed usati.  
   https://docs.chain.link/

---

# Fine Lezione 9

La progressione successiva sarà:

**Composability e dipendenze esterne: trust boundaries tra protocolli, failure propagation, token/router/oracle assumptions, dependency upgrades e defensive integration.**
