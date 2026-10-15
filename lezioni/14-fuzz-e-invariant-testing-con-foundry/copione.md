# Lezione 14 — Fuzz testing e invariant testing con Foundry

Copione da tenere aperto durante la lezione. **Il testo tra virgolette è da dire; le parentesi quadre indicano cosa mostrare o fare.** Le domande includono già la risposta per riprendere il discorso anche se nessuno interviene.

[Laboratorio e codice](README.md) · [Appunti di approfondimento](teoria.md)

Tieni aperti editor e terminale. Dalla radice del repository:

```bash
cd lezioni/14-fuzz-e-invariant-testing-con-foundry
```

Rimani in questa cartella per tutti i comandi della guida. Le demo sono facoltative: se il terminale non è pronto, leggi il test e ricostruisci i risultati riportati qui. Non installare strumenti durante la spiegazione.

## Come distribuire il tempo

I tempi includono lettura del codice, calcoli alla lavagna e risposte degli studenti: non sono minuti di monologo da riempire.

| Passaggio | 90 minuti | 60 minuti |
| --- | --- | --- |
| Apertura | 0–5 | 0–4 |
| Fee, primo fuzz test e forza delle proprietà | 5–20 | 4–14 |
| bound, assume e monotonia | 20–30 | 14–21 |
| Confini dell'oracle | 30–37 | 21–26 |
| Contabilità del vault alla lavagna | 37–49 | 26–35 |
| Handler e azione avversaria | 49–64 | 35–46 |
| Ghost variables, campagna e donazione | 64–76 | 46–53 |
| Stati terminali | 76–82 | Solo spiegazione, 53–55 |
| Regressione e chiusura | 82–90 | 55–60 |

## 1. Apertura: perché questa lezione viene dopo la 13

«Nella scorsa lezione abbiamo lavorato su come scrivere un test che controlli davvero il comportamento del contratto.

Preparavamo una situazione, eseguivamo un'operazione e verificavamo il risultato. Per esempio: Alice deposita cento, quindi il suo credito deve diventare cento.

Oggi partiamo da una domanda: perché proprio cento?

Il contratto potrebbe funzionare con cento e rompersi con uno, con un importo molto grande o dopo diversi prelievi. Non possiamo scrivere a mano un test per ogni numero e per ogni possibile sequenza di operazioni.

Possiamo però scrivere una regola che deve rimanere vera e chiedere a Foundry di cercare un caso che la viola.

Faremo due passaggi. Prima varieremo i numeri dentro uno scenario che abbiamo scritto noi: questo è il fuzz testing. Poi faremo variare anche l'ordine delle operazioni: questo è l'invariant testing.»

[Scrivi queste tre righe.]

```text
Test deterministico: scelgo lo scenario e i valori.
Fuzz test: scelgo lo scenario; Foundry genera i valori.
Invariant test: definisco azioni e proprietà; Foundry genera sequenze.
```

«La cosa fondamentale è questa: Foundry può scegliere gli input. Siamo ancora noi a dovergli dire che cosa significa risultato corretto.»

## 2. Il primo fuzz test: una commissione

[Apri `src/fuzz/FuzzTargets.sol`, contratto `FeeCalculator`. Mostra soltanto `fee`.]

«Partiamo da questa funzione. Riceve un importo e una commissione espressa in basis point.

Diecimila basis point corrispondono al cento per cento. Cento basis point corrispondono all'uno per cento. Nel nostro contratto il massimo è mille, quindi il dieci per cento.»

[Scrivi.]

```text
Importo: 200
Commissione: 500 bps = 5%
Fee: 200 × 500 / 10.000 = 10
```

«Un test deterministico può controllare che, con questi numeri, il risultato sia dieci.

Un fuzz test ci permette di fare un'affermazione più generale: per gli importi e le commissioni ammessi, la commissione calcolata non deve superare l'importo di partenza.

