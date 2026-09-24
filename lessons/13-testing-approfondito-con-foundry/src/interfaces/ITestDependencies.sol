// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// `interface`: solo le firme delle funzioni, nessuna implementazione. L'escrow dipende da
// queste firme, quindi in test si puo' collegare qualunque contratto che le rispetti.

// Il minimo di ERC-20 che serve all'escrow.
interface ITestToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Un oracle di prezzo: il valore e il momento in cui e' stato aggiornato.
interface ITestOracle {
    function latestPrice() external view returns (int256 price, uint256 updatedAt);
}

