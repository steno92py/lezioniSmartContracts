// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {StaticLab} from "../src/noisy/StaticLab.sol";
import {SafeStaticLab} from "../src/fixed/SafeStaticLab.sol";
import {RecordingAction} from "../src/mocks/StaticMocks.sol";

contract DeployStaticLab is Script {
    function run() external returns (StaticLab noisy, RecordingAction action, SafeStaticLab fixedLab) {
        vm.startBroadcast();
        noisy = new StaticLab(address(0xA11CE));
        action = new RecordingAction();
        fixedLab = new SafeStaticLab(address(0xA11CE), action);
        vm.stopBroadcast();
    }
}

