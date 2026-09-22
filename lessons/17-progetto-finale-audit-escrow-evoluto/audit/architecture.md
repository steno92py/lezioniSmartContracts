# Architettura, asset e trust

```text
buyer -- approve/deposit --> EscrowFinal -- payout/refund --> seller/buyer
                                |
                                +-- latestPrice ----------> oracle
                                +-- notifyReleased -------> notifier

owner/timelock -- setOracle, setFee, unpause
pauser --------- pause
```

## Asset

Token custoditi, liability contabile, diritto del seller, diritto di refund, oracle authority,
owner authority, pause authority, stato terminale e affidabilità degli eventi.

## Trust boundary

Token, oracle e notifier eseguono codice esterno. Owner controlla configurazione economica; il
pauser ha solo capability difensiva. Nel percorso esteso il proposer non è owner: il timelock è
l'unico caller riconosciuto dal contratto dopo il delay.

## Capability

| Attore | Previsto | Vietato |
| --- | --- | --- |
| buyer | deposit, release, refund | configurazione privilegiata |
| owner/timelock | oracle, fee, unpause | aggirare asset conservation |
| pauser | pause | unpause/configurazione |
| stranger | letture | ogni write privilegiato |
| token | trasferimenti | falso successo terminale |
| oracle | prezzo/timestamp | stale/future acceptance |
| notifier | best-effort | bloccare settlement |

