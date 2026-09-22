// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Helper low-level minimale per rendere visibili code check e revert bubbling.
/// @dev Primitive didattica: usare una libreria consolidata e pinnata in produzione.
library CallUtilsLite {
    error TargetHasNoCode(address target);
    error CallFailed(address target);

    function functionCall(address target, bytes memory data)
        internal
        returns (bytes memory returnData)
    {
        if (target.code.length == 0) revert TargetHasNoCode(target);

        (bool success, bytes memory result) = target.call(data);
        if (!success) {
            if (result.length == 0) revert CallFailed(target);

            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }

        return result;
    }
}

