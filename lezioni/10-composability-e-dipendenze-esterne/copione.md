# Lezione 10 — Composability e dipendenze esterne

**Copione parlato con decisioni e casi svolti.** Le parentesi quadre indicano cosa mostrare; le domande hanno una risposta pronta. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/10-composability-e-dipendenze-esterne
```

Rimani nella cartella della lezione. Apri `src/NotificationEscrow.sol` e `src/BoundedIntegrator.sol`. Le demo sono facoltative e usano solo dipendenze locali.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Mappa delle dipendenze e policy | 0–14 | 0–9 |
| Notifica accessoria | 14–25 | 9–17 |
| Falso successo e correzione | 25–42 | 17–29 |
| ABI e significato del risultato | 42–55 | 29–39 |
| Provider mutevole e cache | 55–71 | 39–50 |
| Allowlist, esercizio e chiusura | 71–90 | 50–60 |

## 1. Il nostro contratto è soltanto una parte del sistema

«Nelle lezioni 8 e 9 abbiamo chiamato token e oracle. Oggi mettiamo insieme il ragionamento: il nostro contratto dipende da codice che non controlla direttamente.

Composability significa poter costruire usando altri contratti come componenti. È utile perché non dobbiamo realizzare ogni servizio. Ma ogni chiamata aggiunge una domanda: quali promesse stiamo accettando da quel componente?

Un'interfaccia ci dice come invocare una funzione e interpretare i tipi. Non garantisce che il risultato abbia il significato che ci aspettiamo, che la dipendenza sia sempre disponibile o che il suo comportamento resti uguale.»

[Disegna.]

```text
Consumer → token
         → oracle/provider
         → router
         → notifier
