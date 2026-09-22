// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Vault volutamente vulnerabile. Usare soltanto nel laboratorio locale.
contract VulnerableVault {
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
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        // VULNERABILE: INTERACTION prima degli EFFECTS.
        (bool ok,) = msg.sender.call{ value: amount }("");
        if (!ok) revert TransferFailed();

        // Durante la callback il credito era ancora spendibile.
        credit[msg.sender] = 0;
        totalCredits -= amount;
    }
}

