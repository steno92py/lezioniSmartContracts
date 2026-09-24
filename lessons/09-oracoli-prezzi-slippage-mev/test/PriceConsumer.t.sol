// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   vm.warp(t)          imposta block.timestamp a t: si "viaggia nel tempo" senza aspettare;
//   vm.expectRevert(e)  la PROSSIMA call deve revertire con l'errore e;
//   makeAddr("nome")    crea un indirizzo deterministico ed etichettato nei trace (senza codice).
import { Test } from "forge-std/Test.sol";
import { IPriceOracle } from "../src/oracle/IPriceOracle.sol";
import { MockPriceOracle } from "../src/mocks/MockPriceOracle.sol";
import { PriceConsumer } from "../src/PriceConsumer.sol";
import { VulnerableValuation } from "../src/VulnerableValuation.sol";

contract PriceConsumerTest is Test {
    MockPriceOracle internal oracle;
    PriceConsumer internal consumer;

    uint256 internal constant MAX_AGE = 1 hours; // `1 hours` = 3600 secondi
    int256 internal constant PRICE_8 = 3_000e8; // 3000 QUOTE per BASE, feed a 8 decimals

    function setUp() public {
        // In Foundry block.timestamp parte da 1: senza questo warp calcoli come
        // block.timestamp - MAX_AGE - 1 andrebbero sotto zero e la call revertirebbe.
        vm.warp(1_000_000);
        oracle = new MockPriceOracle(8);
        consumer = new PriceConsumer(IPriceOracle(address(oracle)), MAX_AGE);
        oracle.setPrice(PRICE_8, block.timestamp); // prezzo valido e fresco
    }

    // `view` su un test: non modifica lo stato, legge soltanto.
    function test_ReadFreshPositivePrice() public view {
        assertEq(consumer.readPrice(), uint256(PRICE_8));
        assertEq(consumer.priceDecimals(), 8);
        assertEq(consumer.maxAge(), MAX_AGE);
    }

    // CONVERSIONI: il risultato atteso si scrive a mano, con le unita', prima di eseguire.
    // 1 BASE (1e18) a 3000 QUOTE/BASE = 3000 QUOTE = 3000e6 con 6 decimals.
    function test_QuoteOneBaseAssetIntoSixDecimalQuote() public view {
        assertEq(consumer.quote18To6(1 ether), 3_000e6); // `1 ether` = 1e18
    }

    function test_QuoteFractionPreservesExpectedScaling() public view {
        assertEq(consumer.quote18To6(0.25 ether), 750e6); // un quarto: 750 QUOTE
    }

    // Stesso prezzo economico espresso con scale diverse: il risultato non deve cambiare.
    function test_EightAndEighteenDecimalFeedsGiveSameEconomicQuote() public {
        MockPriceOracle oracle18 = new MockPriceOracle(18);
        PriceConsumer consumer18 = new PriceConsumer(IPriceOracle(address(oracle18)), MAX_AGE);
        oracle18.setPrice(3_000e18, block.timestamp);

        assertEq(consumer.quote18To6(1 ether), consumer18.quote18To6(1 ether));
    }

    // Prezzo enorme: 1e18 * type(int256).max supera 2^256. Una moltiplicazione normale
    // revertirebbe; mulDiv restituisce comunque il risultato giusto (qui denominatore 1e20).
    function test_MulDivHandlesOverflowingIntermediateProduct() public {
        oracle.setPrice(type(int256).max, block.timestamp);

        assertEq(consumer.quote18To6(1 ether), uint256(type(int256).max) / 100);
    }

    // CONFINE della freshness: eta' esattamente MAX_AGE deve passare, MAX_AGE + 1
    // (test_RevertWhen_PriceIsStale) deve fallire. Insieme bloccano uno scambio `>` / `>=`.
    function test_ExactlyMaxAgeIsAccepted() public {
        uint256 updateTime = block.timestamp;
        vm.warp(updateTime + MAX_AGE);

        assertEq(consumer.readPrice(), uint256(PRICE_8));
    }

    // TEST NEGATIVI: un test per ogni controllo di readPrice, ciascuno col suo errore preciso.
    // Se due controlli restituissero lo stesso errore non sapremmo quale ha fatto il lavoro.
    function test_RevertWhen_PriceIsZero() public {
        oracle.setPrice(0, block.timestamp);
        vm.expectRevert(PriceConsumer.InvalidPrice.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_PriceIsNegative() public {
        oracle.setPrice(-1, block.timestamp);
        vm.expectRevert(PriceConsumer.InvalidPrice.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_TimestampIsZero() public {
        oracle.setPrice(PRICE_8, 0);
        vm.expectRevert(PriceConsumer.InvalidTimestamp.selector);
        consumer.readPrice();
    }

    // Basta un secondo nel futuro: il valore piu' vicino al confine che deve fallire.
    function test_RevertWhen_TimestampIsInFuture() public {
        oracle.setPrice(PRICE_8, block.timestamp + 1);
        vm.expectRevert(PriceConsumer.InvalidTimestamp.selector);
        consumer.readPrice();
    }

    function test_RevertWhen_PriceIsStale() public {
        vm.warp(block.timestamp + MAX_AGE + 1); // un secondo oltre il limite
        vm.expectRevert(PriceConsumer.StalePrice.selector);
        consumer.readPrice();
    }

    // Anche i controlli del constructor si testano: expectRevert vale per il deploy con `new`.
    function test_RevertWhen_MaxAgeIsZero() public {
        vm.expectRevert(PriceConsumer.InvalidMaxAge.selector);
        new PriceConsumer(IPriceOracle(address(oracle)), 0);
    }

    function test_RevertWhen_OracleHasNoCode() public {
        address notAContract = makeAddr("not-a-contract");
        vm.expectRevert(abi.encodeWithSelector(PriceConsumer.InvalidOracle.selector, notAContract));
        new PriceConsumer(IPriceOracle(notAContract), MAX_AGE);
    }

    // 19 e' il primo valore oltre MAX_ORACLE_DECIMALS (18).
    function test_RevertWhen_OracleDecimalsAreUnsupported() public {
        MockPriceOracle unsupported = new MockPriceOracle(19);
        vm.expectRevert(abi.encodeWithSelector(PriceConsumer.UnsupportedDecimals.selector, 19));
        new PriceConsumer(IPriceOracle(address(unsupported)), MAX_AGE);
    }

    // TEST "VULNERABLE": passano perche' l'errore si verifica davvero. Documentano il bug;
    // i test negativi qui sopra dimostrano che PriceConsumer lo corregge.

    /// @dev Il test passa dimostrando che il consumer vulnerabile usa un prezzo scaduto.
    function test_Vulnerable_StalePriceIsStillAccepted() public {
        VulnerableValuation vulnerable = new VulnerableValuation(IPriceOracle(address(oracle)));
        // Stesso dato che PriceConsumer rifiuterebbe con StalePrice.
        oracle.setPrice(PRICE_8, block.timestamp - MAX_AGE - 1);

        assertEq(vulnerable.valueOf(1), uint256(PRICE_8));
    }

    /// @dev Moltiplicare numeri scalati non produce automaticamente l'unita' desiderata.
    function test_Vulnerable_RawMultiplicationHasWrongUnits() public {
        VulnerableValuation vulnerable = new VulnerableValuation(IPriceOracle(address(oracle)));

        uint256 wrong = vulnerable.valueOf(1 ether);
        uint256 correct = consumer.quote18To6(1 ether);

        // 1e18 * 3000e8 = 3000e26: sbagliato di un fattore 1e20 rispetto a 3000e6.
        assertEq(wrong, 3_000e26);
        assertEq(correct, 3_000e6);
        assertNotEq(wrong, correct);
    }
}
