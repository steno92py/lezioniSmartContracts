// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "./token/IERC20.sol";

// Catena della call di deposit:
//
//   buyer --deposit(100)--> Vault --transferFrom(buyer, vault, 100)--> token
//                                    msg.sender nel token = Vault (lo spender)
//                                    ritorno: false, nessun token spostato
//   Vault ignora il `false` e scrive comunque credit[buyer] += 100.
/// @notice Contratto intenzionalmente vulnerabile: ignora il bool di transferFrom().
contract VulnerableTokenVault {
    // `immutable`: fissato nel constructor, poi scritto nel bytecode e non piu' modificabile.
    IERC20 public immutable token;
    mapping(address account => uint256 amount) public credit;

    constructor(IERC20 token_) {
        token = token_;
    }

    function deposit(uint256 amount) external {
        // BUG: una call che ritorna false non impedisce l'aggiornamento contabile.
        // Il compilatore segnala il return value ignorato (warning atteso, vedi README).
        // Correzione: token.safeTransferFrom(...) di SafeERC20Lite, come in TokenEscrow.
        token.transferFrom(msg.sender, address(this), amount);
        credit[msg.sender] += amount; // credito senza asset dietro: "unbacked credit"
    }
}
