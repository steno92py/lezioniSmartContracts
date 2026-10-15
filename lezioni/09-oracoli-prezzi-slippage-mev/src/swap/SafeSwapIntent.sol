// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { ISwap } from "./ISwap.sol";

/// @notice Intento di swap locale con condizioni economiche e temporali esplicite.
contract SafeSwapIntent {
    error InvalidSwapper(address swapper);
    error ZeroAmountIn();
    error ZeroMinimumOutput();
    error Expired(uint256 deadline, uint256 currentTimestamp);

    ISwap public immutable swapper;

    constructor(ISwap swapper_) {
        // Stesso controllo di PriceConsumer: all'indirizzo deve esserci un contratto.
        if (address(swapper_).code.length == 0) revert InvalidSwapper(address(swapper_));
        swapper = swapper_;
    }

    // Due limiti indipendenti, e servono entrambi:
    //   amountOutMin  il peggior risultato ECONOMICO accettato;
    //   deadline      fino a QUANDO l'intento resta valido.
    function execute(uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        external
        view
        returns (uint256)
    {
        if (amountIn == 0) revert ZeroAmountIn();
        // Rifiutare minOut = 0 chiude proprio il bug di BadSwapConsumer.
        if (amountOutMin == 0) revert ZeroMinimumOutput();
        // `>`: allo scadere esatto (block.timestamp == deadline) l'intento e' ancora valido.
        // Senza deadline una transazione rimasta in attesa potrebbe essere eseguita molto
        // piu' tardi, in un mercato diverso da quello su cui l'utente aveva deciso.
        if (block.timestamp > deadline) revert Expired(deadline, block.timestamp);

        // Il controllo sull'output minimo lo fa lo swapper, che reverte sotto amountOutMin.
        return swapper.swap(amountIn, amountOutMin);
    }
}
