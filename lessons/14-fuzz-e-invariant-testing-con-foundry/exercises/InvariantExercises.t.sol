// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Traccia esclusa dalla suite: copiala sotto test/invariant e aggiungi gli import.

// TODO 1: implementa balance(vault) == totalCredit per la policy exact-transfer senza donation.

// TODO 2: verifica ghostDeposited >= ghostWithdrawn prima della sottrazione.

// TODO 3: confronta ghostDeposited - ghostWithdrawn con totalCredit.

// TODO 4: somma credit[Alice], credit[Bob] e credit[Carol].

// TODO 5: limita targetContract all'handler e dichiara esplicitamente i target selector.

// TODO 6: aggiungi un'azione withdraw(available + extra) e verifica il rollback.

// TODO 7: usa una ghost variable per ricordare se uno stato terminale è già stato raggiunto.

