// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Regression suite della remediation: comportamento atteso, controlli di accesso,
// transizioni di stato e semantica della pausa.
// Cheatcode usati in questo file (oltre a quelli di FinalTestBase):
//   vm.prank(a)             la PROSSIMA call avra' msg.sender = a;
//   vm.expectRevert(e)      la PROSSIMA call deve revertire con l'errore e;
//   vm.recordLogs() / vm.getRecordedLogs()  registrano e restituiscono gli eventi emessi.
// Attenzione all'ordine: prank ed expectRevert valgono per la prossima call esterna,
// quindi devono stare subito prima della call che si vuole osservare.
import {Vm} from "forge-std/Vm.sol";
import {FinalTestBase} from "../helpers/FinalTestBase.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {SafeERC20Lite} from "../../src/libraries/SafeERC20Lite.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {TestToken, FeeToken, FalsePayoutToken, MockOracle, RevertingNotifier} from "../../src/mocks/FinalMocks.sol";

contract FixedRegressionTest is FinalTestBase {
    // Percorso felice: il buyer deposita e l'escrow passa a Funded.
    function test_BuyerCanDeposit() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        _fundFixed(token, escrow, AMOUNT);
        assertEq(escrow.escrowedAmount(), AMOUNT);
        assertEq(uint256(escrow.state()), uint256(EscrowFinalFixed.State.Funded));
    }

    function test_StrangerCannotDeposit() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        token.mint(stranger, AMOUNT);
        vm.startPrank(stranger);
        token.approve(address(escrow), AMOUNT);
        // stranger ha token e allowance: il revert dipende solo dal ruolo.
        vm.expectRevert(EscrowFinalFixed.OnlyBuyer.selector);
        escrow.deposit(AMOUNT);
        vm.stopPrank();
    }

    function test_ZeroDepositReverts() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(buyer);
        vm.expectRevert(EscrowFinalFixed.ZeroAmount.selector);
        escrow.deposit(0);
    }

    // La macchina a stati non torna indietro: deposit e' ammesso solo da Created.
    function test_DoubleDepositReverts() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        _fundFixed(token, escrow, AMOUNT);
        vm.prank(buyer);
        vm.expectRevert(EscrowFinalFixed.InvalidState.selector);
        escrow.deposit(1);
    }

    // FeeToken trattiene il 10%: la liability deve coincidere con il saldo ricevuto.
    function test_F01_DepositUsesActualReceived() public {
        FeeToken token = new FeeToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertEq(escrow.escrowedAmount(), 90 ether);
    }

    // CONFINE della freschezza: 1 ora + 1 secondo e' rifiutata, 1 ora esatta (test successivo)
    // e' accettata. Scrivere `>=` al posto di `>` farebbe fallire il secondo test.
    function test_F02_StaleOracleRejected() public {
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - 1 hours - 1);
        EscrowFinalFixed escrow = _fixed(token, oracle, INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        vm.prank(buyer);
        vm.expectRevert(EscrowFinalFixed.StalePrice.selector);
        escrow.release();
    }

    function test_F02_ExactMaxAgeAccepted() public {
        TestToken token = new TestToken();
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - 1 hours);
        EscrowFinalFixed escrow = _fixed(token, oracle, INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);
        vm.prank(buyer);
        escrow.release();
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_F03_FalseReturnTransferCannotFinalize() public {
        FalsePayoutToken token = new FalsePayoutToken();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
        _fundFixed(token, escrow, AMOUNT);

        vm.prank(buyer);
        // Errore con parametro: si confrontano selettore E indirizzo del token.
        vm.expectRevert(abi.encodeWithSelector(SafeERC20Lite.SafeTransferFailed.selector, address(token)));
        escrow.release();

        // Dopo il revert, i write di release sono stati annullati: tutto come prima.
        assertEq(uint256(escrow.state()), uint256(EscrowFinalFixed.State.Funded));
        assertEq(escrow.escrowedAmount(), AMOUNT);
    }

    function test_F04_StrangerCannotReplaceOracle() public {
        (TestToken token, EscrowFinalFixed escrow) = _standardEscrow();
        MockOracle replacement = _freshOracle();
        vm.prank(stranger);
        vm.expectRevert(EscrowFinalFixed.OnlyOwner.selector);
        escrow.setOracle(replacement);
        // Espressione senza effetti: "usa" la variabile, evitando il warning "unused".
        token; // mantiene esplicito il setup standard.
    }

    function test_F05_NotifierFailureDoesNotBlockReleaseAndIsObservable() public {
        TestToken token = new TestToken();
        RevertingNotifier notifier = new RevertingNotifier();
        EscrowFinalFixed escrow = _fixed(token, _freshOracle(), notifier);
        _fundFixed(token, escrow, AMOUNT);

        vm.recordLogs();
        vm.prank(buyer);
        escrow.release();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Si cerca l'evento per firma: topics[0] = keccak256 della firma dell'evento.
        bytes32 failureTopic = keccak256("NotificationFailed(bytes)");
        bool found;
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].topics[0] == failureTopic) found = true;
        }
        assertTrue(found, "notification failure deve essere osservabile");
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_ReleaseClearsLiability() public {
        (TestToken token, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.prank(buyer);
        escrow.release();
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_RefundClearsLiability() public {
        (TestToken token, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.prank(buyer);
        escrow.refund();
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(buyer), AMOUNT);
    }

    // Stati terminali: dopo Released ne' release ne' refund sono piu' possibili.
    // startPrank qui serve perche' le call del buyer sono due.
    function test_DoubleReleaseReverts() public {
        (, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.startPrank(buyer);
        escrow.release();
        vm.expectRevert(EscrowFinalFixed.InvalidState.selector);
        escrow.release();
        vm.stopPrank();
    }

    function test_RefundAfterReleaseReverts() public {
        (, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.startPrank(buyer);
        escrow.release();
        vm.expectRevert(EscrowFinalFixed.InvalidState.selector);
        escrow.refund();
        vm.stopPrank();
    }

    function test_OnlyPauserCanPause() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(stranger);
        vm.expectRevert(EscrowFinalFixed.OnlyPauser.selector);
        escrow.pause();
        vm.prank(pauser);
        escrow.pause();
        assertTrue(escrow.paused());
    }

    function test_OnlyOwnerCanUnpause() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(pauser);
        escrow.pause();
        vm.prank(stranger);
        vm.expectRevert(EscrowFinalFixed.OnlyOwner.selector);
        escrow.unpause();
        vm.prank(owner);
        escrow.unpause();
        assertFalse(escrow.paused());
    }

    // CONFINE della fee: 1_000 bps accettato, 1_001 rifiutato.
    function test_FeeUpperBound() public {
        (, EscrowFinalFixed escrow) = _standardEscrow();
        vm.prank(owner);
        escrow.setFee(1_000);
        assertEq(escrow.feeBps(), 1_000);
        vm.prank(owner);
        vm.expectRevert(EscrowFinalFixed.FeeTooHigh.selector);
        escrow.setFee(1_001);
    }

    // Specifica: la pausa blocca nuovo rischio, non l'uscita del buyer.
    function test_RefundRemainsAvailableWhilePaused() public {
        (TestToken token, EscrowFinalFixed escrow) = _fundedStandardEscrow();
        vm.prank(pauser);
        escrow.pause();
        vm.prank(buyer);
        escrow.refund();
        assertEq(token.balanceOf(buyer), AMOUNT, "pause new risk, allow exit");
    }

    // Helper: token standard, oracle fresco, nessun notifier. Return con nome.
    function _standardEscrow() internal returns (TestToken token, EscrowFinalFixed escrow) {
        token = new TestToken();
        escrow = _fixed(token, _freshOracle(), INotifierFinal(address(0)));
    }

    function _fundedStandardEscrow() internal returns (TestToken token, EscrowFinalFixed escrow) {
        (token, escrow) = _standardEscrow();
        _fundFixed(token, escrow, AMOUNT);
    }
}

