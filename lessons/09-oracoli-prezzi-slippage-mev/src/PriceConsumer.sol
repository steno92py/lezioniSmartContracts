// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { MulDivLite } from "./math/MulDivLite.sol";
import { IPriceOracle } from "./oracle/IPriceOracle.sol";

/// @title PriceConsumer
/// @notice Converte importi a 18 decimals in quote units a 6 decimals.
contract PriceConsumer {
    error InvalidOracle(address oracle);
    error InvalidMaxAge();
    error UnsupportedDecimals(uint8 decimals);
    error InvalidPrice();
    error InvalidTimestamp();
    error StalePrice();

    uint8 public constant INPUT_DECIMALS = 18;
    uint8 public constant OUTPUT_DECIMALS = 6;
    uint8 public constant MAX_ORACLE_DECIMALS = 18;

    IPriceOracle public immutable oracle;
    uint256 public immutable maxAge;
    uint8 public immutable priceDecimals;

    constructor(IPriceOracle oracle_, uint256 maxAge_) {
        if (address(oracle_).code.length == 0) revert InvalidOracle(address(oracle_));
        if (maxAge_ == 0) revert InvalidMaxAge();

        uint8 decimals_ = oracle_.decimals();
        if (decimals_ > MAX_ORACLE_DECIMALS) revert UnsupportedDecimals(decimals_);

        oracle = oracle_;
        maxAge = maxAge_;
        priceDecimals = decimals_;
    }

    function readPrice() public view returns (uint256) {
        (int256 answer, uint256 updatedAt) = oracle.latestPrice();

        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0 || updatedAt > block.timestamp) revert InvalidTimestamp();
        if (block.timestamp - updatedAt > maxAge) revert StalePrice();

        // Il controllo answer > 0 rende sicura la conversione signed -> unsigned.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }

    /// @notice amount18: BASE 1e18; price: QUOTE/BASE 1eP; risultato: QUOTE 1e6.
    function quote18To6(uint256 amount18) external view returns (uint256) {
        uint256 price = readPrice();
        uint256 denominator = 10 ** uint256(INPUT_DECIMALS + priceDecimals - OUTPUT_DECIMALS);
        return MulDivLite.mulDiv(amount18, price, denominator);
    }
}
