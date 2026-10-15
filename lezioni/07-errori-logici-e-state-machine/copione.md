# Lezione 7 — Errori logici e macchine a stati

**Copione da dire ad alta voce.** Le parentesi quadre indicano cosa mostrare; ogni domanda ha una risposta pronta. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

Dalla radice del repository:

```bash
cd lezioni/07-errori-logici-e-state-machine
```

Apri `src/LogicBugEscrow.sol` e `test/LogicBugEscrow.t.sol`. Rimani qui per le demo. Il percorso funziona anche senza terminale: i conti e i risultati sono riportati nel copione.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Requisito e grafo | 0–13 | 0–9 |
| Complete prima del deposito e ripetizioni | 13–30 | 9–21 |
| Cancellazione e crediti incompatibili | 30–43 | 21–30 |
| Correzione e terminalità | 43–59 | 30–41 |
| Booleani e modello dati | 59–71 | 41–49 |
| Prelievo e proprietà economiche | 71–82 | 49–55 |
| Esercizio e chiusura | 82–90 | 55–60 |

## 1. Una persona autorizzata può usare male una sequenza

«Nella lezione 6 abbiamo controllato chi può fare cosa. Oggi il chiamante sarà quello autorizzato: il seller chiamerà una funzione riservata al seller. Il problema nascerà da quando e quante volte la chiama.

Questo escrow riceve un deposito del buyer. Dopo il deposito, il seller può completare l'accordo e ottenere un credito; in alternativa il buyer può cancellare e ottenere il credito di rimborso.

È una policy semplificata di questo esercizio: qui complete spetta al seller e cancel al buyer. Non stiamo riutilizzando senza modifiche l'approvazione del buyer della lezione 3.»

[Disegna.]

```text
Created ── deposit, buyer ──→ Funded ── complete, seller ──→ Completed
                                └──── cancel, buyer ─────→ Cancelled
```

«Completed e Cancelled sono esiti alternativi. Lo stesso deposito non può diventare contemporaneamente un credito completo per il seller e un credito completo per il buyer.

In questi primi contratti il credito viene registrato ma non ancora pagato. Separiamo l'assegnazione del diritto dalla sua riscossione.»

## 2. Quale proprietà dobbiamo difendere?

[Scrivi i nomi delle variabili con il significato.]

```text
depositedAmount: importo depositato
sellerCredit:   quanto spetta al seller
buyerCredit:    quanto spetta al buyer
liabilities:    sellerCredit + buyerCredit
```

«Liabilities significa obbligazioni: quanto promettiamo complessivamente. Nel modello senza prelievi, non possiamo assegnare più di quanto è stato depositato e dobbiamo avere abbastanza ETH per coprire quei crediti.

Se depositiamo uno e promettiamo tre, non importa che tutte le funzioni siano state chiamate da account autorizzati: la contabilità è insolvente.»

**Domanda:** «Basta controllare che ciascun credito sia non negativo?»

«No: sono interi unsigned, quindi quel controllo non ci aiuterebbe. Dobbiamo confrontare le promesse con le risorse che le coprono.»

## 3. Leggiamo la funzione che non consuma la transizione

[Mostra `LogicBugEscrow.complete`.]

```solidity
function complete() external {
    if (msg.sender != seller) revert OnlySeller();
    sellerCredit += depositedAmount;
}
```

«Il primo controllo è corretto rispetto al ruolo: solo il seller passa. Poi la funzione aggiunge l'importo depositato al credito del seller.

Che cosa manca? Non controlla lo stato Funded e non porta lo stato a Completed. La transizione non viene consumata. Quando la funzione termina, il prossimo complete può ripetere la stessa operazione.»

### Prima del deposito

«Se il seller chiama complete subito, `depositedAmount` è zero. La chiamata viene accettata ma aggiunge zero. È una violazione dell'ordine previsto, non ancora la creazione di un credito positivo.

