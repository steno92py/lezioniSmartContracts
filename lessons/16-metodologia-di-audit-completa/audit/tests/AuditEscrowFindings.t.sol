// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// PoC sul target congelato. Ogni test AUD-* / OBS-* PASSA perche' dimostra il problema:
// e' evidenza del finding, non un'approvazione del contratto. Leggere dopo le proprie ipotesi
// (README, "Percorso guidato"). Per vedere la catena delle call: -vvvv.
//
// Cheatcode e helper usati in questo file:
//   makeAddr("nome")              indirizzo deterministico con etichetta nei trace;
//   vm.warp(t)                    imposta block.timestamp = t;
//   vm.prank(a)                   la PROSSIMA call avra' msg.sender = a;
//   vm.startPrank(a)/stopPrank()  tutte le call nel mezzo avranno msg.sender = a;
//   vm.expectRevert(e)            la PROSSIMA call deve revertire con l'errore e.
import {Test} from "forge-std/Test.sol";
import {AuditEscrow} from "../../src/target/AuditEscrow.sol";
import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../../src/interfaces/IAuditDependencies.sol";
import {
    MockToken,
    FeeToken,
    ReentrantToken,
    MockOracle,
    RecordingNotifier,
    RevertingNotifier
} from "../../src/mocks/AuditMocks.sol";

contract AuditEscrowFindingsTest is Test {
    uint256 internal constant AMOUNT = 100 ether;
    uint256 internal constant MIN_PRICE = 100e8;
    uint256 internal constant MAX_AGE = 1 hours;

    address internal buyer;
    address internal seller;
    address internal governance;
    address internal guardian;
    address internal stranger;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        governance = makeAddr("governance");
        guardian = makeAddr("guardian");
        stranger = makeAddr("stranger");
        // Tempo iniziale lontano da zero: cosi' block.timestamp - MAX_AGE non va in underflow.
        vm.warp(1_000_000);
    }

    // BASELINE: prima di cercare bug si verifica che il flusso previsto funzioni.
    // Senza baseline una PoC che reverte potrebbe fallire per un setup sbagliato.
    function test_Baseline_HappyPathWorks() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RecordingNotifier notifier = new RecordingNotifier();
        AuditEscrow escrow = _deploy(token, oracle, notifier);
        _fundAndDeposit(token, escrow);

        // release e' permissionless: la chiama un indirizzo qualunque.
        vm.prank(stranger);
        escrow.release();

        assertEq(token.balanceOf(seller), AMOUNT);
        assertEq(escrow.liability(), 0);
        assertEq(uint256(escrow.state()), uint256(AuditEscrow.State.Released));
        assertEq(notifier.calls(), 1);
    }

    function test_AUD01_ReentrantTokenPaysSameLiabilityTwice() public {
        ReentrantToken token = new ReentrantToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        AuditEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));

        // ARRANGE: deposito normale, riserva extra nell'escrow, poi si arma il callback.
        _fundAndDeposit(token, escrow);
        token.mint(address(escrow), AMOUNT); // riserva di un altro utente/protocollo
        token.configure(address(escrow));

        // ACT: una sola release esterna; il token richiama release durante il transfer.
        escrow.release();

        // ASSERT: il callback e' avvenuto ed e' riuscito; il seller ha ricevuto due volte.
        assertTrue(token.callbackAttempted());
        assertTrue(token.callbackSucceeded());
        assertEq(token.balanceOf(seller), AMOUNT * 2, "stessa liability pagata due volte");
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_AUD02_FeeTokenCreatesInsolventNominalLiability() public {
        FeeToken token = new FeeToken(1_000); // 10%
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        AuditEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));

        _fundAndDeposit(token, escrow);

        // Passivita' registrata 100, saldo reale 90: assertLt verifica a < b.
        assertEq(escrow.liability(), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 90 ether);
        assertLt(token.balanceOf(address(escrow)), escrow.liability());

        // Conseguenza: il payout di 100 fallisce per saldo insufficiente nel token.
        vm.expectRevert(MockToken.InsufficientBalance.selector);
        escrow.release();
    }

    function test_AUD03_GuardianCanBypassGovernanceAndForceSettlement() public {
        MockToken token = new MockToken();
        MockOracle lowOracle = new MockOracle(int256(MIN_PRICE - 1), block.timestamp);
        MockOracle manipulatedOracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        AuditEscrow escrow = _deploy(token, lowOracle, ISettlementNotifier(address(0)));
        _fundAndDeposit(token, escrow);
        // Con lowOracle (MIN_PRICE - 1) release reverterebbe con InvalidPrice.

        // ACT: il guardian sostituisce l'oracle con uno che soddisfa la soglia.
        vm.prank(guardian);
        escrow.setOracle(manipulatedOracle);

        vm.prank(stranger);
        escrow.release();
        assertEq(token.balanceOf(seller), AMOUNT, "guardian ha anticipato il settlement");
    }

    function test_AUD04_ExactStalenessBoundaryIsAccepted() public {
        MockToken token = new MockToken();
        // CONFINE: prezzo aggiornato esattamente MAX_AGE secondi fa.
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp - MAX_AGE);
        AuditEscrow escrow = _deploy(token, oracle, ISettlementNotifier(address(0)));
        _fundAndDeposit(token, escrow);

        escrow.release();

        assertEq(token.balanceOf(seller), AMOUNT);
    }

    function test_OBS01_RevertingOptionalNotifierBlocksSettlement() public {
        MockToken token = new MockToken();
        MockOracle oracle = new MockOracle(int256(MIN_PRICE), block.timestamp);
        RevertingNotifier notifier = new RevertingNotifier();
        AuditEscrow escrow = _deploy(token, oracle, notifier);
        _fundAndDeposit(token, escrow);

        // Il revert atteso e' quello del notifier, propagato dall'escrow.
        vm.expectRevert(RevertingNotifier.NotificationUnavailable.selector);
        escrow.release();

        // Tutto annullato: lo stato resta Funded e i fondi restano nell'escrow.
        // Un enum si confronta convertendolo a uint256.
        assertEq(uint256(escrow.state()), uint256(AuditEscrow.State.Funded));
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
    }

    // HELPER. `token` e' tipizzato come interfaccia: accetta MockToken e tutti i derivati.
    function _deploy(IAuditToken token, IPriceOracle oracle, ISettlementNotifier notifier)
        internal
        returns (AuditEscrow)
    {
        return new AuditEscrow(buyer, seller, governance, guardian, token, oracle, notifier, MIN_PRICE, MAX_AGE);
    }

    function _fundAndDeposit(MockToken token, AuditEscrow escrow) internal {
        token.mint(buyer, AMOUNT);
        vm.startPrank(buyer);
        token.approve(address(escrow), AMOUNT);
        escrow.deposit(AMOUNT);
        vm.stopPrank();
    }
}

