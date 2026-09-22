// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Questa e' una traccia: Foundry non la esegue perche' si trova fuori da test/.
// Copiala in test/EscrowLesson1Exercises.t.sol, importa Test ed EscrowLesson1,
// quindi trasforma ogni TODO in un test test_* indipendente.

// TODO 1: due payer depositano 1 e 2 ether per lo stesso beneficiary.
// Verifica nextId, credited, totalRecorded e l'identita' dei due payer.

// TODO 2: deposita per due beneficiary diversi.
// Verifica che aggiornare una chiave del mapping non alteri l'altra.

// TODO 3: prova note di 256 e 257 byte.
// Verifica sia il successo al confine sia errore e argomento del revert oltre il confine.

// TODO 4: crea due depositi validi, poi prova un terzo deposito invalido.
// Verifica che contatori, credito, saldo e depositi precedenti siano invariati.

// TODO 5: osserva con forge test -vvvv msg.sender e tx.origin nei due call frame.

