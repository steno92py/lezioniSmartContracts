# Work paper e log di esecuzione

## Ordine delle passate

1. Scope e build riproducibile.
2. Architettura, asset, attori e trust boundary.
3. Invarianti e matrice dei requisiti.
4. Entry point e write path.
5. Flussi critici: deposit, release, refund, setOracle.
6. Passata avversariale: callback, fee token, stale boundary, ruolo errato, revert esterno.
7. Tooling e triage.
8. Consolidamento per root cause.
9. Review della patch e retest.

## Comandi registrati

```bash
forge fmt --root lessons/16-metodologia-di-audit-completa --check
forge build --root lessons/16-metodologia-di-audit-completa --sizes
forge test --root lessons/16-metodologia-di-audit-completa -vvv
forge coverage --root lessons/16-metodologia-di-audit-completa \
  --no-match-path 'audit/tests/RemediatedInvariant.t.sol'
bash scripts/slither-printers.sh
bash scripts/slither-target.sh
```

## Risultato Foundry osservato

- build Solidity 0.8.37 riuscita;
- 14 test passati, 0 falliti, 0 saltati;
- fuzz: 256 run nel profilo di test predefinito;
- invariant: 128 run × 32 chiamate, tre proprietà verificate;
- coverage strumentata (invariant esclusa, ma testata separatamente): 79,12% linee, 70,85% statement;
- Slither locale 0.11.4: 12 contratti, 100 detector, 7 risultati sul target; la reentrancy di
  `release` è stata confermata dalla PoC, gli altri segnali sono stati sottoposti a triage;
- PoC interamente locali, senza fork o RPC esterno.

Il requisito del progetto pinna Slither 0.11.6. L'esecuzione 0.11.4 sopra è annotata come evidenza
locale, non spacciata per il run della versione pinnata; CI o un venv aggiornato devono ripetere il
pass prima di un deliverable professionale.

## Evidenza per finding

| Finding | PoC target | Retest remediation | Invariante |
| --- | --- | --- | --- |
| AUD-01 | `test_AUD01_ReentrantTokenPaysSameLiabilityTwice` | `test_Regression_AUD01_*` | seller <= un settlement |
| AUD-02 | `test_AUD02_FeeTokenCreatesInsolventNominalLiability` | `test_Regression_AUD02_*` | assets >= liability |
| AUD-03 | `test_AUD03_GuardianCanBypassGovernanceAndForceSettlement` | `test_Regression_AUD03_*` | n/a, access test mirato |
| AUD-04 | `test_AUD04_ExactStalenessBoundaryIsAccepted` | `test_Regression_AUD04_*` | n/a, boundary test mirato |
| OBS-01 | `test_OBS01_RevertingOptionalNotifierBlocksSettlement` | `test_Regression_OBS01_*` | terminalità dopo successo |

## Retest checklist

- [x] target originale non modificato;
- [x] diff concettuale reviewato;
- [x] ogni PoC ha una regression nominata;
- [x] suite completa rieseguita;
- [x] fuzz sull'accounting rieseguito;
- [x] invariant di solvency, terminalità e singolo payout rieseguite;
- [ ] validazione upgrade/storage layout: non applicabile, proxy fuori scope;
- [ ] deploy su chain reale: fuori scope.
