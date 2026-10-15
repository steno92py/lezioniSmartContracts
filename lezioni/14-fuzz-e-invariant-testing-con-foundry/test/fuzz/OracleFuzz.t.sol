// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Fuzz test della freshness: si fuzza l'ETA' del prezzo, con due domini distinti,
// uno valido (0..MAX_AGE) e uno stale (oltre MAX_AGE). Cheatcode: vm.warp.
import {Test} from "forge-std/Test.sol";
import {FreshPriceConsumer, MutableOracle} from "../../src/fuzz/FuzzTargets.sol";

contract OracleFuzzTest is Test {
    // "Adesso" fissato lontano da zero, cosi' `NOW - MAX_AGE - 30 days` non va in underflow.
    uint256 internal constant NOW = 100_000_000;
    int256 internal constant PRICE = 3_000e8;

    MutableOracle internal oracle;
    FreshPriceConsumer internal consumer;

    function setUp() public {
        vm.warp(NOW);
        oracle = new MutableOracle();
        consumer = new FreshPriceConsumer(oracle);
    }

    // Dominio valido: eta' da 0 a MAX_AGE compreso.
    function testFuzz_FreshPriceIsAccepted(uint256 rawAge) public {
        uint256 age = bound(rawAge, 0, consumer.MAX_AGE());
        oracle.setAnswer(PRICE, block.timestamp - age);

        assertEq(consumer.readPrice(), PRICE);
    }

    // Dominio stale: da 1 secondo a 30 giorni oltre MAX_AGE.
    function testFuzz_StalePriceIsRejected(uint256 rawExtra) public {
        uint256 extra = bound(rawExtra, 1, 30 days);
        uint256 updatedAt = block.timestamp - consumer.MAX_AGE() - extra;
        oracle.setAnswer(PRICE, updatedAt);

        vm.expectRevert(abi.encodeWithSelector(FreshPriceConsumer.StalePrice.selector, updatedAt, block.timestamp));
        consumer.readPrice();
    }

    // Da uint256 a int256 si passa per un valore <= uint128.max: la conversione non puo'
    // produrre un numero negativo.
    function testFuzz_EveryPositivePriceInDomainIsReturned(uint128 rawPrice) public {
        int256 price = int256(uint256(bound(rawPrice, 1, type(uint128).max)));
        oracle.setAnswer(price, block.timestamp);

        assertEq(consumer.readPrice(), price);
    }

    // Il confine esatto resta un test deterministico: nel fuzz sopra e' solo uno dei tanti
    // valori possibili e non e' garantito che venga provato.
    function test_Regression_ExactFreshnessBoundaryIsAccepted() public {
        oracle.setAnswer(PRICE, block.timestamp - consumer.MAX_AGE());
        assertEq(consumer.readPrice(), PRICE);
    }

    function test_Regression_FutureTimestampIsRejected() public {
        uint256 future = block.timestamp + 1;
        oracle.setAnswer(PRICE, future);

        vm.expectRevert(abi.encodeWithSelector(FreshPriceConsumer.FutureTimestamp.selector, future, block.timestamp));
        consumer.readPrice();
    }

    function test_Regression_ZeroPriceIsRejected() public {
        oracle.setAnswer(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(FreshPriceConsumer.InvalidPrice.selector, 0));
        consumer.readPrice();
    }
}

