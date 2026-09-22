// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { EscrowRoles } from "../src/access/EscrowRoles.sol";

contract EscrowRolesTest is Test {
    address internal admin;
    address internal pauser;
    address internal arbiter;
    address internal stranger;

    EscrowRoles internal escrow;

    function setUp() public {
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        arbiter = makeAddr("arbiter");
        stranger = makeAddr("stranger");
        escrow = new EscrowRoles(admin, pauser, arbiter);
    }

    function test_InitialPermissionMatrix() public view {
        assertTrue(escrow.hasRole(escrow.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(escrow.hasRole(escrow.PAUSER_ROLE(), pauser));
        assertTrue(escrow.hasRole(escrow.ARBITER_ROLE(), arbiter));

        assertFalse(escrow.hasRole(escrow.PAUSER_ROLE(), admin));
        assertFalse(escrow.hasRole(escrow.ARBITER_ROLE(), pauser));
        assertEq(escrow.getRoleAdmin(escrow.PAUSER_ROLE()), escrow.DEFAULT_ADMIN_ROLE());
    }

    function test_PauserCanPauseButCannotResolveDispute() public {
        vm.prank(pauser);
        escrow.setPaused(true);
        assertTrue(escrow.paused());

        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, pauser, escrow.ARBITER_ROLE())
        );
        vm.prank(pauser);
        escrow.resolveDispute();
    }

    function test_ArbiterCanResolveButCannotPause() public {
        vm.prank(arbiter);
        escrow.resolveDispute();
        assertTrue(escrow.disputeResolved());

        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, arbiter, escrow.PAUSER_ROLE())
        );
        vm.prank(arbiter);
        escrow.setPaused(true);
    }

    function test_AdminCanGrantAndRevokeRole() public {
        // I getter sono external calls: li valutiamo prima del prank one-shot.
        bytes32 pauserRole = escrow.PAUSER_ROLE();

        vm.prank(admin);
        escrow.grantRole(pauserRole, stranger);

        vm.prank(stranger);
        escrow.setPaused(true);
        assertTrue(escrow.paused());

        vm.prank(admin);
        escrow.revokeRole(pauserRole, stranger);

        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, stranger, pauserRole)
        );
        vm.prank(stranger);
        escrow.setPaused(false);
    }

    function test_AdminDoesNotImplicitlyHaveOperationalRoles() public {
        vm.expectRevert(
            abi.encodeWithSelector(EscrowRoles.MissingRole.selector, admin, escrow.PAUSER_ROLE())
        );
        vm.prank(admin);
        escrow.setPaused(true);
    }

    function test_RevertWhen_NonAdminGrantsRole() public {
        bytes32 arbiterRole = escrow.ARBITER_ROLE();
        bytes32 adminRole = escrow.DEFAULT_ADMIN_ROLE();

        vm.expectRevert(abi.encodeWithSelector(EscrowRoles.MissingRole.selector, pauser, adminRole));
        vm.prank(pauser);
        escrow.grantRole(arbiterRole, stranger);

        assertFalse(escrow.hasRole(arbiterRole, stranger));
    }
}
