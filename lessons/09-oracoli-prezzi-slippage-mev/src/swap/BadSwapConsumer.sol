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
        return swapper.swap(amountIn, 0);
    }
}

