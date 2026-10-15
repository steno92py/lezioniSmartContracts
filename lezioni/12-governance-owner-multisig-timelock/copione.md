# Lezione 12 — Governance, owner, multisig e timelock

**Copione parlato con flusso completo alla lavagna.** Le parentesi quadre sono azioni del docente. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/12-governance-owner-multisig-timelock
```

Apri i tre contratti in `src/governance/`: `GovernedEscrow.sol`, `ToyMultisig.sol`, `ToyTimelock.sol`. Le demo sono locali. Il multisig usa approvazioni on-chain dei chiamanti: non stiamo implementando raccolta e verifica di firme off-chain.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Mappa dei poteri e trasferimento owner | 0–18 | 0–12 |
| Multisig e quorum | 18–33 | 12–22 |
| Timelock, identità e confini temporali | 33–51 | 22–35 |
| Cancellazione e fallimento | 51–61 | 35–42 |
| Pausa e flusso completo | 61–78 | 42–54 |
| Esercizio e chiusura | 78–90 | 54–60 |

## 1. Un controllo corretto può proteggere un potere eccessivo

«Nella lezione sull'access control abbiamo chiesto: un estraneo riesce a chiamare una funzione riservata? Oggi facciamo una domanda diversa: se la persona autorizzata sbaglia o perde la chiave, quanto può cambiare e quanto rapidamente?

onlyOwner può funzionare perfettamente e lasciare a una singola chiave il potere di cambiare commissioni, oracle o implementation. Il controllo del chiamante è necessario, ma non descrive da solo una governance adeguata.»

[Scrivi tre domande distinte.]

```text
Autorità: quale indirizzo può eseguire questa operazione?
Quorum: quante approvazioni distinte servono per decidere?
Tempo: quanto deve passare prima che la decisione sia eseguibile?
```

«Un multisig risponde al quorum. Un timelock aggiunge una finestra temporale. Nessuno dei due decide automaticamente se la proposta sia economicamente corretta.

Anche due chiavi diverse possono essere controllate dalla stessa persona o compromesse dallo stesso dispositivo. Il contratto conta indirizzi; l'indipendenza operativa delle persone è una questione ulteriore.»

## 2. Disegniamo i poteri prima dei modificatori

[Mostra `src/governance/GovernedEscrow.sol`.]

«Qui owner può cambiare fee e oracle. Un ruolo di emergenza può mettere in pausa. L'owner può riaprire. Già questa separazione è una scelta: chi deve fermare rapidamente un'operazione non riceve anche il potere di riscrivere le regole o riavviare il sistema.»

| Azione | Autorità nel contratto |
| --- | --- |
| Cambiare fee o oracle | owner |
| Mettere in pausa | emergencyPauser |
| Rimuovere la pausa | owner |
| Accettare la proprietà proposta | pendingOwner |

«Non memorizziamo soltanto i nomi dei ruoli. Per ogni funzione privilegiata seguiamo il chiamante ammesso e poi chiediamo chi controlla quell'indirizzo. Se owner è un altro contratto, dobbiamo continuare la catena.»

## 3. Trasferimento in due fasi

«Supponiamo che Alice sia owner e voglia trasferire il potere a Bob. In una procedura immediata un indirizzo sbagliato può far perdere il controllo. Qui Alice propone Bob, poi Bob deve accettare.

Durante l'attesa Alice è ancora owner. pendingOwner non è un secondo amministratore: è il candidato che può completare il trasferimento.»

```text
owner = Alice, pendingOwner = nessuno
Alice propone Bob
owner = Alice, pendingOwner = Bob
Bob accetta
owner = Bob, pendingOwner = nessuno
```

```bash
bash demo.sh trasferimento
```

**Risultato atteso:** due test PASS: il candidato deve accettare; il vecchio owner mantiene l'autorità fino all'accettazione.

**Domanda:** «Se il nuovo owner deve essere un timelock, basta impostarlo come pendingOwner?»

«No. Serve anche l'accettazione effettuata dal timelock, attraverso il suo percorso di esecuzione. Il trasferimento non è completo finché il contratto applicativo non mostra il timelock come owner effettivo.»

«Le due fasi riducono errori operativi, ma non proteggono un trasferimento deliberatamente malevolo da parte dell'owner corrente. Non attribuiamo al meccanismo una garanzia che non offre.»

## 4. Multisig: tre indirizzi, due approvazioni

[Apri `src/governance/ToyMultisig.sol`: constructor, submit, approve, execute.]

«Configuriamo Alice, Bob e Carol, con soglia due. La proposta contiene target, value e data: dove chiamare, quanti wei inviare e quale funzione eseguire con quali argomenti.

Il target è vincolato dalla proposta. Non approviamo una frase come “sistemare la fee”: approviamo una chiamata precisa.»

[Scrivi un esempio: target Escrow, value zero, data che codifica setFee(500).]

«submit crea la proposta, ma qui non conta come approvazione. Anche chi propone deve chiamare approve. Alice approva: siamo a uno. Alice prova ad approvare ancora: viene respinta. Bob approva: siamo a due. A quel punto un owner del multisig può eseguire la proposta.»

```bash
bash demo.sh quorum
```

**Risultato atteso:** tre test PASS: una sola approvazione non basta, una doppia approvazione dello stesso owner è rifiutata, due approvazioni consentono l'esecuzione.

«Il mapping approvedBy collega ogni proposta a ciascun approvatore. Senza questa distinzione, contare semplicemente le chiamate permetterebbe a una chiave di raggiungere da sola la soglia.

Prima della chiamata esterna execute segna la proposta come eseguita. Se il target fallisce, il multisig fa revert e anche quel flag torna indietro. Se il target riesce, la stessa proposta non deve poter essere eseguita di nuovo.»

**Domanda:** «Con due firme abbiamo anche due giorni di attesa?»

«No. Il quorum non introduce tempo. Dopo la seconda approvazione una proposta può diventare subito eseguibile. Per l'attesa serve un altro vincolo.»

## 5. Timelock: una chiamata precisa, dopo un momento preciso

[Apri `src/governance/ToyTimelock.sol`.]

«Il proposer programma l'operazione. Il canceller può cancellarla. L'executor può eseguirla quando è pronta. Nel nostro modello il ruolo executor assegnato all'indirizzo zero apre l'esecuzione a chiunque: chi esegue non sceglie però una nuova operazione, perché deve rispettare quella già programmata.»

«L'identità dell'operazione è l'hash di target, value, data, predecessor e salt. Se cambiamo la fee nella calldata, stiamo parlando di un'altra operazione. Il salt permette di distinguere operazioni con altri parametri uguali. Il predecessor, se presente, impone che un'operazione precedente sia già conclusa.»

[Disegna il tempo, usando un esempio di due giorni.]

```text
Programmazione: lunedì 10:00
Delay:          48 ore
readyAt:        mercoledì 10:00

