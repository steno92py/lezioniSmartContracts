// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { EscrowAdminVulnerable } from "../src/access/EscrowAdminVulnerable.sol";
import { EscrowAdmin } from "../src/access/EscrowAdmin.sol";

contract AccessControlTest is Test {
    address internal buyer;
    address internal seller;
    address internal admin;
    address internal stranger;

    EscrowAdminVulnerable internal vulnerable;
    EscrowAdmin internal secureEscrow;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        admin = makeAddr("admin");
        stranger = makeAddr("stranger");

        vulnerable = new EscrowAdminVulnerable(buyer, seller, admin);
        secureEscrow = new EscrowAdmin(buyer, seller, admin);
    }

    /// @dev Il test passa dimostrando che il ruolo dichiarato non viene applicato.
    function test_Vulnerable_StrangerCanPause() public {
        assertFalse(vulnerable.paused());

        vm.prank(stranger);
        vulnerable.setPaused(true);

        assertTrue(vulnerable.paused());
    }

    function test_AdminCanPauseAndUnpause() public {
        vm.startPrank(admin);
        secureEscrow.setPaused(true);
        assertTrue(secureEscrow.paused());

        secureEscrow.setPaused(false);
        vm.stopPrank();

        assertFalse(secureEscrow.paused());
    }

    function test_RevertWhen_StrangerTriesToPause() public {
        _expectUnauthorized(stranger);
        assertFalse(secureEscrow.paused());
    }

    function test_BuyerIsNotImplicitlyAdmin() public {
        _expectUnauthorized(buyer);
    }

    function test_SellerIsNotImplicitlyAdmin() public {
        _expectUnauthorized(seller);
    }

    function test_RevertWhen_ConstructorReceivesZeroAddress() public {
        vm.expectRevert(EscrowAdmin.ZeroAddress.selector);
        new EscrowAdmin(address(0), seller, admin);
    }

    function _expectUnauthorized(address caller) internal {
        vm.expectRevert(abi.encodeWithSelector(EscrowAdmin.Unauthorized.selector, caller));
        vm.prank(caller);
        secureEscrow.setPaused(true);

        assertFalse(secureEscrow.paused());
    }
}

