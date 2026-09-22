// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ExactToken} from "./ExactToken.sol";

contract CreditVault {
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientCredit(address account, uint256 requested, uint256 available);
    error TokenTransferFailed();

    ExactToken public immutable token;
    mapping(address account => uint256 amount) public credit;
    uint256 public totalCredit;

    constructor(ExactToken token_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (!token.transferFrom(msg.sender, address(this), amount)) revert TokenTransferFailed();
        credit[msg.sender] += amount;
        totalCredit += amount;
    }

    function withdraw(uint256 amount) external {
        uint256 available = credit[msg.sender];
        if (amount == 0 || amount > available) {
            revert InsufficientCredit(msg.sender, amount, available);
        }

        credit[msg.sender] = available - amount;
        totalCredit -= amount;
        if (!token.transfer(msg.sender, amount)) revert TokenTransferFailed();
    }
}

