# Invarianti

Le proprietà sono state scritte prima delle PoC. “Violata” descrive il target congelato, non la
versione corretta.

| ID | Proprietà | Target |
| --- | --- | --- |
| I-01 | Solo il buyer può depositare. | rispettata |
| I-02 | `Funded` può terminare in `Released` oppure `Refunded`, una sola volta. | violata da AUD-01 |
| I-03 | In ogni stato non terminale, asset dell'escrow >= liability. | violata da AUD-02 |
| I-04 | La liability nasce dall'importo realmente ricevuto. | violata da AUD-02 |
| I-05 | Il seller non riceve più di una volta la stessa liability. | violata da AUD-01 |
| I-06 | Gli stati terminali non ritornano a `Created` o `Funded`. | rispettata |
| I-07 | Il prezzo ha età strettamente minore di `maxAge`. | violata da AUD-04 |
| I-08 | Prezzi zero, negativi o sotto soglia non autorizzano release. | rispettata |
| I-09 | Solo governance cambia oracle. | violata da AUD-03 |
| I-10 | Guardian può pausare, ma non cambiare dipendenze. | violata da AUD-03 |
| I-11 | Solo governance può rimuovere la pausa. | rispettata |
| I-12 | Il notifier opzionale non blocca un settlement valido. | violata da OBS-01 |
| I-13 | Un refund restituisce al buyer al massimo la liability. | rispettata nel modello |
| I-14 | Dopo release o refund la liability è zero. | rispettata senza callback avversario |
| I-15 | Una transfer failure non lascia uno stato parzialmente aggiornato. | rispettata per atomicità |
| I-16 | Address critici non possono essere zero. | rispettata |
| I-17 | Transfer-tax token sono rifiutati atomicamente. | violata da AUD-02 |
| I-18 | Timestamp futuri non sono accettati. | revert per underflow, policy non esplicita |
| I-19 | Un caller generico non può ignorare la pausa. | rispettata |
| I-20 | La somma pagata al seller non supera il deposito di questo escrow. | violata da AUD-01 |

Le invariant Foundry della remediation verificano continuamente I-03, I-14 e I-20. Le altre
proprietà richiedono test mirati o handler più ricchi: tre invariant non equivalgono a venti prove.
