// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IRouter } from "../interfaces/IRouter.sol";

contract GoodRouter is IRouter {
    uint256 public output = 1_000;

    function setOutput(uint256 newOutput) external {
        output = newOutput;
    }

    function swap(uint256, uint256) external view returns (uint256) {
        return output;
    }
}

contract WeirdRouter is IRouter {
    function swap(uint256, uint256) external pure returns (uint256) {
        return 1;
    }
}

contract RevertingRouter is IRouter {
    error RouterUnavailable();

    function swap(uint256, uint256) external pure returns (uint256) {
        revert RouterUnavailable();
    }
}

