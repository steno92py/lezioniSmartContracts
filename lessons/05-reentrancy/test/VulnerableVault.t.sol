// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { VulnerableVault } from "../src/reentrancy/VulnerableVault.sol";
import { IVault, LocalReentrantReceiver } from "./helpers/ReentrancyReceivers.sol";

contract VulnerableVaultTest is Test {
    VulnerableVault internal vault;

    address internal alice;
    address internal bob;

    function setUp() public {
        vault = new VulnerableVault();
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_NormalWithdrawWorks() public {
        vm.prank(alice);
        vault.deposit{ value: 1 ether }();
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        vault.withdraw();

        assertEq(vault.credit(alice), 0);
        assertEq(alice.balance, aliceBalanceBefore + 1 ether);
        assertEq(address(vault).balance, 0);
        assertEq(vault.totalCredits(), 0);
    }

    /// @dev Il test passa dimostrando che il contratto vulnerabile diventa insolvente.
    function test_DemonstratesReentrantCallbackBreakingAccounting() public {
        address[4] memory users = [makeAddr("u1"), makeAddr("u2"), makeAddr("u3"), makeAddr("u4")];

        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 1 ether);
            vm.prank(users[i]);
            vault.deposit{ value: 1 ether }();
        }

        LocalReentrantReceiver receiver = new LocalReentrantReceiver(IVault(address(vault)), 4);

        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        assertEq(address(vault).balance, 5 ether);
        assertEq(vault.credit(address(receiver)), 1 ether);
        assertEq(vault.totalCredits(), 5 ether);

        receiver.startWithdrawal();

        assertGt(address(receiver).balance, 1 ether, "lo stesso credito e' stato riutilizzato");
        assertEq(address(vault).balance, 0);

        uint256 honestLiabilities;
        for (uint256 i = 0; i < users.length; i++) {
            honestLiabilities += vault.credit(users[i]);
        }

        // I crediti individuali promettono ancora 4 ETH, ma il vault e' vuoto.
        assertEq(honestLiabilities, 4 ether);
        assertGt(honestLiabilities, address(vault).balance, "liabilities > assets");

        // Anche l'aggregato e' stato corrotto dai decrementi ripetuti durante l'unwind.
        assertEq(vault.totalCredits(), 0);
        assertNotEq(vault.totalCredits(), honestLiabilities);
    }

    function test_RevertWhen_DepositIsZero() public {
        vm.expectRevert(VulnerableVault.ZeroDeposit.selector);
        vm.prank(alice);
        vault.deposit();
    }

    function test_RevertWhen_NoCredit() public {
        vm.expectRevert(VulnerableVault.NoCredit.selector);
        vm.prank(alice);
        vault.withdraw();
    }

    function test_RevertWhen_WithdrawnTwiceSequentially() public {
        vm.prank(alice);
        vault.deposit{ value: 1 ether }();

        vm.prank(alice);
        vault.withdraw();

        vm.expectRevert(VulnerableVault.NoCredit.selector);
        vm.prank(alice);
        vault.withdraw();
    }
}
