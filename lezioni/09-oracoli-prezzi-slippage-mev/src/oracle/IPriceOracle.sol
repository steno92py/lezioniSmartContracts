// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Interfaccia: solo le firme delle funzioni, nessun codice. Chi la usa sa COME chiamare
// l'oracle, ma non puo' sapere se i dati restituiti sono giusti: l'oracle e' una trust boundary,
// e ogni valore che attraversa questo confine va validato da chi lo riceve.
interface IPriceOracle {
    // Quante cifre decimali ha il prezzo: 3000 USD con 8 decimals arriva come 3000e8.
    function decimals() external view returns (uint8);
    // answer e' `int256`, con segno: un feed puo' restituire 0 o un valore negativo.
    // updatedAt e' il momento (in secondi Unix) dell'ultimo aggiornamento del prezzo.
    function latestPrice() external view returns (int256 answer, uint256 updatedAt);
}
