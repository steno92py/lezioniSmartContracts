# Lezione 3 — Escrow e macchina a stati

**Copione parlato.** Le parentesi quadre indicano cosa fare o mostrare. Prima di leggere le soluzioni, fai disegnare le transizioni alla classe. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/03-escrow-e-macchina-a-stati
```

Apri `src/EscrowStateMachine.sol` e `test/EscrowStateMachine.t.sol`. Tutti i comandi partono da questa cartella; sono facoltativi. I risultati possono essere ricostruiti senza terminale.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Storia dell'escrow e diagramma | 0–15 | 0–10 |
| Constructor, ruoli e modifier | 15–28 | 10–19 |
| Funding e approvazione | 28–43 | 19–29 |
| Freccia vietata e versione difettosa | 43–57 | 29–39 |
| Stati terminali e casi negativi | 57–71 | 39–49 |
| Approvazione e pagamento effettivo | 71–83 | 49–56 |
| Esercizio e chiusura | 83–90 | 56–60 |

## 1. Perché non basta che una funzione sia chiamata dal buyer?

«Un escrow custodisce fondi secondo condizioni concordate. Pensiamo a un buyer che deve pagare un seller. Prima si crea l'accordo, poi si deposita l'importo, poi si approva il rilascio.

Il buyer è autorizzato ad approvare, ma può approvare prima che il denaro sia stato depositato? No. Sapere chi chiama non basta: dobbiamo sapere in quale situazione si trova l'accordo.

Questa è l'idea della macchina a stati. Diamo un nome alle situazioni e definiamo quali passaggi sono permessi.»

[Disegna prima dei dettagli Solidity.]

```text
Created ── fund, buyer ──→ Funded ── approveRelease, buyer ──→ ReleaseApproved
   |
   └── cancelBeforeFunding, buyer ──→ Cancelled
