// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Script e' la base di forge-std per gli script: fornisce `vm` come nei test, ma le call
// racchiuse tra startBroadcast e stopBroadcast diventano transazioni reali sulla rete
// indicata con --rpc-url (qui Anvil, una blockchain locale).
import { Script } from "forge-std/Script.sol";
import { IERC20 } from "../src/token/IERC20.sol";
import { TokenEscrow } from "../src/TokenEscrow.sol";
import { TestToken } from "../test/mocks/TestToken.sol";

/// @notice Deploy locale di token giocattolo ed Escrow; non usare asset o chiavi reali.
contract DeployTokenEscrow is Script {
    address internal constant LOCAL_BUYER = address(0xB0B);
    address internal constant LOCAL_SELLER = address(0x5E11E2);

    function run() external returns (TestToken token, TokenEscrow escrow) {
        vm.startBroadcast(); // da qui ogni call e' firmata con la --private-key passata
        token = new TestToken();
        // Il token va deployato PRIMA: il constructor dell'Escrow verifica che abbia codice.
        escrow = new TokenEscrow(IERC20(address(token)), LOCAL_BUYER, LOCAL_SELLER);
        // TestToken ha un mint pubblico: accettabile solo perche' e' un giocattolo locale.
        token.mint(LOCAL_BUYER, 1_000 ether);
        vm.stopBroadcast();
    }
}
