// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Token legacy-like: selector ERC-20 compatibili, ma nessun bool di ritorno.
contract NoReturnToken {
    error InsufficientBalance();
    error InsufficientAllowance();

    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 available = allowance[from][msg.sender];
        if (available < amount) revert InsufficientAllowance();

        allowance[from][msg.sender] = available - amount;
        _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 available = balanceOf[from];
        if (available < amount) revert InsufficientBalance();

        balanceOf[from] = available - amount;
        balanceOf[to] += amount;
    }
}

