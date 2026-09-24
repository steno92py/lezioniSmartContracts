// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { EscrowWithPayout } from "../src/EscrowWithPayout.sol";

/// @notice Deploy locale con parametri giocattolo per Anvil.
contract DeployEscrowWithPayout is Script {
    // payable(...) converte un address in address payable, il tipo richiesto dal constructor.
    address payable internal constant LOCAL_SELLER = payable(address(0xB0B));
    uint256 internal constant LOCAL_PRICE = 5 ether;

    function run() external returns (EscrowWithPayout escrow) {
        // Il firmatario della transazione di deploy diventa il buyer.
        vm.startBroadcast();
        escrow = new EscrowWithPayout(LOCAL_SELLER, LOCAL_PRICE);
        vm.stopBroadcast();
    }
}
