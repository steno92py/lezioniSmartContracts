// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Il contratto conosce token, oracle e notifier solo tramite interfacce: sa quali funzioni
// chiamare, non come sono implementate. Ogni dipendenza esterna e' codice di qualcun altro.
import {IERC20Final, IPriceOracleFinal, INotifierFinal} from "./interfaces/IFinalDependencies.sol";

/// @notice Target deliberatamente imperfetto del progetto finale.
/// @dev Congelare durante l'audit: le correzioni appartengono a EscrowFinalFixed.
contract EscrowFinal {
    // enum: un insieme finito di stati, salvato come uint8 (Created = 0, Funded = 1, ...).
    // Ciclo di vita previsto: Created -> Funded -> Released oppure Refunded.
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    // immutable: assegnate una sola volta nel constructor e poi incorporate nel bytecode;
    // non occupano uno slot di storage e nessuna funzione puo' riscriverle.
    IERC20Final public immutable token;
    address public immutable buyer;
    address public immutable seller;
    // Variabili di storage ordinarie: le funzioni del contratto possono modificarle dopo il deploy.
    // `public` genera un getter automatico, ad esempio escrow.owner().
    address public owner;
    address public emergencyPauser;
    IPriceOracleFinal public oracle;
    INotifierFinal public notifier;
    State public state;
    uint256 public escrowedAmount; // liability: quanto l'escrow deve ancora a seller o buyer
    uint256 public feeBps; // fee in basis point: 1 bps = 0,01%, 10_000 bps = 100%
    bool public paused;

    // constant: fissata a compile time. `1 hours` e' un'unita' di Solidity: 3600 secondi.
    uint256 public constant MAX_ORACLE_AGE = 1 hours;

    // Custom error: piu' economici di una stringa e verificabili nei test con .selector.
    error OnlyBuyer();
    error OnlyOwner();
    error OnlyPauser();
    error InvalidState();
    error ZeroAmount();
    error Paused();
    error InvalidPrice();
    error FeeTooHigh();

    // Eventi: log leggibili off-chain (indexer, monitor), non dal codice on-chain.
    event Deposited(uint256 requestedAmount, uint256 creditedAmount);
    event Released(uint256 grossAmount, uint256 fee);
    event Refunded(uint256 amount);

    // Il constructor gira una sola volta, al deploy: fissa parti, ruoli e dipendenze.
    constructor(
        IERC20Final token_,
        address buyer_,
        address seller_,
        address owner_,
        address emergencyPauser_,
        IPriceOracleFinal oracle_,
        INotifierFinal notifier_
    ) {
        token = token_;
        buyer = buyer_;
        seller = seller_;
        owner = owner_;
        emergencyPauser = emergencyPauser_;
        oracle = oracle_;
        notifier = notifier_;
        state = State.Created;
    }

    // Il buyer versa i token nell'escrow. Guard in ordine: pausa, ruolo, stato, importo.
    // transferFrom sposta token dal buyer all'escrow: il buyer deve aver chiamato prima
    // token.approve(escrow, amount), altrimenti il token rifiuta il prelievo.
    function deposit(uint256 amount) external {
        if (paused) revert Paused();
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Created) revert InvalidState();
        if (amount == 0) revert ZeroAmount();

        // F-01: return ignorato e accounting nominale.
        token.transferFrom(buyer, address(this), amount);
        escrowedAmount = amount;
        state = State.Funded;
        emit Deposited(amount, amount);
    }

    // Il buyer autorizza il pagamento al seller, trattenendo l'eventuale fee.
    function release() external {
        if (paused) revert Paused();
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        // La funzione restituisce due valori: la sintassi (a, b) = ... li destruttura.
        // Il prezzo e' int256 (con segno), per questo si esclude anche lo zero e il negativo.
        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0) revert InvalidPrice();
        updatedAt; // F-02: freshness ignorata.

        // Prima si moltiplica, poi si divide: la divisione intera tronca i decimali.
        uint256 gross = escrowedAmount;
        uint256 fee = gross * feeBps / 10_000;
        uint256 payout = gross - fee;

        // Effects prima delle interactions: lo stato si aggiorna, poi si chiama il token.
        escrowedAmount = 0;
        state = State.Released;

        token.transfer(seller, payout); // F-03: boolean return ignorato.

        // abi.encodeCall costruisce la calldata tipizzata (selettore + argomenti);
        // .call la invia all'indirizzo del notifier come chiamata a basso livello.
        // F-05: best-effort coerente con la policy, ma il fallimento rimane invisibile.
        address(notifier).call(abi.encodeCall(INotifierFinal.notifyReleased, (seller, payout)));
        emit Released(gross, fee);
    }

    // Il buyer recupera i fondi. Per specifica refund non guarda `paused`:
    // la pausa blocca nuovo rischio (deposit/release) ma lascia aperta l'uscita.
    function refund() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        uint256 amount = escrowedAmount; // copia locale prima di azzerare lo storage
        escrowedAmount = 0;
        state = State.Refunded;
        token.transfer(buyer, amount);
        emit Refunded(amount);
    }

    // Setter: cambiano parametri e dipendenze dopo il deploy.
    function setFee(uint256 newFeeBps) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (newFeeBps > 1_000) revert FeeTooHigh(); // tetto: 1_000 bps = 10%
        feeBps = newFeeBps;
    }

    function setOracle(IPriceOracleFinal newOracle) external {
        oracle = newOracle; // F-04: write critico senza authorization.
    }

    // Due ruoli distinti: il pauser ferma, l'owner riattiva.
    function pause() external {
        if (msg.sender != emergencyPauser) revert OnlyPauser();
        paused = true;
    }

    function unpause() external {
        if (msg.sender != owner) revert OnlyOwner();
        paused = false;
    }
}
