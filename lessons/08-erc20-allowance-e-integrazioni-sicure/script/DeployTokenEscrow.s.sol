// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "../src/token/IERC20.sol";
import { TokenEscrow } from "../src/TokenEscrow.sol";
import { TestToken } from "../test/mocks/TestToken.sol";

/// @notice Deploy locale di token giocattolo ed Escrow; non usare asset o chiavi reali.
contract DeployTokenEscrow is Script {
    address internal constant LOCAL_BUYER = address(0xB0B);
    address internal constant LOCAL_SELLER = address(0x5E11E2);

    function run() external returns (TestToken token, TokenEscrow escrow) {
        vm.startBroadcast();
        token = new TestToken();
        escrow = new TokenEscrow(IERC20(address(token)), LOCAL_BUYER, LOCAL_SELLER);
        token.mint(LOCAL_BUYER, 1_000 ether);
        vm.stopBroadcast();
    }
}

