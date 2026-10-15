# Invarianti finali

| ID | Proprietà | Target | Retest |
| --- | --- | --- | --- |
| I-01 | solo buyer deposita | rispettata | unit |
| I-02 | Funded termina una sola volta | rispettata | regression/invariant |
| I-03 | stato terminale non riapre | rispettata | invariant stateful |
| I-04 | se Funded, assets >= escrowedAmount | violata F-01 | fuzz/invariant |
| I-05 | credito = asset realmente ricevuti | violata F-01 | fee-token regression |
| I-06 | prezzo positivo, timestamp valido e age <= max | violata F-02 | boundary fuzz |
| I-07 | solo owner cambia oracle | violata F-04 | unit/timelock |
| I-08 | transfer fallita non lascia Released/Refunded | violata F-03 | false-return regression |
| I-09 | notifier fallito non blocca ed è osservabile | parziale F-05 | event regression |
| I-10 | feeBps <= 1000 | rispettata | fuzz/invariant |
| I-11 | solo pauser pausa | rispettata | unit |
| I-12 | solo owner rimuove pausa | rispettata | unit |
| I-13 | refund resta disponibile durante pausa | rispettata | unit |
| I-14 | liability zero in stato terminale | rispettata salvo F-03 semantico | invariant |
| I-15 | seller non riceve più del credito | rispettata nel fixed | invariant |

Gli invariant automatici coprono I-03, I-04, I-10, I-14 e I-15. Le proprietà di authorization e
boundary sono mantenute come test mirati: una campagna stateful non sostituisce tutte le prove.

