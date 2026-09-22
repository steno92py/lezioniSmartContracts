# Lezione 6 — Access control

Questa lezione trasforma la domanda generica “c'è un `onlyOwner`?” in una verifica più precisa:
**chi può fare cosa, su quale risorsa, in quale stato e chi può assegnare quel privilegio?**

> Tutti i contratti vulnerabili e le identità sono giocattoli locali. Non usare chiavi o sistemi
> reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_06_Access_Control.md`](../../lezioni%20SmartContracts/Lezione_06_Access_Control.md).

## Permission matrix del laboratorio

| Operazione | Admin | Pauser | Arbiter | Buyer/Seller | Stranger |
| --- | ---: | ---: | ---: | ---: | ---: |
| `EscrowAdmin.setPaused` | sì | no | no | no | no |
| `EscrowRoles.setPaused` | no, salvo grant | sì | no | no | no |
| `EscrowRoles.resolveDispute` | no, salvo grant | no | sì | no | no |
| `grantRole` / `revokeRole` | sì | no | no | no | no |

Separare amministrazione dei ruoli e operazioni quotidiane applica il least privilege: l'admin può
assegnare il ruolo, ma non eredita implicitamente il potere operativo.

Nei test, salva i role ID in variabili prima di `vm.prank`: un getter come `PAUSER_ROLE()` è esso
stesso una external call e consumerebbe il prank one-shot destinato all'operazione successiva.

## Prima esecuzione

Dalla directory della lezione:

```bash
forge build
forge test -vv
```

Dalla radice:

```bash
forge build --root lessons/06-access-control
forge test --root lessons/06-access-control -vv
```

Il warning `tx-origin` è intenzionale e appartiene soltanto al contratto vulnerabile del micro-lab.

## Mappa dei file

```text
src/access/EscrowAdminVulnerable.sol   ruolo dichiarato ma mai applicato
src/access/EscrowAdmin.sol             controllo minimale su msg.sender
src/access/TxOriginVault.sol           tx.origin vulnerabile + versione diretta
src/access/Ownable2StepLite.sol        ownership a proposta e accettazione
src/access/EscrowRoles.sol             RBAC e amministrazione dei ruoli
test/                                  test positivi, negativi e regressioni
script/DeployEscrowAdmin.s.sol         deploy locale della versione minimale corretta
exercises/                              attività graduate
```

`Ownable2StepLite` e `EscrowRoles` sono implementazioni didattiche minimali per rendere visibile il
meccanismo senza scaricare dipendenze. Non sostituiscono OpenZeppelin in produzione: una codebase
reale deve pin­nare la versione scelta e revisionarne API, ruoli amministrativi e supply chain.

## Laboratorio missing access control

```bash
forge test --match-test test_Vulnerable_StrangerCanPause -vvvv
```

Il test passa dimostrando il bug: memorizzare `admin` non protegge `setPaused()` se la funzione non
verifica `msg.sender`.

Il regression test della versione corretta è:

```bash
forge test --match-test test_RevertWhen_StrangerTriesToPause -vvvv
```

## Micro-lab `tx.origin`

```bash
forge test --match-contract TxOriginVaultTest -vvvv
```

Con la catena `owner → Forwarder → vault`, nel target `tx.origin == owner` ma
`msg.sender == Forwarder`. La versione vulnerabile accetta la call indiretta; quella corretta la
rifiuta perché la policy richiede il caller immediato.

## Ownership a due fasi

```text
owner --transferOwnership(candidate)--> pendingOwner
candidate --acceptOwnership()---------> owner
```

Il vecchio owner conserva i privilegi finché il candidato non accetta. Dopo l'accettazione perde
immediatamente l'accesso e `pendingOwner` viene azzerato.

## Tre percorsi

### Base — authorized vs unauthorized

1. Per ogni privilegio esegui almeno un test positivo e uno negativo.
2. Verifica anche lo stato dopo il revert.
3. Distingui visibility e authorization.

### Intermedio — ownership e least privilege

1. Segui proposta e accettazione dell'ownership.
2. Confronta admin del ruolo e possessore del ruolo.
3. Verifica che pauser e arbiter non possano sostituirsi a vicenda.

### Avanzato — permission graph

1. Cerca tutti i write path verso una variabile sensibile.
2. Analizza chi può concedere e revocare ogni ruolo.
3. Misura il blast radius di ciascuna credenziale compromessa.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployEscrowAdmin.s.sol:DeployEscrowAdmin \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai distinguere authentication, authorization e business-state authorization;
- sai spiegare perché `tx.origin` non autentica il caller immediato;
- sai costruire una permission matrix e un permission graph;
- sai testare sia successo autorizzato sia fallimento non autorizzato;
- sai spiegare il vantaggio del trasferimento a due fasi;
- sai distinguere possesso e amministrazione di un ruolo.
