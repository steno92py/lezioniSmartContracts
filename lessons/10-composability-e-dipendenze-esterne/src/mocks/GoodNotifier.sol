// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { INotifier } from "../interfaces/INotifier.sol";

// Mock onesto: registra cosa ha ricevuto, cosi' il test puo' verificare gli argomenti.
contract GoodNotifier is INotifier {
    bool public called;
    address public notifiedSeller;
    uint256 public notifiedAmount;

    function notifyReleased(address seller, uint256 amount) external {
        called = true;
        notifiedSeller = seller;
        notifiedAmount = amount;
    }
}
