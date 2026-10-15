// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "../../src/token/IERC20.sol";

// Token "onesto" di riferimento. Gli altri mock ereditano da lui e cambiano un solo
// comportamento: `virtual` segna le funzioni che un contratto figlio puo' ridefinire,
// `override` segna la ridefinizione (o l'implementazione di una funzione dell'interfaccia).
/// @notice ERC-20 minimale e permissivo, esclusivamente per test locali.
contract TestToken is IERC20 {
    error ZeroAddress();
    error InsufficientBalance(address account, uint256 available, uint256 required);
    error InsufficientAllowance(address spender, uint256 available, uint256 required);

    // Variabili `public`: il getter generato (es. balanceOf(address)) implementa la funzione
    // omonima dell'interfaccia, per questo sono marcate `override`.
    uint256 public override totalSupply;
    mapping(address account => uint256 amount) public override balanceOf;
    // Mapping annidato: allowance[owner][spender] = quanto spender puo' spendere di owner.
    mapping(address owner => mapping(address spender => uint256 amount)) public override allowance;

    // Nessun controllo su chi chiama: chiunque puo' creare token. Permissivo di proposito,
    // e' un mock per i test, non un token da mettere in produzione.
    function mint(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount); // from = 0 e' la convenzione per il mint
    }

    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    // Sovrascrive l'allowance precedente, non la somma: approve(100) dopo approve(50) da' 100.
    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        virtual
        override
        returns (bool)
    {
        // msg.sender qui e' lo SPENDER (per esempio l'Escrow), non il proprietario `from`.
        uint256 available = allowance[from][msg.sender];
        if (available < amount) {
            revert InsufficientAllowance(msg.sender, available, amount);
        }

        // Convenzione diffusa: allowance "infinita" (il massimo uint256) non viene consumata.
        if (available != type(uint256).max) {
            allowance[from][msg.sender] = available - amount;
            emit Approval(from, msg.sender, available - amount);
        }

        _transfer(from, to, amount);
        return true;
    }

    // Punto di estensione: FeeToken lo ridefinisce per trattenere una fee.
    function _transfer(address from, address to, uint256 amount) internal virtual {
        _move(from, to, amount);
    }

    // Movimento elementare di saldo, non ridefinibile.
    function _move(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();

        uint256 available = balanceOf[from];
        if (available < amount) revert InsufficientBalance(from, available, amount);

        balanceOf[from] = available - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
