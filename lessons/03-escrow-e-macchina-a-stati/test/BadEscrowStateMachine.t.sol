// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { BadEscrowStateMachine } from "../src/labs/BadEscrowStateMachine.sol";

contract BadEscrowStateMachineTest is Test {
    BadEscrowStateMachine internal badEscrow;

    address internal buyer;
    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);

        vm.prank(buyer);
        badEscrow = new BadEscrowStateMachine(PRICE);
    }

    /// @dev Il test passa proprio perche' rende raggiungibile un comportamento proibito.
    function test_DemonstratesInvalidCreatedToReleaseApprovedTransition() public {
        assertEq(uint256(badEscrow.state()), uint256(BadEscrowStateMachine.State.Created));
        assertEq(address(badEscrow).balance, 0);

        // Nessun funding avviene prima dell'approvazione.
        vm.prank(buyer);
        badEscrow.approveRelease();

        assertEq(uint256(badEscrow.state()), uint256(BadEscrowStateMachine.State.ReleaseApproved));
        assertEq(address(badEscrow).balance, 0);
    }
}

