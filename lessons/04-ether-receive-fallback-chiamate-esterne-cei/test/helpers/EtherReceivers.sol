// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Dimostra che ricevere ETH puo' eseguire codice e scrivere storage.
contract AcceptingSeller {
    uint256 public totalReceived;

    receive() external payable {
        totalReceived += msg.value;
    }
}

/// @notice Destinatario avversariale che rifiuta ogni plain ETH transfer.
contract RejectingSeller {
    receive() external payable {
        revert("REJECT_ETH");
    }
}

/// @notice Helper locale che altera il raw balance senza eseguire il recipient.
contract ForceEther {
    constructor() payable { }

    function force(address payable target) external {
        // SELFDESTRUCT e' deprecato. Qui serve soltanto a mostrare una proprieta' EVM.
        selfdestruct(target);
    }
}

