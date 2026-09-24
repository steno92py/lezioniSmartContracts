// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { MulDivLite } from "../math/MulDivLite.sol";
import { ISwap } from "../swap/ISwap.sol";

/// @notice Simulatore privo di riserve e token: modella soltanto rate e minOut.
contract MockSwap is ISwap {
    error SlippageExceeded(uint256 minimum, uint256 actual);

    // Quanti token in uscita per 1 token in ingresso, scalato 1e18: 2e18 significa "x 2".
    uint256 public rateE18 = 2e18;

    // Chiunque puo' cambiare il rate: nei test simula il prezzo che si muove tra il momento
    // in cui l'utente osserva la quotazione e quello in cui la transazione viene eseguita.
    function setRate(uint256 newRateE18) external {
        rateE18 = newRateE18;
    }

    // Quotazione: amountIn * rate / 1e18. Il / 1e18 toglie la scala del rate.
    function quote(uint256 amountIn) public view returns (uint256) {
        return MulDivLite.mulDiv(amountIn, rateE18, 1e18);
    }

    // `view`: nessun token si muove davvero, il mock calcola solo l'output.
    // Il controllo decisivo e' l'ultima riga: sotto il minimo dichiarato, revert.
    function swap(uint256 amountIn, uint256 amountOutMin)
        external
        view
        returns (uint256 amountOut)
    {
        amountOut = quote(amountIn);
        if (amountOut < amountOutMin) revert SlippageExceeded(amountOutMin, amountOut);
    }
}
