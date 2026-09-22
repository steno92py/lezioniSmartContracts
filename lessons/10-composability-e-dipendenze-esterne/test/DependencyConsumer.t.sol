// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { Test } from "forge-std/Test.sol";
import { IValueProvider } from "../src/interfaces/IValueProvider.sol";
import { DependencyConsumer } from "../src/DependencyConsumer.sol";
import { MutableDependency } from "../src/mocks/MutableDependency.sol";

contract DependencyConsumerTest is Test {
    MutableDependency internal dependency;
    DependencyConsumer internal consumer;

    uint256 internal constant MAX_VALUE = 1_000;
    uint256 internal constant MAX_CACHE_AGE = 1 hours;

    function setUp() public {
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

    function test_DependencyCanBecomeUnavailableWithoutCorruptingCache() public {
        consumer.refresh();
        dependency.setMode(MutableDependency.Mode.RevertAlways);

        vm.expectRevert(MutableDependency.Disabled.selector);
        consumer.refresh();

        assertEq(consumer.lastGoodValue(), 100);
        assertEq(consumer.cachedValue(), 100);
    }

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

    function test_ExactlyMaximumCacheAgeIsAccepted() public {
        consumer.refresh();
        vm.warp(vm.getBlockTimestamp() + MAX_CACHE_AGE);

        assertEq(consumer.cachedValue(), 100);
    }

    function test_RevertWhen_CacheIsStale() public {
        consumer.refresh();
        vm.warp(vm.getBlockTimestamp() + MAX_CACHE_AGE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                DependencyConsumer.StaleCache.selector, MAX_CACHE_AGE + 1, MAX_CACHE_AGE
            )
        );
        consumer.cachedValue();
    }

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

