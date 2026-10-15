// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// amountOutMin e' la protezione dallo slippage: il peggior output che il chiamante accetta.
// Se l'output effettivo e' piu' basso, lo swap deve revertire.
interface ISwap {
    function swap(uint256 amountIn, uint256 amountOutMin) external view returns (uint256 amountOut);
}
