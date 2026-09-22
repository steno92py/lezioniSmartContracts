# Lezione 9 — Oracoli, prezzi, slippage e MEV

Questa lezione introduce la sicurezza economica: un dato può essere valido per l'EVM ma sbagliato
per il protocollo. Prezzo, timestamp, decimals, output minimo e deadline diventano parte della
specifica verificabile.

> Oracle e swapper sono mock locali. Non interagiscono con mercati, feed o asset reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_09_Oracoli_prezzi_slippage_MEV.md`](../../lezioni%20SmartContracts/Lezione_09_Oracoli_prezzi_slippage_MEV.md).

## Prima esecuzione

```bash
forge build --root lessons/09-oracoli-prezzi-slippage-mev
forge test --root lessons/09-oracoli-prezzi-slippage-mev -vv
```

I warning su `block.timestamp` sono attesi: in questo laboratorio viene usato consapevolmente per
freshness e deadline, non come fonte di prezzo o casualità. I warning su return ignorato e cast
signed/unsigned appartengono invece al consumer intenzionalmente vulnerabile.

## Mappa dei file

```text
src/VulnerableValuation.sol      prezzo grezzo, stale data e unità ignorate
src/PriceConsumer.sol            validazione semantica e conversione 18 -> 6
src/math/MulDivLite.sol          mulDiv didattico a precisione estesa
src/mocks/MockPriceOracle.sol    feed arbitrario esclusivamente locale
src/mocks/MockSwap.sol           rate variabile, senza riserve né token
src/swap/BadSwapConsumer.sol     amountOutMin fissato a zero
src/swap/SafeSwapIntent.sol      minOut e deadline espliciti
test/                            boundary, regressioni e ordering simulato
exercises/                       circuit breaker, fuzzing e policy multi-source
```

`MulDivLite` rende ispezionabile l'aritmetica 512-bit, ma non sostituisce una libreria consolidata.
In produzione va usata una versione pinnata e revisionata, con una rounding policy esplicita.

## Laboratorio oracle

```bash
forge test --match-contract PriceConsumerTest -vvvv
```

Il consumer corretto accetta soltanto un prezzo:

```text
positivo
timestamp != 0
timestamp <= block.timestamp
block.timestamp - timestamp <= maxAge
```

La conversione annota le unità:

```text
amount: BASE 1e18
price:  QUOTE/BASE 1eP
output: QUOTE 1e6
```

Per 1 ETH e 3.000 USD/ETH, feed a 8 o 18 decimals producono entrambi `3000e6`.

## Laboratorio slippage e ordering

```bash
forge test --match-contract SwapIntentTest -vvvv
```

Il mock separa due momenti:

```text
quotazione osservata: 200
rate cambia prima dell'esecuzione
output effettivo: 1
```

Il consumer vulnerabile accetta 1 perché usa `minOut = 0`; quello corretto reverte sotto 190. È una
simulazione difensiva del rischio di ordering, non un modello di AMM o una tecnica offensiva.

## Due bounds diversi

```text
amountOutMin  limita il peggior risultato economico
deadline      limita fino a quando l'intento resta valido
```

Uno non sostituisce l'altro. La slippage protection riduce il danno entro una soglia, ma non elimina
MEV né garantisce il miglior prezzo possibile.

## Tre percorsi

### Base — dati e unità

1. Verifica segno, timestamp e freshness.
2. Scrivi le scale prima di moltiplicare.
3. Testa i confini esatti, non soltanto valori molto lontani.

### Intermedio — intenzione economica

1. Distingui quote osservata ed execution effettiva.
2. Calcola `minOut` da una tolleranza dichiarata.
3. Verifica separatamente scadenza e output minimo.

### Avanzato — policy dell'oracle

1. Definisci il comportamento quando il feed non è disponibile.
2. Valuta circuit breaker, deviation check e fonte secondaria.
3. Modella controllo del feed, upgrade e liquidità della sorgente.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployOracleLab.s.sol:DeployOracleLab \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai spiegare perché un oracle è una trust boundary;
- sai verificare valore, timestamp e freshness;
- sai derivare una formula annotando tutte le unità;
- sai distinguere prezzo spot, TWAP e dato fresco;
- sai spiegare la differenza tra `minOut` e deadline;
- sai descrivere MEV e ordering come rischi progettuali.
