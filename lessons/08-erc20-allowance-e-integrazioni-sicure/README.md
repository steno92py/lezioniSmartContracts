# Lezione 8 — ERC-20, allowance e integrazioni sicure

Questa lezione tratta un ERC-20 per ciò che è realmente: **un altro smart contract**. Il protocollo
non riceve oggetti nativi, ma chiede a una dipendenza esterna di aggiornare il proprio storage.

> Token e account sono giocattoli locali. Non usare asset, approval o chiavi reali.

Il testo teorico completo resta in
[`../../lezioni SmartContracts/Lezione_08_ERC20_allowance_e_integrazioni_sicure.md`](../../lezioni%20SmartContracts/Lezione_08_ERC20_allowance_e_integrazioni_sicure.md).

## Prima esecuzione

Dalla directory della lezione:

```bash
forge build
forge test -vv
```

Dalla radice:

```bash
forge build --root lessons/08-erc20-allowance-e-integrazioni-sicure
forge test --root lessons/08-erc20-allowance-e-integrazioni-sicure -vv
```

Il warning sul return value ignorato è intenzionale e appartiene esclusivamente al vault
vulnerabile.

## Mappa dei file

```text
src/token/IERC20.sol              interfaccia minimale
src/token/SafeERC20Lite.sol       wrapper per bool false e return data opzionale
src/VulnerableTokenVault.sol      accounting aggiornato anche quando il token fallisce
src/TokenEscrow.sol               balance delta, state machine e CEI
test/mocks/                       cinque comportamenti token controllati
test/                             allowance, integrazione e regressioni
script/DeployTokenEscrow.s.sol    deploy locale di token ed Escrow
exercises/                        attività graduate e policy design
```

`SafeERC20Lite` è intenzionalmente piccolo per rendere visibile il meccanismo. Non sostituisce
OpenZeppelin in produzione: una codebase reale deve installare e pin­nare la versione scelta di
`SafeERC20`, revisionandone API e supply chain.

## Tre numeri diversi

```text
balanceOf(buyer)                 proprietà contabile nel token
allowance(buyer, escrow)         autorizzazione persistente nel token
escrowedAmount                   passività registrata nell'Escrow
```

`approve` modifica soltanto il secondo numero. Il trasferimento avviene quando l'Escrow, come
spender, chiama `transferFrom`.

## Laboratorio 1 — return value ignorato

```bash
forge test --match-test test_Vulnerable_FalseReturnCreatesUnbackedCredit -vvvv
```

Il test passa dimostrando il bug:

```text
transferFrom ritorna false
asset ricevuti: 0
credito interno: 100
```

Il wrapper corretto considera `false` un fallimento e accetta invece l'assenza di return data solo
quando la call termina con successo.

## Laboratorio 2 — quantità nominale e quantità ricevuta

```bash
forge test --match-test test_FeeTokenAccountsForActualAmountReceived -vvvv
```

Con una fee del 10%:

```text
requestedAmount: 100
receivedAmount:   90
escrowedAmount:   90
```

La policy scelta dal laboratorio supporta la fee in ingresso registrando il balance delta. Anche il
payout è tassato dal token: su 90 addebitati, il seller riceve 81. È una scelta semantica esplicita,
non una garanzia universale di `SafeERC20`.

## Laboratorio 3 — atomicità del payout

```bash
forge test --match-test test_FailedPayoutRollsBackEffectsAndState -vvvv
```

L'Escrow applica CEI prima della chiamata al token. Se il token segnala fallimento, il revert annulla
anche gli effetti precedenti: lo stato resta `Funded`, la passività resta registrata e gli asset non
si muovono.

## Proprietà di solvibilità

Nel modello a posizione singola:

```text
state == Funded
=> token.balanceOf(escrow) >= escrowedAmount
```

Misurare `beforeBalance` e `afterBalance` protegge l'accounting nominale dai token con fee in
ingresso. Non rende automaticamente compatibili rebasing, blacklist, pause o implementazioni
upgradeabili: queste classi devono entrare nella policy degli asset supportati.

## Tre percorsi

### Base — allowance

1. Segui owner, spender e recipient in ogni chiamata.
2. Distingui saldo disponibile e autorizzazione disponibile.
3. Verifica allowance esatta e residua.

### Intermedio — token anomali

1. Confronta `false`, revert e nessun return value.
2. Misura il saldo realmente ricevuto.
3. Verifica che un fallimento esterno non lasci effetti interni.

### Avanzato — policy economica

1. Definisci quali token il protocollo dichiara di supportare.
2. Separa quantità lorda, quantità ricevuta e quantità netta al beneficiario.
3. Analizza allowance persistenti, rebase e target controllabili dall'utente.

## Deploy facoltativo su Anvil

```bash
forge script script/DeployTokenEscrow.s.sol:DeployTokenEscrow \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <CHIAVE_DI_TEST_ANVIL> \
  --broadcast
```

## Criterio di completamento

- sai spiegare `approve`, `allowance` e `transferFrom` indicando il caller di ogni hop;
- sai distinguere business authorization e autorizzazione ERC-20;
- sai riprodurre il bug del return value ignorato;
- sai spiegare perché safe transfer non implica `requested == received`;
- sai verificare la solvibilità rispetto al saldo reale;
- sai formulare una policy esplicita per i token supportati.

