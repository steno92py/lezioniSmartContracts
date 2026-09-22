// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto volutamente vulnerabile: dichiarare admin non applica alcuna policy.
contract EscrowAdminVulnerable {
    address public immutable buyer;
    address public immutable seller;
    address public admin;

    bool public paused;

    constructor(address buyer_, address seller_, address admin_) {
        require(buyer_ != address(0), "ZERO_BUYER");
        require(seller_ != address(0), "ZERO_SELLER");
        require(admin_ != address(0), "ZERO_ADMIN");

        buyer = buyer_;
        seller = seller_;
        admin = admin_;
    }

    // BUG INTENZIONALE: manca il controllo su msg.sender.
    function setPaused(bool value) external {
        paused = value;
    }
}

