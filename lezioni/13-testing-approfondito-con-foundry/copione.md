# Lezione 13 — Testing approfondito con Foundry

**Copione da tenere aperto mentre insegni.** Non serve improvvisare una spiegazione partendo dai nomi dei test: ogni blocco contiene il ragionamento da dire. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/13-testing-approfondito-con-foundry
```

Apri `REQUIREMENTS.md`, `src/TestingEscrow.sol` e `test/unit/Deposit.t.sol`. Foundry è già stato introdotto nella lezione 2: oggi il tema è scegliere prove che distinguano un'implementazione corretta da una difettosa.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| Requisiti e primo test economico | 0–18 | 0–12 |
| Errori precisi e precondizioni | 18–33 | 12–22 |
| Confini, eventi e isolamento | 33–47 | 22–32 |
| Mock e dipendenze | 47–61 | 32–42 |
| Tre regressioni | 61–76 | 42–53 |
| Workflow, esercizio e passaggio al fuzz | 76–90 | 53–60 |

## 1. Verde rispetto a quale affermazione?

«Oggi partiamo da una frase che suona rassicurante: tutti i test passano. È una buona notizia, ma manca un pezzo: che cosa affermano quei test?

Se deposito cento token e il test controlla soltanto che la funzione non faccia revert, potrebbe passare anche se il contratto accredita duecento, dimentica il deposito oppure manda i token al destinatario sbagliato.

Un test è un esperimento con una domanda precisa. Prepariamo una situazione, eseguiamo un'azione e confrontiamo il risultato osservato con una proprietà che abbiamo deciso prima.»

[Scrivi.]

```text
Requisito → scenario → azione → osservazioni → risultato atteso
```

«Non vogliamo tradurre ogni riga del contratto in una riga del test. Vogliamo tradurre una promessa del sistema in una prova che possa smentirla.»

## 2. Prima leggiamo il contratto che stiamo promettendo agli utenti

[Apri `REQUIREMENTS.md`.]

«La specifica di questo Escrow dice: deposita soltanto il buyer, con importo positivo e una volta sola. Il prezzo deve essere positivo, abbastanza recente e non provenire dal futuro. Il credito deve essere coperto dai token ricevuti. Il buyer può rilasciare al seller oppure chiedere rimborso dalla deadline. Gli stati finali non riaprono il contratto. La fee è limitata e la configurazione è riservata all'owner.

Queste frasi ci danno categorie di prove: percorso valido, chiamante sbagliato, input sbagliato, confine temporale, dipendenza che fallisce e tentativo di ripetere un'azione.»

[Disegna.]

```text
Created → Funded → Released
              └─→ Refunded, dalla deadline
