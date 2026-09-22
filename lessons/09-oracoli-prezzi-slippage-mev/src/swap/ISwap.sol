// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface ISwap {
    function swap(uint256 amountIn, uint256 amountOutMin) external view returns (uint256 amountOut);
}

