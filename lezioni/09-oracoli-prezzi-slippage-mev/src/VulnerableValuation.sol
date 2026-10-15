// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IPriceOracle } from "./oracle/IPriceOracle.sol";

/// @notice Consumer intenzionalmente vulnerabile: ignora timestamp, unita' e scaling.
contract VulnerableValuation {
    IPriceOracle public immutable oracle;

    // Nessun controllo sull'indirizzo: confrontalo con il constructor di PriceConsumer.
    constructor(IPriceOracle oracle_) {
        oracle = oracle_;
    }

    function valueOf(uint256 amount) external view returns (uint256) {
        // `(int256 answer,)`: la virgola scarta il secondo valore, updatedAt.
        // Vulnerabilita' 1: senza updatedAt non si puo' sapere se il prezzo e' vecchio di ore.
        (int256 answer,) = oracle.latestPrice();
        // Vulnerabilita' 2: nessun controllo answer > 0. La conversione esplicita
        // uint256(int256) NON reverte: -1 diventa 2^256 - 1, un prezzo enorme.
        // Vulnerabilita' 3: amount (1e18) per price (1e8) da' un numero con 26 decimali
        // "nascosti", non un importo in unita' quote. Mancano le unita' e la scala.
        // La versione corretta di tutti e tre i punti e' PriceConsumer.
        return amount * uint256(answer);
    }
}
