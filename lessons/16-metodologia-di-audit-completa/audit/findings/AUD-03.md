# [AUD-03] Il guardian può sostituire l'oracle aggirando governance

Severity: **Medium**

## Summary

La specifica limita il guardian alla pausa, ma `setOracle` autorizza sia governance sia guardian.
Un guardian compromesso può installare un feed sopra soglia e rendere eseguibile `release`.

## Impact

I fondi possono essere inviati al seller prima che la condizione economica reale sia soddisfatta.
La capability difensiva diventa un controllo sul settlement, violando I-09 e I-10.

## Root Cause

La stessa condizione di accesso usata per `pause` è stata riutilizzata su una funzione con impatto e
trust model differenti.

## Preconditions

- compromissione o malizia del guardian;
- escrow nello stato Funded;
- possibilità di distribuire/indicare un oracle manipolato.

Il privilegio richiesto riduce la likelihood; il guardian, però, è deliberatamente meno fidato di
governance. Severity Medium.

## Local Reproduction

```bash
forge test --root lessons/16-metodologia-di-audit-completa \
  --match-test test_AUD03_GuardianCanBypassGovernanceAndForceSettlement -vvvv
```

## Recommendation

Autorizzare soltanto governance in `setOracle`; mantenere il guardian limitato a `pause`. In un
sistema reale verificare anche che governance sia il timelock/multisig previsto dal deployment.

## Regression Test

`test_Regression_AUD03_GuardianCannotSetOracle`.
