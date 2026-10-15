// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IERC20 } from "./token/IERC20.sol";
import { SafeERC20Lite } from "./token/SafeERC20Lite.sol";

// Flusso completo, con il msg.sender visto da ogni contratto:
//
//   1. buyer --approve(escrow, 100)--> token       (msg.sender = buyer; nessun token si muove)
//   2. buyer --deposit(100)--> escrow --transferFrom(buyer, escrow, 100)--> token
//                                       (nel token msg.sender = escrow, lo spender)
//   3. buyer --release()--> escrow --transfer(seller, amount)--> token
//                                       (nel token msg.sender = escrow, il proprietario)
/// @title TokenEscrow
/// @notice Escrow didattico per un singolo ERC-20 scelto al deploy.
contract TokenEscrow {
    // `using ... for`: permette di scrivere token.safeTransfer(...) invece di
    // SafeERC20Lite.safeTransfer(token, ...). Il primo argomento diventa il token.
    using SafeERC20Lite for IERC20;

    // `enum`: un tipo con un insieme chiuso di valori (0, 1, 2, 3). Il valore di default
    // e' il primo, Created. Created -> Funded -> Released oppure Refunded, senza ritorno.
    enum State {
        Created,
        Funded,
        Released,
        Refunded
    }

    // Custom error con parametri: il test puo' verificare non solo il motivo, ma anche i valori.
    error OnlyBuyer(address caller);
    error InvalidState(State expected, State actual);
    error ZeroAmount();
    error NothingReceived();
    error InvalidToken(address token);
    error ZeroAddress();
    error SameParty();

    // Deposited registra entrambe le quantita': quella chiesta e quella arrivata davvero.
    event Deposited(uint256 requestedAmount, uint256 receivedAmount);
    event Released(address indexed seller, uint256 debitedAmount);
    event Refunded(address indexed buyer, uint256 debitedAmount);

    // Configurazione fissata al deploy e non piu' modificabile.
    IERC20 public immutable token;
    address public immutable buyer;
    address public immutable seller;

    State public state;
    // Passivita' dell'Escrow: quanti token deve ancora a qualcuno. Proprieta' da mantenere:
    // state == Funded  =>  token.balanceOf(escrow) >= escrowedAmount.
    uint256 public escrowedAmount;

    constructor(IERC20 token_, address buyer_, address seller_) {
        // Un indirizzo senza codice non e' un token: ogni call "riuscirebbe" senza fare nulla.
        if (address(token_).code.length == 0) revert InvalidToken(address(token_));
        if (buyer_ == address(0) || seller_ == address(0)) revert ZeroAddress();
        // Buyer e seller coincidenti renderebbero l'escrow privo di significato.
        if (buyer_ == seller_) revert SameParty();

        token = token_;
        buyer = buyer_;
        seller = seller_;
        state = State.Created; // gia' il default: scritto per chiarezza
    }

    /// @dev Prerequisito: il buyer ha chiamato token.approve(escrow, >= requestedAmount).
    /// L'Escrow non puo' "prendere" token da solo: puo' solo spendere l'allowance ricevuta.
    function deposit(uint256 requestedAmount) external {
        // 1. CONTROLLI. Business authorization: solo il buyer. Avere token e allowance
        // non basta, lo stranger viene respinto qui (vedi test_RevertWhen_StrangerHas...).
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Created); // un solo deposito per escrow
        if (requestedAmount == 0) revert ZeroAmount();

        // 2. INTERAZIONE misurata: saldo prima, trasferimento, saldo dopo.
        // Il token puo' prendere una fee: "chiesto" e "ricevuto" non sono la stessa cosa.
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(buyer, address(this), requestedAmount);
        uint256 afterBalance = token.balanceOf(address(this));

        // Nessun aumento di saldo = nessun deposito, qualunque cosa abbia risposto il token.
        if (afterBalance <= beforeBalance) revert NothingReceived();
        uint256 receivedAmount = afterBalance - beforeBalance;

        // 3. EFFETTI: si registra cio' che e' arrivato davvero, non cio' che era stato chiesto.
        // Con requestedAmount la passivita' supererebbe il saldo reale (Escrow insolvente).
        escrowedAmount = receivedAmount;
        state = State.Funded;

        emit Deposited(requestedAmount, receivedAmount);
    }

    function release() external {
        // 1. CONTROLLI
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Funded);

        // 2. EFFETTI prima dell'interazione (CEI): la passivita' e' azzerata e lo stato e'
        // finale PRIMA di cedere il controllo al token, che e' codice esterno.
        uint256 amount = escrowedAmount; // copia locale: dopo l'azzeramento serve ancora
        escrowedAmount = 0;
        state = State.Released;

        // 3. INTERAZIONE. Se il token fallisce, safeTransfer reverte e il revert annulla
        // anche gli effetti del punto 2: lo stato torna Funded (test_FailedPayoutRollsBack...).
        token.safeTransfer(seller, amount);
        emit Released(seller, amount);
    }

    // Speculare a release: stessi controlli e stesso ordine CEI, ma i token tornano al buyer.
    function refund() external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Funded);

        uint256 amount = escrowedAmount;
        escrowedAmount = 0;
        state = State.Refunded;

        token.safeTransfer(buyer, amount);
        emit Refunded(buyer, amount);
    }

    // Guard della macchina a stati, condivisa dalle tre funzioni.
    // `internal view`: chiamabile solo da questo contratto (o da derivati), legge senza scrivere.
    function _requireState(State expected) internal view {
        if (state != expected) revert InvalidState(expected, state);
    }
}