Questa è una proprietà. Non sto indicando un singolo risultato: sto descrivendo una relazione che deve valere per tanti risultati.»

[Apri `test/fuzz/FeeMathFuzz.t.sol`, funzione `testFuzz_FeeNeverExceedsAmount`.]

«Leggiamo il test dall'inizio. La funzione riceve due parametri: `rawAmount` e `rawFeeBps`. I valori li fornisce Foundry.

Poi troviamo `bound`. Fermiamoci qui, perché questo passaggio è importante.»

```solidity
uint256 amount = bound(rawAmount, 0, type(uint128).max);
uint256 feeBps = bound(rawFeeBps, 0, calculator.MAX_FEE_BPS());
```

«`bound` riconduce il valore generato a un intervallo.

Per la commissione scegliamo da zero a mille: stiamo verificando il comportamento nel dominio ammesso.

Per l'importo scegliamo un intervallo che evita l'overflow della moltiplicazione. In questo test vogliamo studiare la relazione matematica fra commissione e importo. Il comportamento fuori da questo dominio richiede altre prove.

Quindi attenzione: stiamo dicendo “questa proprietà vale per gli input provati in questo intervallo”. Non stiamo dicendo “abbiamo verificato tutti i possibili uint256”.»

[Indica le ultime due righe.]

```solidity
uint256 result = calculator.fee(amount, feeBps);
assertLe(result, amount);
```

«Qui eseguiamo la funzione. Poi `assertLe` controlla che il primo valore sia minore o uguale al secondo.

La struttura rimane quella della lezione 13: preparazione, azione, controllo. La novità è che Foundry ripete lo scenario con valori diversi. Ogni caso riparte dallo stato preparato dal setup: gli input di un fuzz test non costituiscono automaticamente una storia di depositi accumulati.»

**Domanda:** «Se sostituissi il calcolo della commissione con `return 0`, questo test passerebbe?»

[Aspetta qualche secondo.]

«Sì. Zero non supera mai l'importo. Questo ci fa vedere una cosa importante: una proprietà può essere vera e, da sola, insufficiente.

Per questo servono anche esempi con risultati precisi e altre proprietà. Fare tanti tentativi non rende automaticamente forte un controllo debole.»

## 3. bound, assume e monotonia

«Abbiamo usato `bound` per trasformare un numero e portarlo nel dominio che ci interessa.

Un altro strumento è `vm.assume`. Funziona diversamente: se la condizione non è soddisfatta, quel caso viene scartato.

Per esempio, se voglio verificare che un estraneo non possa depositare, posso escludere il buyer.»

```solidity
vm.assume(caller != buyer);
```

«Sto dicendo: questa proprietà riguarda chi non è il buyer.

Ma se genero un numero enorme e poi accetto soltanto quelli fra uno e cento, rischio di scartare quasi tutti i tentativi. Per un intervallo numerico, `bound` è spesso più utile.»

[Mostra `testFuzz_FeeIsMonotonicInAmount`.]

«Qui controlliamo un'altra proprietà: mantenendo la stessa percentuale, aumentando l'importo la commissione non deve diminuire.

Questa proprietà si chiama monotonia. Vediamola con numeri semplici.»

```text
Stessa commissione: 5%
Importo 100 → fee 5
Importo 200 → fee 10
```

«Foundry genera due numeri. Il test li ordina: il più piccolo va in `x`, il più grande in `y`.

Non ci interessa quale dei due sia stato generato per primo. Ci interessa confrontare piccolo e grande.»

```solidity
if (x > y) (x, y) = (y, x);
```

«Poi controlliamo che la commissione sul piccolo non superi quella sul grande.

Usiamo minore o uguale perché Solidity fa divisioni intere: due importi vicini possono produrre la stessa commissione arrotondata.»

[Demo facoltativa.]

```bash
bash demo.sh dominio
```

