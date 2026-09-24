// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { CallUtilsLite } from "./utils/CallUtilsLite.sol";

// Separazione dei ruoli:
//   admin    decide QUALI target sono fidati  (setTargetAllowed)
//   operator decide QUANDO e con quali dati chiamarli (execute)
// L'operator non puo' puntare a codice arbitrario, ma ora il punto di fiducia e' l'admin:
// l'allowlist non elimina la trust boundary, la sposta.

/// @notice Target runtime limitati da una allowlist amministrata esplicitamente.
contract AllowlistedExecutor {
    using CallUtilsLite for address;

    error ZeroAddress();
    error Unauthorized(address caller);
    error TargetNotAllowed(address target);

    event TargetPermissionChanged(address indexed target, bool allowed);
    event DependencyExecuted(address indexed target, uint256 indexed sequence);

    address public immutable admin;
    address public immutable operator;
    mapping(address target => bool allowed) public allowedTarget;
    uint256 public completedCalls;

    constructor(address admin_, address operator_) {
        if (admin_ == address(0) || operator_ == address(0)) revert ZeroAddress();
        admin = admin_;
        operator = operator_;
    }

    function setTargetAllowed(address target, bool allowed) external {
        if (msg.sender != admin) revert Unauthorized(msg.sender);
        // Solo quando si AGGIUNGE un target si pretende che abbia codice; la revoca
        // (allowed = false) deve restare sempre possibile.
        if (allowed && target.code.length == 0) revert CallUtilsLite.TargetHasNoCode(target);

        allowedTarget[target] = allowed;
        // Ogni cambio di fiducia lascia una traccia pubblica, verificabile da fuori.
        emit TargetPermissionChanged(target, allowed);
    }

    function execute(address target, bytes calldata data) external returns (bytes memory result) {
        if (msg.sender != operator) revert Unauthorized(msg.sender);
        if (!allowedTarget[target]) revert TargetNotAllowed(target);

        // Call verificata: se il target reverte, l'errore risale e il contatore sotto non
        // viene incrementato.
        result = target.functionCall(data);
        completedCalls += 1;
        emit DependencyExecuted(target, completedCalls);
    }
}
