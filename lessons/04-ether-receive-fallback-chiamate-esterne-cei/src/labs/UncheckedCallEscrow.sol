// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Contratto deliberatamente difettoso per il solo laboratorio locale.
contract UncheckedCallEscrow {
    enum State {
        Created,
        Funded,
        Released
    }

    address public immutable buyer;
    address payable public immutable seller;
    uint256 public immutable price;

    State public state;

    event PayoutAttempted(bool success);

    constructor(address payable seller_, uint256 price_) {
        require(seller_ != address(0), "ZERO_SELLER");
        require(price_ != 0, "ZERO_PRICE");

        buyer = msg.sender;
        seller = seller_;
        price = price_;
        state = State.Created;
    }

    function fund() external payable {
        require(msg.sender == buyer, "NOT_BUYER");
        require(state == State.Created, "WRONG_STATE");
        require(msg.value == price, "WRONG_VALUE");

        state = State.Funded;
    }

    function release() external {
        require(msg.sender == buyer, "NOT_BUYER");
        require(state == State.Funded, "WRONG_STATE");

        // CEI da solo non basta: la call puo' comunque fallire.
        state = State.Released;
        (bool success,) = seller.call{ value: price }("");

        // BUG: il risultato viene registrato, ma il fallimento non viene imposto.
        emit PayoutAttempted(success);
    }
}
