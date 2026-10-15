# Esercizi — Lezione 10

Prima del codice, classifica ogni dipendenza come critica o accessoria e scrivi la policy di
fallimento: revert, continue, pause o fallback.

## Percorso base

1. Correggi la call unchecked sia con un'interfaccia sia con una low-level call verificata.
2. Verifica con `expectEmit` i percorsi del notifier.
3. Elenca la differenza tra successo EVM e successo semantico.

## Percorso intermedio

1. Consenti due router e rifiutane un terzo con una allowlist.
2. Aggiungi un provider che restituisce zero, massimo e poi reverte.
3. Verifica cache fresca, boundary esatto e cache scaduta.

## Percorso avanzato

1. Progetta la sostituzione di una dependency con timelock ed eventi.
2. Elenca allowance e capability da revocare durante il replacement.
3. Disegna il dependency graph includendo governance, proxy e dipendenze transitive.

La traccia `DependencyExercises.t.sol` resta fuori dalla suite predefinita.

