// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { ToyMultisig } from "../src/governance/ToyMultisig.sol";
import { ToyTimelock } from "../src/governance/ToyTimelock.sol";
import { GovernedEscrow } from "../src/governance/GovernedEscrow.sol";

contract FullGovernanceFlowTest is Test {
    uint256 internal constant DELAY = 2 days;

    address internal alice;
    address internal bob;
    address internal carol;
    address internal executor;

    ToyMultisig internal multisig;
    ToyTimelock internal timelock;
    GovernedEscrow internal escrow;

    function setUp() public {
        vm.warp(1_000_000);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        executor = makeAddr("executor");

        address[] memory signers = new address[](3);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;

        multisig = new ToyMultisig(signers, 2);
        timelock = new ToyTimelock(
            DELAY, address(multisig), executor, makeAddr("canceller"), makeAddr("admin")
        );
        escrow = new GovernedEscrow(address(timelock), makeAddr("pauser"));
    }

    function test_TwoSignersScheduleThenTimelockExecutesAfterDelay() public {
        bytes memory targetData = abi.encodeCall(escrow.setFee, (250));
        bytes32 salt = keccak256("multisig-fee-change");

        _scheduleThroughMultisig(targetData, salt);

        bytes32 operationId =
            timelock.hashOperation(address(escrow), 0, targetData, bytes32(0), salt);
        assertEq(
            uint256(timelock.getOperationState(operationId)),
            uint256(ToyTimelock.OperationState.Waiting)
        );
        assertEq(escrow.feeBps(), 0);

        vm.warp(timelock.readyAt(operationId));
        vm.prank(executor);
        timelock.execute(address(escrow), 0, targetData, bytes32(0), salt);

        assertEq(escrow.feeBps(), 250);
    }

    function _scheduleThroughMultisig(bytes memory targetData, bytes32 salt) internal {
        bytes memory scheduleData = abi.encodeCall(
            timelock.schedule, (address(escrow), 0, targetData, bytes32(0), salt, DELAY)
        );

        vm.prank(alice);
        uint256 transactionId = multisig.submit(address(timelock), 0, scheduleData);
        vm.prank(alice);
        multisig.approve(transactionId);
        vm.prank(bob);
        multisig.approve(transactionId);
        vm.prank(carol);
        multisig.execute(transactionId);
    }
}
