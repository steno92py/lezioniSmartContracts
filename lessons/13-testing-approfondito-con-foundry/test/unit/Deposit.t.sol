// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract DepositTest is EscrowTestBase {
    event Deposited(address indexed buyer, uint256 amount, int256 price);

    function test_BuyerCanDepositAndStateDeltaIsCorrect() public {
        uint256 amount = 100 ether;
        uint256 buyerBefore = token.balanceOf(buyer);

        _approveAndDeposit(amount);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Funded));
        assertEq(escrow.depositedAmount(), amount);
        assertEq(escrow.liability(), amount);
        assertEq(escrow.depositPrice(), FRESH_PRICE);
        assertEq(token.balanceOf(buyer), buyerBefore - amount);
        assertEq(token.balanceOf(address(escrow)), amount);
    }

    function test_DepositEmitsEventAndPersistsMatchingState() public {
        uint256 amount = 100 ether;
        _approve(amount);

        vm.expectEmit(true, false, false, true, address(escrow));
        emit Deposited(buyer, amount, FRESH_PRICE);
        vm.prank(buyer);
        escrow.deposit(amount);

        assertEq(escrow.depositedAmount(), amount);
    }

    function test_StrangerCannotDepositAndStateIsUnchanged() public {
        uint256 escrowBefore = token.balanceOf(address(escrow));

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.deposit(100 ether);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.depositedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), escrowBefore);
    }

    function test_ZeroDepositRevertsWithPreciseError() public {
        vm.expectRevert(TestingEscrow.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.deposit(0);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
    }

    function test_CannotDepositTwice() public {
        _approveAndDeposit(100 ether);
        _approve(1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                TestingEscrow.InvalidState.selector, TestingEscrow.State.Created, TestingEscrow.State.Funded
            )
        );
        vm.prank(buyer);
        escrow.deposit(1 ether);

        assertEq(escrow.depositedAmount(), 100 ether);
    }

    function test_PreconditionOrderChecksCallerBeforeAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.deposit(0);
    }
}

