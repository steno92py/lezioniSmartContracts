// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Proxy intenzionalmente insicuro: metadata nello slot 0 e upgrade senza autorizzazione.
contract SimpleProxy {
    address public implementation;

    constructor(address implementation_) {
        implementation = implementation_;
    }

    function upgradeTo(address newImplementation) external {
        implementation = newImplementation;
    }

    fallback() external {
        address target = implementation;
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
