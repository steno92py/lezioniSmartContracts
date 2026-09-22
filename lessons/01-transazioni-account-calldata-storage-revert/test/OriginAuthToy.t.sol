// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { OriginAuthToy, SenderAuthToy, ForwarderToy } from "../src/OriginAuthToy.sol";

contract OriginAuthToyTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant STRANGER = address(0xBAD);

    function test_Vulnerable_TxOriginAcceptsIntermediaryCall() public {
        OriginAuthToy target = new OriginAuthToy(OWNER);
        ForwarderToy forwarder = new ForwarderToy();

        // Nel target: tx.origin == OWNER, ma msg.sender == address(forwarder).
        vm.prank(OWNER, OWNER);
        forwarder.forward(target, 777);

        assertEq(target.value(), 777);
    }

    function test_Fixed_MsgSenderRejectsIntermediaryCall() public {
        SenderAuthToy target = new SenderAuthToy(OWNER);
        ForwarderToy forwarder = new ForwarderToy();

        vm.expectRevert(SenderAuthToy.NotOwner.selector);
        vm.prank(OWNER, OWNER);
        forwarder.forward(target, 777);

        assertEq(target.value(), 0, "il revert deve lasciare lo stato invariato");
    }

    function test_Fixed_OwnerCanCallDirectly() public {
        SenderAuthToy target = new SenderAuthToy(OWNER);

        vm.prank(OWNER);
        target.setValue(777);

        assertEq(target.value(), 777);
    }

    function test_Fixed_StrangerCannotCallDirectly() public {
        SenderAuthToy target = new SenderAuthToy(OWNER);

        vm.expectRevert(SenderAuthToy.NotOwner.selector);
        vm.prank(STRANGER);
        target.setValue(777);

        assertEq(target.value(), 0);
    }

    function test_RevertWhenOriginAuthOwnerIsZero() public {
        vm.expectRevert(OriginAuthToy.ZeroOwner.selector);
        new OriginAuthToy(address(0));
    }

    function test_RevertWhenSenderAuthOwnerIsZero() public {
        vm.expectRevert(SenderAuthToy.ZeroOwner.selector);
        new SenderAuthToy(address(0));
    }
}
