# Lezione 9 — Oracoli, prezzi, slippage e MEV

**Copione parlato con calcoli svolti.** Le parentesi quadre indicano cosa mostrare; le domande hanno una soluzione pronta. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/09-oracoli-prezzi-slippage-mev
```

Apri `src/PriceConsumer.sol`, `test/PriceConsumer.t.sol` e `test/SwapIntent.t.sol`. Le demo partono da questa cartella e usano mock: nessun mercato o asset reale.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Prezzo e significato | 0–12 | 0–8 |
| Segno, timestamp e confini | 12–28 | 8–19 |
| Derivazione delle unità | 28–46 | 19–32 |
| Minimo economico | 46–60 | 32–42 |
| Deadline e ordine di esecuzione | 60–76 | 42–53 |
| Limiti del modello, esercizio e chiusura | 76–90 | 53–60 |

## 1. Un numero non è ancora un prezzo utilizzabile

«Nella lezione 8 abbiamo visto che chiedere cento token non garantisce di riceverne cento. Oggi la dipendenza restituisce un prezzo. Anche qui dobbiamo interpretare il risultato.

Se scrivo 3000 sulla lavagna, che cosa sapete? Potrebbero essere dollari per ETH, unità con otto decimali oppure un prezzo di due giorni fa. Un numero da solo non basta.

Un oracle porta nel nostro sistema un'informazione esterna. Il consumer deve conoscere che cosa misura, in quale scala e quanto può essere vecchia. Il fatto che la chiamata risponda non certifica queste proprietà.»

[Mostra `src/VulnerableValuation.sol`.]

«La variante vulnerabile usa il valore grezzo e non gestisce correttamente il contesto. I primi due test ci mostrano due errori distinti: dato vecchio accettato e formula con unità sbagliate.»

```bash
bash demo.sh vulnerabile
```

**Risultato atteso:** due test PASS che dimostrano i difetti del consumer vulnerabile. Non stiamo dimostrando manipolazione di un feed reale: controlliamo un mock locale.

## 2. Leggere un prezzo significa applicare una policy

[Mostra `PriceConsumer.readPrice`.]

«Il consumer riceve `answer`, con segno, e `updatedAt`, il timestamp del dato.

Prima richiede un prezzo positivo. Poi esclude timestamp zero e futuro. Solo dopo calcola l'età e la confronta con `maxAge`.

L'ordine sul timestamp evita anche una sottrazione negativa: se sottraessimo prima un istante futuro da quello attuale, avremmo un underflow.»

[Scrivi un esempio con età massima di un'ora.]

| Dato | Decisione della policy |
| --- | --- |
| Prezzo zero o negativo | Rifiutare |
| Timestamp zero | Rifiutare |
| Timestamp futuro | Rifiutare |
| Età 3599 secondi | Accettare |
| Età 3600 secondi | Accettare |
| Età 3601 secondi | Rifiutare |

«Nella lezione 9 il confine è incluso: il codice rifiuta età maggiori del limite, non maggiori o uguali. È una decisione da trasformare in un test preciso.»

```bash
bash demo.sh dato
```

**Risultato atteso:** cinque test PASS: dato fresco positivo letto, negativo rifiutato, futuro rifiutato, stale rifiutato e confine esatto accettato. Gli altri controlli esistono nella suite ma non sono tutti in questa selezione.

**Domanda:** «Un dato fresco è necessariamente economicamente corretto?»

«No. La freshness dice quanto è vecchio il campione secondo il timestamp fornito. Non dimostra che la fonte sia onesta, che il mercato sia liquido o che il dato non sia manipolabile. Qui stiamo verificando la reazione del consumer alle risposte modellate.»

## 3. Le unità prima della formula

[Mostra `quote18To6`, ma prima svolgi il calcolo sulla lavagna.]

«Vogliamo convertire un importo dell'asset base con diciotto decimali in un controvalore con sei decimali.

Un'unità intera dell'asset base è rappresentata da `10^18`. Un prezzo di tremila, con otto decimali, è rappresentato da `3000 × 10^8`. Il risultato economico desiderato è tremila, ma espresso con sei decimali: `3000 × 10^6`.»

```text
amount18 = 1 × 10^18
price8   = 3000 × 10^8

