// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Target generico per il multisig: setValue lascia una traccia e restituisce un valore,
// fail() permette di provare cosa succede quando la call eseguita fallisce.
contract CallTarget {
    error ForcedFailure();

    uint256 public value;

    function setValue(uint256 newValue) external returns (uint256) {
        value = newValue;
        return newValue;
    }

    function fail() external pure {
        revert ForcedFailure();
    }
}

// Contratto vuoto: serve solo un indirizzo con codice da impostare come oracle.
contract MockOracle { }
