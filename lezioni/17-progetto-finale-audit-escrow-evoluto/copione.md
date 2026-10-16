# Lezione 17 — Progetto finale: audit dell'Escrow evoluto

Copione esteso per una sessione di audit dall'inizio alla fine, con esercizi e soluzioni. **Il testo tra caporali («…») è pronto da dire; le parentesi quadre indicano cosa mostrare o far fare.** Prima di aprire una soluzione, lascia agli studenti il tempo indicato per ragionare. Se nessuno risponde, scomponi la domanda in caller, stato e saldo, poi usa il calcolo già svolto qui.

[Laboratorio](README.md) · [Appunti di approfondimento](teoria.md)

**Accessi rapidi:** [Tempi e preparazione](#come-distribuire-il-tempo) · [Specifiche e sistema](#2-prima-di-cercare-bug-cinque-differenze-rispetto-alla-16) · [Accounting](#3-esercizio-uno-quanti-token-dobbiamo-registrare) · [Falso payout](#4-esercizio-due-released-significa-che-il-seller-è-stato-pagato) · [Patch](#7-review-della-correzione-fare-previsioni-prima-di-leggere-le-asserzioni) · [Governance](#9-governance-onlyowner-non-dimostra-un-ritardo) · [Report](#10-scrivere-il-report-e-lasciare-visibili-le-domande-aperte) · [Consegna](#11-consegna-finale-agli-studenti)

Dalla radice del repository:

```bash
cd lezioni/17-progetto-finale-audit-escrow-evoluto
```

Rimani qui per tutti i comandi. Apri `src/EscrowFinal.sol` e `audit/scope.md`. Tieni inizialmente chiusi `audit/report.md`, `audit/findings/` e la versione corretta. I commenti del target contengono già indicazioni sui difetti: l'esercizio è motivarli e provarli, non fingere una ricerca alla cieca.

**La sessione guidata prepara il progetto finale; la consegna autonoma è indicata in fondo.** Non promettere di completare un audit professionale in una sola lezione. Le demo sono facoltative e hanno tutte una lettura su carta.

## Come distribuire il tempo

Il percorso completo richiede **180 minuti, divisibili in due incontri da 90**, esclusa una eventuale pausa. I tempi comprendono confronto, demo e scrittura. Le versioni da 90 e 60 minuti selezionano i passaggi essenziali: il testo integrale è un supporto per il docente, non un monologo da comprimere.

| Passaggio | Esteso: 180 minuti | Guidato: 90 minuti | Sintesi: 60 minuti |
| --- | --- | --- | --- |
| Consegna, regole e lettura (§1–2) | 0–25 | 0–12 | 0–8 |
| Accounting (§3) | 25–45 | 12–25 | 8–17 |
| Payout e freshness (§4) | 45–70 | 25–39 | 17–27 |
| Privilegi, notifier e triage (§5–6) | 70–90 | 39–50 | 27–35 |
| Patch, pausa e fee (§7) | 90–120 | 50–64 | 35–45 |
| Fuzz e handler (§8) | 120–140 | 64–74 | 45–51 |
| Governance (§9) | 140–160 | 74–82 | 51–56 |
| Report, consegna e restituzione (§10–12) | 160–180 | 82–90 | 56–60 |

**Nei due incontri:** termina il primo facendo scrivere il finding F-03; apri il secondo con la previsione del suo retest, prima di mostrare il fixed. Nei tempi brevi sposta a casa lettura trasversale, triage Slither e simulazione dell'handler. Mantieni il caso F-03 completo e le differenze di specifica rispetto alla 16.

### Preparazione e richiamo iniziale

[Prima dell'aula esegui `forge build` e `bash demo.sh check`. Tieni pronti `test/helpers/FinalTestBase.sol` e `src/mocks/FinalMocks.sol`, oltre ai file principali.]

«Ripartiamo da tre domande: che cosa deve fare il sistema, che cosa gli facciamo fare nel test, che cosa osserviamo alla fine? Oggi sarete voi a riempire questi collegamenti.

Nei numeri alla lavagna cento significa cento token. Nei test `100 ether` è un intero scalato di diciotto decimali, usato come quantità del token: non stiamo inviando ETH. `feeBps` è espresso in basis point: cento basis point fanno l'uno per cento, cinquecento fanno il cinque per cento, mille fanno il dieci per cento.

Prima di ogni demo scriviamo la previsione. Se il risultato ci sorprende, torniamo al caller, allo stato e ai saldi. Il nome del test e il colore dell'output vengono dopo.»

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

### Che cosa deve rimanere sul tavolo alla fine

«Ogni coppia tiene una scheda con una proprietà, un'ipotesi, i dati della prova, la causa, il fix atteso e il limite della conclusione. Useremo F-03 come caso completo: il contratto potrebbe dichiarare concluso un pagamento senza aver pagato.

Non apriamo subito la soluzione, ma non fingiamo neppure che i commenti del codice siano segreti. Il vostro compito è trasformare un indizio in una spiegazione che un'altra persona può verificare.»

[Apri `exercises/TriageWorksheet.md`. Mostra i campi ancora vuoti; compilali a mano a mano, evitando di riscrivere l'intero report a ogni demo.]

**Identificazione della review:** lo scope riporta uno snapshot storico. Per gli appunti della sessione registra `git rev-parse HEAD`, `git status --short` e `forge --version`; conserva il diff delle modifiche esaminate e gli eventuali file nuovi. Le demo Foundry non richiedono Anvil: i ruoli e il tempo vengono preparati dai test.

## 2. Prima di cercare bug: cinque differenze rispetto alla 16

[Apri `audit/scope.md`, poi mostra le funzioni del target citate nella tabella.]

«Questo escrow somiglia a quello della lezione 16, ma non ha esattamente le stesse regole. Fermiamoci sulle differenze, perché copiare una correzione senza rileggere la specifica può introdurre un nuovo errore.»

| Decisione | Lezione 16 | Progetto finale, lezione 17 |
| --- | --- | --- |
| Chi può chiamare release | Qualsiasi caller, se le condizioni economiche sono valide | Solo il buyer |
| Fee sul trasferimento in ingresso | Deposito da rifiutare atomicamente | Credito basato sul ricevuto effettivo |
| Età esattamente al limite | Rifiutata | Accettata |
| Ruoli di pausa | Governance o guardian pausano; governance riattiva | Emergency pauser pausa; owner riattiva |
| Operazioni bloccate dalla pausa | Release | Deposit e release; refund resta disponibile |

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

### Seguire una transazione completa prima di cercare il difetto

[Apri il target. Usa token standard, oracle fresco e commissione dell'escrow del 5% come esempio alla lavagna. La fee si imposta con `setFee(500)` da owner; nei test che non la impostano parte invece da zero.]

«Prima il buyer chiama `approve` sul token: autorizza l'escrow a spendere cento, ma i token sono ancora suoi. Poi chiama `deposit(100)`. L'escrow controlla pausa, caller, stato Created e importo non nullo. Chiama il token per ricevere il deposito e registra Funded.

Quando il buyer chiama release, il contratto controlla di nuovo pausa, caller e stato. Legge prezzo e timestamp dall'oracle. Calcola la commissione sul credito: cento per cinquecento diviso diecimila fa cinque. Copia i valori necessari, azzera il credito, scrive Released, chiede il trasferimento di novantacinque al seller e tenta la notifica.

Ogni verbo corrisponde a una riga o a un gruppo di righe. Il prezzo qui è una condizione di validità: non entra nel calcolo dei novantacinque token. Non stiamo convertendo un valore in dollari o effettuando uno swap.»

```text
Created -- deposit del buyer --> Funded -- release del buyer --> Released
                                   |
                                   +-- refund del buyer --> Refunded

Pausa: blocca deposit e release; refund resta raggiungibile da Funded.
```

| Istante, con token standard | Saldo escrow | Credito | Saldo seller | Stato |
| --- | ---: | ---: | ---: | --- |
| Prima del deposito | 0 | 0 | 0 | Created |
| Dopo approve | 0 | 0 | 0 | Created |
| Dopo deposit(100) | 100 | 100 | 0 | Funded |
| Dopo release con fee 5% | 5 | 0 | 95 | Released |
| Oppure refund senza release | 0 | 0 | 0 | Refunded |

«Nel ramo refund il buyer recupera cento; quel ramo è alternativo alla release. Nel ramo release restano cinque token: li riprenderemo come domanda sulla destinazione delle commissioni. Una variabile azzerata non spiega da sola che cosa è successo agli asset.»

### Dalle funzioni alle scritture e ai poteri

[Tre minuti: chiedi alla classe tutte le funzioni capaci di cambiare credito, stato, oracle e fee. Poi mostra la mappa.]

| Elemento | Dove cercare | Controllo da motivare |
| --- | --- | --- |
| `escrowedAmount`, `state` | `deposit`, `release`, `refund` | Credito coperto e una sola uscita riuscita |
| `oracle` | constructor, `setOracle` | Scelta della dipendenza riservata a owner |
| `feeBps` | `setFee`, lettura in `release` | Owner autorizzato, massimo 1.000 bps |
| `paused` | `pause`, `unpause`; letture in deposit/release | Ruoli distinti e rimborso possibile |
| Token, oracle, notifier | Tutte le chiamate esterne | Che cosa succede se mentono, falliscono o richiamano? |

«`owner`, `emergencyPauser` e `notifier` sono variabili ordinarie, ma in questa versione non hanno setter dopo il constructor. Non deduciamo un percorso di modifica dalla sola assenza di `immutable`: cerchiamo gli assegnamenti realmente esposti.

Il token è un confine di fiducia: l'interfaccia ci dice come chiamarlo. L'accounting dipende anche dalla correttezza dei saldi che restituisce. I mock isolano comportamenti specifici; non costituiscono un modello di ogni token possibile.»

**Checkpoint:** «Quale differenza c'è fra il buyer che chiama deposit e l'escrow che chiama transferFrom?» **Risposta:** sul primo contratto `msg.sender` è buyer; sul token è escrow, che deve spendere l'allowance concessa a lui. Il chiamante cambia a ogni chiamata esterna.

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

### Perché misuriamo una differenza e non il saldo totale

«Supponiamo che nell'escrow ci siano già sette token arrivati fuori dal normale deposito. Poi il trasferimento richiesto di cento ne porta novanta. Il saldo finale è novantasette, ma il credito di questo deposito è novanta: novantasette meno sette.

Assegnare il saldo totale attribuirebbe al buyer anche asset preesistenti. Assegnare il richiesto attribuirebbe cento quando sono arrivati novanta. Il delta risponde alla domanda giusta: quanto è aumentato il saldo in questa operazione, sotto le assunzioni del token supportato?»

**Nota per il docente:** questo secondo esempio è un ragionamento su carta. La PoC e la regressione fornite partono da saldo escrow zero; non presentare il caso dei sette token come un test già incluso.

### Ricostruire gli helper prima di interpretare la PoC

[Apri `_fundTarget` in `test/helpers/FinalTestBase.sol`.]

«L'helper conia cento al buyer, imposta il buyer come caller, autorizza l'escrow e deposita. La fee è nel comportamento del token, non in un prelievo che facciamo a mano dopo il deposito.

Le asserzioni confrontano due fonti: saldo nel token e credito nell'escrow. F-01 prova la discrepanza; a differenza di AUD-02 della 16, questo test non tenta anche il payout. Quella conseguenza va provata separatamente se vogliamo descriverla come risultato eseguito.»

**Risposta da far completare:** «Mi aspetto credito uguale al ricevuto; il codice registra il richiesto; preparo un token con fee 10% e deposito cento; osservo saldo novanta e credito cento; dopo il fix entrambi devono essere novanta.»

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

### Tre esiti da non confondere

| Comportamento del token | Che cosa vede la chiamata | Decisione necessaria nell'escrow |
| --- | --- | --- |
| Trasferisce e restituisce `true` | Ritorno normale con conferma | Proseguire, nel modello del token supportato |
| Restituisce `false` senza trasferire | Ritorno normale con esito negativo | Rilevare il false e annullare il settlement |
| Fa revert | La chiamata fallisce | Propagare il fallimento del pagamento obbligatorio |

«Un ritorno `false` non è un'eccezione. Se il chiamante lo ignora, l'EVM non può indovinare che quel valore significhi “pagamento non riuscito”. La regola ERC-20 chiede proprio al chiamante di gestirlo.

Apriamo `FalsePayoutToken`: il deposito usa il trasferimento ordinario ereditato, mentre il trasferimento in uscita restituisce false. Così isoliamo il punto di payout. Se anche il setup fallisse, non arriveremmo allo stato Funded che vogliamo studiare.»

**Riferimento per il docente:** [specifica ERC-20, gestione del risultato booleano](https://eips.ethereum.org/EIPS/eip-20#methods).

[Traccia i passaggi del target: credito 100 → copia locale gross 100 → credito 0 → Released → transfer restituisce false → prosecuzione.]

«L'ordine CEI risolve un problema di stato osservabile durante le chiamate esterne. Non decide se il loro risultato rappresenti un successo. In questo caso abbiamo un ordine ragionevole e una gestione dell'esito sbagliata.

Quando la chiamata principale termina, refund richiede ancora Funded e quindi non è più il normale percorso d'uscita. I token sono rimasti nel contratto. Per dire che sono stati trasferiti a un attaccante ci servirebbe un'altra prova.»

**Domanda di controllo:** «L'evento Released sarebbe sufficiente a certificare il pagamento?» **Risposta:** no, è emesso dal contratto che stiamo verificando e può descrivere una conclusione sbagliata. In questa prova lo confrontiamo con i saldi effettivi del mock token.

### Lo stesso percorso usa un prezzo scaduto

[Mostra la lettura dell'oracle e la riga `updatedAt;`.]

«Il contratto legge prezzo e timestamp, ma usa soltanto il prezzo. Scrivere il nome della variabile su una riga non significa validarla.

La prova F-02 prepara un prezzo positivo di due ore fa. Il limite è un'ora, quindi release dovrebbe essere rifiutata. Il target invece paga il seller.»

```bash
bash demo.sh payout
```

**Risultato atteso:** due test PASS. F-03 registra Released senza pagare; F-02 permette il pagamento con il prezzo di due ore fa. Sono cause diverse e rimangono finding distinti.

### Freshness: separare valore, validità del timestamp ed età

«Il prezzo positivo risponde a una domanda. Il timestamp non nullo e non futuro risponde a una seconda. L'età entro un'ora risponde a una terza. Nessuna delle tre sostituisce le altre.

Immaginiamo che adesso siano le 12:00:00. Un campione delle 11:00:01 ha 3.599 secondi; delle 11:00:00 ha 3.600; delle 10:59:59 ha 3.601. Nella 17 i primi due sono ammessi, il terzo no. Nella 16 il caso esatto era già scaduto.»

| Caso, con prezzo positivo | Risultato richiesto nella 17 | Evidenza disponibile |
| --- | --- | --- |
| Età 3.600 secondi | Accettare | Regressione dedicata al confine |
| Età 3.601 secondi | Rifiutare | Regressione stale |
| Età fra 0 e 7.200 secondi | Scegliere il ramo secondo la regola | Fuzz della freshness |
| Timestamp zero o futuro | Rifiutare | Controllo nel fixed; manca una regressione dedicata nella suite fornita |

«Il fuzz genera età e sottrae dal tempo attuale: non sta generando timestamp futuri. Non possiamo usare il suo nome per sostenere che copra ogni dato oracle invalido. La checklist del dossier va letta insieme alle prove concrete.»

**Raccordo:** «Ora vediamo chi può modificare proprio la dipendenza da cui leggiamo quel prezzo.»

## 5. Privilegi: chi può scegliere l'oracle?

[Mostra `setOracle`. Dai un minuto per completare le quattro frasi del formato iniziale.]

«La proprietà prevista è: soltanto owner può cambiare l'oracle.

Il codice assegna il nuovo indirizzo senza controllare il caller. La prova impersona un estraneo, chiama `setOracle` e legge l'indirizzo salvato. È sufficiente per dimostrare la violazione del controllo di accesso.»

[Apri `test_F04_StrangerCanReplaceOracle`.]

«Facciamo attenzione alla conclusione. Questo test dimostra che l'estraneo sostituisce l'oracle. Non dimostra che l'estraneo possa chiamare direttamente release: release resta riservata al buyer.

Il rischio è che una dipendenza economica possa essere scelta da un soggetto non autorizzato, influenzando le operazioni successive. Nel finding separiamo la capacità dimostrata dalle conseguenze che richiedono ulteriori passaggi.»

### Provare il percorso negativo senza chiudere quello legittimo

«La regressione dovrà usare uno stranger e aspettarsi `OnlyOwner`. Ma immaginiamo un fix che faccia revert per chiunque: bloccherebbe anche governance. Serve quindi anche un percorso autorizzato che riesca; lo rivedremo nella suite del timelock.

La prova F-04 non ha bisogno di un deposito: per mostrare la scrittura non autorizzata basta un escrow creato e un oracle sostitutivo. Un setup minimo rende più leggibile la causa. Aggiungeremmo fondi e release se volessimo dimostrare uno specifico effetto economico successivo.»

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

### Passata Slither: collegare un segnale a una prova

[Apri `audit/static-analysis.md`. Esegui i comandi soltanto se hai preparato l'ambiente Slither del README. Il ragionamento sul dossier è disponibile anche senza lo strumento.]

```bash
bash scripts/slither-printers.sh
bash scripts/slither-target.sh
```

«`unchecked-transfer` richiama la nostra attenzione sui ritorni ignorati in deposit, release e refund. Il detector individua una struttura; il test F-03 dimostra il falso successo con un comportamento preciso del token.

`unchecked-lowlevel` sulla notifica richiede invece di rileggere la policy. Qui il settlement deve tollerare il normale fallimento, ma il fallimento deve essere osservabile. La stessa abitudine di ignorare un esito può avere conseguenze diverse in due punti del contratto.

La riga `updatedAt;` è un indizio di un valore inutilizzato. Il test con il campione di due ore fa dimostra la violazione della freshness. Infine F-04, il setter oracle aperto, non emerge dai detector registrati in questo pass: lo troviamo ricostruendo i privilegi.»

| Segnale | Domanda concreta | Evidenza da collegare |
| --- | --- | --- |
| Ritorno token ignorato | Può chiudere senza pagare? | F-03, quattro asserzioni su stato e saldi |
| Timestamp inutilizzato | Un dato oltre un'ora permette release? | F-02 |
| Esito notifier ignorato | Quale evento informa del fallimento? | F-05 |
| Nessun alert dedicato a `setOracle` nel pass | Chi può scrivere l'indirizzo? | Review manuale e F-04 |

«I conteggi e le versioni nel dossier appartengono al pass storico dichiarato. Una nuova esecuzione può avere numeri diversi. Valutiamo i contenuti e i filtri, senza prendere il calo degli alert come criterio di chiusura.»

**Nota operativa:** sul target gli alert sono attesi. Leggi l'output prima di interpretare un exit code non zero; compilazione fallita, tool assente e finding rilevati richiedono azioni diverse.

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

### F-03 dalla prima istruzione al rollback

[Apri `SafeERC20Lite._callOptionalReturn`, poi `test_F03_FalseReturnTransferCannotFinalize`. Non serve leggere l'assembly riga per riga per capire questa prova.]

«`using SafeERC20Lite for IERC20Final` ci permette di scrivere `token.safeTransfer`. La libreria prepara la chiamata al token, distingue il successo della chiamata dal valore restituito e rifiuta il false.

Nel nostro caso release aveva già scritto credito zero e Released. La libreria riceve false, genera `SafeTransferFailed` e il revert risale fino a release. Le scritture di quella chiamata vengono annullate: torniamo a Funded con credito cento. Il deposito fatto prima non viene cancellato.

Il test controlla l'errore specifico con l'indirizzo del token e poi legge stato e credito. Sono le sue asserzioni effettive. I saldi sono coerenti con il comportamento del mock, che non trasferisce, ma questa regressione non li riafferma: se vogliamo renderli parte esplicita dell'evidenza, sono due asserzioni ulteriori da aggiungere nell'esercizio.»

| Momento nella release del fixed | Stato | Credito | Cosa sta accadendo |
| --- | --- | ---: | --- |
| Ingresso | Funded | 100 | Condizioni iniziali valide |
| Prima del token | Released | 0 | Effects eseguiti |
| Ritorno `false` | Released, provvisorio | 0, provvisorio | Wrapper rileva il fallimento |
| Dopo il revert osservato dal test | Funded | 100 | Effects annullati |

«La libreria contempla anche il ritorno vuoto di alcuni token e controlla che il destinatario della chiamata abbia codice. Qui stiamo seguendo la prova del false: non tutte le diramazioni della libreria hanno una regressione dedicata in questa suite.

Il punto non è memorizzare il nome di una libreria: è sapere quale esito interpreta, quale errore produce e quale stato rimane dopo il fallimento.»

**Riferimento per il docente:** la distinzione fra revert propagato, fallimento intercettato e chiamata a basso livello è descritta nella [documentazione Solidity sulla gestione degli errori](https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions). Nei test qui descritti il wrapper rende il false un revert della release.

### Cercare la stessa causa negli altri percorsi

«Abbiamo trovato un risultato ignorato nel payout: ora torniamo a deposit e refund. Anche lì il target ignora il ritorno del token; il fixed usa il wrapper in tutti e tre i percorsi.

La PoC F-03 dimostra release, non ogni variante di refund o deposito fallito. Annotiamo le altre occorrenze e decidiamo quali prove aggiungere. È un passaggio utile della remediation review: verificare se la causa esiste in più punti, senza moltiplicare artificialmente i finding e senza estendere a parole il test oltre ciò che fa.»

```bash
forge test --offline --match-contract '^FixedRegressionTest$' -vv
```

**Risultato atteso:** tutte le diciotto regressioni. La suite verifica anche depositi legittimi, rifiuto di caller errati, importo zero, doppio deposito, chiusure e ruoli di pausa. I sei casi della demo sono una selezione didattica.

### La pausa, con un esempio concreto

«Il buyer ha depositato cento. Il pauser segnala un'emergenza e blocca il contratto. Deposit e release non devono procedere. Refund invece deve restare disponibile al buyer.

Se aggiungessimo automaticamente il controllo della pausa a tutte le funzioni, romperemmo proprio questa via d'uscita. Più controlli non significa sempre maggiore aderenza alla specifica.»

[Fai ragionare separatamente su stato e pausa.]

| Situazione | Azione del buyer | Previsione nel fixed |
| --- | --- | --- |
| Created, pausa attiva | deposit | Revert per pausa |
| Funded, pausa attiva | release | Revert per pausa |
| Funded, pausa attiva | refund | Rimborso possibile con token funzionante |
| Refunded, pausa rimossa | deposit | Revert per stato: unpause non riapre il ciclo |

**Distinzione sull'evidenza:** la regressione sul refund in pausa verifica esplicitamente la terza riga. Le altre sono previsioni dalla lettura delle guardie: l'handler evita deposit/release in pausa e quindi non prova il loro revert. Sono buoni casi per l'esercizio sulla pause semantics.

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

### Esempio con le due commissioni insieme

«Separiamo bene i soggetti. Il token del mock trattiene il dieci per cento di ciascun trasferimento. L'escrow, per questo esempio, trattiene il cinque per cento del credito come propria commissione.»

```text
Richiesta del buyer                                  100
Fee del token in ingresso: 10%                        10
Credito misurato nel fixed                            90
Fee dell'escrow: 5% di 90                            4,5
Importo richiesto al token per il seller             85,5
Fee del token in uscita: 10% di 85,5                 8,55
Ricevuto effettivamente dal seller                  76,95
Saldo residuo nell'escrow                            4,5
```

«La contabilità dell'ingresso è corretta, ma il destinatario non riceve 85,5. Dobbiamo decidere che cosa promette il prodotto e quali asset ammette. Il codice del mock consente di calcolare questo esempio; non è uno scenario già eseguito dalla demo F-01, che si ferma al deposito.

La divisione nel contratto è intera e tronca nelle unità minime del token. Questi numeri sono esatti con la scala del laboratorio; per importi molto piccoli servono casi di arrotondamento dedicati.»

**Ulteriore domanda da affidare ai più esperti:** la fee viene letta al momento della release e owner può cambiarla anche dopo il deposito. È il comportamento desiderato oppure la fee dovrebbe essere fissata all'ingresso? Non chiamarlo automaticamente vulnerabilità: formula il requisito mancante e il test che lo distinguerebbe.

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

### Simulare una sequenza a mano

[Per interpretare il lavoro della campagna, fai seguire questa sequenza. Usa cento token standard e fee zero iniziale.]

| Azione dell'handler | Effetto atteso | Perché conta |
| --- | --- | --- |
| `pause` | Pausa attiva, stato Created | Il pauser è impersonato dall'handler |
| `deposit(100)` | Nessuna chiamata a deposit dell'escrow | L'handler torna subito perché è in pausa |
| `unpause`, poi `deposit(100)` | Funded, credito 100 | Ora l'azione economica è raggiunta |
| `setFee(500)` | Fee 5% | Il setter usa owner |
| `release` | Seller 95, credito 0, residuo 5 | L'handler rende prima fresco l'oracle |
| `refund` | Nessuna chiamata all'escrow | Il filtro trova uno stato già terminale |

«Questa sequenza mostra perché il conteggio delle chiamate all'handler non coincide con quello delle operazioni dell'escrow. Alcune azioni tornano senza fare nulla. Dopo una chiusura, molte azioni economiche vengono filtrate.

La proprietà `TerminalStateNeverReopens` osserva che non si torna da terminale a non terminale. Non dimostra da sola che qualsiasi tentativo vietato faccia revert: per esempio, qui l'handler non prova refund dopo Released. La regressione dedicata lo chiama davvero e ne controlla l'errore.

Anche seller minore o uguale a credited è un limite superiore. Seller zero lo soddisfa: non prova il pagamento dovuto. Le prove deterministiche di release controllano il successo effettivo. Usiamo insieme proprietà di sicurezza e percorsi che dimostrano che il servizio funziona.»

**Checkpoint:** chiedi di citare una capacità esclusa e il test complementare. Esempio: oracle stale escluso dall'handler → fuzz freshness e regressione stale; payout false escluso dal token standard → regressione F-03.

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

### Il collegamento che rende effettivo il ritardo

«Apriamo il constructor usato dal test: l'owner passato all'escrow è `address(timelock)`. Creare un timelock accanto all'escrow, lasciando owner al proposer, non obbligherebbe a passare dal ritardo.

Schedule registra un'operazione identificata da target, calldata e salt. La calldata contiene il setter e il nuovo indirizzo oracle. Execute deve ritrovare la stessa operazione, già programmata e pronta. Il tempo iniziale del test è 1.000.000; due giorni sono 172.800 secondi; l'istante pronto è quindi 1.172.800. Il test positivo avanza esattamente a quel valore.

Quando executor chiama execute, il timelock vede executor. Quando il timelock chiama setOracle, l'escrow vede timelock. È questo secondo caller a soddisfare OnlyOwner.

Queste tre prove controllano bypass diretto, esecuzione troppo precoce ed esecuzione a ritardo trascorso. Il contratto contiene anche altri controlli, per esempio sull'operazione già eseguita; non li presentiamo come test dedicati se non li abbiamo aggiunti.»

**Domanda:** «Il ritardo garantisce che il nuovo oracle sia corretto?» **Risposta:** no, garantisce una condizione temporale nel percorso verificato. La qualità della dipendenza e la decisione di governance richiedono altre verifiche.

## 10. Scrivere il report e lasciare visibili le domande aperte

[Ora apri `audit/report.md`.]

«Possiamo finalmente leggere il report e confrontarlo con il ragionamento fatto in aula.

Per ogni voce dovremmo saper tornare alla proprietà, alla funzione, alla prova e alla regressione. Se una riga del report non ha questo collegamento, è troppo vaga o manca evidenza.

Nel riepilogo i problemi principali sono il payout dichiarato riuscito senza pagamento e la sostituzione non autorizzata dell'oracle. Abbiamo poi accounting nominale, dati scaduti e osservabilità della notifica.

Il report conserva anche le domande aperte: destinazione delle fee, semantica dei token tassati in uscita e controller reale dell'owner. Non spariscono perché la suite passa.»

**Esempio di paragrafo conclusivo da far scrivere:**

«La review ha riprodotto i problemi descritti nei finding e verificato le correzioni nel modello locale attraverso regressioni, fuzz e campagne stateful. Restano da definire la destinazione delle commissioni e la policy dei trasferimenti tassati in uscita. La verifica non comprende provider reali, chiavi, proxy, MEV o multisig reali. Le evidenze sostengono le conclusioni entro questo perimetro.»

«Notate che il paragrafo dice che cosa sappiamo e che cosa resta da decidere. Non promette che sia impossibile trovare altri problemi.»

### Scrivere F-03 dall'inizio alla fine

[Lascia quattro minuti per scrivere il finding, poi confronta con questo esempio.]

**Titolo:** il payout ignora `false` e chiude il debito senza trasferire i token.

«In `EscrowFinal.release`, il buyer può avviare un pagamento da Funded con oracle valido. Il contratto azzera il credito e scrive Released, poi ignora il booleano restituito da `token.transfer`. Con `FalsePayoutToken`, che riceve normalmente il deposito ma restituisce false in uscita, un deposito di cento porta a Released con credito zero, seller zero e saldo escrow cento. I normali percorsi successivi richiedono Funded. La causa è la mancata gestione del risultato del trasferimento obbligatorio.

La PoC `test_F03_FalseReturnCreatesFalseTerminalSuccess` dimostra quei quattro valori. Il dossier assegna High per il falso successo terminale e l'indisponibilità dei normali percorsi per i fondi, subordinatamente al comportamento del token descritto. La patch usa il wrapper per annullare la release su false. La regressione `test_F03_FalseReturnTransferCannotFinalize` verifica l'errore e il ripristino di Funded con credito cento. Non stiamo dimostrando un incasso da parte di un attaccante né la compatibilità con ogni ERC-20.»

**Comandi per ripercorrere soltanto questa catena:**

```bash
forge test --offline --match-contract '^TargetFindingsTest$' \
  --match-test '^test_F03_FalseReturnCreatesFalseTerminalSuccess\(' -vvvv
forge test --offline --match-contract '^FixedRegressionTest$' \
  --match-test '^test_F03_FalseReturnTransferCannotFinalize\(' -vvvv
```

«Entrambi devono passare: il primo riproduce il difetto sul target, il secondo controlla la protezione sul fixed. Se cambiassimo la PoC per nascondere il problema originale perderemmo il confronto.»

### Mappa conclusiva delle evidenze

| Finding | Dato decisivo sul target | Cosa cercare nel retest |
| --- | --- | --- |
| F-01 | Saldo 90, credito 100 | Saldo e credito 90 |
| F-02 | Payout con prezzo di due ore fa | Stale rifiutato; limite esatto accettato |
| F-03 | Released, credito 0, seller 0, escrow 100 | Errore del wrapper, Funded e credito 100 |
| F-04 | Oracle riscritto dallo stranger | OnlyOwner per stranger; percorso autorizzato col timelock |
| F-05 | Payout riuscito, solo evento Released nel mock | Payout riuscito ed evento NotificationFailed |

«Un retest è la verifica di una correzione, non un rimpiazzo di tutto lo scope. La suite non assegna una destinazione alle fee e non decide la policy dei token in uscita. Le percentuali storiche di coverage indicano codice eseguito in quel pass: non misurano da sole la qualità delle asserzioni.»

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

### Valutare la comprensione, non la somiglianza al report

Per ogni riga della griglia assegna 0 se manca o è errata, 1 se è corretta ma generica, 2 se è concreta e sostenuta da codice, numeri o prove: massimo 12 punti. Usa il punteggio per il feedback, mantenendo centrali i collegamenti fra requisito, causa e conseguenza.

**Errori da far correggere prima della consegna:** attribuire release allo stranger nella 17; rifiutare il confine di un'ora copiando la 16; dichiarare furto dove si è provato un falso successo; descrivere come eseguito un test soltanto proposto; chiamare multisig un indirizzo etichettato nel setup.

**Domanda di trasferimento, senza soluzione immediata:** «Se domani il prodotto decidesse di rifiutare i fee token, quali parti cambiereste?» **Risposta da usare dopo:** requisito sul deposito, implementazione del controllo sul ricevuto, esito atteso della regressione F-01 e descrizione nel report. Il mock e la prova della discrepanza sul target possono rimanere utili. Non basta cambiare una riga del fixed lasciando una specifica contraddittoria.

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

Se Forge non trova test, controlla il filtro: zero test selezionati non è un retest riuscito. Se manca Slither, usa il triage documentato e dichiara che lo stai leggendo. Durante il percorso su carta conserva sempre previsione, azione e asserzione; annota separatamente ciò che è stato eseguito nella sessione.

Nel percorso esteso, dopo la review della patch puoi usare `bash scripts/slither-fixed.sh` con l'ambiente già preparato. Collega gli alert residui al triage e alle assunzioni del modello; il confronto fra target e fixed riguarda la causa dei problemi, non soltanto il numero di warning.
