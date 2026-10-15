// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20Final, IPriceOracleFinal, INotifierFinal} from "../interfaces/IFinalDependencies.sol";

// Mock: contratti finti usati solo nei test, per simulare dipendenze normali e avversariali.
// Nessun controllo di accesso: nei test chiunque deve poter coniare o impostare prezzi.

// ERC-20 minimale e "onesto": trasferisce esattamente l'importo e restituisce true.
contract TestToken is IERC20Final {
    error InsufficientBalance();
    error InsufficientAllowance();

    string public name = "Test Token";
    string public symbol = "TEST";
    uint8 public constant decimals = 18;
    // Le variabili public implementano le funzioni view dell'interfaccia tramite il getter.
    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;
    // Mapping annidato: owner -> spender -> importo che lo spender puo' prelevare.
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // `virtual`: i contratti figli possono sostituire (override) questa funzione.
    function transfer(address to, uint256 amount) external virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    // Chi chiama (msg.sender) preleva da `from` consumando l'allowance che `from` gli ha dato.
    function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < amount) revert InsufficientAllowance();
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

// Token con fee sul trasferimento: il mittente perde `amount`, il destinatario riceve il 90%,
// il 10% viene bruciato (esce anche dal totalSupply).
contract FeeToken is TestToken {
    uint256 public constant FEE_BPS = 1_000;

    function _transfer(address from, address to, uint256 amount) internal override {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        uint256 fee = amount * FEE_BPS / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}

// Token il cui transfer non sposta nulla e restituisce false senza revertire.
// transferFrom resta quello di TestToken, quindi il deposito funziona normalmente.
contract FalsePayoutToken is TestToken {
    // Parametri senza nome: non vengono usati. `pure` perche' non tocca lo stato.
    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }
}

// Oracle manovrabile: il test sceglie prezzo e timestamp con setPrice.
contract MockOracle is IPriceOracleFinal {
    int256 public answer;
    uint256 public updatedAt;

    constructor(int256 answer_, uint256 updatedAt_) {
        setPrice(answer_, updatedAt_);
    }

    // `public` (non external) perche' viene chiamata anche dal constructor.
    function setPrice(int256 answer_, uint256 updatedAt_) public {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestPrice() external view returns (int256, uint256) {
        return (answer, updatedAt);
    }
}

// Notifier che registra le chiamate ricevute, per verificarle nei test.
contract RecordingNotifier is INotifierFinal {
    uint256 public calls;
    address public lastSeller;
    uint256 public lastAmount;

    function notifyReleased(address seller, uint256 amount) external {
        calls += 1;
        lastSeller = seller;
        lastAmount = amount;
    }
}

// Notifier che revert sempre: simula un servizio non disponibile.
contract RevertingNotifier is INotifierFinal {
    error NotificationUnavailable();

    function notifyReleased(address, uint256) external pure {
        revert NotificationUnavailable();
    }
}
