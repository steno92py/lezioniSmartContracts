// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Vm} from "forge-std/Vm.sol";
import {FinalTestBase} from "../helpers/FinalTestBase.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {SafeERC20Lite} from "../../src/libraries/SafeERC20Lite.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {TestToken, FeeToken, FalsePayoutToken, MockOracle, RevertingNotifier} from "../../src/mocks/FinalMocks.sol";

contract FixedRegressionTest is FinalTestBase {
    function test_BuyerCanDeposit() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        _fundFixed(token, escrow, AMOUNT);
        assertEq(escrow.escrowedAmount(), AMOUNT);
        assertEq(uint256(escrow.state()), uint256(EscrowFinalFixed.State.Funded));
    }

    function test_StrangerCannotDeposit() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        token.mint(stranger, AMOUNT);
        vm.startPrank(stranger);
        token.approve(address(escrow), AMOUNT);
        vm.expectRevert(EscrowFinalFixed.OnlyBuyer.selector);
        escrow.deposit(AMOUNT);
        vm.stopPrank();
    }

    function test_ZeroDepositReverts() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(buyer);
        vm.expectRevert(EscrowFinalFixed.ZeroAmount.selector);
        escrow.deposit(0);
    }

    function test_DoubleDepositReverts() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        _fundFixed(token, escrow, AMOUNT);
        vm.prank(buyer);
        vm.expectRevert(EscrowFinalFixed.InvalidState.selector);
        escrow.deposit(1);
    }

    function test_F01_DepositUsesActualReceived() public {
        FeeToken token = new FeeToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertEq(escrow.escrowedAmount(), 90 ether);
    }

    function test_F02_StaleOracleRejected() public {
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - 1 hours - 1);
        EscrowFinalFixed escrow = _fixed(token, oracle, INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        vm.prank(buyer);
        vm.expectRevert(EscrowFinalFixed.StalePrice.selector);
        escrow.release();
    }

    function test_F02_ExactMaxAgeAccepted() public {
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - 1 hours);
        EscrowFinalFixed escrow = _fixed(token, oracle, INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        vm.prank(buyer);
        escrow.release();
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_F03_FalseReturnTransferCannotFinalize() public {
        FalsePayoutToken token = new FalsePayoutToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20Lite.SafeTransferFailed.selector, address(token)));
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(EscrowFinalFixed.State.Funded));
        assertEq(escrow.escrowedAmount(), AMOUNT);
    }

    function test_F04_StrangerCannotReplaceOracle() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        MockOracle replacement = _freshOracle();
        vm.prank(stranger);
        vm.expectRevert(EscrowFinalFixed.OnlyOwner.selector);
        escrow.setOracle(replacement);
        token; // mantiene esplicito il setup standard.
    }

    function test_F05_NotifierFailureDoesNotBlockReleaseAndIsObservable() public {
        TestToken token = new TestToken();
        RevertingNotifier notifier = new RevertingNotifier();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), notifier);
        _fundFixed(token, escrow, AMOUNT);

        vm.recordLogs();
        vm.prank(buyer);
        escrow.release();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 failureTopic = keccak256("NotificationFailed(bytes)");
        bool found;
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].topics[0] == failureTopic) found = true;
        }
        assertTrue(found, "notification failure deve essere osservabile");
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_ReleaseClearsLiability() public {
        (TestToken token, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.prank(buyer);
        escrow.release();
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_RefundClearsLiability() public {
        (TestToken token, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.prank(buyer);
        escrow.refund();
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(buyer), AMOUNT);
    }

    function test_DoubleReleaseReverts() public {
        (, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.startPrank(buyer);
        escrow.release();
        vm.expectRevert(EscrowFinalFixed.InvalidState.selector);
        escrow.release();
        vm.stopPrank();
    }

    function test_RefundAfterReleaseReverts() public {
        (, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.startPrank(buyer);
        escrow.release();
        vm.expectRevert(EscrowFinalFixed.InvalidState.selector);
        escrow.refund();
        vm.stopPrank();
    }

    function test_OnlyPauserCanPause() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(stranger);
        vm.expectRevert(EscrowFinalFixed.OnlyPauser.selector);
        escrow.pause();
        vm.prank(pauser);
        escrow.pause();
        assertTrue(escrow.paused());
    }

    function test_OnlyOwnerCanUnpause() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(pauser);
        escrow.pause();
        vm.prank(stranger);
        vm.expectRevert(EscrowFinalFixed.OnlyOwner.selector);
        escrow.unpause();
        vm.prank(owner);
        escrow.unpause();
        assertFalse(escrow.paused());
    }

    function test_FeeUpperBound() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(owner);
        escrow.setFee(1_000);
        assertEq(escrow.feeBps(), 1_000);
        vm.prank(owner);
        vm.expectRevert(EscrowFinalFixed.FeeTooHigh.selector);
        escrow.setFee(1_001);
    }

    function test_RefundRemainsAvailableWhilePaused() public {
        (TestToken token, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.prank(pauser);
        escrow.pause();
        vm.prank(buyer);
        escrow.refund();
        assertEq(token.balanceOf(buyer), AMOUNT, "pause new risk, allow exit");
    }

    function _standardEscrow() internal returns (TestToken token, EscrowFinalFixed escrow) {
        token = new TestToken();
        escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
    }

    function _fundedStandardEscrow() internal returns (TestToken token, EscrowFinalFixed escrow) {
        (token, escrow) = _standardEscrow();
        _fundFixed(token, escrow, AMOUNT);
    }
}

