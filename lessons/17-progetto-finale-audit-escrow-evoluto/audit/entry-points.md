# Entry point e write-path review

| Funzione | Caller | Write | External call | Rischio |
| --- | --- | --- | --- | --- |
| deposit | buyer | amount, state | token | return, nominal/received |
| release | buyer | amount, state | oracle, token, notifier | stale, falso successo, liveness |
| refund | buyer | amount, state | token | falso successo, pause policy |
| setFee | owner | feeBps | — | boundary, fee destination |
| setOracle | target: chiunque | oracle | — | config takeover |
| pause | pauser | paused | — | griefing limitato |
| unpause | owner | paused | — | governance/liveness |

## Write path critici

- `escrowedAmount`: deposito nominale nel target; zero in release/refund.
- `state`: Created → Funded → Released XOR Refunded.
- `oracle`: constructor + setter; il target non protegge il setter.
- `feeBps`: owner-only e limite incluso 1000.
- `paused`: pauser abilita, owner disabilita.

## Chiamate esterne

Il target ignora i return di transfer/transferFrom e low-level notifier. Il fixed usa wrapper per i
token, valida prezzo/timestamp, applica CEI e rende esplicita la failure policy del notifier.

