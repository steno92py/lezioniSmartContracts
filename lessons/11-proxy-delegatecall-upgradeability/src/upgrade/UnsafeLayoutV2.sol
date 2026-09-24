// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IProxiable } from "./IProxiable.sol";

/// @notice Layout volutamente incompatibile: buyer e seller sono invertiti.
/// @dev Solo per dimostrazione locale. Un validator di upgrade deve rifiutarlo.
contract UnsafeLayoutV2 is IProxiable {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Stessi tipi e stessi slot della V1, ma con due nomi scambiati. Lo storage del proxy non
    // cambia: cambia come il nuovo codice lo interpreta. Dopo l'upgrade seller() legge il
    // vecchio buyer e buyer() il vecchio seller. Nessun controllo di questo contratto se ne
    // accorge: proxiableUUID e' corretto. Serve una storage-layout validation.
    uint64 private _initializedVersion;
    address public owner;
    address public seller;
    address public buyer;
    uint256 public amount;
    bool public funded;

    // Risponde con lo slot giusto: supera il controllo UUPS di upgradeToAndCall.
    function proxiableUUID() external pure returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    function version() external pure returns (uint256) {
        return 99;
    }
}
