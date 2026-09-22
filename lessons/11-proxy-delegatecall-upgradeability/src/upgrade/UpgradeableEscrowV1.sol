// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IProxiable } from "./IProxiable.sol";

/// @notice Implementation UUPS-like minimale per comprendere il meccanismo.
/// @dev Non sostituisce OpenZeppelin Contracts Upgradeable o i relativi validator.
contract UpgradeableEscrowV1 is IProxiable {
    error AlreadyInitialized(uint64 currentVersion);
    error InvalidAddress();
    error SameParty();
    error Unauthorized(address caller);
    error AlreadyFunded();
    error ZeroAmount();
    error MustBeCalledThroughActiveProxy();
    error MustNotBeCalledThroughProxy();
    error ImplementationHasNoCode(address implementation);
    error UnsupportedProxiableUUID(bytes32 received);
    error NotUUPSImplementation(address implementation);

    event Funded(address indexed buyer, uint256 amount);
    event Upgraded(address indexed implementation);

    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address private immutable SELF = address(this);

    uint64 private _initializedVersion;
    address public owner;
    address public buyer;
    address public seller;
    uint256 public amount;
    bool public funded;

    constructor() {
        _initializedVersion = type(uint64).max;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyActiveProxy() {
        if (address(this) == SELF || _getImplementation() != SELF) {
            revert MustBeCalledThroughActiveProxy();
        }
        _;
    }

    function initialize(address owner_, address buyer_, address seller_) external {
        _startInitialization(1);
        if (owner_ == address(0) || buyer_ == address(0) || seller_ == address(0)) {
            revert InvalidAddress();
        }
        if (buyer_ == seller_) revert SameParty();

        owner = owner_;
        buyer = buyer_;
        seller = seller_;
    }

    function fund(uint256 amount_) external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (funded) revert AlreadyFunded();
        if (amount_ == 0) revert ZeroAmount();

        amount = amount_;
        funded = true;
        emit Funded(msg.sender, amount_);
    }

    function initializationVersion() external view returns (uint64) {
        return _initializedVersion;
    }

    function version() external pure virtual returns (uint256) {
        return 1;
    }

    function proxiableUUID() external view returns (bytes32) {
        if (address(this) != SELF) revert MustNotBeCalledThroughProxy();
        return IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes calldata migrationData)
        external
        payable
        onlyActiveProxy
        onlyOwner
    {
        _checkNewImplementation(newImplementation);
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (migrationData.length != 0) {
            (bool success, bytes memory result) = newImplementation.delegatecall(migrationData);
            if (!success) _revertWithData(result);
        }
    }

    function _startInitialization(uint64 targetVersion) internal {
        if (_initializedVersion >= targetVersion) {
            revert AlreadyInitialized(_initializedVersion);
        }
        _initializedVersion = targetVersion;
    }

    function _checkNewImplementation(address newImplementation) private view {
        if (newImplementation.code.length == 0) {
            revert ImplementationHasNoCode(newImplementation);
        }

        try IProxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != IMPLEMENTATION_SLOT) revert UnsupportedProxiableUUID(slot);
        } catch {
            revert NotUUPSImplementation(newImplementation);
        }
    }

    function _setImplementation(address newImplementation) private {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            sstore(slot, newImplementation)
        }
    }

    function _getImplementation() internal view returns (address result) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            result := sload(slot)
        }
    }

    function _revertWithData(bytes memory result) private pure {
        assembly ("memory-safe") {
            revert(add(result, 0x20), mload(result))
        }
    }
}

