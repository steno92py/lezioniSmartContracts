// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Macchina a stati dell'Escrow. Ogni funzione deve superare DUE controlli indipendenti:
//   CHI?    autorizzazione del caller  -> modifier onlyBuyer
//   QUANDO? guardia sullo stato        -> modifier onlyState
//
//                      buyer: fund()
//      Created ----------------------------> Funded
//         |                                    |
//         | buyer: cancelBeforeFunding()       | buyer: approveRelease()
//         v                                    v
//     Cancelled                          ReleaseApproved
//     (terminale)                        (terminale)
//
// Ogni freccia NON disegnata e' vietata: deve finire in un revert.

/// @title EscrowStateMachine
/// @notice Contratto didattico locale. Non e' production-ready.
/// @dev Riceve ETH, ma in questa lezione non effettua ancora alcun payout.
contract EscrowStateMachine {
    // `enum`: un tipo con un insieme chiuso di valori con nome. Nello storage e' un numero
    // (Created = 0, Funded = 1, ...); il valore di default e' il primo, Created.
    enum State {
        Created,
        Funded,
        ReleaseApproved,
        Cancelled
    }

    // Errori del constructor: configurazioni che renderebbero l'Escrow inutilizzabile.
    error ZeroSeller();
    error BuyerEqualsSeller();
    error ZeroPrice();
    // Errori delle transizioni: ognuno dice chi, quale stato o quale importo era sbagliato.
    error Unauthorized(address caller);
    error WrongState(State expected, State actual);
    error WrongValue(uint256 expected, uint256 actual);

    // Un evento per ogni transizione riuscita: chi osserva da fuori ricostruisce la storia.
    event Funded(address indexed buyer, uint256 amount);
    event ReleaseApproved(address indexed buyer);
    event Cancelled(address indexed buyer);

    // `immutable`: fissati una volta nel constructor e poi scritti nel bytecode.
    // Nessuna funzione puo' cambiare buyer, seller o prezzo dopo il deploy.
    address public immutable buyer;
    address public immutable seller;
    uint256 public immutable price;

    // L'unica variabile che cambia: lo stato corrente della macchina.
    State public state;

    // Il constructor gira una sola volta, al deploy. Chi fa il deploy (msg.sender)
    // diventa il buyer.
    constructor(address seller_, uint256 price_) {
        if (seller_ == address(0)) revert ZeroSeller(); // nessuno potrebbe mai ricevere
        if (seller_ == msg.sender) revert BuyerEqualsSeller(); // ruoli distinti
        if (price_ == 0) revert ZeroPrice(); // un escrow da 0 wei non protegge nulla

        buyer = msg.sender;
        seller = seller_;
        price = price_;
        // Gia' vero per default, ma scriverlo rende esplicito lo stato iniziale.
        state = State.Created;
    }

    // `modifier`: un controllo riusabile. Il corpo della funzione viene eseguito al posto
    // di `_;`, quindi solo DOPO che il controllo e' passato.
    // CHI: solo il buyer puo' chiamare le funzioni che lo usano.
    modifier onlyBuyer() {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        _;
    }

    // QUANDO: la funzione si puo' chiamare solo se la macchina e' nello stato `expected`.
    // L'errore riporta lo stato richiesto e quello trovato, utile nel debug.
    modifier onlyState(State expected) {
        if (state != expected) revert WrongState(expected, state);
        _;
    }

    /// @notice Deposita esattamente il prezzo concordato.
    /// @dev I modifier girano da sinistra a destra: prima onlyBuyer, poi onlyState, poi il corpo.
    /// Transizione: Created -> Funded.
    function fund() external payable onlyBuyer onlyState(State.Created) {
        // Importo esatto: ne' meno ne' piu' del prezzo.
        if (msg.value != price) revert WrongValue(price, msg.value);

        state = State.Funded;
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Il buyer autorizza il futuro payout al seller.
    /// @dev In questa lezione il payout non viene ancora eseguito.
    /// La guardia onlyState(Funded) garantisce che l'approvazione arrivi solo DOPO un funding:
    /// ReleaseApproved implica che l'ETH e' stata depositata.
    function approveRelease() external onlyBuyer onlyState(State.Funded) {
        state = State.ReleaseApproved;
        emit ReleaseApproved(msg.sender);
    }

    /// @notice Cancella l'Escrow soltanto prima del funding.
    /// @dev Transizione: Created -> Cancelled. Dopo il funding non si puo' piu' cancellare.
    function cancelBeforeFunding() external onlyBuyer onlyState(State.Created) {
        state = State.Cancelled;
        emit Cancelled(msg.sender);
    }
}
