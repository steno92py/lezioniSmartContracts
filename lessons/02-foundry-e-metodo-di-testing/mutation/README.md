# Mutation lab

Questo profilo contiene intenzionalmente un bug:

```solidity
if (msg.value < REGISTRATION_FEE) revert ...;
```

La specifica richiede invece una fee **esatta**. Avvia il laboratorio dalla directory della
Lezione 2:

```bash
FOUNDRY_PROFILE=mutation forge test -vvvv
```

Il risultato atteso è **un test fallito**: `2 ether` vengono accettati dal mutante, mentre il
regression test si aspettava un revert. Un rosso atteso qui dimostra che il test è capace di
distinguere l'implementazione corretta da quella plausibilmente sbagliata.

Il profilo predefinito resta verde e non viene modificato dal laboratorio.

