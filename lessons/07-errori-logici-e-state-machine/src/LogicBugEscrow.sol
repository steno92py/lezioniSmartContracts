// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Un escrow tiene fermi i soldi del buyer finche' l'affare non si conclude.
// Il ciclo di vita PREVISTO e' una state machine con due stati terminali:
//
//   Created --deposit (buyer)--> Funded --complete (seller)--> Completed
//                                   |
//                                   +--cancel (buyer)--------> Cancelled
//
// Ogni funzione deve chiedersi due cose: CHI chiama (msg.sender) e QUANDO (state).

/// @title LogicBugEscrow
/// @notice Contratto intenzionalmente vulnerabile per il laboratorio locale.
/// @dev Non usare in produzione: complete() ignora lo stato e non conclude la transizione.
contract LogicBugEscrow {
    // `enum`: un tipo con un elenco chiuso di valori. In storage e' un piccolo intero
    // (Created = 0, Funded = 1, ...) e una variabile enum ha UN solo valore alla volta.
    enum State {
        Created,
        Funded,
        Completed,
        Cancelled
    }

    error OnlyBuyer();
    error OnlySeller();
    error WrongState();
    error WrongAmount();

    // `immutable`: fissati nel constructor e poi scritti nel bytecode, non cambiano piu'.
    address public immutable buyer;
    address public immutable seller;

    State public state; // lo stato corrente della state machine
    uint256 public depositedAmount; // wei versati dal buyer: e' il "backing"
    uint256 public sellerCredit; // quanto il contratto DEVE al seller
    uint256 public buyerCredit; // quanto il contratto DEVE al buyer

    // Caso vulnerabile: nessun controllo su address(0) ne' su buyer == seller
    // (confronta con il constructor di SafeEscrow).
    constructor(address buyer_, address seller_) {
        buyer = buyer_;
        seller = seller_;
        state = State.Created; // ridondante (0 e' gia' il default), ma esplicito
    }

    // Questa funzione e' scritta bene: controlla chi, quando e quanto.
    function deposit() external payable {
        if (msg.sender != buyer) revert OnlyBuyer(); // chi?
        if (state != State.Created) revert WrongState(); // quando? un solo deposito
        if (msg.value == 0) revert WrongAmount(); // quanto?

        depositedAmount = msg.value;
        state = State.Funded; // la transizione avviene insieme all'effetto
    }

    // VULNERABILITA' (dichiarata dal commento BUG qui sotto): la funzione controlla CHI,
    // ma non QUANDO, e non porta mai il contratto in Completed. Quindi il seller puo':
    //   - chiamarla prima del deposito (in Created);
    //   - chiamarla piu' volte: ogni call somma di nuovo depositedAmount;
    //   - chiamarla dopo cancel(), quando il buyer ha gia' ricevuto il credito.
    // Non serve reentrancy: bastano transazioni normali in sequenza.
    // Correzione (vedi SafeEscrow): richiedere Funded e passare subito a Completed.
    function complete() external {
        if (msg.sender != seller) revert OnlySeller();

        // BUG: manca il requisito Funded e manca state = State.Completed.
        sellerCredit += depositedAmount; // `+=` accumula: ripetuta, gonfia il credito
    }

    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.Funded) revert WrongState(); // guardia di stato presente

        buyerCredit += depositedAmount;
        state = State.Cancelled; // Cancelled dovrebbe essere terminale...
    }
}
