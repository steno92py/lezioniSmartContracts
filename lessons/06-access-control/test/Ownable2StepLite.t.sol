// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper: makeAddr, vm.prank, vm.expectRevert (legenda in AccessControl.t.sol).
// I test seguono le due fasi: prima della proposta, dopo la proposta, dopo l'accettazione.
import { Test } from "forge-std/Test.sol";
import { Ownable2StepLite, EscrowOwnable2Step } from "../src/access/Ownable2StepLite.sol";

contract Ownable2StepLiteTest is Test {
    address internal owner;
    address internal candidate;
    address internal stranger;

    EscrowOwnable2Step internal escrow;

    function setUp() public {
        owner = makeAddr("owner");
        candidate = makeAddr("candidate");
        stranger = makeAddr("stranger");
        escrow = new EscrowOwnable2Step(owner);
    }

    function test_OwnerCanUsePrivilege() public {
        vm.prank(owner);
        escrow.setPaused(true);

        assertTrue(escrow.paused());
    }

    // FASE 1 da sola: la proposta non sposta ancora nessun privilegio.
    function test_TransferDoesNotChangeOwnerBeforeAcceptance() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        assertEq(escrow.owner(), owner);
        assertEq(escrow.pendingOwner(), candidate);

        // Prova concreta: il vecchio owner puo' ancora usare il privilegio.
        vm.prank(owner);
        escrow.setPaused(true);
        assertTrue(escrow.paused());
    }

    // Solo il candidato scelto puo' completare il trasferimento.
    function test_OnlyPendingOwnerCanAccept() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.expectRevert(abi.encodeWithSelector(Ownable2StepLite.NotPendingOwner.selector, stranger));
        vm.prank(stranger);
        escrow.acceptOwnership();

        assertEq(escrow.owner(), owner); // il tentativo fallito non ha cambiato nulla
    }

    // FASE 2: il privilegio passa al candidato e il vecchio owner lo perde SUBITO.
    function test_AcceptanceMovesPrivilegeAndClearsPendingOwner() public {
        vm.prank(owner);
        escrow.transferOwnership(candidate);

        vm.prank(candidate);
        escrow.acceptOwnership();

        assertEq(escrow.owner(), candidate);
        assertEq(escrow.pendingOwner(), address(0));

        // Negativo: il vecchio owner viene respinto...
        vm.expectRevert(abi.encodeWithSelector(Ownable2StepLite.Unauthorized.selector, owner));
        vm.prank(owner);
        escrow.setPaused(true);

        // ...positivo: il nuovo owner passa.
        vm.prank(candidate);
        escrow.setPaused(true);
        assertTrue(escrow.paused());
    }

    function test_RevertWhen_TransferTargetIsZero() public {
        vm.expectRevert(Ownable2StepLite.ZeroOwner.selector);
        vm.prank(owner);
        escrow.transferOwnership(address(0));

        // Stato invariato: nessuna proposta registrata.
        assertEq(escrow.owner(), owner);
        assertEq(escrow.pendingOwner(), address(0));
    }

    function test_RevertWhen_NonOwnerStartsTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable2StepLite.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.transferOwnership(candidate);
    }
}
