# Smart Contract Security — corso e laboratori Foundry

Un percorso di 17 lezioni: ogni cartella riunisce teoria, guida del docente, codice,
test ed esercizi della stessa lezione.

## Da dove iniziare

- **Studenti:** apri la [Lezione 1](lezioni/01-transazioni-account-calldata-storage-revert/README.md) e segui il laboratorio.
- **Docenti:** apri la [guida del docente](lezioni/GUIDA-DOCENTE.md), con l'indice dei copioni, i tempi e la preparazione delle demo.
- **Materiale comune:** trovi la guida PDF per installare Foundry e i prompt di analisi in [risorse](risorse/README.md).
- **Primo esempio:** il progetto Counter generato da Foundry è in [esempi/counter](esempi/counter/README.md).

## Struttura

```text
lezioni/
  GUIDA-DOCENTE.md             indice e preparazione per il docente
  01-transazioni-account-calldata-storage-revert/
    README.md                 punto di ingresso e istruzioni del laboratorio
    teoria.md                 approfondimento teorico
    copione.md                guida per tenere la lezione
    dispensa.pdf              PDF originale, dove disponibile (lezioni 1–5)
    demo.sh                   demo locali
    foundry.toml              configurazione del sottoprogetto
    src/                      contratti Solidity
    test/                     test automatici
    script/                   script Foundry
    exercises/                esercizi e tracce
  ...                         lezioni da 02 a 17, con la stessa organizzazione
risorse/                      materiale comune al corso
esempi/counter/               progetto introduttivo Foundry
lib/forge-std/                dipendenza condivisa dai progetti
.github/workflows/            verifiche automatiche
```

Ogni lezione è un progetto Foundry autonomo e usa `../../lib/forge-std`.
I nomi tecnici `src`, `test`, `script` e `exercises` restano uniformi nei laboratori;
le cartelle specialistiche (`audit`, `mutation`, `scripts`) sono descritte nei rispettivi README.
Le cartelle `out` e `cache` sono generate da Foundry e ignorate da Git.

## Indice delle lezioni

Tutti i 17 laboratori sono disponibili. Apri il titolo per le istruzioni operative,
la teoria per approfondire o il copione per condurre la lezione.

