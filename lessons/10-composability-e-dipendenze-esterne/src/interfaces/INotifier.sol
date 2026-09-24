// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Un'interfaccia dichiara solo le firme delle funzioni, senza codice. Serve al consumer per
// codificare la call (ABI), ma NON garantisce nulla su cosa fara' il contratto chiamato:
// qualunque contratto con questa firma "e'" un INotifier, anche uno ostile.
interface INotifier {
    function notifyReleased(address seller, uint256 amount) external;
}
