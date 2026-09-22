# Report finale — Escrow evoluto

## Executive summary

La review ha confermato quattro finding di sicurezza e un'osservazione: due High, due Medium e una
Informational. I rischi maggiori sono il falso successo terminale del payout e il setter oracle
permissionless. Accounting nominale e assenza di freshness compromettono solvency e correttezza
economica; il notifier richiede osservabilità, non failure atomica.

La remediation supera PoC, regression, fuzz, invariant stateful e test di governance ritardata.
Nessun ulteriore problema è stato identificato entro scope e metodologia; ciò non garantisce assenza
assoluta di vulnerabilità.

## Risultati

| ID | Severity | Stato retest |
| --- | --- | --- |
| F-01 accounting nominale | Medium | fixed |
| F-02 oracle stale | Medium | fixed |
| F-03 payout return ignorato | High | fixed |
| F-04 oracle setter senza auth | High | fixed |
| F-05 notifier silenzioso | Informational | fixed |

## Metodologia ed evidenza

Scope → architettura/asset/attori → 15 invarianti → entry point/write path/external call → manual
review → analisi statica → cinque PoC → remediation → 18 regression → quattro fuzz test → cinque
invariant → governance extension → retest.

Il [triage Slither](static-analysis.md) distingue gli alert risolti da quelli che dipendono dalla
policy sugli asset e mostra che F-04 richiede review manuale.

## Design question aperte

- La specifica non assegna i token trattenuti come fee: prima della produzione servono destinatario,
  accounting, claim e recovery policy.
- Il balance delta risolve l'ingresso fee-on-transfer, ma non definisce quanto debba ricevere il
  seller se anche l'uscita applica fee.
- Owner deve essere collegato al controller reale promesso; `onlyOwner` da solo non prova multisig o
  delay.

## Limitazioni

Working tree senza commit, asset/provider giocattolo, niente fork, MEV, proxy/UUPS, storage layout,
multisig reale o security operativa. `SafeERC20Lite` serve al laboratorio e non sostituisce una
dipendenza mantenuta e auditata in produzione.

## Conclusione

Il capstone dimostra l'intera catena evidence-driven: requisito → proprietà → ipotesi → PoC →
finding → fix → regression → retest. La roadmap didattica principale 1–17 è completa.
