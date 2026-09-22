// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {RemediatedEscrow} from "../../src/fixed/RemediatedEscrow.sol";
import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../../src/interfaces/IAuditDependencies.sol";
import {MockToken, FeeToken, ReentrantToken, MockOracle, RevertingNotifier} from "../../src/mocks/AuditMocks.sol";

contract RemediationRetestTest is Test {
    uint256 internal constant AMOUNT = 100 ether;
    uint256 internal constant MIN_PRICE = 100e8;
    uint256 internal constant MAX_AGE = 1 hours;

    address internal buyer;
    address internal seller;
    address internal governance;
    address internal guardian;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        governance = makeAddr("governance");
        guardian = makeAddr("guardian");
        vm.warp(1_000_000);
    }

    function test_Regression_AUD01_ReentrantCallbackCannotPayTwice() public {
        ReentrantToken token = new ReentrantToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RemediatedEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));
        _fundAndDeposit(token, escrow);
        token.mint(address(escrow), AMOUNT);
        token.configure(address(escrow));

        escrow.release();

        assertTrue(token.callbackAttempted());
        assertFalse(token.callbackSucceeded());
        assertEq(token.balanceOf(seller), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), AMOUNT, "la riserva non viene drenata");
    }

    function test_Regression_AUD02_FeeTokenRejectedAtomically() public {
        FeeToken token = new FeeToken(1_000);
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RemediatedEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));
        token.mint(buyer, AMOUNT);

        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(RemediatedEscrow.UnsupportedTransferTax.selector, AMOUNT, 90 ether));
        escrow.deposit(AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(buyer), AMOUNT, "il revert ripristina anche il token");
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.liability(), 0);
    }

    function test_Regression_AUD03_GuardianCannotSetOracle() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        MockOracle replacement = new MockOracle(int256(MIN_PRICE * 2), block.timestamp);
        RemediatedEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));

        vm.prank(guardian);
        vm.expectRevert(RemediatedEscrow.WrongCaller.selector);
        escrow.setOracle(replacement);

        assertEq(address(escrow.oracle()), address(oracle));
    }

    function test_Regression_AUD04_ExactStalenessBoundaryRejected() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp - MAX_AGE);
        RemediatedEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));
        _fundAndDeposit(token, escrow);

        vm.expectRevert(RemediatedEscrow.StalePrice.selector);
        escrow.release();
    }

    function test_Regression_OBS01_NotifierFailureDoesNotBlockSettlement() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RevertingNotifier notifier = new RevertingNotifier();
        RemediatedEscrow escrow = _deploy(token, oracle, notifier);
        _fundAndDeposit(token, escrow);

        escrow.release();

        assertEq(uint256(escrow.state()), uint256(RemediatedEscrow.State.Released));
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function testFuzz_AssetsAlwaysEqualLiabilityImmediatelyAfterDeposit(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, type(uint96).max);
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RemediatedEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));
        token.mint(buyer, amount);

        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();

        assertEq(token.balanceOf(address(escrow)), escrow.liability());
        assertEq(escrow.liability(), amount);
    }

    function test_RefundIsTerminalAndRestoresBuyerFunds() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RemediatedEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));
        _fundAndDeposit(token, escrow);

        vm.prank(buyer);
        escrow.refund();

        assertEq(token.balanceOf(buyer), AMOUNT);
        assertEq(escrow.liability(), 0);
        vm.expectRevert(RemediatedEscrow.WrongState.selector);
        escrow.release();
    }

    function _deploy(IAuditToken token, IPriceOracle oracle, ISettlementNotifier notifier)
        internal
        returns (RemediatedEscrow)
    {
        return new RemediatedEscrow(buyer, seller, governance, guardian, token, oracle, notifier, MIN_PRICE, MAX_AGE);
    }

    function _fundAndDeposit(MockToken token, RemediatedEscrow escrow) internal {
        token.mint(buyer, AMOUNT);
        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        vm.stopPrank();
    }
}

