// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { CallUtilsLite } from "../src/utils/CallUtilsLite.sol";
import { AllowlistedExecutor } from "../src/AllowlistedExecutor.sol";
import { GoodDependency, RevertingDependency } from "../src/mocks/ActionDependencies.sol";

contract AllowlistedExecutorTest is Test {
    AllowlistedExecutor internal executor;
    GoodDependency internal allowedDependency;

    address internal admin;
    address internal operator;
    address internal stranger;

    function setUp() public {
        admin = makeAddr("admin");
        operator = makeAddr("operator");
        stranger = makeAddr("stranger");
        executor = new AllowlistedExecutor(admin, operator);
        allowedDependency = new GoodDependency();
    }

    function test_AdminCanAllowAndOperatorCanExecute() public {
        _allow(address(allowedDependency));

        vm.prank(operator);
        bytes memory result = executor.execute(
            address(allowedDependency), abi.encodeCall(allowedDependency.execute, ())
        );

        assertTrue(allowedDependency.executed());
        assertEq(abi.decode(result, (uint256)), 42);
        assertEq(executor.completedCalls(), 1);
    }

    function test_RevertWhen_TargetIsNotAllowed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AllowlistedExecutor.TargetNotAllowed.selector, address(allowedDependency)
            )
        );
        vm.prank(operator);
        executor.execute(address(allowedDependency), abi.encodeCall(allowedDependency.execute, ()));

        assertFalse(allowedDependency.executed());
    }

    function test_AdminCanRevokeTarget() public {
        _allow(address(allowedDependency));
        vm.prank(admin);
        executor.setTargetAllowed(address(allowedDependency), false);

        assertFalse(executor.allowedTarget(address(allowedDependency)));
    }

    function test_RevertWhen_NonAdminChangesAllowlist() public {
        vm.expectRevert(abi.encodeWithSelector(AllowlistedExecutor.Unauthorized.selector, stranger));
        vm.prank(stranger);
        executor.setTargetAllowed(address(allowedDependency), true);
    }

    function test_RevertWhen_NonOperatorExecutes() public {
        _allow(address(allowedDependency));

        vm.expectRevert(abi.encodeWithSelector(AllowlistedExecutor.Unauthorized.selector, stranger));
        vm.prank(stranger);
        executor.execute(address(allowedDependency), abi.encodeCall(allowedDependency.execute, ()));
    }

    function test_RevertingAllowedDependencyDoesNotIncrementCounter() public {
        RevertingDependency revertingDependency = new RevertingDependency();
        _allow(address(revertingDependency));

        vm.expectRevert(RevertingDependency.DependencyFailure.selector);
        vm.prank(operator);
        executor.execute(
            address(revertingDependency), abi.encodeCall(revertingDependency.execute, ())
        );

        assertEq(executor.completedCalls(), 0);
    }

    function test_RevertWhen_AllowingTargetWithoutCode() public {
        vm.expectRevert(abi.encodeWithSelector(CallUtilsLite.TargetHasNoCode.selector, stranger));
        vm.prank(admin);
        executor.setTargetAllowed(stranger, true);
    }

    function _allow(address target) internal {
        vm.prank(admin);
        executor.setTargetAllowed(target, true);
    }
}

