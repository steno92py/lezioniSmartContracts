# Lezione 15 — Analisi statica con Slither

Copione da tenere aperto durante la lezione. **Il testo tra virgolette è da dire; le parentesi quadre indicano cosa mostrare o fare.** Le domande includono la risposta. Ogni caso parte da una domanda concreta, segue il codice e arriva a una conclusione circoscritta.

[Laboratorio e codice](README.md) · [Appunti di approfondimento](teoria.md)

Dalla radice del repository:

```bash
cd lezioni/15-analisi-statica-con-slither
```

Rimani in questa cartella. Tieni aperti `src/noisy/StaticLab.sol` e `test/NoisyFindings.t.sol`. Gli altri file si aprono quando indicato.

**Due strumenti, due risultati diversi:** `bash demo.sh ...` esegue test Foundry. `bash scripts/slither-...sh` esegue l'analisi statica. Una demo Foundry riuscita non significa che Slither sia installato o sia stato eseguito. Il repository pinna Slither 0.11.6; la preparazione è nel README del laboratorio. Se non è già disponibile, usa `INVENTORY.md`, `TRIAGE.md` e il codice: non installarlo durante l'aula e non presentare le schede come un output appena generato.

Gli script `scripts/slither-printers.sh`, `scripts/slither-noisy.sh` e `scripts/slither-fixed.sh` cercano prima Slither nell'ambiente locale `.venv-slither`: se è già preparato, non serve attivarlo per usare questi script. Per una nuova installazione segui il README e usa Python 3.10 o superiore; il Python 3.9 fornito da Xcode non può installare la versione fissata. Il README indica Python 3.13 come alternativa e usa il pip dell'ambiente isolato.

## Come distribuire il tempo

I tempi comprendono lettura guidata del codice, una scheda da compilare e discussione: non sono minuti di solo discorso.

| Passaggio | 90 minuti | 60 minuti |
| --- | --- | --- |
| Apertura e distinzione fra strumenti | 0–7 | 0–5 |
| Inventario e lettura di un alert | 7–20 | 5–13 |
| Primo caso: falso successo | 20–33 | 13–23 |
| Secondo caso: chiamata arbitraria e admin | 33–49 | 23–35 |
| Terzo caso: callback e contesto | 49–60 | 35–43 |
| Correzione e regressioni | 60–72 | 43–51 |
| Oracle, triage e filtri | 72–82 | 51–56 |
| Esercizio e chiusura | 82–90 | 56–60 |

## 1. Apertura: dove guardiamo prima di scrivere un test?

«Nelle ultime due lezioni abbiamo imparato a verificare comportamenti precisi e a cercare casi che violano una proprietà.

Oggi partiamo da una situazione diversa. Ci consegnano un contratto che non abbiamo scritto. Prima di avere un test, dobbiamo capire dove cercare.

Possiamo leggerlo manualmente, e continueremo a farlo. Possiamo anche usare uno strumento che analizza la struttura del codice e ci indica operazioni sospette. Oggi useremo Slither.

Analisi statica significa che lo strumento ragiona sul codice e sulla sua rappresentazione, senza dover eseguire una nostra sequenza di transazioni per ogni segnalazione.

Il suo risultato è una lista di punti da investigare. Per ciascuno dobbiamo ancora rispondere: chi può arrivare qui? Che cosa può controllare? Quale comportamento richiesto viene violato? Con quale conseguenza?

Alla fine della lezione voglio che sappiate prendere una segnalazione e arrivare a una di tre conclusioni: problema confermato, ipotesi esclusa nel contesto analizzato, oppure ipotesi ancora da verificare.»

[Scrivi.]

```text
Segnalazione → ipotesi → prova → conclusione
```

«Una segnalazione del tool la chiameremo alert. Un problema che abbiamo analizzato e documentato lo chiameremo finding. Triage è il lavoro che facciamo per decidere come classificare e approfondire le segnalazioni.»

**Domanda:** «Se Slither non segnala nulla, possiamo smettere di leggere il contratto?»

«No. Un tool riconosce certe strutture e certe classi di problemi. La specifica del nostro progetto può contenere regole che lo strumento non conosce. Fra poco vedremo proprio un caso in cui una chiamata funziona perfettamente e produce comunque un risultato non autorizzato.»

