// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Regression test sui token "strani": il ConfigurableToken riproduce comportamenti reali
// (return false, fee-on-transfer) che un escrow ingenuo trasformerebbe in crediti falsi.
// Schema comune: configura il token, prova l'azione, verifica il revert preciso E che stato,
// liability e saldi siano esattamente quelli di prima (rollback atomico).
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {EscrowTestBase} from "../helpers/EscrowTestBase.sol";

contract TokenBehaviorRegressionTest is EscrowTestBase {
    // transferFrom restituisce false senza muovere token: se l'escrow ignorasse il valore
    // di ritorno, registrerebbe un deposito mai pagato.
    function test_Regression_FalseReturnCannotCreateDepositCredit() public {
        uint256 amount = 100 ether;
        token.configure(0, true, false); // nessuna fee, transfer ok, transferFrom -> false
        _approve(amount);

        vm.expectRevert(TestingEscrow.TokenCallFailed.selector);
        vm.prank(buyer);
        escrow.deposit(amount);

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.depositedAmount(), 0);
        assertEq(token.balanceOf(buyer), BUYER_BALANCE);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    // Fee dell'1%: arrivano 99 ether invece di 100. Il controllo di balance delta rifiuta
    // il deposito invece di promettere 100 ether coperti da 99.
    function test_Regression_FeeOnTransferCannotCreateUnbackedLiability() public {
        uint256 amount = 100 ether;
        token.configure(100, true, true);
        _approve(amount);

        vm.expectRevert(abi.encodeWithSelector(TestingEscrow.UnexpectedReceived.selector, amount, 99 ether));
        vm.prank(buyer);
        escrow.deposit(amount);

        // Anche il transfer gia' avvenuto e' annullato: il buyer ha di nuovo tutto il saldo.
        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Created));
        assertEq(escrow.liability(), 0);
        assertEq(token.balanceOf(buyer), BUYER_BALANCE);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    // release() scrive Released PRIMA di pagare. Se il pagamento fallisce, il revert deve
    // riportare tutto a Funded: altrimenti l'escrow sarebbe "chiuso" con i token ancora dentro.
    function test_Regression_FailedPayoutRollsBackTerminalState() public {
        uint256 amount = 100 ether;
        _approveAndDeposit(amount);
        token.configure(0, false, true); // da ora transfer restituisce false

        vm.expectRevert(TestingEscrow.TokenCallFailed.selector);
        vm.prank(buyer);
        escrow.release();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Funded));
        assertEq(escrow.depositedAmount(), amount);
        assertEq(escrow.liability(), amount);
        assertEq(token.balanceOf(address(escrow)), amount);
        assertEq(token.balanceOf(seller), 0);
    }

    // Stessa proprieta' per refund(). Il warp alla deadline esclude RefundTooEarly:
    // l'unica causa di revert rimasta e' il token.
    function test_Regression_FailedRefundRollsBackAccounting() public {
        uint256 amount = 100 ether;
        _approveAndDeposit(amount);
        token.configure(0, false, true);
        vm.warp(escrow.refundDeadline());

        vm.expectRevert(TestingEscrow.TokenCallFailed.selector);
        vm.prank(buyer);
        escrow.refund();

        assertEq(uint256(escrow.state()), uint256(TestingEscrow.State.Funded));
        assertEq(escrow.liability(), amount);
        assertEq(token.balanceOf(address(escrow)), amount);
    }
}

