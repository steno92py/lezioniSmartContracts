// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Micro-lab tx.origin. In una catena di call:
//   msg.sender = il chiamante DIRETTO di questa call (cambia a ogni passaggio);
//   tx.origin  = l'EOA che ha firmato la transazione (uguale in tutta la catena).
//
//   owner (EOA) --forwardSet--> Forwarder --setProtectedValue--> vault
//                               msg.sender = owner               msg.sender = Forwarder
//                               tx.origin  = owner               tx.origin  = owner

// Interfaccia comune: il Forwarder chiama allo stesso modo la versione vulnerabile e quella
// corretta.
interface IProtectedValueSetter {
    function setProtectedValue(uint256 value) external;
}

/// @notice Esempio volutamente vulnerabile: autorizza l'origine della transaction.
contract TxOriginVault is IProtectedValueSetter {
    error ZeroOwner();
    error Unauthorized();

    address public immutable owner;
    uint256 public protectedValue;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setProtectedValue(uint256 value) external {
        // VULNERABILE: se l'owner interagisce con un qualunque contratto (anche malevolo),
        // quel contratto puo' chiamare questa funzione: tx.origin e' ancora l'owner.
        if (tx.origin != owner) revert Unauthorized();
        protectedValue = value;
    }
}

/// @notice Versione corretta quando la policy richiede una chiamata diretta dell'owner.
contract DirectCallerVault is IProtectedValueSetter {
    error ZeroOwner();
    error Unauthorized(address caller);

    address public immutable owner;
    uint256 public protectedValue;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setProtectedValue(uint256 value) external {
        // FIX: si autentica il chiamante immediato. Un intermediario non puo' prendere in
        // prestito l'identita' dell'owner: quando chiama lui, msg.sender e' l'intermediario.
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        protectedValue = value;
    }
}

// Intermediario innocuo che rende visibile la differenza; nella realta' potrebbe essere un
// contratto di phishing che l'owner e' stato convinto a chiamare.
contract Forwarder {
    function forwardSet(IProtectedValueSetter target, uint256 value) external {
        target.setProtectedValue(value); // nuova call: dentro target, msg.sender = Forwarder
    }
}
