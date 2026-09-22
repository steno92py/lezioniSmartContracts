// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {SafeStaticLab, IStaticAction} from "../src/fixed/SafeStaticLab.sol";
import {RecordingAction, RevertingAction} from "../src/mocks/StaticMocks.sol";

contract FixedRegressionTest is Test {
    address internal admin;
    address internal candidate;
    address internal stranger;
    RecordingAction internal action;
    SafeStaticLab internal lab;

    function setUp() public {
        admin = makeAddr("admin");
        candidate = makeAddr("candidate");
        stranger = makeAddr("stranger");
        action = new RecordingAction();
        lab = new SafeStaticLab(admin, action);
    }

    function test_AdminExecutesOnlyImmutableTypedAction() public {
        bytes memory payload = abi.encode("reviewed action");

        vm.prank(admin);
        lab.execute(payload);

        assertTrue(lab.completed());
        assertEq(action.lastCaller(), address(lab));
        assertEq(action.lastData(), payload);
        assertEq(address(lab.action()), address(action));
    }

    function test_Regression_FailedActionCannotMarkCompleted() public {
        RevertingAction failingAction = new RevertingAction();
        SafeStaticLab failingLab = new SafeStaticLab(admin, failingAction);

        vm.expectRevert(RevertingAction.ActionFailed.selector);
        vm.prank(admin);
        failingLab.execute(bytes("fails"));

        assertFalse(failingLab.completed());
    }

    function test_Regression_StrangerCannotExecute() public {
        vm.expectRevert(abi.encodeWithSelector(SafeStaticLab.Unauthorized.selector, stranger));
        vm.prank(stranger);
        lab.execute(bytes("unauthorized"));

        assertFalse(lab.completed());
        assertEq(action.lastCaller(), address(0));
    }

    function test_AdminTransferRequiresProposalAndAcceptance() public {
        vm.prank(admin);
        lab.transferAdmin(candidate);
        assertEq(lab.admin(), admin);
        assertEq(lab.pendingAdmin(), candidate);

        vm.prank(candidate);
        lab.acceptAdmin();
        assertEq(lab.admin(), candidate);
        assertEq(lab.pendingAdmin(), address(0));
    }

    function test_Regression_StrangerCannotReplaceAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(SafeStaticLab.Unauthorized.selector, stranger));
        vm.prank(stranger);
        lab.transferAdmin(stranger);

        assertEq(lab.admin(), admin);
    }

    function test_ConfigurationRejectsZeroAddresses() public {
        vm.expectRevert(SafeStaticLab.ZeroAddress.selector);
        new SafeStaticLab(address(0), action);

        vm.expectRevert(SafeStaticLab.ZeroAddress.selector);
        new SafeStaticLab(admin, IStaticAction(address(0)));
    }
}

