// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Versione ridotta dell'Escrow per il laboratorio. Usa require(condizione, "MESSAGGIO"):
// la forma con stringa, piu' costosa dei custom error, ma equivalente come controllo.

/// @notice Contratto deliberatamente difettoso per il solo laboratorio locale.
contract UncheckedCallEscrow {
    enum State {
        Created,
        Funded,
        Released
    }

    address public immutable buyer;
    address payable public immutable seller;
    uint256 public immutable price;

    State public state;

    event PayoutAttempted(bool success);

    constructor(address payable seller_, uint256 price_) {
        require(seller_ != address(0), "ZERO_SELLER");
        require(price_ != 0, "ZERO_PRICE");

        buyer = msg.sender;
        seller = seller_;
        price = price_;
        state = State.Created;
    }

    function fund() external payable {
        require(msg.sender == buyer, "NOT_BUYER");
        require(state == State.Created, "WRONG_STATE");
        require(msg.value == price, "WRONG_VALUE");

        state = State.Funded;
    }

    function release() external {
        require(msg.sender == buyer, "NOT_BUYER");
        require(state == State.Funded, "WRONG_STATE");

        // CEI da solo non basta: la call puo' comunque fallire.
        state = State.Released;
        (bool success,) = seller.call{ value: price }("");

        // BUG: il risultato viene registrato, ma il fallimento non viene imposto.
        // Se il seller rifiuta l'ETH, success == false ma la transazione termina con successo:
        //   state == Released  (dice "pagato")
        //   seller             non ha ricevuto nulla
        //   price              resta nel contratto, e nessuna funzione puo' piu' spostarlo
        // Un evento non e' un controllo: registra il fallimento, ma non lo impedisce.
        // (Il lint segnala anche l'evento emesso DOPO la call: qui e' atteso.)
        // Correzione: `if (!success) revert ...;` come in EscrowWithPayout.release().
        emit PayoutAttempted(success);
    }
}
