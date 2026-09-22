// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IPriceOracle } from "./oracle/IPriceOracle.sol";

/// @notice Consumer intenzionalmente vulnerabile: ignora timestamp, unita' e scaling.
contract VulnerableValuation {
    IPriceOracle public immutable oracle;

    constructor(IPriceOracle oracle_) {
        oracle = oracle_;
    }

    function valueOf(uint256 amount) external view returns (uint256) {
        (int256 answer,) = oracle.latestPrice();
        return amount * uint256(answer);
    }
}