```

«Per ogni freccia chiediamo: chi sceglie la destinazione, quale risultato serve, che cosa succede se fallisce e quali effetti deve conservare il nostro contratto?»

## 2. Prima decisione: dipendenza critica o accessoria?

«Immaginiamo un pagamento e una notifica del pagamento. Se il pagamento non riesce, non possiamo dichiararlo completato. Se una notifica facoltativa non riesce, la specifica può invece permettere di mantenere valido il risultato principale.

Quindi catturare un errore non è sempre giusto o sempre sbagliato. Dipende da quale operazione è fallita.»

| Dipendenza del laboratorio | Reazione prevista |
| --- | --- |
| Notifier accessorio | Continuare, rendendo visibile il fallimento |
| Router critico | Annullare se fallisce o dà un risultato insufficiente |
| Provider per refresh | Rifiutare il refresh invalido; conservare la cache precedente |
| Cache oltre la sua durata | Rifiutare l'uso come dato valido |

«A volte si dice fail-open per il caso in cui un guasto non blocca il flusso e fail-closed per quello che lo ferma. Usiamo però frasi concrete: “il fallimento della notifica non annulla la release” è molto più preciso di “il contratto è fail-open”.»

## 3. Una notifica può fallire senza far sparire la release

[Mostra `NotificationEscrow.release`.]

«Il contratto controlla buyer e ripetizione, registra `released = true`, emette Released e prova a notificare.

La chiamata è dentro try/catch. Se il notifier fa revert, registriamo `NotificationFailed` con i dati dell'errore. Il fallimento è visibile ma non annulla la release.»

**Precisazione essenziale:** «Questo piccolo contratto registra stato ed eventi; non esegue un vero trasferimento di token o ETH. Lo usiamo per isolare la policy della notifica. Non diremo che il test prova un pagamento effettivo.»

```bash
bash demo.sh notifica
```

**Risultato atteso:** un test PASS: notifier che reverte, release registrata e fallimento osservabile.

**Domanda:** «Se mettiamo qualsiasi chiamata in try/catch, abbiamo risolto la disponibilità del sistema?»

«No. Potremmo nascondere il fallimento di una funzione indispensabile. E questa prova riguarda un revert ordinario del mock, non ogni problema di risorse o comportamento arbitrario. La gestione degli errori deve corrispondere alla responsabilità della dipendenza.»

## 4. Successo apparente: target fallito o senza codice

[Apri `src/UncheckedDependency.sol` e `test/LowLevelCalls.t.sol`.]

«Qui il consumer usa una low-level call e poi segna completato. Abbiamo già visto il primo rischio: se il target fa revert e ignoriamo l'esito, il flag racconta un successo inesistente.

C'è un secondo caso: il target è un indirizzo ordinario senza codice. Una normale call può terminare con successo tecnico e dati vuoti senza aver eseguito l'operazione che credevamo di richiedere.»

```bash
bash demo.sh falso-successo
```

**Risultato atteso:** due test PASS sulla variante vulnerabile: target che reverte e indirizzo senza codice portano entrambi al falso completamento.

[Apri `src/CheckedDependency.sol` e `src/utils/CallUtilsLite.sol`.]

«La correzione controlla la presenza di codice, esegue la call e propaga il revert con i dati restituiti. Soltanto dopo il successo tecnico registra completed.

Propagare i dati del revert, spesso chiamato bubbling, significa conservare l'informazione sulla causa anziché sostituirla sempre con un generico fallimento.»

```bash
bash demo.sh correzione
```

**Risultato atteso:** due test PASS: errore del target propagato con stato conservato; target senza codice rifiutato.

«Questa classe corregge precisamente i due falsi successi. Non è un executor completo: il target resta scelto dall'utente e completed viene scritto dopo la call. Il solo controllo AlreadyCompleted non è una guardia contro una callback durante la prima esecuzione. Non allarghiamo la conclusione oltre le proprietà dimostrate.»

## 5. Compatibilità ABI e compatibilità economica

[Apri `src/BoundedIntegrator.sol`.]

«Adesso il router ha codice, espone la funzione giusta, non fa revert e restituisce un uint256 valido. Possiamo fidarci del risultato?

Supponiamo di chiedere almeno novecento e ricevere uno come valore di ritorno. Il dato è tecnicamente decodificabile, ma viola il minimo richiesto.»

```text
Funzione attesa presente: sì
Tipo restituito corretto: sì
Call senza revert: sì
Output richiesto almeno 900, output dichiarato 1: requisito violato
```

«Per questo il consumer controlla nuovamente il bound dopo la chiamata. Se output è sotto minimumOutput, fa revert e non aggiorna lastOutput.»

```bash
bash demo.sh router
```

**Risultato atteso:** due test PASS: router ABI-compatibile che restituisce troppo poco rifiutato; revert del router propagato senza aggiornare lo stato.

**Domanda:** «Se il router restituisce novecento, abbiamo dimostrato che novecento token sono arrivati?»

«No. Questi mock restituiscono numeri, non trasferiscono token. In un'integrazione reale occorre stabilire quali effetti osservare, per esempio variazioni dei saldi. Un dato dichiarato dalla dipendenza non è sempre una misura indipendente del suo comportamento.»

## 6. Lo stesso indirizzo può comportarsi diversamente domani

[Apri `src/DependencyConsumer.sol`.]

«L'indirizzo provider è immutable, ma il comportamento del contratto a quell'indirizzo non è necessariamente costante. Può dipendere dallo stato, da un amministratore o da un'implementazione aggiornabile.

Il mock ci permette di farlo rispondere correttamente una volta e fallire dopo. Un refresh fallito non deve cancellare o sostituire l'ultimo valore valido.»

[Disegna una sequenza d'esempio; i numeri servono alla lavagna.]

```text
Ore 10:00: refresh valido, valore 100
Ore 10:01: provider fallisce, cache ancora 100
Durata massima cache: 5 minuti
Ore 10:05: cache accettata al confine
Ore 10:05:01: cache scaduta, uso rifiutato
```

«Conservare il valore è una cosa; autorizzarne l'uso è un'altra. La funzione `cachedValue` controlla quanto è vecchio il refresh. Il getter pubblico `lastGoodValue` espone invece il dato memorizzato senza fare quel controllo.

Chi integra il contratto deve usare il percorso che applica la policy, non aggirarla leggendo il getter più comodo.»

```bash
bash demo.sh cache
```

**Risultato atteso:** tre test PASS: guasto dopo un successo senza corruzione della cache, confine massimo accettato, cache più vecchia rifiutata.

**Domanda:** «Il timestamp del refresh prova che il dato è stato prodotto dalla fonte in quel momento?»

«No. Misura quando l'abbiamo aggiornato localmente. Se il provider ci restituisce oggi un valore prodotto ieri senza dircelo, questa cache da sola non scopre l'età alla fonte. È un'assunzione da dichiarare.»

«Qui vedete il compromesso fra sicurezza e disponibilità: una cache limitata può consentire di proseguire durante un guasto breve; superato il limite scelto, preferiamo fermarci al rischio di usare indefinitamente un dato vecchio.»

## 7. Limitare i target sposta la fiducia verso chi mantiene la lista

[Apri `src/AllowlistedExecutor.sol`.]

«L'operator non può chiamare qualsiasi indirizzo: il target deve essere nella allowlist. L'admin decide chi entra ed esce dalla lista.

Abbiamo separato il potere di scegliere le dipendenze da quello di invocarle. Ma l'admin della lista è ora un punto di fiducia importante: può cambiare quali contratti sono ammessi.»

```bash
bash demo.sh allowlist
```

**Risultato atteso:** due test PASS: target non ammesso rifiutato; dipendenza ammessa che reverte non incrementa il contatore dei completamenti.

«Una allowlist per indirizzo non è una lista di tutte le operazioni sicure. L'operator sceglie ancora i dati della chiamata. Dobbiamo vedere quali funzioni espone il target e con quale autorità riceve la chiamata.

Inoltre un target ammesso potrebbe essere un proxy: l'indirizzo resta uguale, mentre il codice eseguito cambia. Questo ci porta alla prossima lezione.»

## 8. Esercizio: la mappa della fiducia

«Disegnate un consumer che usa un router e un oracle, entrambi aggiornabili. Per ogni componente scrivete chi può cambiarlo e quale danno può propagarsi al consumer.»

[Lascia tre minuti.]

**Soluzione da guidare:** consumer dipende dal risultato del router e dal dato oracle; aggiungere le autorità che possono sostituire indirizzi o implementation; annotare controlli sul minimo, timestamp e asset; distinguere blocco del servizio, falso risultato e uso di privilegi del consumer. L'ampiezza delle conseguenze viene talvolta chiamata blast radius: descriverla con effetti concreti è più utile dell'etichetta.

«Non possiamo smettere la mappa al primo indirizzo. La dipendenza può avere a sua volta altre dipendenze e altri amministratori.»

## 9. Chiusura

«Abbiamo distinto errori tecnici e risultati semanticamente sbagliati. Abbiamo scelto quando propagare un fallimento, quando tollerarlo e come renderlo osservabile.

Il confine di fiducia comprende anche la durata dei dati, i permessi residui e chi può cambiare il comportamento dei componenti. Nella lezione 11 vedremo il meccanismo che consente di mantenere lo stesso indirizzo e lo stesso stato usando codice nuovo: proxy e delegatecall.»

**Percorso breve:** notifica, falso successo, output uno contro minimo novecento e cache. La allowlist può essere discussa sulla mappa finale. [Esercizi](exercises/README.md).

## Promemoria del docente

Le prove isolano proprietà diverse in contratti diversi. Non presentare CheckedDependency come una soluzione completa a ogni rischio di chiamata esterna né NotificationEscrow come un pagamento reale. `bash demo.sh help` elenca le selezioni; se il terminale non parte, torna a input, risultato della dipendenza e aggiornamento consentito dello stato.
