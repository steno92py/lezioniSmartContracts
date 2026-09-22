# [AUD-01] La callback del token prima della chiusura consente il doppio pagamento

Severity: **High**

## Summary

`release` trasferisce token mentre `state == Funded` e la liability è ancora visibile. Un token con
callback può rientrare in `release`, che è permissionless, e pagare la stessa liability due volte.

## Impact

Il seller riceve più del deposito. Se l'escrow contiene riserve o fondi condivisi, l'attaccante può
drenarli e rendere insolventi altri utenti. Sono violate I-02, I-05 e I-20.

## Root Cause

Gli effects (`liability = 0`, `state = Released`) avvengono dopo l'interaction con il token.

## Preconditions

- token configurato con callback controllabile o compromesso;
- saldo dell'escrow maggiore della singola liability;
- prezzo valido e contratto non pausato.

La necessità di un token avversariale riduce la likelihood, ma l'impatto è perdita diretta e
ripetibile di asset: severità High nel threat model del laboratorio.

## Local Reproduction

```bash
forge test --root lessons/16-metodologia-di-audit-completa \
  --match-test test_AUD01_ReentrantTokenPaysSameLiabilityTwice -vvvv
```

La PoC deposita 100, aggiunge una riserva di 100 e osserva 200 al seller.

## Recommendation

Azzerare liability e impostare lo stato terminale prima della transfer. Conservare atomicità: se il
token fallisce, l'intera transazione ripristina gli effects. Un guard può essere defense in depth,
non sostituisce la macchina a stati corretta.

## Regression Test

`test_Regression_AUD01_ReentrantCallbackCannotPayTwice` e
`invariant_SellerCannotReceiveMoreThanOneSettlement`.