Distinguiamo sempre il comportamento dimostrato dal danno che immaginiamo. Il caso successivo mostra l'effetto economico.»

### Dopo il deposito

[Costruisci questa tabella una riga per volta.]

| Operazione | Saldo escrow | Credito seller | Stato nel target |
| --- | ---: | ---: | --- |
| Buyer deposita 1 ETH | 1 | 0 | Funded |
| Seller chiama complete | 1 | 1 | Funded |
| Seller chiama complete di nuovo | 1 | 2 | Funded |
| Seller chiama complete ancora | 1 | 3 | Funded |

«Sono chiamate normali in sequenza. Nessuna callback, nessun rientro durante una chiamata esterna. Il difetto della 5 richiedeva un'esecuzione annidata; questo richiede soltanto una funzione che può essere ripetuta.»

```bash
bash demo.sh ripetizione
```

**Risultato atteso:** due test PASS sulla variante vulnerabile: complete prima del deposito accettato e complete ripetuto capace di creare credito non coperto. Il verde conferma le asserzioni che descrivono il problema.

## 4. Una funzione corretta non basta se un'altra ignora lo stato

[Mostra `cancel`.]

«Cancel controlla il buyer e richiede Funded. Assegna il credito al buyer e passa a Cancelled. Presa isolatamente sembra rispettare il diagramma.

Ma complete continua a non guardare lo stato. Quindi il seller può chiamarla dopo la cancellazione.»

```text
deposito 1 → cancel → buyerCredit 1, stato Cancelled
                    → complete → sellerCredit 1
Totale promesso: 2; saldo disponibile: 1
```

**Domanda:** «Il fatto che Cancelled sia un valore dell'enum impedisce questo secondo credito?»

«No. La funzione può lasciare lo stato Cancelled e cambiare comunque i crediti. La terminalità deve proteggere tutti gli effetti che appartengono al ciclo di vita, non soltanto la variabile state.»

```bash
bash demo.sh conflitto
```

**Risultato atteso:** un test PASS che dimostra crediti incompatibili dopo cancel seguito da complete.

«Questa è una ragione per leggere tutte le funzioni che scrivono una variabile economica. Non basta trovare una funzione con un buon controllo e attribuirlo all'intero contratto.»

## 5. La correzione è una transizione completa

[Apri `src/SafeEscrow.sol`, prima `complete`, poi `cancel`.]

«La versione corretta lega nella stessa chiamata tre cose: stato di partenza richiesto, assegnazione del credito e stato di arrivo.

Complete richiede Funded, assegna il credito e passa a Completed. Cancel richiede Funded, assegna il credito al buyer e passa a Cancelled.

Dopo una delle due azioni non siamo più Funded: l'altra e le ripetizioni vengono rifiutate.»

```text
Richiedi Funded → assegna il credito una volta → entra nello stato terminale
```

«Vedete anche `=` al posto di `+=`. Esprime bene una singola assegnazione, ma non è da solo la correzione. Senza guardia, complete dopo cancel potrebbe ancora assegnare il credito al seller. Il significato della transizione viene dal controllo e dall'aggiornamento dello stato insieme.»

```bash
bash demo.sh correzione
```

**Risultato atteso:** quattro test PASS: completamento da Funded riuscito; complete dopo Completed, cancel dopo Completed e complete dopo Cancelled rifiutati.

[Chiedi lo stato e i crediti dopo un tentativo rifiutato.]

«Devono restare quelli della prima transizione riuscita. Il test negativo deve verificare questo, oltre all'errore.»

## 6. Tre booleani possono raccontare tre storie incompatibili

[Apri `src/BooleanStateTrap.sol`.]

«Qui sostituiamo la macchina con tre flag indipendenti: funded, completed e cancelled. Tre booleani permettono otto combinazioni.

