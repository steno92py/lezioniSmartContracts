# Lezione 11 — Proxy, delegatecall e upgradeability

**Copione da dire ad alta voce.** Le parentesi quadre indicano cosa mostrare. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/11-proxy-delegatecall-upgradeability
```

Rimani qui per tutte le demo. Apri `src/lab/ContextLogic.sol`, `src/lab/SimpleProxy.sol` e `src/upgrade/UpgradeableEscrowV1.sol`. Oggi separiamo quattro problemi: contesto di esecuzione, inizializzazione, autorizzazione e compatibilità dello storage.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Contesto di delegatecall | 0–15 | 0–10 |
| Collisione e slot ERC-1967 | 15–28 | 10–19 |
| Inizializzazione | 28–42 | 19–29 |
| Autorità di upgrade | 42–55 | 29–39 |
| Migrazione e layout | 55–76 | 39–53 |
| Esercizio, domande e chiusura | 76–90 | 53–60 |

## 1. Cambiare codice conservando l'indirizzo

«Finora abbiamo ragionato su contratti con una logica già decisa al deploy. Se scopriamo un errore, possiamo distribuire un contratto nuovo. Ma gli utenti conoscono l'indirizzo vecchio e i dati si trovano lì.

Un proxy permette di conservare un indirizzo e il suo storage delegando l'esecuzione a un altro contratto, chiamato implementation. Cambiando l'indirizzo dell'implementation possiamo cambiare la logica usata dal proxy.

Questo introduce un potere enorme: chi controlla l'upgrade può cambiare le regole future del sistema. Non è soltanto un modo comodo per correggere bug. È una parte del modello di fiducia.»

[Disegna.]

```text
Alice → Proxy ──delegatecall──→ Implementation V1
          │
          └── storage del sistema

Dopo l'upgrade:
Alice → stesso Proxy ──delegatecall──→ Implementation V2
          │
          └── stessi dati, interpretati dalla nuova logica
