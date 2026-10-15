// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Reentrancy in una figura. La call a msg.sender NON e' un semplice "invio di ETH": passa il
// controllo al destinatario, che puo' eseguire codice (receive) e richiamare il vault prima che
// il primo withdraw sia finito. Tutti i frame annidati condividono lo STESSO storage.
//
//   withdraw #1: legge credit = 1 ETH
//     call ----> receiver.receive() ----> withdraw #2: legge credit = 1 ETH (non ancora azzerato!)
//                                           call ----> receiver.receive() ----> withdraw #3 ...
//                                           credit = 0; totalCredits -= 1 ETH
//     credit = 0; totalCredits -= 1 ETH   <- gli EFFECTS arrivano solo durante il ritorno (unwind)

/// @notice Vault volutamente vulnerabile. Usare soltanto nel laboratorio locale.
contract VulnerableVault {
    // Quanti wei il vault deve a ogni utente: il "diritto" da spendere una sola volta.
    mapping(address user => uint256 amount) public credit;
    // Somma di tutti i crediti: le liabilities del vault. Normalmente vale
    // address(this).balance >= totalCredits (assets >= liabilities).
    uint256 public totalCredits;

    error ZeroDeposit();
    error NoCredit();
    error TransferFailed();

    /// @dev `payable`: senza questa parola una call con ETH allegato reverte.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        credit[msg.sender] += msg.value;
        totalCredits += msg.value;
    }

    function withdraw() external {
        // CHECK: il chiamante ha un credito da ritirare?
        // `amount` e' una variabile locale: ogni frame annidato ne ha una sua copia.
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        // VULNERABILE: INTERACTION prima degli EFFECTS.
        // Low-level call: invia `amount` wei a msg.sender con calldata vuota (""), quindi nel
        // destinatario gira receive(). Restituisce `ok` invece di revertire da sola: controllarlo
        // e' obbligatorio. Se msg.sender e' un contratto, da qui in poi il controllo e' suo.
        (bool ok,) = msg.sender.call{ value: amount }("");
        if (!ok) revert TransferFailed();

        // Durante la callback il credito era ancora spendibile.
        // FIX (vedi SafeVaultCEI): spostare queste due righe PRIMA della call.
        credit[msg.sender] = 0;
        totalCredits -= amount;
    }
}
