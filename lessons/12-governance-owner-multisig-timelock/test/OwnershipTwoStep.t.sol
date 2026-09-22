// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { GovernedEscrow } from "../src/governance/GovernedEscrow.sol";

contract OwnershipTwoStepTest is Test {
    address internal owner;
    address internal candidate;
    address internal stranger;
    GovernedEscrow internal escrow;

    function setUp() public {
        owner = makeAddr("owner");
        candidate = makeAddr("candidate");
        stranger = makeAddr("stranger");
        escrow = new GovernedEscrow(owner, makeAddr("pauser"));
    }

    function test_CandidateMustAcceptOwnership() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        assertEq(escrow.owner(), owner);
        assertEq(escrow.pendingOwner(), candidate);

        vm.prank(candidate);
        escrow.acceptOwnership();

        assertEq(escrow.owner(), candidate);
        assertEq(escrow.pendingOwner(), address(0));
    }

    function test_CurrentOwnerRetainsAuthorityUntilAcceptance() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.prank(owner);
        escrow.setFee(100);
        assertEq(escrow.feeBps(), 100);
    }

    function test_RevertWhen_StrangerAcceptsOwnership() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.expectRevert(abi.encodeWithSelector(GovernedEscrow.NotPendingOwner.selector, stranger));
        vm.prank(stranger);
        escrow.acceptOwnership();
    }

    function test_RevertWhen_TransferCandidateIsZero() public {
        vm.expectRevert(GovernedEscrow.ZeroAddress.selector);
        vm.prank(owner);
        escrow.transferOwnership(address(0));
    }
}