```

«L'upgrade non converte magicamente i dati. Sostituisce il codice che li legge. Per questo dobbiamo capire dove il codice esegue e come interpreta lo storage.»

## 2. Codice e contesto sono due cose diverse

[Mostra `src/lab/ContextLogic.sol` e `test/DelegatecallContext.t.sol`.]

«Con una normale call da Proxy a Logic, Logic esegue sul proprio storage e vede Proxy come chiamante. Con delegatecall usiamo il codice di Logic ma restiamo nel contesto di Proxy.

Nel percorso Alice → Proxy → delegatecall, il codice delegato vede Alice come msg.sender e Proxy come address(this). Le scritture vanno nello storage del Proxy. Anche msg.value viene conservato nel contesto delegato; delegatecall non è una seconda spedizione autonoma di ETH verso Logic.»

| Domanda nel codice delegato | Risposta nel percorso mostrato |
| --- | --- |
| Da dove arriva il codice? | Implementation |
| Quale storage viene letto e scritto? | Proxy |
| Chi è `address(this)`? | Proxy |
| Chi è `msg.sender`? | Alice |

```bash
bash demo.sh contesto
```

**Risultato atteso:** un test PASS che distingue il contesto del proxy dall'istanza della logica.

«Non basta ricordare la parola delegatecall. Quando leggiamo una funzione dobbiamo sapere su quale contratto finirà ogni scrittura. La stessa funzione chiamata direttamente sull'implementation lavora su uno storage diverso.»

**Domanda:** «Se chiamo initialize direttamente sulla logica, ho configurato anche il proxy?»

«No. I due indirizzi hanno storage distinti. Questa distinzione sarà centrale fra pochi minuti.»

## 3. La collisione: due significati per gli stessi byte

[Apri `src/lab/SimpleProxy.sol` e `src/lab/SimpleLogicV1.sol`.]

«Questo primo proxy è volutamente sbagliato. Conserva l'indirizzo dell'implementation nello slot zero. La logica mette nello slot zero la variabile value.

La logica non sa che il proxy ha usato quello spazio per altro. Quando esegue in delegatecall, scrivere value significa scrivere nello slot zero del proxy. Il numero dell'applicazione sovrascrive l'indirizzo che il proxy usa per scegliere il codice.»

[Scrivi: `slot 0: implementation` e sotto `slot 0: value = 123`.]

«Non abbiamo modificato una variabile per nome. Abbiamo modificato byte a una posizione. I nomi del sorgente non creano spazi separati nello storage.»

```bash
bash demo.sh collisione
```

**Risultato atteso:** due test PASS che dimostrano difetti: una scrittura applicativa corrompe il puntatore; un estraneo può effettuare un upgrade nel proxy vulnerabile.

«Sono due problemi distinti. Spostare il puntatore risolve la collisione mostrata, ma non decide chi può modificarlo. Aggiungere onlyOwner non corregge da solo la posizione sbagliata dello slot.»

[Apri `src/proxy/EducationalERC1967Proxy.sol`.]

«Il proxy successivo usa lo slot standard ERC-1967 per il puntatore all'implementation. Serve a separare quel metadato dal normale layout applicativo. Non serve imparare a memoria il valore esadecimale: dobbiamo riconoscere che proxy e logica di upgrade devono concordare sulla posizione.

Attenzione: lo slot standard non garantisce che due versioni dell'applicazione abbiano layout compatibili.»

## 4. Initialize: chi arriva per primo?

[Apri constructor e initialize in `src/upgrade/UpgradeableEscrowV1.sol`.]

«Il constructor della logica viene eseguito quando distribuiamo la logica. Le sue normali scritture di storage non inizializzano il proxy. Per configurare owner, buyer e seller del proxy eseguiamo initialize attraverso il proxy.

Ora guardiamo la firma: initialize riceve gli indirizzi. Se il proxy resta non inizializzato e chiunque può chiamarla, il primo chiamante può scegliere se stesso come owner. Non serve rubare una chiave: basta arrivare prima del deployer.»

[Mostra la creazione del proxy con calldata di inizializzazione nel test.]

«Per chiudere questa finestra, la creazione del proxy e l'inizializzazione avvengono nella stessa transazione. Se l'inizializzazione fallisce, deve fallire anche quella creazione. Non lasciamo fra le due azioni un contratto utilizzabile ma senza proprietario.»

```bash
bash demo.sh inizializzazione
```

**Risultato atteso:** quattro test PASS: appropriazione del proxy lasciato aperto, inizializzazione atomica corretta, implementation bloccata, seconda initialize rifiutata.

«Abbiamo tre protezioni con tre scopi diversi. L'atomicità impedisce a un estraneo di precederci sul proxy. Il numero di versione impedisce di ripetere l'inizializzazione. Il constructor blocca gli initializer dell'istanza implementation.

Il blocco della logica non blocca automaticamente il proxy: sono storage diversi. È proprio questa separazione che consente alla logica di essere bloccata e al proxy di essere inizializzato una volta.»

**Domanda:** «Posso correggere un proxy già inizializzato chiamando di nuovo initialize?»

«Qui no. Un cambio di configurazione deve passare per una funzione autorizzata o per una migrazione prevista. Rendere ripetibile initialize riaprirebbe la possibilità di riscrivere i ruoli.»

## 5. Chi può cambiare le regole?

[Mostra `upgradeToAndCall`, `onlyActiveProxy` e `proxiableUUID`.]

«In questa architettura didattica la funzione di upgrade vive nella logica. Quando la invochiamo attraverso il proxy, modifica il puntatore conservato dal proxy.

Leggiamone i controlli per responsabilità. onlyOwner decide chi ha autorità. onlyActiveProxy controlla che la funzione stia operando attraverso il proxy attivo corretto, invece che direttamente sull'istanza della logica. Infine controlliamo che la nuova destinazione abbia codice ed esponga il proxiableUUID atteso.»

«SELF è un immutable legato all'indirizzo dell'implementation. Non è una variabile ordinaria dello storage del proxy. Serve a distinguere il codice che stiamo eseguendo dal contesto nel quale lo eseguiamo.»

```bash
bash demo.sh autorita
```

**Risultato atteso:** quattro test PASS: estraneo respinto, chiamata diretta alla logica respinta, implementation non compatibile respinta, UUID errato respinto.

«Superare questi controlli non certifica che il nuovo codice sia sicuro. Un'implementation malevola può esporre l'UUID corretto. E un'implementation onesta ma con layout sbagliato può comunque danneggiare i dati. Il controllo di compatibilità tecnica non sostituisce la revisione della versione.»

## 6. Upgrade e migrazione devono riuscire insieme

[Apri `src/upgrade/UpgradeableEscrowV2.sol` e il test di upgrade autorizzato.]

«V1 conosce owner, buyer, seller, amount e funded. V2 conserva quella base e aggiunge feeBps e feeRecipient. initializeV2 configura i nuovi campi ed è riservata all'owner. Il numero di inizializzazione passa alla versione due, così questa migrazione non è ripetibile.

La funzione upgradeToAndCall cambia l'implementation ed esegue la migrazione. Se la migrazione fallisce, il revert annulla anche il cambio del puntatore. Vogliamo evitare di lasciare attiva una versione che dipende da dati ancora non configurati.»

```bash
bash demo.sh upgrade
```

**Risultato atteso:** tre test PASS: upgrade con stato conservato, migrazione fallita che ripristina il puntatore precedente, seconda inizializzazione V2 rifiutata.

[Calcolo da fare alla lavagna, distinto dai valori specifici del test.]

«Se amount vale 1.000 e feeBps vale 250, feeOnAmount restituisce 1.000 × 250 / 10.000 = 25. Il punto è che V2 usa un amount già scritto con V1.

In questo laboratorio fund registra un importo: non trasferisce realmente token o ETH. Il test dimostra continuità dei dati e autorizzazioni, non la custodia di un saldo reale.»

## 7. Gli stessi byte possono diventare il ruolo sbagliato

[Apri `src/upgrade/UnsafeLayoutV2.sol`.]

«La versione incompatibile scambia le posizioni di buyer e seller. Immaginiamo che prima slot uno contenga Alice e slot due Bob. Il nuovo codice legge seller nello slot uno e buyer nello slot due. I byte non si sono mossi, ma le identità applicative risultano invertite.»

| Posizione | V1 | V2 compatibile | V2 incompatibile |
| --- | --- | --- | --- |
| Slot 0 | versione initializer e owner impacchettati | invariati | da confrontare con V1 |
| Slot 1 | buyer | buyer | seller |
| Slot 2 | seller | seller | buyer |
| Slot 3–4 | amount, funded | invariati | non bastano a salvare i ruoli |
| Slot 5–6 | non usati da questi campi V1 | feeBps, feeRecipient | irrilevanti per la collisione dei ruoli |

```bash
bash demo.sh layout-errato
bash demo.sh layout
```

**Risultato atteso:** il primo comando seleziona due test, uno dimostra la reinterpretazione errata e l'altro verifica l'autorizzazione dopo l'upgrade corretto. Il secondo stampa i tre layout; non esegue un test.

«Confrontiamo slot, offset, tipo e ordine dei campi, includendo l'ereditarietà. Dire “ho aggiunto una variabile” non basta: conta dove finisce. Ereditare V1 aiuta a mantenere la base in questo esempio, ma non è un certificato universale di compatibilità.

Dopo un upgrade non verifichiamo soltanto version() == 2. Verifichiamo chi è ancora buyer, chi può fare fund e quali dati economici restano leggibili.»

## 8. Esercizio guidato e domande pronte

«Il nuovo sviluppatore propone di inserire una variabile uint256 prima di buyer in V1, poi distribuire V2. Lo approviamo?»

**Risposta:** «No senza una strategia esplicita di compatibilità e migrazione. Spostare campi esistenti cambia le posizioni lette dalla nuova logica. In questo esercizio conserviamo il layout V1 e aggiungiamo i campi dopo quelli esistenti, verificando il risultato.»

«Seconda proposta: il layout è corretto, quindi togliamo onlyOwner da upgradeToAndCall.»

**Risposta:** «No. Un layout compatibile non autorizza chiunque a sostituire la logica.»

«Terza proposta: l'upgrade fallisce nella migrazione, però basta continuare e sistemarla dopo.»

**Risposta:** «Il contratto del laboratorio rifiuta questa situazione e annulla tutto. Se vogliamo migrazioni a più fasi, dobbiamo progettare esplicitamente quali operazioni restano consentite fra le fasi.»

**Se chiedono “un proxy è sicuro?”:** «La domanda va scomposta: quale proxy, chi controlla gli upgrade, come inizializziamo, quale layout conserviamo e quali controlli precedono ogni versione? Il modello didattico serve a vedere questi vincoli; non è una raccomandazione di distribuire questo codice minimale in produzione.»

## Chiusura e percorso senza terminale

«Portiamo via quattro domande: dove scrive il codice, chi inizializza, chi può sostituirlo e come il nuovo codice leggerà i dati vecchi. La prossima lezione parte dalla terza: un onlyOwner può essere corretto e lasciare comunque un potere troppo concentrato.»

Se la demo si interrompe, usa la tabella del contesto, disegna slot uno e due prima/dopo lo scambio e leggi le asserzioni in `test/UpgradeableEscrow.t.sol`. Non serve riparare l'ambiente durante la spiegazione.

Nel percorso da 60 minuti mostra una sola trace per il contesto, leggi gli altri risultati dai test e conserva inizializzazione atomica e layout incompatibile. Nell'esercizio autonomo chiedi una proposta di V3 con layout, migrazione e tre proprietà da verificare: stato preservato, chiamante non autorizzato respinto, migrazione fallita senza upgrade parziale.
