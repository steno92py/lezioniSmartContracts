// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { ISwap } from "./ISwap.sol";

/// @notice Consumer vulnerabile che dichiara accettabile qualunque output, incluso zero.
contract BadSwapConsumer {
    ISwap public immutable swapper;

    constructor(ISwap swapper_) {
        swapper = swapper_;
    }

    function execute(uint256 amountIn) external view returns (uint256) {
        // Vulnerabilita': amountOutMin = 0. Il controllo `amountOut < 0` dello swapper non
        // scatta mai, quindi qualunque prezzo viene accettato. Se il rate peggiora prima
        // dell'esecuzione (mercato o transazioni ordinate davanti alla nostra), l'utente
        // riceve quasi nulla. Correzione: SafeSwapIntent, con minOut e deadline espliciti.
        return swapper.swap(amountIn, 0);
    }
}
