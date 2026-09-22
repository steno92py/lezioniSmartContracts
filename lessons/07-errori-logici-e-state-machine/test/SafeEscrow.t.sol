// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { SafeEscrow } from "../src/SafeEscrow.sol";

contract SafeEscrowTest is Test {
    SafeEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal stranger;

    uint256 internal constant DEPOSIT = 1 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");

        escrow = new SafeEscrow(buyer, seller);
        vm.deal(buyer, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    function test_InitialConfiguration() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.depositedAmount(), 0);
        assertEq(escrow.liabilities(), 0);
        _assertState(SafeEscrow.State.Created);
    }

    function test_DepositMovesCreatedToFunded() public {
        _fund();

        _assertState(SafeEscrow.State.Funded);
        assertEq(escrow.depositedAmount(), DEPOSIT);
        assertEq(address(escrow).balance, DEPOSIT);
    }

    function test_CompleteMovesFundedToCompleted() public {
        _fund();

        vm.prank(seller);
        escrow.complete();

        _assertState(SafeEscrow.State.Completed);
        assertEq(escrow.sellerCredit(), DEPOSIT);
        assertEq(escrow.buyerCredit(), 0);
        _assertLiabilitiesBacked();
    }

    function test_CancelMovesFundedToCancelled() public {
        _fund();

        vm.prank(buyer);
        escrow.cancel();

        _assertState(SafeEscrow.State.Cancelled);
        assertEq(escrow.buyerCredit(), DEPOSIT);
        assertEq(escrow.sellerCredit(), 0);
        _assertLiabilitiesBacked();
    }

    function test_RevertWhen_StrangerDeposits() public {
        vm.expectRevert(abi.encodeWithSelector(SafeEscrow.OnlyBuyer.selector, stranger));
        vm.prank(stranger);
        escrow.deposit{ value: DEPOSIT }();

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_DepositIsZero() public {
        vm.expectRevert(SafeEscrow.WrongAmount.selector);
        vm.prank(buyer);
        escrow.deposit();

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_DepositingTwice() public {
        _fund();
        uint256 buyerBalanceBefore = buyer.balance;

        _expectWrongState(SafeEscrow.State.Created, SafeEscrow.State.Funded);
        vm.prank(buyer);
        escrow.deposit{ value: DEPOSIT }();

        _assertState(SafeEscrow.State.Funded);
        assertEq(buyer.balance, buyerBalanceBefore);
        assertEq(address(escrow).balance, DEPOSIT);
    }

    function test_RevertWhen_StrangerCompletes() public {
        _fund();

        vm.expectRevert(abi.encodeWithSelector(SafeEscrow.OnlySeller.selector, stranger));
        vm.prank(stranger);
        escrow.complete();

        _assertFundedWithoutCredits();
    }

    function test_RevertWhen_CompleteHappensBeforeDeposit() public {
        _expectWrongState(SafeEscrow.State.Funded, SafeEscrow.State.Created);
        vm.prank(seller);
        escrow.complete();

        _assertCreatedAndEmpty();
    }

    function test_RevertWhen_CancelHappensBeforeDeposit() public {
        _expectWrongState(SafeEscrow.State.Funded, SafeEscrow.State.Created);
        vm.prank(buyer);
        escrow.cancel();

        _assertCreatedAndEmpty();
    }

    function test_CompletedIsTerminalForComplete() public {
        _complete();

        _expectWrongState(SafeEscrow.State.Funded, SafeEscrow.State.Completed);
        vm.prank(seller);
        escrow.complete();

        _assertCompletedOnly();
    }

    function test_CompletedIsTerminalForCancel() public {
        _complete();

        _expectWrongState(SafeEscrow.State.Funded, SafeEscrow.State.Completed);
        vm.prank(buyer);
        escrow.cancel();

        _assertCompletedOnly();
    }

    function test_CancelledIsTerminalForComplete() public {
        _cancel();

        _expectWrongState(SafeEscrow.State.Funded, SafeEscrow.State.Cancelled);
        vm.prank(seller);
        escrow.complete();

        _assertCancelledOnly();
    }

    function test_CancelledIsTerminalForCancel() public {
        _cancel();

        _expectWrongState(SafeEscrow.State.Funded, SafeEscrow.State.Cancelled);
        vm.prank(buyer);
        escrow.cancel();

        _assertCancelledOnly();
    }

    function test_FailedTransitionLeavesStateAndAccountingUnchanged() public {
        _complete();

        SafeEscrow.State stateBefore = escrow.state();
        uint256 sellerCreditBefore = escrow.sellerCredit();
        uint256 balanceBefore = address(escrow).balance;

        _expectWrongState(SafeEscrow.State.Funded, SafeEscrow.State.Completed);
        vm.prank(seller);
        escrow.complete();

        assertEq(uint256(escrow.state()), uint256(stateBefore));
        assertEq(escrow.sellerCredit(), sellerCreditBefore);
        assertEq(address(escrow).balance, balanceBefore);
        _assertLiabilitiesBacked();
    }

    function test_RevertWhen_BuyerIsZero() public {
        vm.expectRevert(SafeEscrow.ZeroAddress.selector);
        new SafeEscrow(address(0), seller);
    }

    function test_RevertWhen_SellerIsZero() public {
        vm.expectRevert(SafeEscrow.ZeroAddress.selector);
        new SafeEscrow(buyer, address(0));
    }

    function test_RevertWhen_PartiesAreEqual() public {
        vm.expectRevert(SafeEscrow.SameParty.selector);
        new SafeEscrow(buyer, buyer);
    }

    function _fund() internal {
        vm.prank(buyer);
        escrow.deposit{ value: DEPOSIT }();
    }

    function _complete() internal {
        _fund();
        vm.prank(seller);
        escrow.complete();
    }

    function _cancel() internal {
        _fund();
        vm.prank(buyer);
        escrow.cancel();
    }

    function _expectWrongState(SafeEscrow.State expected, SafeEscrow.State actual) internal {
        vm.expectRevert(abi.encodeWithSelector(SafeEscrow.WrongState.selector, expected, actual));
    }

    function _assertState(SafeEscrow.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }

    function _assertCreatedAndEmpty() internal view {
        _assertState(SafeEscrow.State.Created);
        assertEq(escrow.depositedAmount(), 0);
        assertEq(escrow.liabilities(), 0);
        assertEq(address(escrow).balance, 0);
    }

    function _assertFundedWithoutCredits() internal view {
        _assertState(SafeEscrow.State.Funded);
        assertEq(escrow.liabilities(), 0);
        assertEq(address(escrow).balance, DEPOSIT);
    }

    function _assertCompletedOnly() internal view {
        _assertState(SafeEscrow.State.Completed);
        assertEq(escrow.sellerCredit(), DEPOSIT);
        assertEq(escrow.buyerCredit(), 0);
        _assertLiabilitiesBacked();
    }

    function _assertCancelledOnly() internal view {
        _assertState(SafeEscrow.State.Cancelled);
        assertEq(escrow.sellerCredit(), 0);
        assertEq(escrow.buyerCredit(), DEPOSIT);
        _assertLiabilitiesBacked();
    }

    function _assertLiabilitiesBacked() internal view {
        assertLe(escrow.liabilities(), escrow.depositedAmount());
        assertLe(escrow.liabilities(), address(escrow).balance);
    }
}

