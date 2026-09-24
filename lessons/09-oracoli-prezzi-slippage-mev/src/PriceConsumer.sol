// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { MulDivLite } from "./math/MulDivLite.sol";
import { IPriceOracle } from "./oracle/IPriceOracle.sol";

/// @title PriceConsumer
/// @notice Converte importi a 18 decimals in quote units a 6 decimals.
contract PriceConsumer {
    // Un errore per ogni modo in cui il dato dell'oracle puo' essere sbagliato:
    // nei test si verifica il motivo PRECISO del rifiuto, non un revert qualunque.
    error InvalidOracle(address oracle);
    error InvalidMaxAge();
    error UnsupportedDecimals(uint8 decimals);
    error InvalidPrice();
    error InvalidTimestamp();
    error StalePrice();

    // Le scale sono scritte come costanti: le unita' fanno parte della specifica.
    uint8 public constant INPUT_DECIMALS = 18; // importo in ingresso: BASE con 18 decimali
    uint8 public constant OUTPUT_DECIMALS = 6; // risultato: QUOTE con 6 decimali (es. USDC)
    uint8 public constant MAX_ORACLE_DECIMALS = 18; // oltre, il feed viene rifiutato al deploy

    // Tutto `immutable`: letto e validato una sola volta nel constructor, poi non cambia piu'.
    IPriceOracle public immutable oracle;
    uint256 public immutable maxAge; // eta' massima accettata del prezzo, in secondi
    uint8 public immutable priceDecimals; // copia di oracle.decimals() fatta al deploy

    constructor(IPriceOracle oracle_, uint256 maxAge_) {
        // `.code.length == 0`: all'indirizzo non c'e' codice (indirizzo vuoto o EOA).
        // Meglio fallire subito con un errore chiaro che scoprirlo alla prima lettura del prezzo.
        if (address(oracle_).code.length == 0) revert InvalidOracle(address(oracle_));
        // maxAge zero rifiuterebbe ogni prezzo non aggiornato in questo stesso secondo.
        if (maxAge_ == 0) revert InvalidMaxAge();

        // Limite sui decimals: tiene l'esponente del denominatore di quote18To6 in un
        // intervallo noto e testato.
        uint8 decimals_ = oracle_.decimals();
        if (decimals_ > MAX_ORACLE_DECIMALS) revert UnsupportedDecimals(decimals_);

        oracle = oracle_;
        maxAge = maxAge_;
        priceDecimals = decimals_;
    }

    /// @dev `public` (e non `external`): la chiamano sia gli utenti sia quote18To6, dall'interno.
    function readPrice() public view returns (uint256) {
        (int256 answer, uint256 updatedAt) = oracle.latestPrice();

        // Tre controlli, uno per ogni proprieta' del dato:
        // 1. segno: un prezzo zero o negativo non ha senso economico.
        if (answer <= 0) revert InvalidPrice();
        // 2. timestamp plausibile: 0 = mai aggiornato; nel futuro = feed guasto.
        //    Scartare il futuro serve anche alla riga dopo: la sottrazione non puo' andare sotto 0.
        if (updatedAt == 0 || updatedAt > block.timestamp) revert InvalidTimestamp();
        // 3. freshness: `>` e non `>=`, quindi un prezzo con eta' ESATTAMENTE maxAge passa.
        if (block.timestamp - updatedAt > maxAge) revert StalePrice();

        // Il controllo answer > 0 rende sicura la conversione signed -> unsigned.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }

    /// @notice amount18: BASE 1e18; price: QUOTE/BASE 1eP; risultato: QUOTE 1e6.
    /// @dev Derivazione delle unita', con P = priceDecimals:
    ///   amount18 * price = (BASE * 1e18) * (QUOTE/BASE * 1eP) = QUOTE * 1e(18 + P)
    ///   per arrivare a QUOTE * 1e6 si divide per 1e(18 + P - 6).
    /// Esempio: 1e18 * 3000e8 / 1e20 = 3000e6.
    function quote18To6(uint256 amount18) external view returns (uint256) {
        uint256 price = readPrice(); // prezzo gia' validato
        uint256 denominator = 10 ** uint256(INPUT_DECIMALS + priceDecimals - OUTPUT_DECIMALS);
        // mulDiv invece di (amount18 * price) / denominator: il prodotto intermedio puo'
        // superare 2^256 anche quando il risultato finale ci sta. La divisione arrotonda per
        // difetto: la rounding policy va dichiarata.
        return MulDivLite.mulDiv(amount18, price, denominator);
    }
}
