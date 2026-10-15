// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// `library`: codice riusabile senza stato proprio. Le funzioni `internal` vengono copiate nel
// bytecode di chi le usa (MulDivLite.mulDiv(...)): nessuna call esterna, nessun deploy separato.
//
// Il problema: x * y puo' superare 2^256 - 1 anche quando x * y / denominator e' piccolo.
// In Solidity 0.8 quel prodotto farebbe revertire la call per overflow. Qui il prodotto
// viene tenuto su 512 bit, spezzato in due meta' da 256:
//
//   x * y = productHigh * 2^256 + productLow
//
// Leggere questo codice e' utile per capire l'idea; NON va copiato in produzione.

/// @notice Moltiplicazione e divisione a precisione estesa per il laboratorio locale.
/// @dev Implementazione didattica dell'algoritmo 512-bit; usare librerie pinnate e revisionate in produzione.
library MulDivLite {
    error DenominatorZero();
    error MulDivOverflow();

    /// @notice Calcola floor(x * y / denominator) senza perdere il prodotto alto a 256 bit.
    /// @dev `pure`: non legge e non scrive lo stato, lavora solo sugli argomenti.
    function mulDiv(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 result)
    {
        // `unchecked`: disattiva i controlli di overflow di Solidity 0.8. Qui e' voluto:
        // l'algoritmo usa di proposito l'aritmetica modulo 2^256. Fuori da codice cosi'
        // studiato, `unchecked` e' una fonte classica di bug.
        unchecked {
            uint256 productLow;
            uint256 productHigh;

            // `assembly`: codice Yul, un livello sotto Solidity, senza controlli automatici.
            // "memory-safe" promette al compilatore che il blocco non sporca la memoria.
            assembly ("memory-safe") {
                // Il prodotto calcolato modulo 2^256 - 1 e modulo 2^256: dalla differenza
                // tra i due resti si ricava la meta' alta (teorema cinese del resto).
                let mm := mulmod(x, y, not(0))
                productLow := mul(x, y)
                productHigh := sub(sub(mm, productLow), lt(mm, productLow))
            }

            // Caso comune: il prodotto sta in 256 bit, basta una divisione normale.
            if (productHigh == 0) {
                if (denominator == 0) revert DenominatorZero();
                return productLow / denominator;
            }

            // Se denominator <= productHigh il risultato non starebbe in 256 bit.
            if (denominator <= productHigh) revert MulDivOverflow();

            // Si sottrae il resto dal numero a 512 bit: da qui in poi la divisione e' esatta.
            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)
                productHigh := sub(productHigh, gt(remainder, productLow))
                productLow := sub(productLow, remainder)
            }

            // La piu' grande potenza di 2 che divide denominator. Dopo averla tolta
            // da entrambi i lati il denominatore e' dispari; powerOfTwo diventa 2^256 / powerOfTwo.
            uint256 powerOfTwo = denominator & (0 - denominator);
            assembly ("memory-safe") {
                denominator := div(denominator, powerOfTwo)
                productLow := div(productLow, powerOfTwo)
                powerOfTwo := add(div(sub(0, powerOfTwo), powerOfTwo), 1)
            }

            // Porta i bit della meta' alta dentro la meta' bassa.
            productLow |= productHigh * powerOfTwo;

            // Inverso di denominator modulo 2^256 (esiste perche' ora e' dispari).
            // Il valore iniziale e' corretto sui primi 4 bit; ogni passo di Newton-Raphson
            // raddoppia i bit corretti: 8, 16, 32, 64, 128, 256.
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            // Divisione esatta = moltiplicazione per l'inverso.
            result = productLow * inverse;
        }
    }
}
