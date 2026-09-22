// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {TestingEscrow} from "../src/TestingEscrow.sol";
import {WithdrawalVault} from "../src/WithdrawalVault.sol";
import {ConfigurableToken, MockOracle} from "../src/mocks/TestingMocks.sol";

contract DeployTestingLab is Script {
    function run()
        external
        returns (ConfigurableToken token, MockOracle oracle, TestingEscrow escrow, WithdrawalVault vault)
    {
        vm.startBroadcast();
        token = new ConfigurableToken();
        oracle = new MockOracle();
        oracle.setAnswer(3_000e8, block.timestamp);
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

