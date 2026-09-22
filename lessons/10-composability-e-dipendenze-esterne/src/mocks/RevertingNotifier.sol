// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { INotifier } from "../interfaces/INotifier.sol";

contract RevertingNotifier is INotifier {
    error Nope();

    function notifyReleased(address, uint256) external pure {
        revert Nope();
    }
}

