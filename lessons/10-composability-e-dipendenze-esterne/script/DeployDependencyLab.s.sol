// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { INotifier } from "../src/interfaces/INotifier.sol";
import { IValueProvider } from "../src/interfaces/IValueProvider.sol";
import { NotificationEscrow } from "../src/NotificationEscrow.sol";
import { DependencyConsumer } from "../src/DependencyConsumer.sol";
import { GoodNotifier } from "../src/mocks/GoodNotifier.sol";
import { MutableDependency } from "../src/mocks/MutableDependency.sol";

contract DeployDependencyLab is Script {
    address internal constant LOCAL_BUYER = address(0xB0B);
    address internal constant LOCAL_SELLER = address(0x5E11E2);

    function run()
        external
        returns (
            GoodNotifier notifier,
            NotificationEscrow escrow,
            MutableDependency provider,
            DependencyConsumer consumer
        )
    {
        vm.startBroadcast();
        notifier = new GoodNotifier();
        escrow =
            new NotificationEscrow(INotifier(address(notifier)), LOCAL_BUYER, LOCAL_SELLER, 100);
        provider = new MutableDependency();
        consumer = new DependencyConsumer(IValueProvider(address(provider)), 1_000, 1 hours);
        vm.stopBroadcast();
    }
}

