// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Implementation giocattolo: da sola e' innocua. Diventa pericolosa solo quando il suo codice
// gira nello storage di SimpleProxy, dove lo slot 0 ha gia' un altro significato.
contract SimpleLogicV1 {
    uint256 public value; // slot 0

    function setValue(uint256 newValue) external {
        value = newValue; // scrive lo slot 0 del contratto nel cui contesto sta girando
    }
}
