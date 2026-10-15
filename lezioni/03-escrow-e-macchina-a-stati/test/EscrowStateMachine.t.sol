// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode e helper usati in questo file:
//   makeAddr("nome")          crea un indirizzo con un'etichetta leggibile nelle trace;
//   vm.deal(a, x)             assegna x wei all'indirizzo a, dal nulla;
//   vm.prank(a)               la PROSSIMA call (anche un `new`) avra' msg.sender = a;
//   vm.expectRevert(sel)      la PROSSIMA call deve revertire con quell'errore esatto;
//   vm.expectPartialRevert(sel)  come sopra, ma confronta solo il selettore dell'errore
//                             e ignora gli argomenti (es. il caller in Unauthorized(caller)).
// Per verificare anche gli argomenti: vm.expectRevert(abi.encodeWithSelector(sel, ...)).
import { Test } from "forge-std/Test.sol";
import { EscrowStateMachine } from "../src/EscrowStateMachine.sol";

// Struttura della suite:
//   1. percorsi validi: ogni freccia del grafo porta allo stato atteso;
//   2. negative space: ogni freccia assente reverte, per caller, valore o stato sbagliato;
//   3. constructor: le configurazioni invalide non arrivano mai al deploy.
contract EscrowStateMachineTest is Test {
    EscrowStateMachine internal escrow;

    address internal buyer;
    address internal seller;
    address internal outsider;

    uint256 internal constant PRICE = 5 ether;

    // Eseguita prima di OGNI test: ogni test parte da un Escrow nuovo in stato Created.
    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        outsider = makeAddr("outsider");

        vm.deal(buyer, 100 ether);
        vm.deal(outsider, 100 ether);

        // Il deploy lo fa il buyer: nel constructor msg.sender = buyer.
        vm.prank(buyer);
        escrow = new EscrowStateMachine(seller, PRICE);
    }

    function test_InitialConfiguration() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.price(), PRICE);
        _assertState(EscrowStateMachine.State.Created);
    }

    // --- 1. PERCORSI VALIDI: le frecce del grafo -------------------------------------------

    // Created -> Funded. Schema: ARRANGE (setUp), ACT (la call), ASSERT (stato e saldo).
    function test_BuyerCanFundExactPrice() public {
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    // Funded -> ReleaseApproved. L'ETH resta nel contratto: il payout arriva nella Lezione 4.
    function test_BuyerCanApproveAfterFunding() public {
        _fund(); // Arrange: porta l'Escrow in Funded

        vm.prank(buyer);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.ReleaseApproved);
        assertEq(address(escrow).balance, PRICE);
    }

    // Created -> Cancelled.
    function test_BuyerCanCancelBeforeFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(EscrowStateMachine.State.Cancelled);
        assertEq(address(escrow).balance, 0);
    }

    // --- 2. NEGATIVE SPACE: le frecce assenti ------------------------------------------------
    // Ogni test negativo controlla il motivo del revert E che lo stato non sia cambiato.

    // CHI sbagliato: stato giusto (Created), importo giusto, ma caller estraneo.
    function test_RevertWhen_OutsiderFunds() public {
        vm.expectPartialRevert(EscrowStateMachine.Unauthorized.selector);
        vm.prank(outsider);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    // CHI sbagliato: il seller ha un ruolo nell'Escrow, ma non quello di approvare.
    function test_RevertWhen_SellerApprovesRelease() public {
        _fund();

        vm.expectPartialRevert(EscrowStateMachine.Unauthorized.selector);
        vm.prank(seller);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.Funded);
    }

    // QUANTO sbagliato: i due confini appena sotto e appena sopra il prezzo (1 wei di scarto).
    function test_RevertWhen_FundingIsTooLow() public {
        uint256 tooLittle = PRICE - 1;

        vm.expectPartialRevert(EscrowStateMachine.WrongValue.selector);
        vm.prank(buyer);
        escrow.fund{ value: tooLittle }();

        _assertState(EscrowStateMachine.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertWhen_FundingIsTooHigh() public {
        uint256 tooMuch = PRICE + 1;

        vm.expectPartialRevert(EscrowStateMachine.WrongValue.selector);
        vm.prank(buyer);
        escrow.fund{ value: tooMuch }();

        _assertState(EscrowStateMachine.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    // QUANDO sbagliato: il caller e' il buyer, eppure la call deve fallire.
    // E' la freccia Created -> ReleaseApproved che BadEscrowStateMachine lascia aperta.
    /// @dev Regression test per la guardia Funded -> ReleaseApproved.
    function test_RevertWhen_ApproveHappensBeforeFunding() public {
        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.Created);
    }

    // RIPETIZIONE: un secondo fund() non deve essere accettato ne' trattenere altro ETH.
    function test_RevertWhen_FundingTwice() public {
        _fund();
        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Funded);
        assertEq(address(escrow).balance, PRICE); // solo il primo deposito
        assertEq(buyer.balance, buyerBalanceBefore); // i PRICE del secondo tentativo sono tornati
    }

    function test_RevertWhen_CancellingAfterFunding() public {
        _fund();

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.cancelBeforeFunding();

        _assertState(EscrowStateMachine.State.Funded);
        assertEq(address(escrow).balance, PRICE);
    }

    // STATI TERMINALI: una volta raggiunti, nessuna funzione deve poterli riaprire.
    function test_CancelledStateIsTerminalForFunding() public {
        vm.prank(buyer);
        escrow.cancelBeforeFunding();
        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();

        _assertState(EscrowStateMachine.State.Cancelled);
        assertEq(address(escrow).balance, 0);
        assertEq(buyer.balance, buyerBalanceBefore);
    }

    function test_ReleaseApprovedStateIsTerminalForApprove() public {
        _fundAndApprove();

        vm.expectPartialRevert(EscrowStateMachine.WrongState.selector);
        vm.prank(buyer);
        escrow.approveRelease();

        _assertState(EscrowStateMachine.State.ReleaseApproved);
    }

    // Revert atomico: l'ETH inviato con una call fallita torna al mittente, per intero.
    function test_RevertedFundingLeavesNoPartialEffects() public {
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 escrowBalanceBefore = address(escrow).balance;

        vm.expectPartialRevert(EscrowStateMachine.WrongValue.selector);
        vm.prank(buyer);
        escrow.fund{ value: PRICE - 1 }();

        assertEq(buyer.balance, buyerBalanceBefore);
        assertEq(address(escrow).balance, escrowBalanceBefore);
        _assertState(EscrowStateMachine.State.Created);
    }

    // --- 3. CONSTRUCTOR ------------------------------------------------------------------
    // Errori senza parametri: il selettore basta, quindi si usa vm.expectRevert.

    function test_RevertWhen_ConstructorSellerIsZero() public {
        vm.expectRevert(EscrowStateMachine.ZeroSeller.selector);
        vm.prank(buyer);
        new EscrowStateMachine(address(0), PRICE);
    }

    // Il deployer e' il buyer: passare lo stesso indirizzo come seller deve fallire.
    function test_RevertWhen_ConstructorBuyerEqualsSeller() public {
        vm.expectRevert(EscrowStateMachine.BuyerEqualsSeller.selector);
        vm.prank(buyer);
        new EscrowStateMachine(buyer, PRICE);
    }

    function test_RevertWhen_ConstructorPriceIsZero() public {
        vm.expectRevert(EscrowStateMachine.ZeroPrice.selector);
        vm.prank(buyer);
        new EscrowStateMachine(seller, 0);
    }

    // --- Helper `internal`: non sono test, portano l'Escrow in uno stato di partenza. -----

    function _fund() internal {
        vm.prank(buyer);
        escrow.fund{ value: PRICE }();
    }

    function _fundAndApprove() internal {
        _fund();
        vm.prank(buyer);
        escrow.approveRelease();
    }

    // assertEq non accetta enum: si confrontano i loro valori numerici (Created = 0, ...).
    function _assertState(EscrowStateMachine.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }
}
