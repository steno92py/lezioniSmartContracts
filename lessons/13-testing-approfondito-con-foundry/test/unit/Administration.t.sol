// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {MockOracle} from "../../src/mocks/TestingMocks.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract AdministrationTest is EscrowTestBase {
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    function test_OwnerUpdatesFeeWithEventAndState() public {
        vm.expectEmit(false, false, false, true, address(escrow));
        emit FeeUpdated(0, 250);
        vm.prank(owner);
        escrow.setFee(250);

        assertEq(escrow.feeBps(), 250);
    }

    function test_FeeBoundary999Succeeds() public {
        vm.prank(owner);
        escrow.setFee(999);
        assertEq(escrow.feeBps(), 999);
    }

    function test_FeeBoundary1000Succeeds() public {
        vm.prank(owner);
        escrow.setFee(1_000);
        assertEq(escrow.feeBps(), 1_000);
    }

    function test_FeeBoundary1001RevertsAndPreservesOldFee() public {
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.FeeTooHigh.selector, 1_001));
        vm.prank(owner);
        escrow.setFee(1_001);
        assertEq(escrow.feeBps(), 0);
    }

    function test_StrangerCannotSetFee() public {
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.setFee(250);
        assertEq(escrow.feeBps(), 0);
    }

    function test_OwnerUpdatesOracleWithEventAndState() public {
        MockOracle replacement = new MockOracle();

        vm.expectEmit(true, true, false, false, address(escrow));
        emit OracleUpdated(address(oracle), address(replacement));
        vm.prank(owner);
        escrow.setOracle(address(replacement));

        assertEq(address(escrow.oracle()), address(replacement));
    }

    function test_ZeroOracleIsRejected() public {
        vm.expectRevert(TestingEscrow.ZeroAddress.selector);
        vm.prank(owner);
        escrow.setOracle(address(0));
        assertEq(address(escrow.oracle()), address(oracle));
    }

    function test_StrangerCannotSetOracle() public {
        MockOracle replacement = new MockOracle();
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.setOracle(address(replacement));
    }
}

