// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { IPriceOracle } from "../src/oracle/IPriceOracle.sol";
import { MockPriceOracle } from "../src/mocks/MockPriceOracle.sol";
import { PriceConsumer } from "../src/PriceConsumer.sol";
import { VulnerableValuation } from "../src/VulnerableValuation.sol";

contract PriceConsumerTest is Test {
    MockPriceOracle internal oracle;
    PriceConsumer internal consumer;

    uint256 internal constant MAX_AGE = 1 hours;
    int256 internal constant PRICE_8 = 3_000e8;

    function setUp() public {
        vm.warp(1_000_000);
        oracle = new MockPriceOracle(8);
        consumer = new PriceConsumer(IPriceOracle(address(oracle)), MAX_AGE);
        oracle.setPrice(PRICE_8, block.timestamp);
    }

    function test_ReadFreshPositivePrice() public view {
        assertEq(consumer.readPrice(), uint256(PRICE_8));
        assertEq(consumer.priceDecimals(), 8);
        assertEq(consumer.maxAge(), MAX_AGE);
    }

    function test_QuoteOneBaseAssetIntoSixDecimalQuote() public view {
        assertEq(consumer.quote18To6(1 ether), 3_000e6);
    }

    function test_QuoteFractionPreservesExpectedScaling() public view {
        assertEq(consumer.quote18To6(0.25 ether), 750e6);
    }

    function test_EightAndEighteenDecimalFeedsGiveSameEconomicQuote() public {
        MockPriceOracle oracle18 = new MockPriceOracle(18);
        PriceConsumer consumer18 = new PriceConsumer(IPriceOracle(address(oracle18)), MAX_AGE);
        oracle18.setPrice(3_000e18, block.timestamp);

        assertEq(consumer.quote18To6(1 ether), consumer18.quote18To6(1 ether));
    }

    function test_MulDivHandlesOverflowingIntermediateProduct() public {
        oracle.setPrice(type(int256).max, block.timestamp);

        assertEq(consumer.quote18To6(1 ether), uint256(type(int256).max) / 100);
    }

    function test_ExactlyMaxAgeIsAccepted() public {
        uint256 updateTime = block.timestamp;
        vm.warp(updateTime + MAX_AGE);

        assertEq(consumer.readPrice(), uint256(PRICE_8));
    }

    function test_RevertWhen_PriceIsZero() public {
        oracle.setPrice(0, block.timestamp);
        vm.expectRevert(PriceConsumer.InvalidPrice.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_PriceIsNegative() public {
        oracle.setPrice(-1, block.timestamp);
        vm.expectRevert(PriceConsumer.InvalidPrice.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_TimestampIsZero() public {
        oracle.setPrice(PRICE_8, 0);
        vm.expectRevert(PriceConsumer.InvalidTimestamp.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_TimestampIsInFuture() public {
        oracle.setPrice(PRICE_8, block.timestamp + 1);
        vm.expectRevert(PriceConsumer.InvalidTimestamp.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_PriceIsStale() public {
        vm.warp(block.timestamp + MAX_AGE + 1);
        vm.expectRevert(PriceConsumer.StalePrice.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_MaxAgeIsZero() public {
        vm.expectRevert(PriceConsumer.InvalidMaxAge.selector);
        new PriceConsumer(IPriceOracle(address(oracle)), 0);
    }

    function test_RevertWhen_OracleHasNoCode() public {
        address notAContract = makeAddr("not-a-contract");
        vm.expectRevert(abi.encodeWithSelector(PriceConsumer.InvalidOracle.selector, notAContract));
        new PriceConsumer(IPriceOracle(notAContract), MAX_AGE);
    }

    function test_RevertWhen_OracleDecimalsAreUnsupported() public {
        MockPriceOracle unsupported = new MockPriceOracle(19);
        vm.expectRevert(abi.encodeWithSelector(PriceConsumer.UnsupportedDecimals.selector, 19));
        new PriceConsumer(IPriceOracle(address(unsupported)), MAX_AGE);
    }

    /// @dev Il test passa dimostrando che il consumer vulnerabile usa un prezzo scaduto.
    function test_Vulnerable_StalePriceIsStillAccepted() public {
        VulnerableValuation vulnerable = new VulnerableValuation(IPriceOracle(address(oracle)));
        oracle.setPrice(PRICE_8, block.timestamp - MAX_AGE - 1);

        assertEq(vulnerable.valueOf(1), uint256(PRICE_8));
    }

    /// @dev Moltiplicare numeri scalati non produce automaticamente l'unita' desiderata.
    function test_Vulnerable_RawMultiplicationHasWrongUnits() public {
        VulnerableValuation vulnerable = new VulnerableValuation(IPriceOracle(address(oracle)));

        uint256 wrong = vulnerable.valueOf(1 ether);
        uint256 correct = consumer.quote18To6(1 ether);

        assertEq(wrong, 3_000e26);
        assertEq(correct, 3_000e6);
        assertNotEq(wrong, correct);
    }
}

