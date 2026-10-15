// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")    indirizzo deterministico ed etichettato nelle trace;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e.
// Qui l'owner e' un semplice EOA: si studia l'ownership a due fasi da sola, senza timelock.
import { Test } from "forge-std/Test.sol";
import { GovernedEscrow } from "../src/governance/GovernedEscrow.sol";

contract OwnershipTwoStepTest is Test {
    address internal owner;
    address internal candidate;
    address internal stranger;
    GovernedEscrow internal escrow;

    function setUp() public {
        owner = makeAddr("owner");
        candidate = makeAddr("candidate");
        stranger = makeAddr("stranger");
        escrow = new GovernedEscrow(owner, makeAddr("pauser"));
    }

    function test_CandidateMustAcceptOwnership() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        // Dopo la fase 1 nulla e' cambiato per l'owner: il candidato e' solo "in attesa".
        assertEq(escrow.owner(), owner);
        assertEq(escrow.pendingOwner(), candidate);

        vm.prank(candidate);
        escrow.acceptOwnership();

        // Dopo la fase 2 il passaggio e' completo e la proposta e' consumata.
        assertEq(escrow.owner(), candidate);
        assertEq(escrow.pendingOwner(), address(0));
    }

    // Finche' il candidato non accetta, l'owner attuale mantiene tutti i poteri.
    function test_CurrentOwnerRetainsAuthorityUntilAcceptance() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.prank(owner);
        escrow.setFee(100);
        assertEq(escrow.feeBps(), 100);
    }

    // Solo il candidato designato puo' accettare, non un terzo che osserva la proposta.
    function test_RevertWhen_StrangerAcceptsOwnership() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.expectRevert(abi.encodeWithSelector(GovernedEscrow.NotPendingOwner.selector, stranger));
        vm.prank(stranger);
        escrow.acceptOwnership();
    }

    function test_RevertWhen_TransferCandidateIsZero() public {
        vm.expectRevert(GovernedEscrow.ZeroAddress.selector);
        vm.prank(owner);
        escrow.transferOwnership(address(0));
    }
}
