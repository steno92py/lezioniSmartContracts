// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script e' la base di forge-std per gli script: fornisce `vm` come nei test.
import { Script } from "forge-std/Script.sol";
import { FixedFeeRegistry } from "../src/FixedFeeRegistry.sol";

/// @notice Deploy da usare esclusivamente su Anvil o su una rete didattica controllata.
contract DeployFixedFeeRegistry is Script {
    /// @dev `forge script` esegue run(). Senza --broadcast e' solo una simulazione locale.
    function run() external returns (FixedFeeRegistry registry) {
        // Tutto cio' che sta tra start e stop diventa una transazione reale da inviare,
        // firmata con la chiave passata da riga di comando (--private-key).
        vm.startBroadcast();
        registry = new FixedFeeRegistry(); // transazione di deploy
        vm.stopBroadcast();
    }
}
