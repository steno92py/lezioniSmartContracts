// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { SafeEscrow } from "../src/SafeEscrow.sol";

/// @notice Deploy locale con identita' giocattolo; non usare chiavi reali.
contract DeploySafeEscrow is Script {
    address internal constant LOCAL_BUYER = address(0xB0B);
    address internal constant LOCAL_SELLER = address(0x5E11E2);

    function run() external returns (SafeEscrow escrow) {
        vm.startBroadcast();
        escrow = new SafeEscrow(LOCAL_BUYER, LOCAL_SELLER);
        vm.stopBroadcast();
    }
}

