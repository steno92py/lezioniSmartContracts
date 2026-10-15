// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Handler della state machine: tre azioni (fund, release, refund) che eseguono la transizione
// solo quando lo stato la permette, altrimenti sono no-op. Handler e ghost: vedi VaultHandler.
import {Test} from "forge-std/Test.sol";
import {LifecycleEscrow} from "../../../src/invariant/LifecycleEscrow.sol";

contract LifecycleHandler is Test {
    LifecycleEscrow public immutable escrow;
    address public immutable buyer;

    // Ghost con memoria STORICA: diventa true la prima volta che si raggiunge uno stato
    // terminale e non torna piu' false. Lo stato corrente da solo non ricorda il passato.
    bool public ghostTerminalSeen;
    uint256 public callsFund;
    uint256 public callsRelease;
    uint256 public callsRefund;
    uint256 public noOpCalls;

    constructor(LifecycleEscrow escrow_, address buyer_) {
        escrow = escrow_;
        buyer = buyer_;
    }

    function fund(uint256 rawAmount) external {
        // Precondizione non soddisfatta: no-op invece di un revert (fail_on_revert = true).
        if (escrow.state() != LifecycleEscrow.State.Created) {
            noOpCalls += 1;
            return;
        }
        uint256 amount = bound(rawAmount, 1, type(uint128).max);
        vm.prank(buyer);
        escrow.fund(amount);
        callsFund += 1;
    }

    function release() external {
        if (escrow.state() != LifecycleEscrow.State.Funded) {
            noOpCalls += 1;
            return;
        }
        vm.prank(buyer);
        escrow.release();
        ghostTerminalSeen = true;
        callsRelease += 1;
    }

    function refund() external {
        if (escrow.state() != LifecycleEscrow.State.Funded) {
            noOpCalls += 1;
            return;
        }
        // L'handler porta il tempo alla deadline se serve: senza questo warp il refund
        // revertirebbe quasi sempre e lo stato Refunded non verrebbe mai esplorato.
        if (block.timestamp < escrow.refundDeadline()) vm.warp(escrow.refundDeadline());
        vm.prank(buyer);
        escrow.refund();
        ghostTerminalSeen = true;
        callsRefund += 1;
    }
}

