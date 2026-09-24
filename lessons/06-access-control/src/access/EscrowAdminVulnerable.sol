// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto volutamente vulnerabile: dichiarare admin non applica alcuna policy.
contract EscrowAdminVulnerable {
    // `immutable`: fissati nel constructor e poi mai piu' modificabili.
    address public immutable buyer;
    address public immutable seller;
    // Salvare l'admin serve a sapere CHI dovrebbe avere il privilegio, ma da solo non
    // impedisce nulla: nessuna funzione lo confronta con msg.sender.
    address public admin;

    bool public paused;

    constructor(address buyer_, address seller_, address admin_) {
        // require(condizione, "messaggio"): la forma classica di controllo, con un messaggio
        // di testo. EscrowAdmin usa invece i custom error, piu' economici.
        require(buyer_ != address(0), "ZERO_BUYER");
        require(seller_ != address(0), "ZERO_SELLER");
        require(admin_ != address(0), "ZERO_ADMIN");

        buyer = buyer_;
        seller = seller_;
        admin = admin_;
    }

    // BUG INTENZIONALE: manca il controllo su msg.sender.
    // `external` dice DA DOVE si puo' chiamare (visibility), non CHI puo' farlo
    // (authorization): cosi' com'e', chiunque puo' mettere in pausa l'escrow.
    // FIX (vedi EscrowAdmin): il modifier onlyAdmin.
    function setPaused(bool value) external {
        paused = value;
    }
}
