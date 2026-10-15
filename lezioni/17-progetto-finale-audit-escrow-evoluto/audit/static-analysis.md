# Slither — pass finale e triage

Esecuzione locale del 22 settembre 2026 con Slither 0.11.4 e Solidity 0.8.37. Il file
`requirements-slither.txt` pinna 0.11.6 per installazioni nuove; il pass qui riportato è stato
eseguito con il virtualenv locale già disponibile. I comandi sono
`bash scripts/slither-target.sh` e `bash scripts/slither-fixed.sh`, dalla radice della lezione.
Slither ha analizzato 13 contratti con 100 detector in ciascun pass: 19 risultati sul target e 11
sulla remediation. Il codice di uscita 255 segnala risultati trovati, non un errore di compilazione.
I filtri escludono test, script e dipendenze dall'output; ogni pass concentra l'output sul contratto
pertinente.

| Detector | Target | Remediation | Triage |
| --- | --- | --- | --- |
| `unchecked-transfer` | `deposit`, `release`, `refund` | assente | F-01/F-03: return ignorato; la patch usa `safeTransfer*` |
| `unchecked-lowlevel` | notifier in `release` | assente | F-05: failure ora osservabile con `NotificationFailed` |
| `redundant-statements` | `updatedAt;` | assente | F-02: indizio di timestamp ignorato; il test prova l'accettazione stale |
| `missing-zero-check` | ruoli nel constructor | assente | la patch valida gli indirizzi obbligatori |
| `arbitrary-send-erc20` | `deposit` | `deposit` | il `from` è il buyer immutabile e solo lui può chiamare `deposit`; verificare ancora token e allowance ammessi |
| `incorrect-equality` | assente | `received == 0` | è un controllo di importo nullo, non una condizione di prezzo o segreto |
| `reentrancy-*` | chiamate esterne | chiamate esterne | il token resta una trust boundary; vedi analisi sotto |
| `timestamp` | assente | freshness check | il confronto col timestamp serve alla policy dichiarata e ha test di boundary |
| `immutable-states` | owner, pauser, notifier | owner, pauser, notifier | opportunità di design/gas; non equivale a un exploit dimostrato |

`setOracle` permissionless (F-04) non emerge da questi detector. La review manuale dell'entry point e
il test con uno stranger sono l'evidenza, quindi il pass statico da solo non chiude l'audit.

## Chiamate esterne e reentrancy

Nel `deposit` della patch, `transferFrom` e `balanceOf` precedono il write a `Funded`. Slither segnala
questo ordine. Durante una callback ordinaria il token è `msg.sender`, mentre `deposit`, `release` e
`refund` richiedono il buyer. Inoltre `release` e `refund` richiedono `Funded`; le chiamate di payout
avvengono dopo il passaggio a stato terminale. Questo limita le transizioni ripetute nel modello del
laboratorio, ma non dimostra che ogni token con callback sia sicuro. Un buyer contrattuale che possa
essere anche il token, token malevoli e semantiche non standard richiedono test e una policy sugli
asset prima di un impiego reale.

Gli alert `reentrancy-events` riguardano eventi emessi dopo chiamate esterne. In questa versione
l'ordine è coerente con l'esito del trasferimento e la policy best-effort del notifier; se gli
eventi fossero usati come sorgente di accounting esterno, l'ordine andrebbe specificato e testato.

## Limiti del pass

Il pass statico non stabilisce la destinazione della fee, la semantica dei token con fee in uscita,
la correttezza economica del prezzo né l'effettiva governance dell'owner. Questi punti restano nelle
design question del report. I finding F-01…F-05 sono chiusi dai test mirati, non dal solo calo del
numero di alert.
