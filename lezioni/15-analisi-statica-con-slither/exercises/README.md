# Esercizi — Lezione 15

Non correggere un alert prima di avere scritto la proprietà che potrebbe violare.

## Percorso base

1. Esegui `slither-printers.sh` e confronta l'output con `INVENTORY.md`.
2. Esegui `slither-noisy.sh` e compila una nuova scheda usando il template.
3. Collega ogni external call a caller, target controllabile, state prima/dopo e failure policy.

## Percorso intermedio

1. Riproduci il finding unchecked con un test locale, poi confronta la remediation.
2. Genera JSON con `slither . --json slither-report.json` e trova detector, impact, confidence e
   source mapping.
3. Analizza `NotifierFlow`: scrivi l'invariante che una callback dovrebbe violare prima di decidere
   se sopprimere il warning.

## Percorso avanzato

1. Aggiungi una nuova funzione dopo la call del notifier e rivaluta ST-05.
2. Crea una baseline motivata per finding low/info, senza nasconderli soltanto perché rumorosi.
3. Scrivi una policy protocol-specific: ogni write all'oracle richiede authorization, zero check ed
   evento.
4. Confronta call graph, coverage e test per trovare un branch critico mai eseguito.

La traccia `TriageWorksheet.md` è deliberatamente vuota e va completata con evidenza verificabile.

