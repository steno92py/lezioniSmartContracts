# Smart Contract Security — laboratori Foundry

Questa repository trasforma un programma di 17 lezioni in sottoprogetti Foundry autonomi. Ogni
lezione contiene codice, test, un laboratorio locale e attività graduate per studenti con livelli
di esperienza differenti.

Il materiale teorico originale è conservato in `lezioni SmartContracts/`. I progetti eseguibili
sono aggiunti, una lezione alla volta, sotto `lessons/`.

## Come scaricare il corso

### 1. Installa Git e Foundry (solo la prima volta)

Serve [Git](https://git-scm.com/downloads). Poi installa Foundry, lo strumento che compila e testa
i contratti:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

Chiudi e riapri il terminale, poi:

```bash
foundryup
forge --version
```

Se `forge --version` stampa un numero di versione, Foundry è installato. Su Windows usa WSL.

### 2. Clona la repository

```bash
git clone --recurse-submodules https://github.com/steno92py/lezioniSmartContracts.git
cd lezioniSmartContracts
```

`--recurse-submodules` scarica anche `lib/forge-std`, la libreria usata dai test. Se hai già
clonato senza, recuperala con:

```bash
git submodule update --init --recursive
```

### 3. Verifica che tutto funzioni

```bash
cd lessons/01-transazioni-account-calldata-storage-revert
forge build
forge test -vv
```

Tutti i test devono passare. Da qui prosegui con il
[README della Lezione 1](lessons/01-transazioni-account-calldata-storage-revert/README.md).

### Aggiornare il corso

Quando vengono pubblicate modifiche, dalla radice della repository:

```bash
git pull
git submodule update --init --recursive
```

Se hai modificato dei file per gli esercizi, `git pull` può segnalare un conflitto: salva prima le
tue modifiche, per esempio con `git stash`, poi riprendile con `git stash pop`.

## Stato del percorso

| Lezione | Argomento | Stato |
| --- | --- | --- |
| 01 | Transazioni, account, calldata, storage e revert | pronta |
| 02 | Foundry e metodo di testing | pronta |
| 03 | Escrow e macchina a stati | pronta |
| 04 | Ether, receive, fallback, chiamate esterne e CEI | pronta |
| 05 | Reentrancy, CEI e guard | pronta |
| 06 | Access control | pronta |
| 07 | Errori logici e state machine | pronta |
| 08 | ERC-20, allowance e integrazioni sicure | pronta |
| 09 | Oracoli, prezzi, slippage e MEV | pronta |
| 10 | Composability e dipendenze esterne | pronta |
| 11 | Proxy, delegatecall e upgradeability | pronta |
| 12 | Governance, owner, multisig e timelock | pronta |
| 13 | Testing approfondito con Foundry | pronta |
| 14 | Fuzz testing e invariant testing con Foundry | pronta |
| 15 | Analisi statica con Slither | pronta |
| 16 | Metodologia di audit completa | pronta |
| 17 | Progetto finale di audit | pronta |

## Lezioni disponibili

- [Lezione 1 — progetto e istruzioni](lessons/01-transazioni-account-calldata-storage-revert/README.md)
- [Lezione 2 — progetto e istruzioni](lessons/02-foundry-e-metodo-di-testing/README.md)
- [Lezione 3 — progetto e istruzioni](lessons/03-escrow-e-macchina-a-stati/README.md)
- [Lezione 4 — progetto e istruzioni](lessons/04-ether-receive-fallback-chiamate-esterne-cei/README.md)
- [Lezione 5 — progetto e istruzioni](lessons/05-reentrancy/README.md)
- [Lezione 6 — progetto e istruzioni](lessons/06-access-control/README.md)
- [Lezione 7 — progetto e istruzioni](lessons/07-errori-logici-e-state-machine/README.md)
- [Lezione 8 — progetto e istruzioni](lessons/08-erc20-allowance-e-integrazioni-sicure/README.md)
- [Lezione 9 — progetto e istruzioni](lessons/09-oracoli-prezzi-slippage-mev/README.md)
- [Lezione 10 — progetto e istruzioni](lessons/10-composability-e-dipendenze-esterne/README.md)
- [Lezione 11 — progetto e istruzioni](lessons/11-proxy-delegatecall-upgradeability/README.md)
- [Lezione 12 — progetto e istruzioni](lessons/12-governance-owner-multisig-timelock/README.md)
- [Lezione 13 — progetto e istruzioni](lessons/13-testing-approfondito-con-foundry/README.md)
- [Lezione 14 — progetto e istruzioni](lessons/14-fuzz-e-invariant-testing-con-foundry/README.md)
- [Lezione 15 — progetto e istruzioni](lessons/15-analisi-statica-con-slither/README.md)
- [Lezione 16 — progetto e istruzioni](lessons/16-metodologia-di-audit-completa/README.md)
- [Lezione 17 — progetto finale e istruzioni](lessons/17-progetto-finale-audit-escrow-evoluto/README.md)

Per eseguire una lezione dalla radice:

```bash
forge build --root lessons/01-transazioni-account-calldata-storage-revert
forge test --root lessons/01-transazioni-account-calldata-storage-revert -vv

forge build --root lessons/02-foundry-e-metodo-di-testing
forge test --root lessons/02-foundry-e-metodo-di-testing -vv

forge build --root lessons/03-escrow-e-macchina-a-stati
forge test --root lessons/03-escrow-e-macchina-a-stati -vv

forge build --root lessons/04-ether-receive-fallback-chiamate-esterne-cei
forge test --root lessons/04-ether-receive-fallback-chiamate-esterne-cei -vv

forge build --root lessons/05-reentrancy
forge test --root lessons/05-reentrancy -vv

forge build --root lessons/06-access-control
forge test --root lessons/06-access-control -vv

forge build --root lessons/07-errori-logici-e-state-machine
forge test --root lessons/07-errori-logici-e-state-machine -vv

forge build --root lessons/08-erc20-allowance-e-integrazioni-sicure
forge test --root lessons/08-erc20-allowance-e-integrazioni-sicure -vv

forge build --root lessons/09-oracoli-prezzi-slippage-mev
forge test --root lessons/09-oracoli-prezzi-slippage-mev -vv

forge build --root lessons/10-composability-e-dipendenze-esterne
forge test --root lessons/10-composability-e-dipendenze-esterne -vv

forge build --root lessons/11-proxy-delegatecall-upgradeability
forge test --root lessons/11-proxy-delegatecall-upgradeability -vv

forge build --root lessons/12-governance-owner-multisig-timelock
forge test --root lessons/12-governance-owner-multisig-timelock -vv

forge build --root lessons/13-testing-approfondito-con-foundry
forge test --root lessons/13-testing-approfondito-con-foundry -vv

forge build --root lessons/14-fuzz-e-invariant-testing-con-foundry
forge test --root lessons/14-fuzz-e-invariant-testing-con-foundry -vv

forge build --root lessons/15-analisi-statica-con-slither
forge test --root lessons/15-analisi-statica-con-slither -vv

forge build --root lessons/16-metodologia-di-audit-completa
forge test --root lessons/16-metodologia-di-audit-completa -vv

forge build --root lessons/17-progetto-finale-audit-escrow-evoluto
forge test --root lessons/17-progetto-finale-audit-escrow-evoluto -vv
```

Il progetto Foundry creato inizialmente da `forge init` resta per ora alla radice come riferimento.
Ogni sottoprogetto usa la dipendenza condivisa `lib/forge-std` e pinna autonomamente il compilatore.
