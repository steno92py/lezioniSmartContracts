// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script di deploy: si esegue con `forge script`, per esempio contro Anvil in locale.
// Script (forge-std) fornisce `vm` anche qui, con i cheatcode di broadcast.
import {Script} from "forge-std/Script.sol";
import {TestingEscrow} from "../src/TestingEscrow.sol";
import {WithdrawalVault} from "../src/WithdrawalVault.sol";
import {ConfigurableToken, MockOracle} from "../src/mocks/TestingMocks.sol";

contract DeployTestingLab is Script {
    // run() e' il punto d'ingresso che forge script chiama.
    function run()
        external
        returns (ConfigurableToken token, MockOracle oracle, TestingEscrow escrow, WithdrawalVault vault)
    {
        // Tra startBroadcast e stopBroadcast ogni call e ogni deploy diventa una transazione
        // vera, firmata con la chiave passata da riga di comando (--private-key).
        vm.startBroadcast();
        token = new ConfigurableToken();
        oracle = new MockOracle();
        oracle.setAnswer(3_000e8, block.timestamp); // prezzo fresco: 3000 con 8 decimali
        // Ruoli con indirizzi fissi e leggibili: buyer 0xB0B, seller 0x5E11E2, owner 0xA11CE.
        escrow = new TestingEscrow(
            address(token),
            address(oracle),
            address(0xB0B),
            address(0x5E11E2),
            address(0xA11CE),
            block.timestamp + 7 days
        );
        vault = new WithdrawalVault();
        vm.stopBroadcast();
    }
}

