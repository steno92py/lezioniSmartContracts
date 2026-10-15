// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Non eredita da IERC20 ne' la implementa: le sue funzioni non restituiscono il bool, quindi
// per il compilatore non e' un IERC20. I selector pero' coincidono (dipendono solo da nome e
// tipi dei parametri), percio' una call costruita per IERC20 raggiunge queste funzioni.
// Una call tipizzata si aspetterebbe 32 byte di ritorno e reverterebbe; SafeERC20Lite invece
// accetta "nessun dato" quando la call riesce.
/// @notice Token legacy-like: selector ERC-20 compatibili, ma nessun bool di ritorno.
contract NoReturnToken {
    error InsufficientBalance();
    error InsufficientAllowance();

    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }

    // Il fallimento qui e' un revert, mai un `false`: non c'e' un bool da restituire.
    function transferFrom(address from, address to, uint256 amount) external {
        uint256 available = allowance[from][msg.sender];
        if (available < amount) revert InsufficientAllowance();

        allowance[from][msg.sender] = available - amount;
        _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 available = balanceOf[from];
        if (available < amount) revert InsufficientBalance();

        balanceOf[from] = available - amount;
        balanceOf[to] += amount;
    }
}
