// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Token exact-transfer minimale: la policy dell'invariant lab esclude fee e rebase.
/// @dev Exact-transfer: il destinatario riceve esattamente `amount`, niente fee, niente
/// callback, niente `return false`. E' una precondizione dell'invariante balance == credito:
/// con un token diverso l'invariante andrebbe riformulato.
contract ExactToken {
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    // Senza controllo d'accesso: in questo laboratorio conia solo il codice di test.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        // Saldo insufficiente -> revert, mai un fallimento silenzioso.
        require(balanceOf[from] >= amount, "BALANCE");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

