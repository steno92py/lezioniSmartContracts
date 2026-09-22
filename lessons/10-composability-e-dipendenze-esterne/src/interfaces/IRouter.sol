// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IRouter {
    function swap(uint256 amountIn, uint256 amountOutMin) external returns (uint256 amountOut);
}

