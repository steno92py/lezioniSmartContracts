// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title EscrowStateMachine
/// @notice Contratto didattico locale. Non e' production-ready.
/// @dev Riceve ETH, ma in questa lezione non effettua ancora alcun payout.
contract EscrowStateMachine {
    enum State {
        Created,
        Funded,
        ReleaseApproved,
        Cancelled
    }

    error ZeroSeller();
    error BuyerEqualsSeller();
    error ZeroPrice();
    error Unauthorized(address caller);
    error WrongState(State expected, State actual);
    error WrongValue(uint256 expected, uint256 actual);

    event Funded(address indexed buyer, uint256 amount);
    event ReleaseApproved(address indexed buyer);
    event Cancelled(address indexed buyer);

    address public immutable buyer;
    address public immutable seller;
    uint256 public immutable price;

    State public state;

    constructor(address seller_, uint256 price_) {
        if (seller_ == address(0)) revert ZeroSeller();
        if (seller_ == msg.sender) revert BuyerEqualsSeller();
        if (price_ == 0) revert ZeroPrice();

        buyer = msg.sender;
        seller = seller_;
        price = price_;
        state = State.Created;
    }

    modifier onlyBuyer() {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyState(State expected) {
        if (state != expected) revert WrongState(expected, state);
        _;
    }

    /// @notice Deposita esattamente il prezzo concordato.
    function fund() external payable onlyBuyer onlyState(State.Created) {
        if (msg.value != price) revert WrongValue(price, msg.value);

        state = State.Funded;
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Il buyer autorizza il futuro payout al seller.
    /// @dev In questa lezione il payout non viene ancora eseguito.
    function approveRelease() external onlyBuyer onlyState(State.Funded) {
        state = State.ReleaseApproved;
        emit ReleaseApproved(msg.sender);
    }

    /// @notice Cancella l'Escrow soltanto prima del funding.
    function cancelBeforeFunding() external onlyBuyer onlyState(State.Created) {
        state = State.Cancelled;
        emit Cancelled(msg.sender);
    }
}

