# Lezione 8 — ERC-20, allowance e integrazioni sicure

**Copione da dire ad alta voce.** Le parentesi quadre indicano le azioni; le soluzioni seguono le domande. [Laboratorio](README.md) · [Approfondimenti](teoria.md).

```bash
cd lezioni/08-erc20-allowance-e-integrazioni-sicure
```

Apri `src/token/IERC20.sol`, `src/TokenEscrow.sol` e `test/AllowanceFlow.t.sol`. Rimani qui per le demo facoltative. Token, indirizzi e saldi sono locali.

| Attività | 90 minuti | 60 minuti |
| --- | --- | --- |
| ETH contro token, tre contabilità | 0–14 | 0–9 |
| Approve e transferFrom | 14–30 | 9–20 |
| Allowance residua e ruolo buyer | 30–40 | 20–27 |
| False, revert e nessun ritorno | 40–56 | 27–39 |
| Quantità ricevuta e fee in uscita | 56–72 | 39–51 |
| Payout fallito e policy | 72–83 | 51–56 |
| Esercizio e chiusura | 83–90 | 56–60 |

## 1. Un token è un altro contratto

«Finora abbiamo spostato ETH, l'asset nativo usato attraverso il valore della chiamata. Con un ERC-20 chiediamo a un altro contratto di aggiornare i propri saldi.

Il saldo token di Alice è un numero conservato dal contratto del token. Per spostarlo chiamiamo le funzioni di quel contratto. Quindi entrano in gioco una dipendenza esterna, i suoi controlli e il suo modo di segnalare il risultato.

Guardate l'interfaccia: descrive funzioni e tipi. Non ci dice che ogni implementazione trasferisca esattamente il numero richiesto o si comporti nello stesso modo in ogni condizione.»

[Scrivi i tre numeri che seguiremo.]

```text
balanceOf(buyer)          saldo del buyer, nel contratto token
allowance(buyer, escrow)  permesso di spesa, nel contratto token
escrowedAmount           debito registrato, nel contratto escrow
```

«Tre numeri con significati diversi. La lezione consiste nel non confonderli.»

## 2. Approve non trasferisce token

«Il buyer ha cento token e vuole depositarli nell'escrow. Prima autorizza l'escrow a spenderne fino a cento, chiamando approve sul token.

Il caller di approve è il buyer. Lo spender che viene autorizzato è l'escrow. Il saldo del buyer resta cento: abbiamo modificato un permesso, non eseguito un deposito.»

[Disegna.]

```text
Buyer → token.approve(escrow, 100)
Saldo buyer: 100 → 100
Saldo escrow: 0 → 0
Allowance buyer→escrow: 0 → 100
```

«Poi il buyer chiama deposit sull'escrow. È l'escrow che chiama transferFrom sul token, chiedendo di trasferire dal buyer a se stesso.

Dentro il token `msg.sender` è l'escrow: è quello lo spender di cui viene controllata l'allowance.»

```text
Buyer → escrow.deposit(100)
          → token.transferFrom(buyer, escrow, 100)
            nel token: caller = escrow
```

[Completa la tabella riferita al token standard del laboratorio.]

| Momento | Saldo buyer | Saldo escrow | Allowance |
| --- | ---: | ---: | ---: |
| Prima di approve | 100 | 0 | 0 |
| Dopo approve 100 | 100 | 0 | 100 |
| Dopo transferFrom 100 | 0 | 100 | 0 |

```bash
bash demo.sh allowance
```

**Risultato atteso:** due test PASS: approve modifica il permesso senza spostare token; transferFrom usa l'allowance esatta e sposta i token. La tabella è un esempio numerico, non richiede di cambiare la fixture.

**Domanda:** «Se ho allowance cento ma saldo zero, ho creato cento token?»

«No. Permesso e disponibilità sono condizioni diverse. L'allowance non crea asset.»

## 3. Permesso persistente e autorizzazione applicativa

