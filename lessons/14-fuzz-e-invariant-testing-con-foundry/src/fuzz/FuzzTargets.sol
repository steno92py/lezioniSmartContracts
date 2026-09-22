// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract FeeCalculator {
    uint256 public constant MAX_FEE_BPS = 1_000;

    error FeeTooHigh(uint256 feeBps);

    function fee(uint256 amount, uint256 feeBps) external pure returns (uint256) {
        if (feeBps > MAX_FEE_BPS) revert FeeTooHigh(feeBps);
        return amount * feeBps / 10_000;
    }

    function quote(uint256 amount, uint256 price) external pure returns (uint256) {
        return amount * price / 1e18;
    }
}

contract SimpleEscrow {
    error ZeroAddress();
    error OnlyBuyer(address caller);
    error ZeroAmount();
    error AlreadyFunded();

    address public immutable buyer;
    uint256 public escrowedAmount;
    bool public funded;

    constructor(address buyer_) {
        if (buyer_ == address(0)) revert ZeroAddress();
        buyer = buyer_;
    }

    function deposit(uint256 amount) external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        if (funded) revert AlreadyFunded();
        if (amount == 0) revert ZeroAmount();
        escrowedAmount = amount;
        funded = true;
    }
}

contract MutableOracle {
    int256 public price;
    uint256 public updatedAt;

    function setAnswer(int256 newPrice, uint256 newUpdatedAt) external {
        price = newPrice;
        updatedAt = newUpdatedAt;
    }
}

contract FreshPriceConsumer {
    uint256 public constant MAX_AGE = 1 hours;

    error InvalidPrice(int256 price);
    error FutureTimestamp(uint256 updatedAt, uint256 currentTimestamp);
    error StalePrice(uint256 updatedAt, uint256 currentTimestamp);

    MutableOracle public immutable oracle;

    constructor(MutableOracle oracle_) {
        oracle = oracle_;
    }

    function readPrice() external view returns (int256 price) {
        price = oracle.price();
        uint256 updatedAt = oracle.updatedAt();
        if (price <= 0) revert InvalidPrice(price);
        if (updatedAt > block.timestamp) revert FutureTimestamp(updatedAt, block.timestamp);
        if (block.timestamp - updatedAt > MAX_AGE) {
            revert StalePrice(updatedAt, block.timestamp);
        }
    }
}
