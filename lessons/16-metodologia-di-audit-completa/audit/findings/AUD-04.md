# [AUD-04] Il confronto inclusivo accetta un prezzo al limite di scadenza

Severity: **Low**

## Summary

La policy richiede `age < maxAge`, mentre il target reverte soltanto per `age > maxAge`. Un prezzo
con età esattamente uguale a `maxAge` viene accettato.

## Impact

Il settlement può usare un campione che la specifica considera già scaduto. L'impatto economico
dipende dal movimento avvenuto al confine e viola I-07.

## Root Cause

Off-by-one nel boundary temporale (`>` invece di `>=`).

## Preconditions

- timestamp esattamente al boundary;
- prezzo stale sopra soglia mentre il valore corrente non lo è.

La finestra stretta e l'impatto dipendente dal mercato motivano Low.

## Local Reproduction

```bash
forge test --root lessons/16-metodologia-di-audit-completa \
  --match-test test_AUD04_ExactStalenessBoundaryIsAccepted -vvvv
```

## Recommendation

Codificare direttamente la policy: rifiutare timestamp futuri e `block.timestamp - updatedAt >=
maxAge`. Aggiungere test below/exact/above.

## Regression Test

`test_Regression_AUD04_ExactStalenessBoundaryRejected`.
