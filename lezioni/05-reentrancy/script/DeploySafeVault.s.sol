// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script Foundry: si esegue con `forge script` (comando completo nel README della lezione).
import { Script } from "forge-std/Script.sol";
import { SafeVaultGuarded } from "../src/reentrancy/SafeVaultGuarded.sol";

/// @notice Distribuisce soltanto la variante corretta CEI + guard in ambiente locale.
contract DeploySafeVault is Script {
    // run() e' la funzione che forge script esegue.
    function run() external returns (SafeVaultGuarded vault) {
        // Tra startBroadcast e stopBroadcast ogni operazione diventa una transazione reale,
        // firmata con la chiave passata a riga di comando. Fuori, e' solo simulazione.
        vm.startBroadcast();
        vault = new SafeVaultGuarded();
        vm.stopBroadcast();
    }
}
