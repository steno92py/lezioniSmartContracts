// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Regression test delle due correzioni: stesso attacco del test vulnerabile, esito opposto.
// Cheatcode e helper: come in VulnerableVault.t.sol (makeAddr, vm.deal, vm.prank,
// vm.expectRevert). Qui il receiver e' chiamato direttamente dal test, quindi durante
// depositIntoVault e startWithdrawal il chiamante e' questo contratto di test.
import { Test } from "forge-std/Test.sol";
import { SafeVaultCEI } from "../src/reentrancy/SafeVaultCEI.sol";
import { SafeVaultGuarded } from "../src/reentrancy/SafeVaultGuarded.sol";
import { DidacticReentrancyGuard } from "../src/utils/DidacticReentrancyGuard.sol";
import {
    IVault,
    LocalReentrantProbe,
    RejectingVaultReceiver
} from "./helpers/ReentrancyReceivers.sol";

contract SafeVaultsTest is Test {
    function test_CEI_PreventsReuseOfCredit() public {
        // ARRANGE: 2 ETH di utenti onesti, cioe' fondi che un attacco potrebbe rubare.
        SafeVaultCEI safe = new SafeVaultCEI();
        _addHonestLiquidity(IVault(address(safe)), 2 ether);

        // Il probe deposita 1 ETH: e' tutto cio' che potra' legittimamente ritirare.
        LocalReentrantProbe receiver = new LocalReentrantProbe(IVault(address(safe)));
        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        assertEq(address(safe).balance, 3 ether);
        assertEq(safe.credit(address(receiver)), 1 ether);

        // ACT: withdraw -> receive -> tentativo di withdraw annidato.
        receiver.startWithdrawal();

        // ASSERT 1: il rientro e' stato TENTATO. Senza questo controllo il test passerebbe
        // anche se la callback non fosse mai partita, senza dimostrare niente.
        assertTrue(receiver.attemptedReentry());
        // ASSERT 2: il rientro e' fallito per il motivo giusto: il credito era gia' 0.
        assertFalse(receiver.reentrySucceeded());
        assertEq(receiver.reentryError(), SafeVaultCEI.NoCredit.selector);
        // ASSERT 3: il payout legittimo e' avvenuto una sola volta.
        assertEq(address(receiver).balance, 1 ether);
        assertEq(safe.credit(address(receiver)), 0);
        // ASSERT 4: i fondi onesti sono intatti e la contabilita' torna (assets == liabilities).
        assertEq(address(safe).balance, 2 ether);
        assertEq(safe.totalCredits(), 2 ether);
        assertEq(address(safe).balance, safe.totalCredits());
    }

    // Stesso scenario sulla variante con guard. Cambia solo il motivo del rifiuto.
    function test_GuardAndCEI_BlockReentry() public {
        SafeVaultGuarded safe = new SafeVaultGuarded();
        _addHonestLiquidity(IVault(address(safe)), 2 ether);

        LocalReentrantProbe receiver = new LocalReentrantProbe(IVault(address(safe)));
        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        receiver.startWithdrawal();

        assertTrue(receiver.attemptedReentry());
        assertFalse(receiver.reentrySucceeded());
        // Qui a fermare il rientro e' il lucchetto (ReentrantCall), prima ancora del CHECK
        // sul credito: il modifier gira prima del corpo della funzione.
        assertEq(receiver.reentryError(), DidacticReentrancyGuard.ReentrantCall.selector);
        assertEq(address(receiver).balance, 1 ether);
        assertEq(safe.credit(address(receiver)), 0);
        assertEq(address(safe).balance, 2 ether);
        assertEq(safe.totalCredits(), 2 ether);
    }

    // CEI azzera il credito PRIMA di pagare. Se il pagamento fallisce, il credito non deve
    // andare perso: il revert di TransferFailed annulla anche gli EFFECTS.
    function test_CEI_RestoresAccountingWhenReceiverRejectsPayout() public {
        SafeVaultCEI safe = new SafeVaultCEI();
        RejectingVaultReceiver receiver = new RejectingVaultReceiver(IVault(address(safe)));

        vm.deal(address(this), 1 ether);
        receiver.depositIntoVault{ value: 1 ether }();

        // Il revert nasce nel vault e risale attraverso startWithdrawal fino al test.
        vm.expectRevert(SafeVaultCEI.TransferFailed.selector);
        receiver.startWithdrawal();

        // Stato identico a prima del withdraw: credito, totale e saldi.
        assertEq(safe.credit(address(receiver)), 1 ether);
        assertEq(safe.totalCredits(), 1 ether);
        assertEq(address(safe).balance, 1 ether);
        assertEq(address(receiver).balance, 0);
    }

    // Helper: un utente onesto deposita `amount`. `internal`: non e' un test.
    function _addHonestLiquidity(IVault vault, uint256 amount) internal {
        address honestUser = makeAddr("honest-user");
        vm.deal(honestUser, amount);
        vm.prank(honestUser);
        vault.deposit{ value: amount }();
    }
}