**Risultato da leggere:** due fuzz test PASS, con 256 run per test nella configurazione default. Non leggere tutti gli indirizzi della trace: torna ai nomi dei test e alle asserzioni.

«Qui vengono eseguite due proprietà: la commissione non supera l'importo e non diminuisce quando l'importo aumenta. Il PASS significa che non è stato trovato un controesempio nei tentativi effettuati. Anche una fee sempre zero passerebbe entrambe: i risultati esatti restano importanti.»

**Raccordo:** «Ci sono valori che vogliamo verificare con certezza, senza aspettare che vengano generati.»

## 4. Perché i test sui confini restano

[Apri `test/fuzz/OracleFuzz.t.sol`.]

«Immaginiamo di accettare prezzi vecchi al massimo un'ora. Dobbiamo chiarire cosa succede esattamente a un'ora.»

```text
Età del prezzo:
3.599 secondi → valido
3.600 secondi → valido, secondo questa specifica
3.601 secondi → scaduto
```

«La differenza fra maggiore e maggiore o uguale è un solo carattere nel codice, ma cambia una decisione del contratto.

Nel laboratorio della 14, il confine esatto è accettato. Per questo c'è un test deterministico che imposta proprio quel timestamp.

Ci sono anche due casi espliciti: prezzo zero e timestamp nel futuro. Entrambi devono essere rifiutati.

I fuzz test esplorano molti valori. I test deterministici fissano i casi che abbiamo deciso di voler controllare sempre.»

```bash
bash demo.sh confini
```

**Risultato:** tre test PASS: confine accettato, futuro rifiutato, zero rifiutato. Il revert atteso fa parte del successo dei due test negativi.

**Domanda:** «Se aumento da 256 a diecimila tentativi, posso cancellare il test sul confine?»

«No. Il test sul confine documenta una decisione precisa della specifica e la verifica direttamente.»

**Raccordo:** «Finora abbiamo variato i numeri. Ora vogliamo verificare che i conti tornino dopo molte operazioni, anche in ordini diversi.»

## 5. Prima dell'invariant: facciamo i conti a mano

[Apri `src/invariant/CreditVault.sol`.]

«Questo contratto è una cassa comune. Ogni utente può depositare token e prelevare fino al proprio credito.

Ci sono tre cose diverse da osservare: i token realmente presenti nel vault; il credito registrato per ciascun utente; `totalCredit`, cioè il totale che il vault deve agli utenti.

Se Alice deposita dieci e Bob deposita cinque, il vault deve avere quindici token e deve complessivamente quindici agli utenti.»

