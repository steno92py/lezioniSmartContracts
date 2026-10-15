# Lezione 15 — Analisi statica con Slither

[Indice del corso](../../README.md#indice-delle-lezioni) · [Teoria](teoria.md) · [Copione docente](copione.md)

## Per tenere la lezione

Apri la [guida del docente](copione.md): scalette da 60 e 90 minuti,
discorso, demo, risultati attesi e percorso senza terminale.
Dalla cartella di questa lezione usa `bash demo.sh check` per la suite completa (12 test)
e `bash demo.sh help` per le demo selezionate. Prepara compilatore e dipendenze con
`forge build` prima dell'aula; lo script delle demo opera offline.

## Tema e laboratorio

Questa lezione usa compiler, Slither, review manuale e test come strumenti complementari. Un alert
statico è una domanda prioritaria: diventa finding soltanto dopo reachability, threat model ed
evidenza locale.

> `src/noisy/` è intenzionalmente vulnerabile. Non copiare quei contratti in produzione.

Il testo teorico completo resta in
[`teoria.md`](teoria.md).

## Prima esecuzione Foundry

```bash
forge build --root lezioni/15-analisi-statica-con-slither
forge test --root lezioni/15-analisi-statica-con-slither -vv
```

Il warning sulla return value ignorata in `StaticLab.unsafeExecute` è intenzionale e viene
confermato da un test. La versione in `src/fixed/` non ignora failure e riduce la capability.

## Installazione locale isolata di Slither

Da questa directory:

```bash
python3 --version  # richiede Python >= 3.10
python3 -m venv .venv-slither
.venv-slither/bin/python -m pip install -r requirements-slither.txt
.venv-slither/bin/slither --version
```

Il repository pinna Slither `0.11.6`; non installa o modifica automaticamente tool Python globali.

Se `python3` è la versione 3.9 di macOS, crea l'ambiente con un Python più recente già
installato, per esempio `python3.13 -m venv .venv-slither`. Gli script in `scripts/` trovano
automaticamente `.venv-slither`: non serve attivarlo per eseguire
`bash scripts/slither-printers.sh`. Per usare direttamente il comando `slither`, puoi invece
attivare l'ambiente con `source .venv-slither/bin/activate`.

## Mappa del laboratorio

```text
src/noisy/StaticLab.sol          finding intenzionali da confermare
src/fixed/SafeStaticLab.sol      remediation con capability ridotta
src/context/NotifierFlow.sol     warning contestuale da sottoporre a triage
test/NoisyFindings.t.sol         riproduzioni locali dei problemi
test/FixedRegression.t.sol       proprietà permanenti dopo il fix
test/ContextualTriage.t.sol      callback e assunzioni del falso positivo
INVENTORY.md                     entry point, write path e source -> sink
TRIAGE.md                        cinque schede con evidenza e stato
scripts/                          detector, printer e gate della versione corretta
```

## Workflow guidato

### 1. Inventory con i printer

```bash
bash scripts/slither-printers.sh
```

Confronta entry point e write path con [INVENTORY.md](INVENTORY.md). I printer servono a costruire
la mappa prima che i detector orientino la tua attenzione.

### 2. Finding intenzionali

```bash
bash scripts/slither-noisy.sh
```

Indaga almeno:

```text
unchecked low-level call
admin write senza authorization
target e calldata controllati dall'utente
oracle mai inizializzato
```

Non tutti devono provenire da un detector: arbitrary-call e policy admin richiedono anche review
manuale.

### 3. Triage e conferma

Per ogni candidato compila caller, input, stato, external edge, asset impact e invariante. Poi
esegui la riproduzione:

```bash
forge test --match-contract NoisyFindingsTest -vvvv
```

Le schede complete sono in [TRIAGE.md](TRIAGE.md).

### 4. Remediation e regression

```bash
forge test --match-contract FixedRegressionTest -vvvv
bash scripts/slither-fixed.sh
```

Il gate statico fallisce per nuovi finding High/Medium nella superficie corretta. `noisy`, `context`,
mock, test e script sono filtrati con motivazione; non vengono cancellati né dichiarati sicuri.

## Source → sink

Il caso `arbitraryExecute` mostra perché controllare `success` non basta:

```text
attacker target + calldata
          |
          v
StaticLab.arbitraryExecute
          |
          v
token.transfer eseguita come StaticLab
          |
          v
asset del contratto trasferito
```

Slither identifica strutture e data flow; la gravità nasce dal fatto che il contratto possiede
asset o privilegi.

## Finding contestuale

`NotifierFlow` aggiorna `done` prima della call e non scrive stato dopo. Un callback tenta di
ripetere `finish`, ma riceve `AlreadyDone`. Il test non “prova sicurezza universale”: documenta che
la transizione non è ripetibile sotto l'attuale state model. Nuove funzioni, write dopo la call o un
cambio della trust assumption richiedono nuovo triage.

## Output JSON

```bash
slither . --json slither-report.json
```

Il report è un artifact di tooling, non un report di audit già pronto. Per ogni risultato servono
ancora status, severità contestuale, remediation e regression.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployStaticLab.s.sol:DeployStaticLab \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- distingui alert, finding confermato, rischio contestuale e falso positivo;
- usi printer per entry point, call graph e privileged write;
- segui un valore da source a sink;
- non copi impact/confidence nella severity business;
- riproduci ogni finding confermato e conservi una regression;
- motivi filtri e suppression e li rivaluti nei diff futuri.
