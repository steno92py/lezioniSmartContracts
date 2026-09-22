// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract TokenBehaviorRegressionTest is EscrowTestBase {
    function test_Regression_FalseReturnCannotCreateDepositCredit() public {
        uint256 amount = 100 ether;
        token.configure(0, true, false);
        _approve(amount);

        vm.expectRevert(TestingEscrow.TokenCallFailed.selector);
        vm.prank(buyer);
        escrow.deposit(amount);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.depositedAmount(), 0);
        assertEq(token.balanceOf(buyer), BUYER_BALANCE);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_Regression_FeeOnTransferCannotCreateUnbackedLiability() public {
        uint256 amount = 100 ether;
        token.configure(100, true, true);
        _approve(amount);

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.UnexpectedReceived.selector, amount, 99 ether));
        vm.prank(buyer);
        escrow.deposit(amount);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.liability(), 0);
        assertEq(token.balanceOf(buyer), BUYER_BALANCE);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_Regression_FailedPayoutRollsBackTerminalState() public {
        uint256 amount = 100 ether;
        _approveAndDeposit(amount);
        token.configure(0, false, true);

        vm.expectRevert(TestingEscrow.TokenCallFailed.selector);
        vm.prank(buyer);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Funded));
        assertEq(escrow.depositedAmount(), amount);
        assertEq(escrow.liability(), amount);
        assertEq(token.balanceOf(address(escrow)), amount);
        assertEq(token.balanceOf(seller), 0);
    }

    function test_Regression_FailedRefundRollsBackAccounting() public {
        uint256 amount = 100 ether;
        _approveAndDeposit(amount);
        token.configure(0, false, true);
        vm.warp(escrow.refundDeadline());

        vm.expectRevert(TestingEscrow.TokenCallFailed.selector);
        vm.prank(buyer);
        escrow.refund();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Funded));
        assertEq(escrow.liability(), amount);
        assertEq(token.balanceOf(address(escrow)), amount);
    }
}

