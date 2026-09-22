// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {FeeCalculator} from "../../src/fuzz/FuzzTargets.sol";

contract FeeMathFuzzTest is Test {
    FeeCalculator internal calculator;

    function setUp() public {
        calculator = new FeeCalculator();
    }

    function testFuzz_FeeNeverExceedsAmount(uint256 rawAmount, uint256 rawFeeBps) public view {
        uint256 amount = bound(rawAmount, 0, type(uint128).max);
        uint256 feeBps = bound(rawFeeBps, 0, calculator.MAX_FEE_BPS());

        uint256 result = calculator.fee(amount, feeBps);

        assertLe(result, amount);
    }

    function testFuzz_ValidFeeRangeIsAccepted(uint256 rawFeeBps) public view {
        uint256 feeBps = bound(rawFeeBps, 0, calculator.MAX_FEE_BPS());
        calculator.fee(100 ether, feeBps);
    }

    function testFuzz_InvalidFeeRangeIsRejected(uint256 rawFeeBps) public {
        uint256 feeBps = bound(rawFeeBps, calculator.MAX_FEE_BPS() + 1, type(uint16).max);

        vm.expectRevert(abi.encodeWithSelector(FeeCalculator.FeeTooHigh.selector, feeBps));
        calculator.fee(100 ether, feeBps);
    }

    function testFuzz_FeeIsMonotonicInAmount(uint128 a, uint128 b, uint16 rawFeeBps) public view {
        uint256 x = uint256(a);
        uint256 y = uint256(b);
        if (x > y) (x, y) = (y, x);
        uint256 feeBps = bound(rawFeeBps, 0, calculator.MAX_FEE_BPS());

        assertLe(calculator.fee(x, feeBps), calculator.fee(y, feeBps));
    }

    function testFuzz_QuoteIsMonotonicWithoutDiscardingPairs(uint128 a, uint128 b, uint128 price) public view {
        uint256 x = uint256(a);
        uint256 y = uint256(b);
        if (x > y) (x, y) = (y, x);

        assertLe(calculator.quote(x, price), calculator.quote(y, price));
    }
}

