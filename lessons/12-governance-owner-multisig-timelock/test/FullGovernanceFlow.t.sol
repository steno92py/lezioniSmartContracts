// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Il flusso completo, con tre livelli di call annidate:
//
//   alice + bob approvano, carol esegue
//        |
//        v
//   ToyMultisig.execute --call--> ToyTimelock.schedule     (msg.sender = multisig = proposer)
//                                        ... 48h ...
//   executor --> ToyTimelock.execute --call--> GovernedEscrow.setFee
//                                              (msg.sender = timelock = owner)
//
// Cheatcode: vm.warp(t) imposta block.timestamp = t; vm.prank(a) fa da msg.sender a.
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

        // Ordine dei deploy = ordine del grafo: multisig -> timelock (proposer = multisig)
        // -> escrow (owner = timelock).
        multisig = new ToyMultisig(signers, 2);
        timelock = new ToyTimelock(
            DELAY, address(multisig), executor, makeAddr("canceller"), makeAddr("admin")
        );
        escrow = new GovernedEscrow(address(timelock), makeAddr("pauser"));
    }

    function test_TwoSignersScheduleThenTimelockExecutesAfterDelay() public {
        // La calldata che alla fine arrivera' all'escrow: setFee(250).
        bytes memory targetData = abi.encodeCall(escrow.setFee, (250));
        bytes32 salt = keccak256("multisig-fee-change");

        // 1. Il multisig approva e schedula.
        _scheduleThroughMultisig(targetData, salt);

        // 2. L'operazione e' in attesa e la fee non e' ancora cambiata.
        bytes32 operationId =
            timelock.hashOperation(address(escrow), 0, targetData, bytes32(0), salt);
        // Gli enum non si confrontano direttamente con assertEq: si convertono in uint256.
        assertEq(
            uint256(timelock.getOperationState(operationId)),
            uint256(ToyTimelock.OperationState.Waiting)
        );
        assertEq(escrow.feeBps(), 0);

        // 3. Passato il delay, l'executor esegue con gli STESSI parametri schedulati.
        vm.warp(timelock.readyAt(operationId));
        vm.prank(executor);
        timelock.execute(address(escrow), 0, targetData, bytes32(0), salt);

        assertEq(escrow.feeBps(), 250);
    }

    function _scheduleThroughMultisig(bytes memory targetData, bytes32 salt) internal {
        // Calldata annidata: il multisig chiamera' timelock.schedule, che a sua volta porta
        // dentro la calldata destinata all'escrow.
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
