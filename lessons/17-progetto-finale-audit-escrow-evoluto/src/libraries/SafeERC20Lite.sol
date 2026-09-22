// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20Final} from "../interfaces/IFinalDependencies.sol";

/// @notice Wrapper locale per il laboratorio; in produzione usare una libreria mantenuta e auditata.
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
        if (target.code.length == 0) revert TokenHasNoCode(target);

        (bool success, bytes memory returnData) = target.call(callData);
        if (!success) {
            if (returnData.length == 0) revert SafeTransferFailed(target);
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
        if (returnData.length != 0 && (returnData.length < 32 || !abi.decode(returnData, (bool)))) {
            revert SafeTransferFailed(target);
        }
    }
}