mercoledì 09:59:59 → troppo presto
mercoledì 10:00:00 → pronta
```

```bash
bash demo.sh tempo
```

**Risultato atteso:** due test PASS: prima del limite l'esecuzione è rifiutata; esattamente al limite è consentita.

«Il controllo usa il timestamp della chain. Nella demo vm.warp ci porta sui confini senza attendere due giorni. Il timelock non invia da solo la transazione allo scadere: ready significa eseguibile, non già eseguita.»

**Domanda:** «Perché aspettare se la proposta è già approvata?»

«Per dare tempo a osservare una modifica e reagire secondo i meccanismi disponibili: cancellazione autorizzata, valutazione del rischio, eventuale uscita se il protocollo la consente. Il tempo è utile soltanto se qualcuno osserva e dispone di azioni efficaci.»

## 6. Cancellazione e tentativi falliti

[Disegna gli stati.]

```text
Unset → Waiting → Ready → Done
           │        │
           └────────┴──→ Cancelled
```

«Il canceller può intervenire sia mentre aspettiamo sia quando l'operazione è pronta, purché non sia già conclusa. Un'operazione cancellata non diventa eseguibile solo perché è trascorso il tempo originario.

In questo modello si può riprogrammare un'identità cancellata. La nuova programmazione deve rispettare di nuovo il ritardo: cancellare non crea un lasciapassare per un'esecuzione immediata.»

```bash
bash demo.sh cancellazione
```

**Risultato atteso:** due test PASS: un'operazione cancellata non viene eseguita; il fallimento del target lascia l'operazione Ready.

«Nel secondo caso il timelock segna done prima della call, ma propaga il fallimento. Il revert annulla done, quindi resta pronta. Non significa che venga riprovata automaticamente o che convenga riprovarla senza leggere l'errore. Significa che il tentativo fallito non la consuma come se fosse riuscito.»

**Domanda:** «Il timelock rende ritardata qualsiasi decisione amministrativa?»

«Non automaticamente. In ToyTimelock l'admin può modificare immediatamente l'assegnazione dei ruoli. Il minimumDelay è immutabile e assegnare proposer o executor non elimina il ritardo di una nuova operazione; resta però un potere immediato sui soggetti che possono programmare, cancellare o eseguire. La mappa della governance deve includere anche l'admin del timelock.»

## 7. Emergenza: fermare e riaprire non sono lo stesso potere

[Mostra pause, unpause, sensitiveAction ed exit in GovernedEscrow.]

«Se rileviamo un attacco, aspettare due giorni per fermare nuove azioni può essere inaccettabile. Diamo al pauser un potere rapido e ristretto: fermare. Riaprire e cambiare configurazione restano all'owner.

In questo laboratorio la pausa blocca sensitiveAction ma lascia disponibile exit. È una scelta esplicita della specifica. Non assumiamo che ogni protocollo possa sempre preservare ogni uscita durante un incidente.»

```bash
bash demo.sh pausa
```

**Risultato atteso:** due test PASS: il pauser ferma ma non configura o riavvia; la pausa blocca l'azione protetta e conserva il percorso di uscita.

«Qui sensitiveAction ed exit incrementano contatori: non movimentano realmente fondi. La demo prova quali percorsi rimangono accessibili. Per dimostrare il recupero dei fondi servirebbe verificare anche contabilità, liquidità e trasferimenti effettivi.»

**Domanda:** «Un ruolo che può solo mettere in pausa è innocuo?»

«No. Può compromettere la disponibilità. Abbiamo limitato il tipo di danno che può fare, non cancellato ogni rischio.»

## 8. Colleghiamo davvero i componenti

[Scrivi il percorso e seguilo con il dito mentre spieghi.]

```text
Alice + Bob
    ↓ due approvazioni
