// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Deploy locale (Anvil) del grafo di governance della lezione:
//   signer (2-of-3) -> ToyMultisig (proposer) -> ToyTimelock (2 giorni) -> GovernedEscrow
import { Script } from "forge-std/Script.sol";
import { ToyMultisig } from "../src/governance/ToyMultisig.sol";
import { ToyTimelock } from "../src/governance/ToyTimelock.sol";
import { GovernedEscrow } from "../src/governance/GovernedEscrow.sol";

contract DeployGovernanceLab is Script {
    function run()
        external
        returns (ToyMultisig multisig, ToyTimelock timelock, GovernedEscrow escrow)
    {
        // Indirizzi fissi di esempio per i tre signer.
        address[] memory signers = new address[](3);
        signers[0] = address(0xA11CE);
        signers[1] = address(0xB0B);
        signers[2] = address(0xCA201);

        // Tra start e stopBroadcast ogni deploy diventa una transazione firmata.
        vm.startBroadcast();
        multisig = new ToyMultisig(signers, 2);
        // Argomenti: delay, proposer = multisig, executor = address(0) (aperto a tutti),
        // canceller, admin.
        timelock = new ToyTimelock(
            2 days, address(multisig), address(0), address(0xCA11CE1), address(0xAD)
        );
        // L'owner dell'escrow e' il timelock: e' questo che rende il delay non aggirabile.
        escrow = new GovernedEscrow(address(timelock), address(0x5EC));
        vm.stopBroadcast();
    }
}
