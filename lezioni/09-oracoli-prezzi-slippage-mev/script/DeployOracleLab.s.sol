// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script di deploy locale (Anvil). `Script` di forge-std fornisce `vm` anche fuori dai test.
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
        // Tra startBroadcast e stopBroadcast ogni call diventa una transazione vera,
        // firmata con la chiave passata a `forge script --private-key`.
        vm.startBroadcast();
        oracle = new MockPriceOracle(8); // feed a 8 decimals
        oracle.setPrice(3_000e8, block.timestamp); // 3000 con 8 decimals; `_` solo per leggibilita'
        // L'oracle va deployato PRIMA: il constructor del consumer controlla che abbia codice.
        consumer = new PriceConsumer(IPriceOracle(address(oracle)), 1 hours);
        swapper = new MockSwap();
        intent = new SafeSwapIntent(ISwap(address(swapper)));
        vm.stopBroadcast();
    }
}
