// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Test della versione corretta: solo withdraw(), il resto e' identico a SafeEscrow
// ed e' gia' coperto da test/SafeEscrow.t.sol.
// Oltre al saldo si ricontrollano stato e liabilities: il prelievo non deve spostare
// la state machine e deve lasciare l'invariante liabilities <= balance vero.
import { Test } from "forge-std/Test.sol";
import { SafeEscrowFixed } from "../src/fixed/SafeEscrowFixed.sol";

// Contratto senza receive() ne' fallback(): qualunque invio di ETH verso di lui fallisce.
contract RejectsEther { }

contract SafeEscrowFixedTest is Test {
    SafeEscrowFixed internal escrow;

    address internal buyer;
    address internal seller;
    address internal stranger;

    uint256 internal constant DEPOSIT = 1 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");

        escrow = new SafeEscrowFixed(buyer, seller);
        vm.deal(buyer, 10 ether);
    }

    // Caso felice 1: Funded -> Completed, il seller ritira.
    function test_SellerWithdrawsAfterComplete() public {
        _complete();

        vm.expectEmit(true, false, false, true, address(escrow));
        emit SafeEscrowFixed.Withdrawn(seller, DEPOSIT);

        vm.prank(seller);
        escrow.withdraw();

        assertEq(seller.balance, DEPOSIT, "l'ETH deve arrivare al seller");
        assertEq(escrow.sellerCredit(), 0, "il credito deve essere azzerato");
        assertEq(escrow.liabilities(), 0, "nessuna obbligazione residua");
        assertEq(address(escrow).balance, 0, "il contratto non deve trattenere nulla");
        assertEq(escrow.depositedAmount(), DEPOSIT, "il backing storico non cambia");
        _assertState(SafeEscrowFixed.State.Completed);
    }

    // Caso felice 2: Funded -> Cancelled, il buyer si riprende il deposito.
    function test_BuyerWithdrawsAfterCancel() public {
        _cancel();
        uint256 buyerBefore = buyer.balance;

        vm.prank(buyer);
        escrow.withdraw();

        assertEq(buyer.balance, buyerBefore + DEPOSIT, "l'ETH deve tornare al buyer");
        assertEq(escrow.buyerCredit(), 0);
        assertEq(escrow.liabilities(), 0);
        assertEq(address(escrow).balance, 0);
        _assertState(SafeEscrowFixed.State.Cancelled);
    }

    // chi? Un estraneo non puo' ritirare nulla.
    function test_RevertWhenStrangerWithdraws() public {
        _complete();

        vm.expectRevert(abi.encodeWithSelector(SafeEscrowFixed.NotAParty.selector, stranger));
        vm.prank(stranger);
        escrow.withdraw();

        assertEq(escrow.sellerCredit(), DEPOSIT, "il credito del seller resta intatto");
    }

    // Dopo complete() il credito e' del seller: il buyer non ha niente da ritirare.
    function test_RevertWhenBuyerWithdrawsAfterComplete() public {
        _complete();

        vm.expectRevert(SafeEscrowFixed.NothingToWithdraw.selector);
        vm.prank(buyer);
        escrow.withdraw();

        assertEq(escrow.sellerCredit(), DEPOSIT);
        assertEq(address(escrow).balance, DEPOSIT);
    }

    // quando? Prima della fine del ciclo nessuno ha credito, anche se il deposito c'e'.
    function test_RevertWhenWithdrawBeforeTerminalState() public {
        _fund();

        vm.expectRevert(SafeEscrowFixed.NothingToWithdraw.selector);
        vm.prank(seller);
        escrow.withdraw();

        _assertState(SafeEscrowFixed.State.Funded);
        assertEq(address(escrow).balance, DEPOSIT);
    }

    // Lo stesso credito non si ritira due volte.
    function test_RevertOnSecondWithdraw() public {
        _complete();

        vm.prank(seller);
        escrow.withdraw();

        vm.expectRevert(SafeEscrowFixed.NothingToWithdraw.selector);
        vm.prank(seller);
        escrow.withdraw();

        assertEq(seller.balance, DEPOSIT, "il seller non deve ricevere piu' di quanto gli spetta");
    }

    // Se il destinatario rifiuta l'ETH, il revert annulla tutto: il credito NON va perso.
    function test_RevertWhenRecipientRejectsEther() public {
        RejectsEther rejecter = new RejectsEther();
        escrow = new SafeEscrowFixed(buyer, address(rejecter));
        _complete();

        vm.expectRevert(SafeEscrowFixed.TransferFailed.selector);
        vm.prank(address(rejecter));
        escrow.withdraw();

        assertEq(escrow.sellerCredit(), DEPOSIT, "il credito deve restare");
        assertEq(address(escrow).balance, DEPOSIT, "l'ETH deve restare nel contratto");
    }

    function _fund() internal {
        vm.prank(buyer);
        escrow.deposit{ value: DEPOSIT }();
    }

    function _complete() internal {
        _fund();
        vm.prank(escrow.seller());
        escrow.complete();
    }

    function _cancel() internal {
        _fund();
        vm.prank(buyer);
        escrow.cancel();
    }

    function _assertState(SafeEscrowFixed.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }
}
