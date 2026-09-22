// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Modello minimale che mostra come flag indipendenti rendano rappresentabili stati assurdi.
/// @dev Le funzioni sono volutamente prive di guardie: il focus e' il modello dati, non l'accesso.
contract BooleanStateTrap {
    bool public funded;
    bool public completed;
    bool public cancelled;

    function markFunded() external {
        funded = true;
    }

    function markCompleted() external {
        completed = true;
    }

    function markCancelled() external {
        cancelled = true;
    }
}

