// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script: codice Solidity che forge esegue per fare deploy. Solo verso Anvil (rete locale),
// con i mock della lezione: nessun protocollo reale.
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
        // Tra startBroadcast e stopBroadcast ogni call/deploy diventa una transazione vera,
        // firmata con la chiave passata a `forge script --private-key`.
        vm.startBroadcast();
        // Ordine obbligato: le dipendenze prima, perche' i constructor verificano che
        // all'indirizzo ci sia gia' del codice.
        notifier = new GoodNotifier();
        escrow =
            new NotificationEscrow(INotifier(address(notifier)), LOCAL_BUYER, LOCAL_SELLER, 100);
        provider = new MutableDependency();
        // maxValue 1000, cache valida per 1 ora.
        consumer = new DependencyConsumer(IValueProvider(address(provider)), 1_000, 1 hours);
        vm.stopBroadcast();
    }
}
