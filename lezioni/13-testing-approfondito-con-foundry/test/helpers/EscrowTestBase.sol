// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Fixture condivisa: i test unit, integration e regression ereditano da qui lo stesso stato
// iniziale e alcuni helper, invece di ripetere il setup in ogni file.
// Cheatcode usati:
//   vm.warp(t)             imposta block.timestamp = t;
//   makeAddr("nome")       indirizzo deterministico con un'etichetta leggibile nelle trace;
//   vm.prank(a)            solo la PROSSIMA call ha msg.sender = a;
//   vm.startPrank(a)       TUTTE le call seguenti hanno msg.sender = a, fino a vm.stopPrank().
import {Test} from "forge-std/Test.sol";
import {TestingEscrow} from "../../src/TestingEscrow.sol";
import {ConfigurableToken, MockOracle} from "../../src/mocks/TestingMocks.sol";

// `abstract`: non contiene test propri e non viene eseguita da sola, serve solo da base.
abstract contract EscrowTestBase is Test {
    // Un tempo di partenza lontano da zero: cosi' `block.timestamp - MAX_PRICE_AGE` non va
    // in underflow nei test di freshness.
    uint256 internal constant START_TIME = 1_000_000;
    uint256 internal constant REFUND_DELAY = 7 days;
    uint256 internal constant BUYER_BALANCE = 10_000 ether;
    int256 internal constant FRESH_PRICE = 3_000e8;

    ConfigurableToken internal token;
    MockOracle internal oracle;
    TestingEscrow internal escrow;

    address internal buyer;
    address internal seller;
    address internal owner;
    address internal stranger; // un chiamante senza alcun ruolo: serve ai test negativi

    // `virtual`: un test derivato potrebbe ridefinire setUp (e richiamare super.setUp()).
    function setUp() public virtual {
        vm.warp(START_TIME);
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        owner = makeAddr("owner");
        stranger = makeAddr("stranger");

        // Stato iniziale: token senza fee, oracle con prezzo fresco, escrow in Created,
        // buyer con saldo ma senza allowance verso l'escrow.
        token = new ConfigurableToken();
        oracle = new MockOracle();
        oracle.setAnswer(FRESH_PRICE, block.timestamp);
        escrow =
            new TestingEscrow(address(token), address(oracle), buyer, seller, owner, block.timestamp + REFUND_DELAY);
        token.mint(buyer, BUYER_BALANCE);
    }

    // Helper "semantici": il nome dice cosa succede, il test resta corto e leggibile.
    // Approva e deposita come buyer: due call, quindi startPrank invece di prank.
    function _approveAndDeposit(uint256 amount) internal {
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
    }

    // Solo l'approve: il test fa poi la call di deposit da osservare (spesso con expectRevert).
    function _approve(uint256 amount) internal {
        vm.prank(buyer);
        token.approve(address(escrow), amount);
    }
}

