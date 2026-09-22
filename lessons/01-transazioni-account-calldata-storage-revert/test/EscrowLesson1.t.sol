// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { EscrowLesson1 } from "../src/EscrowLesson1.sol";

contract EscrowLesson1Test is Test {
    EscrowLesson1 internal escrow;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        escrow = new EscrowLesson1();
        vm.deal(ALICE, 10 ether);
    }

    function test_RecordBindsSenderValueAndCalldataToStorage() public {
        bytes memory note = bytes("ordine-42");

        vm.prank(ALICE);
        uint256 id = escrow.record{ value: 1 ether }(BOB, note);

        assertEq(id, 0, "il primo id deve essere zero");
        assertEq(escrow.nextId(), 1, "nextId deve avanzare di uno");
        assertEq(escrow.totalRecorded(), 1 ether, "il totale deve riflettere msg.value");
        assertEq(escrow.credited(BOB), 1 ether, "il credito appartiene al beneficiary");
        assertEq(address(escrow).balance, 1 ether, "il contratto riceve l'ETH");

        EscrowLesson1.Deposit memory deposit_ = escrow.getDeposit(id);

        assertEq(deposit_.payer, ALICE, "payer deve essere il msg.sender della call");
        assertEq(deposit_.beneficiary, BOB);
        assertEq(deposit_.amount, 1 ether);
        assertEq(deposit_.noteHash, keccak256(note));
    }

    function test_EmitsDepositRecorded() public {
        bytes memory note = bytes("evento");

        vm.expectEmit(true, true, true, true, address(escrow));
        emit EscrowLesson1.DepositRecorded(0, ALICE, BOB, 1 ether, keccak256(note));

        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, note);
    }

    function test_RevertWhenValueIsZero() public {
        vm.expectRevert(EscrowLesson1.ZeroValue.selector);
        vm.prank(ALICE);
        escrow.record(BOB, bytes("zero-value"));

        _assertEmptyState();
    }

    function test_RevertWhenBeneficiaryIsZero() public {
        vm.expectRevert(EscrowLesson1.ZeroBeneficiary.selector);
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(address(0), bytes("bad-beneficiary"));

        _assertEmptyState();
    }

    function test_RevertWhenNoteIsTooLong() public {
        bytes memory tooLong = new bytes(257);

        vm.expectRevert(abi.encodeWithSelector(EscrowLesson1.NoteTooLong.selector, uint256(257)));
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, tooLong);

        _assertEmptyState();
    }

    function test_AcceptsNoteAtExactBoundary() public {
        bytes memory maximumLengthNote = new bytes(256);

        vm.prank(ALICE);
        uint256 id = escrow.record{ value: 1 ether }(BOB, maximumLengthNote);

        assertEq(id, 0);
        assertEq(escrow.getDeposit(id).noteHash, keccak256(maximumLengthNote));
    }

    function test_RevertRollsBackStateAndIncomingValue() public {
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, bytes("first"));

        uint256 nextIdBefore = escrow.nextId();
        uint256 totalBefore = escrow.totalRecorded();
        uint256 bobCreditBefore = escrow.credited(BOB);
        uint256 balanceBefore = address(escrow).balance;
        EscrowLesson1.Deposit memory firstDepositBefore = escrow.getDeposit(0);

        vm.expectRevert(abi.encodeWithSelector(EscrowLesson1.NoteTooLong.selector, uint256(257)));
        vm.prank(ALICE);
        escrow.record{ value: 2 ether }(BOB, new bytes(257));

        assertEq(escrow.nextId(), nextIdBefore);
        assertEq(escrow.totalRecorded(), totalBefore);
        assertEq(escrow.credited(BOB), bobCreditBefore);
        assertEq(address(escrow).balance, balanceBefore);

        EscrowLesson1.Deposit memory firstDepositAfter = escrow.getDeposit(0);
        assertEq(firstDepositAfter.payer, firstDepositBefore.payer);
        assertEq(firstDepositAfter.beneficiary, firstDepositBefore.beneficiary);
        assertEq(firstDepositAfter.amount, firstDepositBefore.amount);
        assertEq(firstDepositAfter.noteHash, firstDepositBefore.noteHash);
    }

    function test_RevertWhenReadingUnknownDeposit() public {
        vm.expectRevert(abi.encodeWithSelector(EscrowLesson1.UnknownDeposit.selector, uint256(0)));
        escrow.getDeposit(0);
    }

    function _assertEmptyState() internal view {
        assertEq(escrow.nextId(), 0, "un revert non deve consumare un id");
        assertEq(escrow.totalRecorded(), 0, "un revert non deve alterare il totale");
        assertEq(escrow.credited(BOB), 0, "un revert non deve creare credito");
        assertEq(address(escrow).balance, 0, "l'ETH della call fallita non deve restare");
    }
}

