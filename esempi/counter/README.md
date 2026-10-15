# Counter — esempio iniziale Foundry

[Indice del corso](../../README.md)

Questo è il progetto introduttivo generato da `forge init`, conservato come riferimento.
Il percorso didattico principale inizia dalla [Lezione 1](../../lezioni/01-transazioni-account-calldata-storage-revert/README.md).

Dalla radice del repository:

```bash
forge build --root esempi/counter
forge test --root esempi/counter -vv
```

Oppure entra in `esempi/counter` ed esegui `forge build` e `forge test`.
La dipendenza `forge-std` è condivisa con le lezioni e si trova in `../../lib`.

- `src/Counter.sol`: contratto con contatore.
- `test/Counter.t.sol`: test unitario e fuzz test.
- `script/Counter.s.sol`: script Foundry di deploy.
