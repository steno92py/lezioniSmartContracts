// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { CallUtilsLite } from "../src/utils/CallUtilsLite.sol";
import { UncheckedDependency } from "../src/UncheckedDependency.sol";
import { CheckedDependency } from "../src/CheckedDependency.sol";
import { GoodDependency, RevertingDependency } from "../src/mocks/ActionDependencies.sol";

contract LowLevelCallsTest is Test {
    /// @dev Il test passa dimostrando che il caller registra un successo inesistente.
    function test_Vulnerable_RevertCreatesFalseSuccess() public {
        UncheckedDependency consumer = new UncheckedDependency();
        RevertingDependency dependency = new RevertingDependency();

        consumer.run(address(dependency), abi.encodeCall(dependency.execute, ()));

        assertTrue(consumer.completed());
    }

    /// @dev Una low-level call verso un EOA puo' restituire true pur non eseguendo codice.
    function test_Vulnerable_NoCodeStillCreatesFalseSuccess() public {
        UncheckedDependency consumer = new UncheckedDependency();

        consumer.run(makeAddr("empty-target"), hex"");

        assertTrue(consumer.completed());
    }

    function test_CheckedCallCompletesOnlyAfterDependencyRuns() public {
        CheckedDependency consumer = new CheckedDependency();
        GoodDependency dependency = new GoodDependency();

        bytes memory result =
            consumer.run(address(dependency), abi.encodeCall(dependency.execute, ()));

        assertTrue(dependency.executed());
        assertTrue(consumer.completed());
        assertEq(abi.decode(result, (uint256)), 42);
    }

    function test_CheckedCallBubblesRevertAndKeepsState() public {
        CheckedDependency consumer = new CheckedDependency();
        RevertingDependency dependency = new RevertingDependency();

        vm.expectRevert(RevertingDependency.DependencyFailure.selector);
        consumer.run(address(dependency), abi.encodeCall(dependency.execute, ()));

        assertFalse(consumer.completed());
    }

    function test_CheckedCallRejectsTargetWithoutCode() public {
        CheckedDependency consumer = new CheckedDependency();
        address emptyTarget = makeAddr("empty-target");

        vm.expectRevert(abi.encodeWithSelector(CallUtilsLite.TargetHasNoCode.selector, emptyTarget));
        consumer.run(emptyTarget, hex"");

        assertFalse(consumer.completed());
    }

    function test_RevertWhen_CheckedCallRunsTwice() public {
        CheckedDependency consumer = new CheckedDependency();
        GoodDependency dependency = new GoodDependency();
        bytes memory data = abi.encodeCall(dependency.execute, ());

        consumer.run(address(dependency), data);

        vm.expectRevert(CheckedDependency.AlreadyCompleted.selector);
        consumer.run(address(dependency), data);
    }
}

