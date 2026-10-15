// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Modello minimale che mostra come flag indipendenti rendano rappresentabili stati assurdi.
/// @dev Le funzioni sono volutamente prive di guardie: il focus e' il modello dati, non l'accesso.
contract BooleanStateTrap {
    // Tre bool indipendenti = 2 x 2 x 2 = 8 combinazioni possibili, ma solo poche hanno
    // senso. Nulla nel TIPO impedisce completed = true e cancelled = true insieme.
    // Con un solo `State state` (enum) Completed e Cancelled si escludono per costruzione:
    // la variabile puo' contenere un valore alla volta.
    bool public funded;
    bool public completed;
    bool public cancelled;

    // Ogni setter tocca un solo flag e ignora gli altri due: la coerenza tra i flag
    // dovrebbe essere garantita a mano, in ogni funzione.
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
