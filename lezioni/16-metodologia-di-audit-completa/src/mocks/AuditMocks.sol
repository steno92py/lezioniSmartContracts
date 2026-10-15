// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Mock avversariali: ognuno riproduce un comportamento di una dipendenza reale, cosi' che
// i test possano esercitarlo in modo deterministico. Sono harness, non target (scope.md).
import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../interfaces/IAuditDependencies.sol";

// Token "onesto" di base. Le funzioni `virtual` possono essere ridefinite dai derivati.
// mint senza controllo di ruolo: accettabile solo in un mock di test.
contract MockToken is IAuditToken {
    error InsufficientBalance();
    error InsufficientAllowance();

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

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

// Transfer-tax token: il destinatario riceve `amount - fee`, la fee viene bruciata.
// feeBps in basis point: 10_000 = 100%, 1_000 = 10%.
contract FeeToken is MockToken {
    uint256 public immutable feeBps;

    constructor(uint256 feeBps_) {
        feeBps = feeBps_;
    }

    // `override`: sostituisce _transfer di MockToken, quindi vale sia per transfer sia per
    // transferFrom.
    function _transfer(address from, address to, uint256 amount) internal override {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        uint256 fee = amount * feeBps / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}

// Interfaccia minima per costruire la calldata di release() senza importare l'escrow.
interface IReleaseTarget {
    function release() external;
}

// Token con callback: dopo un trasferimento IN USCITA dal `target`, richiama una volta
// target.release(). Simula un token con hook (per esempio in stile ERC-777).
//
//   caller --release()--> target --transfer()--> ReentrantToken
//                                                   |-- _transfer (saldi aggiornati)
//                                                   '-- target.release()  (callback)
//   Nel callback msg.sender per target e' il token, non il caller originale.
contract ReentrantToken is MockToken {
    address public target;
    bool public armed;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    function configure(address target_) external {
        target = target_;
        armed = true;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        super._transfer(from, to, amount); // `super`: esegue prima la versione di MockToken

        if (armed && from == target) {
            armed = false; // disarmato PRIMA della call: un solo tentativo, niente ricorsione
            callbackAttempted = true;
            // Call a basso livello: un revert del target NON fa fallire il transfer, viene
            // solo registrato in callbackSucceeded (letto poi dai test).
            (callbackSucceeded,) = target.call(abi.encodeCall(IReleaseTarget.release, ()));
        }
    }
}

// Oracle programmabile: il test decide prezzo e timestamp con set(). Senza controllo di
// ruolo di proposito: nei test l'oracle e' una variabile da controllare.
contract MockOracle is IPriceOracle {
    int256 public price;
    uint256 public updatedAt;

    constructor(int256 price_, uint256 updatedAt_) {
        set(price_, updatedAt_);
    }

    // `public` (non external) perche' la chiama anche il constructor dall'interno.
    function set(int256 price_, uint256 updatedAt_) public {
        price = price_;
        updatedAt = updatedAt_;
    }

    function latestPrice() external view returns (int256, uint256) {
        return (price, updatedAt);
    }
}

// Notifier che registra l'ultima chiamata: i test verificano quante volte e con quali dati.
contract RecordingNotifier is ISettlementNotifier {
    uint256 public calls;
    address public lastBuyer;
    address public lastSeller;
    uint256 public lastAmount;

    function notify(address buyer, address seller, uint256 amount) external {
        calls += 1;
        lastBuyer = buyer;
        lastSeller = seller;
        lastAmount = amount;
    }
}

// Notifier sempre indisponibile: ogni chiamata reverte.
contract RevertingNotifier is ISettlementNotifier {
    error NotificationUnavailable();

    function notify(address, address, uint256) external pure {
        revert NotificationUnavailable();
    }
}

