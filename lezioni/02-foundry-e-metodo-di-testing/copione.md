# Lezione 2 — Foundry e metodo di testing

**Copione parlato con esperimenti guidati.** Leggi le parti fra virgolette; usa le parentesi quadre come istruzioni. Le domande includono le risposte. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/02-foundry-e-metodo-di-testing
```

Dalla radice del repository entra qui e rimani in questa cartella. Apri `src/FixedFeeRegistry.sol` e `test/FixedFeeRegistry.t.sol`. Non occorre installare o distribuire nulla durante la spiegazione. I comandi delle demo sono facoltativi: il copione contiene i risultati da ricostruire sul codice.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Requisito e strumenti | 0–12 | 0–8 |
| Setup e primo test | 12–30 | 8–21 |
| Importi e revert precisi | 30–46 | 21–33 |
| Ripetizione e rollback | 46–58 | 33–42 |
| Utenti indipendenti ed eventi | 58–70 | 42–49 |
| Mutazione ragionata | 70–80 | 49–55 |
| Tesoreria e chiusura | 80–90 | 55–60 |

## 1. Dalla funzione al requisito

«Nella prima lezione abbiamo letto test già pronti per osservare il contratto. Oggi impariamo come organizzarli.

Il contratto è un registro a pagamento. La regola è: ogni indirizzo può registrarsi una volta pagando esattamente un ETH.

Prima del codice sottolineiamo tre parole: ogni indirizzo, una volta, esattamente. Ciascuna genera esperimenti diversi. Se controllo soltanto che Alice riesca a pagare un ETH, non ho verificato né che Bob sia indipendente né che Alice non possa registrarsi due volte.»

[Scrivi.]

```text
Importo corretto → registrazione riuscita.
Importo diverso → rifiuto, nessun effetto.
Stesso indirizzo due volte → seconda richiesta rifiutata.
Due indirizzi distinti → due registrazioni indipendenti.
```

«Questa è già la struttura della nostra suite. Una suite è l'insieme delle prove; ogni test costruisce un caso e controlla un risultato.»

## 2. Che cosa ci offre Foundry?

«Useremo Forge per compilare ed eseguire test scritti in Solidity. Il contratto sotto test sta in `src`; i test stanno in `test`.

Un test è codice che prepara una situazione, chiama il contratto e verifica gli effetti. Non serve inviare transazioni a una rete pubblica: Forge esegue in un ambiente locale.

Cast e Anvil sono altri strumenti della stessa famiglia. Cast serve a interagire con dati e contratti; Anvil fornisce una catena locale. Oggi il percorso principale usa Forge: impariamo prima a formulare bene un esperimento.»

[Mostra le due importazioni del test.]

«Importiamo il contratto da verificare e la base `Test`, che ci fornisce asserzioni e strumenti di preparazione. `assertEq` significa: i due valori devono essere uguali. `assertTrue` e `assertFalse` controllano una condizione booleana.»

## 3. Setup: costruire lo stesso punto di partenza

[Mostra `setUp`, senza aprire tutti i test.]

«Il setup crea un nuovo registry e assegna dieci ETH fittizi ad Alice e Bob con `vm.deal`.

`vm` dà accesso ai cheatcode: strumenti del laboratorio per impostare saldo, caller e altre condizioni. Non sono funzioni che un utente può invocare sul contratto in produzione.

Ogni test riparte dal proprio stato iniziale. Il test di Bob non deve dipendere dal fatto che sia stato eseguito prima quello di Alice.»

**Domanda:** «Perché non facciamo una sola lunga sequenza con tutte le prove?»

«Possiamo avere test di sequenze quando ci interessano. Ma se una prova dipende accidentalmente da un'altra, un fallimento diventa difficile da interpretare. Vogliamo che ogni esperimento dichiari la propria preparazione.»

[Leggi `test_InitialState`.]

«All'inizio nessuno è registrato, il contatore è zero, il totale ricevuto è zero. Controlliamo anche che la fee sia davvero un ETH. Il test mantiene il valore atteso nella sua costante `FEE`, così un cambiamento accidentale del contratto non cambia automaticamente anche la nostra aspettativa.»

## 4. Primo test: prepara, agisci, osserva

[Mostra `test_Register_SucceedsWithExactFee`.]

«La preparazione viene dal setup. Ora vogliamo che il registry veda Alice come caller. Scriviamo `vm.prank(ALICE)`: la prossima chiamata al contratto avrà quell'identità.»

```solidity
vm.prank(ALICE);
registry.register{value: FEE}();
```

«Le parentesi graffe indicano il valore ETH associato alla chiamata. `register` non ha argomenti: le due informazioni che usa sono `msg.sender` e `msg.value`.

Dopo la chiamata non ci accontentiamo dell'assenza di errori. Controlliamo che Alice sia registrata, il contatore valga uno e il totale ricevuto sia un ETH.»

[Disegna.]

```text
ARRANGE: registry vuoto, Alice con saldo.
ACT:     Alice chiama register con 1 ETH.
ASSERT:  Alice registrata, count 1, totalReceived 1 ETH.
```

```bash
bash demo.sh esatta
```

**Risultato atteso:** due test PASS: stato iniziale e registrazione esatta. Nella trace cerca `register` e le osservazioni; non occorre leggere gli indirizzi di deployment.

«Il verde significa che le asserzioni sono soddisfatte. Se avessimo scritto una verifica sbagliata, il colore non la renderebbe giusta.»

## 5. “Esattamente” comprende entrambi i lati

[Mostra il controllo `msg.value != REGISTRATION_FEE`.]

«La fee non è un minimo: è un importo esatto. Quindi mezzo ETH va rifiutato, ma anche due ETH devono essere rifiutati.

Sono comportamenti diversi. Un controllo che rifiuta solo importi troppo piccoli passerebbe il primo caso e sbaglierebbe il secondo.»

| Pagamento | Risultato richiesto |
| --- | --- |
| 0 | Rifiutato |
| 0,5 ETH | Rifiutato |
| 1 ETH | Accettato |
| 2 ETH | Rifiutato |

[Apri `_expectWrongFeeAndAssertUnchanged`.]

«Questo helper evita di riscrivere gli stessi controlli per tre importi sbagliati. Prima salva i saldi, poi dichiara l'errore atteso, esegue e controlla che nulla sia cambiato.

`vm.expectRevert` non provoca il revert: avvisa il test che la prossima chiamata deve fallire. Se la chiamata riesce, fallisce il test.»

```solidity
vm.expectRevert(
    abi.encodeWithSelector(FixedFeeRegistry.ExactFeeRequired.selector, sent, FEE)
);
```

«Qui non aspettiamo un errore qualunque. Indichiamo il tipo di errore e i suoi dati: quanto abbiamo inviato e quanto era richiesto. La codifica serve a confrontare quella risposta precisa.»

```bash
bash demo.sh importi
```

**Risultato atteso:** tre test PASS: zero, mezzo ETH e due ETH vengono rifiutati. In ciascuno il registry resta vuoto e non trattiene il pagamento.

**Domanda:** «Un test negativo passa quando il contratto rifiuta?»

«Passa se rifiuta nel modo previsto e lascia gli effetti previsti. Non basta vedere una riga Revert nella trace.»

## 6. Registrarsi due volte: cosa conserviamo dopo il rifiuto?

[Apri `test_RevertWhen_AccountRegistersTwice`.]

«Prima Alice si registra normalmente. Poi salviamo i saldi e proviamo una seconda registrazione.

Il risultato atteso è `AlreadyRegistered(ALICE)`. Alice deve rimanere registrata una sola volta; il contatore deve rimanere uno; il totale deve rimanere un ETH.»

```bash
bash demo.sh doppia
```

**Risultato atteso:** un test PASS, con primo pagamento riuscito e secondo rifiutato senza trattenere altro valore.

«Questo test distingue il rifiuto corretto da comportamenti parziali, come aumentare il contatore prima di gestire male l'errore. Nel nostro ambiente osserviamo il valore della chiamata; non stiamo modellando il costo del gas di una transazione reale.»

**Domanda:** «Se cambiamo l'ordine dei controlli nel contratto, può cambiare l'errore?»

«Sì. Un utente già registrato che paga un importo sbagliato viola due condizioni. L'ordine decide quale errore viene osservato per primo. Quando un test richiede un errore preciso, sta anche fissando quel comportamento.»

## 7. Alice non deve registrare Bob

[Mostra `test_Register_TwoDifferentAccountsRemainIndependent`.]

«Dopo la registrazione di Alice controlliamo subito che Bob sia ancora non registrato. Poi registriamo Bob.

Alla fine entrambi risultano registrati, il contatore vale due e il totale due ETH. Il controllo intermedio è utile: ci mostra se la prima operazione ha toccato un'identità che non avrebbe dovuto modificare.»

[Mostra il test sull'evento.]

«Per l'evento dichiariamo il log atteso con `expectEmit`, poi eseguiamo la chiamata. L'emit scritto nel test è il modello che Foundry usa per il confronto. Non è la registrazione effettiva del contratto.

Controllare un evento è utile per le integrazioni, ma un evento da solo non garantisce che il mapping sia stato aggiornato. Per quello abbiamo le altre asserzioni.»

```bash
bash demo.sh indipendenza
```

**Risultato atteso:** due test PASS: indipendenza degli utenti e contenuto dell'evento `Registered`.

[Mostra `_assertAccountingProperty`.]

```text
totalReceived = registrationCount × 1 ETH
```

«Questa è la relazione contabile del registro. La confrontiamo con `totalReceived`, non assumiamo che il saldo ETH sia sempre identico al totale degli ingressi tramite register: un indirizzo può ricevere ETH anche per altre vie. E, nella variante con prelievo, il saldo può scendere senza cancellare la storia degli incassi.»

## 8. Un esperimento sul test: quale errore riuscirebbe a trovare?

[Scrivi una modifica ipotetica, senza cambiare il file in aula.]

```text
Corretto: if (msg.value != FEE) revert …
Mutato:   if (msg.value <  FEE) revert …
```

«Quale test diventa capace di distinguere le due versioni?»

[Aspetta e ripassa la tabella.]

«Quello con due ETH. Zero e mezzo ETH continuano a essere rifiutati; un ETH continua a essere accettato. Serve il caso sopra il valore esatto.

Questo modo di ragionare si chiama mutation thinking: immaginiamo un errore plausibile e chiediamo quale prova lo rileverebbe. Non basta contare quanti test abbiamo.»

**Esercizio di due minuti:** togli mentalmente l'aggiornamento di `registrationCount`. Quali asserzioni lo scoprono? **Soluzione:** il valore esplicito del contatore e la relazione fra numero di registrazioni e totale. Un test che controllasse solo `registered(ALICE)` non basterebbe.

Il laboratorio eseguibile di mutazione è separato in `mutation/README.md`. Non è necessario lanciarlo durante questa lezione: il ragionamento alla lavagna contiene già il punto didattico.

## 9. Estendere il requisito: la tesoreria può ritirare

[Apri `src/fixed/FixedFeeRegistryFixed.sol` e il relativo test.]

«Il registro base incassa ma non permette uscite. La variante fixed aggiunge una tesoreria che può ritirare le fee.

Questa nuova funzione richiede nuove domande: chi può chiamarla, quanto riceve e cosa succede se prova una seconda volta. I test vecchi sul register non verificano automaticamente il prelievo.»

```bash
bash demo.sh tesoreria
```

**Risultato atteso:** tre test PASS: tesoreria pagata, estraneo rifiutato, secondo prelievo senza fondi rifiutato. Leggi i test dedicati prima di attribuire alla funzione altre garanzie.

## 10. Chiusura

«Un test utile parte da un requisito, prepara un caso e osserva effetti precisi. I casi positivi verificano l'uso previsto; quelli negativi verificano il rifiuto e ciò che rimane dopo.

Abbiamo visto perché importi sopra e sotto il confine sono prove diverse, perché i caller vanno preparati esplicitamente e perché ogni test deve essere indipendente.

Nella prossima lezione useremo questo metodo per una macchina a stati: oltre a chi chiama e a quanto paga, conterà il momento in cui l'operazione viene richiesta.»

**Verifica orale:** expectRevert fa fallire il contratto? No, verifica un fallimento atteso. Due ETH vanno bene per una fee esatta di uno? No. Una suite verde può avere controlli insufficienti? Sì: proponi una mutazione per valutarlo.

**Compito:** scegliere un requisito, scrivere preparazione/azione/osservazioni e una mutazione che quel test dovrebbe trovare. [Esercizi](exercises/README.md).

**Se hai poco tempo:** conserva il primo test, la tabella degli importi, il secondo tentativo e la mutazione `!=`/`<`. La tesoreria può restare una lettura finale.

## Promemoria del docente

Le demo usano Forge locale. `bash demo.sh help` elenca le selezioni; la suite ordinaria si richiama con `check`, distinta dal laboratorio di mutazione intenzionalmente fallente. Se il terminale non è pronto, leggi le asserzioni con i risultati del copione. Non interpretare zero test selezionati come successo.
