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

/// @title SafeEscrow, versione con prelievo
/// @notice Stesso contratto di SafeEscrow con in piu' withdraw(): i crediti si ritirano davvero.
/// @dev Da confrontare con src/SafeEscrow.sol: le aggiunte sono segnate con "NOVITA'".
/// La state machine non cambia: withdraw() non e' un arco del grafo e non tocca `state`.
/// Sparisce il warning locked-ether della build.
contract SafeEscrowFixed {
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
    // NOVITA': errori di withdraw().
    error NotAParty(address caller); // chi chiama non e' ne' buyer ne' seller
    error NothingToWithdraw(); // chi chiama non ha credito da ritirare
    error TransferFailed(); // il destinatario ha rifiutato l'ETH

    // Un evento per ogni transizione riuscita: da fuori si ricostruisce la storia dell'escrow.
    event Deposited(address indexed buyer, uint256 amount);
    event Completed(address indexed seller, uint256 credit);
    event Cancelled(address indexed buyer, uint256 credit);
    // NOVITA': registra ogni prelievo riuscito.
    event Withdrawn(address indexed party, uint256 amount);

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

    /// @notice NOVITA': buyer o seller ritira tutto il proprio credito (pull payment).
    /// @dev Non e' una transizione: lo stato resta Completed o Cancelled, entrambi terminali.
    /// Un credito diverso da zero esiste solo dopo complete() o cancel(), quindi non serve
    /// una guardia di stato: prima della fine del ciclo il controllo sull'importo reverte.
    /// Credito e saldo scendono della stessa cifra: liabilities() <= balance resta vero.
    /// depositedAmount non cambia: resta il backing storico del deposito.
    function withdraw() external {
        // 1. CONTROLLI
        // chi? Solo le due parti. Il credito si sceglie da msg.sender, non da un parametro:
        // nessuno puo' ritirare il credito dell'altra parte.
        bool isSeller = msg.sender == seller;
        if (!isSeller && msg.sender != buyer) revert NotAParty(msg.sender);

        uint256 amount = isSeller ? sellerCredit : buyerCredit;
        // Zero se il ciclo non e' finito, se il credito e' dell'altra parte
        // o se e' gia' stato ritirato.
        if (amount == 0) revert NothingToWithdraw();

        // 2. EFFETTI: il credito si azzera PRIMA di mandare l'ETH.
        // Con l'ordine inverso il destinatario potrebbe rientrare in withdraw() durante
        // l'invio e ritirare di nuovo lo stesso credito (reentrancy, Lezione 5).
        if (isSeller) {
            sellerCredit = 0;
        } else {
            buyerCredit = 0;
        }

        emit Withdrawn(msg.sender, amount);

        // 3. INTERAZIONE: l'invio dell'ETH e' l'ultima cosa.
        // .call non fallisce da sola: restituisce true/false e il risultato va controllato.
        (bool ok,) = msg.sender.call{ value: amount }("");
        // Se l'invio fallisce, il revert annulla anche l'azzeramento: il credito resta intatto.
        if (!ok) revert TransferFailed();
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
