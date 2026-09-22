// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto vulnerabile: confonde l'invio della call con il suo successo.
contract UncheckedDependency {
    bool public completed;

    function run(address target, bytes calldata data) external {
        // BUG intenzionale: success e returndata vengono ignorati.
        target.call(data);
        completed = true;
    }
}

