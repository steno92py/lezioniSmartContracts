// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Vault corretto riordinando stato e interazione secondo CEI.
contract SafeVaultCEI {
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

    function withdraw() external {
        // CHECKS
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        // EFFECTS: il diritto viene consumato prima della trust boundary.
        credit[msg.sender] = 0;
        totalCredits -= amount;

        // INTERACTION
        (bool ok,) = msg.sender.call{ value: amount }("");
        if (!ok) revert TransferFailed();
    }
}

