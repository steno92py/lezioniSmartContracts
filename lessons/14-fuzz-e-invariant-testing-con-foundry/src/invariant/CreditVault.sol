// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ExactToken} from "./ExactToken.sol";

// Vault multiutente: ognuno deposita token e ritira fino al proprio credito.
// Proprieta' di contabilita' che l'invariant test verifica dopo ogni sequenza di azioni:
//   token.balanceOf(vault) == totalCredit == somma dei credit di tutti gli utenti.
contract CreditVault {
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientCredit(address account, uint256 requested, uint256 available);
    error TokenTransferFailed();

    ExactToken public immutable token;
    mapping(address account => uint256 amount) public credit;
    uint256 public totalCredit; // totale dovuto a tutti gli utenti

    constructor(ExactToken token_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        // Il valore di ritorno del token si controlla sempre: un false non deve creare credito.
        if (!token.transferFrom(msg.sender, address(this), amount)) revert TokenTransferFailed();
        // Si accredita `amount` e non un balance delta: e' corretto SOLO perche' ExactToken
        // trasferisce esattamente amount (vedi MODEL.md, asset policy).
        credit[msg.sender] += amount;
        totalCredit += amount;
    }

    function withdraw(uint256 amount) external {
        uint256 available = credit[msg.sender];
        // Un solo errore per due casi: prelievo nullo e prelievo oltre il credito.
        // Il payload riporta richiesto e disponibile, cosi' i test li verificano entrambi.
        if (amount == 0 || amount > available) {
            revert InsufficientCredit(msg.sender, amount, available);
        }

        // Effetti prima del transfer: credito individuale e totale scendono insieme.
        credit[msg.sender] = available - amount;
        totalCredit -= amount;
        if (!token.transfer(msg.sender, amount)) revert TokenTransferFailed();
    }
}

