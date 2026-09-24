// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto vulnerabile: confonde l'invio della call con il suo successo.
contract UncheckedDependency {
    bool public completed;

    /// @dev `target.call(data)` e' una low-level call: invia i byte `data` cosi' come sono e
    /// restituisce (bool success, bytes returndata). A differenza di una call via interfaccia,
    /// NON reverte da sola se il target fallisce: e' il chiamante che deve guardare `success`.
    function run(address target, bytes calldata data) external {
        // BUG intenzionale: success e returndata vengono ignorati.
        // Due casi di falso successo:
        //   1. il target reverte   -> success = false, ma nessuno lo legge;
        //   2. il target e' un EOA -> success = true anche se non e' stato eseguito nulla,
        //      perche' una call verso un indirizzo senza codice "riesce" sempre.
        target.call(data);
        // Qui si arriva in entrambi i casi: lo stato dichiara un'operazione mai avvenuta.
        // La correzione e' in CheckedDependency (code check + controllo di success).
        completed = true;
    }
}
