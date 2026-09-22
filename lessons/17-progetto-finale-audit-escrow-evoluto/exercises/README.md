# Esercizi conclusivi

## 1 — Sesto finding

Rivedi zero address, ownership transfer, fee destination, pause semantics e notifier zero. Scrivi un
finding soltanto se colleghi root cause, impatto, prerequisiti e prova.

## 2 — Fee accounting

Specifica destinatario e ciclo di vita della fee. Implementa treasury/claim o trasferimento atomico,
poi testa token standard e fee-on-transfer in uscita.

## 3 — Pause semantics

Difendi o modifica la policy “blocca deposit/release, consenti refund” e aggiungi test per tutti i
ruoli e gli stati.

## 4 — Governance

Estendi `FinalTimelock` con cancel, predecessor, ruoli multipli e open executor, confrontandolo con
un'implementazione mantenuta. Verifica ogni bypass.

## 5 — Upgradeability

Crea una variante UUPS locale: initializer una volta, implementation lock, authorization, storage
compatibility, state preservation e migrazione V2. È un'estensione separata, non va innestata sul
target congelato.

## 6 — Handler invariant

Aggiungi oracle replacement e token failure al handler mantenendo attori realistici e ghost state
indipendente dal contratto.

## 7 — Mutation campaign

Applica una mutation alla volta: rimuovi auth oracle, usa requested, elimina stale check, ignora
transfer, cambia `>` in `>=`. La suite deve “uccidere” ogni mutation; ripristina poi il file.

## 8 — Mini report

Riscrivi il report in 2–4 pagine senza consultare la soluzione: executive summary, scope,
architecture, trust, finding, retest e limitations.

