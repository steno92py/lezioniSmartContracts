// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20Final, IPriceOracleFinal, INotifierFinal} from "./interfaces/IFinalDependencies.sol";

/// @notice Target deliberatamente imperfetto del progetto finale.
/// @dev Congelare durante l'audit: le correzioni appartengono a EscrowFinalFixed.
contract EscrowFinal {
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    IERC20Final public immutable token;
    address public immutable buyer;
    address public immutable seller;
    address public owner;
    address public emergencyPauser;
    IPriceOracleFinal public oracle;
    INotifierFinal public notifier;
    State public state;
    uint256 public escrowedAmount;
    uint256 public feeBps;
    bool public paused;

    uint256 public constant MAX_ORACLE_AGE = 1 hours;

    error OnlyBuyer();
    error OnlyOwner();
    error OnlyPauser();
    error InvalidState();
    error ZeroAmount();
    error Paused();
    error InvalidPrice();
    error FeeTooHigh();

    event Deposited(uint256 requestedAmount, uint256 creditedAmount);
    event Released(uint256 grossAmount, uint256 fee);
    event Refunded(uint256 amount);

    constructor(
        IERC20Final token_,
        address buyer_,
        address seller_,
        address owner_,
        address emergencyPauser_,
        IPriceOracleFinal oracle_,
        INotifierFinal notifier_
    ) {
        token = token_;
        buyer = buyer_;
        seller = seller_;
        owner = owner_;
        emergencyPauser = emergencyPauser_;
        oracle = oracle_;
        notifier = notifier_;
        state = State.Created;
    }

    function deposit(uint256 amount) external {
        if (paused) revert Paused();
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Created) revert InvalidState();
        if (amount == 0) revert ZeroAmount();

        // F-01: return ignorato e accounting nominale.
        token.transferFrom(buyer, address(this), amount);
        escrowedAmount = amount;
        state = State.Funded;
        emit Deposited(amount, amount);
    }

    function release() external {
        if (paused) revert Paused();
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0) revert InvalidPrice();
        updatedAt; // F-02: freshness ignorata.

        uint256 gross = escrowedAmount;
        uint256 fee = gross * feeBps / 10_000;
        uint256 payout = gross - fee;

        escrowedAmount = 0;
        state = State.Released;

        token.transfer(seller, payout); // F-03: boolean return ignorato.

        // F-05: best-effort coerente con la policy, ma il fallimento rimane invisibile.
        address(notifier).call(abi.encodeCall(INotifierFinal.notifyReleased, (seller, payout)));
        emit Released(gross, fee);
    }

    function refund() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        uint256 amount = escrowedAmount;
        escrowedAmount = 0;
        state = State.Refunded;
        token.transfer(buyer, amount);
        emit Refunded(amount);
    }

    function setFee(uint256 newFeeBps) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (newFeeBps > 1_000) revert FeeTooHigh();
        feeBps = newFeeBps;
    }

    function setOracle(IPriceOracleFinal newOracle) external {
        oracle = newOracle; // F-04: write critico senza authorization.
    }

    function pause() external {
        if (msg.sender != emergencyPauser) revert OnlyPauser();
        paused = true;
    }

    function unpause() external {
        if (msg.sender != owner) revert OnlyOwner();
        paused = false;
    }
}

