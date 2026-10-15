# Lezione 5 — Reentrancy, CEI e guard

**Copione parlato, con call stack e conti svolti.** Leggi le virgolette; usa le parentesi quadre per mostrare il codice. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/05-reentrancy
```

Apri `src/reentrancy/VulnerableVault.sol` e `test/VulnerableVault.t.sol`. Le demo sono locali e facoltative. Il contratto vulnerabile e il receiver sono esempi predisposti per studiare il difetto.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Ripetizione e rientro | 0–16 | 0–11 |
| Ordine delle istruzioni e call stack | 16–32 | 11–22 |
| Danno e contabilità indipendente | 32–49 | 22–34 |
| Correzione CEI | 49–64 | 34–44 |
| Guard e perimetro | 64–77 | 44–53 |
| Payout rifiutato, esercizio e chiusura | 77–90 | 53–60 |

## 1. Due prelievi in sequenza non sono una prova contro la reentrancy

«Nella lezione 4 abbiamo visto che pagare un contratto può eseguire il suo codice. Oggi quel destinatario userà il momento in cui ha il controllo per richiamare il vault.

Partiamo da un vault semplice: ogni utente deposita ETH, il contratto registra un credito e l'utente può ritirarlo.

Se Alice deposita uno, preleva uno e poi riprova, il secondo tentativo viene rifiutato. Potremmo pensare che il diritto sia utilizzabile una sola volta. Ma abbiamo verificato soltanto chiamate sequenziali.»

```text
Sequenza: withdraw termina → nuovo withdraw
Rientro:  withdraw → pagamento → receive → nuovo withdraw
          il primo withdraw non è ancora terminato
```

```bash
bash demo.sh sequenziale
```

**Risultato atteso:** due test PASS sul vault vulnerabile: prelievo normale e secondo prelievo sequenziale rifiutato. Un contratto vulnerabile può funzionare perfettamente nei casi ordinari.

## 2. Seguiamo l'esecuzione senza saltare al risultato

[Mostra `withdraw` in `VulnerableVault`.]

«Il vault legge il credito, verifica che sia positivo, manda ETH e soltanto dopo azzera il credito e aggiorna il totale.

Il punto critico è fra l'invio e l'azzeramento. In quel momento il destinatario può già eseguire codice, ma nello storage il credito risulta ancora utilizzabile.»

[Disegna due cornici annidate.]

```text
Primo withdraw:
  legge credito 1
  chiama il receiver con 1 ETH
    receive del receiver:
      richiama withdraw
        Secondo withdraw:
          legge ancora credito 1
          prova a pagare ancora 1 ETH
  solo al ritorno: azzera il credito
```

«Ogni esecuzione ha le proprie variabili locali, ma legge e scrive lo storage dello stesso vault. Il fatto che esista già un withdraw in corso non rende automaticamente zero il credito per quello nuovo.

Non ci sono due transazioni simultanee. È una singola catena di chiamate annidate dentro la stessa esecuzione.»

**Domanda:** «L'atomicità non dovrebbe impedire di vedere lo stato a metà?»

«L'atomicità stabilisce cosa resta se l'esecuzione riesce o fallisce. Il codice chiamato durante l'esecuzione può comunque osservare e usare lo stato intermedio. È proprio per questo che l'ordine delle scritture conta.»

## 3. Prima i fondi disponibili, poi la prova

[Apri `test_DemonstratesReentrantCallbackBreakingAccounting`.]

«Prepariamo quattro utenti onesti. Ciascuno deposita un ETH. Poi il receiver che tenterà il rientro deposita un ETH proprio.

Il vault ha cinque ETH. Il receiver ha diritto a uno. Gli altri quattro appartengono contabilmente agli utenti onesti.»

| Voce iniziale | Valore |
| --- | ---: |
| Saldo vault | 5 ETH |
| Credito receiver | 1 ETH |
| Somma crediti utenti onesti | 4 ETH |
| `totalCredits` | 5 ETH |

«Il receiver parte con una sola richiesta di prelievo e può rientrare quattro volte. Ogni chiamata annidata vede ancora il suo credito di uno.

Nel caso preparato riesce a svuotare i cinque ETH. Dobbiamo però leggere anche cosa resta nei registri, perché lì c'è una seconda parte del problema.»

```bash
bash demo.sh attacco
```

**Risultato atteso:** un test PASS che dimostra il difetto: il receiver incassa più del suo credito, il vault è vuoto e gli utenti onesti mantengono quattro ETH di crediti individuali. Nello scenario vengono pagati cinque ETH complessivi.

## 4. Perché anche il totale può mentire

«Durante il ritorno dalle chiamate annidate, ogni esecuzione aggiorna la contabilità. Cinque esecuzioni sottraggono un ETH ciascuna dal totale iniziale di cinque: `totalCredits` finisce a zero.

Ma i crediti dei quattro utenti onesti non sono mai stati pagati né cancellati. La loro somma è ancora quattro.»

```text
Saldo vault:                 0
Totale dichiarato:           0
Somma crediti utenti onesti: 4
```

**Domanda:** «Se controllassi soltanto saldo uguale a totalCredits, vedrei il problema?»

«No: zero è uguale a zero. Entrambi possono apparire coerenti mentre il contratto conserva debiti individuali non coperti.

Per questo la prova somma indipendentemente i crediti degli utenti onesti. Non si affida soltanto alla variabile aggregata che potrebbe essere corrotta.»

«Anche controllare credito del receiver uguale a zero non basta. Può essere zero dopo che è stato pagato molte volte. Serve confrontare il payout con il credito legittimo.»

## 5. Prima correzione: consumare il diritto prima della call

[Apri `src/reentrancy/SafeVaultCEI.sol`.]

«La prima correzione cambia l'ordine. Leggiamo il credito e lo copiamo nell'importo da pagare. Poi azzeriamo il credito e diminuiamo il totale. Solo dopo chiamiamo il destinatario.

Il destinatario può ancora eseguire codice e tentare una callback. Ma il nuovo withdraw trova credito zero e viene rifiutato.»

```text
CHECK:       credito positivo
EFFECT:      credito = 0; totale diminuito
INTERACTION: pagamento dell'importo copiato
```

[Apri `test_CEI_PreventsReuseOfCredit` in `test/SafeVaults.t.sol`.]

«Qui la fixture usa due ETH di utenti onesti e uno del probe. Il probe tenta davvero il rientro. Il test deve controllare il tentativo, non soltanto il saldo finale: altrimenti passerebbe anche se non avessimo mai esercitato la callback.»

```bash
bash demo.sh cei
```

**Risultato atteso:** un test PASS: callback tentata, rientro rifiutato con `NoCredit`, receiver pagato esattamente un ETH, credito receiver zero, due ETH onesti ancora nel vault e totale due.

«Il payout normale riesce perché il probe gestisce il fallimento della sua chiamata annidata. Non stiamo dicendo che qualunque destinatario si comporterà così: stiamo isolando la prova che il credito non si può riusare.»

## 6. Seconda difesa: una guardia contro il rientro

[Apri `src/utils/DidacticReentrancyGuard.sol` e `SafeVaultGuarded.sol`.]

«Una guardia mantiene un'informazione aggiuntiva: siamo già dentro un'operazione protetta?

All'ingresso controlla il lock e lo imposta come occupato. Prima del ritorno normale lo libera. Se una chiamata annidata entra in un'altra funzione protetta dallo stesso lock, trova occupato e viene rifiutata.»

```text
Libero → entro e occupo → eseguo il corpo → libero
                        ↘ rientro: trova occupato, revert
