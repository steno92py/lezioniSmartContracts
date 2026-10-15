# Threat model

## Obiettivi dell'avversario

- ricevere più token della liability;
- creare una liability superiore agli asset;
- forzare un settlement prima che la condizione economica sia valida;
- bloccare release o refund;
- riportare il lifecycle a uno stato precedente;
- acquisire capability riservate a governance.

## Avversari considerati

- caller senza privilegi;
- buyer o seller malevolo;
- guardian compromesso, ma governance onesta;
- token con fee o callback;
- oracle mal configurato o sostituito;
- notifier che reverte.

## Trust assumptions da verificare, non da intuire

- Il guardian è meno fidato di governance e ha potere soltanto difensivo.
- Token, oracle e notifier sono chiamate esterne e possono eseguire codice arbitrario.
- Il caller di `release` non è fidato.
- La precisione dell'oracle è fissata a 8 decimali dalla specifica; il contratto non la scopre.
- L'atomicità EVM ripristina anche lo stato del token se `deposit` reverte.

## Rischi prioritari

| Categoria | Scenario | Proprietà coinvolta |
| --- | --- | --- |
| accounting | requested diverso da received | I-03, I-04 |
| reentrancy | callback durante payout riusa liability | I-02, I-05 |
| governance | guardian sostituisce oracle | I-09, I-10 |
| oracle | timestamp al confine accettato | I-07 |
| liveness | notifier opzionale reverte | I-12 |

## Vincoli del modello

Non vengono simulati MEV, manipolazione del provider reale, compromissione di governance o token
rebasing. Questi rischi non sono dichiarati assenti: sono fuori dallo scope registrato.
