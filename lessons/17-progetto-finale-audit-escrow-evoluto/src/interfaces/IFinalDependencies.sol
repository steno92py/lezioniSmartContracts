// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IERC20Final {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPriceOracleFinal {
    function latestPrice() external view returns (int256 answer, uint256 updatedAt);
}

interface INotifierFinal {
    function notifyReleased(address seller, uint256 amount) external;
}

