// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "./token/IERC20.sol";
import { SafeERC20Lite } from "./token/SafeERC20Lite.sol";

/// @title TokenEscrow
/// @notice Escrow didattico per un singolo ERC-20 scelto al deploy.
contract TokenEscrow {
    using SafeERC20Lite for IERC20;

    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    error OnlyBuyer(address caller);
    error InvalidState(State expected, State actual);
    error ZeroAmount();
    error NothingReceived();
    error InvalidToken(address token);
    error ZeroAddress();
    error SameParty();

    event Deposited(uint256 requestedAmount, uint256 receivedAmount);
    event Released(address indexed seller, uint256 debitedAmount);
    event Refunded(address indexed buyer, uint256 debitedAmount);

    IERC20 public immutable token;
    address public immutable buyer;
    address public immutable seller;

    State public state;
    uint256 public escrowedAmount;

    constructor(IERC20 token_, address buyer_, address seller_) {
        if (address(token_).code.length == 0) revert InvalidToken(address(token_));
        if (buyer_ == address(0) || seller_ == address(0)) revert ZeroAddress();
        if (buyer_ == seller_) revert SameParty();

        token = token_;
        buyer = buyer_;
        seller = seller_;
        state = State.Created;
    }

    function deposit(uint256 requestedAmount) external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Created);
        if (requestedAmount == 0) revert ZeroAmount();

        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(buyer, address(this), requestedAmount);
        uint256 afterBalance = token.balanceOf(address(this));

        if (afterBalance <= beforeBalance) revert NothingReceived();
        uint256 receivedAmount = afterBalance - beforeBalance;

        escrowedAmount = receivedAmount;
        state = State.Funded;

        emit Deposited(requestedAmount, receivedAmount);
    }

    function release() external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Funded);

        uint256 amount = escrowedAmount;
        escrowedAmount = 0;
        state = State.Released;

        token.safeTransfer(seller, amount);
        emit Released(seller, amount);
    }

    function refund() external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Funded);

        uint256 amount = escrowedAmount;
        escrowedAmount = 0;
        state = State.Refunded;

        token.safeTransfer(buyer, amount);
        emit Refunded(buyer, amount);
    }

    function _requireState(State expected) internal view {
        if (state != expected) revert InvalidState(expected, state);
    }
}

