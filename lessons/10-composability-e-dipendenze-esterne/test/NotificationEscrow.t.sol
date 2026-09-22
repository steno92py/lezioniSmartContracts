// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { INotifier } from "../src/interfaces/INotifier.sol";
import { NotificationEscrow } from "../src/NotificationEscrow.sol";
import { GoodNotifier } from "../src/mocks/GoodNotifier.sol";
import { RevertingNotifier } from "../src/mocks/RevertingNotifier.sol";

contract NotificationEscrowTest is Test {
    event NotificationFailed(address indexed notifier, bytes reason);

    address internal buyer;
    address internal seller;
    address internal stranger;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");
    }

    function test_ReleaseSucceedsWithNotifier() public {
        GoodNotifier notifier = new GoodNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));

        vm.prank(buyer);
        escrow.release();

        assertTrue(escrow.released());
        assertTrue(notifier.called());
        assertEq(notifier.notifiedSeller(), seller);
        assertEq(notifier.notifiedAmount(), 100);
    }

    function test_NotifierFailureIsObservableButDoesNotBlockRelease() public {
        RevertingNotifier notifier = new RevertingNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));
        bytes memory reason = abi.encodeWithSelector(RevertingNotifier.Nope.selector);

        vm.expectEmit(true, false, false, true, address(escrow));
        emit NotificationFailed(address(notifier), reason);

        vm.prank(buyer);
        escrow.release();

        assertTrue(escrow.released());
    }

    function test_RevertWhen_StrangerReleases() public {
        GoodNotifier notifier = new GoodNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));

        vm.expectRevert(abi.encodeWithSelector(NotificationEscrow.OnlyBuyer.selector, stranger));
        vm.prank(stranger);
        escrow.release();

        assertFalse(escrow.released());
        assertFalse(notifier.called());
    }

    function test_RevertWhen_ReleasingTwice() public {
        GoodNotifier notifier = new GoodNotifier();
        NotificationEscrow escrow = _newEscrow(INotifier(address(notifier)));

        vm.startPrank(buyer);
        escrow.release();
        vm.expectRevert(NotificationEscrow.AlreadyReleased.selector);
        escrow.release();
        vm.stopPrank();

        assertTrue(escrow.released());
    }

    function test_RevertWhen_NotifierHasNoCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(NotificationEscrow.InvalidNotifier.selector, stranger)
        );
        new NotificationEscrow(INotifier(stranger), buyer, seller, 100);
    }

    function _newEscrow(INotifier notifier) internal returns (NotificationEscrow) {
        return new NotificationEscrow(notifier, buyer, seller, 100);
    }
}

