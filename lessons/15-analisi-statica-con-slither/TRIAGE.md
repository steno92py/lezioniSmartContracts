# Worksheet di triage

Un detector produce un candidato. Le schede seguenti aggiungono reachability, capability, proprietà
violata, riproduzione e remediation.

## ST-01 — Low-level call ignorata

| Campo | Valutazione |
| --- | --- |
| Pattern/detector | `unchecked-lowlevel` |
| Posizione | `StaticLab.unsafeExecute` |
| Reachability | external, qualsiasi caller |
| Input controllati | `target` e `data` |
| Stato critico | `completed` |
| Proprietà | `completed == true` implica external action riuscita |
| Stato triage | confermato |
| Riproduzione | `test_Confirmed_UncheckedCallCreatesFalseSuccess` |
| Remediation | interfaccia tipizzata/high-level call; failure propagato |
| Regression | `test_Regression_FailedActionCannotMarkCompleted` |

L'impatto del tool diventa business impact perché il flag registra un successo mai avvenuto.

## ST-02 — Write path admin senza authorization

| Campo | Valutazione |
| --- | --- |
| Segnale | `vars-and-auth` + review manuale |
| Posizione | `StaticLab.setAdmin` |
| Reachability | external, qualsiasi caller |
| Stato critico | `admin` |
| Proprietà | solo l'admin corrente può iniziare il cambio |
| Stato triage | confermato |
| Riproduzione | `test_Confirmed_AnyoneCanTakeAdminRole` |
| Remediation | authorization e acceptance a due fasi |
| Regression | `test_Regression_StrangerCannotReplaceAdmin` |

Il detector può non conoscere la policy organizzativa: il finding nasce dall'unione tra printer e
specifica.

## ST-03 — Capability di arbitrary external call

| Campo | Valutazione |
| --- | --- |
| Segnale | target/data user-controlled; call graph e source→sink |
| Posizione | `StaticLab.arbitraryExecute` |
| Reachability | external, qualsiasi caller |
| Sink | `target.call(data)` eseguita come `StaticLab` |
| Asset impact | ETH, token o privilegi detenuti dal contratto |
| Proprietà | un utente non deve poter usare l'autorità del contratto verso target arbitrari |
| Stato triage | confermato |
| Riproduzione | `test_Confirmed_ArbitraryCallCanMoveAssetsHeldByLab` |
| Remediation | target immutabile, interfaccia ristretta e caller autorizzato |
| Regression | `test_AdminExecutesOnlyImmutableTypedAction` |

Il return value è controllato, ma questo non riduce la capability. È il caso più importante di
“nessun finding obvious” che non equivale a design sicuro.

## ST-04 — Oracle non inizializzato

| Campo | Valutazione |
| --- | --- |
| Pattern/detector | `uninitialized-state` o inventory manuale |
| Posizione | `StaticLab.oracle` / `readOracle` |
| Effetto | il read path non può restituire una risposta valida |
| Stato triage | confermato |
| Riproduzione | `test_Confirmed_UninitializedOracleMakesReadPathUnusable` |
| Remediation | inizializzare e validare oppure rimuovere la feature incompleta |

La versione corretta rimuove il percorso: una feature security-sensitive incompleta non viene
mantenuta come dead configuration.

## ST-05 — External notifier dopo state update

| Campo | Valutazione |
| --- | --- |
| Segnale | reentrancy/event ordering da investigare |
| Posizione | `NotifierFlow.finish` |
| State before call | `done = true` |
| State after call | nessuno; solo evento |
| Callback | può riprovare `finish`, che reverte `AlreadyDone` |
| Stato triage | non sfruttabile per ripetere la transizione nel modello corrente |
| Evidenza | `test_CallbackCannotRepeatTerminalTransition` |
| Assumption da rivalutare | nuove funzioni che usano `done`, notifier upgradeabile, write dopo call |

Non aggiungiamo una suppression automatica. Il test e questa motivazione devono essere rivisti se il
diff modifica stato condiviso o trust assumption.

