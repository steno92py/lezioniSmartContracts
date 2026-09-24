// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Invariant testing (stateful fuzzing): Foundry chiama in sequenza casuale le funzioni
// dell'handler (128 run x 64 chiamate, vedi [invariant] in foundry.toml) e dopo ogni
// chiamata verifica tutte le funzioni invariant_*. Una proprieta' deve valere SEMPRE.
// Cheatcode e helper usati in questo file:
//   bound(x, min, max)       riporta un input casuale in un intervallo utile;
//   vm.prank / startPrank    impersonano i ruoli dentro l'handler;
//   vm.warp(t)               imposta block.timestamp;
//   targetContract(a)        il fuzzer chiama solo il contratto a (l'handler);
//   targetSelector(...)      ...e solo le funzioni elencate.
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {EscrowFinalFixed} from "../../src/fixed/EscrowFinalFixed.sol";
import {TestToken, MockOracle} from "../../src/mocks/FinalMocks.sol";
import {INotifierFinal} from "../../src/interfaces/IFinalDependencies.sol";

// HANDLER: fa da intermediario tra il fuzzer e l'escrow. Ogni azione prepara input validi,
// impersona il ruolo giusto ed evita chiamate destinate a revertire, cosi' le sequenze
// esplorano stati reali invece di sprecare run in revert.
contract FinalHandler is Test {
    EscrowFinalFixed public immutable escrow;
    TestToken public immutable token;
    MockOracle public immutable oracle;
    address public immutable buyer;
    address public immutable owner;
    address public immutable pauser;

    // Ghost variable: stato tenuto dal test (non dal contratto) per proprieta' storiche.
    uint256 public credited;
    bool public terminalSeen;
    bool public terminalBroken;

    constructor(
        EscrowFinalFixed escrow_,
        TestToken token_,
        MockOracle oracle_,
        address buyer_,
        address owner_,
        address pauser_
    ) {
        escrow = escrow_;
        token = token_;
        oracle = oracle_;
        buyer = buyer_;
        owner = owner_;
        pauser = pauser_;
    }

    // Precondizione: se l'azione non e' ammessa nello stato corrente si esce senza fare nulla.
    function deposit(uint96 rawAmount) external {
        if (escrow.state() != EscrowFinalFixed.State.Created || escrow.paused()) return;
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000 ether);
        token.mint(buyer, amount);
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
        credited = escrow.escrowedAmount();
        _observe();
    }

    function release() external {
        if (escrow.state() != EscrowFinalFixed.State.Funded || escrow.paused()) return;
        // Prezzo sempre fresco: la sequenza esplora il ciclo di vita, non la freschezza
        // (coperta da regression e fuzz).
        oracle.setPrice(3_000e8, block.timestamp);
        vm.prank(buyer);
        escrow.release();
        _observe();
    }

    function refund() external {
        if (escrow.state() != EscrowFinalFixed.State.Funded) return;
        vm.prank(buyer);
        escrow.refund();
        _observe();
    }

    function pause() external {
        vm.prank(pauser);
        escrow.pause();
        _observe();
    }

    function unpause() external {
        vm.prank(owner);
        escrow.unpause();
        _observe();
    }

    function setFee(uint16 rawFee) external {
        uint256 fee = bound(uint256(rawFee), 0, 1_100);
        vm.prank(owner);
        // Fino a 1_100: include valori oltre il tetto. try/catch ignora il revert atteso,
        // cosi' la sequenza continua e l'invariant sul tetto viene comunque verificata.
        try escrow.setFee(fee) {} catch {}
        _observe();
    }

    // Chiamata dopo ogni azione: ricorda se si e' visto uno stato terminale e segnala
    // se in seguito lo stato risulta non terminale.
    function _observe() private {
        EscrowFinalFixed.State current = escrow.state();
        bool terminal = current == EscrowFinalFixed.State.Released || current == EscrowFinalFixed.State.Refunded;
        if (terminalSeen && !terminal) terminalBroken = true;
        if (terminal) terminalSeen = true;
    }
}

contract FinalInvariantTest is StdInvariant, Test {
    TestToken internal token;
    MockOracle internal oracle;
    EscrowFinalFixed internal escrow;
    FinalHandler internal handler;
    address internal buyer;
    address internal seller;
    address internal owner;
    address internal pauser;

    // Il setup crea il sistema reale e registra l'handler come unico bersaglio del fuzzer.
    function setUp() public {
        vm.warp(1_000_000);
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        owner = makeAddr("owner");
        pauser = makeAddr("pauser");
        token = new TestToken();
        oracle = new MockOracle(3_000e8, block.timestamp);
        escrow = new EscrowFinalFixed(token, buyer, seller, owner, pauser, oracle, INotifierFinal(address(0)));
        handler = new FinalHandler(escrow, token, oracle, buyer, owner, pauser);

        // Le sei azioni che il fuzzer puo' combinare. bytes4 = selettore di funzione.
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = FinalHandler.deposit.selector;
        selectors[1] = FinalHandler.release.selector;
        selectors[2] = FinalHandler.refund.selector;
        selectors[3] = FinalHandler.pause.selector;
        selectors[4] = FinalHandler.unpause.selector;
        selectors[5] = FinalHandler.setFee.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    // Le cinque proprieta'. Sono `view`: leggono lo stato, non lo modificano.
    // Solvibilita': finche' Funded, il saldo reale copre la liability.
    function invariant_FundedLiabilityIsBacked() public view {
        if (escrow.state() == EscrowFinalFixed.State.Funded) {
            assertGe(token.balanceOf(address(escrow)), escrow.escrowedAmount());
        }
    }

    function invariant_TerminalStateClearsLiability() public view {
        EscrowFinalFixed.State current = escrow.state();
        if (current == EscrowFinalFixed.State.Released || current == EscrowFinalFixed.State.Refunded) {
            assertEq(escrow.escrowedAmount(), 0);
        }
    }

    // Proprieta' storica: non si deduce dallo stato attuale, serve la ghost variable.
    function invariant_TerminalStateNeverReopens() public view {
        assertFalse(handler.terminalBroken());
    }

    function invariant_FeeAlwaysWithinBound() public view {
        assertLe(escrow.feeBps(), 1_000);
    }

    // Il seller non riceve mai piu' di quanto l'escrow ha accreditato (la fee puo' solo ridurre).
    function invariant_SellerNeverReceivesMoreThanCredited() public view {
        assertLe(token.balanceOf(seller), handler.credited());
    }
}
