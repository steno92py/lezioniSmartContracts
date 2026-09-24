// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { SafeEscrow } from "../src/SafeEscrow.sol";

/// @notice Deploy locale con identita' giocattolo; non usare chiavi reali.
contract DeploySafeEscrow is Script {
    address internal constant LOCAL_BUYER = address(0xB0B);
    address internal constant LOCAL_SELLER = address(0x5E11E2);

    // `forge script` esegue run(). Senza --broadcast e' solo una simulazione locale.
    function run() external returns (SafeEscrow escrow) {
        // Tra startBroadcast e stopBroadcast ogni call diventa una transazione vera,
        // firmata con la chiave passata da riga di comando (--private-key).
        vm.startBroadcast();
        escrow = new SafeEscrow(LOCAL_BUYER, LOCAL_SELLER); // deploy: parte in Created
        vm.stopBroadcast();
    }
}
