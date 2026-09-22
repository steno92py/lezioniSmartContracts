// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title LogicBugEscrow
/// @notice Contratto intenzionalmente vulnerabile per il laboratorio locale.
/// @dev Non usare in produzione: complete() ignora lo stato e non conclude la transizione.
contract LogicBugEscrow {
    enum State {
        Created,
        Funded,
        Completed,
        Cancelled
    }

    error OnlyBuyer();
    error OnlySeller();
    error WrongState();
    error WrongAmount();

    address public immutable buyer;
    address public immutable seller;

    State public state;
    uint256 public depositedAmount;
    uint256 public sellerCredit;
    uint256 public buyerCredit;

    constructor(address buyer_, address seller_) {
        buyer = buyer_;
        seller = seller_;
        state = State.Created;
    }

    function deposit() external payable {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Created) revert WrongState();
        if (msg.value == 0) revert WrongAmount();

        depositedAmount = msg.value;
        state = State.Funded;
    }

    function complete() external {
        if (msg.sender != seller) revert OnlySeller();

        // BUG: manca il requisito Funded e manca state = State.Completed.
        sellerCredit += depositedAmount;
    }

    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert WrongState();

        buyerCredit += depositedAmount;
        state = State.Cancelled;
    }
}

