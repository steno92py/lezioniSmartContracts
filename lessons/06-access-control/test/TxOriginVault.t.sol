// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { TxOriginVault, DirectCallerVault, Forwarder } from "../src/access/TxOriginVault.sol";

contract TxOriginVaultTest is Test {
    address internal owner;

    function setUp() public {
        owner = makeAddr("owner");
    }

    function test_Vulnerable_TxOriginAllowsIndirectCall() public {
        TxOriginVault target = new TxOriginVault(owner);
        Forwarder forwarder = new Forwarder();

        vm.prank(owner, owner);
        forwarder.forwardSet(target, 123);

        assertEq(target.protectedValue(), 123);
    }

    function test_Fixed_MsgSenderRejectsIndirectCall() public {
        DirectCallerVault target = new DirectCallerVault(owner);
        Forwarder forwarder = new Forwarder();

        vm.expectRevert(
            abi.encodeWithSelector(DirectCallerVault.Unauthorized.selector, address(forwarder))
        );
        vm.prank(owner, owner);
        forwarder.forwardSet(target, 123);

        assertEq(target.protectedValue(), 0);
    }

    function test_Fixed_OwnerCanCallDirectly() public {
        DirectCallerVault target = new DirectCallerVault(owner);

        vm.prank(owner);
        target.setProtectedValue(123);

        assertEq(target.protectedValue(), 123);
    }
}

