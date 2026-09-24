// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Perche' due fasi: con un trasferimento in un solo passo, un indirizzo sbagliato (un typo,
// un contratto che non sa chiamare nulla) riceverebbe l'ownership e nessuno potrebbe piu'
// recuperarla. Qui il candidato deve DIMOSTRARE di controllare l'indirizzo chiamando lui
// acceptOwnership; fino ad allora l'owner resta quello vecchio.
//
//   owner     --transferOwnership(candidate)--> pendingOwner = candidate  (owner invariato)
//   candidate --acceptOwnership()-------------> owner = candidate, pendingOwner = 0

/// @notice Primitive didattica minimale per osservare un trasferimento di ownership a due fasi.
/// @dev Per produzione usare una libreria mantenuta e pinnata, come OpenZeppelin Ownable2Step.
/// `abstract`: non si distribuisce da solo, si eredita (vedi EscrowOwnable2Step sotto).
abstract contract Ownable2StepLite {
    error ZeroOwner();
    error Unauthorized(address caller);
    error NotPendingOwner(address caller);

    address public owner;
    address public pendingOwner; // candidato proposto; address(0) = nessuna proposta in corso

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroOwner();
        owner = initialOwner;
        // Convenzione: la nascita dell'ownership si registra come trasferimento da address(0).
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    // FASE 1: l'owner propone. Nessun privilegio si sposta ancora.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroOwner();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    // FASE 2: il candidato accetta. Niente onlyOwner: il controllo e' su pendingOwner.
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);

        address previousOwner = owner; // salvato per l'evento, prima di sovrascriverlo
        owner = msg.sender;
        pendingOwner = address(0); // la proposta e' consumata: non si puo' riusare
        emit OwnershipTransferred(previousOwner, msg.sender);
    }
}

// Contratto concreto: eredita owner, pendingOwner e onlyOwner.
contract EscrowOwnable2Step is Ownable2StepLite {
    bool public paused;

    event PauseChanged(bool paused, address indexed owner);

    // Passa initialOwner al constructor del genitore. Il corpo `{ }` e' vuoto.
    constructor(address initialOwner) Ownable2StepLite(initialOwner) { }

    function setPaused(bool value) external onlyOwner {
        paused = value;
        emit PauseChanged(value, msg.sender);
    }
}
