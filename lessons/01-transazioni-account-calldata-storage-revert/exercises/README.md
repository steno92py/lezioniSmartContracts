# Esercizi — Lezione 1

Gli esercizi sono intenzionalmente senza soluzione. Prima di scrivere codice, completa per ogni
caso questa frase: **dato ..., quando ..., allora ...**. È la proprietà che il test deve provare.

## Percorso base

1. Esegui la suite e individua Arrange, Act e Assert nel primo test.
2. Cambia temporaneamente `1 ether` in `2 ether` e anticipa quali assert falliranno.
3. Completa i test sui due beneficiari e sul confine 256/257 byte.

## Percorso intermedio

1. Completa il test con due payer per lo stesso beneficiario.
2. Verifica tutti gli effetti dopo un revert avvenuto quando esiste già dello stato.
3. Usa `cast sig` e `cast calldata` come indicato nel README principale.

## Percorso avanzato

1. Scrivi la tabella caller/input/storage/revert per `record` senza guardare i test.
2. Spiega perché `balance == totalRecorded` non è un invariante Ethereum universale.
3. Modifica localmente `SenderAuthToy` reintroducendo `tx.origin`: quale regression test fallisce?

La traccia iniziale si trova in `EscrowLesson1Exercises.t.sol`. Copiala sotto `test/` soltanto
quando inizi a implementarla; così la suite distribuita rimane verde.

