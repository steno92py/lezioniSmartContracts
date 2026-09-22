// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { SafeVaultCEI } from "../src/reentrancy/SafeVaultCEI.sol";
import { SafeVaultGuarded } from "../src/reentrancy/SafeVaultGuarded.sol";
import { DidacticReentrancyGuard } from "../src/utils/DidacticReentrancyGuard.sol";
import {
    IVault,
    LocalReentrantProbe,
    RejectingVaultReceiver
} from "./helpers/ReentrancyReceivers.sol";

contract SafeVaultsTest is Test {
    function test_CEI_PreventsReuseOfCredit() public {
        SafeVaultCEI safe = new SafeVaultCEI();
        _addHonestLiquidity(IVault(address(safe)), 2 ether);

        LocalReentrantProbe receiver = new LocalReentrantProbe(IVault(address(safe)));
        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        assertEq(address(safe).balance, 3 ether);
        assertEq(safe.credit(address(receiver)), 1 ether);

        receiver.startWithdrawal();

        assertTrue(receiver.attemptedReentry());
        assertFalse(receiver.reentrySucceeded());
        assertEq(receiver.reentryError(), SafeVaultCEI.NoCredit.selector);
        assertEq(address(receiver).balance, 1 ether);
        assertEq(safe.credit(address(receiver)), 0);
        assertEq(address(safe).balance, 2 ether);
        assertEq(safe.totalCredits(), 2 ether);
        assertEq(address(safe).balance, safe.totalCredits());
    }

    function test_GuardAndCEI_BlockReentry() public {
        SafeVaultGuarded safe = new SafeVaultGuarded();
        _addHonestLiquidity(IVault(address(safe)), 2 ether);

        LocalReentrantProbe receiver = new LocalReentrantProbe(IVault(address(safe)));
        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        receiver.startWithdrawal();

        assertTrue(receiver.attemptedReentry());
        assertFalse(receiver.reentrySucceeded());
        assertEq(receiver.reentryError(), DidacticReentrancyGuard.ReentrantCall.selector);
        assertEq(address(receiver).balance, 1 ether);
        assertEq(safe.credit(address(receiver)), 0);
        assertEq(address(safe).balance, 2 ether);
        assertEq(safe.totalCredits(), 2 ether);
    }

    function test_CEI_RestoresAccountingWhenReceiverRejectsPayout() public {
        SafeVaultCEI safe = new SafeVaultCEI();
        RejectingVaultReceiver receiver = new RejectingVaultReceiver(IVault(address(safe)));

        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        vm.expectRevert(SafeVaultCEI.TransferFailed.selector);
        receiver.startWithdrawal();

        assertEq(safe.credit(address(receiver)), 1 ether);
        assertEq(safe.totalCredits(), 1 ether);
        assertEq(address(safe).balance, 1 ether);
        assertEq(address(receiver).balance, 0);
    }

    function _addHonestLiquidity(IVault vault, uint256 amount) internal {
        address honestUser = makeAddr("honest-user");
        vm.deal(honestUser, amount);
        vm.prank(honestUser);
        vault.deposit{ value: amount }();
    }
}

