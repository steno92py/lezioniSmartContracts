// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { LogicBugEscrow } from "../src/LogicBugEscrow.sol";

contract LogicBugEscrowTest is Test {
    LogicBugEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal stranger;

    uint256 internal constant DEPOSIT = 1 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");

        escrow = new LogicBugEscrow(buyer, seller);
        vm.deal(buyer, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    function test_DepositMovesCreatedToFunded() public {
        _fund();

        _assertState(LogicBugEscrow.State.Funded);
        assertEq(escrow.depositedAmount(), DEPOSIT);
    }

    function test_RevertWhen_NonBuyerDeposits() public {
        vm.expectRevert(LogicBugEscrow.OnlyBuyer.selector);
        vm.prank(stranger);
        escrow.deposit{ value: DEPOSIT }();

        _assertState(LogicBugEscrow.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    /// @dev Il test passa perche' rende visibile una transizione semanticamente vietata.
    function test_Vulnerable_CompleteBeforeDepositIsAccepted() public {
        vm.prank(seller);
        escrow.complete();

        _assertState(LogicBugEscrow.State.Created);
        assertEq(escrow.sellerCredit(), 0);
    }

    /// @dev Una singola azione autorizzata puo' essere ripetuta senza reentrancy.
    function test_Vulnerable_CompleteCanCreateUnbackedCredit() public {
        _fund();

        vm.startPrank(seller);
        escrow.complete();
        escrow.complete();
        escrow.complete();
        vm.stopPrank();

        assertEq(escrow.depositedAmount(), DEPOSIT);
        assertEq(escrow.sellerCredit(), 3 * DEPOSIT);
        assertGt(escrow.sellerCredit() + escrow.buyerCredit(), escrow.depositedAmount());
        _assertState(LogicBugEscrow.State.Funded);
    }

    /// @dev Cancelled dovrebbe essere terminale, ma complete() lo ignora.
    function test_Vulnerable_CompleteAfterCancelCreatesConflictingCredits() public {
        _fund();

        vm.prank(buyer);
        escrow.cancel();

        vm.prank(seller);
        escrow.complete();

        _assertState(LogicBugEscrow.State.Cancelled);
        assertEq(escrow.buyerCredit(), DEPOSIT);
        assertEq(escrow.sellerCredit(), DEPOSIT);
        assertEq(escrow.buyerCredit() + escrow.sellerCredit(), 2 * DEPOSIT);
    }

    function _fund() internal {
        vm.prank(buyer);
        escrow.deposit{ value: DEPOSIT }();
    }

    function _assertState(LogicBugEscrow.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }
}

