// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {LifecycleEscrow} from "../../src/invariant/LifecycleEscrow.sol";

contract LifecycleNegativeFuzzTest is Test {
    uint256 internal constant START = 1_000_000;
    uint256 internal constant DELAY = 7 days;

    LifecycleEscrow internal escrow;
    address internal buyer;

    function setUp() public {
        vm.warp(START);
        buyer = makeAddr("buyer");
        escrow = new LifecycleEscrow(buyer, block.timestamp + DELAY);
    }

    function testFuzz_UnauthorizedCallerCannotFund(address caller, uint128 rawAmount) public {
        vm.assume(caller != buyer && caller != address(0));
        uint256 amount = bound(rawAmount, 1, type(uint128).max);

        vm.expectRevert(abi.encodeWithSelector(LifecycleEscrow.Unauthorized.selector, caller));
        vm.prank(caller);
        escrow.fund(amount);

        assertEq(uint256(escrow.state()), uint256(LifecycleEscrow.State.Created));
        assertEq(escrow.amount(), 0);
    }

    function testFuzz_UnauthorizedCallerCannotRelease(address caller) public {
        vm.assume(caller != buyer && caller != address(0));
        vm.prank(buyer);
        escrow.fund(100 ether);

        vm.expectRevert(abi.encodeWithSelector(LifecycleEscrow.Unauthorized.selector, caller));
        vm.prank(caller);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(LifecycleEscrow.State.Funded));
        assertEq(escrow.amount(), 100 ether);
    }

    function testFuzz_RefundBeforeDeadlineAlwaysReverts(uint256 rawSecondsBefore) public {
        vm.prank(buyer);
        escrow.fund(100 ether);
        uint256 secondsBefore = bound(rawSecondsBefore, 1, DELAY);
        vm.warp(escrow.refundDeadline() - secondsBefore);

        vm.expectRevert(
            abi.encodeWithSelector(LifecycleEscrow.TooEarly.selector, escrow.refundDeadline(), block.timestamp)
        );
        vm.prank(buyer);
        escrow.refund();
    }

    function testFuzz_TerminalStateCannotBeFundedAgain(uint128 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, type(uint128).max);
        vm.startPrank(buyer);
        escrow.fund(100 ether);
        escrow.release();

        vm.expectRevert(
            abi.encodeWithSelector(
                LifecycleEscrow.InvalidState.selector, LifecycleEscrow.State.Created, LifecycleEscrow.State.Released
            )
        );
        escrow.fund(amount);
        vm.stopPrank();

        assertEq(uint256(escrow.state()), uint256(LifecycleEscrow.State.Released));
        assertEq(escrow.amount(), 0);
    }

    function test_Regression_ZeroFundingIsRejected() public {
        vm.expectRevert(LifecycleEscrow.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.fund(0);
    }

    function test_Regression_ReleaseFromCreatedIsRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LifecycleEscrow.InvalidState.selector, LifecycleEscrow.State.Funded, LifecycleEscrow.State.Created
            )
        );
        vm.prank(buyer);
        escrow.release();
    }

    function test_Regression_ZeroBuyerConfigurationIsRejected() public {
        vm.expectRevert(LifecycleEscrow.ZeroAddress.selector);
        new LifecycleEscrow(address(0), block.timestamp + DELAY);
    }
}

