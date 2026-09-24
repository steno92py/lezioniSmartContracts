// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {AuditEscrow} from "../src/target/AuditEscrow.sol";
import {RemediatedEscrow} from "../src/fixed/RemediatedEscrow.sol";
import {MockToken, MockOracle, RecordingNotifier} from "../src/mocks/AuditMocks.sol";

// Deploy locale (Anvil) di mock, target e patch con la stessa configurazione, per poterli
// confrontare fianco a fianco. Le call tra startBroadcast e stopBroadcast diventano
// transazioni firmate con la --private-key passata a forge script.
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
        oracle = new MockOracle(100e8, block.timestamp); // prezzo 100,00 (8 decimali), fresco
        notifier = new RecordingNotifier();

        // Argomenti: buyer, seller, governance (msg.sender dello script), guardian, token,
        // oracle, notifier, minPrice = 100e8, maxAge = 1 ora.
        target = new AuditEscrow(
            address(0xB0B), address(0x5E11E2), msg.sender, address(0x6A42D1A), token, oracle, notifier, 100e8, 1 hours
        );
        fixedEscrow = new RemediatedEscrow(
            address(0xB0B), address(0x5E11E2), msg.sender, address(0x6A42D1A), token, oracle, notifier, 100e8, 1 hours
        );
        vm.stopBroadcast();
    }
}