```

«Questo laboratorio rifiuta un trasferimento che consegna meno dell'importo richiesto. Nella lezione 8 avevamo visto anche la politica di accreditare il netto. Sono due specifiche diverse: il test corretto dipende da quale abbiamo scelto qui.»

**Domanda:** «Da dove ricaviamo l'atteso: dal codice o dal requisito?»

«Dal requisito, usando il codice per costruire lo scenario e osservare gli effetti. Se ricopiamo nel test lo stesso errore della funzione, i due potrebbero concordare perfettamente e sbagliare insieme.»

## 3. Primo test: seguire i cento token

[Apri `test/unit/Deposit.t.sol`, test_BuyerCanDepositAndStateDeltaIsCorrect.]

«La preparazione crea buyer, seller, owner, token, oracle ed Escrow. Il buyer ha token e autorizza l'Escrow a spenderli. Chiamiamo deposit con cento token.

Dopo il deposito controlliamo più facce della stessa promessa: lo stato è Funded, depositedAmount vale cento, la liability vale cento, il saldo del buyer è diminuito di cento e l'Escrow possiede cento. Inoltre il prezzo salvato è quello valido fornito dall'oracle.»

| Osservazione | Prima | Dopo il deposito di 100 |
| --- | --- | --- |
| Stato | Created | Funded |
| Credito registrato | 0 | 100 |
| Liability | 0 | 100 |
| Saldo Escrow nella fixture | 0 | 100 |
| Saldo buyer | B | B − 100 |

«Nel sorgente vedete 100 ether come numero. Qui non inviamo cento ETH: stiamo usando la costante numerica 100 × 10 alla diciottesima per un token del mock con quella scala. Guardate sempre quale asset si sta muovendo.»

```bash
bash demo.sh deposito
```

**Risultato atteso:** un test PASS sul deposito e sui suoi effetti economici.

«Il confronto fra saldo e liability ci dice se il credito è coperto in questo scenario. L'uguaglianza vale nella fixture senza donazioni. In un sistema che può ricevere token extra, la proprietà di copertura è generalmente saldo maggiore o uguale alla liability: un saldo in eccesso non significa automaticamente insolvenza.»

## 4. Un revert qualsiasi può nascondere un controllo mancante

«Ora vogliamo verificare che un estraneo non possa depositare. Se scriviamo soltanto expectRevert, il test potrebbe passare perché l'estraneo non ha allowance. Avremmo ottenuto un errore, ma non la prova dell'autorizzazione.

Qui ci aspettiamo precisamente Unauthorized con l'indirizzo dell'estraneo. In questo modo un fallimento del token non soddisfa la nostra aspettativa.»

[Mostra nel file la combinazione expectRevert con abi.encodeWithSelector e vm.prank.]

«vm.prank cambia il chiamante della chiamata bersaglio. expectRevert specifica l'errore previsto. Dopo il tentativo controlliamo che lo stato sia ancora Created, l'importo zero e i saldi non abbiano subito la modifica vietata.»

```bash
bash demo.sh errore
```

**Risultato atteso:** due test PASS: estraneo rifiutato senza effetti persistenti; chiamante controllato prima dell'importo.

«Il secondo caso usa un estraneo e importo zero: ci sono due ragioni possibili per rifiutare. La specifica di questo laboratorio sceglie di controllare prima il chiamante, quindi attendiamo Unauthorized, non ZeroAmount. Stiamo fissando anche l'ordine dell'errore quando è intenzionalmente parte del comportamento.»

[Apri `test/unit/Settlement.t.sol`, test_UnauthorizedCallerCannotReleaseEvenWhenFunded.]

«Per release, prepariamo prima un deposito valido. Così il contratto si trova proprio nello stato in cui l'operazione sarebbe consentita al buyer. Un test di autorizzazione eseguito soltanto in Created potrebbe essere respinto dal controllo di stato e non esercitare la situazione che ci interessa.»

**Frase da ripetere:** «Prepariamo le altre condizioni valide per isolare la regola che vogliamo mettere alla prova.»

## 5. I confini decidono il significato della regola

[Apri `test/unit/Administration.t.sol`.]

«La fee massima è mille basis point. Diecimila basis point sono cento per cento, quindi mille sono dieci per cento. La specifica dice massimo incluso.

Provare solo cinquecento e duemila non distingue bene tutte le interpretazioni del confine. Proviamo novecentonovantanove, mille e milleuno.»

| Fee | Esito previsto |
| ---: | --- |
| 999 bps | accettata |
| 1000 bps | accettata |
| 1001 bps | rifiutata, vecchia fee conservata |

```bash
bash demo.sh confini
```

**Risultato atteso:** quattro test PASS: i tre valori di confine e il cambiamento autorizzato con evento e stato.

«Se qualcuno cambia il controllo da maggiore di mille a maggiore o uguale a mille, il test sul valore mille fallisce. Questo è un buon segno: il test distingue due implementazioni quasi identiche con un comportamento diverso.»

[Mostra expectEmit.]

«Controlliamo anche evento, emettitore e campi rilevanti. Ma un evento corretto non prova che lo storage sia cambiato: il contratto potrebbe emettere FeeUpdated e dimenticare l'assegnazione. Per questo leggiamo anche feeBps dopo la chiamata.»

[Mostra in Settlement i due test sulla deadline.]

«Per il rimborso usiamo deadline meno un secondo ed esattamente deadline. vm.warp modifica il tempo del test; non è un'attesa reale. Prima del limite rifiutiamo, al limite accettiamo. Questi due punti rendono esplicita la differenza fra minore e minore o uguale.»

## 6. setUp e helper: comodità senza nascondere la domanda

[Apri `test/helpers/EscrowTestBase.sol`.]

«setUp prepara una fixture nuova per ciascun test. Il test che rilascia i fondi non lascia il successivo in Released. Ogni prova deve poter essere capita ed eseguita senza dipendere dall'ordine delle altre.

Gli helper evitano di ripetere approve e deposit in ogni scenario, ma dobbiamo sapere che cosa fanno. Se sto testando deposit, non voglio nascondere in un helper tutte le osservazioni che dovrebbero spiegare il comportamento. Se sto testando release, un helper per preparare un deposito valido è utile.»

**Domanda:** «Un test con molte righe è migliore?»

«No. Conta se prepara una situazione leggibile e osserva la proprietà giusta. Tante asserzioni scollegate possono rendere difficile capire il fallimento. Più osservazioni sullo stesso trasferimento, invece, possono essere necessarie per seguirne tutti gli effetti.»

## 7. Mock: decidere quale dipendenza stiamo controllando

[Apri `test/integration/OracleIntegration.t.sol`.]

«Un mock ci permette di scegliere il comportamento della dipendenza. Possiamo fornire un prezzo valido, un timestamp troppo vecchio oppure un revert.

Non stiamo dimostrando che un oracle reale non fallirà mai. Stiamo dimostrando come l'Escrow reagisce ai comportamenti che abbiamo modellato.»

[Mostra test_MockCallCanIsolateOracleReturnValue.]

«vm.mockCall intercetta la chiamata a latestPrice e fornisce la risposta scelta. vm.expectCall verifica che quella chiamata avvenga. Ma chiamare non significa usare correttamente: per questo controlliamo che depositPrice contenga proprio il valore restituito dal mock, 4200 con scala a otto decimali.»

```bash
bash demo.sh integrazione
```

**Risultato atteso:** quattro test PASS: risposta controllata usata nel deposito, revert dell'oracle propagato senza deposito persistente, prezzo al limite di età accettato, un secondo oltre rifiutato.

«Il limite di età qui è un giorno. Un prezzo vecchio esattamente un giorno è accettato; un giorno e un secondo è rifiutato. Questo definisce una politica di freschezza, non dimostra che il prezzo sia economicamente corretto.

Nel caso di oracle che reverte, ci aspettiamo l'errore della dipendenza e uno stato ancora Created, senza token depositati nell'Escrow. Stiamo verificando anche cosa rimane dopo il fallimento.»

**Domanda:** «Posso simulare sempre un oracle che risponde bene?»

«Puoi, ma allora avrai verificato solo quella condizione. La selezione dei comportamenti del mock è parte della qualità della prova. La dipendenza che fallisce non deve comparire per caso: la modelliamo intenzionalmente.»

## 8. Regressione: conservare una prova del difetto

«Una regressione è un test che impedisce di reintrodurre un errore già individuato. Per essere utile deve conservare le condizioni che lo rendevano possibile e verificare l'effetto che vogliamo impedire.»

### Caso A — Richiesti cento, arrivati novantanove

[Apri `test/regression/TokenBehaviorRegression.t.sol`.]

«Il token trattiene l'uno per cento. Richiediamo cento, l'Escrow ne riceverebbe novantanove. Se registrasse un debito di cento, mancherebbe un token di copertura.

La politica di questa lezione rifiuta la differenza con UnexpectedReceived(100, 99), usando nel codice la scala del token. Verifichiamo anche il rollback: il buyer conserva il saldo iniziale, l'Escrow rimane a zero, liability zero e stato Created. Non basta aver segnalato l'errore dopo aver perso soldi.»

### Caso B — Il pagamento fallisce dopo la scrittura dello stato

«Prepariamo un deposito valido di cento. Poi configuriamo il token affinché il payout restituisca false. release scrive lo stato terminale prima della chiamata esterna, ma propaga il fallimento del token.

Il revert deve riportare tutto a Funded, con liability cento, saldo Escrow cento e nessun pagamento al seller. CEI non significa sacrificare il credito se la call fallisce: il rollback della transazione conserva gli effetti corretti del fallimento.»

### Caso C — Il callback prova a prelevare due volte

[Apri `test/regression/ReentrancyRegression.t.sol` e `src/WithdrawalVault.sol`.]

«Qui cambiamo componente: usiamo un vault ETH separato. Non presentiamo questo test come una prova della reentrancy di TestingEscrow, che segue un altro flusso.

Il ricevente ha credito uno, un utente onesto ha credito due e il vault contiene tre. Nel callback il ricevente tenta un secondo prelievo. Dobbiamo osservare sia che l'attacco sia stato tentato sia che il secondo prelievo non sia riuscito.

Alla fine il ricevente ottiene soltanto uno; il credito onesto resta due, il vault conserva due e le passività residue sono due. Se non controllassimo callbackAttempted, potremmo avere un test verde perché il callback non si è mai attivato.»

```bash
bash demo.sh regressione
```

**Risultato atteso:** tre test PASS, uno per ciascuna regressione descritta. Leggi le asserzioni economiche oltre al nome del test.

## 9. Un workflow completo: ogni token ha una destinazione

[Apri `test/integration/WorkflowIntegration.t.sol`.]

«Facciamo ora un percorso dall'inizio alla fine. L'owner configura una fee del cinque per cento. Il buyer deposita quattrocento token. La liability diventa quattrocento ed è coperta. Il buyer chiama release.

Cinque per cento di quattrocento è venti. Al seller vanno trecentottanta, all'owner venti. Lo stato è Released, la liability zero e il saldo dell'Escrow zero.»

```text
400 depositati = 380 al seller + 20 all'owner + 0 residui
```

```bash
bash demo.sh workflow
```

**Risultato atteso:** due test PASS: il flusso economico completo e una fixture che riparte indipendente per ogni test.

«Questo esempio fissa anche la destinazione della fee: in questa lezione viene pagata all'owner. Non dobbiamo importare automaticamente questa conclusione in un altro Escrow del corso. Ogni laboratorio ha una specifica da leggere.»

## 10. Coverage, prove mancanti e passaggio alla lezione 14

«La coverage indica quale codice è stato esercitato. Non misura da sola quanto siano forti le asserzioni. Posso attraversare tutta release e controllare soltanto lo stato, dimenticando che il seller non ha ricevuto nulla.

Unit, integration e regression descrivono lo scopo dei test, non una classifica. Il test unitario isola una regola, quello d'integrazione collega componenti, quello di regressione conserva un caso di errore. Per valutare la suite torniamo ai requisiti e cerchiamo affermazioni ancora senza una prova.»

**Esercizio da fare in aula:** «Un test chiama release prima di depositare, usa un estraneo e si aspetta un revert qualsiasi. Che cosa sappiamo davvero?»

**Risposta pronta:** «Sappiamo soltanto che quella chiamata fallisce. Per verificare l'autorizzazione prepariamo Funded e attendiamo Unauthorized. Per verificare lo stato Created usiamo il buyer e attendiamo InvalidState. Separiamo le domande.»

**Secondo esercizio:** «Il test controlla che il saldo finale del seller sia 380. Come lo rendiamo robusto se il seller parte con token propri?»

**Risposta:** «Salviamo il saldo iniziale e controlliamo che la differenza sia 380. Il saldo assoluto funziona nella fixture in cui sappiamo che partiva da zero.»

«Finora scegliamo manualmente importi e sequenze. È indispensabile per confini e regressioni, ma non esaurisce i possibili casi. Nella prossima lezione faremo generare a Foundry molti input e molte sequenze. Le asserzioni devono restare significative: moltiplicare i casi di un test debole non lo trasforma automaticamente in una prova forte.»

## Percorso breve e alternativa alla demo

Nei 60 minuti conserva deposito, errore preciso, fee al confine e le tre regressioni. Leggi mock e workflow senza aprire ogni trace. Non reinstallare Foundry in aula: se il terminale si ferma, usa le tabelle di saldi e leggi dal file la preparazione, la chiamata e le asserzioni.

Come esercizio autonomo assegna un requisito di `REQUIREMENTS.md`: lo studente deve indicare il percorso valido, il caso rifiutato, l'errore preciso e gli effetti che devono restare invariati. Chiedi infine quale modifica errata del contratto farebbe fallire il suo test: la risposta mostra se sa quale promessa sta verificando.
