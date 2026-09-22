// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { MulDivLite } from "../math/MulDivLite.sol";
import { ISwap } from "../swap/ISwap.sol";

/// @notice Simulatore privo di riserve e token: modella soltanto rate e minOut.
contract MockSwap is ISwap {
    error SlippageExceeded(uint256 minimum, uint256 actual);

    uint256 public rateE18 = 2e18;

    function setRate(uint256 newRateE18) external {
        rateE18 = newRateE18;
    }

    function quote(uint256 amountIn) public view returns (uint256) {
        return MulDivLite.mulDiv(amountIn, rateE18, 1e18);
    }

    function swap(uint256 amountIn, uint256 amountOutMin)
        external
        view
        returns (uint256 amountOut)
    {
        amountOut = quote(amountIn);
        if (amountOut < amountOutMin) revert SlippageExceeded(amountOutMin, amountOut);
    }
}

