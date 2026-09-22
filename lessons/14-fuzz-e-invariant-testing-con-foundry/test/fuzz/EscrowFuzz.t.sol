// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {SimpleEscrow} from "../../src/fuzz/FuzzTargets.sol";

contract EscrowFuzzTest is Test {
    SimpleEscrow internal escrow;
    address internal buyer;

    function setUp() public {
        buyer = makeAddr("buyer");
        escrow = new SimpleEscrow(buyer);
    }

    function testFuzz_DepositRecordsEveryValidAmount(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, type(uint128).max);

        vm.prank(buyer);
        escrow.deposit(amount);

        assertEq(escrow.escrowedAmount(), amount);
        assertTrue(escrow.funded());
    }

    function testFuzz_NonBuyerCannotDeposit(address caller, uint256 rawAmount) public {
        vm.assume(caller != buyer);
        vm.assume(caller != address(0));
        uint256 amount = bound(rawAmount, 1, type(uint128).max);

        vm.expectRevert(abi.encodeWithSelector(SimpleEscrow.OnlyBuyer.selector, caller));
        vm.prank(caller);
        escrow.deposit(amount);

        assertFalse(escrow.funded());
        assertEq(escrow.escrowedAmount(), 0);
    }

    function testFuzz_AuthorizationCheckPrecedesAmountValidation(address caller) public {
        vm.assume(caller != buyer);
        vm.assume(caller != address(0));

        vm.expectRevert(abi.encodeWithSelector(SimpleEscrow.OnlyBuyer.selector, caller));
        vm.prank(caller);
        escrow.deposit(0);
    }

    function testFuzz_SecondDepositAlwaysFails(uint128 firstAmount, uint128 secondAmount) public {
        uint256 first = bound(firstAmount, 1, type(uint128).max);
        uint256 second = bound(secondAmount, 1, type(uint128).max);
        vm.prank(buyer);
        escrow.deposit(first);

        vm.expectRevert(SimpleEscrow.AlreadyFunded.selector);
        vm.prank(buyer);
        escrow.deposit(second);

        assertEq(escrow.escrowedAmount(), first);
    }

    function test_Regression_ZeroDepositUsesExactError() public {
        vm.expectRevert(SimpleEscrow.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.deposit(0);
    }
}

