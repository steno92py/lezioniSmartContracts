// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Laboratorio su msg.sender e tx.origin. In ogni call di una transazione:
//   msg.sender = chi ha fatto QUESTA call (il chiamante diretto, cambia a ogni passaggio);
//   tx.origin  = l'account esterno (EOA) che ha avviato TUTTA la transazione (non cambia mai).
//
//   OWNER (EOA) --call--> ForwarderToy --call--> target.setValue
//                         msg.sender = OWNER     msg.sender = ForwarderToy
//                         tx.origin  = OWNER     tx.origin  = OWNER

// Interfaccia comune: il forwarder puo' chiamare sia la versione vulnerabile sia quella corretta.
interface ISetter {
    function setValue(uint256 newValue) external;
}

/// @notice Esempio volutamente vulnerabile. Non usare questo modello in produzione.
contract OriginAuthToy is ISetter {
    error NotOwner();
    error ZeroOwner();

    // `immutable`: fissato una volta nel constructor, poi scritto nel bytecode.
    address public immutable owner;
    uint256 public value;

    // Il constructor gira una sola volta, al deploy.
    constructor(address owner_) {
        // Un owner zero renderebbe setValue inutilizzabile per sempre.
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setValue(uint256 newValue) external {
        // Vulnerabilita': autorizza l'origine, non il chiamante diretto.
        // Se l'owner interagisce con un qualunque contratto malevolo, quel contratto puo'
        // chiamare setValue: tx.origin e' ancora l'owner e il controllo passa.
        if (tx.origin != owner) revert NotOwner();
        value = newValue;
    }
}

/// @notice Versione corretta per il requisito "solo l'owner chiama direttamente".
contract SenderAuthToy is ISetter {
    error NotOwner();
    error ZeroOwner();

    address public immutable owner;
    uint256 public value;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
    }

    function setValue(uint256 newValue) external {
        // Controlla il chiamante DIRETTO: un intermediario non puo' prendere in prestito
        // l'identita' dell'owner, perche' quando chiama lui msg.sender e' l'intermediario.
        if (msg.sender != owner) revert NotOwner();
        value = newValue;
    }
}

/// @notice Intermediario che rende visibile la differenza tra msg.sender e tx.origin.
/// @dev Qui e' innocuo; nella realta' potrebbe essere un contratto di phishing.
contract ForwarderToy {
    event Forwarding(address indexed directCaller, address indexed target, uint256 newValue);

    function forward(ISetter target, uint256 newValue) external {
        emit Forwarding(msg.sender, address(target), newValue);
        // Qui nasce una nuova call: dentro target, msg.sender diventa questo contratto.
        target.setValue(newValue);
    }
}
