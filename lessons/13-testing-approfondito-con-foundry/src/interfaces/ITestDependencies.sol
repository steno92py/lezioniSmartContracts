// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface ITestToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ITestOracle {
    function latestPrice() external view returns (int256 price, uint256 updatedAt);
}

