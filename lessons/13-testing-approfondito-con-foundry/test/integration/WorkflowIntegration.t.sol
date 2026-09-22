// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract WorkflowIntegrationTest is EscrowTestBase {
    function test_FullDepositAndReleaseWorkflowPreservesEconomicAccounting() public {
        uint256 amount = 400 ether;
        vm.prank(owner);
        escrow.setFee(500);

        _approveAndDeposit(amount);
        assertEq(token.balanceOf(address(escrow)), escrow.liability());

        vm.prank(buyer);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Released));
        assertEq(token.balanceOf(seller), 380 ether);
        assertEq(token.balanceOf(owner), 20 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.liability(), 0);
    }

    function test_EachTestStartsFromSetUpState() public view {
        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.depositedAmount(), 0);
        assertEq(token.balanceOf(buyer), BUYER_BALANCE);
    }
}

