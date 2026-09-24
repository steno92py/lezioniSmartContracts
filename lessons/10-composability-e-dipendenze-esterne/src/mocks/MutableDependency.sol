// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IValueProvider } from "../interfaces/IValueProvider.sol";

// Provider il cui comportamento cambia nel tempo senza cambiare indirizzo: prima risponde
// bene, poi puo' revertire o restituire valori estremi. Il consumer deve reggere tutti i casi.
contract MutableDependency is IValueProvider {
    // `enum`: un tipo con un insieme chiuso di valori; il default e' il primo (Normal).
    enum Mode {
        Normal,
        RevertAlways,
        ReturnZero,
        ReturnMaximum
    }

    error Disabled();

    Mode public mode;

    // Nessun controllo d'accesso: e' un mock, i test devono poterlo guastare liberamente.
    function setMode(Mode newMode) external {
        mode = newMode;
    }

    function value() external view returns (uint256) {
        if (mode == Mode.RevertAlways) revert Disabled();
        if (mode == Mode.ReturnZero) return 0;
        // type(uint256).max: il piu' grande uint256 possibile, 2**256 - 1.
        if (mode == Mode.ReturnMaximum) return type(uint256).max;
        return 100;
    }
}
