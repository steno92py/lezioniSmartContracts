# Registro delle ipotesi

| ID | Osservazione → ipotesi | Metodo | Esito |
| --- | --- | --- | --- |
| H-01 | `release` scrive dopo `transfer` → callback può riusare liability | reentrant token + riserva | confermata, AUD-01 |
| H-02 | deposito accredita `amount` → fee token rende insolvente | token con fee 10% | confermata, AUD-02 |
| H-03 | guardian passa `setOracle` → può forzare soglia | oracle sotto/sopra soglia | confermata, AUD-03 |
| H-04 | confronto `>` → età esatta `maxAge` accettata | warp + timestamp boundary | confermata, AUD-04 |
| H-05 | notifier sincrono → revert blocca settlement | notifier che reverte | confermata, OBS-01 |
| H-06 | address zero critici accettati | constructor review | falsificata: revert esplicito |
| H-07 | caller generico può depositare per il buyer | prank da stranger | falsificata dal caller check |
| H-08 | stato terminale può essere eseguito di nuovo senza callback | seconda release/refund | falsificata da `WrongState` |
| H-09 | timestamp futuro viene accettato | arithmetic/data-flow review | falsificata: underflow reverte, ma UX migliorabile |
| H-10 | token che restituisce `false` viene ignorato | return-path review | falsificata: bool controllato |

## Esempio completo: H-02

```text
Observation: deposit salva l'argomento amount.
Hypothesis: un token con fee crea credit > saldo reale.
Evidence: requested 100, received 90, liability 100.
Finding: nominal accounting can make settlement insolvent.
```

Una ipotesi falsificata resta utile. Registra l'assunzione che la rende falsa oggi e il cambio che
richiederebbe un nuovo controllo; non eliminarla per rendere il report più “pulito”.
