// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Macchina a stati dell'Escrow. Ogni funzione deve superare DUE controlli indipendenti:
//   CHI?    autorizzazione del caller  -> modifier onlyBuyer (NOVITA': anche onlySeller)
//   QUANDO? guardia sullo stato        -> modifier onlyState
//
//                      buyer: fund()
//      Created ----------------------------> Funded
//         |                                    |
//         | buyer: cancelBeforeFunding()       | buyer: approveRelease()
//         v                                    v
//     Cancelled                          ReleaseApproved
//     (terminale)                              |
//                                              | NOVITA' seller: release() + payout
//                                              v
//                                          Released
//                                         (terminale)
//
// Ogni freccia NON disegnata e' vietata: deve finire in un revert.
//
// NOVITA': ReleaseApproved non e' piu' terminale. Il seller incassa con release() e la
// macchina arriva in Released. Il ramo Cancelled non ha bisogno di rimborsi: ci si arriva
// solo da Created, quando nel contratto non c'e' ancora ETH.

/// @title EscrowStateMachineFixed
/// @notice Contratto didattico locale. Non e' production-ready.
/// @dev Da confrontare con src/EscrowStateMachine.sol: le aggiunte sono segnate con "NOVITA'".
/// Stesso contratto con in piu' release(): l'ETH depositata esce verso il seller, quindi
/// sparisce il warning locked-ether della build. La Lezione 4 (EscrowWithPayout) sviluppa il
/// payout per intero: trust boundary, receive(), fallback() e seller ostili.
contract EscrowStateMachineFixed {
    // `enum`: un tipo con un insieme chiuso di valori con nome. Nello storage e' un numero
    // (Created = 0, Funded = 1, ...); il valore di default e' il primo, Created.
    enum State {
        Created,
        Funded,
        ReleaseApproved,
        Cancelled,
        // NOVITA': stato terminale dopo il payout. Aggiunto in fondo, cosi' i valori numerici
        // degli stati esistenti restano identici a quelli del contratto originale.
        Released
    }

    // Errori del constructor: configurazioni che renderebbero l'Escrow inutilizzabile.
    error ZeroSeller();
    error BuyerEqualsSeller();
    error ZeroPrice();
    // Errori delle transizioni: ognuno dice chi, quale stato o quale importo era sbagliato.
    error Unauthorized(address caller);
    error WrongState(State expected, State actual);
    error WrongValue(uint256 expected, uint256 actual);
    // NOVITA': il seller ha rifiutato l'ETH (stesso nome e argomenti della Lezione 4).
    error EtherTransferFailed(address recipient, uint256 amount);

    // Un evento per ogni transizione riuscita: chi osserva da fuori ricostruisce la storia.
    event Funded(address indexed buyer, uint256 amount);
    event ReleaseApproved(address indexed buyer);
    event Cancelled(address indexed buyer);
    // NOVITA': registra il payout riuscito (stessa firma della Lezione 4).
    event Released(address indexed buyer, address indexed seller, uint256 amount);

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

    // NOVITA': CHI, lato seller. Solo il seller puo' incassare.
    modifier onlySeller() {
        if (msg.sender != seller) revert Unauthorized(msg.sender);
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
    /// NOVITA': qui il payout lo esegue poi release(), chiamata dal seller.
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

    /// @notice NOVITA': il seller incassa il prezzo dopo l'approvazione del buyer.
    /// @dev Transizione: ReleaseApproved -> Released. Ordine: controlli -> effetti -> evento
    /// -> invio dell'ETH. Il buyer ha gia' dato il consenso con approveRelease(): qui e' il
    /// seller a ritirare (pull), come withdraw() nella Lezione 1. Nella Lezione 4 invece
    /// release() la chiama il buyer e fonde approvazione e pagamento in un solo passo.
    function release() external onlySeller onlyState(State.ReleaseApproved) {
        // 1. CONTROLLI: i modifier (seller + stato ReleaseApproved), prima di ogni scrittura.

        // 2. EFFETTI: la transizione si consuma PRIMA di mandare l'ETH.
        // Mentre il seller esegue il suo codice, l'Escrow risulta gia' Released: se provasse a
        // rientrare in release() troverebbe lo stato sbagliato (reentrancy, Lezione 5).
        state = State.Released;
        emit Released(buyer, seller, price);

        // 3. INTERAZIONE: l'invio dell'ETH e' l'ultima cosa.
        // Si paga `price`, l'importo dovuto, non address(this).balance.
        // .call non fallisce da sola: restituisce true/false e il risultato va controllato.
        (bool ok,) = seller.call{ value: price }("");
        // Se l'invio fallisce, il revert annulla anche `state = Released` e l'evento:
        // l'Escrow torna ReleaseApproved con i fondi ancora dentro.
        if (!ok) revert EtherTransferFailed(seller, price);
    }
}
