// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { FixedFeeRegistry } from "../src/FixedFeeRegistry.sol";

contract FixedFeeRegistryTest is Test {
    FixedFeeRegistry internal registry;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    uint256 internal constant FEE = 1 ether;

    function setUp() public {
        registry = new FixedFeeRegistry();

        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    function test_InitialState() public view {
        assertFalse(registry.registered(ALICE));
        assertFalse(registry.registered(BOB));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);
        assertEq(registry.REGISTRATION_FEE(), FEE);
    }

    function test_Register_SucceedsWithExactFee() public {
        // Arrange: setUp ha creato il registry e finanziato ALICE.

        // Act
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        // Assert
        assertTrue(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 1);
        assertEq(registry.totalReceived(), FEE);
        _assertAccountingProperty();
    }

    function test_Register_EmitsRegisteredEvent() public {
        vm.expectEmit(true, false, false, true, address(registry));
        emit FixedFeeRegistry.Registered(ALICE, FEE);

        vm.prank(ALICE);
        registry.register{ value: FEE }();
    }

    function test_Register_TwoDifferentAccountsRemainIndependent() public {
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        assertTrue(registry.registered(ALICE));
        assertFalse(registry.registered(BOB));

        vm.prank(BOB);
        registry.register{ value: FEE }();

        assertTrue(registry.registered(ALICE));
        assertTrue(registry.registered(BOB));
        assertEq(registry.registrationCount(), 2);
        assertEq(registry.totalReceived(), 2 * FEE);
        _assertAccountingProperty();
    }

    function test_RevertWhen_FeeIsZero() public {
        _expectWrongFeeAndAssertUnchanged(0);
    }

    function test_RevertWhen_FeeIsTooLow() public {
        _expectWrongFeeAndAssertUnchanged(0.5 ether);
    }

    /// @dev Regression test per la mutazione `msg.value < REGISTRATION_FEE`.
    function test_RevertWhen_FeeIsTooHigh() public {
        _expectWrongFeeAndAssertUnchanged(2 ether);
    }

    function test_RevertWhen_AccountRegistersTwice() public {
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        vm.expectRevert(abi.encodeWithSelector(FixedFeeRegistry.AlreadyRegistered.selector, ALICE));
        vm.prank(ALICE);
        registry.register{ value: FEE }();

        assertTrue(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 1);
        assertEq(registry.totalReceived(), FEE);
        assertEq(ALICE.balance, aliceBalanceBefore, "la call fallita non deve spendere la fee");
        assertEq(address(registry).balance, registryBalanceBefore);
        _assertAccountingProperty();
    }

    function _expectWrongFeeAndAssertUnchanged(uint256 sent) internal {
        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        vm.expectRevert(
            abi.encodeWithSelector(FixedFeeRegistry.ExactFeeRequired.selector, sent, FEE)
        );
        vm.prank(ALICE);
        registry.register{ value: sent }();

        assertFalse(registry.registered(ALICE));
        assertEq(registry.registrationCount(), 0);
        assertEq(registry.totalReceived(), 0);
        assertEq(ALICE.balance, aliceBalanceBefore, "il revert deve ripristinare il saldo");
        assertEq(address(registry).balance, registryBalanceBefore);
        _assertAccountingProperty();
    }

    function _assertAccountingProperty() internal view {
        assertEq(registry.totalReceived(), registry.registrationCount() * FEE);
    }
}