## 2. Facciamo una mappa prima di leggere gli alert

[Apri `src/noisy/StaticLab.sol`. Non scorrere tutto velocemente: fermati sulle quattro funzioni.]

«Il contratto del laboratorio si chiama `StaticLab`. È intenzionalmente vulnerabile.

Prima di cercare il bug, facciamo una mappa. Per ogni funzione esterna voglio sapere quattro cose: chi può chiamarla, quali dati sceglie, quale stato cambia e quale altro contratto viene chiamato.

Le funzioni esterne sono i punti da cui qualcuno può entrare nel nostro sistema. Le chiameremo entry point.»

[Costruisci la tabella; usa `INVENTORY.md` solo dopo aver compilato almeno una riga con la classe.]

| Funzione | Chi la chiama | Cosa controlla | Effetto da investigare |
| --- | --- | --- | --- |
| `unsafeExecute` | Qualsiasi caller | Target e dati | Chiamata esterna, poi `completed = true` |
| `arbitraryExecute` | Qualsiasi caller | Target e dati | Chiamata esterna con esito controllato |
| `setAdmin` | Qualsiasi caller | Nuovo admin | Scrive `admin` |
| `readOracle` | Qualsiasi caller | Nessun argomento | Legge dall'indirizzo `oracle` |

«Notate che il nome `setAdmin` non limita chi può chiamare la funzione. Il nome ci suggerisce un'intenzione, ma dobbiamo cercare il controllo nel codice.

Analogamente, il nome `completed` non garantisce che qualcosa sia stato davvero completato. Dobbiamo seguire come viene scritto.»

### Dove entra Slither

«Slither offre detector e printer. Un detector cerca un pattern potenzialmente problematico. Un printer produce una vista del programma: per esempio funzioni accessibili o variabili scritte e controlli di autorizzazione.

I printer ci aiutano a costruire questa mappa. I detector ci aiutano a scegliere alcune domande da approfondire.»

