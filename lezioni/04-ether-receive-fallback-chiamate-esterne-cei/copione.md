# Lezione 4 — Ether, receive, fallback, chiamate esterne e CEI

**Copione parlato.** Testo fra virgolette da dire, parentesi quadre per le azioni. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/04-ether-receive-fallback-chiamate-esterne-cei
```

Apri `src/EscrowWithPayout.sol` e `test/EscrowWithPayout.t.sol`. Resta qui per le demo facoltative. Il ragionamento è completo anche senza eseguirle.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Passaggio dalla 3 e pagamento | 0–18 | 0–12 |
| Receive, fallback e calldata | 18–34 | 12–23 |
| Call ed esito | 34–45 | 23–31 |
| CEI, rifiuto e rollback | 45–62 | 31–43 |
| Falso successo | 62–73 | 43–51 |
| Saldo, diritti e chiusura | 73–90 | 51–60 |

## 1. Mandare ETH può significare eseguire altro codice

«Nella lezione 3 abbiamo distinto l'approvazione dal pagamento. La variante finale faceva approvare il buyer e prelevare il seller.

Oggi usiamo una macchina più corta: il buyer chiama release e quella funzione paga direttamente il seller. È una decisione di questa versione, non un cambiamento da indovinare guardando lo stesso nome della funzione.»

```text
Created → fund del buyer → Funded → release del buyer e payout → Released
```

«La novità è nel payout. Se il destinatario è un contratto, inviargli ETH tramite una chiamata può eseguire il suo codice. Quindi il pagamento non è soltanto spostare un numero: in quel punto cediamo il controllo a un altro programma.»

[Mostra `test/helpers/EtherReceivers.sol`, il receiver accettante.]

«Il destinatario del test registra di essere stato chiamato. Possiamo quindi osservare sia il saldo sia l'esecuzione del suo codice.»

```bash
bash demo.sh pagamento
```

**Risultato atteso:** due test PASS: pagamento al seller senza codice nel caso base e pagamento al contratto che esegue `receive`. Nella seconda trace individua `release → AcceptingSeller.receive` e la scrittura fatta dal destinatario.

**Domanda:** «Mentre il seller esegue receive, la release dell'escrow è già terminata?»

«No. È sospesa in attesa del risultato della chiamata. Riprenderà dopo che il destinatario avrà terminato, oppure gestirà il fallimento.»

## 2. Quale funzione riceve la chiamata?

[Mostra `receive` e `fallback` dell'escrow.]

«Per capire quale codice viene eseguito guardiamo i dati della chiamata, non soltanto quanto ETH viene inviato.

Se la calldata corrisponde a una funzione esistente, viene selezionata quella funzione. Nel nostro contratto, con calldata vuota viene selezionata receive. Con un selettore sconosciuto si arriva a fallback.»

| Richiesta verso questo escrow | Funzione selezionata | Policy locale |
| --- | --- | --- |
| Chiamata a `fund` con argomenti corretti | `fund` | Controlla buyer, stato e prezzo |
| Calldata vuota, anche con zero wei | `receive` | Rifiuta |
| Selettore sconosciuto | `fallback` | Rifiuta |

«Receive non significa “qualunque funzione a cui arrivano soldi”. Una chiamata a fund con ETH entra in fund.

E calldata vuota non significa necessariamente importo positivo: anche zero wei può arrivare a receive. Qui la funzione fa revert perché vogliamo che i depositi seguano i controlli di fund.»

**Precisazione:** questa tabella descrive il contratto presente, che ha entrambe le funzioni. In generale, in assenza di receive, una calldata vuota può ricadere su fallback, se disponibile; per ricevere valore deve essere payable.

```bash
bash demo.sh dispatch
```

**Risultato atteso:** tre test PASS: calldata vuota a zero valore raggiunge receive e viene rifiutata; selettore sconosciuto rifiutato; invio diretto ETH rifiutato. Il successo del test è il rifiuto previsto dall'API.

## 3. Leggere la low-level call un pezzo alla volta

[Mostra la riga del payout.]

```solidity
(bool success,) = seller.call{value: price}("");
```

«Seller è la destinazione. `value: price` è il valore inviato. La stringa vuota indica calldata vuota. La call restituisce un booleano e dei dati; qui conserviamo il booleano e non usiamo i dati.

Se il destinatario fa revert, il booleano è falso. Questa forma di chiamata non obbliga automaticamente l'escrow a fare revert: siamo noi a dover decidere cosa fare con il risultato.»

[Mostra il controllo successivo.]

```solidity
if (!success) revert EtherTransferFailed(seller, price);
```

«La policy di questo escrow è che release riesca soltanto se il pagamento riesce. Quindi un fallimento del payout fa fallire anche release.

Per altre dipendenze, come una notifica opzionale, potremmo scegliere di proseguire. Il risultato va sempre interpretato secondo il requisito dell'operazione.»

**Domanda:** «Success vero significa che il destinatario ha fatto tutto ciò che volevamo?»

«Indica che la chiamata non è fallita a livello EVM. Non dimostra qualsiasi proprietà applicativa. Qui osserviamo anche il trasferimento previsto; con un'altra interfaccia potrebbero esserci valori di ritorno o effetti ulteriori da controllare.»

## 4. CEI: che cosa deve vedere il destinatario mentre esegue?

[Dividi `release` in tre gruppi.]

```text
Checks:       buyer e stato Funded
Effects:      state = Released; evento
Interactions: chiamata al seller
Esito:        se la call fallisce, revert
```

«Questo ordine si chiama checks-effects-interactions. Prima verifichiamo le condizioni, poi aggiorniamo lo stato, poi cediamo il controllo all'esterno.

Il motivo per anticipare lo stato è questo: se il seller interagisce nuovamente con l'escrow durante il pagamento, deve vedere che la release è già stata consumata. Nella prossima lezione seguiremo proprio una chiamata che rientra.

Ma aggiornare prima lo stato non significa perdere la possibilità di annullarlo. Se il pagamento fallisce e facciamo revert, vengono annullati anche gli effetti precedenti della release.»

**Domanda:** «Se scrivo Released e poi il seller rifiuta, restiamo bloccati in Released?»

«Non in questa implementazione: il fallimento viene convertito in revert. Torniamo al precedente stato Funded e i fondi restano nell'escrow.»

[Apri `test_RejectingSellerMakesReleaseRevertAtomically`.]

```bash
bash demo.sh rifiuto
```

**Risultato atteso:** un test PASS: errore di payout, stato Funded, prezzo ancora nel contratto e seller non pagato. Anche l'evento della release annullata non resta nei log confermati.

«Abbiamo preservato la contabilità. Non abbiamo però reso cooperativo il seller: se rifiuta sempre, questo flusso continua a non completarsi. Atomicità e possibilità di proseguire sono questioni diverse.»

## 5. Il falso successo: CEI da solo non basta

[Apri `src/labs/UncheckedCallEscrow.sol`.]

«Nella variante difettosa l'ordine può anche sembrare corretto: lo stato viene aggiornato prima della call. Ma l'esito del pagamento viene ignorato.

Facciamo la previsione con lo stesso seller che rifiuta. La call restituisce falso, l'escrow continua e la release termina. Rimangono lo stato Released e i fondi nel contratto.»

| Osservabile | Versione corretta dopo rifiuto | Variante che ignora l'esito |
| --- | --- | --- |
| Release | Revert | Termina |
| Stato | Funded | Released |
| Seller pagato | No | No |
| ETH ancora nell'escrow | Sì | Sì |

```bash
bash demo.sh falso-successo
```

**Risultato atteso:** un test PASS che dimostra Released falso dopo payout fallito. Leggi `test_DemonstratesFalseReleasedStateAfterFailedPayout` come una prova del problema, non come un'approvazione della variante.

«La conseguenza è che il contratto racconta una storia diversa da quella economica. Questo è il motivo per cui nei test osserviamo sia lo stato sia i saldi.»

## 6. Il saldo può aumentare senza un deposito valido

«Il nostro receive rifiuta gli invii diretti. Possiamo quindi affermare che ogni ETH nel saldo provenga da fund?

No. Il laboratorio contiene un helper che trasferisce ETH all'indirizzo senza eseguire receive del destinatario. Ci serve a dimostrare una proprietà del modello, non a insegnare una strategia di distruzione dei contratti.»

[Mostra i test `test_ForcedEtherBypassesReceive` e `test_ForcedEtherDoesNotIncreaseSellerEntitlement`.]

«Immaginiamo un prezzo di cinque e un surplus di due. Il saldo diventa sette, ma il seller continua ad avere diritto a cinque. Se pagassimo tutto il saldo, confonderemmo asset presenti e debito contrattuale.»

```text
Deposito concordato: 5
Surplus estraneo al funding: 2
Saldo: 7
Payout dovuto: 5
Residuo: 2
```

I numeri sono un esempio alla lavagna; nei test segui i valori effettivamente preparati dalla fixture.

```bash
bash demo.sh saldo
```

**Risultato atteso:** due test PASS: saldo aumentato senza receive e pagamento limitato a `price`. Il surplus rimane nell'esempio didattico: un'eventuale recovery policy va progettata separatamente.

## 7. Conservare caller e sequenza

«Aggiungere un payout non cancella i requisiti della macchina a stati. Un estraneo non può chiamare release, non si paga prima del funding e non si paga due volte.»

```bash
bash demo.sh sequenza
```

**Risultato atteso:** tre test PASS per caller estraneo, release anticipata e release ripetuta, tutti rifiutati.

**Esercizio di tre minuti:** «Progettate i controlli di un test per una release fallita. Non scrivete soltanto expectRevert.»

**Soluzione:** preparare stato Funded, prezzo e seller rifiutante; chiamare dal buyer; aspettare l'errore di trasferimento; controllare stato ancora Funded, fondi conservati e saldo seller invariato. Questo distingue un rifiuto atomico dal falso successo.

## 8. Chiusura

«Abbiamo seguito il punto in cui il controllo lascia il nostro contratto. Receive e fallback spiegano dove entra una chiamata; il booleano della call ci dice se è fallita; la nostra policy decide se propagare quel fallimento.

CEI fa vedere uno stato coerente al destinatario. Il controllo dell'esito permette il rollback se il pagamento non riesce. Servono entrambi per il comportamento che abbiamo scelto.

La prossima lezione entra dentro quella pausa: il destinatario richiama il vault prima che il primo prelievo sia terminato. Vedremo perché una seconda chiamata annidata è diversa da due chiamate una dopo l'altra.»

**Percorso breve:** pagamento a contratto, tabella dispatch, rifiuto e falso successo. Spiega il surplus alla lavagna se manca tempo. [Esercizi](exercises/README.md).

## Promemoria del docente

`bash demo.sh help` elenca i casi. Non presentare receive come una barriera capace di impedire qualsiasi aumento del saldo. Non generalizzare il comportamento dell'helper a tutte le semantiche storiche di SELFDESTRUCT. Se una demo non parte, usa la tabella dei risultati. I test e i receiver sono interamente locali.
