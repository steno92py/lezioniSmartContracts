// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Versione minimale corretta con un singolo ruolo amministrativo.
contract EscrowAdmin {
    error ZeroAddress();
    error Unauthorized(address caller);

    address public immutable buyer;
    address public immutable seller;
    address public admin;

    bool public paused;

    event PauseChanged(bool paused, address indexed admin);

    constructor(address buyer_, address seller_, address admin_) {
        if (buyer_ == address(0) || seller_ == address(0) || admin_ == address(0)) {
            revert ZeroAddress();
        }

        buyer = buyer_;
        seller = seller_;
        admin = admin_;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized(msg.sender);
        _;
    }

    function setPaused(bool value) external onlyAdmin {
        paused = value;
        emit PauseChanged(value, msg.sender);
    }
}

