// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Proxy ERC-1967 minimale per il laboratorio. Non usare in produzione.
contract EducationalERC1967Proxy {
    error ImplementationHasNoCode(address implementation);

    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation_, bytes memory initializationData) payable {
        _setImplementation(implementation_);
        if (initializationData.length != 0) {
            _delegateCall(implementation_, initializationData);
        }
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    fallback() external payable {
        _delegate(_implementation());
    }

    receive() external payable {
        _delegate(_implementation());
    }

    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ImplementationHasNoCode(newImplementation);
        }
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            sstore(slot, newImplementation)
        }
    }

    function _implementation() private view returns (address result) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            result := sload(slot)
        }
    }

    function _delegateCall(address target, bytes memory data) private {
        (bool success, bytes memory result) = target.delegatecall(data);
        if (!success) _revertWithData(result);
    }

    function _revertWithData(bytes memory result) private pure {
        assembly ("memory-safe") {
            revert(add(result, 0x20), mload(result))
        }
    }

    function _delegate(address target) private {
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