ToyMultisig
    ↓ schedule di una specifica operazione
ToyTimelock
    ↓ attesa di 48 ore, poi execute
GovernedEscrow.setFee(...)
    owner effettivo = ToyTimelock
```

«Le approvazioni autorizzano il multisig a programmare. La programmazione fa partire l'attesa. Dopo l'attesa un executor invia la transazione di esecuzione. Nell'ultima chiamata l'Escrow vede il timelock come msg.sender.

Se l'Escrow avesse ancora il multisig come owner, il multisig potrebbe chiamare direttamente setFee, saltando il timelock. Avere un timelock distribuito da qualche parte non significa che il potere debba passarci.»

```bash
bash demo.sh flusso
```

**Risultato atteso:** due test PASS: due approvatori programmano e il timelock esegue dopo il ritardo; il proposer non può aggirare l'ownership del timelock.

«Questa è la prova di sistema: seguiamo tutti i passaggi fino al contratto che applica la modifica. I test dei singoli componenti non sostituiscono la verifica del collegamento.»

## 9. Esercizio con risposta

«Il team dice: “Abbiamo un multisig e un timelock, quindi tutti gli upgrade aspettano 48 ore”. Quali dati chiediamo?»

Lascia due minuti, poi proponi questa risposta:

«Chiediamo chi possiede effettivamente il potere di upgrade; chi può programmare e cancellare; chi amministra quei ruoli; quale ritardo è configurato; se esistono funzioni alternative che cambiano l'implementation. Infine seguiamo una proposta dalla sua approvazione fino alla scrittura del nuovo indirizzo.»

«Ora compromettiamo soltanto il pauser. Può cambiare la fee?»

**Risposta:** «Non attraverso i permessi mostrati. Può fermare il percorso protetto; il ripristino appartiene all'owner. Questo separa contenimento dell'emergenza e decisione di ripartenza.»

«Ora approvano Alice e Bob, ma nessuno esegue dopo due giorni. La fee cambia?»

**Risposta:** «No. Pronta non significa eseguita: serve la transazione finale.»

## Chiusura e percorso breve

«Una governance si legge come una catena di poteri. Per ogni modifica seguiamo chi la decide, chi la programma, chi può fermarla e quale indirizzo arriva al controllo finale. Nella prossima lezione tradurremo requisiti come questi in test capaci di distinguere un comportamento corretto da uno soltanto plausibile.»

Se manca il terminale, conserva il diagramma completo e fai simulare alla classe proposta, due approvazioni, attesa ed esecuzione. Chiedi a ogni passaggio chi sia msg.sender nella chiamata successiva. Nei 60 minuti mostra quorum, confine temporale e flusso; gli altri casi si leggono dal codice. Come esercizio autonomo fai disegnare una governance con upgrade ritardato e pausa immediata, indicando anche il potere dell'amministratore dei ruoli.
