// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Dipendenza che funziona: lascia una traccia (`executed`) e restituisce 42, cosi' i test
// possono verificare sia l'esecuzione sia il return value decodificato.
contract GoodDependency {
    bool public executed;

    function execute() external returns (uint256 result) {
        executed = true;
        return 42;
    }
}

// Dipendenza che fallisce sempre con un errore riconoscibile.
contract RevertingDependency {
    error DependencyFailure();

    function execute() external pure {
        revert DependencyFailure();
    }
}
