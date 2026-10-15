// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Test e' la base di forge-std: fornisce gli assert (assertEq...) e `vm`, i cheatcode di Foundry.
// Cheatcode usati in questo file:
//   vm.deal(a, x)       assegna x wei all'indirizzo a, dal nulla;
//   vm.prank(a)         la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e, altrimenti il test fallisce;
//   vm.expectEmit(...)  la PROSSIMA call deve emettere esattamente l'evento indicato.
import { Test } from "forge-std/Test.sol";
import { EscrowLesson1 } from "../src/EscrowLesson1.sol";

contract EscrowLesson1Test is Test {
    EscrowLesson1 internal escrow;

    // Indirizzi fissi e leggibili: 0xA11CE ("alice") e 0xB0B ("bob").
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    // setUp() viene eseguita prima di OGNI test: ogni test parte da uno stato pulito.
    function setUp() public {
        escrow = new EscrowLesson1(); // deploy di un contratto nuovo
        vm.deal(ALICE, 10 ether); // ALICE ha ETH da depositare
    }

    // Ogni funzione che inizia con test_ e' un test. Lo schema e' sempre:
    // ARRANGE (prepara), ACT (esegui la call), ASSERT (verifica il risultato).
    function test_RecordBindsSenderValueAndCalldataToStorage() public {
        // ARRANGE
        bytes memory note = bytes("ordine-42");

        // ACT: ALICE chiama record inviando 1 ether a favore di BOB.
        // {value: ...} e' il msg.value della call.
        vm.prank(ALICE);
        uint256 id = escrow.record{ value: 1 ether }(BOB, note);

        // ASSERT: ogni input deve essere finito nel posto giusto dello storage.
        // Il terzo argomento e' il messaggio mostrato se l'assert fallisce.
        assertEq(id, 0, "il primo id deve essere zero");
        assertEq(escrow.nextId(), 1, "nextId deve avanzare di uno");
        assertEq(escrow.totalRecorded(), 1 ether, "il totale deve riflettere msg.value");
        assertEq(escrow.credited(BOB), 1 ether, "il credito appartiene al beneficiary");
        assertEq(address(escrow).balance, 1 ether, "il contratto riceve l'ETH");

        EscrowLesson1.Deposit memory deposit_ = escrow.getDeposit(id);

        // msg.sender -> payer, argomento -> beneficiary, msg.value -> amount, calldata -> hash.
        assertEq(deposit_.payer, ALICE, "payer deve essere il msg.sender della call");
        assertEq(deposit_.beneficiary, BOB);
        assertEq(deposit_.amount, 1 ether);
        assertEq(deposit_.noteHash, keccak256(note));
    }

    function test_EmitsDepositRecorded() public {
        bytes memory note = bytes("evento");

        // I quattro true chiedono di confrontare i tre campi indexed e i dati non indicizzati;
        // l'ultimo argomento e' il contratto che deve emettere l'evento.
        vm.expectEmit(true, true, true, true, address(escrow));
        // Questo emit non e' reale: e' il "modello" dell'evento atteso.
        emit EscrowLesson1.DepositRecorded(0, ALICE, BOB, 1 ether, keccak256(note));

        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, note);
    }

    // TEST NEGATIVI: provano che gli input sbagliati vengono rifiutati.
    // Non basta che la call fallisca: dopo il revert si controlla anche lo stato.
    function test_RevertWhenValueIsZero() public {
        // .selector identifica l'errore: si verifica il motivo preciso del revert.
        vm.expectRevert(EscrowLesson1.ZeroValue.selector);
        vm.prank(ALICE);
        escrow.record(BOB, bytes("zero-value")); // senza {value: ...} msg.value e' 0

        _assertEmptyState();
    }

    function test_RevertWhenBeneficiaryIsZero() public {
        vm.expectRevert(EscrowLesson1.ZeroBeneficiary.selector);
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(address(0), bytes("bad-beneficiary"));

        _assertEmptyState();
    }

    // CONFINE: 257 byte deve fallire, 256 (test successivo) deve passare.
    // Se qualcuno scrivesse `>=` al posto di `>`, il test sul confine diventerebbe rosso.
    function test_RevertWhenNoteIsTooLong() public {
        bytes memory tooLong = new bytes(257);

        // Errore con parametro: si confrontano selettore E valore (257).
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

    // Il test piu' importante della lezione: un revert non deve toccare lo stato GIA' esistente.
    // Verificarlo su un contratto vuoto e' facile; qui prima si crea un deposito vero.
    function test_RevertRollsBackStateAndIncomingValue() public {
        // 1. Stato reale: un primo deposito valido.
        vm.prank(ALICE);
        escrow.record{ value: 1 ether }(BOB, bytes("first"));

        // 2. Si fotografa tutto.
        uint256 nextIdBefore = escrow.nextId();
        uint256 totalBefore = escrow.totalRecorded();
        uint256 bobCreditBefore = escrow.credited(BOB);
        uint256 balanceBefore = address(escrow).balance;
        EscrowLesson1.Deposit memory firstDepositBefore = escrow.getDeposit(0);

        // 3. Una call invalida che porta con se' 2 ether.
        vm.expectRevert(abi.encodeWithSelector(EscrowLesson1.NoteTooLong.selector, uint256(257)));
        vm.prank(ALICE);
        escrow.record{ value: 2 ether }(BOB, new bytes(257));

        // 4. Tutto deve essere identico alla foto. I 2 ether sono tornati ad ALICE.
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
        // Nessun deposito creato: l'ID 0 non esiste e getDeposit deve fallire,
        // invece di restituire una struct piena di zeri.
        vm.expectRevert(abi.encodeWithSelector(EscrowLesson1.UnknownDeposit.selector, uint256(0)));
        escrow.getDeposit(0);
    }

    // Helper riusato dai test negativi. `internal`: non e' un test, lo chiamano gli altri test.
    function _assertEmptyState() internal view {
        assertEq(escrow.nextId(), 0, "un revert non deve consumare un id");
        assertEq(escrow.totalRecorded(), 0, "un revert non deve alterare il totale");
        assertEq(escrow.credited(BOB), 0, "un revert non deve creare credito");
        assertEq(address(escrow).balance, 0, "l'ETH della call fallita non deve restare");
    }
}