Prodotto = 3000 × 10^26
Output richiesto = 3000 × 10^6
Denominatore necessario = 10^20
```

«La divisione per dieci alla ventesima non è un numero magico: corregge la scala accumulata dal prodotto.»

[Scrivi la formula generale, con P decimali del feed.]

```text
output6 = amount18 × priceP / 10^(18 + P − 6)
```

«Le unità economiche si cancellano così: quantità BASE per prezzo QUOTE/BASE produce QUOTE. Le potenze di dieci servono poi a rappresentare QUOTE nella scala scelta.

Se il feed usa diciotto decimali invece di otto, cambia il denominatore, non il valore economico finale.»

**Esercizio di due minuti:** «Due unità base a prezzo 1500, output a sei decimali: che numero aspettate?»

**Soluzione:** `3000 × 10^6`, indipendentemente dal fatto che il feed supportato esprima 1500 con otto o diciotto decimali.

## 4. Perché il prodotto intermedio conta

«Solidity usa interi di dimensione limitata. Il prodotto `amount × price` può essere troppo grande anche quando, dopo la divisione, il risultato starebbe nel tipo.

Il laboratorio usa `MulDivLite` per gestire un prodotto intermedio a precisione estesa. Non dobbiamo leggere tutto l'assembly per capire il requisito: calcolare la moltiplicazione e divisione senza un overflow intermedio evitabile, mantenendo una policy di arrotondamento esplicita.

Qui arrotondiamo per difetto. Se il risultato matematico ha una frazione dell'unità minima, la parte frazionaria viene scartata.»

```bash
bash demo.sh scala
```

**Risultato atteso:** tre test PASS: una unità base quotata correttamente con output a sei decimali; feed a otto e diciotto decimali economicamente equivalenti; prodotto intermedio grande gestito nel caso previsto.

«Questo non rende automaticamente sicuro qualsiasi intervallo di input. Il consumer limita i decimali supportati e il risultato deve comunque essere rappresentabile. La funzione matematica è una parte della validazione, non la specifica completa.»

## 5. Una quotazione osservata non è il risultato dell'esecuzione

[Apri `src/swap/SafeSwapIntent.sol` e `src/mocks/MockSwap.sol`.]

«Ora immaginiamo che l'utente osservi una quotazione di duecento unità in uscita. Fra la decisione e l'esecuzione le condizioni possono cambiare.

Per esprimere quanto peggioramento accetta, l'utente fornisce un output minimo. Con una tolleranza del cinque per cento su duecento, il minimo è centonovanta.»

```text
Output osservato: 200
Tolleranza: 5% = 10
Minimo accettato: 190

