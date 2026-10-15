// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IAuditToken, IPriceOracle, ISettlementNotifier} from "../interfaces/IAuditDependencies.sol";

// Patch separata dal target: si studia in fase di retest, confrontandola con
// src/target/AuditEscrow.sol (README, passo 4). Stessa struttura, stesse funzioni.
/// @notice Versione separata usata per review della patch e retest.
contract RemediatedEscrow {
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    error WrongCaller();
    error WrongState();
    error Paused();
    error InvalidPrice();
    error StalePrice();
    error TokenCallFailed();
    error UnsupportedTransferTax(uint256 requested, uint256 received);
    error ZeroAddress();
    error InvalidMaxAge();

    event Deposited(uint256 amount);
    event Released(uint256 amount);
    event Refunded(uint256 amount);
    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    event NotificationResult(bool success);
    event PauseChanged(bool paused);

    address public immutable buyer;
    address public immutable seller;
    address public immutable governance;
    address public immutable guardian;
    IAuditToken public immutable token;
    ISettlementNotifier public immutable notifier;
    uint256 public immutable minPrice;
    uint256 public immutable maxAge;

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
        if (
            buyer_ == address(0) || seller_ == address(0) || governance_ == address(0) || guardian_ == address(0)
                || address(token_) == address(0) || address(oracle_) == address(0)
        ) revert ZeroAddress();
        // Con `>= maxAge` in release, maxAge = 0 renderebbe ogni prezzo scaduto: release
        // sarebbe impossibile per sempre. Il deploy lo rifiuta subito.
        if (maxAge_ == 0) revert InvalidMaxAge();

        buyer = buyer_;
        seller = seller_;
        governance = governance_;
        guardian = guardian_;
        token = token_;
        oracle = oracle_;
        notifier = notifier_;
        minPrice = minPrice_;
        maxAge = maxAge_;
    }

    function deposit(uint256 amount) external {
        if (msg.sender != buyer) revert WrongCaller();
        if (state != State.Created) revert WrongState();

        // Balance delta: si misura quanto e' arrivato davvero, non quanto era stato chiesto.
        uint256 beforeBalance = token.balanceOf(address(this));
        _safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - beforeBalance;

        // Policy esplicita: questo escrow supporta soltanto trasferimenti esatti.
        if (received != amount) revert UnsupportedTransferTax(amount, received);

        liability = received;
        state = State.Funded;
        emit Deposited(received);
    }

    function release() external {
        if (paused) revert Paused();
        if (state != State.Funded) revert WrongState();

        (int256 price, uint256 updatedAt) = oracle.latestPrice();
        if (price <= 0 || uint256(price) < minPrice) revert InvalidPrice();
        // Freshness stretta: prezzo non futuro ed eta' strettamente minore di maxAge.
        // Il primo controllo evita anche l'underflow della sottrazione successiva.
        if (updatedAt > block.timestamp || block.timestamp - updatedAt >= maxAge) revert StalePrice();

        uint256 amount = liability;

        // Effects prima delle interactions: la seconda release non vede piu' Funded.
        liability = 0;
        state = State.Released;
        _safeTransfer(seller, amount);

        // Il notifier e' osservabilita' best-effort, non una condizione di settlement.
        // try/catch: se notify reverte, il revert viene catturato invece di propagarsi;
        // si registra l'esito in un evento e il settlement resta valido.
        if (address(notifier) != address(0)) {
            try notifier.notify(buyer, seller, amount) {
                emit NotificationResult(true);
            } catch {
                emit NotificationResult(false);
            }
        }

        emit Released(amount);
    }

    // Gia' in ordine CEI: effetti (liability, state) prima del trasferimento.
    function refund() external {
        if (msg.sender != buyer) revert WrongCaller();
        if (state != State.Funded) revert WrongState();

        uint256 amount = liability;
        liability = 0;
        state = State.Refunded;
        _safeTransfer(buyer, amount);
        emit Refunded(amount);
    }

    function setOracle(IPriceOracle newOracle) external {
        // Solo governance: il guardian puo' mettere in pausa ma non cambiare l'oracle.
        if (msg.sender != governance) revert WrongCaller();
        if (address(newOracle) == address(0)) revert ZeroAddress();
        emit OracleChanged(address(oracle), address(newOracle));
        oracle = newOracle;
    }

    // Ruoli asimmetrici: pausa da governance o guardian, rimozione della pausa solo governance.
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

    // Call a basso livello al token: restituisce (success, returndata) invece di revertire.
    // Fallimento se la call reverte oppure se restituisce dati che decodificano a `false`;
    // nessun dato di ritorno (token legacy) e' accettato come successo.
    // `private`: visibile solo in questo contratto, neppure nei contratti derivati.
    function _safeTransfer(address to, uint256 amount) private {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(IAuditToken.transfer, (to, amount)));
        if (!success || (returndata.length != 0 && !abi.decode(returndata, (bool)))) revert TokenCallFailed();
    }

    function _safeTransferFrom(address from, address to, uint256 amount) private {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(IAuditToken.transferFrom, (from, to, amount)));
        if (!success || (returndata.length != 0 && !abi.decode(returndata, (bool)))) revert TokenCallFailed();
    }
}

