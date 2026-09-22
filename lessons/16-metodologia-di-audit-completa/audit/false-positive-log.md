# False-positive e triage log

## FP-01 — `block.timestamp` usato in un confronto

- Segnale: il lint segnala dipendenza dal timestamp.
- Perché non è un finding autonomo: la freshness di un oracle richiede il tempo di blocco; piccoli
  scostamenti del proposer sono assorbiti da `maxAge`.
- Assunzione: `maxAge` è molto maggiore della tolleranza di timestamp della chain target.
- Evidenza: il timestamp non determina da solo il prezzo e viene usato soltanto per l'età.
- Da riaprire se: una soglia di pochi secondi crea vantaggio economico o cambia la chain.

## FP-02 — Reentrancy warning nel deposito corretto

- Segnale: `_safeTransferFrom` precede gli aggiornamenti di `liability/state`.
- Perché non è confermato: soltanto il buyer può chiamare `deposit`; durante il callback il caller è
  il token, non il buyer. Il saldo viene misurato dopo la call e qualsiasi revert è atomico.
- Assunzione: il token non è anche l'indirizzo buyer e non esistono altri entry point che consumano
  uno stato parzialmente scritto.
- Evidenza: caller check e assenza di write prima della call.
- Da riaprire se: si aggiungono depositi permissionless, hook o accounting condiviso.

## FP-03 — Evento emesso dopo una external call nella remediation

- Segnale: lint `reentrancy-events` dopo transfer/notifier.
- Perché non consente doppio settlement: state e liability sono chiusi prima del trasferimento; una
  callback non può ripetere la transizione. L'evento `NotificationResult` descrive necessariamente
  l'esito di una chiamata già avvenuta.
- Assunzione: i consumer off-chain usano `Released` insieme allo stato canonico.
- Evidenza: regression reentrancy e terminal-state invariant.
- Da riaprire se: vengono aggiunti eventi prima/dopo che rappresentano ordini economici distinti.

Un warning scartato non è “sbagliato”: è una struttura che, sotto le assunzioni documentate, non
raggiunge un impatto di sicurezza.
