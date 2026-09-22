# Lezione 12 — Governance, owner, multisig e timelock

Questa lezione amplia la domanda “chi può chiamare?” in “chi può cambiare le regole, con quante
approvazioni, dopo quanto tempo e con quale blast radius?”. Authorization, quorum e delay sono
proprietà indipendenti.

> Multisig e timelock sono modelli locali minimali. Non custodiscono fondi reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_12_Governance_owner_multisig_timelock.md`](../../lezioni%20SmartContracts/Lezione_12_Governance_owner_multisig_timelock.md).

## Prima esecuzione

```bash
forge build --root lessons/12-governance-owner-multisig-timelock
forge test --root lessons/12-governance-owner-multisig-timelock -vv
```

I warning del linter sulle chiamate generiche e sull'invio di ETH sono attesi: multisig e timelock
devono poter eseguire una destinazione scelta dalla governance. Anche `block.timestamp` è qui usato
intenzionalmente per il delay, non come fonte di casualità. Gli `effects` (`executed`/`done`) vengono
scritti prima della chiamata esterna e un revert ripristina atomicamente lo stato. Queste primitive
locali restano modelli didattici e non sostituiscono Safe o OpenZeppelin `TimelockController`.

## Mappa dei file

```text
src/governance/ToyMultisig.sol       proposta, m-of-n, esecuzione generica
src/governance/ToyTimelock.sol       proposer, executor, canceller, admin e delay
src/governance/GovernedEscrow.sol    ownership a due fasi e emergency pauser
src/mocks/GovernanceTargets.sol      target e oracle giocattolo
test/ToyMultisig.t.sol               threshold, doppio voto e failure rollback
test/TimelockGovernance.t.sol        scheduling, boundary, cancel e pause
test/FullGovernanceFlow.t.sol        signer -> multisig -> timelock -> escrow
exercises/                            graph, recovery, deadlock e blast radius
```

## Tre controlli diversi

```text
multisig   chi e quante persone devono approvare
timelock   quanto tempo deve passare
target     quale address possiede davvero il privilegio
```

Se `GovernedEscrow.owner` fosse ancora una EOA o il multisig, il delay sarebbe aggirabile. Nel
laboratorio l'owner è il timelock: proposer ed executor non possono chiamare direttamente le
funzioni `onlyOwner`.

## Laboratorio multisig

```bash
forge test --match-contract ToyMultisigTest -vvvv
```

Il modello 2-of-3 verifica:

```text
una approval       non basta
due approval       consentono l'esecuzione
stesso signer      conta una volta
target fallisce    executed torna false per atomicità
```

## Laboratorio timelock

```bash
forge test --match-contract TimelockGovernanceTest -vvvv
```

La state machine è:

```text
Unset -> Waiting -> Ready -> Done
                   |
                   +------> Cancelled
```

Sono testati esecuzione anticipata, boundary esatto, cancellazione, predecessor, executor aperto e
propagazione del fallimento del target.

## Fast pause, slow restart

L'emergency pauser può fermare immediatamente le nuove azioni, ma non può cambiare fee/oracle né
riaprire il sistema. `unpause()` appartiene al timelock. L'uscita resta disponibile durante la pausa,
limitando il blast radius della chiave di emergenza.

## Flusso completo

```bash
forge test --match-contract FullGovernanceFlowTest -vvvv
```

```text
Alice + Bob approvano
        |
        v
ToyMultisig schedula
        |
        v
ToyTimelock attende 48h
        |
        v
executor esegue
        |
        v
GovernedEscrow vede msg.sender == Timelock
```

## Tre percorsi

### Base — authority

1. Distingui owner, signer e quorum.
2. Distingui proposer, executor e canceller.
3. Verifica che il target appartenga davvero al timelock.

### Intermedio — tempo ed emergenze

1. Testa tutti i boundary del delay.
2. Cancella un'operazione durante la finestra di review.
3. Mantieni separati pause, unpause e configurazione.

### Avanzato — governance operativa

1. Analizza recovery e rischio di deadlock.
2. Decodifica target, selector, argomenti, predecessor e salt.
3. Costruisci governance graph e blast-radius table.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployGovernanceLab.s.sol:DeployGovernanceLab \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai distinguere authorization, quorum e delay;
- sai spiegare threshold trust e relativi rischi di liveness;
- sai verificare schedule, ready boundary, execute e cancel;
- sai cercare percorsi che aggirano il timelock;
- sai progettare fast-pause con poteri minimi;
- sai disegnare governance graph e blast radius.
