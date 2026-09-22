# Lezione 16 — Metodologia di audit completa

Questa lezione trasforma una review in un processo riproducibile: scope, architettura, threat model,
invarianti, ipotesi, PoC, finding, remediation e retest. Il laboratorio non premia chi trova più
warning: premia chi collega una causa a una proprietà violata con evidenza verificabile.

> `src/target/AuditEscrow.sol` contiene vulnerabilità intenzionali. È il reperto congelato
> dell'audit: non copiarlo in produzione e non correggerlo direttamente.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_16_Metodologia_di_Audit_Completa.md`](../../lezioni%20SmartContracts/Lezione_16_Metodologia_di_Audit_Completa.md).

## Obiettivi

Al termine saprai:

- fissare uno scope verificabile prima di leggere il codice;
- modellare asset, attori, trust boundary e dipendenze;
- convertire requisiti in invarianti testabili;
- passare da osservazione a ipotesi, evidenza e finding;
- distinguere finding confermati, osservazioni e falsi positivi;
- motivare severità e remediation;
- retestare una patch senza cancellare la PoC originale.

## Mappa del laboratorio

```text
src/target/AuditEscrow.sol       target vulnerabile congelato
src/fixed/RemediatedEscrow.sol   patch separata sottoposta a retest
src/mocks/AuditMocks.sol         token, oracle e notifier avversariali
audit/*.md                       work paper e report riproducibili
audit/findings/                  finding completi, uno per root cause
audit/tests/                     PoC, regression, fuzz e invariant
exercises/                       tracce graduate e template vuoto
scripts/                         passata Slither e printer di supporto
```

Foundry legge i test da `audit/tests/`: in questo progetto le prove sono parte esplicita del dossier
di audit, non materiale separato.

## Prima esecuzione

Dalla radice della repository:

```bash
forge build --root lessons/16-metodologia-di-audit-completa
forge test --root lessons/16-metodologia-di-audit-completa -vv
forge coverage --root lessons/16-metodologia-di-audit-completa \
  --no-match-path 'audit/tests/RemediatedInvariant.t.sol'
```

La suite contiene 14 test: 6 prove sul target, 7 retest/fuzz e una campagna invariant con tre
proprietà. I test `AUD-*` devono passare proprio perché dimostrano i bug; non sono approvazioni del
contratto vulnerabile.

Il file invariant viene escluso soltanto dalla strumentazione coverage per evitare una duplicazione
di `StdInvariant` nel resolver della versione locale di Foundry; viene comunque compilato ed eseguito
dal normale `forge test`.

## Percorso guidato

### 1. Non aprire subito i finding

Leggi nell'ordine:

1. [scope.md](audit/scope.md)
2. [architecture.md](audit/architecture.md)
3. [threat-model.md](audit/threat-model.md)
4. [invariants.md](audit/invariants.md)
5. [requirements-matrix.md](audit/requirements-matrix.md)
6. [attack-surface.md](audit/attack-surface.md)

Poi prova a compilare una copia di [HypothesisWorksheet.md](exercises/HypothesisWorksheet.md).

### 2. Audit del target

Leggi `AuditEscrow` due volte: prima per entry point, poi seguendo ogni write a `state`, `liability`,
`oracle` e `paused`. Confronta le tue ipotesi con [hypotheses.md](audit/hypotheses.md) soltanto dopo.

Esegui le riproduzioni singolarmente:

```bash
forge test --root lessons/16-metodologia-di-audit-completa \
  --match-contract AuditEscrowFindingsTest -vvvv
```

### 3. Finding e severità

Ogni documento in `audit/findings/` separa impatto e prerequisiti. Un finding High non è “un alert
rosso”: è una proprietà ad alto impatto violabile nelle condizioni documentate.

### 4. Review della remediation

Confronta `src/target/` e `src/fixed/`, poi esegui:

```bash
forge test --root lessons/16-metodologia-di-audit-completa \
  --match-contract RemediationRetestTest -vvvv
forge test --root lessons/16-metodologia-di-audit-completa \
  --match-contract RemediatedInvariantTest -vvvv
```

La patch applica CEI, rifiuta esplicitamente transfer-tax token, restringe `setOracle`, rende
stretta la freshness policy e degrada il notifier a best-effort.

## Passata Slither facoltativa ma raccomandata

Installa la versione pinnata in un ambiente isolato:

```bash
python3 -m venv .venv-slither
source .venv-slither/bin/activate
python -m pip install -r requirements-slither.txt
bash scripts/slither-printers.sh
bash scripts/slither-target.sh
```

`slither-target.sh` può terminare con stato non zero: sul target i finding sono intenzionali. Il
triage dei warning osservati è in [false-positive-log.md](audit/false-positive-log.md).

## Due percorsi per livelli diversi

Se è il tuo primo audit, usa i test già scritti e completa per ogni funzione le cinque domande in
`attack-surface.md`: chi chiama, cosa controlla, cosa scrive, chi riceve il controllo, quale
invariante rischia.

Se hai già esperienza, nascondi `audit/findings/`, ricostruisci le dieci ipotesi, assegna severità
prima di leggere il report e aggiungi un handler invariant che eserciti anche pause/unpause e cambio
oracle sotto ruoli realistici.

## Deploy locale facoltativo

```bash
forge script \
  lessons/16-metodologia-di-audit-completa/script/DeployAuditLab.s.sol:DeployAuditLab \
  --root lessons/16-metodologia-di-audit-completa \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai indicare scope e limitazioni senza ambiguità;
- hai scritto proprietà prima di cercare bug;
- ogni finding confermato ha PoC minima e regression;
- sai spiegare perché i warning scartati non sono applicabili oggi;
- verifichi la patch con diff, suite completa, fuzz e invariant;
- il report non promette assenza assoluta di vulnerabilità.
