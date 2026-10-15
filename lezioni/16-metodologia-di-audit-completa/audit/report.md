# Report finale — Mini audit AuditEscrow

## Executive summary

La review ha identificato quattro finding: uno High, due Medium e uno Low. Il rischio principale è
la possibilità di pagare due volte la stessa liability tramite callback del token. Sono emersi anche
accounting nominale incompatibile con fee token, un bypass del modello di governance e un errore al
boundary della freshness oracle.

La remediation separata supera tutte le PoC, il fuzz sull'accounting e tre invariant. Questo non
dimostra assenza assoluta di vulnerabilità: nessun ulteriore problema è stato identificato nello
scope e con la metodologia documentati.

## Risultati

| ID | Severity | Titolo | Retest |
| --- | --- | --- | --- |
| AUD-01 | High | callback prima degli effects consente doppio payout | fixed |
| AUD-02 | Medium | accounting nominale crea liability non collateralizzata | fixed |
| AUD-03 | Medium | guardian può sostituire oracle | fixed |
| AUD-04 | Low | prezzo accettato al boundary di scadenza | fixed |

## Osservazione informativa

`OBS-01`: nel target un notifier opzionale che reverte blocca release. La remediation lo tratta come
best-effort con `try/catch` ed evento d'esito. La classificazione resta Informational perché la
dipendenza è fissata al deployment, visibile e il buyer conserva il percorso di refund; resta però
un mismatch verificabile con la policy di liveness.

## Metodologia

Sono state eseguite passate separate per comprensione, flow critici, casi avversariali, privilegi,
tooling, checklist e consolidamento. I finding sono raggruppati per root cause e non per numero di
linee segnalate. Ogni finding ha una riproduzione deterministica senza fork.

## Remediation review

- CEI chiude stato/liability prima delle chiamate esterne;
- balance delta enforce exact-transfer policy;
- `setOracle` è governance-only;
- oracle future/exact-stale è rifiutato;
- notifier è best-effort;
- regression, fuzz e invariant sono verdi.

## Limitazioni

Restano fuori scope proxy/upgrades, controller governance reale, chiavi, frontend, provider oracle,
token rebasing e simulazioni MEV/economiche. Il working tree non ha un commit `HEAD`, quindi lo scope
non è ancorato a un hash immutabile. Per un audit reale questa condizione va risolta prima della
review finale.
