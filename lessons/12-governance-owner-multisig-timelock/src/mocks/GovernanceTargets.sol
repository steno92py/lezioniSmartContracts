// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract CallTarget {
    error ForcedFailure();

    uint256 public value;

    function setValue(uint256 newValue) external returns (uint256) {
        value = newValue;
        return newValue;
    }

    function fail() external pure {
        revert ForcedFailure();
    }
}

contract MockOracle { }

