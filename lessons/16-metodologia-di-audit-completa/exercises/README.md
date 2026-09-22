# Esercizi graduati

## Livello 1 — Orientamento

1. Segui `deposit` e annota saldo reale, liability e stato prima/dopo.
2. Disegna i tre edge del lifecycle ammessi.
3. Esegui una sola PoC con `--match-test` e spiega quale invariante viola.

## Livello 2 — Audit manuale

1. Compila il template per H-01 senza leggere `audit/findings/`.
2. Aggiungi test below/exact/above per `maxAge`.
3. Aggiungi test per prezzo zero, negativo e timestamp futuro.
4. Verifica pause/unpause per ogni ruolo.

## Livello 3 — Adversarial testing

1. Implementa un token che restituisce `false` e testa target/remediation.
2. Implementa un token senza return data e confronta le due integrazioni.
3. Estendi l'handler invariant con pause e un oracle mutabile sotto ruoli realistici.
4. Introduci deliberatamente un fix solo con guard e cerca la nuova failure mode.

## Livello 4 — Audit professionale

1. Ancora lo scope a un commit reale.
2. Esporta output Slither JSON e collega ogni alert al triage log.
3. Proponi severity alternative cambiando una sola trust assumption.
4. Scrivi una remediation che supporti fee-on-transfer in ingresso e documenta la semantica in
   uscita.
5. Aggiungi proxy e timelock, quindi estendi scope, storage layout review e governance graph.
