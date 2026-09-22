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
        if (address(swapper_).code.length == 0) revert InvalidSwapper(address(swapper_));
        swapper = swapper_;
    }

    function execute(uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        external
        view
        returns (uint256)
    {
        if (amountIn == 0) revert ZeroAmountIn();
        if (amountOutMin == 0) revert ZeroMinimumOutput();
        if (block.timestamp > deadline) revert Expired(deadline, block.timestamp);

        return swapper.swap(amountIn, amountOutMin);
    }
}

