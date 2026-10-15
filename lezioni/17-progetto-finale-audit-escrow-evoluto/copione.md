# Lezione 17 — Progetto finale: audit dell'Escrow evoluto

Copione per una sessione di audit guidata con esercizi e soluzioni. **Il testo tra virgolette è da dire; le parentesi quadre indicano cosa mostrare o far fare.** Prima di aprire una soluzione, lascia agli studenti il tempo indicato per ragionare. Se nessuno risponde, usa il calcolo o la sequenza già svolta qui.

[Laboratorio](README.md) · [Appunti di approfondimento](teoria.md)

Dalla radice del repository:

```bash
cd lezioni/17-progetto-finale-audit-escrow-evoluto
```

Rimani qui per tutti i comandi. Apri `src/EscrowFinal.sol` e `audit/scope.md`. Tieni inizialmente chiusi `audit/report.md`, `audit/findings/` e la versione corretta. I commenti del target contengono già indicazioni sui difetti: l'esercizio è motivarli e provarli, non fingere una ricerca alla cieca.

**La sessione guidata prepara il progetto finale; la consegna autonoma è indicata in fondo.** Non promettere di completare un audit professionale in una sola lezione. Le demo sono facoltative e hanno tutte una lettura su carta.

## Come distribuire il tempo

| Passaggio | 90 minuti | 60 minuti |
| --- | --- | --- |
| Consegna, regole e mappa | 0–12 | 0–8 |
| Esercizio accounting e soluzione | 12–25 | 8–17 |
| Payout e freshness | 25–39 | 17–27 |
| Privilegi e notifier | 39–50 | 27–35 |
| Patch, pausa e fee residue | 50–64 | 35–45 |
| Fuzz e limiti dell'handler | 64–74 | 45–51 |
| Governance ritardata | 74–82 | 51–56 |
| Report e consegna finale | 82–90 | 56–60 |

## 1. Apertura: oggi ricostruiamo la catena delle prove

«Nella scorsa lezione abbiamo seguito un audit già organizzato, dallo scope al retest. Oggi useremo lo stesso metodo sul progetto finale.

Il contratto si chiama `EscrowFinal`. Un buyer deposita token, poi può autorizzare il pagamento al seller oppure ottenere il rimborso. Ci sono una commissione, un oracle, un owner, un ruolo di emergenza e un notifier.

Avete già incontrato tutti questi elementi. La difficoltà adesso è tenerli insieme senza perdere il collegamento fra regola, codice e conseguenza.

Per ogni problema vi chiederò quattro cose: quale proprietà dovrebbe valere, quale istruzione la mette in dubbio, come costruite la prova e che cosa vi aspettate dopo la correzione.

Non basta riconoscere un nome come reentrancy o access control. Voglio una frase concreta su questo contratto.»

[Scrivi il formato di risposta.]

```text
Mi aspetto che …
Il codice invece …
Lo dimostro preparando … e chiamando …
Dopo il fix deve succedere …
```

«Il target originale resta fermo. La patch è in un altro file. Così possiamo confrontare il comportamento vulnerabile con quello corretto senza cancellare l'evidenza.»

## 2. Prima di cercare bug: quattro differenze rispetto alla 16

[Apri `audit/scope.md`, poi mostra le funzioni del target citate nella tabella.]

«Questo escrow somiglia a quello della lezione 16, ma non ha esattamente le stesse regole. Fermiamoci sulle differenze, perché copiare una correzione senza rileggere la specifica può introdurre un nuovo errore.»

| Decisione | Lezione 16 | Progetto finale, lezione 17 |
| --- | --- | --- |
| Chi può chiamare release | Qualsiasi caller, se le condizioni economiche sono valide | Solo il buyer |
| Fee sul trasferimento in ingresso | Deposito da rifiutare atomicamente | Credito basato sul ricevuto effettivo |
| Età esattamente al limite | Rifiutata | Accettata |
| Ruoli di pausa | Governance o guardian pausano; governance riattiva | Emergency pauser pausa; owner riattiva |

«Qui la pausa blocca deposit e release, ma lascia disponibile refund. È una decisione esplicita: fermiamo nuovo rischio e settlement, mantenendo la possibilità di uscire.

