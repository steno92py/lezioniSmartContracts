// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Versione minimale corretta con un singolo ruolo amministrativo.
contract EscrowAdmin {
    error ZeroAddress();
    // Il custom error riporta chi ha tentato la call: i test verificano anche questo valore.
    error Unauthorized(address caller);

    address public immutable buyer;
    address public immutable seller;
    address public admin;

    bool public paused;

    // Evento: lascia traccia pubblica di chi ha cambiato la pausa. `indexed` permette di
    // filtrare i log per admin.
    event PauseChanged(bool paused, address indexed admin);

    constructor(address buyer_, address seller_, address admin_) {
        // Un admin zero renderebbe setPaused inutilizzabile per sempre: nessuno puo' firmare
        // come address(0).
        if (buyer_ == address(0) || seller_ == address(0) || admin_ == address(0)) {
            revert ZeroAddress();
        }

        buyer = buyer_;
        seller = seller_;
        admin = admin_;
    }

    // Modifier: codice riusabile che gira PRIMA del corpo della funzione. `_;` indica il
    // punto in cui viene inserito il corpo. Se il controllo fallisce, il corpo non gira.
    // Si controlla msg.sender, il chiamante diretto, non tx.origin (vedi TxOriginVault).
    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized(msg.sender);
        _;
    }

    // Stessa funzione di EscrowAdminVulnerable: l'unica differenza e' `onlyAdmin`.
    function setPaused(bool value) external onlyAdmin {
        paused = value;
        emit PauseChanged(value, msg.sender);
    }
}
