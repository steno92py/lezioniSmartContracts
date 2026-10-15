// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { UpgradeableEscrowV1 } from "./UpgradeableEscrowV1.sol";

// In questo layout la V1 invariata conserva i campi negli slot 0-4; feeBps e feeRecipient
// occupano gli slot 5 e 6. L'ereditarieta' da sola non valida un upgrade: confrontare
// sempre slot, offset e tipi delle due versioni, anche in presenza di packing.
contract UpgradeableEscrowV2 is UpgradeableEscrowV1 {
    error FeeTooHigh(uint256 feeBps);

    event V2Initialized(uint256 feeBps, address indexed feeRecipient);

    uint256 public feeBps; // basis point: 1 bps = 0,01%, 10_000 bps = 100%
    address public feeRecipient;

    /// @dev Migrazione della V2, da passare come migrationData a upgradeToAndCall. A differenza
    /// di initialize() qui c'e' onlyOwner: il proxy esiste gia' e ha un owner.
    function initializeV2(uint256 feeBps_, address feeRecipient_) external onlyOwner {
        _startInitialization(2); // una sola volta: dopo, la versione vale 2
        if (feeBps_ > 1_000) revert FeeTooHigh(feeBps_); // tetto: 10%
        if (feeRecipient_ == address(0)) revert InvalidAddress();

        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
        emit V2Initialized(feeBps_, feeRecipient_);
    }

    function version() external pure override returns (uint256) {
        return 2;
    }

    // amount e' scritto dalla V1: la V2 lo legge perche' e' ancora nello stesso slot.
    function feeOnAmount() external view returns (uint256) {
        return amount * feeBps / 10_000;
    }
}
