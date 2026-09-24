// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20Final, IPriceOracleFinal, INotifierFinal} from "../interfaces/IFinalDependencies.sol";
import {SafeERC20Lite} from "../libraries/SafeERC20Lite.sol";

/// @notice Remediation didattica sottoposta a regression, fuzz e invariant testing.
/// @dev Non costituisce una certificazione production-ready.
contract EscrowFinalFixed {
    // `using L for T`: le funzioni della libreria diventano chiamabili come metodi del tipo.
    // token.safeTransfer(to, x) equivale a SafeERC20Lite.safeTransfer(token, to, x).
    using SafeERC20Lite for IERC20Final;

    // Stesso ciclo di vita: Created -> Funded -> Released oppure Refunded.
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    // Stesso layout del target (immutable per le parti, storage per i parametri modificabili).
    IERC20Final public immutable token;
    address public immutable buyer;
    address public immutable seller;
    address public owner;
    address public emergencyPauser;
    IPriceOracleFinal public oracle;
    INotifierFinal public notifier; // opzionale: address(0) significa "nessun notifier"
    State public state;
    uint256 public escrowedAmount;
    uint256 public feeBps;
    bool public paused;

    uint256 public constant MAX_ORACLE_AGE = 1 hours;

    error OnlyBuyer();
    error OnlyOwner();
    error OnlyPauser();
    error InvalidState();
    error ZeroAmount();
    error ZeroAddress();
    error Paused();
    error InvalidPrice();
    error InvalidTimestamp();
    error StalePrice();
    error FeeTooHigh();

    event Deposited(uint256 requestedAmount, uint256 receivedAmount);
    event Released(uint256 grossAmount, uint256 fee);
    event Refunded(uint256 amount);
    event NotificationFailed(bytes reason);
    // Ogni modifica amministrativa lascia una traccia: vecchio e nuovo valore.
    // `indexed` rende il campo filtrabile off-chain (finisce nei topic del log).
    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    event FeeChanged(uint256 oldFeeBps, uint256 newFeeBps);
    event PauseChanged(bool paused);

    constructor(
        IERC20Final token_,
        address buyer_,
        address seller_,
        address owner_,
        address emergencyPauser_,
        IPriceOracleFinal oracle_,
        INotifierFinal notifier_
    ) {
        // Validazione degli indirizzi obbligatori: le immutable non si possono piu' correggere.
        // Il notifier non e' nella lista perche' e' opzionale.
        if (
            address(token_) == address(0) || buyer_ == address(0) || seller_ == address(0) || owner_ == address(0)
                || emergencyPauser_ == address(0) || address(oracle_) == address(0)
        ) revert ZeroAddress();

        token = token_;
        buyer = buyer_;
        seller = seller_;
        owner = owner_;
        emergencyPauser = emergencyPauser_;
        oracle = oracle_;
        notifier = notifier_;
        state = State.Created;
    }

    function deposit(uint256 requestedAmount) external {
        if (paused) revert Paused();
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Created) revert InvalidState();
        if (requestedAmount == 0) revert ZeroAmount();

        // Balance delta: si misura il saldo prima e dopo il trasferimento e si accredita
        // la differenza, cioe' quanto e' arrivato davvero, non quanto e' stato richiesto.
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(buyer, address(this), requestedAmount); // revert se fallisce
        uint256 received = token.balanceOf(address(this)) - beforeBalance;
        if (received == 0) revert ZeroAmount();

        escrowedAmount = received;
        state = State.Funded;
        emit Deposited(requestedAmount, received); // l'evento mostra entrambi i valori
    }

    function release() external {
        if (paused) revert Paused();
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        // Tre controlli sul dato dell'oracle: prezzo positivo, timestamp plausibile
        // (non zero, non nel futuro), eta' entro MAX_ORACLE_AGE.
        // Confine: eta' == MAX_ORACLE_AGE e' accettata, solo `>` e' stale.
        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0) revert InvalidPrice();
        if (updatedAt == 0 || updatedAt > block.timestamp) revert InvalidTimestamp();
        // La sottrazione e' sicura: la riga sopra garantisce updatedAt <= block.timestamp.
        if (block.timestamp - updatedAt > MAX_ORACLE_AGE) revert StalePrice();

        uint256 gross = escrowedAmount;
        uint256 fee = gross * feeBps / 10_000;
        uint256 payout = gross - fee;

        // Effects prima dell'interaction. Se safeTransfer revert, l'intera transazione
        // viene annullata, compresi questi due write: lo stato torna Funded.
        escrowedAmount = 0;
        state = State.Released;
        token.safeTransfer(seller, payout);

        // Notifier best-effort: try/catch cattura il revert della chiamata esterna, quindi
        // il settlement prosegue comunque, ma il fallimento resta visibile in un evento.
        if (address(notifier) != address(0)) {
            try notifier.notifyReleased(seller, payout) {}
            catch (bytes memory reason) {
                emit NotificationFailed(reason); // reason = dati grezzi del revert
            }
        }
        emit Released(gross, fee);
    }

    // Come da specifica, refund resta disponibile anche in pausa.
    function refund() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert InvalidState();

        uint256 amount = escrowedAmount;
        escrowedAmount = 0;
        state = State.Refunded;
        token.safeTransfer(buyer, amount);
        emit Refunded(amount);
    }

    function setFee(uint256 newFeeBps) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (newFeeBps > 1_000) revert FeeTooHigh();
        emit FeeChanged(feeBps, newFeeBps); // emesso prima del write: feeBps e' ancora il vecchio
        feeBps = newFeeBps;
    }

    // Solo l'owner puo' cambiare l'oracle, e mai verso address(0).
    // L'owner puo' essere un timelock: vedi src/extensions/FinalTimelock.sol.
    function setOracle(IPriceOracleFinal newOracle) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (address(newOracle) == address(0)) revert ZeroAddress();
        emit OracleChanged(address(oracle), address(newOracle));
        oracle = newOracle;
    }

    function pause() external {
        if (msg.sender != emergencyPauser) revert OnlyPauser();
        paused = true;
        emit PauseChanged(true);
    }

    function unpause() external {
        if (msg.sender != owner) revert OnlyOwner();
        paused = false;
        emit PauseChanged(false);
    }
}
