// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {AuditEscrow} from "../src/target/AuditEscrow.sol";
import {RemediatedEscrow} from "../src/fixed/RemediatedEscrow.sol";
import {MockToken, MockOracle, RecordingNotifier} from "../src/mocks/AuditMocks.sol";

contract DeployAuditLab is Script {
    function run()
        external
        returns (
            MockToken token,
            MockOracle oracle,
            RecordingNotifier notifier,
            AuditEscrow target,
            RemediatedEscrow fixedEscrow
        )
    {
        vm.startBroadcast();
        token = new MockToken();
        oracle = new MockOracle(100e8, block.timestamp);
        notifier = new RecordingNotifier();

        target = new AuditEscrow(
            address(0xB0B), address(0x5E11E2), msg.sender, address(0x6A42D1A), token, oracle, notifier, 100e8, 1 hours
        );
        fixedEscrow = new RemediatedEscrow(
            address(0xB0B), address(0x5E11E2), msg.sender, address(0x6A42D1A), token, oracle, notifier, 100e8, 1 hours
        );
        vm.stopBroadcast();
    }
}
