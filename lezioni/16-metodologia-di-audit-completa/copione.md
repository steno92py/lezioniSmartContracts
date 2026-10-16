# Lezione 16 — Metodologia di audit completa

Copione esteso per condurre un mini audit dall'inizio alla fine. **Il testo tra caporali («…») è pronto da dire; le parentesi quadre indicano cosa mostrare o far fare.** Le soluzioni sono incluse: prima dai agli studenti il tempo di formulare un'ipotesi, poi leggile insieme a loro. Costruisci tabelle e sequenze alla lavagna, facendo anticipare i risultati alla classe.

[Laboratorio](README.md) · [Appunti di approfondimento](teoria.md)

**Accessi rapidi:** [Tempi e preparazione](#come-distribuire-il-tempo) · [Sistema e baseline](#3-disegniamo-il-sistema-e-scegliamo-le-proprietà) · [Accounting](#4-da-una-riga-di-codice-a-unipotesi-verificabile) · [Reentrancy](#5-reentrancy-raccontare-la-sequenza-e-dichiarare-la-riserva) · [Finding](#7-scrivere-un-finding-che-qualcuno-possa-usare) · [Retest](#8-review-della-patch-stesso-requisito-comportamento-corretto) · [Chiusura](#10-chiusura-cosa-scriviamo-nel-report)

Dalla radice del repository:

```bash
cd lezioni/16-metodologia-di-audit-completa
```

Rimani qui per tutti i comandi. Tieni aperti `audit/scope.md`, `src/target/AuditEscrow.sol` e `audit/tests/AuditEscrowFindings.t.sol`. Le demo sono facoltative; ogni risultato viene spiegato nel copione. Il target vulnerabile resta invariato: la versione corretta è in `src/fixed/RemediatedEscrow.sol`.

## Come distribuire il tempo

Il percorso consigliato è di **180 minuti, divisibili in due incontri da 90**, esclusa una eventuale pausa. Comprende lettura, previsioni, demo e restituzione degli studenti. Le versioni da 90 e 60 minuti sono selezioni: non leggere integralmente questo copione nei tempi brevi. Il lavoro autonomo consiste nel produrre un finding e la sua motivazione senza copiare il report.

| Passaggio | Esteso: 180 minuti | Guidato: 90 minuti | Sintesi: 60 minuti |
| --- | --- | --- | --- |
| Apertura e scope (§1–2) | 0–20 | 0–12 | 0–8 |
| Architettura, proprietà e baseline (§3) | 20–45 | 12–25 | 8–17 |
| Ipotesi e accounting (§4) | 45–65 | 25–39 | 17–27 |
| Reentrancy (§5) | 65–90 | 39–52 | 27–37 |
| Governance, freshness e notifier (§6) | 90–115 | 52–64 | 37–45 |
| Triage, finding e severità (§7) | 115–140 | 64–75 | 45–51 |
| Patch, retest e invariant (§8–9) | 140–165 | 75–85 | 51–57 |
| Report e restituzione (§10) | 165–180 | 85–90 | 57–60 |

**Nei due incontri:** chiudi il primo facendo ricostruire AUD-01 senza guardare la soluzione. Apri il secondo recuperando saldo, debito e stato prima e dopo la callback. Nei percorsi brevi assegna a casa la seconda lettura per write path, il triage Slither e la scrittura completa del finding; conserva in aula almeno una catena requisito → prova → fix → retest.

### Preparazione e patto con la classe

[Prima dell'aula esegui `forge build`, poi `bash demo.sh check`. Apri anche `src/mocks/AuditMocks.sol`: servirà a spiegare quale comportamento produce ogni risultato insolito.]

«Oggi alterniamo tre momenti: prevedere, eseguire e spiegare. Prima del comando vi chiederò i valori attesi. Dopo il comando voglio sapere quale asserzione è passata e che cosa significa.

Useremo cento token come cifra leggibile. Nel codice `100 ether` significa cento per dieci alla diciottesima: qui rappresenta un importo del token, non un invio di ETH. Il prezzo ha un'altra scala: `100e8` significa cento con otto decimali. Quantità del token e prezzo restano grandezze diverse.

Quando un passaggio sembra complicato torniamo a tre domande: chi chiama, quale dato cambia, dove sono i token?»

**Controllo iniziale, due minuti:** chiedi la differenza fra approve e deposito, saldo e liability, revert e ritorno `false`. Risposte: approve autorizza una spesa e deposit la esegue; il saldo misura asset e la liability l'obbligo registrato; `false` è un valore che il chiamante deve interpretare. Recupera gli eventuali dubbi durante gli esempi.

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

### Il caso che ci accompagna fino alla consegna

«Il nostro esempio principale sarà un deposito richiesto di cento che porta soltanto novanta token nel contratto. Lo vedremo come dubbio, misura, finding e regressione.

All'inizio chiamarlo “insolvenza” sarebbe prematuro: dobbiamo stabilire quale regola si applica, se lo scenario è raggiungibile e quale obbligo nasce. Alla fine sapremo indicare la prova che sostiene la conclusione. Questo è il significato concreto di end-to-end: nessun salto fra il requisito e il report.»

| Passaggio | Domanda | Documento da usare quando serve |
| --- | --- | --- |
| Scope | Quale codice e quali regole? | `audit/scope.md` |
| Modello | Chi può fare cosa? | `audit/architecture.md`, `audit/threat-model.md` |
| Proprietà | Che cosa deve restare vero? | `audit/invariants.md`, `audit/requirements-matrix.md` |
| Ipotesi | Quale scenario può violarlo? | Worksheet personale, poi `audit/hypotheses.md` |
| Prova | Che cosa osserviamo? | `audit/tests/AuditEscrowFindings.t.sol` |
| Finding | Qual è la causa e quanto conta? | `audit/findings/AUD-02.md` |
| Retest | La modifica ripristina la regola? | `audit/tests/RemediationRetest.t.sol` |
| Report | Che cosa possiamo concludere? | `audit/report.md` |

## 2. Scope: stabilire che cosa stiamo revisionando

[Apri `audit/scope.md`.]

«Scope significa perimetro del lavoro. Qui il target è `AuditEscrow`, insieme alle interfacce e ai comportamenti d'integrazione previsti.

Token, oracle e notifier sono dipendenze esterne. Nei test useremo mock che ne riproducono alcuni comportamenti. Questo ci permette di verificare la reazione dell'escrow; non equivale ad aver auditato un provider oracle reale.

Proxy, upgrade, chiavi e frontend sono fuori da questo esercizio. Li dichiariamo perché chi legge non deve attribuirci una verifica che non abbiamo fatto.»

**Nota per il docente:** il documento `scope.md` contiene una nota storica sull'assenza di un commit al momento della sua stesura; non descriverla come lo stato attuale del repository. Anche il report conserva quel riferimento storico. Per la lezione usa questa distinzione esplicita:

«Nel dossier trovate una nota relativa allo snapshot usato nella stesura originale. Per una nuova review, l'identificazione va aggiornata: commit e modifiche locali effettivamente esaminate. Un hash non identifica da solo le modifiche non committate.

Questo è già un controllo di audit: i metadati devono descrivere il codice che stiamo davvero guardando.»

[Per identificare lo snapshot della sessione, dalla cartella della lezione:]

```bash
git rev-parse HEAD
git status --short
forge --version
```

«Registriamo hash, versione dello strumento e modifiche locali. Se il codice è modificato conserviamo anche il diff; eventuali file nuovi vanno conservati separatamente, perché il diff dei file tracciati non li include. Un hash copiato da un report precedente non identifica automaticamente la review di oggi.»

### Requisito, assunzione e limite

«Un requisito dice che cosa il sistema deve fare: rifiutare un deposito tassato. Un'assunzione dice su che cosa si basa il ragionamento: `balanceOf` rappresenta correttamente il saldo del token supportato. Un limite dice che cosa non abbiamo verificato: l'implementazione di un oracle reale.

Se un token inventa i saldi, leggerli due volte non lo rende affidabile. La nostra prova usa un token con fee definita e saldi coerenti. Dimostra quella incompatibilità; non verifica ogni possibile contratto che espone la stessa interfaccia.»

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

### Prima lettura: il viaggio di cento token

[Apri `deposit`, `release` e `refund`. Segui un percorso per volta, prima di discutere i commenti sui finding.]

«L'escrow nasce Created. Il buyer possiede i token e autorizza l'escrow a spenderli con `approve`, chiamata sul token. Non ha ancora spostato fondi.

Il buyer chiama poi `deposit(100)`. L'escrow chiama `transferFrom`: per il token, il chiamante adesso è l'escrow. Il token controlla l'allowance concessa dal buyer a quell'indirizzo.

Dopo un deposito riuscito siamo Funded. Possiamo pagare il seller con release oppure restituire il deposito con refund. Sono uscite alternative dallo stesso debito: una chiusura riuscita esclude l'altra.»

```text
Created -- deposit del buyer --> Funded -- release --> Released
                                   |
                                   +-- refund del buyer --> Refunded

Released e Refunded sono terminali: questo escrow non apre un nuovo ciclo.
```

| Punto del percorso standard | Saldo escrow | Liability | Stato |
| --- | ---: | ---: | --- |
| Appena creato | 0 | 0 | Created |
| Dopo approve | 0 | 0 | Created |
| Dopo deposit(100) | 100 | 100 | Funded |
| Dopo release riuscita | 0 | 0 | Released |
| Oppure dopo refund riuscito | 0 | 0 | Refunded |

«L'ultima riga è un'alternativa alla penultima. Leggerle come azioni consecutive significherebbe spendere due volte lo stesso deposito.»

### Seconda lettura: chi scrive i dati importanti?

[Tre minuti per cercare gli assegnamenti. Poi completa la tabella.]

| Dato | Scritture nel target | Domanda di review |
| --- | --- | --- |
| `liability` | `deposit`, `release`, `refund` | L'importo è coperto? Quando viene azzerato? |
| `state` | `deposit`, `release`, `refund` | Quale stato vede una chiamata annidata? |
| `oracle` | constructor, `setOracle` | Chi sceglie la fonte che autorizza il pagamento? |
| `paused` | `pause`, `unpause` | Chi ferma, chi riattiva e quali funzioni consultano la pausa? |

«Per proteggere un dato dobbiamo conoscere tutti i percorsi che lo modificano. Questa lettura trasversale completa quella per funzioni.

Nella 16 soltanto release legge `paused`. Deposit e refund non lo controllano, sia nel target sia nel fixed. Non attribuiamo alla pausa il significato che avrà nella 17: controlliamo dove viene applicata e quali requisiti sono dichiarati.

Individuiamo anche token, oracle e notifier: sono punti in cui il nostro contratto chiama codice esterno. L'interfaccia descrive come chiamarlo, non garantisce il suo comportamento. Questo è il confine di fiducia, o trust boundary.»

**Checkpoint:** «Refund richiede un oracle funzionante?» **Risposta:** no, controlla caller e stato e trasferisce la liability; non consulta prezzo o notifier. Ricorderemo questa via d'uscita nel valutare il blocco di release.

### La baseline

[Apri `test_Baseline_HappyPathWorks` in `audit/tests/AuditEscrowFindings.t.sol`.]

«Prima di introdurre dipendenze avversarie, verifichiamo il percorso normale: token standard, prezzo valido, deposito cento e release da un caller generico.

Ci aspettiamo seller con cento, debito zero, stato Released e una notifica. Questa è la baseline: ci serve a riconoscere se un esperimento successivo fallisce per la causa che stiamo studiando oppure per un setup sbagliato.»

```bash
bash demo.sh baseline
```

**Risultato atteso:** un test PASS con quei quattro risultati. La baseline dimostra che il flusso normale del target funziona nello scenario; non cancella le vulnerabilità degli altri scenari.

### Leggere una prova: preparazione, azione, asserzioni

«Arrange prepara attori, dipendenze e stato. Act esegue l'azione studiata. Assert confronta i risultati con la previsione.

`makeAddr` assegna indirizzi leggibili ai ruoli. `vm.warp` imposta il tempo locale. `vm.prank(stranger)` fa arrivare la prossima chiamata dal ruolo scelto nel test: non è un potere che un estraneo possiede sul contratto reale. Gli helper finanziano il buyer, autorizzano la spesa e depositano.

Poi arrivano le prove: seller cento controlla l'esito economico; liability zero e Released la chiusura contabile; una chiamata al notifier il comportamento di quella dipendenza. Nessuna asserzione, da sola, racconta tutto il percorso.»

[Fai indicare le tre parti del test. Se qualcuno confonde setup e attacco, chiedi quali poteri vengono dal laboratorio e quali dall'interfaccia esposta agli utenti.]

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

### Fermare il ragionamento in un work paper

[Prima di passare alla reentrancy, dedica quattro minuti a una copia di `exercises/HypothesisWorksheet.md`. Mostra questa compilazione soltanto dopo il tentativo degli studenti.]

| Campo | Esempio svolto per H-02 |
| --- | --- |
| Osservazione | `deposit` copia `amount` in `liability` dopo `transferFrom` |
| Proprietà | I depositi non esatti devono essere rifiutati senza lasciare debito |
| Attore e stato | Buyer autorizzato, escrow Created, saldo e allowance sufficienti |
| Variabile dell'esperimento | Token con fee 10%; gli altri componenti restano ordinari |
| Previsione | Deposito accettato, saldo 90, liability 100 |
| Conferma osservata | Le tre asserzioni contabili e il revert del payout |
| Causa | Richiesto e ricevuto vengono considerati equivalenti |
| Limite | Nessuna prova di furto o di manipolazione di un token reale |
| Retest atteso | Deposito rifiutato e movimenti annullati |

«Cambiamo un comportamento per volta. Se usassimo insieme un token tassato, un oracle stale e un caller sbagliato, release potrebbe fallire prima di raggiungere il trasferimento. Avremmo un revert, ma non la prova della nostra ipotesi.

Per questo `expectRevert` con l'errore preciso conta: qui vogliamo l'insufficienza di saldo del token, non un generico fallimento. Inoltre misuriamo saldo e debito prima della release, così la discrepanza è già osservabile.»

**Errore frequente:** «Nel test il payout fallisce, dunque il contratto si è difeso.» **Risposta:** ha già accettato il deposito incompatibile e registrato un obbligo non coperto. Il controllo richiesto apparteneva all'ingresso. Un fallimento successivo non ripristina automaticamente la possibilità di onorare quel debito.

**Raccordo:** «Abbiamo conservato il primo ragionamento. Il secondo problema non nasce da quanto entra, ma da quante volte può essere pagato lo stesso debito.»

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

### La trace, letta come una pila di chiamate

[Seleziona solo la prova di reentrancy per evitare di cercarla in un output lungo.]

```bash
forge test --offline --match-contract '^AuditEscrowFindingsTest$' \
  --match-test '^test_AUD01_ReentrantTokenPaysSameLiabilityTwice\(' -vvvv
```

«L'indentazione ci aiuta a seguire chi sta aspettando il ritorno di chi. Non stiamo osservando due transazioni simultanee. La prima release è sospesa mentre il token esegue il trasferimento e richiama l'escrow nella stessa catena di chiamate.»

```text
caller → escrow.release()           il contratto vede caller
  escrow → token.transfer(...)      il token vede escrow
    token → escrow.release()        il contratto vede token
      escrow → token.transfer(...) secondo pagamento
```

«La seconda release passa il controllo sul caller perché qui release è permissionless. Non abbiamo falsificato l'identità del buyer. Passa anche il controllo di stato perché la prima esecuzione non ha ancora scritto Released.

Apriamo ora `ReentrantToken._transfer`: prima modifica i saldi, poi disarma la callback e la tenta una sola volta. Disarmarla evita una ricorsione indefinita. La chiamata di ritorno è a basso livello: il mock ne registra il successo e può continuare anche se quella chiamata fallisce.»

**Precisazione da dire:** «Senza la riserva, in questo specifico mock il secondo trasferimento fallirebbe e il fallimento della callback verrebbe catturato; il primo pagamento potrebbe comunque completarsi. Con altre dipendenze un revert propagato potrebbe annullare l'intera release. La riserva rende osservabile il doppio payout nella prova che abbiamo davanti.»

[Fai ricostruire il saldo in tre istanti: 200 prima, 100 dopo il primo trasferimento, 0 dopo il secondo. Poi domanda chi riceve l'extra.]

«Il beneficiario osservato è il seller. Per affermare che l'attaccante incassa, dovremmo anche spiegare il suo legame con quel destinatario. La prova attuale basta a dimostrare che lo stesso debito può essere pagato due volte.»

## 6. Tre ipotesi che richiedono la specifica

### Guardian e oracle

[Mostra `setOracle`.]

«Qui esiste un controllo di autorizzazione, ma ammette governance oppure guardian. La specifica assegna al guardian il potere di fermare il sistema, non quello di cambiare la fonte del prezzo.

La prova parte con un oracle sotto soglia. Il guardian lo sostituisce con un altro che soddisfa la soglia. Poi un caller generico esegue `release`.

Non diciamo che il guardian ha alterato il prezzo di un provider reale. Ha sostituito la dipendenza usata dal contratto, aggirando la separazione dei ruoli.»

### Confine della freshness

«Il target rifiuta soltanto età maggiori di `maxAge`. Il requisito chiede età strettamente minori. Quindi il caso esatto viene accettato quando dovrebbe essere rifiutato.

La prova imposta `updatedAt` esattamente un'ora prima. Questo è il valore che distingue le due regole.»

[Scrivi i tre valori vicini, con prezzo altrimenti valido.]

| Età del dato | Requisito della 16 | Target con `> maxAge` | Fixed con `>= maxAge` |
| --- | --- | --- | --- |
| 3.599 secondi | Accettare | Accetta | Accetta |
| 3.600 secondi | Rifiutare | Accetta | Rifiuta |
| 3.601 secondi | Rifiutare | Rifiuta | Rifiuta |

«Provare soltanto il dato fresco e quello molto vecchio non distingue le implementazioni. Il controesempio minimo è sul confine. Queste tre righe sono una previsione ricavata dalla condizione; le prove fornite su AUD-04 coprono il confine esatto. Completare la terna è uno degli esercizi, non un test che possiamo già dichiarare eseguito.»

### Notifier opzionale

«Il notifier dovrebbe essere best-effort: proviamo a notificare, ma un normale fallimento della notifica non deve annullare il pagamento.

Nel target la chiamata è diretta e il revert si propaga. Se il notifier fallisce, viene annullata tutta la release, anche il trasferimento dei token. Il contratto torna Funded e i token restano nell'escrow.

Non confondiamo questa prova con il doppio pagamento: qui la conseguenza dimostrata è che una dipendenza opzionale blocca il settlement.»

```bash
bash demo.sh policy
```

**Risultato atteso:** tre test PASS: guardian sostituisce l'oracle e permette il settlement; confine esatto accettato; notifier che reverte blocca la release con rollback.

**Nota per il docente:** il dossier classifica il notifier come osservazione Informational, motivando dipendenza nota al deployment e refund ancora disponibile. Presentala come valutazione contestuale del dossier. Non insegnare che un blocco del settlement sia sempre Informational: assenza di vie d'uscita o altre conseguenze cambierebbero la valutazione.

### Due fallimenti esterni, due decisioni di prodotto

«Pagamento e notifica sono chiamate esterne, ma hanno responsabilità diverse. Se il pagamento obbligatorio fallisce, non vogliamo dichiarare il debito estinto. Se una notifica opzionale fallisce normalmente, vogliamo poter mantenere il pagamento e registrare il problema.

Nel target della 16 il notifier fa revert dopo il trasferimento. Quel trasferimento era ancora parte della stessa esecuzione: il revert propagato annulla anche i saldi modificati dal token. Non restano metà pagamento e metà chiusura.

Nel fixed il catch gestisce il revert della notifica e consente di completare il percorso. Questa prova riguarda il normale revert del mock. Non abbiamo fatto una campagna sul consumo avversario di gas o su ogni comportamento possibile della dipendenza: best-effort non va trasformato in una promessa illimitata.»

## 7. Scrivere un finding che qualcuno possa usare

### Inserire l'analisi statica senza perdere la domanda iniziale

[Nel percorso esteso apri `audit/false-positive-log.md`. Se Slither è già installato seguendo il README, puoi usare i due comandi; altrimenti svolgi il triage sul dossier.]

```bash
bash scripts/slither-printers.sh
bash scripts/slither-target.sh
```

«I printer aiutano a rivedere entry point, funzioni e scritture. I detector suggeriscono strutture da investigare. Ogni segnale torna nella stessa catena: proprietà, attore, stato, conseguenza e prova.

Un alert su `block.timestamp` non dimostra che il tempo sia usato male: la freshness richiede proprio un confronto temporale. Qui il nostro problema concreto è l'uguaglianza al limite.

Anche il deposito corretto fa una chiamata esterna prima di scrivere il credito, perché deve misurare quanto riceve. Durante una callback ordinaria il caller sarebbe il token, mentre deposit richiede il buyer. Prima di chiudere l'ipotesi registriamo l'assunzione che i ruoli non coincidano e controlliamo gli altri entry point. “C'è un controllo sul caller” è l'inizio dell'analisi, non una prova universale contro ogni callback.»

**Nota operativa:** un codice d'uscita non zero va letto insieme all'output: finding intenzionali, tool assente e compilazione fallita sono situazioni diverse. Il log fornito contiene ragionamenti di triage; non presentarlo come output generato nella sessione se non hai eseguito lo strumento.

**Esercizio, due minuti:** fai classificare H-02 confermata, H-09 falsificata e H-05 informativa. La motivazione deve includere rispettivamente misura contabile, underflow e contesto di liveness. Il livello Informational non nega che il comportamento sia stato riprodotto.

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

### Motivare una severità senza indovinare l'etichetta

«Partiamo dall'impatto: che cosa perde il sistema, o quale operazione non riesce più a completare? Poi elenchiamo le condizioni: chi ha il potere necessario, quale token serve, quali fondi devono essere presenti.

Per AUD-01 l'impatto osservato è il pagamento extra al seller. Le condizioni comprendono callback, stato Funded, prezzo valido e riserva. Per AUD-03 il potere è già privilegiato: è il guardian a sostituire la dipendenza, non un utente qualsiasi. Queste informazioni permettono di discutere la severità, anche se un altro team usa una scala diversa.

Provate a cambiare una sola assunzione: nessuna riserva disponibile, oppure guardian coincidente con governance. Il codice resta uguale, ma cambiano la raggiungibilità dell'impatto mostrato o il significato della separazione dei ruoli. Nel report deve risultare quale scenario stiamo valutando.»

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

### Che cosa significa davvero aver ritestato AUD-02

«Nella regressione conserviamo buyer, importo e fee del caso originale. Cambia il contratto. Ora ci aspettiamo `UnsupportedTransferTax(100, 90)`, poi controlliamo buyer cento, escrow zero e liability zero.

L'errore dimostra che è stata rilevata la discrepanza prevista. I saldi dimostrano che il trasferimento tentato dal deposito è stato annullato. L'approve, eseguito prima e fuori dalla chiamata che reverte, non viene cancellato dal revert di deposit. Il confine del rollback conta.

Una patch che rifiutasse tutti i depositi supererebbe il solo caso negativo. Per questo leggiamo anche il fuzz sul token standard: con importi positivi, saldo, credito e importo coincidono. Il test sul refund controlla l'altro percorso legittimo. Il retest deve preservare il servizio oltre a interrompere il controesempio.»

```bash
forge test --offline --match-contract '^RemediationRetestTest$' -vv
```

**Risultato atteso:** sette test, comprendenti cinque regressioni, il fuzz sul deposito standard e il refund terminale. La selezione `demo.sh retest` ne mostra solo cinque.

«Rivediamo anche le modifiche collaterali: il constructor rifiuta `maxAge == 0`, e i wrapper token gestiscono il ritorno opzionale. Sono codice aggiunto dalla patch. La matrice requisiti distingue la lettura manuale dai test presenti; non dichiariamo verificata ogni variante di token soltanto perché la suite è verde.»

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

### Una proprietà può essere vera e lasciare passare un problema

«Pensate al doppio payout: alla fine il saldo può essere zero e il debito zero. La proprietà saldo maggiore o uguale al debito è ancora vera. Anche lo stato terminale può essere corretto. Ci serve la terza vista: quanto ha incassato il seller nel corso dell'esecuzione.

Ora pensate a una campagna che non riesce mai a pagare: il seller rimane sempre a zero e quindi non supera cento. La proprietà di sicurezza passa, ma il servizio potrebbe essere inutilizzabile. La baseline e le prove di successo ci servono anche per questo.

Un'invariante viene controllata nei punti di osservazione della campagna. Qui non osserva automaticamente ogni istante interno a una chiamata al token; la PoC con callback serve a costruire proprio quel punto intermedio.»

[Chiedi una frase precisa da mettere nel report.]

**Risposta svolta:** «Le tre proprietà non hanno prodotto controesempi nelle sequenze generate di release/refund sul fixed già finanziato, con token standard e oracle inizialmente fresco. I comportamenti avversari sono trattati nelle prove mirate.»

## 10. Chiusura: cosa scriviamo nel report

«Il report deve permettere di capire tre cose: quale sistema è stato revisionato, quali problemi sono stati dimostrati e quale evidenza abbiamo sulle correzioni.

Nel riepilogo spieghiamo prima gli effetti: doppio payout, accounting incompatibile con la policy, ruoli troppo ampi e confine oracle errato. Per i dettagli rimandiamo ai finding e alle prove.

Distinguiamo poi i problemi corretti dalle domande ancora aperte e dalle aree fuori scope. Un mock oracle locale non è una verifica del provider reale. Un indirizzo chiamato governance non dimostra da solo che dietro ci sia un multisig o un timelock.

Oggi abbiamo seguito una catena completa: requisito, proprietà, ipotesi, prova, finding, correzione e retest. Nella prossima lezione sarete voi a ricostruirla sul progetto finale.»

### Restituzione conclusiva: riempire i collegamenti

[Cinque minuti individuali e tre di confronto. Nascondi i finding, lascia disponibili codice e test. Chiedi di completare questa catena con AUD-02.]

```text
Requisito → ipotesi → setup → azione → misura → impatto → fix → retest → limite
```

**Soluzione da leggere dopo:**

«Vogliamo accettare solo trasferimenti esatti. Il codice registra il nominale, quindi ipotizziamo che una fee crei un debito non coperto. Prepariamo buyer autorizzato, cento token, allowance e fee del dieci per cento. Depositiamo: osserviamo novanta di saldo e cento di debito. Il payout da cento fallisce. La patch misura il delta e rifiuta il deposito non esatto. Il retest verifica errore, saldi ripristinati e liability zero; il fuzz conserva i depositi standard. Questo non dimostra un furto e non certifica token diversi da quelli modellati.»

**Criterio del docente:** se manca un collegamento, chiedi di indicare il dato o l'asserzione che lo sostiene. Se viene proposta una conclusione più ampia, chiedi quale prova aggiuntiva servirebbe. La risposta corretta comprende anche sapere dove termina l'evidenza.

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

**Recupero di una demo interrotta:** scrivi stato iniziale e saldi; leggi solo l'azione del test; fai prevedere il risultato; apri le asserzioni e spiega ogni confronto. Distingui sempre una previsione letta dal codice da un'esecuzione osservata. Se Forge dice che non ha trovato test, la selezione non è una verifica riuscita: controlla il filtro o usa `bash demo.sh help`.

Per ripassare il meccanismo alla base del rollback, il riferimento del docente è la [documentazione Solidity sulla gestione degli errori](https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions): un errore propagato annulla le modifiche della chiamata coinvolta e delle sue sottochiamate; un fallimento intercettato richiede di ragionare sul confine in cui viene gestito.
