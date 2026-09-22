// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { Ownable2StepLite, EscrowOwnable2Step } from "../src/access/Ownable2StepLite.sol";

contract Ownable2StepLiteTest is Test {
    address internal owner;
    address internal candidate;
    address internal stranger;

    EscrowOwnable2Step internal escrow;

    function setUp() public {
        owner = makeAddr("owner");
        candidate = makeAddr("candidate");
        stranger = makeAddr("stranger");
        escrow = new EscrowOwnable2Step(owner);
    }

    function test_OwnerCanUsePrivilege() public {
        vm.prank(owner);
        escrow.setPaused(true);

        assertTrue(escrow.paused());
    }

    function test_TransferDoesNotChangeOwnerBeforeAcceptance() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        assertEq(escrow.owner(), owner);
        assertEq(escrow.pendingOwner(), candidate);

        vm.prank(owner);
        escrow.setPaused(true);
        assertTrue(escrow.paused());
    }

    function test_OnlyPendingOwnerCanAccept() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.expectRevert(abi.encodeWithSelector(Ownable2StepLite.NotPendingOwner.selector, stranger));
        vm.prank(stranger);
        escrow.acceptOwnership();

        assertEq(escrow.owner(), owner);
    }

    function test_AcceptanceMovesPrivilegeAndClearsPendingOwner() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.prank(candidate);
        escrow.acceptOwnership();

        assertEq(escrow.owner(), candidate);
        assertEq(escrow.pendingOwner(), address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable2StepLite.Unauthorized.selector, owner));
        vm.prank(owner);
        escrow.setPaused(true);

        vm.prank(candidate);
        escrow.setPaused(true);
        assertTrue(escrow.paused());
    }

    function test_RevertWhen_TransferTargetIsZero() public {
        vm.expectRevert(Ownable2StepLite.ZeroOwner.selector);
        vm.prank(owner);
        escrow.transferOwnership(address(0));

        assertEq(escrow.owner(), owner);
        assertEq(escrow.pendingOwner(), address(0));
    }

    function test_RevertWhen_NonOwnerStartsTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable2StepLite.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.transferOwnership(candidate);
    }
}

