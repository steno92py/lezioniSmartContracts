// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {LifecycleEscrow} from "../../../src/invariant/LifecycleEscrow.sol";

contract LifecycleHandler is Test {
    LifecycleEscrow public immutable escrow;
    address public immutable buyer;

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
        if (block.timestamp < escrow.refundDeadline()) vm.warp(escrow.refundDeadline());
        vm.prank(buyer);
        escrow.refund();
        ghostTerminalSeen = true;
        callsRefund += 1;
    }
}

