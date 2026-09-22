// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IProxiable } from "./IProxiable.sol";

contract NotUUPSImplementation {
    function version() external pure returns (uint256) {
        return 404;
    }
}

contract WrongUUIDImplementation is IProxiable {
    function proxiableUUID() external pure returns (bytes32) {
        return bytes32(uint256(123));
    }
}
