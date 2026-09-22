// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IValueProvider } from "./interfaces/IValueProvider.sol";

/// @notice Provider critico fail-closed con cache esplicitamente limitata nel tempo.
contract DependencyConsumer {
    error InvalidProvider(address provider);
    error InvalidConfiguration();
    error InvalidValue(uint256 value);
    error CacheUnavailable();
    error StaleCache(uint256 age, uint256 maximumAge);

    IValueProvider public immutable provider;
    uint256 public immutable maximumValue;
    uint256 public immutable maximumCacheAge;

    uint256 public lastGoodValue;
    uint256 public lastUpdatedAt;

    constructor(IValueProvider provider_, uint256 maximumValue_, uint256 maximumCacheAge_) {
        if (address(provider_).code.length == 0) {
            revert InvalidProvider(address(provider_));
        }
        if (maximumValue_ == 0 || maximumCacheAge_ == 0) revert InvalidConfiguration();

        provider = provider_;
        maximumValue = maximumValue_;
        maximumCacheAge = maximumCacheAge_;
    }

    function refresh() external returns (uint256 newValue) {
        newValue = provider.value();
        if (newValue == 0 || newValue > maximumValue) revert InvalidValue(newValue);

        lastGoodValue = newValue;
        lastUpdatedAt = block.timestamp;
    }

    function cachedValue() external view returns (uint256) {
        uint256 updatedAt = lastUpdatedAt;
        if (updatedAt == 0) revert CacheUnavailable();

        uint256 age = block.timestamp - updatedAt;
        if (age > maximumCacheAge) revert StaleCache(age, maximumCacheAge);

        return lastGoodValue;
    }
}

