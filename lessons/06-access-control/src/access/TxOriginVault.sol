// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IProtectedValueSetter {
    function setProtectedValue(uint256 value) external;
}

/// @notice Esempio volutamente vulnerabile: autorizza l'origine della transaction.
contract TxOriginVault is IProtectedValueSetter {
    error ZeroOwner();
    error Unauthorized();

    address public immutable owner;
    uint256 public protectedValue;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setProtectedValue(uint256 value) external {
        if (tx.origin != owner) revert Unauthorized();
        protectedValue = value;
    }
}

/// @notice Versione corretta quando la policy richiede una chiamata diretta dell'owner.
contract DirectCallerVault is IProtectedValueSetter {
    error ZeroOwner();
    error Unauthorized(address caller);

    address public immutable owner;
    uint256 public protectedValue;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setProtectedValue(uint256 value) external {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        protectedValue = value;
    }
}

contract Forwarder {
    function forwardSet(IProtectedValueSetter target, uint256 value) external {
        target.setProtectedValue(value);
    }
}
