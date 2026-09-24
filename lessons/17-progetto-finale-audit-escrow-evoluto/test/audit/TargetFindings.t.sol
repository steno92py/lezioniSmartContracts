// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Proof of Concept sul target. Leggile DOPO la tua review (README, workflow passo 4):
// ogni test PASSA quando il comportamento riprodotto si verifica davvero.
// Cheatcode usati in questo file (oltre a quelli di FinalTestBase):
//   vm.prank(a)             la PROSSIMA call avra' msg.sender = a;
//   vm.recordLogs()         da qui in poi Foundry registra gli eventi emessi;
//   vm.getRecordedLogs()    restituisce gli eventi registrati come Vm.Log[].
// Ogni test segue ARRANGE (dipendenze + escrow), ACT (la call), ASSERT (lo stato osservato).
import {Vm} from "forge-std/Vm.sol";
import {FinalTestBase} from "../helpers/FinalTestBase.sol";
import {EscrowFinal} from "../../src/EscrowFinal.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";
import {TestToken, FeeToken, FalsePayoutToken, MockOracle, RevertingNotifier} from "../../src/mocks/FinalMocks.sol";

contract TargetFindingsTest is FinalTestBase {
    function test_F01_NominalAccountingExceedsReceivedAssets() public {
        // INotifierFinal(address(0)): nessun notifier, cast dell'indirizzo zero all'interfaccia.
        FeeToken token = new FeeToken();
        MockOracle oracle = _freshOracle();
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));

        _fundTarget(token, escrow, AMOUNT);

        // Si confrontano due numeri: il saldo reale del token e la liability registrata.
        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertEq(escrow.escrowedAmount(), AMOUNT);
        assertLt(token.balanceOf(address(escrow)), escrow.escrowedAmount()); // Lt: minore stretto
    }

    function test_F02_StaleOracleStillAllowsRelease() public {
        TestToken token = new TestToken();
        // Campione di prezzo con timestamp di due ore fa.
        MockOracle oracle = new MockOracle(VALID_PRICE, block.timestamp - 2 hours);
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));
        _fundTarget(token, escrow, AMOUNT);

        vm.prank(buyer);
        escrow.release();

        // Un enum non si confronta direttamente con assertEq: si converte a uint256.
        assertEq(uint256(escrow.state()), uint256(EscrowFinal.State.Released));
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_F03_FalseReturnCreatesFalseTerminalSuccess() public {
        FalsePayoutToken token = new FalsePayoutToken();
        MockOracle oracle = _freshOracle();
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));
        _fundTarget(token, escrow, AMOUNT);

        vm.prank(buyer);
        escrow.release();

        // Si confronta cio' che dice lo stato del contratto con dove sono davvero i token.
        assertEq(uint256(escrow.state()), uint256(EscrowFinal.State.Released));
        assertEq(escrow.escrowedAmount(), 0);
        assertEq(token.balanceOf(seller), 0);
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
    }

    function test_F04_StrangerCanReplaceOracle() public {
        TestToken token = new TestToken();
        MockOracle oracle = _freshOracle();
        MockOracle attackerOracle = new MockOracle(1, block.timestamp);
        EscrowFinal escrow = _target(token, oracle, INotifierFinal(address(0)));

        vm.prank(stranger);
        escrow.setOracle(attackerOracle);

        assertEq(address(escrow.oracle()), address(attackerOracle));
    }

    function test_F05_NotifierFailureIsSilentButSettlementContinues() public {
        TestToken token = new TestToken();
        MockOracle oracle = _freshOracle();
        RevertingNotifier notifier = new RevertingNotifier();
        EscrowFinal escrow = _target(token, oracle, notifier);
        _fundTarget(token, escrow, AMOUNT);

        // Registrazione avviata subito prima della call: si catturano solo gli eventi di release.
        vm.recordLogs();
        vm.prank(buyer);
        escrow.release();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // topics[0] di un evento e' keccak256 della sua firma: identifica il tipo di evento.
        // Nota: il Transfer del TestToken non compare perche' il mock non emette eventi.
        assertEq(entries.length, 1, "solo Released: il notifier failure non e' osservabile");
        assertEq(entries[0].topics[0], keccak256("Released(uint256,uint256)"));
        assertEq(token.balanceOf(seller), AMOUNT);
    }
}
