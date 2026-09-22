# Architettura e trust boundary

```text
 buyer -- approve/deposit --> AuditEscrow -- transfer --> seller
                                |    |
                                |    +-- notify (best-effort atteso) --> notifier esterno
                                |
 permissionless release -------+-- latestPrice ---------------------> oracle esterno
                                |
 governance -- setOracle -------+
 guardian   -- pause -----------+
```

Il token custodito e la `liability` attraversano il trust boundary più importante. Oracle e
notifier non custodiscono direttamente asset, ma possono rispettivamente autorizzare o bloccare il
settlement. Un callback da token/notifier rientra nel contratto con un nuovo `msg.sender`.

## Asset

1. saldo token detenuto dall'escrow;
2. liability del buyer;
3. diritto del seller al settlement;
4. diritto del buyer al refund;
5. stato terminale del lifecycle;
6. indirizzo oracle;
7. freshness e scala del prezzo;
8. potere di pausa del guardian;
9. potere di configurazione governance;
10. disponibilità del flusso di settlement;
11. correttezza degli eventi usati off-chain;
12. assunzione sulla semantica ERC-20.

## Attori e capability

| Attore | Capability prevista | Non deve poter fare |
| --- | --- | --- |
| buyer | depositare una volta, richiedere refund | cambiare oracle, doppio settlement |
| seller | ricevere un solo settlement | modificare accounting/configurazione |
| caller generico | finalizzare se l'oracle soddisfa la policy | aggirare prezzo, pausa o stato |
| governance | cambiare oracle, pause/unpause | creare asset dal nulla |
| guardian | mettere in pausa | cambiare oracle o rimuovere la pausa |
| token | muovere asset secondo policy | rientrare e riusare la liability |
| oracle | fornire prezzo/timestamp | essere accettato se stale/futuro/non positivo |
| notifier | ricevere una notifica | rendere obbligatorio il settlement |

## Percorsi non presenti

Il laboratorio non usa proxy, multisig o timelock on-chain. In produzione `governance` dovrebbe
puntare al controller previsto; verificarne signer, threshold e delay sarebbe un'estensione dello
scope. Non si può inferire un timelock dal solo nome dell'indirizzo.
