// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { EducationalERC1967Proxy } from "../src/proxy/EducationalERC1967Proxy.sol";
import { UpgradeableEscrowV1 } from "../src/upgrade/UpgradeableEscrowV1.sol";

// Deploy locale (Anvil): prima l'implementation, poi il proxy che la usa.
contract DeployUpgradeableEscrow is Script {
    address internal constant LOCAL_OWNER = address(0xA11CE);
    address internal constant LOCAL_BUYER = address(0xB0B);
    address internal constant LOCAL_SELLER = address(0x5E11E2);

    function run()
        external
        returns (UpgradeableEscrowV1 implementation, EducationalERC1967Proxy proxy)
    {
        // Ogni call tra start e stop diventa una transazione firmata e inviata.
        vm.startBroadcast();
        implementation = new UpgradeableEscrowV1(); // gia' bloccata dal suo constructor
        // La chiamata a initialize viaggia DENTRO il deploy del proxy: nessuna finestra in cui
        // il proxy esiste senza owner. abi.encodeCall costruisce la calldata controllando al
        // compile-time che tipi e numero degli argomenti corrispondano alla funzione.
        proxy = new EducationalERC1967Proxy(
            address(implementation),
            abi.encodeCall(UpgradeableEscrowV1.initialize, (LOCAL_OWNER, LOCAL_BUYER, LOCAL_SELLER))
        );
        vm.stopBroadcast();
    }
}
