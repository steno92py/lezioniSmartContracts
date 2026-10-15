// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Evoluzione di EscrowStateMachine (Lezione 3): ora release() paga davvero il seller.
//
//   Created --fund(price)--> Funded --release() + payout--> Released
//      |
//      +--cancelBeforeFunding()---------------------------> Cancelled
//
// Novita' di questa lezione: il payout e' una chiamata ESTERNA. Da quel punto (la "trust
// boundary") il controllo passa a codice che l'Escrow non conosce e non controlla.

/// @title EscrowWithPayout
/// @notice Contratto didattico locale. Non e' production-ready.
/// @dev Introduce un payout ETH e una chiamata esterna verso il seller.
contract EscrowWithPayout {
    // Released sostituisce ReleaseApproved: ora la release include il pagamento.
    enum State {
        Created,
        Funded,
        Released,
        Cancelled
    }

    error ZeroSeller();
    error BuyerEqualsSeller();
    error ZeroPrice();
    error Unauthorized(address caller);
    error WrongState(State expected, State actual);
    error WrongValue(uint256 expected, uint256 actual);
    // Nuovi errori: payout fallito, ETH inviato senza passare da fund(), selettore sconosciuto.
    error EtherTransferFailed(address recipient, uint256 amount);
    error DirectEtherNotAccepted();
    error UnknownCall(bytes4 selector);

    event Funded(address indexed buyer, uint256 amount);
    event Released(address indexed buyer, address indexed seller, uint256 amount);
    event Cancelled(address indexed buyer);

    address public immutable buyer;
    // `address payable`: un indirizzo dichiarato come destinatario di ETH.
    address payable public immutable seller;
    uint256 public immutable price;

    State public state;

    constructor(address payable seller_, uint256 price_) {
        // Stessi controlli della Lezione 3: il deployer diventa il buyer.
        if (seller_ == address(0)) revert ZeroSeller();
        if (seller_ == msg.sender) revert BuyerEqualsSeller();
        if (price_ == 0) revert ZeroPrice();

        buyer = msg.sender;
        seller = seller_;
        price = price_;
        state = State.Created;
    }

    // CHI: solo il buyer.
    modifier onlyBuyer() {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        _;
    }

    // QUANDO: solo nello stato atteso.
    modifier onlyState(State expected) {
        if (state != expected) revert WrongState(expected, state);
        _;
    }

    /// @notice Deposita esattamente il prezzo concordato.
    /// @dev Unica porta prevista per far entrare ETH: `payable` e con importo controllato.
    function fund() external payable onlyBuyer onlyState(State.Created) {
        if (msg.value != price) revert WrongValue(price, msg.value);

        state = State.Funded;
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Conclude l'Escrow e paga il seller.
    /// @dev Checks -> Effects -> Interactions. Il fallimento della call viene imposto con revert.
    /// CHECKS: i modifier (buyer + stato Funded), prima di ogni scrittura.
    function release() external onlyBuyer onlyState(State.Funded) {
        // EFFECT: la transizione viene consumata prima di cedere il controllo.
        // Mentre il seller esegue il suo codice, l'Escrow risulta gia' Released, non Funded.
        // Anche l'evento sta prima della call: i log restano in ordine rispetto a quelli
        // emessi dal receiver.
        state = State.Released;
        emit Released(buyer, seller, price);

        // INTERACTION: il seller puo' ora eseguire codice arbitrario.
        // Low-level call: invia `price` wei con calldata vuota "" e quindi, se il seller e' un
        // contratto, esegue la sua receive(). Restituisce (success, dati di ritorno); i dati
        // qui non servono e vengono scartati con la virgola.
        // Si paga `price`, l'importo dovuto, non address(this).balance: il saldo grezzo puo'
        // contenere ETH arrivato per altre vie (vedi i test con ForceEther).
        // Non si usa transfer(): e' deprecato e passa solo 2300 gas, troppo pochi per un
        // destinatario che scrive storage (come AcceptingSeller nei test).
        (bool success,) = seller.call{ value: price }("");

        // Una low-level call non propaga automaticamente la failure.
        // Se il seller rifiuta, success e' false e l'esecuzione continuerebbe: questo revert
        // la ferma e annulla TUTTO, compresi `state = Released` e l'evento. L'Escrow torna
        // Funded con i fondi ancora dentro.
        if (!success) revert EtherTransferFailed(seller, price);
    }

    /// @notice Consente al buyer di cancellare soltanto prima del funding.
    function cancelBeforeFunding() external onlyBuyer onlyState(State.Created) {
        state = State.Cancelled;
        emit Cancelled(msg.sender);
    }

    // Dispatch: quale funzione esegue una call in arrivo?
    //   calldata vuota                       -> receive()
    //   selettore di una funzione esistente  -> quella funzione
    //   selettore sconosciuto                -> fallback()
    // receive() e' sempre `payable` per regola del linguaggio; fallback() lo e' per poter
    // rispondere con UnknownCall anche quando la call porta ETH. Entrambe rifiutano tutto.

    /// @notice Il funding diretto senza chiamare fund() non appartiene all'API.
    /// @dev Si attiva con calldata vuota, anche con 0 wei. Senza questo revert l'ETH entrerebbe
    /// senza controlli di chi, quando e quanto.
    receive() external payable {
        revert DirectEtherNotAccepted();
    }

    /// @notice Selector sconosciuti non appartengono all'API.
    /// @dev msg.sig sono i primi 4 byte della calldata: il selettore chiesto dal chiamante.
    fallback() external payable {
        revert UnknownCall(msg.sig);
    }
}
