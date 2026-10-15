# Lezione 16 — Metodologia di audit completa

Copione per condurre un mini audit guidato. **Il testo tra virgolette è da dire; le parentesi quadre indicano cosa mostrare o far fare.** Le soluzioni sono incluse: prima dai agli studenti il tempo di formulare un'ipotesi, poi leggile insieme a loro.

[Laboratorio](README.md) · [Appunti di approfondimento](teoria.md)

Dalla radice del repository:

```bash
cd lezioni/16-metodologia-di-audit-completa
```

Rimani qui per tutti i comandi. Tieni aperti `audit/scope.md`, `src/target/AuditEscrow.sol` e `audit/tests/AuditEscrowFindings.t.sol`. Le demo sono facoltative; ogni risultato viene spiegato nel copione. Il target vulnerabile resta invariato: la versione corretta è in `src/fixed/RemediatedEscrow.sol`.

## Come distribuire il tempo

Questa è una conduzione guidata, non un audit professionale completo da finire in novanta minuti. Il lavoro autonomo consiste nel produrre un finding e la sua motivazione senza copiare il report.

| Passaggio | 90 minuti | 60 minuti |
| --- | --- | --- |
| Apertura e scope | 0–12 | 0–8 |
| Architettura, proprietà e baseline | 12–25 | 8–17 |
| Ipotesi e accounting | 25–39 | 17–27 |
| Reentrancy: sequenza e prerequisiti | 39–52 | 27–37 |
| Governance, freshness e notifier | 52–64 | 37–45 |
| Scrivere un finding e motivare severity | 64–75 | 45–51 |
| Review della patch e retest | 75–85 | 51–57 |
| Report e chiusura | 85–90 | 57–60 |

## 1. Apertura: che cosa consegna un audit?

«Nella lezione 15 abbiamo preso alcune segnalazioni e verificato quali corrispondevano a un problema. Oggi organizziamo quel lavoro dall'inizio alla fine.

Immaginate che qualcuno vi consegni questo escrow e vi chieda di revisionarlo. A fine lavoro dovete poter spiegare quale codice avete esaminato, quali regole avrebbe dovuto rispettare, quali problemi avete trovato e quali prove sostenete.

Non basta dire “ho letto tutto”. E non basta consegnare l'output di uno strumento. Un'altra persona deve poter ripercorrere il ragionamento e riprodurre i problemi.

Il nostro percorso sarà questo.»

```text
Scope → modello del sistema → proprietà → ipotesi
      → prove → finding → correzione → retest → report
```

«I documenti nella cartella `audit` servono a conservare queste decisioni. Non li leggeremo tutti in ordine come un elenco: costruiremo un caso completo e useremo i documenti per registrarlo.»

## 2. Scope: stabilire che cosa stiamo revisionando

[Apri `audit/scope.md`.]

«Scope significa perimetro del lavoro. Qui il target è `AuditEscrow`, insieme alle interfacce e ai comportamenti d'integrazione previsti.

Token, oracle e notifier sono dipendenze esterne. Nei test useremo mock che ne riproducono alcuni comportamenti. Questo ci permette di verificare la reazione dell'escrow; non equivale ad aver auditato un provider oracle reale.

Proxy, upgrade, chiavi e frontend sono fuori da questo esercizio. Li dichiariamo perché chi legge non deve attribuirci una verifica che non abbiamo fatto.»

**Nota per il docente:** il documento `scope.md` contiene una nota storica sull'assenza di un commit al momento della sua stesura; non descriverla come lo stato attuale del repository. Anche il report conserva quel riferimento storico. Per la lezione usa questa distinzione esplicita:

«Nel dossier trovate una nota relativa allo snapshot usato nella stesura originale. Per una nuova review, l'identificazione va aggiornata: commit e modifiche locali effettivamente esaminate. Un hash non identifica da solo le modifiche non committate.

Questo è già un controllo di audit: i metadati devono descrivere il codice che stiamo davvero guardando.»

[Mostra le assunzioni del file. Evidenzia queste cinque regole.]

