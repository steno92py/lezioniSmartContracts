# Lezione 11 — Proxy, delegatecall e upgradeability

Questa lezione separa address, storage e code. Con `delegatecall`, il bytecode
dell'implementation interpreta e modifica lo storage persistente del proxy: per questo layout,
initializer e upgrade authority sono security boundary.

> Proxy e implementation sono primitive didattiche locali. Non usarli in produzione.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_11_Proxy_delegatecall_e_upgradeability.md`](../../lezioni%20SmartContracts/Lezione_11_Proxy_delegatecall_e_upgradeability.md).

## Prima esecuzione

```bash
forge build --root lessons/11-proxy-delegatecall-upgradeability
forge test --root lessons/11-proxy-delegatecall-upgradeability -vv
```

## Mappa dei file

```text
src/lab/SimpleProxy.sol                 collisione e upgrade pubblico intenzionali
src/lab/ContextLogic.sol                msg.sender e address(this sotto delegatecall
src/proxy/EducationalERC1967Proxy.sol   metadata in slot ERC-1967
src/upgrade/UpgradeableEscrowV1.sol     initializer, owner e upgradeToAndCall
src/upgrade/UpgradeableEscrowV2.sol     stato aggiunto in coda e migration V2
src/upgrade/UnsafeLayoutV2.sol          buyer/seller riordinati intenzionalmente
test/                                   collisioni, takeover, upgrade e invarianti
exercises/                              packing, validation e governance
```

Il proxy ERC-1967 e il meccanismo UUPS-like sono minimali e ispezionabili. Non sostituiscono
OpenZeppelin Contracts Upgradeable né il Foundry Upgrades plugin: un progetto reale deve pin­nare
le versioni, usare la validation ufficiale e revisionare il processo di governance.

## Laboratorio 1 — collisione proxy/application

```bash
forge test --match-contract SimpleProxyTest -vvvv
```

`SimpleProxy.implementation` e `SimpleLogicV1.value` usano entrambi lo slot 0. Una scrittura tramite
delegatecall trasforma quindi l'indirizzo dell'implementation nel valore `123`.

## Laboratorio 2 — execution context

```bash
forge test --match-contract DelegatecallContextTest -vvvv
```

Per `Alice → Proxy →delegatecall→ Logic`:

```text
code          Logic
storage       Proxy
address(this) Proxy
msg.sender    Alice
```

Lo storage della Logic distribuita direttamente resta vuoto.

## Laboratorio 3 — initialization e upgrade

```bash
forge test --match-contract UpgradeableEscrowTest -vvvv
```

Il deploy corretto passa `initialize(...)` al constructor del proxy, rendendo creazione e
configurazione atomiche. Un test separato lascia intenzionalmente il proxy non inizializzato e
dimostra che uno stranger può reclamarne l'ownership.

L'upgrade V1 → V2 verifica:

```text
solo owner
implementation UUPS-compatible
upgrade + migration atomici
owner, buyer, seller, amount e funded preservati
initialize e initializeV2 non ripetibili
authorization applicativa ancora valida
```

## ERC-1967 non valida il layout applicativo

`UnsafeLayoutV2` espone il UUID atteso ma inverte buyer e seller. Il laboratorio mostra che il solo
controllo UUPS/ERC-1967 lascia passare la reinterpretazione dello storage. In produzione questo è il
compito della storage-layout validation, della review manuale e dei regression test.

Confronta i layout:

```bash
forge inspect --root lessons/11-proxy-delegatecall-upgradeability \
  UpgradeableEscrowV1 storageLayout
forge inspect --root lessons/11-proxy-delegatecall-upgradeability \
  UpgradeableEscrowV2 storageLayout
forge inspect --root lessons/11-proxy-delegatecall-upgradeability \
  UnsafeLayoutV2 storageLayout
```

## Tre percorsi

### Base — delegatecall

1. Distingui code context e storage context.
2. Riproduci la collisione allo slot 0.
3. Osserva perché i nomi delle variabili non esistono nell'EVM.

### Intermedio — upgrade sicuro

1. Inizializza il proxy atomicamente.
2. Proteggi upgrade e reinitializer.
3. Confronta tutto lo stato prima e dopo.

### Avanzato — validation e governance

1. Esamina slot, offset, type e inheritance.
2. Valida il layout con tooling OpenZeppelin in un progetto dedicato.
3. Modella compromissione dell'upgrade authority e bricking risk.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployUpgradeableEscrow.s.sol:DeployUpgradeableEscrow \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai descrivere il contesto di una `delegatecall`;
- sai distinguere collisione metadata/application e incompatibilità V1/V2;
- sai spiegare constructor, initializer e implementation lock;
- sai testare authorization, atomicità della migration e conservazione dello stato;
- sai usare `forge inspect` per leggere slot, offset e tipi;
- sai spiegare perché upgradeability aggiunge governance al threat model.

