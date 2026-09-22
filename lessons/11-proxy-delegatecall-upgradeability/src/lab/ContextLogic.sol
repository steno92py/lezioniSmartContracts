// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract ContextLogic {
    address public lastCaller;
    address public lastContext;

    function recordContext() external {
        lastCaller = msg.sender;
        lastContext = address(this);
    }
}

