# Inventory statico e source → sink

## Entry point

| Contratto | Funzione | Categoria | Write | External edge |
| --- | --- | --- | --- | --- |
| `StaticLab` | `unsafeExecute` | user | `completed` | target arbitrario, unchecked |
| `StaticLab` | `arbitraryExecute` | user | — | target arbitrario, checked |
| `StaticLab` | `setAdmin` | admin-intended ma public | `admin` | — |
| `StaticLab` | `readOracle` | view | — | oracle non inizializzato |
| `SafeStaticLab` | `execute` | admin | `completed` | action tipizzata immutabile |
| `SafeStaticLab` | `transferAdmin` | admin | `pendingAdmin` | — |
| `SafeStaticLab` | `acceptAdmin` | pending admin | `admin`, `pendingAdmin` | — |
| `NotifierFlow` | `finish` | user | `done` prima della call | notifier immutabile |

## Variabili critiche e write path

```text
StaticLab.admin
└── setAdmin             nessuna authorization: finding confermato

SafeStaticLab.admin
└── acceptAdmin          richiede msg.sender == pendingAdmin

SafeStaticLab.pendingAdmin
├── transferAdmin        onlyAdmin
└── acceptAdmin          azzera dopo acceptance

completed
├── unsafeExecute        dopo call ignorata: falso successo
└── SafeStaticLab.execute prima della high-level call: revert ripristina lo stato
```

## Source → sink

```text
msg.sender + target + data
          |
          v
StaticLab.arbitraryExecute
          |
          v
target.call(data) eseguita con l'autorità e gli asset del contratto
```

Nella remediation:

```text
admin autorizzato + payload
          |
          v
SafeStaticLab.execute
          |
          v
IStaticAction immutable e tipizzata
```