| Regola del laboratorio 16 | Conseguenza per la review |
| --- | --- |
| Solo token exact-transfer; fee token da rifiutare | Un deposito tassato deve essere annullato |
| Prezzo positivo e almeno pari alla soglia | Il solo timestamp recente non basta |
| Età strettamente minore di `maxAge` | Al confine esatto il prezzo è già scaduto |
| Solo governance cambia oracle | Il guardian non può farlo |
| Notifier opzionale e best-effort | Il suo normale revert non deve bloccare il settlement |

«Queste regole vengono prima della ricerca dei bug. Se non sappiamo quale comportamento è richiesto, rischiamo di chiamare vulnerabilità una scelta lecita oppure di accettare una violazione.»

**Domanda:** «Nella 14 accettavamo il prezzo vecchio esattamente un'ora. Perché qui no?»

«Perché questo laboratorio ha una specifica diversa: qui l'età deve essere strettamente minore del limite. Un confronto non è giusto in assoluto: deve implementare la regola concordata.»

## 3. Disegniamo il sistema e scegliamo le proprietà

[Apri `audit/architecture.md`. Disegna una versione ridotta.]

```text
Buyer → deposita token → Escrow → paga → Seller
                           |
                           +→ legge prezzo e timestamp dall'oracle
                           +→ invia una notifica al notifier

Governance → cambia oracle, pausa e riattiva
Guardian   → può mettere in pausa
```

«L'asset più evidente sono i token. Ma dobbiamo proteggere anche il diritto a riceverli, lo stato dell'escrow e il potere di cambiare l'oracle.

Nel codice `liability` è quanto l'escrow deve ancora pagare. Se registra cento, deve poter onorare cento.

In questo laboratorio `release` può essere chiamata da chiunque. L'autorizzazione economica viene dalle condizioni sul prezzo e dallo stato del contratto. Quindi non segnaliamo automaticamente come bug l'assenza di `onlyBuyer` su quella funzione.»

[Scrivi tre proprietà in italiano prima di mostrare `audit/invariants.md`.]

```text
1. I token disponibili coprono il debito registrato.
2. Lo stesso debito non può essere pagato due volte.
3. Soltanto governance può sostituire l'oracle.
```

«Ora sappiamo che cosa osservare. La prima proprietà si controlla confrontando saldo e debito. La seconda richiede di osservare quanti token riceve il seller, anche durante una callback. La terza richiede di provare i ruoli separatamente.»

### La baseline

[Apri `test_Baseline_HappyPathWorks` in `audit/tests/AuditEscrowFindings.t.sol`.]

«Prima di introdurre dipendenze avversarie, verifichiamo il percorso normale: token standard, prezzo valido, deposito cento e release da un caller generico.

Ci aspettiamo seller con cento, debito zero, stato Released e una notifica. Questa è la baseline: ci serve a riconoscere se un esperimento successivo fallisce per la causa che stiamo studiando oppure per un setup sbagliato.»

```bash
bash demo.sh baseline
```

**Risultato atteso:** un test PASS con quei quattro risultati. La baseline dimostra che il flusso normale del target funziona nello scenario; non cancella le vulnerabilità degli altri scenari.

## 4. Da una riga di codice a un'ipotesi verificabile

[Apri `src/target/AuditEscrow.sol`, funzione `deposit`. Fermati su `liability = amount`.]

«Il contratto chiede un trasferimento di `amount` e poi registra quello stesso importo come debito.

L'osservazione è: salva il valore richiesto. L'ipotesi è: se arriva meno di quanto richiesto, il debito supera gli asset.

Dobbiamo ora scegliere un comportamento del token che renda verificabile la differenza.»

[Lascia due minuti per proporre importo, fee e risultato. Poi svolgi.]

```text
Richiesto al buyer: 100
Fee sul trasferimento: 10%
Ricevuto dall'escrow: 90
Debito registrato dal target: 100
Differenza non coperta: 10
```

«La proprietà violata è saldo maggiore o uguale al debito. Novanta è minore di cento.

Qui dobbiamo essere precisi sull'impatto. Il test dimostra un debito senza copertura e il fallimento del payout da cento. Non mostra un attaccante che ruba cento: quella sarebbe un'altra affermazione.»

[Apri `test_AUD02_FeeTokenCreatesInsolventNominalLiability`.]

«Il test controlla prima i numeri: liability cento, saldo novanta. Poi tenta `release` e si aspetta l'errore di saldo insufficiente del token. Colleghiamo così il difetto contabile a una conseguenza operativa.»

