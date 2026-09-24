// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   makeAddr("nome")   crea un indirizzo deterministico con un'etichetta leggibile nelle trace;
//   vm.deal(a, x)      assegna x wei all'indirizzo a;
//   vm.prank(a)        la PROSSIMA call avra' msg.sender = a;
//   vm.startPrank(a)   TUTTE le call seguenti avranno msg.sender = a, fino a vm.stopPrank();
//   vm.expectRevert(e) la PROSSIMA call deve revertire con l'errore e.
// Per vedere la sequenza delle call: forge test --match-contract LogicBugEscrowTest -vvvv
import { Test } from "forge-std/Test.sol";
import { LogicBugEscrow } from "../src/LogicBugEscrow.sol";

// I test test_Vulnerable_* sono VERDI perche' dimostrano che una sequenza proibita
// riesce davvero. Sulla versione corretta (SafeEscrowTest) le stesse sequenze revertono.
contract LogicBugEscrowTest is Test {
    LogicBugEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal stranger; // un terzo qualunque, senza alcun ruolo

    uint256 internal constant DEPOSIT = 1 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");

        escrow = new LogicBugEscrow(buyer, seller);
        vm.deal(buyer, 10 ether);
        vm.deal(stranger, 10 ether); // anche lo stranger ha ETH: il revert non dipende dal saldo
    }

    // Happy path: la parte del contratto che funziona.
    function test_DepositMovesCreatedToFunded() public {
        _fund();

        _assertState(LogicBugEscrow.State.Funded);
        assertEq(escrow.depositedAmount(), DEPOSIT);
    }

    function test_RevertWhen_NonBuyerDeposits() public {
        vm.expectRevert(LogicBugEscrow.OnlyBuyer.selector);
        vm.prank(stranger);
        escrow.deposit{ value: DEPOSIT }();

        // Dopo il revert: stato invariato e nessun wei rimasto nel contratto.
        _assertState(LogicBugEscrow.State.Created);
        assertEq(address(escrow).balance, 0);
    }

    /// @dev Il test passa perche' rende visibile una transizione semanticamente vietata.
    function test_Vulnerable_CompleteBeforeDepositIsAccepted() public {
        // Nessun deposito: siamo in Created. complete() dovrebbe revertire, invece passa.
        vm.prank(seller);
        escrow.complete();

        // Il danno qui e' nullo (depositedAmount = 0), ma la call e' stata ACCETTATA:
        // la funzione non sa in che fase del ciclo si trova.
        _assertState(LogicBugEscrow.State.Created);
        assertEq(escrow.sellerCredit(), 0);
    }

    /// @dev Una singola azione autorizzata puo' essere ripetuta senza reentrancy.
    function test_Vulnerable_CompleteCanCreateUnbackedCredit() public {
        _fund();

        // Tre call normali e consecutive dello stesso seller: nessun trucco.
        vm.startPrank(seller);
        escrow.complete();
        escrow.complete();
        escrow.complete();
        vm.stopPrank();

        // backing: 1 ETH    credito del seller: 3 ETH
        assertEq(escrow.depositedAmount(), DEPOSIT);
        assertEq(escrow.sellerCredit(), 3 * DEPOSIT);
        // assertGt(a, b) verifica a > b: l'invariante liabilities <= backing e' violato.
        assertGt(escrow.sellerCredit() + escrow.buyerCredit(), escrow.depositedAmount());
        // Lo stato non e' mai uscito da Funded.
        _assertState(LogicBugEscrow.State.Funded);
    }

    /// @dev Cancelled dovrebbe essere terminale, ma complete() lo ignora.
    function test_Vulnerable_CompleteAfterCancelCreatesConflictingCredits() public {
        _fund();

        vm.prank(buyer);
        escrow.cancel();

        vm.prank(seller);
        escrow.complete();

        // Entrambe le parti risultano creditrici dello stesso deposito: 2 ETH dovuti, 1 ETH reale.
        _assertState(LogicBugEscrow.State.Cancelled);
        assertEq(escrow.buyerCredit(), DEPOSIT);
        assertEq(escrow.sellerCredit(), DEPOSIT);
        assertEq(escrow.buyerCredit() + escrow.sellerCredit(), 2 * DEPOSIT);
    }

    // Helper: porta l'escrow in Funded con un deposito valido del buyer.
    function _fund() internal {
        vm.prank(buyer);
        escrow.deposit{ value: DEPOSIT }();
    }

    // assertEq non confronta enum direttamente: si convertono in uint256 (Created = 0, ...).
    function _assertState(LogicBugEscrow.State expected) internal view {
        assertEq(uint256(escrow.state()), uint256(expected));
    }
}
