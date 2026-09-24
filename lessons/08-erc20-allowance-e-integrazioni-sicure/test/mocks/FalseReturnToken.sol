// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "../../src/token/IERC20.sol";

/// @notice Simula un token che segnala fallimento con false senza spostare asset.
contract FalseReturnToken is IERC20 {
    uint256 public override totalSupply;
    mapping(address account => uint256 amount) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public override allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // Il cuore del mock: la call RIESCE (nessun revert) ma risponde `false` e non sposta nulla.
    // Parametri senza nome perche' non vengono usati; `pure`: non legge ne' scrive lo stato.
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}
