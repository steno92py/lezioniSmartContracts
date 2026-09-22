// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {FeeCalculator, MutableOracle, FreshPriceConsumer} from "../src/fuzz/FuzzTargets.sol";
import {CreditVault} from "../src/invariant/CreditVault.sol";
import {ExactToken} from "../src/invariant/ExactToken.sol";
import {LifecycleEscrow} from "../src/invariant/LifecycleEscrow.sol";

contract DeployFuzzLab is Script {
    function run()
        external
        returns (
            FeeCalculator calculator,
            MutableOracle oracle,
            FreshPriceConsumer consumer,
            ExactToken token,
            CreditVault vault,
            LifecycleEscrow lifecycle
        )
    {
        vm.startBroadcast();
        calculator = new FeeCalculator();
        oracle = new MutableOracle();
        oracle.setAnswer(3_000e8, block.timestamp);
        consumer = new FreshPriceConsumer(oracle);
        token = new ExactToken();
        vault = new CreditVault(token);
        lifecycle = new LifecycleEscrow(address(0xB0B), block.timestamp + 7 days);
        vm.stopBroadcast();
    }
}