«Se autorizzo cento e lo spender ne usa quaranta, nel modello standard del laboratorio restano sessanta di allowance. Non spariscono perché l'operazione che avevo in mente è terminata.

Per capire quali poteri restano a una dipendenza, guardiamo quindi anche le autorizzazioni residue. Alcuni token trattano in modo particolare l'allowance massima: non generalizziamo il consumo osservato nel nostro mock a qualsiasi token.»

[Mostra i controlli all'inizio di `TokenEscrow.deposit`.]

«Avere saldo e allowance non basta per diventare il buyer di questo accordo. Deposit controlla prima il ruolo applicativo. Uno stranger potrebbe avere token e aver approvato l'escrow, ma resta uno stranger per la specifica.»

```bash
bash demo.sh residuo
```

**Risultato atteso:** due test PASS: allowance maggiore conserva un residuo dopo una spesa parziale; estraneo con token e allowance rifiutato dall'escrow.

«Questo collegamento con la lezione 6 è importante: il token autorizza una spesa, l'escrow autorizza una partecipazione. Sono due controlli su due contratti.»

## 4. Quattro modi di terminare una chiamata al token

[Apri `src/VulnerableTokenVault.sol`, poi `test/TokenCompatibility.t.sol`.]

«Il vault vulnerabile chiama transferFrom e registra credito senza gestire adeguatamente il risultato. Il mock del primo esperimento restituisce false e non sposta i token.

La chiamata può terminare senza revert anche se il risultato applicativo indica fallimento. Se ignoriamo il booleano, registriamo cento di credito con zero asset.»

```text
Richiesta transferFrom: 100
Valore restituito: false
Saldo ricevuto: 0
Credito vulnerabile: 100
```

```bash
bash demo.sh false-return
```

**Risultato atteso:** due test PASS: falso ritorno crea credito non coperto nel vault vulnerabile; escrow corretto rifiuta e conserva lo stato precedente.

[Apri `src/token/SafeERC20Lite.sol`, senza spiegare l'assembly riga per riga.]

«Il wrapper centralizza la gestione dell'esito. La tabella ci dice il comportamento che vogliamo capire.»

| Risposta del token | Comportamento del wrapper locale |
| --- | --- |
| Revert | Propaga il fallimento |
| Call riuscita e bool false | Fa revert |
| Call riuscita e bool true | Accetta |
| Call riuscita senza dati di ritorno | Accetta secondo la policy per questi token |

«Prima controlla anche che il target contenga codice. Una normale low-level call a un indirizzo vuoto potrebbe terminare senza eseguire la funzione del token: non vogliamo confonderla con un token compatibile che non restituisce dati.»

## 5. Nessun ritorno non è lo stesso di false

«Alcune implementazioni usate come token non restituiscono il booleano atteso. Il mock del laboratorio esegue il trasferimento e non restituisce dati.

Il wrapper accetta questo caso se la call riesce. La prova controlla il risultato sul saldo e sulla contabilità dell'escrow.»

```bash
bash demo.sh no-return
```

**Risultato atteso:** un test PASS sul deposito con token senza return data.

**Domanda:** «Quindi assenza di dati dimostra che i token sono stati trasferiti?»

«No. È una regola di compatibilità del wrapper, non una prova universale dell'effetto. Il codice dell'escrow misura inoltre l'aumento del saldo in ingresso. E un token completamente malevolo potrebbe mentire anche attraverso balanceOf: dobbiamo dichiarare quali comportamenti supportiamo e di quali dipendenze ci fidiamo.»

## 6. Trasferimento riuscito non significa importo esatto

[Mostra la misura dei saldi in `TokenEscrow.deposit`.]

«Ora il token trasferisce davvero, ma trattiene una fee. Il buyer richiede cento; nel contratto arrivano novanta.

Se il wrapper vede un trasferimento riuscito, ha fatto il proprio lavoro. Non ha promesso che il ricevuto sia uguale al richiesto.»

```solidity
uint256 beforeBalance = token.balanceOf(address(this));
token.safeTransferFrom(buyer, address(this), requestedAmount);
uint256 afterBalance = token.balanceOf(address(this));
```

«Il contratto calcola la differenza e registra il ricevuto effettivo. Questo è il balance delta.»

```text
Saldo prima: 0
Saldo dopo: 90
Ricevuto: 90 − 0 = 90
Credito: 90
```

«La scelta della lezione 8 è supportare questa fee in ingresso. Avremmo potuto definire una policy diversa: richiedere il trasferimento esatto e rifiutare il resto. L'importante è che test e contabilità corrispondano alla scelta.»

### E in uscita?

«Il credito è novanta. Quando l'escrow invia novanta al seller, il token applica un'altra fee del dieci per cento. Il seller riceve ottantuno.

Questo laboratorio definisce il diritto in termini di quantità addebitata all'escrow; la seconda fee ricade sul seller. È esplicito nel test. Se il requisito fosse che il seller riceva novanta netti, questa implementazione non basterebbe.»

```text
Buyer invia 100 → escrow riceve 90
Escrow invia 90 → seller riceve 81
```

```bash
bash demo.sh netto
```

**Risultato atteso:** due test PASS: credito pari al ricevuto e policy d'uscita con seconda fee a carico del seller. Non presentare 81 come una garanzia di qualunque token: è il comportamento del mock con fee del dieci per cento.

## 7. Se il payout fallisce, il debito resta

[Mostra `release`, poi il test `test_FailedPayoutRollsBackEffectsAndState`.]

«La release copia l'importo, azzera il debito e passa a Released prima di chiamare il token. È l'ordine CEI sul percorso di uscita.

Se il token segnala fallimento, il wrapper fa revert. Vengono annullati anche l'azzeramento e lo stato terminale. L'escrow rimane Funded con il debito da onorare.»

```bash
bash demo.sh payout
```

**Risultato atteso:** un test PASS: payout fallito, stato e debito ripristinati, asset conservati.

«Non cancelliamo un debito soltanto perché abbiamo tentato un pagamento. La storia contabile deve corrispondere all'esito previsto dalla policy.»

## 8. Esercizio: scrivere la policy del token

«Scrivete tre frasi: quale importo accreditate, come interpretate false o assenza di return data, quanto deve ricevere il seller.»

[Lascia tre minuti; usa questa soluzione per il laboratorio.]

**Soluzione:** accredito del balance delta positivo; false/revert rifiutati e nessun ritorno ammesso secondo il wrapper; payout dell'importo accreditato con fee d'uscita a carico del seller. I test non dimostrano compatibilità universale con token rebasing, blacklist, upgradeabili o callback arbitrarie.

«Il deposito qui misura un'interazione prima di poter registrare il ricevuto. Non trasformiamo questo esempio in una promessa di sicurezza contro ogni callback possibile: i comportamenti esterni coperti sono quelli modellati e testati. Progettare protezioni per ulteriori token richiede estendere il modello.»

## 9. Chiusura

«Abbiamo separato tre cose: possedere token, autorizzarne la spesa e registrare un credito nell'escrow.

Abbiamo poi distinto successo tecnico, risultato restituito e quantità realmente arrivata. Il wrapper gestisce alcuni modi di segnalare l'esito; il balance delta risponde alla domanda contabile; la policy decide quali asset e quali quantità supportiamo.

Nella prossima lezione una dipendenza ci restituirà un numero invece di token: un prezzo. Anche lì un valore leggibile dal programma può essere sbagliato per il significato economico che gli attribuiamo.»

**Percorso breve:** tabella approve/transferFrom, false-return, 100→90→81 e rollback. Le allowance residue si possono spiegare senza demo. [Esercizi](exercises/README.md).

## Promemoria del docente

Gli importi scritti con `ether` nei test ERC-20 sono numeri moltiplicati per 10^18, non invii di ETH. Non confondere una libreria didattica con una dipendenza di produzione. Se una demo non parte, disegna il caller di ogni chiamata e compila saldo, allowance e credito: la distinzione rimane comprensibile senza trace.