[Se Slither è già pronto, esegui i due comandi separatamente. Altrimenti mostra l'inventario e passa al caso successivo.]

```bash
bash scripts/slither-printers.sh
```

«Qui cerchiamo gli entry point e chi scrive `admin` e `completed`. Non leggiamo ogni riga: seguiamo le variabili che hanno significato per il contratto.»

```bash
bash scripts/slither-noisy.sh
```

«Qui leggiamo i candidati prodotti dai detector. Per ogni segnalazione individuo il nome del detector, la funzione coinvolta e l'operazione indicata. Poi apro quel punto nel sorgente.»

**Come commentare l'output:** cerca `unchecked-lowlevel` associato alla chiamata ignorata in `unsafeExecute`. Se l'output differisce, apri direttamente la funzione; non promettere che ogni scheda del laboratorio corrisponda a un detector. Il compilatore può già segnalare il valore di ritorno ignorato.

«Impact e confidence, quando riportati, sono classificazioni del tool. La gravità del problema nel nostro sistema richiede ancora di conoscere asset, permessi e condizioni necessarie.»

**Raccordo:** «Prendiamo il segnale più semplice: una chiamata esterna di cui ignoriamo il risultato.»

## 3. Primo caso: l'operazione fallisce, il contratto registra successo

[Mostra `unsafeExecute`.]

```solidity
function unsafeExecute(address target, bytes calldata data) external {
    target.call(data);
    completed = true;
}
```

«Queste due righe dicono: chiama il target e poi segna completato.

La domanda è: che cosa succede se il target fallisce?

Questa è una low-level call. Quando il contratto chiamato fa revert, la call restituisce un booleano falso. Il chiamante può decidere come gestirlo. Qui il risultato viene ignorato, quindi l'esecuzione prosegue e scrive `completed = true`.

Pensate a un sistema che debba inviare un pagamento e poi segnare una pratica come pagata. Se ignora l'esito del pagamento, può dichiarare chiusa una pratica che non è stata pagata. Nel nostro laboratorio non abbiamo quella pratica: abbiamo il problema minimo sul flag `completed`.»

[Scrivi la proprietà prima di aprire il test.]

```text
Se questa operazione registra completed = true,
l'azione esterna richiesta deve essere riuscita.
```

«Ora costruiamo una prova. Ci serve un target che fallisce sempre. Non dipendiamo da una rete o da un errore occasionale: usiamo `RevertingAction`, un contratto del test che fa appositamente revert.»

[Apri `test/NoisyFindings.t.sol`, `test_Confirmed_UncheckedCallCreatesFalseSuccess`.]

«Prima creiamo il target. Poi `abi.encodeCall` prepara i dati della chiamata a `run`: indica quale funzione chiamare e con quali argomenti.

Chiamiamo `unsafeExecute`. Infine leggiamo `completed`. Il test controlla che sia vero: sta cercando di dimostrare il comportamento sbagliato.»

```bash
bash demo.sh falso-successo
```

**Risultato atteso:** un test PASS. Nella trace individua il revert di `RevertingAction.run` e il fatto che la chiamata esterna a `unsafeExecute` termina comunque. L'asserzione finale trova `completed == true`.

«Il verde significa che la nostra riproduzione è riuscita. Il problema esiste proprio perché il test che lo descrive passa.

Abbiamo collegato tre elementi: una causa nel codice, un input che la attiva e uno stato finale contrario al requisito. Ora possiamo scrivere un finding.»

**Domanda:** «Basta dire “c'è una call non controllata”?»

«Quello descrive il pattern. Il finding deve aggiungere che il fallimento viene registrato come successo, e spiegare quale parte dell'applicazione si fida di quel risultato. In questo laboratorio dimostriamo il flag errato; non inventiamo un furto che il test non mostra.»

## 4. Secondo caso: la chiamata riesce, ma non avrebbe dovuto essere permessa

[Mostra `arbitraryExecute`, in particolare `require(success, "CALL_FAILED")`.]

«Questa funzione sembra migliore. Controlla `success`: se la chiamata fallisce, fa revert.

Facciamo una previsione: significa che possiamo lasciare a chiunque la scelta del target e dei dati da inviare?»

[Aspetta. Poi costruisci l'esempio.]

«Immaginiamo che `StaticLab` possieda cento token. Un attaccante sceglie come target il contratto del token e come dati una chiamata a `transfer`: destinatario l'attaccante, importo cento.

L'attaccante non chiama direttamente il token. Chiede a `StaticLab` di chiamarlo.»

```text
Attaccante
  → StaticLab.arbitraryExecute(token, transfer(attaccante, 100))
      → token.transfer(attaccante, 100)
```

**Domanda centrale:** «Quando il token esegue `transfer`, chi vede come `msg.sender`?»

«Vede `StaticLab`, perché è il chiamante immediato. E quei cento token appartengono proprio a `StaticLab`.

Per il token il trasferimento è valido. I token vengono spostati, `success` è vero e il `require` passa.

Il controllo dell'esito funziona. Manca il controllo sul potere che abbiamo dato all'utente: gli abbiamo permesso di decidere come il contratto usa i propri asset.»

[Apri `test_Confirmed_ArbitraryCallCanMoveAssetsHeldByLab`. Leggi preparazione, azione e due asserzioni.]

```text
Prima: StaticLab = 100; attaccante = 0
Dopo:  StaticLab = 0;   attaccante = 100
```

«Questo percorso viene spesso descritto come source to sink. La source è l'origine del dato controllato dall'utente: target e calldata. Il sink è l'operazione sensibile che usa quei dati: la chiamata esterna eseguita dal contratto.

Seguiamo anche l'autorità, non soltanto i valori. Lo stesso `transfer` ha effetti diversi a seconda di chi lo chiama.»

### Il caso admin, più corto

[Mostra `setAdmin`.]

«Qui chiunque può scrivere `admin`. Per confermarlo basta impersonare un estraneo, chiamare `setAdmin` con il suo indirizzo e controllare che sia diventato admin.

Non basta il nome della variabile per dire che il rischio è identico in ogni progetto: dobbiamo poi vedere quali privilegi usa quell'admin. La violazione dimostrata qui è che chiunque può assegnarsi il ruolo.»

```bash
bash demo.sh capability
```

**Risultato atteso:** due test PASS: trasferimento dei cento token all'attaccante e sostituzione dell'admin da parte di un caller arbitrario.

**Raccordo:** «Abbiamo confermato due problemi. Ora vediamo un caso in cui c'è una chiamata esterna e una callback, ma la specifica ipotesi di attacco non riesce.»

## 5. Terzo caso: una callback non basta per dimostrare una vulnerabilità

[Apri `src/context/NotifierFlow.sol`, funzione `finish`.]

«Questo contratto deve completare un'operazione una volta sola e notificare un altro contratto.

Il notifier è esterno. Potrebbe richiamare `finish` mentre la prima esecuzione è ancora in corso. Quindi abbiamo una domanda legittima sulla reentrancy.

Seguiamo però l'ordine effettivo delle istruzioni.»

```text
1. Se done è già true → revert AlreadyDone.
2. Scrivi done = true.
3. Chiama il notifier.
4. Emetti l'evento.
```

«Quando il notifier riceve il controllo, `done` è già vero. Se prova a rientrare in `finish`, trova il controllo iniziale e viene rifiutato.

Il fatto che si possa fare una callback non implica che si possa ripetere la transizione. Serve vedere quale stato osserva la seconda chiamata.»

[Apri `test/ContextualTriage.t.sol`, primo test.]

«Il test usa un notifier che prova davvero la callback. Controlliamo tre cose: l'operazione principale è completata; il tentativo di callback è avvenuto; la callback non è riuscita.

Il secondo test controlla l'errore preciso di una nuova chiamata a `finish`: deve essere `AlreadyDone`.»

```bash
bash demo.sh contesto
```

**Risultato atteso:** due test PASS. La callback è tentata ma fallisce; `done` resta vero. Il mock gestisce il fallimento della callback, quindi la chiamata principale può completarsi.

«La nostra conclusione è: la ripetizione di `finish` attraverso questa callback è impedita dal controllo sullo stato.

Non abbiamo dimostrato che ogni possibile interazione futura sia sicura. Se domani aggiungiamo un'altra funzione che usa lo stesso stato, dobbiamo rivedere il ragionamento.

E non abbiamo dimostrato che un notifier che fa sempre revert non possa bloccare l'operazione: quella è un'altra domanda, sulla disponibilità del flusso.»

**Domanda:** «Quindi possiamo cancellare per sempre ogni warning di reentrancy su questo contratto?»

«No. Documentiamo la specifica ipotesi esclusa, il test e le assunzioni. Se cambia il codice da cui dipende la conclusione, rifacciamo il triage.»

## 6. Correggere la causa e controllare che l'uso legittimo funzioni

[Apri `src/fixed/SafeStaticLab.sol`.]

«Ora passiamo alla versione corretta. Le modifiche rispondono a problemi diversi, quindi le leggiamo separatamente.

La prima è `onlyAdmin`: chi chiama `execute` deve essere autorizzato.

La seconda è il target. Non viene più scelto a ogni chiamata dall'utente: `action` viene fissato nel costruttore ed è immutable.

La terza è l'interfaccia. Chiamiamo `action.run(data)`: abbiamo una funzione prevista dal progetto, invece di permettere qualunque chiamata verso qualunque indirizzo.

Questo restringe i poteri disponibili. Non significa che la parola “immutable” renda affidabile un contratto: l'azione scelta al deployment deve comunque essere appropriata.»

[Mostra `execute`.]

«Vedete che `completed = true` viene scritto prima della chiamata. Potrebbe sembrare lo stesso errore di prima, ma qui l'azione è chiamata ad alto livello e il suo revert viene propagato.

Se l'azione fallisce, fa revert anche `execute`. Vengono annullati la scrittura di stato e l'evento di questa esecuzione.

Nel test partiamo da `completed = false`, facciamo fallire l'azione e verifichiamo che sia ancora falso. In generale il rollback ripristina lo stato precedente: non imposta magicamente ogni variabile a zero.»

[Apri `test/FixedRegression.t.sol`.]

«Ci servono sia i tentativi vietati sia l'uso legittimo. Se correggessi il contratto impedendo a tutti di fare qualsiasi cosa, fermerei l'attaccante ma romperei il prodotto.

Perciò controlliamo che l'estraneo non possa eseguire; che non possa cambiare admin; che una chiamata fallita non registri successo; e che l'admin riesca a chiamare l'azione prevista con i dati corretti.»

```bash
bash demo.sh correzione
```

**Risultato atteso:** quattro test PASS. Il test positivo controlla anche `action.lastCaller()` e `action.lastData()`: la dipendenza conferma chi l'ha chiamata e con quali dati.

### Trasferire l'admin in due fasi

[Mostra `transferAdmin` e `acceptAdmin`.]

«L'admin corrente propone un candidato. Il candidato deve poi accettare. Dopo la proposta, l'admin non è ancora cambiato.

Il vantaggio è evitare che una semplice proposta assegni subito il ruolo a un indirizzo sbagliato o incapace di accettare. Questa è una protezione aggiuntiva; il controllo fondamentale resta che un estraneo non possa avviare il trasferimento.»

[Per mostrare il caso completo senza un altro comando, leggi `test_AdminTransferRequiresProposalAndAcceptance`: proposta, vecchio admin ancora presente, accettazione, nuovo admin e proposta azzerata. Questo test è nella suite completa, non nei quattro selezionati da `demo.sh correzione`.]

## 7. Un problema può rendere una funzione inutilizzabile senza rubare fondi

[Torna a `StaticLab`, variabile `oracle` e funzione `readOracle`.]

«Ci manca un caso. `oracle` è dichiarato, ma non viene inizializzato dal costruttore e non esiste una funzione che lo imposti. Resta l'indirizzo zero.

`readOracle` prova a usarlo come un contratto che restituisce un prezzo. Quel percorso non può produrre la risposta prevista.

Non ogni finding è un trasferimento di fondi all'attaccante. Anche una funzione necessaria che non può essere usata è un problema da descrivere, con un impatto legato al suo ruolo nel sistema.»

```bash
bash demo.sh configurazione
```

**Risultato atteso:** un test PASS. La chiamata a `readOracle` fallisce e `oracle` resta zero. Il test usa una low-level call per osservare il fallimento senza imporre un particolare payload d'errore.

«La remediation del laboratorio rimuove questa feature incompleta. Questo va dichiarato: non diciamo di aver riparato una lettura oracle che nella nuova versione non esiste più.

In un progetto reale dovremmo concordare se la funzione serve: se serve, inizializzazione, validazione e test diventano parte della correzione.»

## 8. Scriviamo una scheda di triage insieme

[Apri `TRIAGE.md` soltanto dopo aver proposto l'esercizio. Concedi due minuti per completare a voce o su carta il caso `unsafeExecute`.]

«Adesso descriviamo il problema in modo che un'altra persona possa capirlo e riprodurlo senza essere stata qui.

Non scrivete soltanto “unchecked call”. Completate: chi chiama, cosa fa fallire, quale stato osserva e quale requisito viene violato.»

**Soluzione da costruire con la classe:**

| Campo | Caso ST-01 |
| --- | --- |
| Punto coinvolto | `StaticLab.unsafeExecute` |
| Caller e dati | Qualsiasi caller sceglie target e calldata |
| Causa | Il risultato della low-level call viene ignorato |
| Condizione | Il target richiesto fa revert |
| Risultato osservato | La chiamata esterna termina e `completed` diventa true |
| Proprietà violata | Lo stato registra come riuscita un'azione fallita |
| Prova | `test_Confirmed_UncheckedCallCreatesFalseSuccess` |
| Correzione del caso | Propagare il fallimento e limitare chi può eseguire quale azione |
| Regressione | `test_Regression_FailedActionCannotMarkCompleted` |

«Ora possiamo confrontare questa scheda con le altre. ST-03 riguarda l'autorità ceduta all'utente, anche quando la chiamata riesce. ST-05 documenta invece una specifica ripetizione della transizione che il codice impedisce.

Queste conclusioni non sono intercambiabili. Una lista di alert non le contiene automaticamente.»

**Domanda sulla severità:** «Se il tool scrive High, copiamo High nel report?»

«Prima descriviamo impatto e prerequisiti. Un'operazione che sposta token detenuti dal contratto ha un'evidenza economica diversa da un flag sbagliato senza conseguenze ulteriori dimostrate. La severità finale deve essere motivata nel contesto, non ricavata dal colore dell'output.»

## 9. Filtri e gate: che cosa stiamo davvero controllando?

[Apri `scripts/slither-fixed.sh`.]

«Dopo la correzione vogliamo rieseguire l'analisi statica sulla superficie corretta. Lo script usa una soglia che fa fallire il gate per finding Medium o High.

Vedete anche `--filter-paths`: filtra i risultati relativi a librerie, test, script, mock e alle cartelle didattiche `noisy` e `context`.

La motivazione è separare la valutazione della versione corretta dai contratti che conserviamo apposta per mostrare i problemi. Questo filtro non corregge i file esclusi e non dimostra che siano sicuri. Non significa neppure che lo strumento non compili o non consideri quei file come dipendenze.»

[Solo se Slither è disponibile.]

```bash
bash scripts/slither-fixed.sh
```

«Se il gate passa, la conclusione è che non sono emerse segnalazioni bloccanti secondo quella configurazione. Le regressioni continuano a servirci per verificare i comportamenti.

Se il comando restituisce un codice non zero, leggo il messaggio: potrebbe aver trovato segnalazioni oppure potrebbe non essere riuscito a compilare. Sono situazioni diverse.»

**Se chiedono il JSON:** «`slither . --json slither-report.json` esporta un risultato del tool. È materiale per il dossier; il report di audit richiede ancora contesto, evidenza, severità e decisioni.»

## 10. Chiusura pronta da leggere

«Oggi siamo partiti da una segnalazione e abbiamo costruito un ragionamento verificabile.

Nel primo caso la chiamata falliva, ma il contratto dichiarava successo. Nel secondo la chiamata riusciva, ma permetteva a un estraneo di usare gli asset del contratto. Nel terzo una callback era possibile, ma il controllo sullo stato impediva di ripetere la transizione.

Abbiamo visto perché servono sia la struttura del codice sia il contesto. Slither ci aiuta a trovare punti da investigare e a costruire una mappa. Le prove ci aiutano a confermare cosa succede. La specifica ci dice se quel comportamento è accettabile.

Per ogni problema confermato conserviamo una riproduzione, una correzione motivata e una regressione. Per un'ipotesi esclusa conserviamo il motivo e le assunzioni da rivedere quando il codice cambia.

Nella lezione 16 metteremo questi elementi dentro un processo di audit completo: partiremo dallo scope e arriveremo a un report in cui ogni finding è collegato a una proprietà e a una prova.»

### Ultime domande

| Domanda | Risposta |
| --- | --- |
| `success == true` significa che l'operazione era autorizzata? | No: un trasferimento non autorizzato dal progetto può riuscire perfettamente. |
| Un test verde sul target vulnerabile dimostra sicurezza? | No: bisogna leggere se l'asserzione conferma il bug. |
| Una callback dimostra da sola una reentrancy sfruttabile? | No: occorre seguire stato osservato, controlli e conseguenze. |
| Un filtro elimina il problema? | No: cambia quali risultati vengono riportati. |

**Compito:** compilare [TriageWorksheet.md](exercises/TriageWorksheet.md) per ST-03 senza copiare la scheda. Devono comparire la catena dei caller, i saldi prima e dopo, la proprietà violata e il motivo per cui `require(success)` non risolve la causa.

**Se hai poco tempo:** conserva i due casi su `unsafeExecute` e `arbitraryExecute`, il confronto con `SafeStaticLab` e la scheda di triage. Racconta la callback senza eseguire la demo; lascia oracle e filtri come lettura guidata finale.

## Promemoria operativo del docente

Le demo Foundry sono locali e non richiedono wallet, chiavi, RPC o Anvil. `bash demo.sh help` elenca le selezioni; `bash demo.sh check` richiama la suite completa di 12 test. I comandi Slither richiedono invece lo strumento già preparato secondo il README.

Se una demo non parte, mostra il test e ricostruisci preparazione, chiamata e asserzioni. Nelle trace dei casi vulnerabili cerca la chiamata decisiva e i saldi o lo stato finali; salta deployment e indirizzi. Zero test selezionati non è una verifica riuscita. Non presentare come osservato un output Slither che non hai eseguito.

Per la sintassi di printer, filtri ed esportazione JSON, riferimento ufficiale: [Slither — Usage](https://github.com/crytic/slither/wiki/Usage). Le conclusioni dei cinque casi vengono dal codice locale e dalle schede del laboratorio.
