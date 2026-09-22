// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {LifecycleEscrow} from "../../src/invariant/LifecycleEscrow.sol";
import {LifecycleHandler} from "./handlers/LifecycleHandler.sol";

contract LifecycleInvariantTest is Test {
    LifecycleEscrow internal escrow;
    LifecycleHandler internal handler;

    function setUp() public {
        vm.warp(1_000_000);
        address buyer = makeAddr("buyer");
        escrow = new LifecycleEscrow(buyer, block.timestamp + 7 days);
        handler = new LifecycleHandler(escrow, buyer);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = LifecycleHandler.fund.selector;
        selectors[1] = LifecycleHandler.release.selector;
        selectors[2] = LifecycleHandler.refund.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_OnceTerminalNeverReturnsToNonTerminalState() public view {
        if (!handler.ghostTerminalSeen()) return;
        LifecycleEscrow.State current = escrow.state();
        assertTrue(current == LifecycleEscrow.State.Released || current == LifecycleEscrow.State.Refunded);
    }

    function invariant_TerminalStateHasNoLiability() public view {
        LifecycleEscrow.State current = escrow.state();
        if (current == LifecycleEscrow.State.Released || current == LifecycleEscrow.State.Refunded) {
            assertEq(escrow.amount(), 0);
        }
    }

    function invariant_NonTerminalStateAndAmountRemainConsistent() public view {
        if (escrow.state() == LifecycleEscrow.State.Created) assertEq(escrow.amount(), 0);
        if (escrow.state() == LifecycleEscrow.State.Funded) assertGt(escrow.amount(), 0);
    }
}
