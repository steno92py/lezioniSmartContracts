// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Pull-payment vault minimale per regression test su callback e rollback.
/// @dev Pull payment: il vault non invia ETH di sua iniziativa, e' ogni beneficiario a
/// ritirare il proprio credito con withdraw().
contract WithdrawalVault {
    error ZeroAddress();
    error ZeroAmount();
    error NoCredit(address account);
    error EtherTransferFailed();

    mapping(address account => uint256 amount) public credit;
    // Somma di tutti i crediti: in ogni momento deve valere balance(vault) >= totalLiabilities.
    uint256 public totalLiabilities;

    function depositFor(address beneficiary) external payable {
        // Un credito intestato ad address(0) non potrebbe mai essere ritirato: ETH bloccati.
        if (beneficiary == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        credit[beneficiary] += msg.value;
        totalLiabilities += msg.value;
    }

    function withdraw() external {
        uint256 amount = credit[msg.sender];
        if (amount == 0) revert NoCredit(msg.sender);

        // Checks-effects-interactions: il credito si azzera PRIMA di inviare ETH.
        // Se il destinatario rientra in withdraw() durante la call, trova credito zero
        // e il secondo prelievo reverte con NoCredit.
        credit[msg.sender] = 0;
        totalLiabilities -= amount;
        // Inviare ETH a un contratto esegue il suo codice (receive): e' qui che puo' rientrare.
        (bool success,) = payable(msg.sender).call{value: amount}("");
        // Se il destinatario rifiuta gli ETH, il revert annulla anche l'azzeramento del credito:
        // l'utente non perde nulla e potra' riprovare.
        if (!success) revert EtherTransferFailed();
    }
}

