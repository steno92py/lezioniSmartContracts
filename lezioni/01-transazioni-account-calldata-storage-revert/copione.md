# Lezione 1 — Transazioni, account, calldata, storage e revert

**Copione da dire ad alta voce.** Le parentesi quadre indicano cosa mostrare; le domande hanno una risposta pronta. L'obiettivo è seguire un singolo deposito dall'inizio alla fine, introducendo il lessico quando serve.

[Laboratorio](README.md) · [Approfondimenti](teoria.md)

Dalla radice del repository:

```bash
cd lezioni/01-transazioni-account-calldata-storage-revert
```

Rimani qui. Apri `src/EscrowLesson1.sol` e `test/EscrowLesson1.t.sol`. Ogni comando è una demo facoltativa: puoi condurre la lezione leggendo codice e risultati. Non servono account finanziati, wallet o rete pubblica.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Storia iniziale, transazione e chiamata | 0–12 | 0–8 |
| Deposito e contesto della chiamata | 12–30 | 8–20 |
| Storage, memoria e log | 30–43 | 20–29 |
| Input e confini | 43–53 | 29–37 |
| Rollback | 53–66 | 37–47 |
| Identità attraverso un intermediario | 66–80 | 47–56 |
| Credito, prelievo e chiusura | 80–90 | 56–60 |

I tempi comprendono le previsioni degli studenti e la compilazione delle tabelle, non solo la lettura del testo.

## 1. Una storia prima della sintassi

«Alice vuole depositare un ETH a favore di Bob e lasciare una nota: “acconto”. Il nostro primo contratto registra questa operazione.

Per capirlo dobbiamo separare tre domande: chi sta chiamando, quanto sta inviando e che cosa sta chiedendo di registrare.

Un contratto è un programma che espone operazioni e conserva uno stato. Non decide da solo quando partire: qualcuno ne chiama una funzione, direttamente o attraverso un altro contratto.

Nel nostro esempio Alice avvia una transazione che chiama il contratto. La transazione contiene una destinazione, un valore in ETH e dati che indicano l'operazione richiesta. Durante l'esecuzione possono nascere altre chiamate fra contratti: una transazione può quindi contenere più chiamate.»

[Disegna soltanto questo.]

```text
Alice → record(Bob, "acconto"), valore 1 ETH → Registro
```

«Per oggi ci concentriamo su quello che questa operazione può leggere e cambiare. I test ci permettono di osservarlo in un ambiente locale, con saldi fittizi.»

## 2. Leggere la firma senza perdersi nelle parole

[Mostra `record`, prima dei controlli.]

```solidity
function record(address beneficiary, bytes calldata note)
    external payable returns (uint256 id)
```

«`record` è il nome della funzione. `beneficiary` è un indirizzo: nel nostro esempio Bob. `note` è una sequenza di byte: qui contiene la parola acconto.

`external` indica che la funzione è un punto di ingresso chiamabile dall'esterno. `payable` permette di associare ETH alla chiamata. Non significa che ogni importo sia accettabile: i controlli arrivano dopo.

`returns` dice che la chiamata restituisce un identificativo numerico. Per il primo deposito sarà zero.

Non vedete fra gli argomenti né il pagatore né l'importo. Li prendiamo dal contesto della chiamata: `msg.sender` e `msg.value`.»

[Compila con la classe.]

| Informazione | Da dove viene | Valore nell'esempio |
| --- | --- | --- |
| Pagatore | `msg.sender` | Alice |
| Valore inviato | `msg.value` | 1 ETH |
| Beneficiario | Argomento `beneficiary` | Bob |
| Nota | Argomento `note` | acconto |

«Solidity esprime il valore in wei. Un ETH corrisponde a dieci alla diciottesima wei. La scrittura `1 ether` nel codice è un modo leggibile per esprimere quel numero.»

**Domanda:** «Alice può dichiarare di aver inviato due ETH scrivendo due in un argomento?»

«Qui non c'è un argomento importo: il contratto legge il valore effettivamente associato alla chiamata. Alice sceglie quanto inviare, ma non può far sì che `msg.value` descriva un altro importo.»

## 3. Dal deposito ai numeri nello storage

