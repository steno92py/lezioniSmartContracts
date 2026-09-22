// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { IPriceOracle } from "../src/oracle/IPriceOracle.sol";
import { MockPriceOracle } from "../src/mocks/MockPriceOracle.sol";
import { PriceConsumer } from "../src/PriceConsumer.sol";
import { MockSwap } from "../src/mocks/MockSwap.sol";
import { ISwap } from "../src/swap/ISwap.sol";
import { SafeSwapIntent } from "../src/swap/SafeSwapIntent.sol";

contract DeployOracleLab is Script {
    function run()
        external
        returns (
            MockPriceOracle oracle,
            PriceConsumer consumer,
            MockSwap swapper,
            SafeSwapIntent intent
        )
    {
        vm.startBroadcast();
        oracle = new MockPriceOracle(8);
        oracle.setPrice(3_000e8, block.timestamp);
        consumer = new PriceConsumer(IPriceOracle(address(oracle)), 1 hours);
        swapper = new MockSwap();
        intent = new SafeSwapIntent(ISwap(address(swapper)));
        vm.stopBroadcast();
    }
}

