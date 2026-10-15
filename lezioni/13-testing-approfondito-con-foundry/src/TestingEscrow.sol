// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Le dipendenze esterne sono viste solo attraverso interfacce: nei test si possono sostituire
// con mock configurabili senza toccare questo contratto.
import {ITestToken, ITestOracle} from "./interfaces/ITestDependencies.sol";

/// @notice Escrow compatto usato per imparare a progettare test, non per produzione.
/// @dev Il ciclo di vita: il buyer deposita token, poi li rilascia al seller (meno la fee
/// dell'owner) oppure, dopo la deadline, se li fa rimborsare. Ogni regola qui sotto e' un
/// requisito che la suite di test deve poter dimostrare (vedi REQUIREMENTS.md).
contract TestingEscrow {
    // `enum`: un tipo con un insieme chiuso di valori, salvati come numeri (Created = 0...).
    // Rende esplicita la macchina a stati: Created -> Funded -> Released oppure Refunded.
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    // Custom error con payload: i test li verificano con abi.encodeWithSelector confrontando
    // anche i parametri, non soltanto "c'e' stato un revert".
    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized(address caller);
    error InvalidState(State expected, State actual);
    error FeeTooHigh(uint256 feeBps);
    error InvalidPrice(int256 price);
    error InvalidOracleTimestamp(uint256 updatedAt, uint256 currentTimestamp);
    error StalePrice(uint256 updatedAt, uint256 currentTimestamp);
    error TokenCallFailed();
    error UnexpectedReceived(uint256 requested, uint256 received);
    error RefundTooEarly(uint256 deadline, uint256 currentTimestamp);

    event Deposited(address indexed buyer, uint256 amount, int256 price);
    event Released(address indexed seller, uint256 payout, uint256 fee);
    event Refunded(address indexed buyer, uint256 amount);
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // Fee in basis point (bps): 10_000 bps = 100%, quindi 1_000 bps = 10% massimo.
    uint256 public constant MAX_FEE_BPS = 1_000;
    // Un prezzo piu' vecchio di un giorno e' "stale": non rappresenta piu' il mercato.
    uint256 public constant MAX_PRICE_AGE = 1 days;

    // I ruoli sono `immutable`: fissati al deploy, nessuno puo' cambiarli dopo.
    ITestToken public immutable token;
    address public immutable buyer;
    address public immutable seller;
    address public immutable owner;
    uint256 public immutable refundDeadline;

    // Stato mutabile: l'oracle e' l'unica dipendenza che l'owner puo' sostituire.
    ITestOracle public oracle;
    State public state; // parte da Created, il valore di default (0) dell'enum
    uint256 public depositedAmount;
    uint256 public feeBps;
    int256 public depositPrice; // `int256`: un oracle puo' restituire anche valori negativi

    constructor(
        address token_,
        address oracle_,
        address buyer_,
        address seller_,
        address owner_,
        uint256 refundDeadline_
    ) {
        // Un solo errore per cinque indirizzi: i test di Configuration.t.sol li provano uno a uno,
        // perche' dimenticarne uno nella condizione non farebbe fallire gli altri test.
        if (
            token_ == address(0) || oracle_ == address(0) || buyer_ == address(0) || seller_ == address(0)
                || owner_ == address(0)
        ) revert ZeroAddress();

        token = ITestToken(token_);
        oracle = ITestOracle(oracle_);
        buyer = buyer_;
        seller = seller_;
        owner = owner_;
        refundDeadline = refundDeadline_;
    }

    function deposit(uint256 requestedAmount) external {
        // L'ORDINE dei controlli e' parte della specifica: prima chi chiama, poi lo stato,
        // poi l'input. Un test dedicato (PreconditionOrder...) lo fissa.
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        // Il deposito e' possibile una volta sola: solo da Created.
        if (state != State.Created) revert InvalidState(State.Created, state);
        if (requestedAmount == 0) revert ZeroAmount();

        // Il prezzo arriva da un contratto esterno: va validato prima di usarlo.
        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0) revert InvalidPrice(price);
        // Un timestamp nel futuro e' un dato impossibile. Senza questo controllo la sottrazione
        // successiva andrebbe in underflow con un Panic generico invece di un errore chiaro.
        if (updatedAt > block.timestamp) {
            revert InvalidOracleTimestamp(updatedAt, block.timestamp);
        }
        // `>` e non `>=`: un prezzo vecchio ESATTAMENTE MAX_PRICE_AGE e' ancora accettato.
        // Proprio su questo confine si scrivono i boundary test.
        if (block.timestamp - updatedAt > MAX_PRICE_AGE) {
            revert StalePrice(updatedAt, block.timestamp);
        }

        // Balance delta: si misura quanto arriva davvero, non quanto si e' chiesto.
        uint256 balanceBefore = token.balanceOf(address(this));
        // Effetti PRIMA della call esterna. Se qualcosa dopo fallisce, il revert annulla
        // anche queste scritture: la transazione e' atomica.
        depositedAmount = requestedAmount;
        depositPrice = price;
        state = State.Funded;
        emit Deposited(msg.sender, requestedAmount, price);
        // abi.encodeCall costruisce la calldata controllando tipi e numero degli argomenti.
        _callOptionalReturn(abi.encodeCall(ITestToken.transferFrom, (msg.sender, address(this), requestedAmount)));
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        // Un token con fee-on-transfer consegnerebbe meno del richiesto: il contratto
        // registrerebbe un credito non coperto da token reali. Qui si rifiuta tutto.
        if (received != requestedAmount) revert UnexpectedReceived(requestedAmount, received);
    }

    function release() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Funded) revert InvalidState(State.Funded, state);

        uint256 gross = depositedAmount;
        // Si moltiplica prima di dividere: dividere prima perderebbe precisione.
        uint256 fee = gross * feeBps / 10_000;
        uint256 payout = gross - fee;

        // Stato terminale e liability azzerata prima dei transfer (checks-effects-interactions).
        depositedAmount = 0;
        state = State.Released;
        emit Released(seller, payout, fee);
        _callOptionalReturn(abi.encodeCall(ITestToken.transfer, (seller, payout)));
        if (fee != 0) {
            _callOptionalReturn(abi.encodeCall(ITestToken.transfer, (owner, fee)));
        }
    }

    function refund() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Funded) revert InvalidState(State.Funded, state);
        // `<`: dal secondo esatto della deadline il rimborso e' permesso.
        if (block.timestamp < refundDeadline) {
            revert RefundTooEarly(refundDeadline, block.timestamp);
        }

        uint256 amount = depositedAmount;
        depositedAmount = 0;
        state = State.Refunded;
        emit Refunded(buyer, amount);
        _callOptionalReturn(abi.encodeCall(ITestToken.transfer, (buyer, amount)));
    }

    // Funzioni amministrative: solo l'owner, sempre con un evento vecchio -> nuovo valore.
    function setFee(uint256 newFeeBps) external {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        // Limite INCLUSIVO: 1000 e' valido, 1001 no. I test coprono 999, 1000 e 1001.
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh(newFeeBps);
        uint256 oldFeeBps = feeBps;
        feeBps = newFeeBps;
        emit FeeUpdated(oldFeeBps, newFeeBps);
    }

    function setOracle(address newOracle) external {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        // Un oracle zero bloccherebbe per sempre ogni deposito.
        if (newOracle == address(0)) revert ZeroAddress();
        address oldOracle = address(oracle);
        oracle = ITestOracle(newOracle);
        emit OracleUpdated(oldOracle, newOracle);
    }

    /// @dev Quanto l'escrow deve ancora restituire. Proprieta' economica da testare:
    /// token.balanceOf(escrow) >= liability(). `cond ? a : b` e' l'operatore ternario.
    function liability() external view returns (uint256) {
        return state == State.Funded ? depositedAmount : 0;
    }

    /// @dev Chiama il token con una call di basso livello per gestire tre comportamenti:
    /// revert, `return false` e nessun valore di ritorno (alcuni token reali non restituiscono
    /// bool). `private`: nemmeno i contratti derivati possono chiamarla.
    function _callOptionalReturn(bytes memory data) private {
        // `.call` NON propaga il revert: restituisce success = false e va controllato a mano.
        (bool success, bytes memory returnData) = address(token).call(data);
        // Fallisce se la call e' fallita, oppure se ha restituito dati che decodificati sono false.
        // Nessun dato restituito (length == 0) viene accettato come successo.
        if (!success || (returnData.length != 0 && !abi.decode(returnData, (bool)))) {
            revert TokenCallFailed();
        }
    }
}
