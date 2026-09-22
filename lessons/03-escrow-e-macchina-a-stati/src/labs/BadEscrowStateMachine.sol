// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto volutamente vulnerabile per un laboratorio esclusivamente locale.
contract BadEscrowStateMachine {
    enum State {
        Created,
        Funded,
        ReleaseApproved,
        Cancelled
    }

    error Unauthorized(address caller);
    error WrongState();
    error WrongValue();

    address public immutable buyer;
    uint256 public immutable price;

    State public state;

    constructor(uint256 price_) {
        buyer = msg.sender;
        price = price_;
        state = State.Created;
    }

    function fund() external payable {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Created) revert WrongState();
        if (msg.value != price) revert WrongValue();

        state = State.Funded;
    }

    function approveRelease() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);

        // BUG INTENZIONALE: manca la guardia state == State.Funded.
        state = State.ReleaseApproved;
    }
}

