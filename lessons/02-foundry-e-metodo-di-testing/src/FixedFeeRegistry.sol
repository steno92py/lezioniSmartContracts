// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title Registro didattico con fee fissa
/// @notice Ogni indirizzo puo' registrarsi una volta pagando esattamente 1 ether.
/// @dev Il contratto non include prelievi: le chiamate esterne arriveranno nelle lezioni successive.
contract FixedFeeRegistry {
    uint256 public constant REGISTRATION_FEE = 1 ether;

    mapping(address account => bool isRegistered) public registered;

    uint256 public registrationCount;
    uint256 public totalReceived;

    error ExactFeeRequired(uint256 sent, uint256 required);
    error AlreadyRegistered(address account);

    event Registered(address indexed account, uint256 amount);

    function register() external payable {
        if (registered[msg.sender]) {
            revert AlreadyRegistered(msg.sender);
        }

        if (msg.value != REGISTRATION_FEE) {
            revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
        }

        registered[msg.sender] = true;
        registrationCount += 1;
        totalReceived += msg.value;

        emit Registered(msg.sender, msg.value);
    }
}

