// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IAuditToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPriceOracle {
    function latestPrice() external view returns (int256 price, uint256 updatedAt);
}

interface ISettlementNotifier {
    function notify(address buyer, address seller, uint256 amount) external;
}

