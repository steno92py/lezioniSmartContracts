// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Mock: contratti finti che i test configurano per riprodurre comportamenti difficili da
// ottenere con dipendenze reali (token che restituiscono false, oracle che revertono,
// destinatari ostili). Non hanno controlli d'accesso: esistono solo nei test.
import {ITestToken, ITestOracle} from "../interfaces/ITestDependencies.sol";
import {WithdrawalVault} from "../WithdrawalVault.sol";

// Token ERC-20 minimale con tre "manopole": fee sul trasferimento e valore di ritorno
// di transfer e transferFrom.
contract ConfigurableToken is ITestToken {
    // Un mapping `public` genera il getter balanceOf(address): soddisfa l'interfaccia.
    mapping(address account => uint256 amount) public balanceOf;
    // Mapping annidato: allowance[owner][spender] = quanto spender puo' spendere per owner.
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    uint256 public feeBps;
    bool public transferReturns = true;
    bool public transferFromReturns = true;

    // Chiunque puo' coniare: accettabile solo in un mock.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // Esempio: configure(100, true, true) = fee dell'1%; configure(0, false, true) = transfer
    // restituisce false senza muovere nulla.
    function configure(uint256 newFeeBps, bool transferResult, bool transferFromResult) external {
        feeBps = newFeeBps;
        transferReturns = transferResult;
        transferFromReturns = transferFromResult;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        // Fallimento "silenzioso": nessun revert, solo false. Chi chiama deve controllarlo.
        if (!transferReturns) return false;
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (!transferFromReturns) return false;
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "BALANCE");
        // Fee-on-transfer: il mittente perde `amount`, il destinatario riceve `amount - fee`.
        uint256 fee = amount * feeBps / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
    }
}

// Oracle programmabile: il test decide prezzo, timestamp e se la lettura deve revertire.
contract MockOracle is ITestOracle {
    error OracleUnavailable();

    int256 public price;
    uint256 public updatedAt;
    bool public shouldRevert;

    function setAnswer(int256 newPrice, uint256 newUpdatedAt) external {
        price = newPrice;
        updatedAt = newUpdatedAt;
    }

    function setShouldRevert(bool enabled) external {
        shouldRevert = enabled;
    }

    function latestPrice() external view returns (int256, uint256) {
        if (shouldRevert) revert OracleUnavailable();
        return (price, updatedAt);
    }
}

// Destinatario ostile: quando riceve ETH prova a rientrare nel vault una seconda volta.
contract ReentrantReceiver {
    WithdrawalVault public immutable vault;
    // Due flag che il test legge dopo l'attacco: il tentativo c'e' stato? e' riuscito?
    bool public callbackAttempted;
    bool public secondWithdrawalSucceeded;

    constructor(WithdrawalVault vault_) {
        vault = vault_;
    }

    function attack() external {
        vault.withdraw();
    }

    // `receive()` viene eseguita quando il contratto riceve ETH senza calldata:
    // qui avviene durante la call del vault, PRIMA che withdraw() sia terminata.
    receive() external payable {
        // Il flag limita il rientro a un solo tentativo, evitando una ricorsione infinita.
        if (!callbackAttempted) {
            callbackAttempted = true;
            // Call di basso livello: se il secondo withdraw reverte, l'errore non si propaga,
            // resta solo success = false. Cosi' il primo prelievo puo' completarsi e il test
            // puo' osservare l'esito del tentativo.
            (secondWithdrawalSucceeded,) = address(vault).call(abi.encodeCall(WithdrawalVault.withdraw, ()));
        }
    }
}

// Destinatario che rifiuta sempre gli ETH: fa fallire la call del vault.
contract RejectEther {
    function claim(WithdrawalVault vault) external {
        vault.withdraw();
    }

    receive() external payable {
        revert("NO_ETHER");
    }
}

