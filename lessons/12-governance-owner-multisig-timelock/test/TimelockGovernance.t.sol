// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { ToyTimelock } from "../src/governance/ToyTimelock.sol";
import { GovernedEscrow } from "../src/governance/GovernedEscrow.sol";
import { MockOracle } from "../src/mocks/GovernanceTargets.sol";

contract TimelockGovernanceTest is Test {
    ToyTimelock internal timelock;
    GovernedEscrow internal escrow;

    address internal proposer;
    address internal executor;
    address internal canceller;
    address internal admin;
    address internal pauser;
    address internal stranger;

    uint256 internal constant DELAY = 2 days;
    bytes32 internal constant NO_PREDECESSOR = bytes32(0);

    function setUp() public {
        vm.warp(1_000_000);
        proposer = makeAddr("proposer");
        executor = makeAddr("executor");
        canceller = makeAddr("canceller");
        admin = makeAddr("admin");
        pauser = makeAddr("emergency-pauser");
        stranger = makeAddr("stranger");

        timelock = new ToyTimelock(DELAY, proposer, executor, canceller, admin);
        escrow = new GovernedEscrow(address(timelock), pauser);
    }

    function test_ProposerCannotBypassTimelockOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(GovernedEscrow.Unauthorized.selector, proposer));
        vm.prank(proposer);
        escrow.setFee(250);
    }

    function test_ScheduledOperationStartsWaiting() public {
        (bytes32 id,,) = _scheduleFee(250, keccak256("fee-waiting"), DELAY);

        assertEq(
            uint256(timelock.getOperationState(id)), uint256(ToyTimelock.OperationState.Waiting)
        );
        assertEq(timelock.readyAt(id), block.timestamp + DELAY);
    }

    function test_RevertWhen_ExecutingBeforeDelay() public {
        bytes32 salt = keccak256("fee-too-early");
        (bytes32 id, bytes memory data,) = _scheduleFee(250, salt, DELAY);
        uint256 readyAt = timelock.readyAt(id);

        vm.warp(readyAt - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ToyTimelock.OperationNotReady.selector, id, readyAt, block.timestamp
            )
        );
        vm.prank(executor);
        timelock.execute(address(escrow), 0, data, NO_PREDECESSOR, salt);

        assertEq(escrow.feeBps(), 0);
    }

    function test_ExecuteExactlyAtDelayBoundary() public {
        bytes32 salt = keccak256("fee-ready");
        (bytes32 id, bytes memory data,) = _scheduleFee(250, salt, DELAY);
        vm.warp(timelock.readyAt(id));

        vm.prank(executor);
        timelock.execute(address(escrow), 0, data, NO_PREDECESSOR, salt);

        assertEq(escrow.feeBps(), 250);
        assertEq(uint256(timelock.getOperationState(id)), uint256(ToyTimelock.OperationState.Done));
    }

    function test_CancelledOperationCannotExecute() public {
        bytes32 salt = keccak256("fee-cancelled");
        (bytes32 id, bytes memory data,) = _scheduleFee(250, salt, DELAY);

        vm.prank(canceller);
        timelock.cancel(id);
        vm.warp(vm.getBlockTimestamp() + DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                ToyTimelock.OperationNotReady.selector, id, 1_000_000 + DELAY, block.timestamp
            )
        );
        vm.prank(executor);
        timelock.execute(address(escrow), 0, data, NO_PREDECESSOR, salt);

        assertEq(
            uint256(timelock.getOperationState(id)), uint256(ToyTimelock.OperationState.Cancelled)
        );
    }

    function test_RevertWhen_NonCancellerCancels() public {
        (bytes32 id,,) = _scheduleFee(250, keccak256("fee-cancel-auth"), DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                ToyTimelock.Unauthorized.selector, stranger, ToyTimelock.Role.Canceller
            )
        );
        vm.prank(stranger);
        timelock.cancel(id);
    }

    function test_RevertWhen_NonProposerSchedules() public {
        bytes memory data = abi.encodeCall(escrow.setFee, (250));

        vm.expectRevert(
            abi.encodeWithSelector(
                ToyTimelock.Unauthorized.selector, stranger, ToyTimelock.Role.Proposer
            )
        );
        vm.prank(stranger);
        timelock.schedule(address(escrow), 0, data, NO_PREDECESSOR, bytes32(0), DELAY);
    }

    function test_RevertWhen_DelayIsBelowMinimum() public {
        bytes memory data = abi.encodeCall(escrow.setFee, (250));
        vm.expectRevert(ToyTimelock.InvalidDelay.selector);
        vm.prank(proposer);
        timelock.schedule(address(escrow), 0, data, NO_PREDECESSOR, bytes32("short"), DELAY - 1);
    }

    function test_UnderlyingFailureLeavesOperationReadyForReview() public {
        bytes32 salt = keccak256("invalid-fee");
        (bytes32 id, bytes memory data,) = _scheduleFee(1_001, salt, DELAY);
        vm.warp(timelock.readyAt(id));
        bytes memory reason = abi.encodeWithSelector(GovernedEscrow.FeeTooHigh.selector, 1_001);

        vm.expectRevert(abi.encodeWithSelector(ToyTimelock.UnderlyingCallFailed.selector, reason));
        vm.prank(executor);
        timelock.execute(address(escrow), 0, data, NO_PREDECESSOR, salt);

        assertEq(uint256(timelock.getOperationState(id)), uint256(ToyTimelock.OperationState.Ready));
        assertEq(escrow.feeBps(), 0);
    }

    function test_PredecessorMustBeDoneBeforeDependentOperation() public {
        bytes32 saltA = keccak256("fee-a");
        (bytes32 idA, bytes memory dataA,) = _scheduleFee(100, saltA, DELAY);
        bytes memory dataB = abi.encodeCall(escrow.setFee, (200));
        bytes32 saltB = keccak256("fee-b");

        vm.prank(proposer);
        bytes32 idB = timelock.schedule(address(escrow), 0, dataB, idA, saltB, DELAY);
        vm.warp(timelock.readyAt(idB));

        vm.expectRevert(abi.encodeWithSelector(ToyTimelock.MissingPredecessor.selector, idA));
        vm.prank(executor);
        timelock.execute(address(escrow), 0, dataB, idA, saltB);

        vm.prank(executor);
        timelock.execute(address(escrow), 0, dataA, NO_PREDECESSOR, saltA);
        vm.prank(executor);
        timelock.execute(address(escrow), 0, dataB, idA, saltB);

        assertEq(escrow.feeBps(), 200);
        assertEq(uint256(timelock.getOperationState(idB)), uint256(ToyTimelock.OperationState.Done));
    }

    function test_OpenExecutorImprovesExecutionLiveness() public {
        ToyTimelock open = new ToyTimelock(DELAY, proposer, address(0), canceller, admin);
        GovernedEscrow openEscrow = new GovernedEscrow(address(open), pauser);
        bytes memory data = abi.encodeCall(openEscrow.setFee, (250));
        bytes32 salt = keccak256("open-executor");

        vm.prank(proposer);
        open.schedule(address(openEscrow), 0, data, NO_PREDECESSOR, salt, DELAY);
        vm.warp(vm.getBlockTimestamp() + DELAY);

        vm.prank(stranger);
        open.execute(address(openEscrow), 0, data, NO_PREDECESSOR, salt);
        assertEq(openEscrow.feeBps(), 250);
    }

    function test_AdminCanGrantProposerButCannotBypassDelay() public {
        vm.prank(admin);
        timelock.setRole(ToyTimelock.Role.Proposer, stranger, true);
        assertTrue(timelock.hasRole(ToyTimelock.Role.Proposer, stranger));

        bytes memory data = abi.encodeCall(escrow.setFee, (250));
        vm.prank(stranger);
        bytes32 id = timelock.schedule(
            address(escrow), 0, data, NO_PREDECESSOR, keccak256("new-proposer"), DELAY
        );
        assertEq(
            uint256(timelock.getOperationState(id)), uint256(ToyTimelock.OperationState.Waiting)
        );
    }

    function test_EmergencyPauserCanStopButCannotReconfigureOrRestart() public {
        vm.prank(pauser);
        escrow.pause();
        assertTrue(escrow.paused());

        vm.expectRevert(abi.encodeWithSelector(GovernedEscrow.Unauthorized.selector, pauser));
        vm.prank(pauser);
        escrow.setFee(250);

        vm.expectRevert(abi.encodeWithSelector(GovernedEscrow.Unauthorized.selector, pauser));
        vm.prank(pauser);
        escrow.unpause();
    }

    function test_PauseBlocksNewActionButPreservesExit() public {
        vm.prank(pauser);
        escrow.pause();

        vm.expectRevert(GovernedEscrow.Paused.selector);
        escrow.sensitiveAction();

        escrow.exit();
        assertEq(escrow.exits(), 1);
    }

    function test_UnpauseMustPassThroughTimelock() public {
        vm.prank(pauser);
        escrow.pause();
        bytes memory data = abi.encodeCall(escrow.unpause, ());
        bytes32 salt = keccak256("slow-unpause");

        vm.prank(proposer);
        bytes32 id = timelock.schedule(address(escrow), 0, data, NO_PREDECESSOR, salt, DELAY);
        vm.warp(timelock.readyAt(id));
        vm.prank(executor);
        timelock.execute(address(escrow), 0, data, NO_PREDECESSOR, salt);

        assertFalse(escrow.paused());
    }

    function test_OracleChangeMustPassThroughTimelock() public {
        MockOracle newOracle = new MockOracle();
        bytes memory data = abi.encodeCall(escrow.setOracle, (address(newOracle)));
        bytes32 salt = keccak256("oracle-change");

        vm.prank(proposer);
        bytes32 id = timelock.schedule(address(escrow), 0, data, NO_PREDECESSOR, salt, DELAY);
        vm.warp(timelock.readyAt(id));
        vm.prank(executor);
        timelock.execute(address(escrow), 0, data, NO_PREDECESSOR, salt);

        assertEq(escrow.oracle(), address(newOracle));
    }

    function _scheduleFee(uint256 fee, bytes32 salt, uint256 delay)
        internal
        returns (bytes32 id, bytes memory data, uint256 readyAt)
    {
        data = abi.encodeCall(escrow.setFee, (fee));
        vm.prank(proposer);
        id = timelock.schedule(address(escrow), 0, data, NO_PREDECESSOR, salt, delay);
        readyAt = timelock.readyAt(id);
    }
}

