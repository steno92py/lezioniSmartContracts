// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {ITestOracle} from "../../src/interfaces/ITestDependencies.sol";
import {MockOracle} from "../../src/mocks/TestingMocks.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract OracleIntegrationTest is EscrowTestBase {
    function test_PriceExactlyAtFreshnessBoundaryIsAccepted() public {
        oracle.setAnswer(FRESH_PRICE, block.timestamp - escrow.MAX_PRICE_AGE());

        _approveAndDeposit(100 ether);

        assertEq(escrow.depositPrice(), FRESH_PRICE);
    }

    function test_PriceOneSecondPastFreshnessBoundaryIsRejected() public {
        uint256 updatedAt = block.timestamp - escrow.MAX_PRICE_AGE() - 1;
        oracle.setAnswer(FRESH_PRICE, updatedAt);
        _approve(100 ether);

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.StalePrice.selector, updatedAt, block.timestamp));
        vm.prank(buyer);
        escrow.deposit(100 ether);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
    }

    function test_ZeroAndNegativePricesAreRejected() public {
        oracle.setAnswer(0, block.timestamp);
        _approve(100 ether);
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.InvalidPrice.selector, 0));
        vm.prank(buyer);
        escrow.deposit(100 ether);

        oracle.setAnswer(-1, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.InvalidPrice.selector, -1));
        vm.prank(buyer);
        escrow.deposit(100 ether);
    }

    function test_FutureOracleTimestampIsRejected() public {
        uint256 future = block.timestamp + 1;
        oracle.setAnswer(FRESH_PRICE, future);
        _approve(100 ether);

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.InvalidOracleTimestamp.selector, future, block.timestamp));
        vm.prank(buyer);
        escrow.deposit(100 ether);
    }

    function test_RevertingDependencyPropagatesAndPreservesState() public {
        oracle.setShouldRevert(true);
        _approve(100 ether);

        vm.expectRevert(MockOracle.OracleUnavailable.selector);
        vm.prank(buyer);
        escrow.deposit(100 ether);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_MockCallCanIsolateOracleReturnValue() public {
        int256 mockedPrice = 4_200e8;
        bytes memory callData = abi.encodeCall(ITestOracle.latestPrice, ());
        vm.mockCall(address(oracle), callData, abi.encode(mockedPrice, block.timestamp));
        vm.expectCall(address(oracle), callData);

        _approveAndDeposit(100 ether);

        assertEq(escrow.depositPrice(), mockedPrice);
    }
}

