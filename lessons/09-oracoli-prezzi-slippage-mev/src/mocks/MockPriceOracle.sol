// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IPriceOracle } from "../oracle/IPriceOracle.sol";

/// @notice Feed completamente controllabile per test locali.
contract MockPriceOracle is IPriceOracle {
    uint8 public immutable override decimals;
    int256 public answer;
    uint256 public updatedAt;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setPrice(int256 newAnswer, uint256 newUpdatedAt) external {
        answer = newAnswer;
        updatedAt = newUpdatedAt;
    }

    function latestPrice() external view returns (int256, uint256) {
        return (answer, updatedAt);
    }
}

