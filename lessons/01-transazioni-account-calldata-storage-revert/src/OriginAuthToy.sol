// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface ISetter {
    function setValue(uint256 newValue) external;
}

/// @notice Esempio volutamente vulnerabile. Non usare questo modello in produzione.
contract OriginAuthToy is ISetter {
    error NotOwner();
    error ZeroOwner();

    address public immutable owner;
    uint256 public value;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setValue(uint256 newValue) external {
        // Vulnerabilita': autorizza l'origine, non il chiamante diretto.
        if (tx.origin != owner) revert NotOwner();
        value = newValue;
    }
}

/// @notice Versione corretta per il requisito "solo l'owner chiama direttamente".
contract SenderAuthToy is ISetter {
    error NotOwner();
    error ZeroOwner();

    address public immutable owner;
    uint256 public value;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setValue(uint256 newValue) external {
        if (msg.sender != owner) revert NotOwner();
        value = newValue;
    }
}

/// @notice Intermediario che rende visibile la differenza tra msg.sender e tx.origin.
contract ForwarderToy {
    event Forwarding(address indexed directCaller, address indexed target, uint256 newValue);

    function forward(ISetter target, uint256 newValue) external {
        emit Forwarding(msg.sender, address(target), newValue);
        target.setValue(newValue);
    }
}
