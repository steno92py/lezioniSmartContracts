# Lezione 6 — Access control

**Copione parlato.** Le virgolette contengono il discorso; le parentesi quadre indicano file e attività. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/06-access-control
```

Apri `src/access/EscrowAdminVulnerable.sol`, `EscrowAdmin.sol` e `test/AccessControl.t.sol`. Le demo sono facoltative, locali e indipendenti. Rimani nella cartella della lezione.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Permessi prima dei modifier | 0–15 | 0–10 |
| Pausa e partecipanti | 15–31 | 10–21 |
| Caller diretto e intermediario | 31–43 | 21–29 |
| Ruoli operativi | 43–59 | 29–40 |
| Grant, revoke e potere amministrativo | 59–71 | 40–49 |
| Ownership in due fasi | 71–83 | 49–56 |
| Esercizio e chiusura | 83–90 | 56–60 |

## 1. Chi può fare cosa?

«Nella lezione 5 il problema era il momento in cui il credito veniva consumato. Oggi mettiamo a fuoco l'identità: una funzione può aggiornare bene lo stato ed essere comunque accessibile alla persona sbagliata.

Immaginiamo un escrow con buyer, seller e admin. Buyer e seller sono parti dell'accordo; admin gestisce la configurazione. Essere coinvolti nell'accordo non significa automaticamente poter mettere in pausa il sistema.

Prima di aprire i modifier, scriviamo una matrice dei permessi. Una riga per operazione, una colonna per attore. È la specifica con cui confronteremo il codice.»

[Compila per il primo contratto.]

| Operazione in `EscrowAdmin` | Admin | Buyer | Seller | Estraneo |
| --- | --- | --- | --- | --- |
| `setPaused(true/false)` | Sì | No | No | No |

«Non esiste una regola universale per cui il buyer debba essere admin. Possiamo scegliere ruoli diversi in altri sistemi, ma qui questa è la policy.»

## 2. Una variabile chiamata admin non protegge una funzione

[Mostra `setPaused` della versione vulnerabile.]

«Il contratto memorizza un indirizzo admin. Ma la funzione che cambia la pausa non lo controlla.

Dichiarare la variabile non crea un controllo invisibile: ogni percorso che modifica uno stato protetto deve applicare la policy.

La prova più piccola consiste nel chiamare da un estraneo e leggere `paused`. Se l'estraneo riesce a cambiarlo, abbiamo dimostrato che quel privilegio è esposto.»

[Passa alla versione corretta e al modifier `onlyAdmin`.]

«Qui confrontiamo il caller immediato con admin prima di eseguire il corpo. Il test deve verificare sia il rifiuto dell'estraneo sia il percorso consentito all'admin.»

```bash
bash demo.sh pausa
```

**Risultato atteso:** tre test PASS: stranger mette in pausa la variante vulnerabile; stranger è rifiutato nella corretta; admin può pausare e riattivare.

**Domanda:** «Se tutti i caller vengono rifiutati, il contratto è corretto?»

«No: avremmo bloccato anche l'uso legittimo. Ogni permesso richiede almeno una prova positiva e una negativa significativa.»

## 3. Partecipazione economica e amministrazione

«Ora usiamo come caller il buyer e poi il seller. Non sono estranei all'accordo, ma non hanno il ruolo amministrativo.

Questi casi scoprono un errore di ragionamento frequente: “è uno dei soggetti principali, quindi può configurare tutto”. La matrice dice il contrario.»

```bash
bash demo.sh partecipanti
```

**Risultato atteso:** due test PASS: buyer e seller non sono implicitamente admin.

[Chiedi un esempio di conseguenza di una pausa non autorizzata.]

«Può bloccare operazioni degli utenti. Non serve che l'attaccante riceva denaro per avere un problema di sicurezza. L'impatto dipende da quali funzioni leggono la pausa e da quali vie d'uscita restano.»

## 4. Non prendere in prestito l'identità dell'origine

[Apri `src/access/TxOriginVault.sol`. Disegna il percorso.]

```text
Owner → Forwarder → setProtectedValue nel target
```

«Riprendiamo brevemente il concetto della lezione 1, ora come controllo di privilegio. Nel target il caller diretto è il forwarder. L'origine della transazione è ancora l'owner del nostro esempio.

Se autorizziamo in base all'origine, permettiamo all'intermediario di agire attraverso una transazione avviata dall'owner. Se la policy richiede una chiamata diretta dell'owner, dobbiamo controllare `msg.sender`.»

```bash
bash demo.sh identita
```

**Risultato atteso:** tre test PASS: chiamata indiretta accettata dalla variante con origin, rifiutata da quella con sender, owner diretto accettato dalla corretta.

«Non concludiamo che ogni intermediario sia vietato. Un controller autorizzato può essere un contratto. Dobbiamo dichiarare quale indirizzo deve comparire come caller nel punto in cui applichiamo il permesso. Ci torneremo con multisig e timelock.»

## 5. Da un admin a ruoli distinti

[Apri `src/access/EscrowRoles.sol`.]

«Ora separiamo due operazioni: mettere in pausa e risolvere una disputa. Non vogliamo assegnare entrambe a chi deve fare soltanto la prima.

Un ruolo è un identificatore associato a una lista di account. `hasRole` risponde se un account possiede quel ruolo. Il modifier richiede il ruolo specifico dell'operazione.»

[Compila la matrice del nuovo contratto.]

| Operazione in `EscrowRoles` | Admin iniziale | Pauser | Arbiter |
| --- | --- | --- | --- |
| Cambiare pausa | No, senza un grant | Sì | No |
| Risolvere disputa | No, senza un grant | No | Sì |
| Concedere e revocare ruoli | Sì | No | No |

«Il costruttore assegna inizialmente tre ruoli a tre indirizzi. Il pauser può cambiare `paused`; l'arbiter può segnare la disputa risolta; l'admin gestisce le assegnazioni.

Questa separazione viene chiamata principio del minimo privilegio: a ciascun compito attribuiamo i poteri necessari. Ma dobbiamo studiare anche chi può modificare quella distribuzione.»

```bash
bash demo.sh ruoli
```

**Risultato atteso:** tre test PASS: pauser non risolve, arbiter non pausa, admin non possiede automaticamente i ruoli operativi.

**Domanda:** «L'admin non può quindi ottenere il potere di pausa?»

«Può concedersi il ruolo se la policy di amministrazione lo permette, come qui. Il test dimostra che non lo possiede implicitamente, non che non possa mai acquisirlo. Il potere di assegnare un privilegio è esso stesso molto importante.»

## 6. Chi amministra chi?

[Mostra `getRoleAdmin`, `grantRole` e `revokeRole`.]

«Ci sono due domande distinte: chi possiede il ruolo e chi può concederlo.

Per concedere un ruolo il contratto cerca il suo ruolo amministratore, poi verifica se il caller lo possiede. In questo laboratorio il mapping degli amministratori usa il valore predefinito zero, che corrisponde a `DEFAULT_ADMIN_ROLE`.

Quindi dobbiamo guardare anche l'amministrazione dell'admin stesso. Questo modello minimale permette al default admin di gestire anche quel ruolo: non è un sistema completo di recupero o governance.»

[Descrivi una sequenza a tre passi.]

```text
1. Bob non ha PAUSER_ROLE → setPaused rifiutata.
2. Admin concede PAUSER_ROLE a Bob → Bob può operare.
3. Admin revoca PAUSER_ROLE a Bob → le nuove operazioni sono rifiutate.
```

```bash
bash demo.sh assegnazioni
```

**Risultato atteso:** due test PASS: concessione e revoca funzionano; un non-admin non può concedere il ruolo.

«La revoca cambia i permessi futuri. Non annulla automaticamente le operazioni già eseguite mentre Bob era autorizzato. Se Bob ha messo in pausa, serve un'operazione successiva consentita per cambiare quello stato.»

**Nota pratica per leggere i test:** salva un role ID in una variabile prima di `vm.prank`. Un getter esterno chiamato come argomento può consumare l'effetto del prank prima della chiamata che intendevi impersonare. Preparazione dell'input e impersonazione devono restare leggibili.

## 7. Trasferire ownership senza perdere il controllo per un errore di indirizzo

[Apri `src/access/Ownable2StepLite.sol`.]

«Cambiare chi governa il contratto è una transizione sensibile. Con due fasi separiamo proposta e accettazione.

L'owner corrente chiama transferOwnership indicando il candidato. Questa prima operazione scrive `pendingOwner`, ma non cambia `owner`.

Poi il candidato chiama acceptOwnership. Solo allora il ruolo si sposta e la proposta viene azzerata.»

| Momento | Owner | Pending owner |
| --- | --- | --- |
| Inizio | Alice | Nessuno |
| Alice propone Bob | Alice | Bob |
| Bob accetta | Bob | Nessuno |

**Domanda:** «Dopo la proposta Bob può già chiamare le funzioni onlyOwner?»

«No. L'accettazione è il momento in cui cambia il privilegio. Dopo quel passaggio Alice non è più owner.»

```bash
bash demo.sh ownership
```

**Risultato atteso:** tre test PASS: proposta senza spostamento immediato, accettazione riservata al candidato, trasferimento effettivo con pending azzerato.

«Questo evita che una semplice proposta consegni subito il ruolo a un indirizzo incapace di accettare. Non dimostra che il nuovo owner sia affidabile, né aggiunge un ritardo o più firme: quelle sono proprietà diverse.»

## 8. Esercizio: una matrice che genera test

«Aggiungiamo una funzione per cambiare la fee. Decidete chi può chiamarla e chi può attribuire quel ruolo. Poi proponete tre test.»

[Lascia tre minuti.]

**Una soluzione possibile:** solo un fee manager può cambiare la fee; admin può assegnare il ruolo. Test positivo del fee manager, negativo di buyer o stranger con configurazione invariata, revoca seguita da nuovo tentativo rifiutato. Se esiste un massimo di fee, serve anche un test sul valore: essere autorizzati non rende valido qualsiasi argomento.

«Questo è il collegamento con la prossima lezione. L'access control risponde a chi. Una persona autorizzata può comunque ripetere un'azione nel momento sbagliato e creare un problema logico.»

## 9. Chiusura

«Abbiamo trasformato l'access control in una matrice verificabile. Siamo partiti da una funzione senza controllo, abbiamo distinto partecipanti e amministratori, seguito l'identità attraverso un intermediario e separato ruoli operativi e gestione dei ruoli.

Quando leggete un contratto, cercate tutti i percorsi che scrivono una variabile critica, non soltanto il modifier più evidente. E quando trovate un ruolo, chiedete chi può concederlo, revocarlo o trasferirlo.

Nella lezione 7 vedremo un seller autorizzato che crea troppo credito senza aggirare alcun controllo di identità.»

**Percorso breve:** matrice, pausa, ruoli e ownership. L'esempio origin può essere un richiamo alla 1 senza demo. [Esercizi](exercises/README.md).

## Promemoria del docente

I contratti sono esempi separati: `EscrowAdmin` consente pausa all'admin, `EscrowRoles` richiede PAUSER_ROLE. Non fondere le due matrici. `resolveDispute` è una dimostrazione di autorizzazione, non un arbitrato completo. Se una demo non parte, usa le sequenze prima/dopo e i test nominati da `bash demo.sh help`.
