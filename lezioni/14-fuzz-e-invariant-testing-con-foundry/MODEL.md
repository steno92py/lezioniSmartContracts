# Modello dello stateful invariant test

Un invariant test vale soltanto per gli stati che il suo modello rende raggiungibili. Questo file
dichiara esplicitamente quel perimetro.

## CreditVault

### Asset policy

- `ExactToken` trasferisce esattamente l'amount;
- niente fee, rebase, callback o return `false`;
- nessuna donation diretta al vault nell'action space;
- saldo iniziale del vault uguale a zero.

Con queste precondizioni vale la relazione forte:

```text
token.balanceOf(vault) == vault.totalCredit()
```

Se aggiungessimo donation dirette, la relazione corretta diventerebbe:

```text
token.balanceOf(vault) >= vault.totalCredit()
```

### Actor e azioni

Gli actor sono Alice, Bob e Carol. `targetContract` limita Foundry al `VaultHandler`; i target
selector limitano ulteriormente le azioni a:

```text
deposit(actorSeed, amount)       azione valida bounded
withdraw(actorSeed, amount)      azione valida o no-op senza credito
withdrawTooMuch(actorSeed, extra) azione avversaria con rollback verificato
```

Il caller casuale usato da Foundry per invocare l'handler non è il caller del protocollo: l'handler
sceglie l'actor e usa `vm.prank` in modo esplicito.

### Osservabili indipendenti

```text
on-chain: balance, totalCredit, credit[actor]
ghost:    deposited, withdrawn
```

Gli invarianti confrontano balance, contabilità del protocollo, somma cross-user e net deposit.

## LifecycleEscrow

Il bounded handler consente soltanto:

```text
Created -> Funded -> Released
                  -> Refunded
```

`ghostTerminalSeen` conserva memoria storica. Se diventa `true`, lo stato non deve mai tornare a
`Created` o `Funded`; ogni stato terminale deve inoltre avere amount zero.

## Capability escluse

Questo modello non rappresenta token malevoli, admin compromessi o oracle. Questi threat model
richiedono suite separate: aggiungerli qui cambierebbe le precondizioni degli invarianti.

