# Lezione 14 — Fuzz testing e invariant testing con Foundry

[Indice del corso](../../README.md#indice-delle-lezioni) · [Teoria](teoria.md) · [Copione docente](copione.md)

## Per tenere la lezione

Apri la [guida del docente](copione.md): scalette da 60 e 90 minuti,
discorso, demo, risultati attesi e percorso senza terminale.
Dalla cartella di questa lezione usa `bash demo.sh check` per la suite completa (31 test)
e `bash demo.sh help` per le demo selezionate. Prepara compilatore e dipendenze con
`forge build` prima dell'aula; lo script delle demo opera offline.

## Tema e laboratorio

Questa lezione passa da pochi esempi scelti a mano a proprietà verificate su molti input e su
sequenze stateful. Il fuzzer amplia l'esplorazione; specifica, dominio e threat model restano
responsabilità di chi scrive il test.

> Tutto gira localmente con contratti giocattolo. Nessun fork, RPC pubblico o asset reale.

Il testo teorico completo resta in
[`teoria.md`](teoria.md).

## Prima esecuzione

```bash
forge build --root lezioni/14-fuzz-e-invariant-testing-con-foundry
forge test --root lezioni/14-fuzz-e-invariant-testing-con-foundry -vv
```

Solo fuzz o invariant:

```bash
forge test --root lezioni/14-fuzz-e-invariant-testing-con-foundry --match-path 'test/fuzz/*'
forge test --root lezioni/14-fuzz-e-invariant-testing-con-foundry --match-path 'test/invariant/*' -vvv
```

I warning su `block.timestamp` sono intenzionali: timestamp e `vm.warp` modellano freshness e
deadline, non casualità.

## Mappa dei file

```text
src/fuzz/FuzzTargets.sol               fee, quote, escrow e oracle freshness
src/invariant/CreditVault.sol          contabilità multiutente
src/invariant/ExactToken.sol           asset policy exact-transfer
src/invariant/LifecycleEscrow.sol      state machine con stati terminali
test/fuzz/                             property stateless e regressioni boundary
test/invariant/handlers/               action space, actor e ghost variables
test/invariant/                        solvibilità, conservation e terminalità
test/regression/                       sequenza ridotta come guardrail permanente
MODEL.md                               precondizioni e capability del modello
exercises/                              tracce graduate escluse dalla suite
```

## Fuzz test: una chiamata, molti input

I test mostrano tre modi diversi di modellare il dominio:

```text
bound     trasforma ogni input in un range realistico
assume    esclude proprietà discrete, per esempio caller == buyer
normalize ordina (a, b) senza scartare metà delle coppie
```

I casi `0`, boundary esatto e counterexample storico restano test deterministici: fuzzing non li
sostituisce.

## Invariant test: molte chiamate, uno stato

```text
Foundry -> handler -> actor scelto -> protocollo
              |
              +-> ghost accounting e action counter
```

`targetContract` limita il perimetro all'handler. `targetSelector` limita le azioni a deposit,
withdraw e over-withdraw oppure fund, release e refund. Servono entrambi: i selector non sono di per
sé una security property né un'esclusione automatica degli altri contratti deployati.

## Invarianti verificati

Per il vault exact-transfer senza donation:

```text
vault token balance == totalCredit
ghostDeposited - ghostWithdrawn == totalCredit
sum(credit[Alice, Bob, Carol]) == totalCredit
initial tokens == actor balances + vault balance
```

Per la state machine:

```text
once terminal -> always terminal
terminal -> amount == 0
Created -> amount == 0
Funded -> amount > 0
```

Leggi [MODEL.md](MODEL.md) prima di cambiare l'action space: donation, fee, rebase o admin
compromesso richiedono proprietà differenti o suite separate.

## Handler bounded e azione avversaria

`deposit` e `withdraw` normalizzano input per esplorare stati validi in profondità. Una terza azione
prova sempre `available + extra` e verifica revert più rollback. Bounded handler e negative testing
sono complementari.

## Ghost variables

`ghostDeposited`, `ghostWithdrawn` e `ghostTerminalSeen` non modificano il protocollo. Registrano
fatti osservati e forniscono memoria indipendente. I counter delle azioni aiutano a vedere se
l'handler raggiunge davvero deposit, withdraw e terminal states o produce quasi soltanto no-op.

## Profilo più intenso

```bash
FOUNDRY_PROFILE=deep forge test \
  --root lezioni/14-fuzz-e-invariant-testing-con-foundry \
  --match-path 'test/invariant/*'
```

Più run e depth aumentano l'esplorazione, ma non correggono una property debole o un handler povero.

## Mutation workflow

1. rimuovi temporaneamente `totalCredit -= amount`;
2. esegui `CreditVaultInvariantTest`;
3. leggi e riduci la failing sequence;
4. trasformala in un regression test deterministico;
5. ripristina il codice corretto e conserva entrambi i test.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployFuzzLab.s.sol:DeployFuzzLab \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- distingui fuzz test stateless e invariant test stateful;
- scegli consapevolmente `bound`, `assume` o normalizzazione;
- sai leggere un counterexample e trasformarlo in regression;
- definisci actor, asset policy, capability e selector dell'handler;
- usi ghost variables senza duplicare la business logic;
- sai motivare un invariante di solvibilità e riconoscere una tautologia.

