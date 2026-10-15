// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IProxiable } from "./IProxiable.sol";

// Due implementation da RIFIUTARE, usate nei test negativi dell'upgrade.

// Nessuna proxiableUUID: in UUPS la funzione di upgrade sta nell'implementation, quindi un
// proxy aggiornato a questo contratto non potrebbe piu' essere aggiornato (bricking).
contract NotUUPSImplementation {
    function version() external pure returns (uint256) {
        return 404;
    }
}

// Ha proxiableUUID, ma dichiara uno slot diverso da quello ERC-1967 usato dal proxy.
contract WrongUUIDImplementation is IProxiable {
    function proxiableUUID() external pure returns (bytes32) {
        return bytes32(uint256(123));
    }
}
