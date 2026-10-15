// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Unit test di deposit(): una proprieta' locale per ogni test.
// Cheatcode usati (oltre a quelli della fixture EscrowTestBase):
//   vm.expectRevert(e)       la PROSSIMA call deve revertire con esattamente l'errore e;
//   vm.expectEmit(t1,t2,t3,d,emitter)  la PROSSIMA call deve emettere l'evento dichiarato
//                            subito dopo; i bool dicono quali topic indexed e se i dati
//                            vanno confrontati, emitter e' il contratto che deve emetterlo.
// expectRevert/expectEmit e prank sono cheatcode, non call: la "prossima call" e' la call
// all'escrow che segue, anche se prank sta in mezzo.
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract DepositTest is EscrowTestBase {
    // Stessa firma dell'evento del contratto: serve per scrivere il "modello" da confrontare.
    event Deposited(address indexed buyer, uint256 amount, int256 price);

    // Happy path, verificato per DELTA: quanto e' cambiato ogni saldo, non solo lo stato finale.
    function test_BuyerCanDepositAndStateDeltaIsCorrect() public {
        // ARRANGE
        uint256 amount = 100 ether;
        uint256 buyerBefore = token.balanceOf(buyer);

        // ACT
        _approveAndDeposit(amount);

        // ASSERT: storage dell'escrow e saldi del token devono raccontare la stessa storia.
        // Gli enum si confrontano convertendoli in uint256.
        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Funded));
        assertEq(escrow.depositedAmount(), amount);
        assertEq(escrow.liability(), amount);
        assertEq(escrow.depositPrice(), FRESH_PRICE);
        assertEq(token.balanceOf(buyer), buyerBefore - amount);
        assertEq(token.balanceOf(address(escrow)), amount);
    }

    // L'evento da solo non prova nulla: potrebbe essere emesso anche se lo storage e' sbagliato.
    // Per questo, dopo expectEmit, si controlla anche lo stato.
    function test_DepositEmitsEventAndPersistsMatchingState() public {
        uint256 amount = 100 ether;
        _approve(amount);

        // true, false, false, true: confronta il topic indexed `buyer` e i dati non indicizzati.
        vm.expectEmit(true, false, false, true, address(escrow));
        emit Deposited(buyer, amount, FRESH_PRICE);
        vm.prank(buyer);
        escrow.deposit(amount);

        assertEq(escrow.depositedAmount(), amount);
    }

    // TEST NEGATIVI: revert preciso (errore + payload) E stato invariato dopo il fallimento.
    function test_StrangerCannotDepositAndStateIsUnchanged() public {
        uint256 escrowBefore = token.balanceOf(address(escrow));

        // Il payload (stranger) prova che il controllo ha guardato il chiamante giusto.
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.deposit(100 ether);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.depositedAmount(), 0);
        assertEq(token.balanceOf(address(escrow)), escrowBefore);
    }

    function test_ZeroDepositRevertsWithPreciseError() public {
        // Errore senza parametri: basta il selector.
        vm.expectRevert(TestingEscrow.ZeroAmount.selector);
        vm.prank(buyer);
        escrow.deposit(0);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
    }

    // Transizione di stato vietata: Funded non puo' tornare a ricevere un deposito.
    function test_CannotDepositTwice() public {
        _approveAndDeposit(100 ether);
        _approve(1 ether); // allowance valida: il revert deve dipendere solo dallo stato

        // Payload: stato atteso Created, stato reale Funded.
        vm.expectRevert(
            abi.encodeWithSelector(
                TestingEscrow.InvalidState.selector, TestingEscrow.State.Created, TestingEscrow.State.Funded
            )
        );
        vm.prank(buyer);
        escrow.deposit(1 ether);

        assertEq(escrow.depositedAmount(), 100 ether); // il primo deposito e' intatto
    }

    // Input con DUE difetti (chiamante sbagliato e importo zero): l'errore ricevuto rivela
    // quale controllo viene eseguito per primo. L'ordine fa parte della specifica.
    function test_PreconditionOrderChecksCallerBeforeAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.deposit(0);
    }
}

