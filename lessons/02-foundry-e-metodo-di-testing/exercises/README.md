# Esercizi — Lezione 2

Prima di ogni test scrivi la proprietà nel formato **dato / quando / allora**. Le tracce non hanno
soluzioni incorporate: l'obiettivo è derivare il test dalla specifica.

## Percorso base

1. Indica Arrange, Act e Assert in `test_Register_SucceedsWithExactFee`.
2. Esegui un solo test con `--match-test` e poi l'intero test contract con `--match-contract`.
3. Aggiungi il caso “tentativo errato, poi fee corretta”.

## Percorso intermedio

1. Completa le verifiche sui saldi dopo un revert.
2. Esegui il profilo `mutation` e spiega perché quel fallimento è desiderato.
3. Applica le mutazioni al flag e al contatore descritte nella traccia; anticipa i test rossi.

## Percorso avanzato

1. Introduci un revert non correlato e confronta `expectRevert()` con il matching preciso.
2. Progetta proprietà e casi di confine per il limite di 100 registrazioni.
3. Immagina tre implementazioni errate che supererebbero una suite composta solo da happy path
   e doppia registrazione.

Lavora su una copia o su modifiche locali facilmente reversibili. Il contratto distribuito nella
directory `src/` rappresenta sempre la versione corretta di riferimento.

