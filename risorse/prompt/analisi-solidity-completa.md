# Prompt Helper per Analizzare Funzioni Solidity

Analizza la seguente funzione Solidity come se stessi insegnandola a una persona che sta imparando Smart Contract Security.

Non partire subito dalle vulnerabilità. Segui questo ordine:

## 1. Scopo della funzione
- Spiega in linguaggio semplice cosa cerca di fare.
- Indica quale requisito di business sembra implementare.

## 2. Caller
- Chi può chiamarla?
- Ci sono modifier o controlli su `msg.sender`?
- Se chiunque può chiamarla, è intenzionale?

## 3. Input controllati
- Quali parametri controlla il caller?
- Il caller controlla anche address di token, router, oracle o altri contratti?
- Può inviare Ether tramite `msg.value`?

## 4. Stato
- Quali variabili di storage vengono lette?
- Quali vengono modificate?
- Descrivi lo stato prima e dopo la funzione.

## 5. External calls
- La funzione chiama altri contratti?
- Quali?
- In quale punto il controllo passa a codice esterno?
- Il target della call è trusted, configurabile o controllabile dall'utente?
- Il valore di ritorno viene controllato?
- Un revert esterno viene propagato o ignorato?

## 6. Ordine delle operazioni
Identifica:
- Checks
- Effects
- Interactions

Spiega se l'ordine è coerente con il pattern CEI.

Segnala se una external call avviene mentre esiste ancora stato sensibile non aggiornato.

## 7. Assunzioni implicite
Elenca le assunzioni che il codice sta facendo, per esempio:
- il token trasferisce esattamente `amount`;
- l'oracle è fresco;
- un address contiene il contratto atteso;
- una chiamata che non reverte è economicamente corretta;
- un ruolo privilegiato è affidabile.

## 8. Proprietà di sicurezza
Trasforma la logica in frasi verificabili, ad esempio:
- un utente non può ritirare più del proprio credito;
- solo il buyer può eseguire la release;
- se la funzione termina con successo, il pagamento deve essere realmente avvenuto;
- dopo uno stato terminale non devono esistere altre transizioni.

## 9. Failure cases
Analizza almeno:
- input zero;
- input massimo / range boundary;
- caller non autorizzato;
- stato sbagliato;
- external call che reverte;
- external call che restituisce un valore inatteso;
- callback / reentrancy, se pertinente.

## 10. Possibili vulnerabilità o code smell
Solo dopo avere completato i punti precedenti, indica eventuali problemi.

Per ogni problema specifica:
- root cause;
- proprietà violata;
- precondizioni;
- possibile impatto;
- se è un problema certo oppure solo una domanda da approfondire.

## 11. Test Foundry
Proponi:
- 1 happy-path test;
- almeno 2 negative test;
- eventuale regression test;
- una property adatta a fuzz testing;
- un possibile invariant, se pertinente.

## 12. Spiegazione didattica
Se compaiono concetti come `storage`, `calldata`, `delegatecall`, `allowance`, `reentrancy`, `oracle` o `invariant`, spiegali brevemente:
- perché esistono;
- come funzionano;
- perché sono importanti per la sicurezza.

Non inventare vulnerabilità se il codice non fornisce abbastanza informazioni. In quel caso indica chiaramente quali informazioni mancano.

## Codice da analizzare

```solidity
INCOLLA QUI LA FUNZIONE O IL CONTRATTO
```
