// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Test della versione corretta: solo withdraw(), il resto e' identico a EscrowLesson1
// ed e' gia' coperto da test/EscrowLesson1.t.sol.
import { Test } from "forge-std/Test.sol";
import { EscrowLesson1Fixed } from "../src/fixed/EscrowLesson1Fixed.sol";

// Contratto senza receive() ne' fallback(): qualunque invio di ETH verso di lui fallisce.
contract RejectsEther { }

contract EscrowLesson1FixedTest is Test {
    EscrowLesson1Fixed internal escrow;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        escrow = new EscrowLesson1Fixed();
        vm.deal(ALICE, 10 ether);
    }

    // Caso felice: ALICE deposita per BOB, BOB ritira.
    function test_BeneficiaryWithdrawsCredit() public {
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, bytes("ordine-42"));

        vm.expectEmit(true, false, false, true, address(escrow));
        emit EscrowLesson1Fixed.Withdrawn(BOB, 1 ether);

        vm.prank(BOB);
        escrow.withdraw();

        assertEq(BOB.balance, 1 ether, "l'ETH deve arrivare al beneficiary");
        assertEq(escrow.credited(BOB), 0, "il credito deve essere azzerato");
        assertEq(address(escrow).balance, 0, "il contratto non deve trattenere nulla");
        assertEq(escrow.totalRecorded(), 1 ether, "il totale storico non cambia");
    }

    // Il payer non puo' ritirare: il credito e' del beneficiary.
    function test_RevertWhenPayerTriesToWithdraw() public {
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, bytes("ordine-42"));

        vm.expectRevert(EscrowLesson1Fixed.NothingToWithdraw.selector);
        vm.prank(ALICE);
        escrow.withdraw();

        assertEq(escrow.credited(BOB), 1 ether);
    }

    // Senza credito non si ritira niente.
    function test_RevertWhenNothingToWithdraw() public {
        vm.expectRevert(EscrowLesson1Fixed.NothingToWithdraw.selector);
        vm.prank(BOB);
        escrow.withdraw();
    }

    // Lo stesso credito non si ritira due volte.
    function test_RevertOnSecondWithdraw() public {
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, bytes("ordine-42"));

        vm.prank(BOB);
        escrow.withdraw();

        vm.expectRevert(EscrowLesson1Fixed.NothingToWithdraw.selector);
        vm.prank(BOB);
        escrow.withdraw();

        assertEq(BOB.balance, 1 ether, "BOB non deve ricevere piu' di quanto gli spetta");
    }

    // Se il destinatario rifiuta l'ETH, il revert annulla tutto: il credito NON va perso.
    function test_RevertWhenRecipientRejectsEther() public {
        RejectsEther rejecter = new RejectsEther();

        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(address(rejecter), bytes("rifiuta"));

        vm.expectRevert(EscrowLesson1Fixed.TransferFailed.selector);
        vm.prank(address(rejecter));
        escrow.withdraw();

        assertEq(escrow.credited(address(rejecter)), 1 ether, "il credito deve restare");
        assertEq(address(escrow).balance, 1 ether, "l'ETH deve restare nel contratto");
    }
}
