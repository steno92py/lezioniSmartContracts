// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract SettlementTest is EscrowTestBase {
    event Released(address indexed seller, uint256 payout, uint256 fee);
    event Refunded(address indexed buyer, uint256 amount);

    function test_ReleaseClearsLiabilityAndPaysBalanceDeltas() public {
        uint256 amount = 100 ether;
        vm.prank(owner);
        escrow.setFee(250);
        _approveAndDeposit(amount);

        uint256 sellerBefore = token.balanceOf(seller);
        uint256 ownerBefore = token.balanceOf(owner);
        uint256 expectedFee = 2.5 ether;

        vm.expectEmit(true, false, false, true, address(escrow));
        emit Released(seller, amount - expectedFee, expectedFee);
        vm.prank(buyer);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Released));
        assertEq(escrow.depositedAmount(), 0);
        assertEq(escrow.liability(), 0);
        assertEq(token.balanceOf(seller) - sellerBefore, amount - expectedFee);
        assertEq(token.balanceOf(owner) - ownerBefore, expectedFee);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_ReleaseBeforeFundingReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TestingEscrow.InvalidState.selector, TestingEscrow.State.Funded, TestingEscrow.State.Created
            )
        );
        vm.prank(buyer);
        escrow.release();
    }

    function test_RefundOneSecondBeforeDeadlineRevertsAndPreservesState() public {
        _approveAndDeposit(100 ether);
        vm.warp(escrow.refundDeadline() - 1);

        vm.expectRevert(
            abi.encodeWithSelector(TestingEscrow.RefundTooEarly.selector, escrow.refundDeadline(), block.timestamp)
        );
        vm.prank(buyer);
        escrow.refund();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Funded));
        assertEq(escrow.depositedAmount(), 100 ether);
    }

    function test_RefundExactlyAtDeadlineSucceeds() public {
        uint256 amount = 100 ether;
        _approveAndDeposit(amount);
        uint256 buyerBefore = token.balanceOf(buyer);
        vm.warp(escrow.refundDeadline());

        vm.expectEmit(true, false, false, true, address(escrow));
        emit Refunded(buyer, amount);
        vm.prank(buyer);
        escrow.refund();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Refunded));
        assertEq(token.balanceOf(buyer) - buyerBefore, amount);
        assertEq(escrow.liability(), 0);
    }

    function test_ReleasedIsTerminalState() public {
        _approveAndDeposit(100 ether);
        vm.prank(buyer);
        escrow.release();
        vm.warp(escrow.refundDeadline());

        vm.expectRevert(
            abi.encodeWithSelector(
                TestingEscrow.InvalidState.selector, TestingEscrow.State.Funded, TestingEscrow.State.Released
            )
        );
        vm.prank(buyer);
        escrow.refund();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Released));
    }

    function test_UnauthorizedCallerCannotReleaseEvenWhenFunded() public {
        _approveAndDeposit(100 ether);

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.release();

        assertEq(escrow.liability(), 100 ether);
    }
}

