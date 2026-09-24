// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// amountOutMin e' un'istruzione per il router, non una garanzia: un router scorretto puo'
// ignorarlo e restituire meno. Per questo BoundedIntegrator ricontrolla l'output.
interface IRouter {
    function swap(uint256 amountIn, uint256 amountOutMin) external returns (uint256 amountOut);
}
