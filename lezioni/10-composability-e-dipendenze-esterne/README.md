# Lezione 10 — Composability e dipendenze esterne

[Indice del corso](../../README.md#indice-delle-lezioni) · [Teoria](teoria.md) · [Copione docente](copione.md)

## Per tenere la lezione

Apri la [guida del docente](copione.md):
contiene la scaletta da 90 o 60 minuti, il discorso con esempi svolti, i file da mostrare,
le domande alla classe, i risultati attesi e un percorso senza terminale in caso di problemi.
Gli appunti teorici restano il riferimento per gli approfondimenti.

Dalla radice del repository, prima della lezione:

```bash
cd lezioni/10-composability-e-dipendenze-esterne
forge build
bash demo.sh check
bash demo.sh help
```

Il controllo completo deve eseguire 33 test. Le demo selezionate usano `--offline` e non richiedono
Anvil o RPC; prepara compilatore e dipendenze prima dell'aula. Dopo il `cd`, tutti i comandi
`bash demo.sh ...` e i comandi dei laboratori sotto partono dalla cartella della lezione.

## Tema della lezione

Questa lezione tratta ogni external call come una trust boundary. La compatibilità ABI permette di
codificare una chiamata; non dimostra che il target sia corretto, disponibile o semanticamente
compatibile con il protocollo.

> Tutte le dipendenze sono mock locali. Non vengono invocati protocolli o asset reali.

Il testo teorico completo resta in
[`teoria.md`](teoria.md).

## Prima esecuzione

Questi due comandi alternativi partono dalla **radice del repository**:

```bash
forge build --root lezioni/10-composability-e-dipendenze-esterne
forge test --root lezioni/10-composability-e-dipendenze-esterne -vv
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
`CheckedDependency` corregge i due falsi successi mostrati; non è un executor completo con
autorizzazione dei target e protezione generale dalle callback.

## Laboratorio ABI contro semantica

```bash
forge test --match-contract BoundedIntegratorTest -vvvv
```

`WeirdRouter` implementa l'interfaccia corretta e ritorna normalmente, ma produce `1` quando il
consumer richiede almeno `900`. Il bound viene quindi verificato nuovamente dal protocollo che ne
dipende.

I router sono mock che restituiscono numeri: questo controllo non dimostra che siano stati
trasferiti token né che il valore dichiarato dal router corrisponda a un effetto reale.

## Laboratorio comportamento mutevole

```bash
forge test --match-contract DependencyConsumerTest -vvvv
```

Lo stesso address può prima restituire `100`, poi revertire, restituire zero o il massimo. Un
refresh fallito non corrompe l'ultimo valore valido, ma la cache non può essere usata indefinitamente.
La scadenza è verificata da `cachedValue()`, non dal getter pubblico `lastGoodValue()`.
Il timestamp misura il tempo dal refresh locale, non l'età del dato alla fonte.

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

