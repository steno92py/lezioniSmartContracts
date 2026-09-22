// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { UpgradeableEscrowV1 } from "./UpgradeableEscrowV1.sol";

contract UpgradeableEscrowV2 is UpgradeableEscrowV1 {
    error FeeTooHigh(uint256 feeBps);

    event V2Initialized(uint256 feeBps, address indexed feeRecipient);

    uint256 public feeBps;
    address public feeRecipient;

    function initializeV2(uint256 feeBps_, address feeRecipient_) external onlyOwner {
        _startInitialization(2);
        if (feeBps_ > 1_000) revert FeeTooHigh(feeBps_);
        if (feeRecipient_ == address(0)) revert InvalidAddress();

        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
        emit V2Initialized(feeBps_, feeRecipient_);
    }

    function version() external pure override returns (uint256) {
        return 2;
    }

    function feeOnAmount() external view returns (uint256) {
        return amount * feeBps / 10_000;
    }
}
