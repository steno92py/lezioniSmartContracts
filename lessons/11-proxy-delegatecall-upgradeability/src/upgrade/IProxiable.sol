// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Interfaccia di un'implementation UUPS (ERC-1822): proxiableUUID() dichiara in quale slot
// il proxy tiene l'indirizzo dell'implementation. Prima di un upgrade la si interroga per
// verificare che il nuovo codice sappia gestire gli upgrade futuri.
interface IProxiable {
    function proxiableUUID() external view returns (bytes32);
}
