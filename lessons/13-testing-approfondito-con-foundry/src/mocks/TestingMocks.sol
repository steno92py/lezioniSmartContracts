// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ITestToken, ITestOracle} from "../interfaces/ITestDependencies.sol";
import {WithdrawalVault} from "../WithdrawalVault.sol";

contract ConfigurableToken is ITestToken {
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    uint256 public feeBps;
    bool public transferReturns = true;
    bool public transferFromReturns = true;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function configure(uint256 newFeeBps, bool transferResult, bool transferFromResult) external {
        feeBps = newFeeBps;
        transferReturns = transferResult;
        transferFromReturns = transferFromResult;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (!transferReturns) return false;
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (!transferFromReturns) return false;
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "BALANCE");
        uint256 fee = amount * feeBps / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
    }
}

contract MockOracle is ITestOracle {
    error OracleUnavailable();

    int256 public price;
    uint256 public updatedAt;
    bool public shouldRevert;

    function setAnswer(int256 newPrice, uint256 newUpdatedAt) external {
        price = newPrice;
        updatedAt = newUpdatedAt;
    }

    function setShouldRevert(bool enabled) external {
        shouldRevert = enabled;
    }

    function latestPrice() external view returns (int256, uint256) {
        if (shouldRevert) revert OracleUnavailable();
        return (price, updatedAt);
    }
}

contract ReentrantReceiver {
    WithdrawalVault public immutable vault;
    bool public callbackAttempted;
    bool public secondWithdrawalSucceeded;

    constructor(WithdrawalVault vault_) {
        vault = vault_;
    }

    function attack() external {
        vault.withdraw();
    }

    receive() external payable {
        if (!callbackAttempted) {
            callbackAttempted = true;
            (secondWithdrawalSucceeded,) = address(vault).call(abi.encodeCall(WithdrawalVault.withdraw, ()));
        }
    }
}

contract RejectEther {
    function claim(WithdrawalVault vault) external {
        vault.withdraw();
    }

    receive() external payable {
        revert("NO_ETHER");
    }
}

