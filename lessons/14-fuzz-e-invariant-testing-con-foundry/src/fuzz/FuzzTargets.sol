// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Bersagli dei fuzz test stateless: funzioni piccole con proprieta' facili da enunciare
// ("la fee non supera mai l'importo", "solo il buyer deposita", "un prezzo stale e' rifiutato").

contract FeeCalculator {
    // Basis point: 10_000 bps = 100%, quindi al massimo il 10%.
    uint256 public constant MAX_FEE_BPS = 1_000;

    error FeeTooHigh(uint256 feeBps);

    // `pure`: non legge ne' scrive lo stato, il risultato dipende solo dagli argomenti.
    // Ideale per il fuzzing: ogni input e' un caso indipendente.
    function fee(uint256 amount, uint256 feeBps) external pure returns (uint256) {
        if (feeBps > MAX_FEE_BPS) revert FeeTooHigh(feeBps);
        // Moltiplicazione prima della divisione. Con amount enorme il prodotto andrebbe in
        // overflow (revert automatico dalla 0.8): per questo i test limitano il dominio.
        return amount * feeBps / 10_000;
    }

    // Controvalore di `amount` a un prezzo con 18 decimali (1e18 = 1,0).
    function quote(uint256 amount, uint256 price) external pure returns (uint256) {
        return amount * price / 1e18;
    }
}

contract SimpleEscrow {
    error ZeroAddress();
    error OnlyBuyer(address caller);
    error ZeroAmount();
    error AlreadyFunded();

    address public immutable buyer;
    uint256 public escrowedAmount;
    bool public funded;

    constructor(address buyer_) {
        if (buyer_ == address(0)) revert ZeroAddress();
        buyer = buyer_;
    }

    function deposit(uint256 amount) external {
        // Ordine: autorizzazione, stato, input. Un fuzz test dedicato verifica che un estraneo
        // riceva OnlyBuyer anche con amount = 0.
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        if (funded) revert AlreadyFunded(); // un solo deposito
        if (amount == 0) revert ZeroAmount();
        escrowedAmount = amount;
        funded = true;
    }
}

// Oracle senza alcun controllo: i test scrivono prezzo e timestamp a piacere.
contract MutableOracle {
    int256 public price;
    uint256 public updatedAt;

    function setAnswer(int256 newPrice, uint256 newUpdatedAt) external {
        price = newPrice;
        updatedAt = newUpdatedAt;
    }
}

// Consumer che accetta un prezzo solo se positivo, non nel futuro e non piu' vecchio di MAX_AGE.
contract FreshPriceConsumer {
    uint256 public constant MAX_AGE = 1 hours;

    error InvalidPrice(int256 price);
    error FutureTimestamp(uint256 updatedAt, uint256 currentTimestamp);
    error StalePrice(uint256 updatedAt, uint256 currentTimestamp);

    MutableOracle public immutable oracle;

    constructor(MutableOracle oracle_) {
        oracle = oracle_;
    }

    function readPrice() external view returns (int256 price) {
        price = oracle.price();
        uint256 updatedAt = oracle.updatedAt();
        if (price <= 0) revert InvalidPrice(price);
        // Da controllare prima della sottrazione sotto, che altrimenti andrebbe in underflow.
        if (updatedAt > block.timestamp) revert FutureTimestamp(updatedAt, block.timestamp);
        // `>`: un'eta' esattamente uguale a MAX_AGE e' ancora valida (confine incluso).
        if (block.timestamp - updatedAt > MAX_AGE) {
            revert StalePrice(updatedAt, block.timestamp);
        }
    }
}
