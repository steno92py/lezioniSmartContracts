// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Tre destinatari "giocattolo" usati dai test come seller o come sorgente di ETH.

/// @notice Dimostra che ricevere ETH puo' eseguire codice e scrivere storage.
contract AcceptingSeller {
    uint256 public totalReceived;

    // receive() gira quando arriva una call con calldata vuota, come il payout dell'Escrow.
    // Qui aggiorna il proprio storage: ricevere ETH non e' un evento passivo.
    receive() external payable {
        totalReceived += msg.value;
    }
}

/// @notice Destinatario avversariale che rifiuta ogni plain ETH transfer.
contract RejectingSeller {
    // Revert dentro receive(): la call dell'Escrow restituisce success == false.
    receive() external payable {
        revert("REJECT_ETH");
    }
}

/// @notice Helper locale che altera il raw balance senza eseguire il recipient.
contract ForceEther {
    // Constructor `payable`: il contratto riceve ETH gia' al deploy (new ForceEther{value: x}()).
    constructor() payable { }

    function force(address payable target) external {
        // SELFDESTRUCT e' deprecato. Qui serve soltanto a mostrare una proprieta' EVM.
        // Trasferisce tutto il saldo di questo contratto a `target` SENZA eseguire codice di
        // target: ne' receive() ne' fallback(), quindi nessun revert puo' fermarlo.
        selfdestruct(target);
    }
}
