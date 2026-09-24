// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20Final} from "../interfaces/IFinalDependencies.sol";

/// @notice Wrapper locale per il laboratorio; in produzione usare una libreria mantenuta e auditata.
/// @dev Una library non ha stato proprio; le funzioni `internal` vengono copiate nel contratto
/// che le usa. Scopo: trasformare ogni esito negativo di un token in un revert.
library SafeERC20Lite {
    error TokenHasNoCode(address token);
    error SafeTransferFailed(address token);

    function safeTransfer(IERC20Final token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20Final.transfer, (to, amount)));
    }

    function safeTransferFrom(IERC20Final token, address from, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20Final.transferFrom, (from, to, amount)));
    }

    function _callOptionalReturn(IERC20Final token, bytes memory callData) private {
        address target = address(token);
        // Una call verso un indirizzo senza codice "riesce" sempre e non restituisce nulla:
        // senza questo controllo verrebbe scambiata per un trasferimento riuscito.
        if (target.code.length == 0) revert TokenHasNoCode(target);

        // Chiamata a basso livello: non revert da sola, restituisce (esito, dati di ritorno).
        (bool success, bytes memory returnData) = target.call(callData);
        if (!success) {
            if (returnData.length == 0) revert SafeTransferFailed(target);
            // Il token ha revertito con un motivo: lo si rilancia identico ("bubbling").
            // In memoria un `bytes` inizia con 32 byte di lunghezza, poi i dati:
            // add(returnData, 0x20) salta la lunghezza, mload(returnData) la legge.
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
        // Return "opzionale": alcuni token storici non restituiscono nulla (length 0: accettato).
        // Se invece restituiscono dati, devono essere un bool (32 byte) uguale a true.
        if (returnData.length != 0 && (returnData.length < 32 || !abi.decode(returnData, (bool)))) {
            revert SafeTransferFailed(target);
        }
    }
}
