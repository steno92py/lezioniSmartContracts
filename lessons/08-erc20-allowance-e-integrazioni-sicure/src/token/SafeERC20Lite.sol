// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "./IERC20.sol";

// Una `library` e' codice riusabile senza stato proprio. Le sue funzioni `internal` vengono
// copiate nel contratto che le usa: girano nel contesto del chiamante (stesso msg.sender,
// stesso storage), quindi verso il token il chiamante resta il contratto che usa la libreria.
/// @notice Wrapper minimale per studiare i return value ERC-20 opzionali.
/// @dev Primitive didattica, non sostituisce OpenZeppelin SafeERC20 in produzione.
library SafeERC20Lite {
    error TokenHasNoCode(address token);
    error SafeTransferFailed(address token);

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        // abi.encodeCall costruisce la calldata (selector + argomenti) e il compilatore
        // controlla che i tipi degli argomenti corrispondano alla firma di IERC20.transfer.
        _callOptionalReturn(token, abi.encodeCall(IERC20.transfer, (to, amount)));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
    }

    // Quattro esiti possibili di una call a un token, e come li tratta questa funzione:
    //   revert                    -> si propaga il revert (con il motivo originale);
    //   successo + `false`        -> SafeTransferFailed: il token dice di non aver spostato nulla;
    //   successo + nessun dato    -> accettato: token legacy che non restituisce il bool;
    //   successo + `true`         -> accettato.
    function _callOptionalReturn(IERC20 token, bytes memory callData) private {
        address target = address(token);
        // Una call a un indirizzo senza codice RIESCE sempre e non restituisce dati: sarebbe
        // scambiata per un token legacy andato a buon fine. Per questo si controlla il codice.
        if (target.code.length == 0) revert TokenHasNoCode(target);

        // Call a basso livello: non reverte da sola se il token reverte, ma restituisce
        // success = false e i byte di ritorno. Serve per leggere il return value "a mano",
        // perche' una call tipizzata fallirebbe sui token che non restituiscono nulla.
        (bool success, bytes memory returnData) = target.call(callData);

        if (!success) {
            // Revert senza motivo: si usa l'errore della libreria.
            if (returnData.length == 0) revert SafeTransferFailed(target);

            // Revert con motivo: lo si rilancia identico, cosi' chi chiama vede l'errore
            // originale del token (per esempio InsufficientAllowance). In memory i primi
            // 32 byte di `returnData` sono la lunghezza; i dati iniziano a +0x20.
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }

        // Call riuscita: se il token ha restituito dati, devono essere un bool `true`.
        // Meno di 32 byte non e' un bool ABI valido; `false` e' un fallimento dichiarato.
        if (returnData.length != 0 && (returnData.length < 32 || !abi.decode(returnData, (bool)))) {
            revert SafeTransferFailed(target);
        }
    }
}
