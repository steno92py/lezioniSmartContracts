// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ITestToken, ITestOracle} from "./interfaces/ITestDependencies.sol";

/// @notice Escrow compatto usato per imparare a progettare test, non per produzione.
contract TestingEscrow {
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized(address caller);
    error InvalidState(State expected, State actual);
    error FeeTooHigh(uint256 feeBps);
    error InvalidPrice(int256 price);
    error InvalidOracleTimestamp(uint256 updatedAt, uint256 currentTimestamp);
    error StalePrice(uint256 updatedAt, uint256 currentTimestamp);
    error TokenCallFailed();
    error UnexpectedReceived(uint256 requested, uint256 received);
    error RefundTooEarly(uint256 deadline, uint256 currentTimestamp);

    event Deposited(address indexed buyer, uint256 amount, int256 price);
    event Released(address indexed seller, uint256 payout, uint256 fee);
    event Refunded(address indexed buyer, uint256 amount);
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    uint256 public constant MAX_FEE_BPS = 1_000;
    uint256 public constant MAX_PRICE_AGE = 1 days;

    ITestToken public immutable token;
    address public immutable buyer;
    address public immutable seller;
    address public immutable owner;
    uint256 public immutable refundDeadline;

    ITestOracle public oracle;
    State public state;
    uint256 public depositedAmount;
    uint256 public feeBps;
    int256 public depositPrice;

    constructor(
        address token_,
        address oracle_,
        address buyer_,
        address seller_,
        address owner_,
        uint256 refundDeadline_
    ) {
        if (
            token_ == address(0) || oracle_ == address(0) || buyer_ == address(0) || seller_ == address(0)
                || owner_ == address(0)
        ) revert ZeroAddress();

        token = ITestToken(token_);
        oracle = ITestOracle(oracle_);
        buyer = buyer_;
        seller = seller_;
        owner = owner_;
        refundDeadline = refundDeadline_;
    }

    function deposit(uint256 requestedAmount) external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Created) revert InvalidState(State.Created, state);
        if (requestedAmount == 0) revert ZeroAmount();

        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0) revert InvalidPrice(price);
        if (updatedAt > block.timestamp) {
            revert InvalidOracleTimestamp(updatedAt, block.timestamp);
        }
        if (block.timestamp - updatedAt > MAX_PRICE_AGE) {
            revert StalePrice(updatedAt, block.timestamp);
        }

        uint256 balanceBefore = token.balanceOf(address(this));
        depositedAmount = requestedAmount;
        depositPrice = price;
        state = State.Funded;
        emit Deposited(msg.sender, requestedAmount, price);
        _callOptionalReturn(abi.encodeCall(ITestToken.transferFrom, (msg.sender, address(this), requestedAmount)));
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received != requestedAmount) revert UnexpectedReceived(requestedAmount, received);
    }

    function release() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Funded) revert InvalidState(State.Funded, state);

        uint256 gross = depositedAmount;
        uint256 fee = gross * feeBps / 10_000;
        uint256 payout = gross - fee;

        depositedAmount = 0;
        state = State.Released;
        emit Released(seller, payout, fee);
        _callOptionalReturn(abi.encodeCall(ITestToken.transfer, (seller, payout)));
        if (fee != 0) {
            _callOptionalReturn(abi.encodeCall(ITestToken.transfer, (owner, fee)));
        }
    }

    function refund() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Funded) revert InvalidState(State.Funded, state);
        if (block.timestamp < refundDeadline) {
            revert RefundTooEarly(refundDeadline, block.timestamp);
        }

        uint256 amount = depositedAmount;
        depositedAmount = 0;
        state = State.Refunded;
        emit Refunded(buyer, amount);
        _callOptionalReturn(abi.encodeCall(ITestToken.transfer, (buyer, amount)));
    }

    function setFee(uint256 newFeeBps) external {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh(newFeeBps);
        uint256 oldFeeBps = feeBps;
        feeBps = newFeeBps;
        emit FeeUpdated(oldFeeBps, newFeeBps);
    }

    function setOracle(address newOracle) external {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        if (newOracle == address(0)) revert ZeroAddress();
        address oldOracle = address(oracle);
        oracle = ITestOracle(newOracle);
        emit OracleUpdated(oldOracle, newOracle);
    }

    function liability() external view returns (uint256) {
        return state == State.Funded ? depositedAmount : 0;
    }

    function _callOptionalReturn(bytes memory data) private {
        (bool success, bytes memory returnData) = address(token).call(data);
        if (!success || (returnData.length != 0 && !abi.decode(returnData, (bool)))) {
            revert TokenCallFailed();
        }
    }
}
