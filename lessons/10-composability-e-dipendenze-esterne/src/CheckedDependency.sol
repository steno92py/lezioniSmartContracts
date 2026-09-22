// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { CallUtilsLite } from "./utils/CallUtilsLite.sol";

/// @notice Verifica il successo tecnico della call prima di registrare il completamento.
contract CheckedDependency {
    using CallUtilsLite for address;

    error AlreadyCompleted();

    bool public completed;

    function run(address target, bytes calldata data) external returns (bytes memory result) {
        if (completed) revert AlreadyCompleted();
        result = target.functionCall(data);
        completed = true;
    }
}

