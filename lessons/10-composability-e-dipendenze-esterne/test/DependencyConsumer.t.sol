// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Cheatcode usati in questo file:
//   vm.warp(t)             imposta block.timestamp = t (si "viaggia nel tempo");
//   vm.getBlockTimestamp() timestamp corrente, letto da vm: affidabile anche dopo un warp;
//   vm.expectRevert(e)     la PROSSIMA call deve revertire con l'errore e;
//   makeAddr("nome")       indirizzo deterministico ed etichettato, senza codice.
import { Test } from "forge-std/Test.sol";
import { IValueProvider } from "../src/interfaces/IValueProvider.sol";
import { DependencyConsumer } from "../src/DependencyConsumer.sol";
import { MutableDependency } from "../src/mocks/MutableDependency.sol";

contract DependencyConsumerTest is Test {
    MutableDependency internal dependency;
    DependencyConsumer internal consumer;

    uint256 internal constant MAX_VALUE = 1_000;
    uint256 internal constant MAX_CACHE_AGE = 1 hours; // `1 hours` = 3600 secondi

    function setUp() public {
        // Partenza da un timestamp realistico: con il default (1) i calcoli di eta' sarebbero
        // poco leggibili e un timestamp 0 si confonderebbe con "mai aggiornato".
        vm.warp(1_000_000);
        dependency = new MutableDependency();
        consumer =
            new DependencyConsumer(IValueProvider(address(dependency)), MAX_VALUE, MAX_CACHE_AGE);
    }

    function test_RefreshStoresValidatedValueAndTimestamp() public {
        assertEq(consumer.refresh(), 100);
        assertEq(consumer.lastGoodValue(), 100);
        assertEq(consumer.lastUpdatedAt(), block.timestamp);
        assertEq(consumer.cachedValue(), 100);
    }

    // SAFETY e LIVENESS insieme: il provider si guasta, refresh fallisce (fail-closed), ma
    // la cache valida resta leggibile.
    function test_DependencyCanBecomeUnavailableWithoutCorruptingCache() public {
        consumer.refresh();
        dependency.setMode(MutableDependency.Mode.RevertAlways);

        vm.expectRevert(MutableDependency.Disabled.selector);
        consumer.refresh();

        assertEq(consumer.lastGoodValue(), 100);
        assertEq(consumer.cachedValue(), 100);
    }

    // I prossimi due: il provider risponde senza revertire, ma con valori invalidi.
    // Il consumer li rifiuta e non sovrascrive l'ultimo valore buono.
    function test_ZeroCannotReplaceLastGoodValue() public {
        consumer.refresh();
        dependency.setMode(MutableDependency.Mode.ReturnZero);

        vm.expectRevert(
            abi.encodeWithSelector(DependencyConsumer.InvalidValue.selector, uint256(0))
        );
        consumer.refresh();

        assertEq(consumer.lastGoodValue(), 100);
    }

    function test_ExtremeValueCannotReplaceLastGoodValue() public {
        consumer.refresh();
        dependency.setMode(MutableDependency.Mode.ReturnMaximum);

        vm.expectRevert(
            abi.encodeWithSelector(DependencyConsumer.InvalidValue.selector, type(uint256).max)
        );
        consumer.refresh();

        assertEq(consumer.lastGoodValue(), 100);
    }

    // CONFINE: eta' == MAX_CACHE_AGE deve passare, MAX_CACHE_AGE + 1 (test successivo) no.
    // Se qualcuno scrivesse `>=` al posto di `>`, questo test diventerebbe rosso.
    function test_ExactlyMaximumCacheAgeIsAccepted() public {
        consumer.refresh();
        vm.warp(vm.getBlockTimestamp() + MAX_CACHE_AGE);

        assertEq(consumer.cachedValue(), 100);
    }

    function test_RevertWhen_CacheIsStale() public {
        consumer.refresh();
        vm.warp(vm.getBlockTimestamp() + MAX_CACHE_AGE + 1);

        // L'errore riporta eta' e limite: si verificano entrambi.
        vm.expectRevert(
            abi.encodeWithSelector(
                DependencyConsumer.StaleCache.selector, MAX_CACHE_AGE + 1, MAX_CACHE_AGE
            )
        );
        consumer.cachedValue();
    }

    // Senza alcun refresh, cachedValue non deve restituire lo 0 di default.
    function test_RevertWhen_CacheWasNeverInitialized() public {
        vm.expectRevert(DependencyConsumer.CacheUnavailable.selector);
        consumer.cachedValue();
    }

    function test_RevertWhen_ProviderHasNoCode() public {
        address emptyTarget = makeAddr("provider");
        vm.expectRevert(
            abi.encodeWithSelector(DependencyConsumer.InvalidProvider.selector, emptyTarget)
        );
        new DependencyConsumer(IValueProvider(emptyTarget), MAX_VALUE, MAX_CACHE_AGE);
    }

    function test_RevertWhen_ConfigurationIsZero() public {
        vm.expectRevert(DependencyConsumer.InvalidConfiguration.selector);
        new DependencyConsumer(IValueProvider(address(dependency)), 0, MAX_CACHE_AGE);
    }
}