L'oracle deve fornire un prezzo positivo con un timestamp valido e sufficientemente recente. Non stiamo riprendendo la soglia `minPrice` della 16: questo contratto ha un'altra specifica.

Il notifier è opzionale. Se fallisce, il pagamento deve poter restare valido, ma il fallimento deve essere osservabile.»

[Disegna la mappa minima.]

```text
Buyer → deposit → Escrow → release → Seller
                    |
                    +→ refund → Buyer
                    +→ oracle: prezzo e timestamp
                    +→ notifier: notifica dell'esito

Owner: fee, oracle, unpause
Emergency pauser: pause
```

«Adesso abbiamo le regole necessarie a giudicare le funzioni. Non apriamo ancora il report.»

## 3. Esercizio uno: quanti token dobbiamo registrare?

[Mostra `deposit` in `src/EscrowFinal.sol`. Dai tre minuti: gli studenti devono scrivere saldo reale, credito e proprietà dopo un deposito tassato.]

«Il buyer chiede di depositare cento. Il token trattiene il dieci per cento durante il trasferimento. Guardate quale numero viene salvato in `escrowedAmount` e quale numero arriva realmente.»

**Soluzione da svolgere:**

```text
Richiesto:                  100
Ricevuto dall'escrow:        90
escrowedAmount nel target:  100
Asset mancanti:              10
```

«La proprietà è che il saldo debba coprire il credito. Il contratto registra cento perché copia l'argomento, ma ne possiede novanta.

La causa non è semplicemente “il token ha una fee”. La causa è che l'escrow registra il richiesto senza misurare il ricevuto, nonostante la policy del progetto richieda di usare il ricevuto.»

[Apri `test/audit/TargetFindings.t.sol`, `test_F01_NominalAccountingExceedsReceivedAssets`.]

«La prova crea il token con fee, finanzia l'escrow e confronta due fonti: il saldo del token e il credito del contratto. Le asserzioni dicono novanta, cento e saldo minore del credito.»

```bash
bash demo.sh accounting
```

**Risultato atteso:** un test PASS. Il PASS conferma il difetto contabile del target.

**Domanda:** «Quale comportamento vogliamo dopo il fix: rifiutare oppure registrare novanta?»

«In questa lezione vogliamo registrare novanta. Nella 16 rifiutavamo il trasferimento tassato perché la policy era diversa. Il balance delta è uno strumento: la decisione su come usare quella misura viene dalla specifica.»

[Scrivi la soluzione concettuale prima di aprire il fixed.]

```text
saldoPrima = saldo del contratto
esegui trasferimento e gestisci il suo esito
ricevuto = saldoDopo − saldoPrima
credito = ricevuto
```

«Misurare il ricevuto non sostituisce la gestione del fallimento della chiamata. Sono controlli diversi.»

## 4. Esercizio due: Released significa che il seller è stato pagato?

[Mostra `release`, dalla copia di `gross` al trasferimento del token.]

«Qui stato e credito vengono aggiornati prima della chiamata esterna. L'ordine segue checks-effects-interactions.

Quindi questa funzione è corretta?»

[Aspetta una previsione. Poi introduci il comportamento del mock.]

«Il token del nostro esperimento non fa revert. Restituisce `false` e non trasferisce i token.

Guardate la chiamata: il contratto ignora quel booleano. Dal punto di vista EVM la chiamata è terminata senza revert, quindi non parte automaticamente un rollback.

Questo è diverso dal revert che abbiamo visto nella lezione 15. Se una funzione restituisce un risultato che significa fallimento, qualcuno deve leggerlo e gestirlo.»

[Compila la tabella insieme agli studenti.]

| Osservabile dopo release sul target | Valore |
| --- | --- |
| Stato | Released |
| `escrowedAmount` | 0 |
| Token ricevuti dal seller | 0 |
| Token rimasti nell'escrow | 100 |

«Il contratto dichiara chiuso il pagamento, ma i token sono ancora lì. Inoltre il normale refund richiede lo stato Funded: quel percorso non è più disponibile.

