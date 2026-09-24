// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Registra il contesto di esecuzione. Chiamata tramite proxy con delegatecall:
//   msg.sender    = chi ha chiamato il PROXY (non il proxy stesso);
//   address(this) = il proxy (non ContextLogic);
//   storage       = quello del proxy: lastCaller e lastContext vengono scritti li'.
contract ContextLogic {
    address public lastCaller;
    address public lastContext;

    function recordContext() external {
        lastCaller = msg.sender;
        lastContext = address(this);
    }
}
