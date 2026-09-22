// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IPriceOracle {
    function decimals() external view returns (uint8);
    function latestPrice() external view returns (int256 answer, uint256 updatedAt);
}

