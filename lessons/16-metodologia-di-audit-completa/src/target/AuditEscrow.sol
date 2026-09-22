// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../interfaces/IAuditDependencies.sol";

/// @notice Target congelato del mini audit. Contiene vulnerabilita intenzionali.
/// @dev Non usare in produzione e non correggere qui: le PoC devono restare riproducibili.
contract AuditEscrow {
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    error WrongCaller();
    error WrongState();
    error Paused();
    error InvalidPrice();
    error StalePrice();
    error TokenTransferFailed();
    error ZeroAddress();

    event Deposited(uint256 requestedAmount);
    event Released(uint256 amount);
    event Refunded(uint256 amount);
    event OracleChanged(address indexed oldOracle, address indexed newOracle, address indexed caller);
    event PauseChanged(bool paused);

    address public immutable buyer;
    address public immutable seller;
    address public immutable governance;
    address public immutable guardian;
    IAuditToken public immutable token;
    ISettlementNotifier public immutable notifier;
    uint256 public immutable minPrice;
    uint256 public immutable maxAge;

    IPriceOracle public oracle;
    State public state;
    uint256 public liability;
    bool public paused;

    constructor(
        address buyer_,
        address seller_,
        address governance_,
        address guardian_,
        IAuditToken token_,
        IPriceOracle oracle_,
        ISettlementNotifier notifier_,
        uint256 minPrice_,
        uint256 maxAge_
    ) {
        if (
            buyer_ == address(0) || seller_ == address(0) || governance_ == address(0) || guardian_ == address(0)
                || address(token_) == address(0) || address(oracle_) == address(0)
        ) revert ZeroAddress();

        buyer = buyer_;
        seller = seller_;
        governance = governance_;
        guardian = guardian_;
        token = token_;
        oracle = oracle_;
        notifier = notifier_;
        minPrice = minPrice_;
        maxAge = maxAge_;
    }

    function deposit(uint256 amount) external {
        if (msg.sender != buyer) revert WrongCaller();
        if (state != State.Created) revert WrongState();

        if (!token.transferFrom(msg.sender, address(this), amount)) revert TokenTransferFailed();

        // AUD-02: accredita il nominale senza misurare quanto e' arrivato.
        liability = amount;
        state = State.Funded;
        emit Deposited(amount);
    }

    /// @notice Chiunque puo' finalizzare quando il prezzo raggiunge la soglia.
    function release() external {
        if (paused) revert Paused();
        if (state != State.Funded) revert WrongState();

        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0 || uint256(price) < minPrice) revert InvalidPrice();

        // AUD-04: al confine esatto maxAge il dato viene ancora accettato.
        if (block.timestamp - updatedAt > maxAge) revert StalePrice();

        uint256 amount = liability;

        // AUD-01: due chiamate esterne precedono la chiusura della liability.
        if (!token.transfer(seller, amount)) revert TokenTransferFailed();
        if (address(notifier) != address(0)) notifier.notify(buyer, seller, amount);

        liability = 0;
        state = State.Released;
        emit Released(amount);
    }

    function refund() external {
        if (msg.sender != buyer) revert WrongCaller();
        if (state != State.Funded) revert WrongState();

        uint256 amount = liability;
        liability = 0;
        state = State.Refunded;
        if (!token.transfer(buyer, amount)) revert TokenTransferFailed();
        emit Refunded(amount);
    }

    function setOracle(IPriceOracle newOracle) external {
        // AUD-03: il guardian di emergenza aggira il path governance dichiarato.
        if (msg.sender != governance && msg.sender != guardian) revert WrongCaller();
        if (address(newOracle) == address(0)) revert ZeroAddress();
        emit OracleChanged(address(oracle), address(newOracle), msg.sender);
        oracle = newOracle;
    }

    function pause() external {
        if (msg.sender != governance && msg.sender != guardian) revert WrongCaller();
        paused = true;
        emit PauseChanged(true);
    }

    function unpause() external {
        if (msg.sender != governance) revert WrongCaller();
        paused = false;
        emit PauseChanged(false);
    }
}