Alcune potrebbero rappresentare fatti storici sensati: per esempio essere stato finanziato e poi completato. Ma se vogliamo rappresentare una fase corrente unica, dobbiamo evitare combinazioni contraddittorie, come completato e cancellato contemporaneamente.

In questo esempio ogni setter accende un flag senza controllare gli altri, quindi possiamo averli tutti veri.»

**Domanda:** «Un enum risolve automaticamente tutti i bug di stato?»

«No. Un enum impedisce alla singola variabile di essere contemporaneamente Completed e Cancelled, ma abbiamo appena visto un contratto con enum e transizioni sbagliate. Il tipo migliora la rappresentazione; le guardie rendono corretti i passaggi.»

```bash
bash demo.sh booleani
```

**Risultato atteso:** due test selezionati: combinazione contraddittoria raggiungibile nella trappola a booleani; transizione fallita senza alterazione di stato e contabilità nella versione corretta. Sono esempi distinti, non due passi sullo stesso contratto.

## 7. Credito assegnato e credito riscosso

[Apri `src/fixed/SafeEscrowFixed.sol`, `withdraw`.]

«Finora completare assegnava un credito al seller; cancellare lo assegnava al buyer. La variante fixed aggiunge il prelievo.

Per ritirare, il caller deve avere il proprio credito. Il credito viene consumato prima della chiamata esterna, come abbiamo imparato nella 5. Se l'invio fallisce e il contratto fa revert, il credito viene ripristinato.»

```bash
bash demo.sh payout
```

**Risultato atteso:** tre test PASS: seller riscuote dopo complete; buyer riscuote dopo cancel; secondo prelievo rifiutato.

«Ora il saldo può diminuire. Non dobbiamo continuare a pretendere che ogni importo storicamente depositato sia ancora presente: una parte può essere stata correttamente pagata. La solvibilità riguarda i crediti ancora dovuti.

Questa distinzione fra storia degli ingressi e debito attuale tornerà negli invariant test.»

## 8. Esercizio: aggiungere Disputed

«Vogliamo inserire uno stato Disputed. Prima del codice, decidete da dove si entra, chi può aprire la disputa e chi può chiuderla. Poi decidete quali crediti vengono assegnati alla risoluzione.»

[Lascia tre minuti.]

**Soluzione possibile:** entrata da Funded, apertura consentita alle parti, risoluzione riservata a un arbitro; uscite definite verso un solo esito terminale. La risoluzione non deve essere ripetibile, il totale dei crediti non deve superare il deposito e complete/cancel ordinari non devono saltare la disputa. Questa è una proposta di specifica, non una funzione già presente.

«Se non riusciamo a compilare questa matrice, non siamo pronti a scrivere i modifier. Prima rendiamo esplicita la regola.»

## 9. Chiusura

«Oggi abbiamo trovato un problema usando soltanto funzioni autorizzate in sequenza. Mancavano il controllo sul momento e il consumo della transizione.

La proprietà decisiva è economica: il totale dei crediti deve essere coperto. Per mantenerla, stato e contabilità devono avanzare insieme e gli esiti alternativi devono restare alternativi.

Nella prossima lezione cambieremo asset. Con gli ERC-20, chiedere un trasferimento a un altro contratto non significa automaticamente aver ricevuto l'importo richiesto.»

**Verifica orale:** complete prima del deposito crea necessariamente credito positivo? No. `=` da solo impedisce crediti dopo cancel? No. Un test sulla singola funzione sostituisce le sequenze? No.

**Percorso breve:** conserva la tabella delle tre complete, cancel seguito da complete e la correzione. Booleani e payout possono essere letti senza demo. [Esercizi](exercises/README.md).

## Promemoria del docente

Il registro base non paga: non chiamare il credito un incasso già avvenuto. I risultati delle demo descrivono i test presenti; non è necessario modificarli o lanciare una mutation in aula. `bash demo.sh help` elenca le selezioni. Se il terminale non parte, completa a mano saldi, crediti e stato dopo ciascuna azione.
