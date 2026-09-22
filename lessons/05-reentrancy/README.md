# Lezione 5 — Reentrancy, CEI e guard

Questa lezione mostra che una external call non interrompe semplicemente una funzione: sospende il
frame corrente e consente al destinatario di richiamare il contratto mentre lo storage può essere
ancora incoerente.

> Tutto il laboratorio è locale e difensivo. `VulnerableVault` e il receiver ricorsivo sono
> giocattoli deliberatamente vulnerabili; non usarli contro sistemi o fondi reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_05_Reentrancy.md`](../../lezioni%20SmartContracts/Lezione_05_Reentrancy.md).

## Modello mentale

```text
VulnerableVault.withdraw()
  CHECK credit = 1 ETH
  CALL receiver ------------------------------+
                                                |
                               receiver.receive()
                                                |
                               vault.withdraw() |
                               credit e' ancora 1
                                                |
  EFFECT credit = 0 <--------------------------+
```

Il bug non è “una funzione viene chiamata due volte”. Il bug è che un diritto rimane spendibile
mentre il controllo è già passato all'esterno.

## Tre implementazioni a confronto

| Variante | Ordine | Callback osserva | Risultato |
| --- | --- | --- | --- |
| `VulnerableVault` | Check → Interaction → Effect | credito ancora valido | payout multiplo |
| `SafeVaultCEI` | Check → Effect → Interaction | credito zero | reentry `NoCredit` |
| `SafeVaultGuarded` | CEI + mutex | lock `ENTERED` | reentry `ReentrantCall` |

Il guard locale è intenzionalmente minimale e leggibile. Riproduce la macchina di locking classica
senza aggiungere una dipendenza di rete alla lezione. In un progetto reale si usa normalmente una
libreria mantenuta come OpenZeppelin, con versione pinnata, lockfile e review della supply chain.

Il lint segnala correttamente la call del `VulnerableVault`. Può segnalare anche quella della
variante guarded perché non ricostruisce completamente il modifier locale: in quel caso `_status`
viene impostato a `ENTERED` prima del body e i test verificano esplicitamente il blocco del callback.
Un warning va quindi sottoposto a triage, non ignorato né trattato automaticamente come finding.

## Prima esecuzione

Dalla directory della lezione:

```bash
forge build
forge test -vv
```

Dalla radice:

```bash
forge build --root lessons/05-reentrancy
forge test --root lessons/05-reentrancy -vv
```

## Mappa dei file

```text
src/reentrancy/VulnerableVault.sol       Interaction prima degli Effects
src/reentrancy/SafeVaultCEI.sol          credito consumato prima della call
src/reentrancy/SafeVaultGuarded.sol      CEI + mutex
src/utils/DidacticReentrancyGuard.sol    lock minimale ispezionabile
test/helpers/ReentrancyReceivers.sol     receiver ricorsivo, probe e rejector
test/VulnerableVault.t.sol               riproduzione dell'insolvenza
test/SafeVaults.t.sol                     regression test delle remediation
script/DeploySafeVault.s.sol              deploy locale della sola versione safe
exercises/                                attività graduate
```

## Esperimento vulnerabile

```bash
forge test \
  --match-test test_DemonstratesReentrantCallbackBreakingAccounting \
  -vvvv
```

Il test passa dimostrando il bug. Il receiver ha un credito legittimo di `1 ether`, ma riceve più
di `1 ether`. I quattro crediti individuali onesti restano pari a `4 ether` mentre il vault è vuoto,
quindi liabilities superano assets. I decrementi annidati corrompono inoltre `totalCredits` fino a
zero: per questo il test calcola anche una somma indipendente dei crediti.

Un semplice assert finale `credit[receiver] == 0` non sarebbe sufficiente: può essere vero anche
dopo più payout illegittimi.

## Regression test CEI

```bash
forge test --match-test test_CEI_PreventsReuseOfCredit -vvvv
```

Il probe riceve il controllo e tenta davvero il rientro, ma osserva il credito già azzerato. La
chiamata annidata fallisce con `NoCredit`, mentre il payout principale riesce esattamente una volta.

## Regression test CEI + guard

```bash
forge test --match-test test_GuardAndCEI_BlockReentry -vvvv
```

Qui la callback viene fermata dal lock `ENTERED` con `ReentrantCall`. CEI rimane comunque presente:
un mutex non corregge accounting sbagliato e non definisce automaticamente lo scope del lock.

## Tre percorsi

### Base — seguire il call stack

1. Confronta chiamate sequenziali e chiamate annidate.
2. Segui `withdraw → receive → withdraw` nella trace.
3. Individua lo storage condiviso tra i frame.

### Intermedio — ragionare economicamente

1. Confronta il credito legittimo con il payout totale.
2. Verifica `assets >= liabilities` dopo ogni remediation.
3. Prova un receiver che rifiuta il payout e osserva il rollback.

### Avanzato — oltre la stessa funzione

1. Cerca cross-function e cross-contract reentrancy.
2. Definisci tutte le entry point che devono condividere il lock.
3. Considera anche stato transitorio osservabile da funzioni `view`.

## Deploy facoltativo su Anvil

Lo script distribuisce soltanto `SafeVaultGuarded`:

```bash
forge script script/DeploySafeVault.s.sol:DeploySafeVault \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai indicare il punto esatto in cui il controllo lascia il vault;
- sai spiegare perché l'atomicità non elimina gli stati intermedi osservabili;
- sai distinguere single-function, cross-function e cross-contract reentrancy;
- sai formulare la solvibilità come relazione tra assets e liabilities;
- sai spiegare cosa aggiunge il guard e cosa non può correggere;
- sai trasformare il controesempio in un regression test permanente.
