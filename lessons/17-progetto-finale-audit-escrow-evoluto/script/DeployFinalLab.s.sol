// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script di forge: `forge script` esegue run(); le transazioni tra startBroadcast e
// stopBroadcast vengono firmate e (con --broadcast) inviate davvero alla rete scelta.
import {Script} from "forge-std/Script.sol";
import {EscrowFinal} from "../src/EscrowFinal.sol";
import {EscrowFinalFixed} from "../src/fixed/EscrowFinalFixed.sol";
import {TestToken, MockOracle, RecordingNotifier} from "../src/mocks/FinalMocks.sol";

// Deploy di laboratorio: target e remediation affiancati, con le stesse dipendenze finte.
contract DeployFinalLab is Script {
    function run()
        external
        returns (
            TestToken token,
            MockOracle oracle,
            RecordingNotifier notifier,
            EscrowFinal target,
            EscrowFinalFixed fixedEscrow
        )
    {
        vm.startBroadcast();
        token = new TestToken();
        oracle = new MockOracle(3_000e8, block.timestamp); // 3000 con 8 decimali, appena aggiornato
        notifier = new RecordingNotifier();
        // Ruoli: buyer 0xB0B, seller 0x5E11E2, owner = chi esegue lo script, pauser 0xA115E.
        target =
            new EscrowFinal(token, address(0xB0B), address(0x5E11E2), msg.sender, address(0xA115E), oracle, notifier);
        fixedEscrow = new EscrowFinalFixed(
            token, address(0xB0B), address(0x5E11E2), msg.sender, address(0xA115E), oracle, notifier
        );
        vm.stopBroadcast();
    }
}
