# [AUD-02] Accounting nominale crea liability non collateralizzate

Severity: **Medium**

## Summary

`deposit` salva l'argomento richiesto senza misurare il balance delta. Con un transfer-tax token,
l'escrow riceve meno di quanto accredita.

## Impact

Una liability di 100 può essere coperta da soli 90 token. Release e refund possono revertire in
modo permanente, bloccando il lifecycle e violando solvency (I-03, I-04, I-17).

## Root Cause

Il codice confonde `requestedAmount` con `receivedAmount` e non dichiara/enforcement la token policy.

## Preconditions

- viene configurato un token fee-on-transfer o con semantica equivalente;
- la fee è attiva al deposito.

Non serve un caller privilegiato dopo il deploy, ma l'impatto primario è lock/insolvenza del singolo
escrow, non estrazione diretta: severità Medium.

## Local Reproduction

```bash
forge test --root lessons/16-metodologia-di-audit-completa \
  --match-test test_AUD02_FeeTokenCreatesInsolventNominalLiability -vvvv
```

## Recommendation

Scegliere una policy esplicita. La remediation didattica misura il saldo prima/dopo e reverte se
`received != requested`; un protocollo che supporta fee token deve invece accreditare il delta e
definire anche la semantica delle fee in uscita.

## Regression Test

`test_Regression_AUD02_FeeTokenRejectedAtomically`, fuzz sul balance delta e
`invariant_AssetsAlwaysCoverLiability`.
