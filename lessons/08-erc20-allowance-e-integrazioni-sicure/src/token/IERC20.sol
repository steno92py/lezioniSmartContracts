// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Un'`interface` elenca solo le firme delle funzioni, senza codice: descrive COME chiamare
// un altro contratto, non garantisce COSA fara'. Il token dietro l'interfaccia puo' essere
// onesto, bizzarro o malevolo: il compilatore non lo sa.
//
// Due numeri distinti, conservati nello storage del TOKEN (non del protocollo che lo usa):
//   balanceOf(owner)          quanti token possiede owner;
//   allowance(owner, spender) quanti token spender puo' spostare per conto di owner.
// Il terzo numero, la contabilita' interna (es. escrowedAmount), vive invece nel protocollo.
/// @notice Sottoinsieme didattico dell'interfaccia ERC-20.
interface IERC20 {
    // Transfer: ogni movimento di saldo. Approval: ogni modifica dell'allowance.
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    // Sposta token del CHIAMANTE (msg.sender) verso `to`.
    function transfer(address to, uint256 amount) external returns (bool);
    // Autorizza `spender`: non muove alcun token, scrive solo l'allowance.
    function approve(address spender, uint256 amount) external returns (bool);
    // Chiamata dallo SPENDER: sposta token di `from` consumando allowance[from][msg.sender].
    // Il bool di ritorno e' parte dello standard: `false` significa "non ho spostato nulla".
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