```

«La versione guarded mantiene anche CEI. Il lock protegge l'ingresso; l'ordine corretto mantiene coerente la contabilità. Sono difese diverse.»

```bash
bash demo.sh guard
```

**Risultato atteso:** un test PASS: tentativo di callback presente, errore `ReentrantCall`, payout legittimo una volta e fondi onesti conservati. Rispetto alla demo CEI cambia il primo controllo che ferma il rientro.

**Domanda:** «Basta mettere il modifier su withdraw e dimenticarsi del resto?»

«Dobbiamo guardare tutte le funzioni che condividono lo stato sensibile. Una callback potrebbe entrare in un'altra funzione non protetta. E una guardia non corregge una formula sbagliata o un pagamento destinato alla persona sbagliata.»

«Quando sentite cross-function, pensate proprio a un rientro attraverso una funzione diversa. Cross-contract coinvolge più contratti e stato condiviso fra loro. Sono estensioni del ragionamento: dove passa il controllo e quali valori sono osservabili in quel momento?»

## 7. Azzerare prima non deve far perdere il credito se il pagamento fallisce

«C'è un'obiezione naturale: se azzeriamo prima e il destinatario rifiuta, perdiamo il credito?

No, se gestiamo il fallimento facendo revert. Il rollback annulla anche l'azzeramento e la diminuzione del totale.»

```bash
bash demo.sh rifiuto
```

**Risultato atteso:** un test PASS: receiver rifiutante, errore `TransferFailed`, credito e totale ancora un ETH, vault con un ETH, receiver non pagato.

«Abbiamo preservato il diritto. Non abbiamo risolto il fatto che il destinatario rifiuti sempre: un'eventuale destinazione alternativa o altra uscita richiederebbe un requisito e controlli specifici.»

## 8. Esercizio e chiusura

**Consegna di tre minuti:** «Vi mostro solo `credit[receiver] == 0` alla fine del test. Quali altre osservazioni chiedete?»

**Soluzione:** credito iniziale, importo realmente ricevuto, tentativo di callback, ragione del rifiuto sulla versione sicura, saldo residuo e crediti degli utenti onesti. Il controllo deve distinguere una callback bloccata da una mai avvenuta e un singolo pagamento da pagamenti multipli.

«La reentrancy diventa pericolosa quando il controllo passa fuori mentre un diritto è ancora utilizzabile o lo stato condiviso è incoerente.

Abbiamo seguito l'esecuzione annidata, misurato il danno e confrontato due difese. CEI consuma il diritto prima della chiamata; la guardia blocca il rientro nel suo perimetro. Le asserzioni economiche dimostrano che il pagamento legittimo avviene una volta e gli altri utenti restano coperti.

Nella prossima lezione ci concentriamo su un'altra domanda: anche se ordine e conti sono corretti, chi deve avere il permesso di eseguire l'operazione?»

**Percorso breve:** sequenziale contro annidato, tabella cinque/uno/quattro, correzione CEI e rollback. La guardia può essere spiegata senza una seconda trace. [Esercizi](exercises/README.md).

## Promemoria del docente

Il receiver vulnerabile e il probe sicuro hanno comportamenti diversi: il secondo registra e gestisce il rientro rifiutato. Non attribuire loro la stessa sequenza di callback. Se il terminale non parte, usa il call stack e le tabelle. La guardia è una piccola implementazione didattica: questa lezione non verifica una libreria o un protocollo esterno.