| Lezione | Laboratorio | Approfondimento | Guida docente |
| --- | --- | --- | --- |
| 01 | [Transazioni, account, calldata, storage e revert](lezioni/01-transazioni-account-calldata-storage-revert/README.md) | [Teoria](lezioni/01-transazioni-account-calldata-storage-revert/teoria.md) | [Copione](lezioni/01-transazioni-account-calldata-storage-revert/copione.md) |
| 02 | [Foundry e metodo di testing](lezioni/02-foundry-e-metodo-di-testing/README.md) | [Teoria](lezioni/02-foundry-e-metodo-di-testing/teoria.md) | [Copione](lezioni/02-foundry-e-metodo-di-testing/copione.md) |
| 03 | [Escrow e macchina a stati](lezioni/03-escrow-e-macchina-a-stati/README.md) | [Teoria](lezioni/03-escrow-e-macchina-a-stati/teoria.md) | [Copione](lezioni/03-escrow-e-macchina-a-stati/copione.md) |
| 04 | [Ether, receive, fallback, chiamate esterne e CEI](lezioni/04-ether-receive-fallback-chiamate-esterne-cei/README.md) | [Teoria](lezioni/04-ether-receive-fallback-chiamate-esterne-cei/teoria.md) | [Copione](lezioni/04-ether-receive-fallback-chiamate-esterne-cei/copione.md) |
| 05 | [Reentrancy, CEI e guard](lezioni/05-reentrancy/README.md) | [Teoria](lezioni/05-reentrancy/teoria.md) | [Copione](lezioni/05-reentrancy/copione.md) |
| 06 | [Access control](lezioni/06-access-control/README.md) | [Teoria](lezioni/06-access-control/teoria.md) | [Copione](lezioni/06-access-control/copione.md) |
| 07 | [Errori logici e state machine](lezioni/07-errori-logici-e-state-machine/README.md) | [Teoria](lezioni/07-errori-logici-e-state-machine/teoria.md) | [Copione](lezioni/07-errori-logici-e-state-machine/copione.md) |
| 08 | [ERC-20, allowance e integrazioni sicure](lezioni/08-erc20-allowance-e-integrazioni-sicure/README.md) | [Teoria](lezioni/08-erc20-allowance-e-integrazioni-sicure/teoria.md) | [Copione](lezioni/08-erc20-allowance-e-integrazioni-sicure/copione.md) |
| 09 | [Oracoli, prezzi, slippage e MEV](lezioni/09-oracoli-prezzi-slippage-mev/README.md) | [Teoria](lezioni/09-oracoli-prezzi-slippage-mev/teoria.md) | [Copione](lezioni/09-oracoli-prezzi-slippage-mev/copione.md) |
| 10 | [Composability e dipendenze esterne](lezioni/10-composability-e-dipendenze-esterne/README.md) | [Teoria](lezioni/10-composability-e-dipendenze-esterne/teoria.md) | [Copione](lezioni/10-composability-e-dipendenze-esterne/copione.md) |
| 11 | [Proxy, delegatecall e upgradeability](lezioni/11-proxy-delegatecall-upgradeability/README.md) | [Teoria](lezioni/11-proxy-delegatecall-upgradeability/teoria.md) | [Copione](lezioni/11-proxy-delegatecall-upgradeability/copione.md) |
| 12 | [Governance, owner, multisig e timelock](lezioni/12-governance-owner-multisig-timelock/README.md) | [Teoria](lezioni/12-governance-owner-multisig-timelock/teoria.md) | [Copione](lezioni/12-governance-owner-multisig-timelock/copione.md) |
| 13 | [Testing approfondito con Foundry](lezioni/13-testing-approfondito-con-foundry/README.md) | [Teoria](lezioni/13-testing-approfondito-con-foundry/teoria.md) | [Copione](lezioni/13-testing-approfondito-con-foundry/copione.md) |
| 14 | [Fuzz testing e invariant testing con Foundry](lezioni/14-fuzz-e-invariant-testing-con-foundry/README.md) | [Teoria](lezioni/14-fuzz-e-invariant-testing-con-foundry/teoria.md) | [Copione](lezioni/14-fuzz-e-invariant-testing-con-foundry/copione.md) |
| 15 | [Analisi statica con Slither](lezioni/15-analisi-statica-con-slither/README.md) | [Teoria](lezioni/15-analisi-statica-con-slither/teoria.md) | [Copione](lezioni/15-analisi-statica-con-slither/copione.md) |
| 16 | [Metodologia di audit completa](lezioni/16-metodologia-di-audit-completa/README.md) | [Teoria](lezioni/16-metodologia-di-audit-completa/teoria.md) | [Copione](lezioni/16-metodologia-di-audit-completa/copione.md) |
| 17 | [Progetto finale: audit dell’Escrow evoluto](lezioni/17-progetto-finale-audit-escrow-evoluto/README.md) | [Teoria](lezioni/17-progetto-finale-audit-escrow-evoluto/teoria.md) | [Copione](lezioni/17-progetto-finale-audit-escrow-evoluto/copione.md) |

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
cd lezioni/01-transazioni-account-calldata-storage-revert
forge build
forge test -vv
```

Tutti i test devono passare. Da qui prosegui con il
[README della Lezione 1](lezioni/01-transazioni-account-calldata-storage-revert/README.md).

### Aggiornare il corso

Quando vengono pubblicate modifiche, dalla radice della repository:

```bash
git pull
git submodule update --init --recursive
```

Se hai modificato dei file per gli esercizi, `git pull` può segnalare un conflitto: salva prima le
tue modifiche, per esempio con `git stash`, poi riprendile con `git stash pop`.

## Eseguire i laboratori

Dalla radice del repository, indica la cartella della lezione:

```bash
forge build --root lezioni/01-transazioni-account-calldata-storage-revert
forge test --root lezioni/01-transazioni-account-calldata-storage-revert -vv
bash lezioni/01-transazioni-account-calldata-storage-revert/demo.sh help
```

Oppure entra nella cartella e usa `forge build`, `forge test` e `bash demo.sh check`.
Le demo operano offline: prepara prima compilatore e dipendenze con `forge build`.

Per controllare tutte le suite ordinarie, incluso Counter:

```bash
for progetto in esempi/counter lezioni/[0-9]*/; do
  forge test --root "$progetto" || break
done
```

La CI controlla formattazione, compilazione e test di tutti i progetti e l'analisi Slither
della lezione 15. I profili didattici che devono fallire, come `mutation` nella lezione 2,
si eseguono separatamente seguendo il relativo README.
