// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { FixedFeeRegistry } from "../src/FixedFeeRegistry.sol";

/// @notice Deploy da usare esclusivamente su Anvil o su una rete didattica controllata.
contract DeployFixedFeeRegistry is Script {
    function run() external returns (FixedFeeRegistry registry) {
        vm.startBroadcast();
        registry = new FixedFeeRegistry();
        vm.stopBroadcast();
    }
}

