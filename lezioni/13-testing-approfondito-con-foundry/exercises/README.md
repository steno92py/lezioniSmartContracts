# Esercizi — Lezione 13

Lavora un requisito alla volta. Prima scrivi in una frase la proprietà, poi il test che dovrebbe
fallire se quella proprietà venisse rimossa.

## Percorso base

1. Copia `TestingExercises.t.sol` sotto `test/` e completa i test con revert preciso.
2. Aggiungi i boundary `MAX_PRICE_AGE - 1`, `MAX_PRICE_AGE` e `MAX_PRICE_AGE + 1`.
3. Per ogni negative test verifica anche state, liability e balance rimasti invariati.

## Percorso intermedio

1. Scrivi lo stesso test oracle con `MockOracle` e con `vm.mockCall`.
2. Aggiungi `vm.expectCall` senza rimuovere le assertion sullo stato.
3. Implementa un token senza return data e verifica la compatibilità con `_callOptionalReturn`.
4. Genera un report con `forge coverage --report summary` e spiega un branch scoperto prima di
   aggiungere un test.

## Percorso avanzato

1. Muta temporaneamente `state = State.Funded` rimuovendolo: identifica i test che devono fallire.
2. Muta `>` in `>=` nel controllo di freshness e verifica che il boundary test uccida il mutante.
3. Estendi `REQUIREMENTS.md` con almeno cinque requisiti e collega positive, negative e regression.
4. Crea un test che dimostri il bug di un vault vulnerabile, senza usare fondi o reti reali.

La traccia resta fuori dalla suite predefinita per non consegnare esercizi già risolti.

