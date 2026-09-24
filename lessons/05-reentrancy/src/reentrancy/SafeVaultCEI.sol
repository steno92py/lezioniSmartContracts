// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Stesso vault di VulnerableVault, stesse funzioni: cambia SOLO l'ordine dentro withdraw.
// Checks -> Effects -> Interactions (CEI): quando il controllo passa al destinatario, lo storage
// e' gia' coerente. Una callback che richiama withdraw vede credit = 0 e riceve NoCredit.

/// @notice Vault corretto riordinando stato e interazione secondo CEI.
contract SafeVaultCEI {
    mapping(address user => uint256 amount) public credit;
    uint256 public totalCredits;

    error ZeroDeposit();
    error NoCredit();
    error TransferFailed();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        credit[msg.sender] += msg.value;
        totalCredits += msg.value;
    }

    function withdraw() external {
        // CHECKS
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit();

        // EFFECTS: il diritto viene consumato prima della trust boundary.
        // `amount` resta nella variabile locale: il valore da pagare non si perde.
        credit[msg.sender] = 0;
        totalCredits -= amount;

        // INTERACTION
        (bool ok,) = msg.sender.call{ value: amount }("");
        // Se il pagamento fallisce, il revert annulla anche gli EFFECTS qui sopra:
        // il credito torna intatto e l'utente potra' riprovare.
        if (!ok) revert TransferFailed();
    }
}
