# Scope

## Identificazione

- Commit: non disponibile; repository didattica ancora priva di un commit `HEAD` al momento della review.
- Snapshot: working tree locale della Lezione 16.
- Compilatore: Solidity `0.8.37`, EVM `prague`, optimizer 200 run.
- Framework: Foundry; `forge 1.8.3` osservato durante il tool pass.

L'assenza di un commit è una limitazione reale: in un audit professionale impedirebbe di identificare
in modo immutabile il target. Qui viene registrata, non nascosta.

## In scope

- `src/target/AuditEscrow.sol`
- `src/interfaces/IAuditDependencies.sol`
- comportamento d'integrazione richiesto a token, oracle e notifier;
- autorizzazione di governance e guardian;
- accounting, lifecycle, oracle freshness, external call e liveness.

`src/mocks/` e `audit/tests/` sono harness ed evidenza, non target di produzione.
`src/fixed/RemediatedEscrow.sol` entra in scope soltanto nella fase di retest.

## Out of scope

- frontend, backend e indicizzazione degli eventi;
- sicurezza operativa delle chiavi;
- implementazione interna di provider oracle reali;
- proxy, storage layout e processo di upgrade;
- router/DEX, slippage e simulazione economica multi-mercato;
- conformità di token diversi dai mock usati nella riproduzione.

## Dipendenze e assunzioni dichiarate

- Il token supportato deve trasferire esattamente l'importo richiesto; i transfer-tax token sono
  fuori policy e devono essere rifiutati atomicamente.
- `latestPrice()` restituisce prezzo con 8 decimali e timestamp Unix.
- Un prezzo è valido solo se positivo, almeno `minPrice`, non futuro e con età strettamente minore
  di `maxAge`.
- Il notifier è opzionale e best-effort: il suo fallimento non deve impedire il settlement.
- Governance è il solo attore autorizzato a cambiare oracle e a rimuovere la pausa.
- Guardian può soltanto attivare la pausa.
- Chiunque può chiamare `release`; l'oracle, non il caller, autorizza economicamente la transizione.

## Deliverable

Work paper, PoC Foundry locali, quattro finding confermati, un'osservazione informativa, patch
didattica separata, regression/fuzz/invariant e report finale.
