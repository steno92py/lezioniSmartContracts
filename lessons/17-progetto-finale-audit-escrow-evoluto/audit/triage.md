# Triage worksheet compilato

| ID | Observation | Reachable | Property | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| F-01 | credit nominale dopo transferFrom | buyer + fee token | I-04/I-05 | confirmed | 100 richiesti, 90 ricevuti, 100 accreditati |
| F-02 | updatedAt ignorato | buyer, Funded | I-06 | confirmed | prezzo vecchio di 2h accettato |
| F-03 | transfer bool ignorato | buyer + false token | I-08 | confirmed | Released con seller non pagato |
| F-04 | setOracle senza auth | qualsiasi caller | I-07 | confirmed | stranger sostituisce feed |
| F-05 | low-level result ignorato | notifier revert | I-09 | informational | settlement riesce, failure invisibile |

## Consolidamento

F-01 e F-03 riguardano entrambi token integration, ma hanno root cause e remediation distinte:
balance reconciliation contro gestione del return. F-05 non viene elevato artificialmente: la
policy best-effort rende corretto non revertire, mentre manca osservabilità.

