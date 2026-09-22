// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title EscrowWithPayout
/// @notice Contratto didattico locale. Non e' production-ready.
/// @dev Introduce un payout ETH e una chiamata esterna verso il seller.
contract EscrowWithPayout {
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
    error EtherTransferFailed(address recipient, uint256 amount);
    error DirectEtherNotAccepted();
    error UnknownCall(bytes4 selector);

    event Funded(address indexed buyer, uint256 amount);
    event Released(address indexed buyer, address indexed seller, uint256 amount);
    event Cancelled(address indexed buyer);

    address public immutable buyer;
    address payable public immutable seller;
    uint256 public immutable price;

    State public state;

    constructor(address payable seller_, uint256 price_) {
        if (seller_ == address(0)) revert ZeroSeller();
        if (seller_ == msg.sender) revert BuyerEqualsSeller();
        if (price_ == 0) revert ZeroPrice();

        buyer = msg.sender;
        seller = seller_;
        price = price_;
        state = State.Created;
    }

    modifier onlyBuyer() {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyState(State expected) {
        if (state != expected) revert WrongState(expected, state);
        _;
    }

    /// @notice Deposita esattamente il prezzo concordato.
    function fund() external payable onlyBuyer onlyState(State.Created) {
        if (msg.value != price) revert WrongValue(price, msg.value);

        state = State.Funded;
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Conclude l'Escrow e paga il seller.
    /// @dev Checks -> Effects -> Interactions. Il fallimento della call viene imposto con revert.
    function release() external onlyBuyer onlyState(State.Funded) {
        // EFFECT: la transizione viene consumata prima di cedere il controllo.
        state = State.Released;
        emit Released(buyer, seller, price);

        // INTERACTION: il seller puo' ora eseguire codice arbitrario.
        (bool success,) = seller.call{ value: price }("");

        // Una low-level call non propaga automaticamente la failure.
        if (!success) revert EtherTransferFailed(seller, price);
    }

    /// @notice Consente al buyer di cancellare soltanto prima del funding.
    function cancelBeforeFunding() external onlyBuyer onlyState(State.Created) {
        state = State.Cancelled;
        emit Cancelled(msg.sender);
    }

    /// @notice Il funding diretto senza chiamare fund() non appartiene all'API.
    receive() external payable {
        revert DirectEtherNotAccepted();
    }

    /// @notice Selector sconosciuti non appartengono all'API.
    fallback() external payable {
        revert UnknownCall(msg.sig);
    }
}
