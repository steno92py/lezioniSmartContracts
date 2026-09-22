// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../interfaces/IAuditDependencies.sol";

contract MockToken is IAuditToken {
    error InsufficientBalance();
    error InsufficientAllowance();

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < amount) revert InsufficientAllowance();
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract FeeToken is MockToken {
    uint256 public immutable feeBps;

    constructor(uint256 feeBps_) {
        feeBps = feeBps_;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        uint256 fee = amount * feeBps / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}

interface IReleaseTarget {
    function release() external;
}

contract ReentrantToken is MockToken {
    address public target;
    bool public armed;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    function configure(address target_) external {
        target = target_;
        armed = true;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        super._transfer(from, to, amount);

        if (armed && from == target) {
            armed = false;
            callbackAttempted = true;
            (callbackSucceeded,) = target.call(abi.encodeCall(IReleaseTarget.release, ()));
        }
    }
}

contract MockOracle is IPriceOracle {
    int256 public price;
    uint256 public updatedAt;

    constructor(int256 price_, uint256 updatedAt_) {
        set(price_, updatedAt_);
    }

    function set(int256 price_, uint256 updatedAt_) public {
        price = price_;
        updatedAt = updatedAt_;
    }

    function latestPrice() external view returns (int256, uint256) {
        return (price, updatedAt);
    }
}

contract RecordingNotifier is ISettlementNotifier {
    uint256 public calls;
    address public lastBuyer;
    address public lastSeller;
    uint256 public lastAmount;

    function notify(address buyer, address seller, uint256 amount) external {
        calls += 1;
        lastBuyer = buyer;
        lastSeller = seller;
        lastAmount = amount;
    }
}

contract RevertingNotifier is ISettlementNotifier {
    error NotificationUnavailable();

    function notify(address, address, uint256) external pure {
        revert NotificationUnavailable();
    }
}

