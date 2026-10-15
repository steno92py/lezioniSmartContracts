// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Un'interfaccia elenca solo le firme delle funzioni: nessuno stato, nessuna implementazione.
// Basta per chiamare un contratto esterno, ma non garantisce come quel contratto si comporti.

// Le funzioni dello standard ERC-20 usate nel laboratorio.
interface IERC20Final {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Feed di prezzo: il valore e il momento (timestamp in secondi) in cui e' stato aggiornato.
interface IPriceOracleFinal {
    function latestPrice() external view returns (int256 answer, uint256 updatedAt);
}

// Servizio di notifica opzionale, chiamato dopo il pagamento al seller.
interface INotifierFinal {
    function notifyReleased(address seller, uint256 amount) external;
}