```

«Created significa creato ma non finanziato. Funded significa che l'importo richiesto è stato depositato. ReleaseApproved significa che il buyer ha approvato il futuro pagamento. Cancelled significa che l'accordo è stato annullato prima del finanziamento.

In questa prima versione ReleaseApproved non esegue ancora il pagamento. È fondamentale: non attribuiamo al nome dello stato un trasferimento che il codice non fa.»

## 2. Le frecce assenti sono requisiti

«Quando disegniamo la macchina, non descriviamo solo il percorso felice. Ogni freccia assente è un'operazione da rifiutare.

Non vogliamo finanziare due volte. Non vogliamo approvare da Created. Non vogliamo cancellare dopo il deposito con una funzione pensata soltanto per la fase iniziale.»

[Chiedi di riempire la colonna finale.]

| Partenza | Richiesta | Risultato |
| --- | --- | --- |
| Created | fund corretto | Funded |
| Created | approveRelease | Rifiuto |
| Funded | fund di nuovo | Rifiuto |
| Funded | approveRelease | ReleaseApproved |
| Cancelled | fund | Rifiuto |

«Il diagramma ci permette di scrivere questi casi prima di conoscere la sintassi delle guardie. Questo è un requisito verificabile, non una decorazione nella documentazione.»

## 3. Leggere la configurazione iniziale

[Apri il constructor.]

«Il buyer è chi distribuisce questo contratto: nel costruttore leggiamo `msg.sender`. Seller e prezzo vengono passati come argomenti e poi fissati.

Il contratto rifiuta seller zero, buyer uguale al seller e prezzo zero. Sono regole di questo esercizio, non definizioni universali di ogni escrow.

`immutable` indica che buyer, seller e prezzo vengono fissati durante la costruzione. La variabile `state`, invece, cambia durante il ciclo di vita.»

[Mostra l'enum.]

«Un enum raccoglie un insieme finito di valori con nome. È più leggibile dire Funded che ricordare un numero. Ma l'enum, da solo, non impedisce passaggi sbagliati: qualunque funzione che scrive lo stato deve rispettare le regole.»

**Domanda:** «Dichiarare `State {Created, Funded, …}` impedisce automaticamente Created → ReleaseApproved?»

«No. Per impedire quella freccia serve un controllo prima dell'assegnazione.»

## 4. Due controlli separati: chi e quando

[Mostra `onlyBuyer` e `onlyState`.]

«Un modifier è un pezzo di codice riutilizzato intorno alla funzione. Qui esegue un controllo e poi, nel punto indicato da `_;`, lascia eseguire il corpo.

`onlyBuyer` risponde a chi. `onlyState` risponde a quando. Nessuno dei due sostituisce l'altro.»

```solidity
function fund() external payable onlyBuyer onlyState(State.Created)
```

«Questa firma dice: la funzione accetta una chiamata con ETH, deve provenire dal buyer e la macchina deve trovarsi in Created. Il corpo controlla poi che il valore sia esattamente il prezzo.

L'ordine dei modifier è anche l'ordine dei controlli: prima il caller, poi lo stato. Se una richiesta viola entrambi, sarà osservato il primo errore.»

[Leggi le poche righe di `fund`.]

«Quando tutti i controlli passano, scriviamo Funded ed emettiamo l'evento. Il denaro associato alla chiamata rimane nel contratto.»

```bash
bash demo.sh funding
```

**Risultato atteso:** due test PASS: buyer finanzia con il prezzo esatto; buyer può anche cancellare prima del funding. Sono test indipendenti: non è una cancellazione del deposito del primo test.

## 5. Essere autorizzati non significa poter saltare una fase

[Mostra `approveRelease`.]

«L'approvazione richiede buyer e stato Funded. Non riceve altro ETH: modifica lo stato dell'accordo già finanziato.

Facciamo due esperimenti mantenendo lo stesso caller. Nel primo il buyer deposita e poi approva: deve riuscire. Nel secondo approva subito: deve fallire.

Mantenere uguale il caller ci aiuta a isolare la proprietà sul momento della chiamata.»

```bash
bash demo.sh sequenza
```

**Risultato atteso:** due test PASS: approvazione dopo funding riuscita; approvazione prima del funding rifiutata con la guardia sullo stato.

**Domanda:** «Se togliamo onlyBuyer ma lasciamo onlyState, siamo protetti?»

«Abbiamo protetto l'ordine, ma chiunque potrebbe approvare dopo il deposito. Se togliamo onlyState e lasciamo onlyBuyer, abbiamo il problema opposto. Servono entrambi perché esprimono regole diverse.»

## 6. La versione difettosa: disegnare una freccia che non esiste

[Apri `src/labs/BadEscrowStateMachine.sol` e il test della variante difettosa.]

«Nel laboratorio difettoso l'approvazione può saltare il controllo necessario sullo stato. La prova parte da Created e arriva a ReleaseApproved senza funding.

Non abbiamo ancora spostato soldi verso un attaccante. Abbiamo dimostrato che lo stato dichiara una fase dell'accordo che non è stata preceduta dal deposito richiesto.»

[Disegna in un colore diverso.]

```text
Created ── approvazione senza funding ──→ ReleaseApproved
                  freccia vietata
