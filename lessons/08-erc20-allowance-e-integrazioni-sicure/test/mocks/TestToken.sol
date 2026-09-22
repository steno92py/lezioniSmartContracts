// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "../../src/token/IERC20.sol";

/// @notice ERC-20 minimale e permissivo, esclusivamente per test locali.
contract TestToken is IERC20 {
    error ZeroAddress();
    error InsufficientBalance(address account, uint256 available, uint256 required);
    error InsufficientAllowance(address spender, uint256 available, uint256 required);

    uint256 public override totalSupply;
    mapping(address account => uint256 amount) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public override allowance;

    function mint(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        virtual
        override
        returns (bool)
    {
        uint256 available = allowance[from][msg.sender];
        if (available < amount) {
            revert InsufficientAllowance(msg.sender, available, amount);
        }

        if (available != type(uint256).max) {
            allowance[from][msg.sender] = available - amount;
            emit Approval(from, msg.sender, available - amount);
        }

        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        _move(from, to, amount);
    }

    function _move(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();

        uint256 available = balanceOf[from];
        if (available < amount) revert InsufficientBalance(from, available, amount);

        balanceOf[from] = available - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

