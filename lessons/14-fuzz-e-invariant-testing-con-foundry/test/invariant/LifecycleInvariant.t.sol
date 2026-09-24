// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Invariant test della state machine. Meccanismo, targetContract e targetSelector: vedi
// CreditVaultInvariant.t.sol. Qui le azioni sono fund, release e refund del LifecycleHandler.
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

    // "Once terminal, always terminal": serve la ghost variable, perche' l'invariante vede
    // solo lo stato corrente. Finche' nessuno stato terminale e' stato raggiunto non c'e'
    // niente da verificare.
    function invariant_OnceTerminalNeverReturnsToNonTerminalState() public view {
        if (!handler.ghostTerminalSeen()) return;
        LifecycleEscrow.State current = escrow.state();
        assertTrue(current == LifecycleEscrow.State.Released || current == LifecycleEscrow.State.Refunded);
    }

    // Terminale -> nessun importo ancora dovuto.
    function invariant_TerminalStateHasNoLiability() public view {
        LifecycleEscrow.State current = escrow.state();
        if (current == LifecycleEscrow.State.Released || current == LifecycleEscrow.State.Refunded) {
            assertEq(escrow.amount(), 0);
        }
    }

    // Coerenza stato/importo negli stati non terminali: Created -> 0, Funded -> > 0.
    function invariant_NonTerminalStateAndAmountRemainConsistent() public view {
        if (escrow.state() == LifecycleEscrow.State.Created) assertEq(escrow.amount(), 0);
        if (escrow.state() == LifecycleEscrow.State.Funded) assertGt(escrow.amount(), 0);
    }
}
