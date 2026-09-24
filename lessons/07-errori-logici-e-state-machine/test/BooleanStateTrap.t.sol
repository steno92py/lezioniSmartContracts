// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { BooleanStateTrap } from "../src/BooleanStateTrap.sol";

contract BooleanStateTrapTest is Test {
    /// @dev Il test passa dimostrando che tre flag consentono una combinazione incoerente.
    function test_Vulnerable_AllMutuallyExclusiveFlagsCanBeTrue() public {
        BooleanStateTrap trap = new BooleanStateTrap();

        // Nessun vm.prank: il chiamante e' il contratto di test, e basta.
        trap.markFunded();
        trap.markCompleted();
        trap.markCancelled();

        // "Completato" e "annullato" insieme: uno stato impossibile nel dominio,
        // ma rappresentabile nello storage. Con un enum questa riga non si potrebbe scrivere.
        assertTrue(trap.funded());
        assertTrue(trap.completed());
        assertTrue(trap.cancelled());
    }
}
