# Matrice requisiti → test

Questa matrice rende bidirezionale la tracciabilità: da ogni requisito si arriva ai test e ogni test
dovrebbe dichiarare quale proprietà protegge.

| ID | Requisito | Test positivo | Test negativo/regressione |
| --- | --- | --- | --- |
| R01 | Solo il buyer deposita | `BuyerCanDepositAndStateDeltaIsCorrect` | `StrangerCannotDepositAndStateIsUnchanged` |
| R02 | Il deposito deve essere positivo | `BuyerCanDepositAndStateDeltaIsCorrect` | `ZeroDepositRevertsWithPreciseError` |
| R03 | Si deposita una sola volta | `BuyerCanDepositAndStateDeltaIsCorrect` | `CannotDepositTwice` |
| R04 | Il prezzo deve essere positivo | `PriceExactlyAtFreshnessBoundaryIsAccepted` | `ZeroAndNegativePricesAreRejected` |
| R05 | Il prezzo non deve essere stale | `PriceExactlyAtFreshnessBoundaryIsAccepted` | `PriceOneSecondPastFreshnessBoundaryIsRejected` |
| R06 | Il timestamp oracle non è futuro | `BuyerCanDepositAndStateDeltaIsCorrect` | `FutureOracleTimestampIsRejected` |
| R07 | Il credito deve essere interamente coperto | `FullDepositAndReleaseWorkflowPreservesEconomicAccounting` | `FeeOnTransferCannotCreateUnbackedLiability` |
| R08 | Un token `false-returning` non crea credito | — | `FalseReturnCannotCreateDepositCredit` |
| R09 | Solo il buyer rilascia | `ReleaseClearsLiabilityAndPaysBalanceDeltas` | `UnauthorizedCallerCannotReleaseEvenWhenFunded` |
| R10 | Release azzera la liability | `ReleaseClearsLiabilityAndPaysBalanceDeltas` | `FailedPayoutRollsBackTerminalState` |
| R11 | Refund solo dalla deadline | `RefundExactlyAtDeadlineSucceeds` | `RefundOneSecondBeforeDeadlineRevertsAndPreservesState` |
| R12 | Gli stati finali sono terminali | `ReleaseClearsLiabilityAndPaysBalanceDeltas` | `ReleasedIsTerminalState` |
| R13 | Fee massima inclusiva a 1000 bps | `FeeBoundary1000Succeeds` | `FeeBoundary1001RevertsAndPreservesOldFee` |
| R14 | Solo owner modifica configurazione | `OwnerUpdatesOracleWithEventAndState` | `StrangerCannotSetOracle` |
| R15 | Una callback non ritira due volte | `ReentrantCallbackCannotWithdrawTwice` | stessa regressione, con tentativo registrato |
| R16 | Un recipient che reverte non perde credito | — | `RevertingRecipientRollsBackCredit` |

La matrice non misura la qualità da sola: durante review controlla che ogni test possa realmente
fallire se il requisito viene mutato.

