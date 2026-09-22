// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IValueProvider } from "../interfaces/IValueProvider.sol";

contract MutableDependency is IValueProvider {
    enum Mode {
        Normal,
        RevertAlways,
        ReturnZero,
        ReturnMaximum
    }

    error Disabled();

    Mode public mode;

    function setMode(Mode newMode) external {
        mode = newMode;
    }

    function value() external view returns (uint256) {
        if (mode == Mode.RevertAlways) revert Disabled();
        if (mode == Mode.ReturnZero) return 0;
        if (mode == Mode.ReturnMaximum) return type(uint256).max;
        return 100;
    }
}

