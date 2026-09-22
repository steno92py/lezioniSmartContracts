// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Primitive didattica minimale per osservare un trasferimento di ownership a due fasi.
/// @dev Per produzione usare una libreria mantenuta e pinnata, come OpenZeppelin Ownable2Step.
abstract contract Ownable2StepLite {
    error ZeroOwner();
    error Unauthorized(address caller);
    error NotPendingOwner(address caller);

    address public owner;
    address public pendingOwner;

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroOwner();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroOwner();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);

        address previousOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }
}

contract EscrowOwnable2Step is Ownable2StepLite {
    bool public paused;

    event PauseChanged(bool paused, address indexed owner);

    constructor(address initialOwner) Ownable2StepLite(initialOwner) { }

    function setPaused(bool value) external onlyOwner {
        paused = value;
        emit PauseChanged(value, msg.sender);
    }
}

