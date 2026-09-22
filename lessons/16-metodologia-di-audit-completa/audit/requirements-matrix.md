# Matrice requisiti → evidenza

| Req | Requisito | Codice/controllo | Evidenza |
| --- | --- | --- | --- |
| R-01 | buyer-only deposit | controllo `msg.sender` | baseline + code review |
| R-02 | exact-transfer token soltanto | balance delta e reject | AUD-02 + regression |
| R-03 | singolo settlement | effects prima della transfer | AUD-01 + invariant |
| R-04 | release permissionless sopra soglia | price check | baseline |
| R-05 | freshness `age < maxAge` | future/age check | AUD-04 + regression |
| R-06 | oracle modificabile solo da governance | authorization | AUD-03 + regression |
| R-07 | guardian può attivare pause | authorization | code review |
| R-08 | solo governance può unpause | authorization | code review |
| R-09 | notifier best-effort | `try/catch` | OBS-01 + regression |
| R-10 | terminalità release/refund | state check + CEI | refund test + invariant |
| R-11 | token false/revert non ignorati | safe-call wrapper | code review |
| R-12 | asset coprono liability | received accounting | fuzz + invariant |

La matrice espone anche i buchi: pause/unpause e token senza return meritano test aggiuntivi negli
esercizi, pur essendo stati ispezionati manualmente.
