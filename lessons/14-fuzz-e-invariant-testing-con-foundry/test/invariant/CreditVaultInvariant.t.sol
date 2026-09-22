// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {CreditVault} from "../../src/invariant/CreditVault.sol";
import {ExactToken} from "../../src/invariant/ExactToken.sol";
import {VaultHandler} from "./handlers/VaultHandler.sol";

contract CreditVaultInvariantTest is Test {
    ExactToken internal token;
    CreditVault internal vault;
    VaultHandler internal handler;

    function setUp() public {
        token = new ExactToken();
        vault = new CreditVault(token);
        handler = new VaultHandler(vault, token);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.withdraw.selector;
        selectors[2] = VaultHandler.withdrawTooMuch.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_VaultBalanceEqualsTotalCredit() public view {
        assertEq(token.balanceOf(address(vault)), vault.totalCredit());
    }

    function invariant_GhostNetDepositsEqualTotalCredit() public view {
        assertGe(handler.ghostDeposited(), handler.ghostWithdrawn());
        assertEq(handler.ghostDeposited() - handler.ghostWithdrawn(), vault.totalCredit());
    }

    function invariant_TotalCreditEqualsSumOfAllModelledActors() public view {
        uint256 actorCredits;
        for (uint256 i; i < handler.actorCount(); ++i) {
            actorCredits += vault.credit(handler.actor(i));
        }
        assertEq(actorCredits, vault.totalCredit());
    }

    function invariant_TokensAreConservedAcrossActorsAndVault() public view {
        uint256 observed = token.balanceOf(address(vault));
        for (uint256 i; i < handler.actorCount(); ++i) {
            observed += token.balanceOf(handler.actor(i));
        }
        assertEq(observed, 3 * handler.INITIAL_ACTOR_BALANCE());
    }
}
