// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { DidacticReentrancyGuard } from "../utils/DidacticReentrancyGuard.sol";

/// @notice Vault didattico protetto sia da CEI sia da un mutex esplicito.
contract SafeVaultGuarded is DidacticReentrancyGuard {
    mapping(address user => uint256 amount) public credit;
    uint256 public totalCredits;

    error ZeroDeposit();
    error NoCredit();
    error TransferFailed();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        credit[msg.sender] += msg.value;
        totalCredits += msg.value;
    }

    function withdraw() external nonReentrant {
        // Manteniamo CEI: il guard non sostituisce la coerenza dell'accounting.
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        credit[msg.sender] = 0;
        totalCredits -= amount;

        (bool ok,) = msg.sender.call{ value: amount }("");
        if (!ok) revert TransferFailed();
    }
}

