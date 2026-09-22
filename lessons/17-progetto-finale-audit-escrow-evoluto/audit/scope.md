# Scope

## Identificazione

- Target: `src/EscrowFinal.sol`.
- Compilatore: Solidity 0.8.37, EVM Prague, optimizer 200 run.
- Snapshot: working tree locale; non esiste ancora un commit `HEAD` a cui ancorare lo scope.
- Ambiente: Foundry/Anvil locale, account e asset fittizi, nessun fork o protocollo reale.

L'assenza di commit è registrata come limitazione. Prima di un audit reale lo scope deve essere
fissato a repository e hash immutabile.

## In scope

Accounting ERC-20, lifecycle, oracle freshness, privilegi, fee bound, pausa, chiamate esterne,
failure policy e osservabilità del notifier.

## Support e retest

Interfacce, mock e test sono strumenti di evidenza. `EscrowFinalFixed` entra in scope solo nella
review della remediation. `FinalTimelock` dimostra l'estensione di governance, ma non è presentato
come implementazione production-ready.

## Out of scope

Frontend/backend, chiavi, provider oracle reale, MEV, token rebasing, proxy/UUPS, storage migration,
multisig reale e deploy pubblico.

## Assunzioni

- buyer/seller sono fissi;
- owner rappresenta governance;
- token supportati espongono l'interfaccia ERC-20;
- oracle restituisce prezzo USD e timestamp;
- notifier è opzionale;
- release e refund sono terminali;
- fee massima 10%; destinazione fee da specificare prima della produzione.

