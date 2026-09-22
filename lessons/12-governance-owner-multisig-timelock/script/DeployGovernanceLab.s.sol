// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { ToyMultisig } from "../src/governance/ToyMultisig.sol";
import { ToyTimelock } from "../src/governance/ToyTimelock.sol";
import { GovernedEscrow } from "../src/governance/GovernedEscrow.sol";

contract DeployGovernanceLab is Script {
    function run()
        external
        returns (ToyMultisig multisig, ToyTimelock timelock, GovernedEscrow escrow)
    {
        address[] memory signers = new address[](3);
        signers[0] = address(0xA11CE);
        signers[1] = address(0xB0B);
        signers[2] = address(0xCA201);

        vm.startBroadcast();
        multisig = new ToyMultisig(signers, 2);
        timelock = new ToyTimelock(
            2 days, address(multisig), address(0), address(0xCA11CE1), address(0xAD)
        );
        escrow = new GovernedEscrow(address(timelock), address(0x5EC));
        vm.stopBroadcast();
    }
}

