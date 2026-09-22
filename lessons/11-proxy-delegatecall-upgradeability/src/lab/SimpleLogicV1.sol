// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract SimpleLogicV1 {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

