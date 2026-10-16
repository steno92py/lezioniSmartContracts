# Retest checklist

Questa checklist registra il pass originale del dossier. Per una nuova review annotare snapshot,
modifiche locali, versioni e comandi eseguiti: una spunta storica non è una nuova esecuzione.

- [x] target congelato e PoC ancora riproducibili;
- [x] F-01 usa balance delta;
- [x] F-02: stale e confine esatto verificati nei test; controlli zero/futuro revisionati nel codice;
- [x] F-03 false-return non finalizza;
- [x] F-04 stranger non cambia oracle;
- [x] F-05 fallimento osservabile e settlement non bloccato;
- [x] 18 regression test;
- [x] 4 fuzz test × 256 run;
- [x] campagna invariant con cinque proprietà, configurata con 128 run e depth 64;
- [x] governance: direct bypass/pre-delay/post-delay;
- [x] build e format;
- [x] Slither rieseguito su target e remediation, alert esaminati in `static-analysis.md`;
- [x] coverage riesaminata: fixed 98,57% linee, 56,52% branch;
- [ ] upgrade/storage validation: non applicabile, upgrade fuori scope;
- [x] snapshot storico del dossier: commit `c3e4fc3`.

## Review del fix

La remediation è nuovo codice: sono stati testati atomic rollback, boundary esatto, ruoli, refund in
pausa e fallimento del token/notifier. Restano design question su fee destination e policy dei token in
uscita; sono dichiarate nel report invece di essere considerate implicitamente risolte.

## Distinguere le evidenze

- `test_F03_FalseReturnTransferCannotFinalize` verifica l'errore, lo stato Funded e il credito
  ripristinato; non contiene asserzioni aggiuntive sui saldi dopo il revert.
- Le regressioni della freshness verificano stale e confine esatto. Il fuzz genera età da zero a
  due ore; non genera timestamp zero o futuri. Questi ultimi controlli sono presenti nel fixed,
  ma non hanno un test dedicato nella suite fornita.
- Il refund in pausa è verificato direttamente. L'handler evita deposit/release quando il
  contratto è in pausa: quelle azioni filtrate non provano il revert dei relativi entry point.
- L'handler usa un token standard e rinfresca l'oracle prima di release. Non comprende una
  campagna di callback avversarie o token failure; i casi di fallimento mirati restano separati.
- I tre test di governance verificano bypass diretto, pre-delay e post-delay del cambio oracle;
  non costituiscono una suite completa di ogni controllo di `FinalTimelock`.

I casi aggiuntivi sono proposte per gli [esercizi](../exercises/README.md), non verifiche già
eseguite. Il [copione](../copione.md) spiega come collegare ciascuna conclusione all'asserzione
o alla lettura che la sostiene.
