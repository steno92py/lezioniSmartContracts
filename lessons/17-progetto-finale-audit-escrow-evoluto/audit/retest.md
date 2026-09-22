# Retest checklist

- [x] target congelato e PoC ancora riproducibili;
- [x] F-01 usa balance delta;
- [x] F-02 rifiuta stale/future/zero timestamp;
- [x] F-03 false-return non finalizza;
- [x] F-04 stranger non cambia oracle;
- [x] F-05 fallimento osservabile e settlement non bloccato;
- [x] 18 regression test;
- [x] 4 fuzz test × 256 run;
- [x] 5 invariant × 128 run × 64 chiamate;
- [x] governance: direct bypass/pre-delay/post-delay;
- [x] build e format;
- [x] Slither rieseguito su target e remediation, alert esaminati in `static-analysis.md`;
- [x] coverage riesaminata: fixed 98,57% linee, 56,52% branch;
- [ ] upgrade/storage validation: non applicabile, upgrade fuori scope;
- [x] snapshot del codice: commit `c3e4fc3`.

## Review del fix

La remediation è nuovo codice: sono stati testati atomic rollback, boundary esatto, ruoli, refund in
pausa e callback/failure policy. Restano design question su fee destination e policy dei token in
uscita; sono dichiarate nel report invece di essere considerate implicitamente risolte.
