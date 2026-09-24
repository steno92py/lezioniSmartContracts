// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { EscrowStateMachine } from "../src/EscrowStateMachine.sol";

/// @notice Deploy locale con parametri giocattolo per Anvil.
contract DeployEscrowStateMachine is Script {
    address internal constant LOCAL_SELLER = address(0xB0B);
    uint256 internal constant LOCAL_PRICE = 5 ether;

    function run() external returns (EscrowStateMachine escrow) {
        // Le transazioni tra start e stop vengono firmate con la chiave passata a forge script.
        // Il firmatario fa il deploy, quindi diventa il buyer (msg.sender nel constructor).
        vm.startBroadcast();
        escrow = new EscrowStateMachine(LOCAL_SELLER, LOCAL_PRICE);
        vm.stopBroadcast();
    }
}