**Domanda:** «Ma se i fee token sono fuori policy, possiamo ignorare il caso?»

«La specifica richiede che siano rifiutati atomicamente. Qui vengono accettati e creano debito. “Non supportato” deve tradursi nel comportamento richiesto: non basta scriverlo negli appunti.»

**Raccordo:** «Il secondo problema non nasce da quanto entra, ma da quante volte può essere pagato lo stesso debito.»

## 5. Reentrancy: raccontare la sequenza e dichiarare la riserva

[Apri `release`. Indica che trasferimento e notifica precedono `liability = 0` e `state = Released`.]

«Il contratto trasferisce il controllo all'esterno mentre nello storage risulta ancora Funded con un debito da pagare.

Se il token richiama `release` durante il trasferimento, la seconda esecuzione può vedere lo stesso debito della prima.»

[Costruisci questa sequenza alla lavagna.]

```text
Stato iniziale: Funded, liability 100, saldo 200
1. Prima release legge liability 100.
2. Chiama token.transfer(seller, 100).
3. Durante il trasferimento il token richiama release.
4. La seconda release vede ancora Funded e liability 100.
5. Esegue un secondo payout di 100.
6. Le esecuzioni chiudono infine lo stato.
Risultato: seller riceve 200 a fronte di liability 100.
```

**Fermati sul saldo iniziale di 200.**

«Per rendere visibile il doppio pagamento, la PoC mette nell'escrow una riserva aggiuntiva di cento token oltre al deposito.

È un prerequisito esplicito della prova. Non stiamo creando un secondo deposito attraverso questo escrow, che ne ammette uno solo: il mock accredita direttamente la riserva.

Senza asset sufficienti, un secondo trasferimento potrebbe fallire e far annullare la sequenza. Perciò nel finding scriviamo sia la callback sia la disponibilità di asset extra. Non nascondiamo le condizioni necessarie al risultato.»

[Apri `test_AUD01_ReentrantTokenPaysSameLiabilityTwice`. Mostra `token.mint(address(escrow), AMOUNT)` e `token.configure(address(escrow))`.]

«Il test prepara la riserva e attiva la callback. Dopo una sola chiamata esterna a `release`, verifica che la callback sia stata tentata e sia riuscita, che il seller abbia duecento e che il saldo dell'escrow sia zero.»

```bash
bash demo.sh poc
```

**Risultato atteso:** due test PASS: AUD-01 dimostra il doppio pagamento, AUD-02 dimostra il debito non coperto e il payout rifiutato. Se leggi la trace di AUD-01, cerca la seconda `release` annidata nel trasferimento.

**Domanda:** «Basta controllare che alla fine `liability` sia zero?»

«No. Anche dopo aver pagato due volte potrebbe essere zero. Il controllo economico sul saldo ricevuto dal seller distingue una chiusura corretta da una chiusura dopo un doppio pagamento.»

## 6. Tre ipotesi che richiedono la specifica

### Guardian e oracle

[Mostra `setOracle`.]

«Qui esiste un controllo di autorizzazione, ma ammette governance oppure guardian. La specifica assegna al guardian il potere di fermare il sistema, non quello di cambiare la fonte del prezzo.

La prova parte con un oracle sotto soglia. Il guardian lo sostituisce con un altro che soddisfa la soglia. Poi un caller generico esegue `release`.

Non diciamo che il guardian ha alterato il prezzo di un provider reale. Ha sostituito la dipendenza usata dal contratto, aggirando la separazione dei ruoli.»

### Confine della freshness

«Il target rifiuta soltanto età maggiori di `maxAge`. Il requisito chiede età strettamente minori. Quindi il caso esatto viene accettato quando dovrebbe essere rifiutato.

La prova imposta `updatedAt` esattamente un'ora prima. Questo è il valore che distingue le due regole.»

### Notifier opzionale

«Il notifier dovrebbe essere best-effort: proviamo a notificare, ma un normale fallimento della notifica non deve annullare il pagamento.

Nel target la chiamata è diretta e il revert si propaga. Se il notifier fallisce, viene annullata tutta la release, anche il trasferimento dei token. Il contratto torna Funded e i token restano nell'escrow.

