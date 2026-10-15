// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Target dell'audit. I commenti in questo file descrivono soltanto la MECCANICA (che cosa fa
// ogni riga e quale concetto Solidity usa): stabilire se controlli e ordine sono corretti e'
// il lavoro dello studente. Percorso consigliato: README -> audit/scope.md -> ... -> qui.
// Le righe marcate AUD-xx sono note del report finale: se vuoi fare l'audit da solo,
// ignorale finche' non hai scritto le tue ipotesi.
//
// Tre dipendenze esterne, raggiunte tramite interfacce (vedi IAuditDependencies.sol):
//   token     custodisce gli asset;
//   oracle    fornisce prezzo e timestamp;
//   notifier  riceve una notifica al settlement (facoltativo: address(0) = nessuno).
import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../interfaces/IAuditDependencies.sol";

/// @notice Target congelato del mini audit. Contiene vulnerabilita intenzionali.
/// @dev Non usare in produzione e non correggere qui: le PoC devono restare riproducibili.
contract AuditEscrow {
    // Lifecycle: il valore di default di un enum e' il primo, quindi si parte da Created.
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    // Custom error senza parametri: il test ne verifica il selettore (.selector).
    error WrongCaller();
    error WrongState();
    error Paused();
    error InvalidPrice();
    error StalePrice();
    error TokenTransferFailed();
    error ZeroAddress();

    event Deposited(uint256 requestedAmount);
    event Released(uint256 amount);
    event Refunded(uint256 amount);
    // Fino a tre campi `indexed`: filtrabili da chi legge i log off-chain.
    event OracleChanged(address indexed oldOracle, address indexed newOracle, address indexed caller);
    event PauseChanged(bool paused);

    // `immutable`: fissati nel constructor e poi non piu' modificabili da nessuna funzione.
    // `public` genera il getter omonimo (buyer(), seller(), ...).
    address public immutable buyer;
    address public immutable seller;
    address public immutable governance;
    address public immutable guardian;
    IAuditToken public immutable token;
    ISettlementNotifier public immutable notifier;
    uint256 public immutable minPrice;
    uint256 public immutable maxAge;

    // Variabili di storage MUTABILI: sono le sole che le funzioni possono riscrivere.
    // Per ciascuna conviene cercare tutte le write (vedi "write-path worksheet").
    IPriceOracle public oracle;
    State public state;
    uint256 public liability;
    bool public paused;

    constructor(
        address buyer_,
        address seller_,
        address governance_,
        address guardian_,
        IAuditToken token_,
        IPriceOracle oracle_,
        ISettlementNotifier notifier_,
        uint256 minPrice_,
        uint256 maxAge_
    ) {
        // Un solo revert per sei indirizzi: basta che uno sia zero (`||` = OR logico).
        // Il notifier non compare: e' facoltativo.
        if (
            buyer_ == address(0) || seller_ == address(0) || governance_ == address(0) || guardian_ == address(0)
                || address(token_) == address(0) || address(oracle_) == address(0)
        ) revert ZeroAddress();

        buyer = buyer_;
        seller = seller_;
        governance = governance_;
        guardian = guardian_;
        token = token_;
        oracle = oracle_;
        notifier = notifier_;
        minPrice = minPrice_;
        maxAge = maxAge_;
        // `state`, `liability` e `paused` non vengono scritti: restano ai default
        // (Created, 0, false).
    }

    function deposit(uint256 amount) external {
        if (msg.sender != buyer) revert WrongCaller();
        if (state != State.Created) revert WrongState();

        // Call tipizzata tramite interfaccia: si legge il bool restituito e `!` lo nega.
        // Chiede al token di spostare `amount` dal buyer a qui, spendendo la sua allowance.
        if (!token.transferFrom(msg.sender, address(this), amount)) revert TokenTransferFailed();

        // AUD-02: accredita il nominale senza misurare quanto e' arrivato.
        liability = amount;
        state = State.Funded;
        emit Deposited(amount);
    }

    /// @notice Chiunque puo' finalizzare quando il prezzo raggiunge la soglia.
    function release() external {
        if (paused) revert Paused();
        if (state != State.Funded) revert WrongState();

        // Destrutturazione di una tupla: la funzione restituisce due valori.
        // `price` e' con segno (int256); uint256(price) lo converte per il confronto con
        // minPrice, dopo aver escluso i valori <= 0.
        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0 || uint256(price) < minPrice) revert InvalidPrice();

        // block.timestamp: istante del blocco corrente, in secondi Unix.
        // La differenza e' l'eta' del prezzo in secondi.
        // AUD-04: al confine esatto maxAge il dato viene ancora accettato.
        if (block.timestamp - updatedAt > maxAge) revert StalePrice();

        uint256 amount = liability; // copia locale del valore letto dallo storage

        // AUD-01: due chiamate esterne precedono la chiusura della liability.
        if (!token.transfer(seller, amount)) revert TokenTransferFailed();
        // Il notifier viene chiamato solo se configurato (indirizzo diverso da zero).
        if (address(notifier) != address(0)) notifier.notify(buyer, seller, amount);

        liability = 0;
        state = State.Released;
        emit Released(amount);
    }

    function refund() external {
        if (msg.sender != buyer) revert WrongCaller();
        if (state != State.Funded) revert WrongState();

        uint256 amount = liability;
        liability = 0;
        state = State.Refunded;
        if (!token.transfer(buyer, amount)) revert TokenTransferFailed();
        emit Refunded(amount);
    }

    // Funzioni amministrative: cambiano configurazione (oracle) o stato operativo (paused).
    function setOracle(IPriceOracle newOracle) external {
        // AUD-03: il guardian di emergenza aggira il path governance dichiarato.
        if (msg.sender != governance && msg.sender != guardian) revert WrongCaller();
        if (address(newOracle) == address(0)) revert ZeroAddress();
        // L'evento legge il vecchio oracle prima che venga sovrascritto.
        emit OracleChanged(address(oracle), address(newOracle), msg.sender);
        oracle = newOracle;
    }

    function pause() external {
        if (msg.sender != governance && msg.sender != guardian) revert WrongCaller();
        paused = true;
        emit PauseChanged(true);
    }

    function unpause() external {
        if (msg.sender != governance) revert WrongCaller();
        paused = false;
        emit PauseChanged(false);
    }
}

