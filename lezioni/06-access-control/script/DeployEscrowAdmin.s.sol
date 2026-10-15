// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script Foundry: si esegue con `forge script` (comando completo nel README della lezione).
import { Script } from "forge-std/Script.sol";
import { EscrowAdmin } from "../src/access/EscrowAdmin.sol";

/// @notice Deploy locale con ruoli giocattolo.
contract DeployEscrowAdmin is Script {
    // Indirizzi finti e fissi: nessuno ne possiede la chiave, vanno bene solo su Anvil.
    address internal constant LOCAL_BUYER = address(0xB0B);
    address internal constant LOCAL_SELLER = address(0x5E11E2);
    address internal constant LOCAL_ADMIN = address(0xAD);

    function run() external returns (EscrowAdmin escrow) {
        // Solo cio' che sta tra startBroadcast e stopBroadcast diventa una transazione reale.
        vm.startBroadcast();
        escrow = new EscrowAdmin(LOCAL_BUYER, LOCAL_SELLER, LOCAL_ADMIN);
        vm.stopBroadcast();
    }
}
