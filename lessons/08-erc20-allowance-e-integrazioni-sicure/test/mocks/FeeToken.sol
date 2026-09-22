// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { TestToken } from "./TestToken.sol";

/// @notice Mock che tassa ogni trasferimento del 10% e invia la fee a un collector.
contract FeeToken is TestToken {
    uint256 public constant FEE_BPS = 1_000;
    address public constant FEE_COLLECTOR = address(0xFEE);

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 fee = amount * FEE_BPS / 10_000;
        uint256 received = amount - fee;

        _move(from, FEE_COLLECTOR, fee);
        _move(from, to, received);
    }
}

