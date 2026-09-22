// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Mutante volutamente errato: accetta qualsiasi importo maggiore o uguale alla fee.
/// @dev Esiste soltanto per mostrare se il regression test distingue `==` da `>=`.
contract MinimumFeeRegistry {
    uint256 public constant REGISTRATION_FEE = 1 ether;

    mapping(address account => bool isRegistered) public registered;
    uint256 public registrationCount;
    uint256 public totalReceived;

    error ExactFeeRequired(uint256 sent, uint256 required);
    error AlreadyRegistered(address account);

    function register() external payable {
        if (registered[msg.sender]) revert AlreadyRegistered(msg.sender);

        // MUTAZIONE: il requisito richiede `!=`, non `<`.
        if (msg.value < REGISTRATION_FEE) {
            revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
        }

        registered[msg.sender] = true;
        registrationCount += 1;
        totalReceived += msg.value;
    }
}

