// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { SafeVaultGuarded } from "../src/reentrancy/SafeVaultGuarded.sol";

/// @notice Distribuisce soltanto la variante corretta CEI + guard in ambiente locale.
contract DeploySafeVault is Script {
    function run() external returns (SafeVaultGuarded vault) {
        vm.startBroadcast();
        vault = new SafeVaultGuarded();
        vm.stopBroadcast();
    }
}

