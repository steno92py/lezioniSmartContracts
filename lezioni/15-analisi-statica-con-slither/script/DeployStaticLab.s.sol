// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {StaticLab} from "../src/noisy/StaticLab.sol";
import {SafeStaticLab} from "../src/fixed/SafeStaticLab.sol";
import {RecordingAction} from "../src/mocks/StaticMocks.sol";

// Deploy locale (Anvil) di entrambe le versioni. 0xA11CE e' un admin giocattolo.
// Tra startBroadcast e stopBroadcast ogni call diventa una transazione firmata
// con la chiave passata da riga di comando (--private-key).
contract DeployStaticLab is Script {
    function run() external returns (StaticLab noisy, RecordingAction action, SafeStaticLab fixedLab) {
        vm.startBroadcast();
        noisy = new StaticLab(address(0xA11CE));
        action = new RecordingAction();
        fixedLab = new SafeStaticLab(address(0xA11CE), action);
        vm.stopBroadcast();
    }
}
