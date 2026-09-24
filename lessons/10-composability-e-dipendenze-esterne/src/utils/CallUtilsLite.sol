// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Helper low-level minimale per rendere visibili code check e revert bubbling.
/// @dev Primitive didattica: usare una libreria consolidata e pinnata in produzione.
/// `library`: codice riusabile senza stato proprio. Le funzioni `internal` vengono copiate
/// dentro il contratto che le usa, quindi la call parte dall'indirizzo di quel contratto.
library CallUtilsLite {
    error TargetHasNoCode(address target);
    error CallFailed(address target);

    function functionCall(address target, bytes memory data)
        internal
        returns (bytes memory returnData)
    {
        // 1. CODE CHECK: una call verso un indirizzo senza codice (EOA o contratto non ancora
        // deployato) restituisce success = true senza eseguire nulla. Va esclusa a priori.
        if (target.code.length == 0) revert TargetHasNoCode(target);

        // 2. La low-level call. `result` contiene i byte restituiti dal target: il valore di
        // ritorno se la call riesce, l'errore codificato se reverte.
        (bool success, bytes memory result) = target.call(data);
        if (!success) {
            // Revert senza dati (per esempio un `revert()` nudo): non c'e' nulla da
            // inoltrare, si usa un errore proprio.
            if (result.length == 0) revert CallFailed(target);

            // 3. REVERT BUBBLING: si rilancia esattamente l'errore del target, cosi' chi sta
            // sopra vede il motivo originale (es. DependencyFailure) e non un errore generico.
            // In memory un `bytes` e' [32 byte di lunghezza][dati...]:
            //   add(result, 0x20) = inizio dei dati, mload(result) = lunghezza.
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }

        return result;
    }
}
