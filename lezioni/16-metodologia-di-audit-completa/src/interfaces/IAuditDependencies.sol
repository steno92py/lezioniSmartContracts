// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Interfacce delle tre dipendenze esterne dell'escrow. Un'interfaccia fissa solo le firme:
// il codice reale dietro l'indirizzo e' fuori dal controllo del contratto che la usa
// (trust boundary). Nei test il ruolo lo fanno i mock di src/mocks/AuditMocks.sol.

// Sottoinsieme ERC-20: solo le funzioni usate dall'escrow.
interface IAuditToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPriceOracle {
    // price: con segno e 8 decimali (100e8 = 100,00); updatedAt: timestamp Unix dell'ultimo
    // aggiornamento. Valori ammessi: vedi "Dipendenze e assunzioni" in audit/scope.md.
    function latestPrice() external view returns (int256 price, uint256 updatedAt);
}

interface ISettlementNotifier {
    // Nessun valore di ritorno: il chiamante vede solo successo o revert.
    function notify(address buyer, address seller, uint256 amount) external;
}

