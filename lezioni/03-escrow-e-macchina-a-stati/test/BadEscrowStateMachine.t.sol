// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { BadEscrowStateMachine } from "../src/labs/BadEscrowStateMachine.sol";

// Laboratorio: riproduce localmente il bug di BadEscrowStateMachine.
// Per seguire la call nella trace: forge test --match-contract BadEscrowStateMachineTest -vvvv
contract BadEscrowStateMachineTest is Test {
    BadEscrowStateMachine internal badEscrow;

    address internal buyer;
    uint256 internal constant PRICE = 5 ether;

    function setUp() public {
        buyer = makeAddr("buyer"); // indirizzo con etichetta leggibile nelle trace
        vm.deal(buyer, 100 ether);

        vm.prank(buyer); // il buyer fa il deploy
        badEscrow = new BadEscrowStateMachine(PRICE);
    }

    // Una suite verde non implica sicurezza: qui il verde DIMOSTRA che l'attacco riesce.
    // Il test di regressione sul contratto corretto e' test_RevertWhen_ApproveHappensBeforeFunding.
    /// @dev Il test passa proprio perche' rende raggiungibile un comportamento proibito.
    function test_DemonstratesInvalidCreatedToReleaseApprovedTransition() public {
        // Punto di partenza: Created, nessun ETH depositato.
        assertEq(uint256(badEscrow.state()), uint256(BadEscrowStateMachine.State.Created));
        assertEq(address(badEscrow).balance, 0);

        // Nessun funding avviene prima dell'approvazione.
        vm.prank(buyer);
        badEscrow.approveRelease();

        // Stato "approvato" con saldo zero: una storia impossibile nel grafo progettato.
        assertEq(uint256(badEscrow.state()), uint256(BadEscrowStateMachine.State.ReleaseApproved));
        assertEq(address(badEscrow).balance, 0);
    }
}
