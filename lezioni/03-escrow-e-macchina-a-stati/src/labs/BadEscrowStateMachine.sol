// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Versione ridotta di EscrowStateMachine, con i controlli scritti dentro le funzioni
// invece che nei modifier. Confrontala con quella corretta funzione per funzione.

/// @notice Contratto volutamente vulnerabile per un laboratorio esclusivamente locale.
contract BadEscrowStateMachine {
    enum State {
        Created,
        Funded,
        ReleaseApproved,
        Cancelled
    }

    error Unauthorized(address caller);
    error WrongState();
    error WrongValue();

    address public immutable buyer;
    uint256 public immutable price;

    State public state;

    constructor(uint256 price_) {
        buyer = msg.sender;
        price = price_;
        state = State.Created;
    }

    // Qui i controlli ci sono tutti: CHI, QUANDO e QUANTO.
    function fund() external payable {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (state != State.Created) revert WrongState();
        if (msg.value != price) revert WrongValue();

        state = State.Funded;
    }

    // Qui c'e' solo il CHI. Il chiamante e' giusto, ma nessuno controlla il QUANDO.
    function approveRelease() external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);

        // BUG INTENZIONALE: manca la guardia state == State.Funded.
        // Conseguenza: il buyer passa da Created a ReleaseApproved senza aver depositato
        // nulla. Lo stato racconta una storia ("pagamento approvato") che non e' mai avvenuta.
        //   Created --approveRelease()--> ReleaseApproved   (freccia che non deve esistere)
        // Correzione: la guardia `if (state != State.Funded) revert WrongState();`,
        // come fa onlyState(State.Funded) in EscrowStateMachine.
        state = State.ReleaseApproved;
    }
}
