// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { EscrowLesson1 } from "../src/EscrowLesson1.sol";

/// @notice Deploy da eseguire soltanto su Anvil o su un'altra rete didattica controllata.
contract DeployEscrowLesson1 is Script {
    function run() external returns (EscrowLesson1 escrow) {
        vm.startBroadcast();
        escrow = new EscrowLesson1();
        vm.stopBroadcast();
    }
}