Non descriviamo il caso come un furto già eseguito. Dimostriamo un falso successo terminale e la perdita dei normali percorsi di pagamento o rimborso per quei fondi.»

[Apri `test_F03_FalseReturnCreatesFalseTerminalSuccess`. Leggi le quattro asserzioni.]

**Domanda:** «Se controllo soltanto stato Released e credito zero, il test mi protegge?»

«No. Sono proprio i due valori che il contratto sbagliato produce. Serve osservare anche dove sono i token e quanto ha ricevuto il seller.»

### Lo stesso percorso usa un prezzo scaduto

[Mostra la lettura dell'oracle e la riga `updatedAt;`.]

«Il contratto legge prezzo e timestamp, ma usa soltanto il prezzo. Scrivere il nome della variabile su una riga non significa validarla.

La prova F-02 prepara un prezzo positivo di due ore fa. Il limite è un'ora, quindi release dovrebbe essere rifiutata. Il target invece paga il seller.»

```bash
bash demo.sh payout
```

**Risultato atteso:** due test PASS. F-03 registra Released senza pagare; F-02 permette il pagamento con il prezzo di due ore fa. Sono cause diverse e rimangono finding distinti.

**Raccordo:** «Ora vediamo chi può modificare proprio la dipendenza da cui leggiamo quel prezzo.»

## 5. Privilegi: chi può scegliere l'oracle?

[Mostra `setOracle`. Dai un minuto per completare le quattro frasi del formato iniziale.]

«La proprietà prevista è: soltanto owner può cambiare l'oracle.

Il codice assegna il nuovo indirizzo senza controllare il caller. La prova impersona un estraneo, chiama `setOracle` e legge l'indirizzo salvato. È sufficiente per dimostrare la violazione del controllo di accesso.»

[Apri `test_F04_StrangerCanReplaceOracle`.]

«Facciamo attenzione alla conclusione. Questo test dimostra che l'estraneo sostituisce l'oracle. Non dimostra che l'estraneo possa chiamare direttamente release: release resta riservata al buyer.

Il rischio è che una dipendenza economica possa essere scelta da un soggetto non autorizzato, influenzando le operazioni successive. Nel finding separiamo la capacità dimostrata dalle conseguenze che richiedono ulteriori passaggi.»

## 6. Notifier: fallimento tollerato, ma visibile

[Mostra la low-level call al notifier in `release`.]

«Nella 15 abbiamo visto una chiamata ignorata che creava un falso successo. Ora vediamo ancora una low-level call con esito ignorato, ma la specifica dice che la notifica è opzionale.

Quindi la soluzione è sempre far fallire tutto se il notifier non risponde?»

[Aspetta.]

«No. Qui bloccare il pagamento violerebbe il requisito best-effort. Il problema è che il fallimento della notifica non è osservabile attraverso un evento dedicato.

La prova crea un notifier che fa revert, esegue release e registra i log. Il seller riceve comunque cento. Compare l'evento Released, ma nessun evento che descriva il fallimento della notifica.»

[Apri `test_F05_NotifierFailureIsSilentButSettlementContinues`.]

«Il mock del token non emette eventi Transfer, quindi il test trova un solo log. Non generalizziamo quel conteggio a qualsiasi ERC-20: dipende dalla fixture del laboratorio.»

```bash
bash demo.sh policy
```

**Risultato atteso:** due test PASS: setter oracle accessibile allo stranger e fallimento della notifica silenzioso nonostante il settlement riesca.

«Abbiamo così quattro finding di sicurezza e un'osservazione sull'osservabilità. Nel dossier sono classificati F-01 e F-02 Medium, F-03 e F-04 High, F-05 Informational. Le etichette sono motivate dai casi di questo progetto: non sono una tabella universale per ogni oracle o notifier.»

## 7. Review della correzione: fare previsioni prima di leggere le asserzioni

[Apri `src/fixed/EscrowFinalFixed.sol`. Per ogni caso chiedi il risultato prima di aprire `test/regression/FixedRegression.t.sol`.]

«Adesso confrontiamo il requisito con il comportamento corretto. Voglio prima la previsione, poi il test che la controlla.»

| Scenario | Risultato richiesto sulla versione corretta |
| --- | --- |
| Richiesti 100, ricevuti 90 | Credito 90 |
| Prezzo vecchio esattamente un'ora | Accettato |
| Token restituisce false nel payout | Revert e ripristino di Funded e del credito |
| Estraneo cambia oracle | Revert; oracle invariato |
| Notifier fa revert | Settlement riuscito ed evento di fallimento |
| Contratto in pausa, buyer chiede refund | Rimborso ancora disponibile |

«La gestione sicura del token converte anche il `false` in un revert. Così il rollback annulla gli aggiornamenti anticipati dello stato.

Per l'oracle vengono controllati prezzo, timestamp zero o futuro ed età. Il confronto della freshness resta maggiore stretto, perché il confine esatto è accettato dalla specifica della 17.

Il notifier viene chiamato dentro un try/catch e il suo fallimento produce un evento. Per questa dipendenza il comportamento desiderato è proseguire.

Vedete quindi due policy diverse per due chiamate esterne nella stessa funzione: pagamento obbligatorio, notifica opzionale.»

```bash
bash demo.sh retest
```

**Risultato atteso:** sei regressioni PASS, corrispondenti ai sei scenari della tabella. La suite completa contiene altre regressioni: questa demo ne seleziona sei per la discussione.

### La pausa, con un esempio concreto

«Il buyer ha depositato cento. Il pauser segnala un'emergenza e blocca il contratto. Deposit e release non devono procedere. Refund invece deve restare disponibile al buyer.

Se aggiungessimo automaticamente il controllo della pausa a tutte le funzioni, romperemmo proprio questa via d'uscita. Più controlli non significa sempre maggiore aderenza alla specifica.»

### Dove finiscono le commissioni?

[Scrivi un esempio con token standard.]

```text
Deposito: 100
Fee dell'escrow: 5%
Payout al seller: 95
Token rimasti nell'escrow: 5
Credito terminale: 0
```

«La fee dell'escrow è distinta dalla fee applicata dal token al trasferimento.

Qui i cinque token restano nel contratto. La specifica non definisce ancora chi possa riceverli e con quale meccanismo. Questo va scritto come domanda di design aperta: destinatario, contabilizzazione, riscossione e gestione dei residui.

Non inventiamo in silenzio un destinatario per far sembrare completo il progetto. E notate che saldo uguale a liability non è una proprietà universale: dopo il settlement possiamo avere una fee residua e liability zero.»

**Altra domanda aperta:** «Accreditare il ricevuto risolve l'ingresso di un token tassato. Se anche il trasferimento in uscita trattiene una fee, quanto deve ricevere il seller? La policy in uscita va ancora definita: il balance delta in ingresso non risponde a questa domanda.»

## 8. Fuzz e invariant: quali prove aggiungono?

[Apri `test/fuzz/FinalFuzz.t.sol`.]

«Le quattro prove fuzz fanno variare importo del deposito standard, fee, età del prezzo e caller del setter oracle.

Per la fee esploriamo entrambi i lati del limite: fino a mille deve essere accettata, oltre mille deve essere rifiutata.

Per il caller escludiamo owner con `assume`: tutti gli altri indirizzi generati devono ricevere l'errore di autorizzazione. Ricordate la 14: siamo noi a scegliere il dominio e il risultato atteso.»

[Apri `test/invariant/FinalInvariant.t.sol`, prima l'handler e poi le proprietà.]

«L'handler combina sei azioni: deposit, release, refund, pause, unpause e setFee.

Le proprietà controllano che il credito Funded sia coperto, che negli stati terminali sia zero, che lo stato non si riapra, che la fee resti nel limite e che il seller non riceva più del credito registrato dal modello.»

```bash
bash demo.sh invariant
```

**Risultato atteso:** campagna PASS con cinque proprietà. La configurazione usa 128 run e depth 64. Non confondere le chiamate generate con altrettante transizioni utili.

### Il limite da far riconoscere agli studenti

[Mostra `FinalHandler.release`, dove il mock oracle viene aggiornato prima della chiamata.]

«Prima di release, l'handler rende il prezzo fresco. Quindi questa campagna non esplora il comportamento con prezzi scaduti: lo verifichiamo con regressioni e fuzz dedicati.

Inoltre `setFee` cattura i revert. Questo permette di continuare dopo un valore fuori limite, ma da solo non dimostra che ogni valore valido sia stato accettato: serve il fuzz specifico che distingue i due rami.

Anche la variabile `credited` ha un limite: legge il credito assegnato dall'escrow. È utile come memoria del tetto di pagamento, ma non è da sola una verifica indipendente del deposito. Per quello confrontiamo credito e saldo e manteniamo i test sul balance delta.

Leggere un handler fa parte della review. Il nome dell'invariante non basta a sapere quanto sia forte la prova.»

**Esercizio orale:** «Quale azione aggiungereste per studiare un problema oggi escluso?»

**Risposta possibile:** cambiare l'oracle con ruoli realistici, introdurre timestamp stale, oppure configurare un fallimento del token. Per ciascuna aggiunta occorre dichiarare chi ha quel potere e quali proprietà cambiano. Non dare a un utente normale poteri da owner per comodità del test.

## 9. Governance: onlyOwner non dimostra un ritardo

[Apri `test/governance/TimelockExtension.t.sol`.]

«Abbiamo corretto il setter con onlyOwner. Ora qualcuno ci dice: “L'oracle potrà cambiare soltanto dopo due giorni”. Possiamo verificarlo guardando soltanto quel modifier?

No. Dobbiamo sapere chi è owner e come arriva alla chiamata.

Nell'estensione del laboratorio l'owner dell'escrow è il contratto timelock. Il proposer programma l'operazione; dopo il ritardo, l'executor può eseguirla; il timelock chiama l'escrow.»

```text
Proposer → schedule
              ↓ attesa di 2 giorni
Executor → Timelock.execute → Escrow.setOracle
                             msg.sender = timelock
```

«Ci servono tre prove. La prima: il proposer non deve poter saltare il timelock chiamando direttamente l'escrow. La seconda: un'operazione programmata non può essere eseguita prima del ritardo. La terza: quando il ritardo è trascorso, deve poter riuscire.»

[Mostra i tre test e `vm.warp(block.timestamp + DELAY)`.]

«`vm.warp` cambia il tempo dell'ambiente di test. Non modifica il ritardo del contratto e non è un potere disponibile al proposer in produzione.

Il nome `multisig-proposer` assegnato all'indirizzo nel test è un'etichetta. Non stiamo eseguendo o auditando un multisig reale.»

```bash
bash demo.sh verifica-finale
```

**Risultato atteso:** sette test PASS: quattro fuzz e tre prove di governance. Questa selezione non include la campagna invariant, richiamata dal comando precedente.

«La conclusione riguarda il controller locale e questi percorsi. Signer, soglia di un multisig reale e sicurezza operativa restano fuori scope.»

## 10. Scrivere il report e lasciare visibili le domande aperte

[Ora apri `audit/report.md`.]

«Possiamo finalmente leggere il report e confrontarlo con il ragionamento fatto in aula.

Per ogni voce dovremmo saper tornare alla proprietà, alla funzione, alla prova e alla regressione. Se una riga del report non ha questo collegamento, è troppo vaga o manca evidenza.

Nel riepilogo i problemi principali sono il payout dichiarato riuscito senza pagamento e la sostituzione non autorizzata dell'oracle. Abbiamo poi accounting nominale, dati scaduti e osservabilità della notifica.

Il report conserva anche le domande aperte: destinazione delle fee, semantica dei token tassati in uscita e controller reale dell'owner. Non spariscono perché la suite passa.»

**Esempio di paragrafo conclusivo da far scrivere:**

«La review ha riprodotto i problemi descritti nei finding e verificato le correzioni nel modello locale attraverso regressioni, fuzz e campagne stateful. Restano da definire la destinazione delle commissioni e la policy dei trasferimenti tassati in uscita. La verifica non comprende provider reali, chiavi, proxy, MEV o multisig reali. Le evidenze sostengono le conclusioni entro questo perimetro.»

«Notate che il paragrafo dice che cosa sappiamo e che cosa resta da decidere. Non promette che sia impossibile trovare altri problemi.»

## 11. Consegna finale agli studenti

«Per completare il progetto, consegnate un mini report di due-quattro pagine. Il materiale di soluzione rimane disponibile, ma prima scrivete la vostra versione.

Il report deve identificare il codice e le modifiche revisionate, riassumere attori e regole, documentare almeno un finding completo, spiegare come lo avete ritestato e dichiarare i limiti.

Scegliete poi una domanda aperta sulle fee o sulla governance. Scrivete la decisione che manca e quale test servirebbe dopo averla presa.»

[Mostra la griglia prima che lavorino.]

| Elemento | Criterio di completamento |
| --- | --- |
| Scope | File, versione o snapshot identificabile, inclusioni ed esclusioni |
| Proprietà | Una frase verificabile, collegata alla specifica della 17 |
| Finding | Causa, caller, prerequisiti, conseguenza e PoC |
| Severità | Motivazione in termini di impatto e condizioni |
| Retest | Scenario vulnerabile e risultato corretto, senza cancellare il target |
| Limiti | Almeno una capacità esclusa dall'handler e una domanda di design aperta |

**Soluzione minima del finding F-03, per correggere gli elaborati:** il buyer chiama release su un escrow Funded; il token restituisce false senza pagare; il target ignora il risultato e resta Released con credito zero; seller zero e saldo escrow cento dimostrano il falso successo. Il fixed deve rilevare il false e fare revert, ripristinando stato e credito. Scrivere soltanto “usare SafeERC20” non sostituisce la spiegazione della causa e della prova.

[Ulteriori tracce](exercises/README.md) · [Worksheet di triage](exercises/TriageWorksheet.md)

## 12. Chiusura del corso, pronta da leggere

«Abbiamo iniziato il percorso imparando a seguire una transazione, distinguere caller, stato e chiamate esterne. Ora abbiamo usato quegli elementi per capire un sistema, formulare ipotesi, dimostrarle e revisionare una correzione.

Il metodo che dovete portare via è questo: partite da una regola concreta, seguite il codice che dovrebbe applicarla, cercate una situazione che la mette in crisi e controllate effetti reali, non soltanto nomi o eventi.

Quando trovate un problema, rendetelo riproducibile. Quando valutate una patch, controllate sia l'attacco sia l'uso legittimo. Quando scrivete il report, dichiarate il perimetro e le domande rimaste aperte.

Un buon risultato finale è un ragionamento che un'altra persona può controllare, dal requisito all'ultima asserzione.»

### Ultime domande

| Domanda | Risposta |
| --- | --- |
| Il fixed deve rifiutare un prezzo vecchio esattamente un'ora? | No: nella 17 il confine è incluso. |
| CEI basta se ignoriamo false dal token? | No: manca la gestione del fallimento applicativo. |
| Correggere setOracle significa che abbiamo verificato un multisig? | No: vanno verificati controller e percorsi reali. |
| Il balance delta risolve anche la fee in uscita? | Non definisce quanto debba ricevere il destinatario: serve una policy. |
| Il progetto è pronto per produzione perché passano i test? | È una remediation didattica con limiti e domande aperte documentati. |

**Se hai poco tempo:** svolgi accounting e falso payout con i numeri; usa la tabella del retest per gli altri casi; conserva il confronto tra specifiche, il bypass diretto del timelock e la consegna finale. Evita di leggere tutti i test uno dopo l'altro.

## Promemoria operativo del docente

`bash demo.sh help` mostra le selezioni. `bash demo.sh check` richiama la suite completa di 31 test; nel riepilogo locale la campagna invariant è aggregata, pur mostrando cinque proprietà. Le demo non richiedono wallet, chiavi o RPC.

Se una demo non parte, leggi il test e ricostruisci i numeri del copione. Le percentuali di coverage e le spunte dei dossier sono registrazioni del lavoro precedente, non misurazioni appena eseguite. Il commit storico indicato nello scope va distinto dallo snapshot e dalle modifiche locali di un nuovo audit. La libreria `SafeERC20Lite` e il timelock del laboratorio sono implementazioni didattiche: le prove qui discusse non costituiscono una review universale di tutte le loro integrazioni.
