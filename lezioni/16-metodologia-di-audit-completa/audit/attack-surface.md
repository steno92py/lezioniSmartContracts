# Attack surface

| Entry point | Caller previsto | Write | External call | Rischio dominante |
| --- | --- | --- | --- | --- |
| `deposit` | buyer | liability, state | token `transferFrom`/`balanceOf` | nominal vs received, callback |
| `release` | chiunque | liability, state | oracle, token, notifier | reentrancy, stale data, liveness |
| `refund` | buyer | liability, state | token | terminalità, transfer failure |
| `setOracle` | governance | oracle | nessuna | privilege bypass |
| `pause` | governance/guardian | paused | nessuna | griefing autorizzato |
| `unpause` | governance | paused | nessuna | liveness/governance |

## External-call worksheet

| Call | Callee controllabile? | Return | Stato prima/dopo nel target | Failure policy |
| --- | --- | --- | --- | --- |
| `transferFrom` | governance/deploy config | bool controllato | accounting dopo | revert |
| `latestPrice` | governance può sostituire | tuple validata parzialmente | nessun write | revert |
| `transfer` release | token configurato | bool controllato | liability dopo: pericoloso | revert |
| `notify` | notifier da constructor | nessun return | liability dopo: pericoloso | bubble: blocca |
| `transfer` refund | token configurato | bool controllato | liability prima | revert atomico |

## Write-path worksheet

- `liability`: nasce in `deposit`; viene azzerata in `release` e `refund`.
- `state`: `Created → Funded → Released|Refunded`; nessun setter generico.
- `oracle`: constructor e `setOracle`; il secondo path include erroneamente guardian.
- `paused`: `pause` da governance/guardian, `unpause` solo governance.

La review per entry point trova il flusso; quella per write-path trova i bypass tra funzioni.
