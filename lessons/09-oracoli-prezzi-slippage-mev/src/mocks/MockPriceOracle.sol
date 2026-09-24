// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IPriceOracle } from "../oracle/IPriceOracle.sol";

/// @notice Feed completamente controllabile per test locali.
/// @dev `is IPriceOracle`: il contratto deve implementare tutte le funzioni dell'interfaccia.
contract MockPriceOracle is IPriceOracle {
    // `immutable`: fissato una volta nel constructor e poi scritto nel bytecode.
    // Una variabile `public` genera un getter decimals(): e' lui che implementa la funzione
    // dell'interfaccia, per questo serve `override`.
    uint8 public immutable override decimals;
    int256 public answer;
    uint256 public updatedAt;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    // Nessun controllo di accesso ne' di validita', di proposito: nei test si puo' simulare
    // qualunque feed, anche guasto (prezzo zero, negativo, vecchio o nel futuro).
    // Un oracle reale non deve MAI essere scrivibile da chiunque.
    function setPrice(int256 newAnswer, uint256 newUpdatedAt) external {
        answer = newAnswer;
        updatedAt = newUpdatedAt;
    }

    function latestPrice() external view returns (int256, uint256) {
        return (answer, updatedAt);
    }
}
