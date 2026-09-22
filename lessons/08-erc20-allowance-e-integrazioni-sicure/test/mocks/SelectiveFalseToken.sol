// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { TestToken } from "./TestToken.sol";

/// @notice Deposita normalmente, ma puo' restituire false nei trasferimenti in uscita.
contract SelectiveFalseToken is TestToken {
    bool public failDirectTransfers;

    function setFailDirectTransfers(bool shouldFail) external {
        failDirectTransfers = shouldFail;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (failDirectTransfers) return false;
        _transfer(msg.sender, to, amount);
        return true;
    }
}

