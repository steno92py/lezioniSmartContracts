// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {AuditEscrow} from "../../src/target/AuditEscrow.sol";
import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../../src/interfaces/IAuditDependencies.sol";
import {
    MockToken,
    FeeToken,
    ReentrantToken,
    MockOracle,
    RecordingNotifier,
    RevertingNotifier
} from "../../src/mocks/AuditMocks.sol";

contract AuditEscrowFindingsTest is Test {
    uint256 internal constant AMOUNT = 100 ether;
    uint256 internal constant MIN_PRICE = 100e8;
    uint256 internal constant MAX_AGE = 1 hours;

    address internal buyer;
    address internal seller;
    address internal governance;
    address internal guardian;
    address internal stranger;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        governance = makeAddr("governance");
        guardian = makeAddr("guardian");
        stranger = makeAddr("stranger");
        vm.warp(1_000_000);
    }

    function test_Baseline_HappyPathWorks() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RecordingNotifier notifier = new RecordingNotifier();
        AuditEscrow escrow = _deploy(token, oracle, notifier);
        _fundAndDeposit(token, escrow);

        vm.prank(stranger);
        escrow.release();

        assertEq(token.balanceOf(seller), AMOUNT);
        assertEq(escrow.liability(), 0);
        assertEq(uint256(escrow.state()), uint256(AuditEscrow.State.Released));
        assertEq(notifier.calls(), 1);
    }

    function test_AUD01_ReentrantTokenPaysSameLiabilityTwice() public {
        ReentrantToken token = new ReentrantToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        AuditEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));

        _fundAndDeposit(token, escrow);
        token.mint(address(escrow), AMOUNT); // riserva di un altro utente/protocollo
        token.configure(address(escrow));

        escrow.release();

        assertTrue(token.callbackAttempted());
        assertTrue(token.callbackSucceeded());
        assertEq(token.balanceOf(seller), AMOUNT * 2, "stessa liability pagata due volte");
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_AUD02_FeeTokenCreatesInsolventNominalLiability() public {
        FeeToken token = new FeeToken(1_000); // 10%
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        AuditEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));

        _fundAndDeposit(token, escrow);

        assertEq(escrow.liability(), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertLt(token.balanceOf(address(escrow)), escrow.liability());

        vm.expectRevert(MockToken.InsufficientBalance.selector);
        escrow.release();
    }

    function test_AUD03_GuardianCanBypassGovernanceAndForceSettlement() public {
        MockToken token = new MockToken();
        MockOracle lowOracle = new MockOracle(int256(MIN_PRICE - 1), block.timestamp);
        MockOracle manipulatedOracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        AuditEscrow escrow = _deploy(token, lowOracle, ISettlementNotifier(address(0)));
        _fundAndDeposit(token, escrow);

        vm.prank(guardian);
        escrow.setOracle(manipulatedOracle);

        vm.prank(stranger);
        escrow.release();
        assertEq(token.balanceOf(seller), AMOUNT, "guardian ha anticipato il settlement");
    }

    function test_AUD04_ExactStalenessBoundaryIsAccepted() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp - MAX_AGE);
        AuditEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));
        _fundAndDeposit(token, escrow);

        escrow.release();

        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_OBS01_RevertingOptionalNotifierBlocksSettlement() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RevertingNotifier notifier = new RevertingNotifier();
        AuditEscrow escrow = _deploy(token, oracle, notifier);
        _fundAndDeposit(token, escrow);

        vm.expectRevert(RevertingNotifier.NotificationUnavailable.selector);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(AuditEscrow.State.Funded));
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
    }

    function _deploy(IAuditToken token, IPriceOracle oracle, ISettlementNotifier notifier)
        internal
        returns (AuditEscrow)
    {
        return new AuditEscrow(buyer, seller, governance, guardian, token, oracle, notifier, MIN_PRICE, MAX_AGE);
    }

    function _fundAndDeposit(MockToken token, AuditEscrow escrow) internal {
        token.mint(buyer, AMOUNT);
        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        vm.stopPrank();
    }
}

