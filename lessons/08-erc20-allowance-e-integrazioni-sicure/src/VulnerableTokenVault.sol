// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "./token/IERC20.sol";

/// @notice Contratto intenzionalmente vulnerabile: ignora il bool di transferFrom().
contract VulnerableTokenVault {
    IERC20 public immutable token;
    mapping(address account => uint256 amount) public credit;

    constructor(IERC20 token_) {
        token = token_;
    }

    function deposit(uint256 amount) external {
        // BUG: una call che ritorna false non impedisce l'aggiornamento contabile.
        token.transferFrom(msg.sender, address(this), amount);
        credit[msg.sender] += amount;
    }
}

