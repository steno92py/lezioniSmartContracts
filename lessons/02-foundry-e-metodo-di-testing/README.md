# Lezione 2 — Foundry e metodo di testing

Questo sottoprogetto insegna a trasformare un requisito in proprietà verificabili. Il contratto è
piccolo per permettere di concentrarsi sulla qualità della suite, non sulla quantità di codice.

> Ambiente esclusivamente locale e didattico. Non usare fondi o chiavi reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_02_Foundry_e_metodo_di_testing.md`](../../lezioni%20SmartContracts/Lezione_02_Foundry_e_metodo_di_testing.md).

## Requisito

> Un indirizzo può registrarsi una sola volta pagando esattamente 1 ether.

Da questa frase derivano proprietà separate:

- `1 ether` e nuovo account: successo;
- zero, meno o più di `1 ether`: revert preciso;
- seconda registrazione dello stesso account: revert;
- account differenti: stato indipendente;
- ogni successo incrementa contatore e totale esattamente una volta;
- ogni fallimento lascia stato e trasferimento di valore invariati;
- `totalReceived == registrationCount * REGISTRATION_FEE`.

## Prima esecuzione

Dalla directory della lezione:

```bash
forge build
forge test -vv
```

Dalla radice della repository:

```bash
forge build --root lessons/02-foundry-e-metodo-di-testing
forge test --root lessons/02-foundry-e-metodo-di-testing -vv
```

Il warning `locked-ether` è atteso: questa lezione esclude intenzionalmente i prelievi. Le chiamate
esterne e l'uscita di ETH saranno introdotte nelle lezioni successive.

Per confrontare, `src/fixed/FixedFeeRegistryFixed.sol` è lo stesso contratto con in più una
tesoreria `immutable`, fissata nel constructor, e `withdrawFees()`: la tesoreria ritira le fee e il
warning `locked-ether` non compare più. Le aggiunte sono segnate con `NOVITA'`; per vederle tutte
insieme:

```bash
diff src/FixedFeeRegistry.sol src/fixed/FixedFeeRegistryFixed.sol
```

## Mappa dei file

```text
src/FixedFeeRegistry.sol              contratto corretto sotto test
src/fixed/FixedFeeRegistryFixed.sol   stesso contratto con tesoreria e withdrawFees()
test/FixedFeeRegistry.t.sol           suite predefinita sempre verde
test/FixedFeeRegistryFixed.t.sol      prelievo, chiamante non autorizzato, tesoreria che rifiuta
script/DeployFixedFeeRegistry.s.sol   deploy locale facoltativo
mutation/                             implementazione errata e test rosso atteso
exercises/                            attività graduate escluse dalla suite
```

## Metodo: specifica prima del test

```text
requisito
   |
   v
proprietà falsificabile
   |
   v
Arrange -> Act -> Assert
   |
   +--> happy path
   +--> input vietati
   +--> stato dopo revert
   +--> regressione di un bug
```

Ogni test viene eseguito su uno stato indipendente: Foundry richiama `setUp()` prima di ciascun
caso. `vm.deal` e `vm.prank` configurano il laboratorio, ma non sono capacità disponibili agli
utenti sulla blockchain.

## Comandi da imparare

```bash
# intera suite
forge test

# una proprietà specifica
forge test --match-test test_RevertWhen_FeeIsTooHigh -vvvv

# un test contract
forge test --match-contract FixedFeeRegistryTest

# debugger EVM
forge test --debug --match-test test_RevertWhen_FeeIsTooHigh

# copertura: una mappa, non una prova di sicurezza
forge coverage
```

## Mutation lab: il rosso atteso

Il profilo separato cambia il confronto da “diverso dalla fee” a “minore della fee”. Esegui:

```bash
FOUNDRY_PROFILE=mutation forge test -vvvv
```

Il comando deve terminare con **1 test fallito**. Se il test diventasse verde, la mutazione avrebbe
eluso la proprietà “fee esatta”. Torna alla suite corretta con il normale `forge test`.

## Tre percorsi

### Base — imparare la meccanica

1. Leggi requisito e nomi dei test prima dell'implementazione.
2. Esegui suite completa e singolo test.
3. Individua Arrange, Act e Assert.
4. Completa il percorso base in `exercises/README.md`.

### Intermedio — testare il fallimento

1. Controlla selector e argomenti dei custom error.
2. Verifica mapping, contatori e saldi dopo ogni revert.
3. Esegui il mutation lab e interpreta la trace come un call tree.

### Avanzato — valutare la forza della suite

1. Formula mutazioni plausibili prima di leggere i test.
2. Chiediti quali mutazioni sopravviverebbero.
3. Distingui coverage strutturale e copertura delle proprietà.

## Deploy facoltativo su Anvil

Con `anvil` già avviato e usando esclusivamente una sua chiave di test:

```bash
forge script script/DeployFixedFeeRegistry.s.sol:DeployFixedFeeRegistry \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- la suite predefinita è verde;
- sai spiegare perché un `expectRevert()` generico può produrre un falso senso di sicurezza;
- sai indicare quale test distingue `msg.value == FEE` da `msg.value >= FEE`;
- hai osservato il fallimento atteso del profilo `mutation`;
- sai perché coverage elevata non equivale a correttezza.

