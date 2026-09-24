// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { CallUtilsLite } from "./utils/CallUtilsLite.sol";

/// @notice Verifica il successo tecnico della call prima di registrare il completamento.
contract CheckedDependency {
    // `using L for T`: le funzioni della libreria L si chiamano come metodi di un valore T.
    // Qui `target.functionCall(data)` equivale a `CallUtilsLite.functionCall(target, data)`.
    using CallUtilsLite for address;

    error AlreadyCompleted();

    bool public completed;

    function run(address target, bytes calldata data) external returns (bytes memory result) {
        // L'azione si puo' registrare una sola volta.
        if (completed) revert AlreadyCompleted();
        // functionCall reverte se il target non ha codice o se la call fallisce, e in quel
        // caso l'intera transazione viene annullata: `completed` non viene mai scritto.
        result = target.functionCall(data);
        // Si arriva qui SOLO dopo un successo tecnico. Successo tecnico non vuol dire che il
        // risultato abbia senso: quello va validato a parte (vedi BoundedIntegrator).
        completed = true;
    }
}