[Costruisci la tabella una riga alla volta. Fai calcolare alla classe l'ultima.]

| Operazione | Credito Alice | Credito Bob | Credito totale | Token nel vault |
| --- | ---: | ---: | ---: | ---: |
| Inizio | 0 | 0 | 0 | 0 |
| Alice deposita 10 | 10 | 0 | 10 | 10 |
| Bob deposita 5 | 10 | 5 | 15 | 15 |
| Alice preleva 4 | 6 | 5 | 11 | 11 |

«Gli importi cambiano. La relazione resta.»

```text
token nel vault = credito totale = somma dei crediti degli utenti
```

«Questa è la nostra invariante. Un'invariante non è una variabile che non cambia. È una proprietà che deve restare vera mentre lo stato cambia.»

**Domanda:** «Se nel prelievo aggiorno il credito di Alice, trasferisco i token, ma dimentico di diminuire `totalCredit`, che cosa succede?»

[Mostra la riga sbagliata. Questo è un ragionamento su una modifica ipotetica, non una modifica da fare in diretta.]

```text
Credito Alice: 6
Credito Bob:   5
Credito totale registrato: 15
Token nel vault:           11
```

«Il contratto dichiara di dovere quindici, ma i token sono undici e i crediti individuali sommano undici. Abbiamo tre letture che non coincidono più.

Non dobbiamo prevedere ogni possibile sequenza che arriva a questa situazione. Possiamo chiedere a Foundry di generare operazioni e controllare continuamente questa relazione.»

## 6. L'handler: come rendiamo utili le operazioni generate

[Apri `test/invariant/handlers/VaultHandler.sol`.]

«Foundry deve sapere quali operazioni può provare e come costruirle.

Se chiamasse `deposit` con un indirizzo qualsiasi, quell'indirizzo potrebbe non avere token e non aver dato l'approvazione. Otterremmo tanti fallimenti senza esplorare la contabilità.

Per questo usiamo un handler: un contratto di supporto del test che prepara ed esegue le azioni.»

```text
Foundry sceglie azione e parametri
             ↓
Handler sceglie utente e importo
             ↓
Vault esegue deposito o prelievo
             ↓
Il test controlla le proprietà
```

«Nel nostro modello ci sono Alice, Bob e Carol. Nel costruttore dell'handler ricevono token e approvano il vault.

Guardiamo soltanto `deposit`, una riga alla volta.»

[Indica `_actor(actorSeed)`.]

«Il primo parametro serve a scegliere uno dei tre utenti.»

[Indica `bound`.]

«Il secondo viene trasformato in un importo positivo, entro il limite previsto.»

[Indica `vm.prank(selectedActor)`.]

«Questa istruzione fa sì che la prossima chiamata al vault provenga dall'utente scelto.

È importante distinguere i due caller: Foundry chiama l'handler, ma il vault vede Alice, Bob o Carol.»

[Indica `vault.deposit(amount)`.]

«Qui avviene il deposito vero.»

[Indica `ghostDeposited += amount`.]

«Solo dopo che il deposito è riuscito, il test annota quanto è stato depositato. Tra poco vediamo perché.»

[Passa a `withdraw`.]

«Per il prelievo leggiamo il credito dell'utente. Se è zero, non esiste un prelievo valido: l'handler registra un'azione senza effetto e termina.

Se il credito è positivo, sceglie un importo fra uno e quel credito.

In questo modo riusciamo a esplorare sequenze di operazioni valide.»

**Domanda:** «Ma così non stiamo evitando tutti i tentativi vietati?»

«Per questo c'è una terza azione: `withdrawTooMuch`.

Questa chiede deliberatamente più del credito disponibile. Si aspetta l'errore preciso e controlla che credito individuale, totale e saldo restino invariati.

Le azioni valide servono ad arrivare a stati interessanti. L'azione avversaria verifica che il contratto rifiuti una richiesta vietata.»

[Apri `test/invariant/CreditVaultInvariant.t.sol`, dentro `setUp`.]

«Qui registriamo l'handler con `targetContract` e scegliamo le tre azioni con `targetSelector`.

Questo è il mondo che Foundry può esplorare in questa campagna. Se un'azione non è inclusa, non possiamo sostenere di averla verificata con queste sequenze.»

**Se chiedono dei revert:** nel `foundry.toml` locale `fail_on_revert = true`. Un revert inatteso che emerge dall'handler fa fallire la campagna; quello dichiarato con `vm.expectRevert` nell'azione avversaria viene invece verificato e gestito dal test.

## 7. Ghost variables: un registro separato per controllare i conti

«Torniamo a `ghostDeposited` e `ghostWithdrawn`.

Il nome può sembrare strano, ma l'idea è semplice: sono il quaderno del test.

Il protocollo mantiene la propria contabilità. Il test annota gli importi dei depositi e dei prelievi riusciti. Poi confrontiamo i due registri.»

```text
Depositi annotati dal test − prelievi annotati dal test
                         =
                credito totale del vault
```

«Se il contratto dimentica un aggiornamento, il quaderno del test può accorgersene.

Ma attenzione: se facessi semplicemente `ghostTotal = vault.totalCredit()`, copierei il numero che voglio verificare. Non avrei un controllo indipendente.»

[Mostra le quattro funzioni `invariant_` nel file.]

«La prima confronta token effettivi e credito totale.

La seconda confronta depositi netti annotati dal test e credito totale.

La terza somma i crediti di Alice, Bob e Carol e li confronta con il totale.

La quarta controlla che i token complessivi degli utenti e del vault si conservino. Nel nostro modello si spostano, ma non vengono creati o distrutti durante le azioni.»

```bash
bash demo.sh vault
```

**Risultato:** campagna PASS con quattro proprietà. La versione locale di Forge aggrega la campagna nel riepilogo: numero di test, numero di proprietà e numero di chiamate non sono la stessa cosa.

«La configurazione locale prevede 128 sequenze, con profondità 64. La profondità indica quante chiamate vengono generate per una sequenza: non significa che ogni chiamata produca un cambiamento utile.

Per leggere il risultato non basta cercare il verde. Dobbiamo anche chiederci se depositi e prelievi siano stati esercitati e quanto spesso l'handler non abbia fatto nulla.»

### Esercizio breve, con soluzione

«Alice trasferisce direttamente cinque token al vault, senza chiamare `deposit`. Che cosa cambia?»

[Aspetta e fai distinguere saldo e credito.]

«Aumenta il saldo. Il credito resta uguale.

Quindi l'uguaglianza fra saldo e credito non vale più. Se vogliamo includere donazioni nel modello, la proprietà di solvibilità diventa:»

```text
token nel vault >= credito totale
```

«Non abbiamo scoperto automaticamente un bug nel contratto: abbiamo cambiato le azioni possibili e dobbiamo riesaminare la proprietà.»

[Se serve, apri `MODEL.md`: il modello corrente esclude donazioni, fee, rebase e callback del token. La somma dei crediti dei tre actor funziona perché sono gli unici depositanti modellati.]

## 8. Ricordare il passato: gli stati terminali

[Apri `test/invariant/handlers/LifecycleHandler.sol` e poi `test/invariant/LifecycleInvariant.t.sol`.]

«Finora abbiamo confrontato numeri presenti nello stato attuale.

Alcune proprietà richiedono anche di ricordare cosa è successo prima. Per esempio: una volta chiuso, un escrow non deve riaprirsi.»

```text
Created → Funded → Released
                 ↘ Refunded
```

«Se ora vedo `Funded`, non posso sapere dal solo stato attuale se il contratto sia appena stato finanziato oppure se fosse già stato chiuso e poi riaperto per errore.

Per questo l'handler conserva `ghostTerminalSeen`. Diventa vero quando raggiungiamo uno stato terminale.

Da quel momento, l'invariante richiede che lo stato continui a essere terminale.»

**Precisazione da dire**

«C'è però un limite importante: questo handler evita molte chiamate non valide. Per esempio, non prova a finanziare di nuovo un escrow già chiuso.

Quindi questa campagna, da sola, non verifica tutti i tentativi di riapertura. In `test/fuzz/LifecycleNegativeFuzz.t.sol` c'è anche un test negativo dedicato, `testFuzz_TerminalStateCannotBeFundedAgain`, che prova proprio quella chiamata.

Ancora una volta dobbiamo guardare sia la proprietà sia le azioni che il test esegue davvero.»

```bash
bash demo.sh stato-terminale
```

**Risultato:** campagna PASS con tre proprietà: memoria della terminalità, importo zero negli stati terminali, coerenza stato/importo negli altri stati. Molte azioni diventano no-op dopo la chiusura: più profondità non significa automaticamente più stati interessanti.

## 9. Quando troviamo un problema: dalla sequenza alla regressione

[Apri `test/regression/InvariantDiscoveryRegression.t.sol`.]

«Quando una campagna trova un problema, ci interessa la sequenza che lo ha prodotto.

Non basta rilanciare il comando e sperare che non succeda più. Dobbiamo capire quali passaggi sono necessari, ridurre il caso e conservarlo come test leggibile.

Qui abbiamo un esempio deterministico di sequenza multiutente. Non lo presentiamo come una scoperta avvenuta oggi: serve a mostrare la forma del test da conservare.»

[Leggi e fai calcolare i saldi.]

```text
Alice deposita 17.
Alice preleva 16.
Bob deposita 2.
Alice preleva l'ultimo 1.
```

«Alla fine Alice ha credito zero. Bob ha credito due. Il totale è due e nel vault devono esserci due token.

Il test scrive esplicitamente questi quattro controlli.

Un secondo caso deposita diciassette e prova a prelevare diciotto: deve fallire e lasciare tutti i conti invariati.»

```bash
bash demo.sh regressione
```

**Risultato:** due test PASS. Nel codice `17 ether` indica `17 × 10^18` unità del token del laboratorio: non stiamo inviando ETH.

«La campagna generativa continua a cercare altri casi. La regressione conserva un caso preciso, facile da leggere e riprodurre.»

**Se chiedono shrinking e seed:** «Lo shrinking cerca di ridurre il controesempio mantenendo il fallimento. Non promette la sequenza minima assoluta. Conserviamo output, seed se disponibile, versione e configurazione; poi scriviamo la regressione esplicita.»

## 10. Chiusura pronta da leggere

«Oggi abbiamo aggiunto due strumenti al metodo della scorsa lezione.

Con il fuzz testing manteniamo uno scenario e facciamo variare gli input.

Con l'invariant testing facciamo variare anche le sequenze di azioni e controlliamo proprietà che devono continuare a valere.

In entrambi i casi il lavoro decisivo resta nostro: scegliere il dominio, scrivere una proprietà utile e costruire un modello che raggiunga situazioni interessanti.

Se una proprietà è debole, ripeterla diecimila volte non la rende sufficiente. Se l'handler non prova un'azione, la campagna non ci dà evidenza su quell'azione.

Quando troviamo un controesempio, lo comprendiamo e lo trasformiamo in una regressione.

Nella prossima lezione aggiungeremo Slither: uno strumento che analizza il codice e ci segnala punti da investigare. Useremo quello che sappiamo sui test per distinguere un sospetto da un problema dimostrato.»

### Ultime tre domande alla classe

| Domanda | Risposta |
| --- | --- |
| Chi decide che cosa è corretto? | Noi, attraverso specifica e asserzioni. |
| Un'invariante significa che lo stato non cambia? | No, che una proprietà resta vera mentre cambia. |
| Una campagna verde dimostra che il contratto è sicuro? | Non abbiamo trovato violazioni delle proprietà controllate nelle sequenze esplorate. |

**Se hai poco tempo:** fai bene commissione, tabella del vault e handler. Salta la demo sugli stati terminali; chiudi comunque con regressione e limiti del modello.

**Compito:** partendo dalla tabella del vault, aggiungere una donazione di cinque token. Scrivere quali uguaglianze restano vere e quale deve cambiare, poi proporre l'azione da aggiungere all'handler. Soluzione: saldo maggiore del credito; somma dei crediti e depositi netti restano uguali a `totalCredit`; la conservazione richiede di includere il donatore se esterno agli actor. Altre tracce negli [esercizi](exercises/README.md).

## Promemoria operativo del docente

La suite ordinaria si richiama con `bash demo.sh check`; le demo disponibili con `bash demo.sh help`. La configurazione del repository usa 256 run fuzz e invariant da 128 run con depth 64. Il profilo `deep` è per lavoro fuori dall'aula.

Se una demo non parte, prosegui con il file e i numeri già presenti nel copione. Non descrivere un errore inatteso come il risultato previsto. Se il filtro seleziona zero test, non è una verifica riuscita. Queste demo usano Forge locale: non servono wallet, chiavi, RPC o Anvil.
