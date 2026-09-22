# Lezione 10 — Composability e dipendenze esterne

Questa lezione tratta ogni external call come una trust boundary. La compatibilità ABI permette di
codificare una chiamata; non dimostra che il target sia corretto, disponibile o semanticamente
compatibile con il protocollo.

> Tutte le dipendenze sono mock locali. Non vengono invocati protocolli o asset reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_10_Composability_e_dipendenze_esterne.md`](../../lezioni%20SmartContracts/Lezione_10_Composability_e_dipendenze_esterne.md).

## Prima esecuzione

```bash
forge build --root lessons/10-composability-e-dipendenze-esterne
forge test --root lessons/10-composability-e-dipendenze-esterne -vv
```

Il warning sulla low-level call unchecked è intenzionale e appartiene soltanto al contratto
vulnerabile. I warning su `block.timestamp` derivano dalla scadenza esplicita della cache.

## Mappa dei file

```text
src/NotificationEscrow.sol       notifier accessorio e best-effort
src/UncheckedDependency.sol     falso successo dopo una call fallita
src/CheckedDependency.sol       code check, revert bubbling e stato coerente
src/BoundedIntegrator.sol       validazione semantica del return value
src/DependencyConsumer.sol      provider mutabile e cache con max age
src/AllowlistedExecutor.sol     target runtime limitati da admin e operator
src/utils/CallUtilsLite.sol     helper low-level ispezionabile
src/mocks/                      dipendenze valide, ostili e mutevoli
test/                           safety, liveness, policy e regressioni
exercises/                      replacement, capability e dependency graph
```

`CallUtilsLite` è una primitiva didattica, non un sostituto di una libreria production-ready. Una
codebase reale deve pin­nare e revisionare la utility scelta.

## Critica o accessoria?

```text
notifier      accessoria: il failure emette un evento, la release resta valida
router        critica: revert o output insufficiente annullano l'operazione
valueProvider critica per refresh; la cache è usabile solo entro maxAge
```

`try/catch` non è automaticamente più sicuro: è corretto nel notifier soltanto perché la notifica
non determina il diritto economico.

## Laboratorio low-level call

```bash
forge test --match-contract LowLevelCallsTest -vvvv
```

La versione vulnerabile registra `completed = true` sia quando il target reverte sia quando il
target non contiene codice. La versione corretta:

```text
verifica code.length
propaga il revert data
registra completed soltanto dopo il successo tecnico
```

Questo non dimostra ancora la correttezza semantica del risultato.

## Laboratorio ABI contro semantica

```bash
forge test --match-contract BoundedIntegratorTest -vvvv
```

`WeirdRouter` implementa l'interfaccia corretta e ritorna normalmente, ma produce `1` quando il
consumer richiede almeno `900`. Il bound viene quindi verificato nuovamente dal protocollo che ne
dipende.

## Laboratorio comportamento mutevole

```bash
forge test --match-contract DependencyConsumerTest -vvvv
```

Lo stesso address può prima restituire `100`, poi revertire, restituire zero o il massimo. Un
refresh fallito non corrompe l'ultimo valore valido, ma la cache non può essere usata indefinitamente.

## Allowlist e nuova trust boundary

L'allowlist impedisce all'operator di scegliere qualsiasi codice, ma assegna all'admin il potere di
cambiare i target fidati. In una review reale vanno analizzati ownership, timelock, eventi, proxy,
capability residue e procedure di emergenza.

## Tre percorsi

### Base — failure propagation

1. Osserva high-level revert e low-level `success`.
2. Verifica che un failure critico non lasci falso successo.
3. Rendi osservabile un failure accessorio.

### Intermedio — semantica e liveness

1. Valida i return value nel consumer.
2. Cambia il comportamento del provider dopo un primo successo.
3. Verifica che la cache abbia una scadenza esplicita.

### Avanzato — governance delle dipendenze

1. Disegna dipendenze dirette e transitive.
2. Analizza chi può sostituire o aggiornare ogni componente.
3. Misura capability persistenti e blast radius.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployDependencyLab.s.sol:DeployDependencyLab \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai distinguere ABI compatibility e semantic compatibility;
- sai spiegare revert propagation e atomicità;
- sai scegliere consapevolmente fail-open o fail-closed;
- sai verificare una low-level call senza creare falso successo;
- sai distinguere safety e liveness;
- sai costruire dependency graph, trust matrix e blast-radius analysis.

