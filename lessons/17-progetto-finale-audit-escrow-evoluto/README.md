# Lezione 17 — Progetto finale: audit dell’Escrow evoluto

Questo capstone applica l'intero corso in una review locale end-to-end: scope, architettura,
invarianti, review manuale, analisi statica, PoC, finding, remediation, regression, fuzz, invariant,
governance ritardata e report finale.

> `src/EscrowFinal.sol` è deliberatamente vulnerabile e resta congelato come evidenza. Non usarlo in
> produzione. `src/fixed/EscrowFinalFixed.sol` è una remediation didattica, non una certificazione.

Il testo completo è in
[`../../lezioni SmartContracts/Lezione_17_Progetto_Finale_Audit_Escrow_Evoluto.md`](../../lezioni%20SmartContracts/Lezione_17_Progetto_Finale_Audit_Escrow_Evoluto.md).

## Mappa

```text
src/EscrowFinal.sol              target congelato
src/fixed/EscrowFinalFixed.sol   remediation
src/mocks/                       dipendenze normali e avversariali
src/extensions/FinalTimelock.sol governance ritardata locale
test/audit/                       cinque riproduzioni
test/regression/                  suite minima e pause semantics
test/fuzz/                        amount, fee, freshness, caller
test/invariant/                   handler stateful con sei azioni
test/governance/                  proposer -> timelock -> escrow
audit/                            work paper, finding e report
exercises/                        consegna finale e mutation campaign
```

## Esecuzione

```bash
forge build --root lessons/17-progetto-finale-audit-escrow-evoluto
forge test --root lessons/17-progetto-finale-audit-escrow-evoluto -vv
```

La suite contiene 31 test: cinque PoC sul target, diciotto regression, quattro fuzz test, tre test di
governance e una campagna invariant con cinque proprietà e 8.192 chiamate.

Per il report coverage, l'invariant viene esclusa soltanto dalla strumentazione a causa del resolver
di `StdInvariant`; resta eseguita nel comando precedente:

```bash
forge coverage --root lessons/17-progetto-finale-audit-escrow-evoluto \
  --no-match-path 'test/invariant/FinalInvariant.t.sol'
```

Nel pass locale, `EscrowFinalFixed.sol` ha copertura del 98,57% delle linee e del 100% delle
funzioni; la copertura dei branch è 56,52%. Le branch non coperte restano materia di review,
non sono una prova di sicurezza.

## Workflow consigliato allo studente

1. Leggi [scope](audit/scope.md), [architettura](audit/architecture.md) e
   [invarianti](audit/invariants.md).
2. Nascondi temporaneamente `audit/findings/` e revisiona il target.
3. Compila [TriageWorksheet.md](exercises/TriageWorksheet.md) per ogni ipotesi.
4. Esegui le PoC con `--match-contract TargetFindingsTest -vvvv`.
5. Scrivi severità e remediation prima di leggere il [report](audit/report.md).
6. Revisiona il diff concettuale target/fixed.
7. Esegui regression, fuzz, invariant e governance.
8. Verifica la [retest checklist](audit/retest.md).

## Slither locale

```bash
python3 -m venv .venv-slither
source .venv-slither/bin/activate
python -m pip install -r requirements-slither.txt
bash scripts/slither-printers.sh
bash scripts/slither-target.sh
bash scripts/slither-fixed.sh
```

Il target deve produrre alert: un test che dimostra un bug “passa” perché la riproduzione è riuscita.
La versione corretta è analizzata separatamente; mock e test sono filtrati con motivazione.
Slither restituisce codice 255 quando trova detector: leggi il risultato e il
[triage dell'analisi statica](audit/static-analysis.md) prima di interpretarlo come errore del comando.

## Decisioni di specification

- `age == MAX_ORACLE_AGE` è accettato; `age > MAX_ORACLE_AGE` è stale.
- la pausa blocca deposit/release, ma non refund: blocca nuovo rischio e conserva l'uscita;
- il notifier è best-effort, ma il fallimento emette un evento;
- il balance delta supporta fee-on-transfer in ingresso; la semantica in uscita va valutata per ogni
  asset;
- il fee destination non è definito dalla specifica originale: resta una design question esplicita,
  non viene inventato silenziosamente.

## Completamento del corso

Il progetto è completato quando sai collegare ogni finding a una proprietà, riprodurlo localmente,
motivare la severità, verificare la patch e dichiarare ciò che rimane fuori scope. A quel punto la
roadmap principale 1–17 è terminata.