```

```bash
bash demo.sh salto
```

**Risultato atteso:** un test PASS che dimostra la transizione illegale. Il verde conferma la riproduzione del difetto: leggi l'asserzione prima di interpretare il colore.

«Possiamo esprimere la proprietà così: se lo stato è ReleaseApproved, deve essere avvenuto un finanziamento valido. Il difetto rompe il significato dello stato, anche se il codice compila e il caller è il buyer.»

## 7. Terminalità e tentativi ripetuti

«Uno stato terminale non ammette ulteriori transizioni nel modello che abbiamo definito. Nella versione base Cancelled e ReleaseApproved sono terminali.

Terminale non significa che nessuno possa più chiamare una funzione dell'indirizzo. Significa che le operazioni che cambierebbero questa macchina devono essere rifiutate.»

```bash
bash demo.sh terminali
```

**Risultato atteso:** tre test PASS: funding da Cancelled rifiutato, nuova approvazione da ReleaseApproved rifiutata, secondo funding rifiutato.

[Chiedi di anticipare lo stato dopo ogni rifiuto.]

«Dopo un secondo tentativo fallito conserviamo lo stato precedente. Se ero Funded, resto Funded; non torno Created e non consumo altro denaro.»

```bash
bash demo.sh autorizzazione
```

**Risultato atteso:** tre test PASS: outsider non finanzia, seller non approva al posto del buyer, funding rifiutato senza effetti parziali.

«Qui controlliamo ruoli e atomicità. Il seller è interessato a ricevere il denaro, ma in questa specifica non può darsi da solo l'approvazione del buyer.»

## 8. Estendere la macchina: approvazione e pagamento sono due passi

[Apri `src/fixed/EscrowStateMachineFixed.sol`. Disegna solo l'estensione.]

```text
Funded → ReleaseApproved ── release, seller ──→ Released
```

«Nella variante con payout aggiungiamo un nuovo stato, Released. ReleaseApproved ora non è più terminale: permette al seller di incassare.

Questo è un buon esempio di evoluzione di una specifica. La stessa parola “terminale” dipende dalle transizioni disponibili nella versione considerata.

Il buyer approva; il seller chiama release. La funzione controlla entrambi i fatti, porta lo stato a Released e invia il prezzo al seller.»

**Domanda:** «Perché paga il prezzo e non tutto il saldo del contratto?»

«Il prezzo è il debito dell'accordo. Eventuali ETH aggiuntivi nel saldo non aumentano automaticamente il diritto del seller. Nelle prossime lezioni distingueremo sempre saldo effettivo e importo dovuto.»

```bash
bash demo.sh payout
```

**Risultato atteso:** tre test PASS: seller incassa dopo approvazione, release anticipata rifiutata, seller che rifiuta ETH provoca revert. Nell'ultimo caso lo stato torna ReleaseApproved e i fondi rimangono nel contratto: l'assegnazione anticipata a Released viene annullata.

«L'invio di ETH può eseguire codice del destinatario. Oggi prendiamo atto di questo confine. Nella lezione 4 lo apriremo e guarderemo receive, fallback ed esito della chiamata.»

## 9. Esercizio guidato e chiusura

**Consegna:** «Vogliamo aggiungere un rimborso dopo il funding. Basta scrivere `state = Cancelled`?»

[Lascia tre minuti per elencare le decisioni.]

**Soluzione ragionata:** «Prima decidiamo chi può chiederlo, da quale stato, con quale eventuale condizione temporale e a chi va il denaro. Poi definiamo uno stato finale che esprima il rimborso e controlliamo saldo e importo trasferito. Cambiare soltanto l'etichetta dello stato non restituisce i fondi.»

«La lezione di oggi è che una funzione deve essere corretta dentro una storia. Caller giusto, stato giusto e importo giusto sono condizioni diverse.

Abbiamo usato il diagramma per descrivere sia le azioni lecite sia quelle da rifiutare. Abbiamo anche distinto un'approvazione da un pagamento reale.

La prossima lezione studia proprio quel pagamento: quando trasferiamo ETH a un contratto, cediamo temporaneamente il controllo al suo codice.»

**Verifica orale:** l'enum impone le frecce? No. onlyBuyer impone l'ordine? No. ReleaseApproved è terminale in entrambe le versioni? No: nella variante con payout porta a Released.

**Percorso breve:** conserva diagramma, separazione ruolo/stato, salto vietato e differenza approvazione/payout. Le altre demo possono essere lette come casi sulla tabella. [Esercizi](exercises/README.md).

## Promemoria del docente

`bash demo.sh help` elenca le selezioni. Se una demo non parte, segui la freccia sul diagramma e leggi le asserzioni del test. Il contratto base trattiene ETH senza payout: è il limite didattico dichiarato, non una funzione da improvvisare durante la lezione. La 4 userà una policy diversa, con release chiamata dal buyer: segnalare quel cambio evita confusione sui ruoli.