Non confondiamo questa prova con il doppio pagamento: qui la conseguenza dimostrata è che una dipendenza opzionale blocca il settlement.»

```bash
bash demo.sh policy
```

**Risultato atteso:** tre test PASS: guardian sostituisce l'oracle e permette il settlement; confine esatto accettato; notifier che reverte blocca la release con rollback.

**Nota per il docente:** il dossier classifica il notifier come osservazione Informational, motivando dipendenza nota al deployment e refund ancora disponibile. Presentala come valutazione contestuale del dossier. Non insegnare che un blocco del settlement sia sempre Informational: assenza di vie d'uscita o altre conseguenze cambierebbero la valutazione.

## 7. Scrivere un finding che qualcuno possa usare

[Chiedi agli studenti di scrivere due frasi su AUD-02. Poi mostra questa versione svolta.]

**Titolo:** il deposito registra il nominale e crea un debito non coperto con token tassati.

**Testo da leggere come esempio di finding:**

«In `AuditEscrow.deposit`, `liability` viene impostata all'importo richiesto senza verificare l'aumento effettivo del saldo. Con un token che trattiene il dieci per cento, un deposito richiesto di cento produce un saldo di novanta e una liability di cento. Il successivo payout di cento fallisce per saldo insufficiente. Il comportamento viola la policy che impone il rifiuto atomico dei trasferimenti non esatti. La PoC `test_AUD02_FeeTokenCreatesInsolventNominalLiability` riproduce saldo, debito e fallimento. La correzione proposta misura il ricevuto e annulla il deposito se differisce dal richiesto.»

«Questo testo contiene punto del codice, causa, prerequisito, numeri osservati, conseguenza, requisito e direzione del fix. Non costringe chi lo legge a indovinare perché la riga è importante.»

[Apri `audit/report.md` e mostra la tabella senza leggerla come una graduatoria universale.]

| Finding | Severità nel dossier | Ragionamento da esporre |
| --- | --- | --- |
| AUD-01 | High | Doppio payout, con callback e riserva esplicite |
| AUD-02 | Medium | Liability non coperta e settlement che fallisce con fee token |
| AUD-03 | Medium | Guardian ottiene un potere economico riservato a governance |
| AUD-04 | Low | Violazione al confine della freshness stretta |

«Le etichette riassumono la valutazione; il ragionamento la sostiene. Se cambiano asset, ruoli o precondizioni, dobbiamo rivalutare la severità.

E non sommiamo automaticamente tutti i sintomi come finding distinti. Saldo insufficiente e liability eccessiva possono avere la stessa causa: l'accounting nominale.»

### Le ipotesi escluse restano nel dossier

[Apri `audit/hypotheses.md`, H-09 e H-10.]

«Avevamo anche ipotesi che non sono state confermate. Un timestamp futuro non viene accettato dal target: la sottrazione va in underflow e fa revert. La policy potrebbe essere espressa meglio, ma non scriviamo che il prezzo futuro passa.

Anche l'ipotesi “il bool del token viene ignorato” è falsa per queste chiamate del target: il codice lo controlla. È importante non trasferire automaticamente i bug del contratto della lezione precedente a questo.»

## 8. Review della patch: stesso requisito, comportamento corretto

[Apri `src/fixed/RemediatedEscrow.sol`, una funzione alla volta.]

«La correzione è un nuovo pezzo di codice da revisionare. Non ci basta che la vecchia PoC smetta di funzionare: vogliamo capire perché e verificare che l'uso previsto resti possibile.»

| Caso | Prima | Dopo |
| --- | --- | --- |
| AUD-01 | Trasferimento prima della chiusura | Liability azzerata e stato terminale prima del trasferimento |
| AUD-02 | Accredito del nominale | Misura del ricevuto e rifiuto se il trasferimento non è esatto |
| AUD-03 | Governance oppure guardian | Solo governance |
| AUD-04 | Età esatta accettata | Età esatta rifiutata; futuro gestito esplicitamente |
| OBS-01 | Revert notifier propagato | Revert catturato e risultato notificato con evento |

«Nel caso della callback, la seconda release trova già Released e viene rifiutata. Il seller riceve cento e la riserva resta nel contratto.

