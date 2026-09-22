# Lezione 13 — Testing approfondito con Foundry

Questa lezione trasforma i test da semplice conferma dell'happy path a specifica eseguibile:
proprietà, controesempi, failure policy, rollback e regressioni permanenti.

> Tutto gira localmente. I contratti e i mock sono progettati per apprendere, non per produzione.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_13_Testing_approfondito_con_Foundry.md`](../../lezioni%20SmartContracts/Lezione_13_Testing_approfondito_con_Foundry.md).

## Prima esecuzione

```bash
forge build --root lessons/13-testing-approfondito-con-foundry
forge test --root lessons/13-testing-approfondito-con-foundry -vv
```

I warning del linter su `block.timestamp` sono intenzionali: qui il timestamp serve a testare
freshness e deadline, non come sorgente di casualità.

Per osservare una singola call trace:

```bash
forge test --root lessons/13-testing-approfondito-con-foundry \
  --match-test test_Regression_ReentrantCallbackCannotWithdrawTwice -vvvv
```

## Mappa del laboratorio

```text
src/TestingEscrow.sol                 specifica: auth, oracle, token e state machine
src/WithdrawalVault.sol               pull payment e callback reentrante
src/mocks/TestingMocks.sol            token configurabile, oracle e recipient ostili
test/helpers/EscrowTestBase.sol        fixture e piccoli helper semantici
test/unit/                             una proprietà locale per scenario
test/integration/                      boundary tra escrow, oracle e token
test/regression/                       bug plausibili che non devono ritornare
REQUIREMENTS.md                        tracciabilità requisito -> test
exercises/                              attività graduate, escluse dalla suite
```

## Come leggere un test

Ogni scenario dovrebbe rendere visibili:

```text
Arrange   stato minimo e caller
Act       una sola azione osservata
Assert    cosa cambia e cosa deve restare invariato
```

Un revert preciso non basta da solo: i negative test controllano anche state, liability e balance
dopo il fallimento. Gli eventi vengono verificati insieme allo storage, mai come unica prova.

## Unit, integration e regression

- `unit`: authorization, transizioni, eventi e boundary della fee;
- `integration`: risposta reale dell'oracle, `vm.mockCall`, token e workflow economico;
- `regression`: false-return, fee-on-transfer, payout fallito e callback reentrante.

Filtri utili:

```bash
forge test --root lessons/13-testing-approfondito-con-foundry --match-path 'test/unit/*'
forge test --root lessons/13-testing-approfondito-con-foundry --match-path 'test/integration/*'
forge test --root lessons/13-testing-approfondito-con-foundry --match-path 'test/regression/*'
```

## Mock contract oppure `vm.mockCall`?

`MockOracle` è preferibile per stato, sequenze e revert configurabili. `vm.mockCall` rende molto
piccolo un unit test che vuole isolare un singolo return. La suite mostra entrambi: il mock non deve
limitarsi a confermare la stessa assunzione fatta dal codice.

## Boundary e mutation thinking

Per `fee <= 1000` sono testati `999`, `1000` e `1001`. Per la freshness sono testati il boundary
esatto e il secondo immediatamente successivo. Prova poi a mutare `>` in `>=`: almeno un test deve
fallire. Se nessun test distingue il codice corretto dal mutante, la suite non protegge la proprietà.

## Coverage

```bash
forge coverage --root lessons/13-testing-approfondito-con-foundry --report summary
```

Coverage indica dove sono passati i test, non se hanno dimostrato le proprietà giuste. Usa ogni gap
come domanda: ramo impossibile, dead code, failure path o test mancante?

## Tre percorsi

### Base

Leggi `Deposit.t.sol`, riconosci Arrange–Act–Assert e confronta revert generico con custom error
completo di payload.

### Intermedio

Segui balance delta, rollback delle chiamate token e due strategie di mock dell'oracle.

### Avanzato

Usa la matrice dei requisiti, prova mutazioni intenzionali e analizza l'invariante economico
`token balance >= liability`, che sarà generalizzato con fuzz e invariant testing nella Lezione 14.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployTestingLab.s.sol:DeployTestingLab \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai formulare la proprietà prima del test;
- sai distinguere unit, integration, negative e regression test;
- usi caller, tempo, eventi e revert senza footgun;
- verifichi lo stato dopo failure ed external call;
- interpreti coverage senza scambiarla per prova di sicurezza;
- sai collegare requisiti, test e mutanti plausibili.
