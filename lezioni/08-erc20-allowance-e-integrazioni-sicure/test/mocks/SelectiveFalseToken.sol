// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { TestToken } from "./TestToken.sol";

// Serve a far fallire il PAYOUT dopo un deposito riuscito: transferFrom (ingresso) resta
// quello di TestToken, transfer (uscita) puo' essere spento con un interruttore.
/// @notice Deposita normalmente, ma puo' restituire false nei trasferimenti in uscita.
contract SelectiveFalseToken is TestToken {
    bool public failDirectTransfers;

    function setFailDirectTransfers(bool shouldFail) external {
        failDirectTransfers = shouldFail;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (failDirectTransfers) return false; // nessun revert: solo `false`
        _transfer(msg.sender, to, amount);
        return true;
    }
}