Nel caso del fee token, il deposito viene annullato. Il buyer torna ad avere cento, il saldo escrow torna zero e non nasce liability. Questa è l'atomicità da controllare: non basta osservare un messaggio d'errore.

Per il notifier la decisione è diversa da quella del token: se il trasferimento fallisce, annulliamo il settlement; se la notifica opzionale fa revert, registriamo il fallimento e proseguiamo.»

```bash
bash demo.sh retest
```

**Risultato atteso:** cinque regressioni PASS, una per ciascuno dei cinque casi. Il test notifier selezionato verifica settlement e saldo; l'evento si vede nel codice ma non va descritto come un'asserzione presente in quel test.

«Le PoC sul target originale restano. Le regressioni verificano la versione corretta. Entrambe possono essere verdi nello stesso repository perché affermano cose diverse su contratti diversi.»

## 9. Quanto ci dice la campagna invariant?

[Apri `audit/tests/RemediatedInvariant.t.sol`.]

«La campagna parte da un escrow già finanziato con cento. L'handler può chiamare release e refund. Questi sono i due percorsi esplorati.

Le tre proprietà controllano copertura del debito, liability zero negli stati terminali e impossibilità per il seller di ricevere più di cento.»

```bash
bash demo.sh invariant
```

**Risultato atteso:** campagna PASS con tre proprietà. La configurazione del laboratorio usa 128 run e depth 32.

«L'handler cattura i revert, per esempio quelli delle chiamate dopo la chiusura. Quindi un numero basso di revert visibili non dimostra che ogni azione abbia prodotto un avanzamento utile.

Soprattutto, qui non stiamo cambiando oracle, esercitando token avversari o combinando pause e unpause. Queste tre proprietà non sostituiscono tutti i test mirati che abbiamo appena letto. Un report corretto descrive questo limite.»

## 10. Chiusura: cosa scriviamo nel report

«Il report deve permettere di capire tre cose: quale sistema è stato revisionato, quali problemi sono stati dimostrati e quale evidenza abbiamo sulle correzioni.

Nel riepilogo spieghiamo prima gli effetti: doppio payout, accounting incompatibile con la policy, ruoli troppo ampi e confine oracle errato. Per i dettagli rimandiamo ai finding e alle prove.

Distinguiamo poi i problemi corretti dalle domande ancora aperte e dalle aree fuori scope. Un mock oracle locale non è una verifica del provider reale. Un indirizzo chiamato governance non dimostra da solo che dietro ci sia un multisig o un timelock.

Oggi abbiamo seguito una catena completa: requisito, proprietà, ipotesi, prova, finding, correzione e retest. Nella prossima lezione sarete voi a ricostruirla sul progetto finale.»

### Verifica orale

| Domanda | Risposta |
| --- | --- |
| Perché teniamo il target originale? | Per conservare e riprodurre l'evidenza del problema. |
| La PoC con doppio payout richiede solo una callback? | Richiede anche asset sufficienti per entrambi i trasferimenti nella sequenza mostrata. |
| La patch deve accettare un deposito tassato accreditando 90? | Non nella 16: la policy impone il rifiuto atomico. |
| Tre invariant verificano tutte le proprietà del dossier? | No: dipende dalle asserzioni e dalle azioni dell'handler. |

**Compito:** compilare [HypothesisWorksheet.md](exercises/HypothesisWorksheet.md) e un finding per AUD-03 senza copiare il report. Devono esserci ruolo previsto, ruolo effettivo, sostituzione oracle, conseguenza economica, PoC e regressione. Confrontare soltanto dopo con `audit/findings/`.

**Percorso breve:** svolgi interamente AUD-02 e AUD-01. Per gli altri casi usa la tabella prima/dopo e i risultati già descritti. Non saltare scope, prerequisiti della PoC o limiti del retest per mostrare più output.

## Promemoria operativo

`bash demo.sh help` mostra le demo; `bash demo.sh check` richiama la suite completa di 14 test. Foundry legge i test da `audit/tests/`. Le prove sono locali; Slither è un approfondimento separato con gli script del laboratorio, non un prerequisito per questa conduzione guidata.

Se il terminale non parte, esegui il ragionamento sui numeri e leggi le asserzioni. Non correggere il target in diretta. Le percentuali di coverage o i risultati storici nei documenti non vanno presentati come misurazioni appena effettuate.
