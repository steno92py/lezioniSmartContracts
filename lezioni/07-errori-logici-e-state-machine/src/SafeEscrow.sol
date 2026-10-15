// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Versione corretta di LogicBugEscrow. Matrice delle transizioni ammesse:
//
//   stato     azione    caller   nuovo stato
//   Created   deposit   buyer    Funded
//   Funded    complete  seller   Completed   (terminale)
//   Funded    cancel    buyer    Cancelled   (terminale)
//   ogni altra combinazione -> revert
//
// Ogni funzione di ciclo segue lo stesso schema:
//   1. chi?     msg.sender e' la parte giusta
//   2. quando?  lo stato corrente e' quello richiesto
//   3. effetto  credito assegnato UNA volta + nuovo stato, nella stessa call
//   4. evento

/// @title SafeEscrow
/// @notice State machine didattica: registra crediti e omette i payout per isolare la logica.
contract SafeEscrow {
    enum State {
        Created,
        Funded,
        Completed,
        Cancelled
    }

    // Rispetto alla versione vulnerabile gli errori trasportano dati: chi ha chiamato,
    // stato atteso e stato reale. Nei test si puo' verificare il motivo esatto del revert.
    error OnlyBuyer(address caller);
    error OnlySeller(address caller);
    error WrongState(State expected, State actual);
    error WrongAmount();
    error ZeroAddress();
    error SameParty();

    // Un evento per ogni transizione riuscita: da fuori si ricostruisce la storia dell'escrow.
    event Deposited(address indexed buyer, uint256 amount);
    event Completed(address indexed seller, uint256 credit);
    event Cancelled(address indexed buyer, uint256 credit);

    address public immutable buyer;
    address public immutable seller;

    State public state;
    uint256 public depositedAmount; // backing: i wei entrati col deposito
    uint256 public sellerCredit; // obbligazione verso il seller
    uint256 public buyerCredit; // obbligazione verso il buyer

    constructor(address buyer_, address seller_) {
        // Le parti sono immutable: un errore qui non si puo' piu' correggere dopo il deploy.
        if (buyer_ == address(0) || seller_ == address(0)) revert ZeroAddress();
        // Con buyer == seller la stessa persona potrebbe sia completare sia annullare:
        // i due ruoli devono essere distinti perche' l'escrow abbia senso.
        if (buyer_ == seller_) revert SameParty();

        buyer = buyer_;
        seller = seller_;
        state = State.Created;
    }

    // Arco Created -> Funded.
    function deposit() external payable {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Created); // impedisce un secondo deposito
        if (msg.value == 0) revert WrongAmount();

        depositedAmount = msg.value;
        state = State.Funded;

        emit Deposited(msg.sender, msg.value);
    }

    // Arco Funded -> Completed. La correzione del bug di LogicBugEscrow e' qui.
    function complete() external {
        if (msg.sender != seller) revert OnlySeller(msg.sender);
        _requireState(State.Funded); // niente complete prima del deposito o dopo la fine

        // `=` e non `+=`: il credito si assegna, non si accumula.
        sellerCredit = depositedAmount;
        // Uscita da Funded nella stessa call: una seconda complete() trova Completed
        // e reverte. Anche cancel() ora reverte: Completed e' terminale.
        state = State.Completed;

        emit Completed(msg.sender, depositedAmount);
    }

    // Arco Funded -> Cancelled, simmetrico a complete().
    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        _requireState(State.Funded);

        buyerCredit = depositedAmount;
        state = State.Cancelled; // terminale: nessuna funzione accetta Cancelled

        emit Cancelled(msg.sender, depositedAmount);
    }

    /// @notice Obbligazioni contabili correnti del contratto.
    /// @dev Invariante: liabilities() <= depositedAmount e <= address(this).balance.
    /// Se il contratto deve piu' di quanto possiede, il credito non e' coperto.
    function liabilities() external view returns (uint256) {
        return sellerCredit + buyerCredit;
    }

    // Guardia di stato in un unico punto: tutte le funzioni di ciclo la riusano.
    // `internal`: chiamabile solo da questo contratto (e da chi lo eredita), non da fuori.
    function _requireState(State expected) internal view {
        if (state != expected) revert WrongState(expected, state);
    }
}
