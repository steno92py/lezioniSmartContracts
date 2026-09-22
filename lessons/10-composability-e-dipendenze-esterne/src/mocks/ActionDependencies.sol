// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract GoodDependency {
    bool public executed;

    function execute() external returns (uint256 result) {
        executed = true;
        return 42;
    }
}

contract RevertingDependency {
    error DependencyFailure();

    function execute() external pure {
        revert DependencyFailure();
    }
}

