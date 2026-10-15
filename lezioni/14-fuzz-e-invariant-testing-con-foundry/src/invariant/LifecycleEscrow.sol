// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Macchina a stati con due stati terminali:
//   Created -> Funded -> Released
//                     -> Refunded
// Una volta terminale, sempre terminale: e' la proprieta' che l'invariant test verifica.
contract LifecycleEscrow {
    // `enum`: insieme chiuso di valori; Created (= 0) e' lo stato iniziale di default.
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    error ZeroAddress();
    error Unauthorized(address caller);
    error InvalidState(State expected, State actual);
    error ZeroAmount();
    error TooEarly(uint256 deadline, uint256 currentTimestamp);

    address public immutable buyer;
    uint256 public immutable refundDeadline;
    State public state;
    uint256 public amount;

    constructor(address buyer_, uint256 refundDeadline_) {
        if (buyer_ == address(0)) revert ZeroAddress();
        buyer = buyer_;
        refundDeadline = refundDeadline_;
    }

    // Ogni transizione ha lo stesso schema: chi chiama, da quale stato, con quali input.
    function fund(uint256 newAmount) external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Created) revert InvalidState(State.Created, state);
        // Garantisce la coppia coerente "Funded -> amount > 0".
        if (newAmount == 0) revert ZeroAmount();
        amount = newAmount;
        state = State.Funded;
    }

    function release() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Funded) revert InvalidState(State.Funded, state);
        amount = 0; // stato terminale -> nessun importo ancora dovuto
        state = State.Released;
    }

    function refund() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Funded) revert InvalidState(State.Funded, state);
        if (block.timestamp < refundDeadline) revert TooEarly(refundDeadline, block.timestamp);
        amount = 0;
        state = State.Refunded;
    }
}
