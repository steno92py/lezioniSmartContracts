// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IRouter } from "./interfaces/IRouter.sol";

/// @notice Verifica nel consumer una proprietà economica anche se il router dovrebbe rispettarla.
contract BoundedIntegrator {
    error InvalidRouter(address router);
    error ZeroMinimumOutput();
    error InsufficientOutput(uint256 minimum, uint256 actual);

    IRouter public immutable router;
    uint256 public lastOutput;

    constructor(IRouter router_) {
        if (address(router_).code.length == 0) revert InvalidRouter(address(router_));
        router = router_;
    }

    function execute(uint256 amountIn, uint256 minimumOutput) external returns (uint256 output) {
        if (minimumOutput == 0) revert ZeroMinimumOutput();

        output = router.swap(amountIn, minimumOutput);
        if (output < minimumOutput) revert InsufficientOutput(minimumOutput, output);

        lastOutput = output;
    }
}

