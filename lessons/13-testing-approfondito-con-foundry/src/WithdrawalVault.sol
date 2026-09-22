// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Pull-payment vault minimale per regression test su callback e rollback.
contract WithdrawalVault {
    error ZeroAddress();
    error ZeroAmount();
    error NoCredit(address account);
    error EtherTransferFailed();

    mapping(address account => uint256 amount) public credit;
    uint256 public totalLiabilities;

    function depositFor(address beneficiary) external payable {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        credit[beneficiary] += msg.value;
        totalLiabilities += msg.value;
    }

    function withdraw() external {
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit(msg.sender);

        credit[msg.sender] = 0;
        totalLiabilities -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert EtherTransferFailed();
    }
}

