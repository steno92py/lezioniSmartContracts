// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title SafeEscrow
/// @notice State machine didattica: registra crediti e omette i payout per isolare la logica.
contract SafeEscrow {
    enum State {
        Created,
        Funded,
        Completed,
        Cancelled
    }

    error OnlyBuyer(address caller);
    error OnlySeller(address caller);
    error WrongState(State expected, State actual);
    error WrongAmount();
    error ZeroAddress();
    error SameParty();

    event Deposited(address indexed buyer, uint256 amount);
    event Completed(address indexed seller, uint256 credit);
    event Cancelled(address indexed buyer, uint256 credit);

    address public immutable buyer;
    address public immutable seller;

    State public state;
    uint256 public depositedAmount;
    uint256 public sellerCredit;
    uint256 public buyerCredit;

    constructor(address buyer_, address seller_) {
        if (buyer_ == address(0) || seller_ == address(0)) revert ZeroAddress();
        if (buyer_ == seller_) revert SameParty();

        buyer = buyer_;
        seller = seller_;
        state = State.Created;
    }

    function deposit() external payable {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Created);
        if (msg.value == 0) revert WrongAmount();

        depositedAmount = msg.value;
        state = State.Funded;

        emit Deposited(msg.sender, msg.value);
    }

    function complete() external {
        if (msg.sender != seller) revert OnlySeller(msg.sender);
        _requireState(State.Funded);

        sellerCredit = depositedAmount;
        state = State.Completed;

        emit Completed(msg.sender, depositedAmount);
    }

    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Funded);

        buyerCredit = depositedAmount;
        state = State.Cancelled;

        emit Cancelled(msg.sender, depositedAmount);
    }

    /// @notice Obbligazioni contabili correnti del contratto.
    function liabilities() external view returns (uint256) {
        return sellerCredit + buyerCredit;
    }

    function _requireState(State expected) internal view {
        if (state != expected) revert WrongState(expected, state);
    }
}
