// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { BooleanStateTrap } from "../src/BooleanStateTrap.sol";

contract BooleanStateTrapTest is Test {
    /// @dev Il test passa dimostrando che tre flag consentono una combinazione incoerente.
    function test_Vulnerable_AllMutuallyExclusiveFlagsCanBeTrue() public {
        BooleanStateTrap trap = new BooleanStateTrap();

        trap.markFunded();
        trap.markCompleted();
        trap.markCancelled();

        assertTrue(trap.funded());
        assertTrue(trap.completed());
        assertTrue(trap.cancelled());
    }
}

