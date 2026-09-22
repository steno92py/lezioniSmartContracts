// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20Final, IPriceOracleFinal, INotifierFinal} from "../interfaces/IFinalDependencies.sol";

contract TestToken is IERC20Final {
    error InsufficientBalance();
    error InsufficientAllowance();

    string public name = "Test Token";
    string public symbol = "TEST";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
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

contract FeeToken is TestToken {
    uint256 public constant FEE_BPS = 1_000;

    function _transfer(address from, address to, uint256 amount) internal override {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        uint256 fee = amount * FEE_BPS / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}

contract FalsePayoutToken is TestToken {
    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }
}

contract MockOracle is IPriceOracleFinal {
    int256 public answer;
    uint256 public updatedAt;

    constructor(int256 answer_, uint256 updatedAt_) {
        setPrice(answer_, updatedAt_);
    }

    function setPrice(int256 answer_, uint256 updatedAt_) public {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestPrice() external view returns (int256, uint256) {
        return (answer, updatedAt);
    }
}

contract RecordingNotifier is INotifierFinal {
    uint256 public calls;
    address public lastSeller;
    uint256 public lastAmount;

    function notifyReleased(address seller, uint256 amount) external {
        calls += 1;
        lastSeller = seller;
        lastAmount = amount;
    }
}

contract RevertingNotifier is INotifierFinal {
    error NotificationUnavailable();

    function notifyReleased(address, uint256) external pure {
        revert NotificationUnavailable();
    }
}
