// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IProxiable {
    function proxiableUUID() external view returns (bytes32);
}

