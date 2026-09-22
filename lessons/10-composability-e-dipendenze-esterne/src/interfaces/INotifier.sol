// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface INotifier {
    function notifyReleased(address seller, uint256 amount) external;
}

