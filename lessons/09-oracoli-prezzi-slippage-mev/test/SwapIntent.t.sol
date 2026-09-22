// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { MockSwap } from "../src/mocks/MockSwap.sol";
import { ISwap } from "../src/swap/ISwap.sol";
import { BadSwapConsumer } from "../src/swap/BadSwapConsumer.sol";
import { SafeSwapIntent } from "../src/swap/SafeSwapIntent.sol";

contract SwapIntentTest is Test {
    MockSwap internal dex;
    BadSwapConsumer internal vulnerable;
    SafeSwapIntent internal safeIntent;

    uint256 internal constant AMOUNT_IN = 100 ether;
    uint256 internal constant MIN_OUT = 190 ether;

    function setUp() public {
        vm.warp(1_000_000);
        dex = new MockSwap();
        vulnerable = new BadSwapConsumer(ISwap(address(dex)));
        safeIntent = new SafeSwapIntent(ISwap(address(dex)));
    }

    function test_SwapWithinBounds() public view {
        uint256 output = safeIntent.execute(AMOUNT_IN, MIN_OUT, block.timestamp + 5 minutes);
        assertEq(output, 200 ether);
    }

    function test_ExactMinimumOutputIsAccepted() public {
        dex.setRate(1.9e18);
        uint256 output = safeIntent.execute(AMOUNT_IN, MIN_OUT, block.timestamp + 5 minutes);
        assertEq(output, MIN_OUT);
    }

    function test_RevertWhen_RateFallsBelowMinimum() public {
        dex.setRate(1e18);
        vm.expectRevert(
            abi.encodeWithSelector(MockSwap.SlippageExceeded.selector, MIN_OUT, 100 ether)
        );
        safeIntent.execute(AMOUNT_IN, MIN_OUT, block.timestamp + 5 minutes);
    }

    function test_DeadlineMinusOneIsAccepted() public {
        uint256 deadline = vm.getBlockTimestamp() + 10;
        vm.warp(deadline - 1);
        assertEq(safeIntent.execute(AMOUNT_IN, MIN_OUT, deadline), 200 ether);
    }

    function test_ExactDeadlineIsAccepted() public {
        uint256 deadline = vm.getBlockTimestamp() + 10;
        vm.warp(deadline);
        assertEq(safeIntent.execute(AMOUNT_IN, MIN_OUT, deadline), 200 ether);
    }

    function test_RevertWhen_DeadlineHasPassed() public {
        uint256 deadline = vm.getBlockTimestamp() + 10;
        vm.warp(deadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(SafeSwapIntent.Expired.selector, deadline, block.timestamp)
        );
        safeIntent.execute(AMOUNT_IN, MIN_OUT, deadline);
    }

    function test_RevertWhen_AmountInIsZero() public {
        vm.expectRevert(SafeSwapIntent.ZeroAmountIn.selector);
        safeIntent.execute(0, MIN_OUT, block.timestamp + 1);
    }

    function test_RevertWhen_MinimumOutputIsZero() public {
        vm.expectRevert(SafeSwapIntent.ZeroMinimumOutput.selector);
        safeIntent.execute(AMOUNT_IN, 0, block.timestamp + 1);
    }

    function test_RevertWhen_SwapperHasNoCode() public {
        address notAContract = makeAddr("not-a-contract");
        vm.expectRevert(
            abi.encodeWithSelector(SafeSwapIntent.InvalidSwapper.selector, notAContract)
        );
        new SafeSwapIntent(ISwap(notAContract));
    }

    /// @dev Il test passa: minOut zero accetta un output economicamente disastroso.
    function test_Vulnerable_AcceptsNearZeroOutputAfterRateChange() public {
        uint256 quoteBefore = dex.quote(AMOUNT_IN);
        dex.setRate(0.01e18);

        uint256 executedOutput = vulnerable.execute(AMOUNT_IN);

        assertEq(quoteBefore, 200 ether);
        assertEq(executedOutput, 1 ether);
    }

    function test_SafeIntentRejectsSameAdverseOrderingScenario() public {
        assertEq(dex.quote(AMOUNT_IN), 200 ether);
        dex.setRate(0.01e18);

        vm.expectRevert(
            abi.encodeWithSelector(MockSwap.SlippageExceeded.selector, MIN_OUT, 1 ether)
        );
        safeIntent.execute(AMOUNT_IN, MIN_OUT, block.timestamp + 5 minutes);
    }
}
