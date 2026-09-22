// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { EscrowStateMachine } from "../src/EscrowStateMachine.sol";

contract EscrowStateMachineTest is Test {
    EscrowStateMachine internal escrow;

    address internal buyer;
    address internal seller;
    address internal outsider;

    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        outsider = makeAddr("outsider");

        vm.deal(buyer, 100 ether);
        vm.deal(outsider, 100 ether);

        vm.prank(buyer);
        escrow = new EscrowStateMachine(seller, PRICE);
    }

    function test_InitialConfiguration() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.price(), PRICE);
        _assertState(EscrowStateMachine.State.Created);
    }

    function test_BuyerCanFundExactPrice() public {
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_BuyerCanApproveAfterFunding() public {
        _fund();

        vm.prank(buyer);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.ReleaseApproved);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_BuyerCanCancelBeforeFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(EscrowStateMachine.State.Cancelled);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhen_OutsiderFunds() public {
        vm.expectPartialRevert(EscrowStateMachine.Unauthorized.selector);
        vm.prank(outsider);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhen_SellerApprovesRelease() public {
        _fund();

        vm.expectPartialRevert(EscrowStateMachine.Unauthorized.selector);
        vm.prank(seller);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.Funded);
    }

    function test_RevertWhen_FundingIsTooLow() public {
        uint256 tooLittle = PRICE - 1;

        vm.expectPartialRevert(EscrowStateMachine.WrongValue.selector);
        vm.prank(buyer);
        escrow.fund{ value: tooLittle }();

        _assertState(EscrowStateMachine.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhen_FundingIsTooHigh() public {
        uint256 tooMuch = PRICE + 1;

        vm.expectPartialRevert(EscrowStateMachine.WrongValue.selector);
        vm.prank(buyer);
        escrow.fund{ value: tooMuch }();

        _assertState(EscrowStateMachine.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    /// @dev Regression test per la guardia Funded -> ReleaseApproved.
    function test_RevertWhen_ApproveHappensBeforeFunding() public {
        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.Created);
    }

    function test_RevertWhen_FundingTwice() public {
        _fund();
        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Funded);
        assertEq(address(escrow).balance, PRICE);
        assertEq(buyer.balance, buyerBalanceBefore);
    }

    function test_RevertWhen_CancellingAfterFunding() public {
        _fund();

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(EscrowStateMachine.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    function test_CancelledStateIsTerminalForFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();
        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Cancelled);
        assertEq(address(escrow).balance, 0);
        assertEq(buyer.balance, buyerBalanceBefore);
    }

    function test_ReleaseApprovedStateIsTerminalForApprove() public {
        _fundAndApprove();

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.ReleaseApproved);
    }

    function test_RevertedFundingLeavesNoPartialEffects() public {
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 escrowBalanceBefore = address(escrow).balance;

        vm.expectPartialRevert(EscrowStateMachine.WrongValue.selector);
        vm.prank(buyer);
        escrow.fund{ value: PRICE - 1 }();

        assertEq(buyer.balance, buyerBalanceBefore);
        assertEq(address(escrow).balance, escrowBalanceBefore);
        _assertState(EscrowStateMachine.State.Created);
    }

    function test_RevertWhen_ConstructorSellerIsZero() public {
        vm.expectRevert(EscrowStateMachine.ZeroSeller.selector);
        vm.prank(buyer);
        new EscrowStateMachine(address(0), PRICE);
    }

    function test_RevertWhen_ConstructorBuyerEqualsSeller() public {
        vm.expectRevert(EscrowStateMachine.BuyerEqualsSeller.selector);
        vm.prank(buyer);
        new EscrowStateMachine(buyer, PRICE);
    }

    function test_RevertWhen_ConstructorPriceIsZero() public {
        vm.expectRevert(EscrowStateMachine.ZeroPrice.selector);
        vm.prank(buyer);
        new EscrowStateMachine(seller, 0);
    }

    function _fund() internal {
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();
    }

    function _fundAndApprove() internal {
        _fund();
        vm.prank(buyer);
        escrow.approveRelease();
    }

    function _assertState(EscrowStateMachine.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }
}
