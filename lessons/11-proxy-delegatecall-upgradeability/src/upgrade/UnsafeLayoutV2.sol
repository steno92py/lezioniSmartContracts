// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IProxiable } from "./IProxiable.sol";

/// @notice Layout volutamente incompatibile: buyer e seller sono invertiti.
/// @dev Solo per dimostrazione locale. Un validator di upgrade deve rifiutarlo.
contract UnsafeLayoutV2 is IProxiable {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    uint64 private _initializedVersion;
    address public owner;
    address public seller;
    address public buyer;
    uint256 public amount;
    bool public funded;

    function proxiableUUID() external pure returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    function version() external pure returns (uint256) {
        return 99;
    }
}