[Mostra il blocco dopo i controlli, da `id = nextId` all'evento.]

«All'inizio `nextId` vale zero. La funzione assegna zero al deposito e porta il prossimo identificativo a uno.

Poi costruisce una scheda: pagatore Alice, beneficiario Bob, importo un ETH e hash della nota. La salva nel mapping `_deposits` usando l'identificativo come chiave.

Un mapping è un'associazione fra chiavi e valori. Qui da un numero otteniamo una scheda di deposito. Nell'altro mapping, `credited`, da un beneficiario otteniamo il credito totale registrato per lui.»

[Prima di mostrare il test chiedi di completare la colonna finale.]

| Osservabile | Prima | Dopo |
| --- | ---: | ---: |
| `nextId` | 0 | 1 |
| Credito di Bob | 0 | 1 ETH |
| `totalRecorded` | 0 | 1 ETH |
| Saldo ETH del registro | 0 | 1 ETH |

«Questi sono aggiornamenti dello storage: restano disponibili dopo la fine della chiamata. La prossima operazione partirà da questi valori, se la transazione è stata confermata con successo.»

[Apri `test_RecordBindsSenderValueAndCalldataToStorage`.]

«Il test prepara Alice e Bob, chiama la funzione e legge i risultati. Per ora basta riconoscere le asserzioni: `assertEq` confronta due valori e fa fallire il test se sono diversi. Nella prossima lezione costruiremo questi esperimenti con calma.»

```bash
bash demo.sh deposito
```

**Risultato atteso:** un test PASS; deposito id zero, pagatore Alice, beneficiario Bob, importo un ETH, prossimo id uno, saldo e credito come in tabella.

**Domanda:** «Bob ha già ricevuto un ETH nel suo account?»

«No. Ha un credito registrato a suo favore. L'ETH è nel contratto. Scrivere che qualcuno deve ricevere un pagamento e trasferirglielo sono due operazioni diverse.»

## 4. Calldata, memory, storage ed eventi

«Abbiamo incontrato tre posti in cui possono stare i dati. Li distinguiamo seguendo la nota.

La nota arriva nella calldata, cioè nei dati della chiamata. Il parametro è leggibile dalla funzione e non viene modificato attraverso quel riferimento.

Calcoliamo l'hash e lo salviamo nello storage insieme alla scheda. Quello è il dato persistente scelto dal contratto.

Quando `getDeposit` restituisce una scheda, ne prepara una copia in memory, un'area temporanea dell'esecuzione. La copia restituita non è un nuovo deposito.»

[Mostra `getDeposit` e il controllo `id >= nextId`.]

«Una chiave mai scritta in un mapping restituisce valori predefiniti. Per questo controlliamo se l'id è valido: non vogliamo presentare una scheda piena di zeri come un deposito esistente.»

**Domanda:** «Il mapping è private. E della nota salviamo solo l'hash. Quindi la nota è segreta?»

«No. Private è una regola di accesso del linguaggio, non una cifratura dello storage. Inoltre il testo originale della nota è stato inviato nei dati pubblici della transazione. Salvarne soltanto l'hash non cancella quell'informazione.»

[Indica `DepositRecorded`.]

«L'evento è una comunicazione per chi osserva le transazioni dall'esterno, per esempio un'interfaccia o un indicizzatore. Riporta chi ha pagato, a favore di chi, quanto e con quale identificativo.

Il contratto usa lo storage per la propria contabilità. Non deve sostituirlo con un evento sperando di rileggerlo come un normale mapping.»

```bash
bash demo.sh evento
```

**Risultato atteso:** un test PASS sul contenuto di `DepositRecorded`. Questo controllo riguarda il log; il test precedente controlla lo stato. Le due osservazioni si completano.

## 5. Decidere che cosa rifiutare

[Mostra i tre controlli iniziali di `record`.]

«Chi chiama può scegliere dati che non rispettano il significato dell'operazione. Qui rifiutiamo beneficiario zero, valore zero e note più lunghe di 256 byte.

Non è il compilatore a sapere che un deposito da zero non ha senso per questa applicazione. È una decisione del contratto.»

[Scrivi e chiedi il risultato.]

```text
Nota da 255 byte → ammessa
Nota da 256 byte → ammessa
Nota da 257 byte → rifiutata
```

«Il controllo usa maggiore di 256, quindi il confine è incluso. E misura byte, non caratteri visibili: un carattere può richiedere più di un byte.

Il custom error `NoteTooLong` porta con sé la lunghezza ricevuta. In questo modo il test può distinguere il rifiuto atteso da un altro errore.»

```bash
bash demo.sh confini
```

**Risultato atteso:** tre test PASS: nota da 256 accettata, da 257 rifiutata con la lunghezza nell'errore, valore zero rifiutato. Il beneficiario zero è controllato dal codice e dalla suite, ma non fa parte di questa selezione di tre test.

## 6. Revert: che cosa torna indietro e che cosa rimane?

«Un revert interrompe la chiamata fallita e annulla i suoi effetti applicativi. Per capirlo facciamo due operazioni distinte.

Prima registriamo un deposito valido. Quello esiste già. Poi tentiamo un altro deposito con una nota troppo lunga.

Il secondo tentativo deve fallire senza consumare un identificativo e senza trattenere altro ETH. Il primo deposito deve rimanere.»

[Apri `test_RevertRollsBackStateAndIncomingValue`. Compila prima i risultati attesi.]

```text
Dopo il primo deposito: un record, credito e saldo corrispondenti.
Dopo il secondo tentativo fallito:
  stesso nextId;
  stesso credito;
  stesso saldo del contratto;
  primo record ancora leggibile.
```

«Non stiamo tornando all'inizio della storia della blockchain. Stiamo annullando gli effetti dell'esecuzione fallita. Una transazione reale fallita consuma comunque gas: non confondiamo il valore del deposito con il costo di esecuzione.»

```bash
bash demo.sh rollback
```

**Risultato atteso:** due test PASS: stato precedente conservato e lettura di un id inesistente rifiutata con `UnknownDeposit`.

**Domanda:** «Se il contratto emettesse un evento e poi facesse revert nella stessa esecuzione, il log resterebbe confermato?»

«No: anche quei log vengono annullati. Più avanti vedremo che un chiamante può gestire il fallimento di una chiamata interna e continuare: il confine del fallimento sarà importante.»

## 7. Identità: chi chiama attraverso un intermediario?

[Apri `src/OriginAuthToy.sol`. Disegna.]

```text
Owner → ForwarderToy → target.setValue
```

«Finora Alice chiamava direttamente il registro. Ora l'owner chiama un intermediario, e l'intermediario chiama il target.

Dentro il target `msg.sender` è l'intermediario. `tx.origin`, nel nostro esempio, è l'account che ha avviato la transazione: l'owner.

Se il requisito è “solo l'owner può chiamarmi direttamente”, quale dei due dobbiamo controllare?»

[Aspetta; mostra i due `setValue`.]

«Il target vulnerabile controlla `tx.origin`. L'intermediario può quindi usare una transazione iniziata dall'owner per farsi autorizzare. Il target corretto controlla il caller diretto e rifiuta quel passaggio.

Il punto non è fidarsi di qualunque `msg.sender`. Il punto è confrontare l'identità giusta con quella autorizzata dalla nostra policy.»

```bash
bash demo.sh identita
```

**Risultato atteso:** tre test PASS: l'intermediario passa nel target basato su origin, fallisce in quello basato su sender, l'owner diretto riesce nella versione corretta.

## 8. Credito e prelievo: anticipazione delle prossime lezioni

[Apri `src/fixed/EscrowLesson1Fixed.sol`, funzione `withdraw`.]

«Il registro iniziale conserva ETH ma non ha un'uscita. È un esempio didattico limitato. La variante fixed aggiunge il prelievo del beneficiario.

Bob riscuote il credito registrato per lui. Alice non può riscuoterlo soltanto perché era il pagatore. Se il destinatario rifiuta l'ETH e la funzione fa revert, il credito deve essere conservato.

Per oggi ci basta distinguere diritto registrato e pagamento. Studieremo il trasferimento del controllo durante il pagamento nelle lezioni 4 e 5.»

```bash
bash demo.sh prelievo
```

**Risultato atteso:** tre test PASS: beneficiario pagato, payer senza credito rifiutato, destinatario che rifiuta provoca rollback e conserva il diritto al pagamento.

## 9. Chiusura ed esercizio svolto

«Oggi abbiamo seguito una chiamata concreta: chi la fa, quali dati porta, quale ETH invia e quale stato lascia. Abbiamo distinto credito e pagamento, dati persistenti e temporanei, log e contabilità.

Quando leggerete una funzione, tornate a queste domande: quali valori provengono dall'utente, quale identità viene usata e cosa resta dopo un successo o un fallimento?

Nella lezione 2 organizzeremo queste domande in test ripetibili con Foundry.»

**Esercizio:** Alice registra un ETH per Bob; Carol ne registra due per Bob. Chiedi id, prossimo id, credito e saldo. **Soluzione:** id zero e uno, `nextId = 2`, credito Bob tre ETH, saldo tre ETH nel modello con questi soli depositi. Pagatori diversi non impediscono di avere lo stesso beneficiario.

**Verifica orale:** un mapping private è segreto? No. Un credito paga già il beneficiario? No. Il secondo tentativo fallito cancella il primo deposito? No.

**Percorso breve:** tieni deposito, tabella dello stato, rollback e identità. Il prelievo può restare un'anticipazione senza demo. Ulteriori [esercizi](exercises/README.md).

## Promemoria del docente

`bash demo.sh help` elenca le demo. Se un comando non parte, prosegui dal test indicato e dai valori attesi: non serve fare troubleshooting in aula. Un PASS riguarda le asserzioni del test, anche quando dimostrano un comportamento vulnerabile. Un filtro che trova zero test non è una verifica riuscita. Le tracce del registro non rappresentano un escrow completo pronto per usare fondi reali.