Output 195 → accettabile
Output 190 → accettabile
Output 189 → rifiutare
```

«Non chiediamo al contratto di eseguire a qualsiasi prezzo. Gli diamo una condizione verificabile. Nel mock il controllo del minimo è effettuato dallo swapper; il consumer gli passa il limite richiesto.»

```bash
bash demo.sh slippage
```

**Risultato atteso:** tre test PASS: output nel limite accettato, minimo esatto accettato, risultato sotto il minimo rifiutato.

**Domanda:** «Se fisso il minimo a zero, ho comunque una protezione?»

«Accetterei anche risultati quasi nulli. In questo consumer zero viene rifiutato proprio per evitare un limite privo di significato economico.»

## 6. La deadline risponde a una domanda diversa

«L'output minimo stabilisce quanto poco sono disposto a ricevere. La deadline stabilisce fino a quando la mia intenzione resta valida.

Un prezzo accettabile oggi non significa che io voglia eseguire la stessa operazione fra una settimana. E una deadline breve non impedisce un prezzo pessimo entro quel tempo. Servono condizioni separate.»

```text
amountOutMin → limite sul risultato
deadline     → limite sul momento dell'esecuzione
```

[Mostra il controllo in `SafeSwapIntent.execute`.]

«Qui l'istante esatto della deadline è ancora ammesso. Il codice rifiuta quando il timestamp corrente è maggiore.»

```bash
bash demo.sh deadline
```

**Risultato atteso:** tre test PASS: un secondo prima e istante esatto accettati; deadline superata rifiutata.

«Per provare questi casi usiamo `vm.warp` nel test. Non è un potere che il caller del contratto possiede sul tempo della rete.»

## 7. Ordine delle operazioni e MEV

«Il risultato economico può dipendere dall'ordine delle transazioni. Chi ha influenza sull'inclusione o sull'ordine può avere opportunità di estrarre valore: questo è il contesto del MEV.

Qui non simuleremo una rete, un mempool o un attacco su un AMM. Il nostro mock cambia semplicemente il rate fra il momento della quotazione osservata e l'esecuzione. Vogliamo isolare la conseguenza per l'utente.»

```text
Prima: output atteso 200
Prima dell'esecuzione: cambia il rate
Adesso: output effettivo 1
```

[Mostra `BadSwapConsumer` e il confronto nel test.]

«La versione vulnerabile usa minimo zero e accetta uno. La versione con limite centonovanta rifiuta lo stesso scenario sfavorevole.»

```bash
bash demo.sh ordine
```

**Risultato atteso:** due test PASS: consumer vulnerabile accetta output quasi nullo; consumer con intento vincolato rifiuta.

«Il limite contiene il peggior risultato accettato; non garantisce il miglior prezzo disponibile e non elimina tutte le forme di MEV. Anche il riferimento da cui l'utente calcola il minimo deve essere sensato.»

## 8. Cosa abbiamo modellato, cosa resta da decidere

«Un prezzo spot fotografa una situazione in un momento. Una media nel tempo, come un TWAP, aggrega osservazioni su una finestra. Sono scelte con proprietà diverse: una media può reagire più lentamente e la robustezza dipende anche dal mercato e dalla finestra.

Il laboratorio non implementa un TWAP né dimostra la sicurezza di un provider. Ci ha insegnato quali domande fare al consumer: unità, segno, tempo, fonte e comportamento quando il dato non è utilizzabile.

Se l'oracle non risponde, possiamo fermarci oppure usare un'alternativa progettata. Non possiamo prendere senza limiti un prezzo vecchio soltanto perché è l'ultimo disponibile.»

**Esercizio finale:** «Proponete due test distinti per un'operazione che ha sia minimo sia deadline.»

**Soluzione:** deadline ancora valida ma output sotto il minimo; output sufficiente ma deadline superata. In ciascuno l'altra condizione va preparata correttamente, per isolare la causa del rifiuto.

## 9. Chiusura

«Oggi abbiamo trattato il prezzo come un dato con unità e condizioni di validità. Abbiamo derivato la conversione prima di scriverla nel codice e distinto il limite economico da quello temporale.

La prossima lezione generalizza il metodo: per ogni dipendenza esterna dobbiamo sapere che cosa promette, che cosa verifichiamo noi e quale comportamento scegliamo se smette di rispettare le aspettative.»

**Percorso breve:** tabella freshness, calcolo di una unità base, minimo 190 e deadline. Il dettaglio di mulDiv resta un approfondimento. [Esercizi](exercises/README.md).

## Promemoria del docente

Il mock swap restituisce numeri: non muove token e non rappresenta riserve di un AMM. I test dimostrano le condizioni dell'intento nel modello locale. Se una demo non parte, svolgi i confronti numerici e indica la condizione che deve fallire. Non trasformare le tolleranze didattiche in consigli per operazioni reali.
