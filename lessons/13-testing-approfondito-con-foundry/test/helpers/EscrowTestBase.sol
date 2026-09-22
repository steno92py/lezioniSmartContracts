// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {ConfigurableToken, MockOracle} from "../../src/mocks/TestingMocks.sol";

abstract contract EscrowTestBase is Test {
    uint256 internal constant START_TIME = 1_000_000;
    uint256 internal constant REFUND_DELAY = 7 days;
    uint256 internal constant BUYER_BALANCE = 10_000 ether;
    int256 internal constant FRESH_PRICE = 3_000e8;

    ConfigurableToken internal token;
    MockOracle internal oracle;
    TestingEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal owner;
    address internal stranger;

    function setUp() public virtual {
        vm.warp(START_TIME);
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        owner = makeAddr("owner");
        stranger = makeAddr("stranger");

        token = new ConfigurableToken();
        oracle = new MockOracle();
        oracle.setAnswer(FRESH_PRICE, block.timestamp);
        escrow =
            new TestingEscrow(address(token), address(oracle), buyer, seller, owner, block.timestamp + REFUND_DELAY);
        token.mint(buyer, BUYER_BALANCE);
    }

    function _approveAndDeposit(uint256 amount) internal {
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
    }

    function _approve(uint256 amount) internal {
        vm.prank(buyer);
        token.approve(address(escrow), amount);
    }
}

