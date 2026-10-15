// SPDX-License-Identifier: MIT
// Versione esatta del compilatore: dalla 0.8 un overflow aritmetico provoca un revert automatico.
pragma solidity 0.8.37;

/// @title Registro didattico con fee fissa
/// @notice Ogni indirizzo puo' registrarsi una volta pagando esattamente 1 ether.
/// @dev Il contratto non include prelievi: le chiamate esterne arriveranno nelle lezioni successive.
contract FixedFeeRegistry {
    // `constant`: valore scritto nel bytecode, non occupa storage e non puo' cambiare.
    // `1 ether` e' solo un'unita' di misura: vale 10**18 wei.
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Per ogni indirizzo: gia' registrato si' o no. Una chiave mai scritta vale `false`.
    // `public` genera il getter registered(indirizzo), usato dai test per leggere lo stato.
    mapping(address account => bool isRegistered) public registered;

    // Contabilita' interna. La proprieta' da rispettare sempre e':
    //   totalReceived == registrationCount * REGISTRATION_FEE
    uint256 public registrationCount;
    uint256 public totalReceived;

    // Custom error con parametri: il test puo' verificare non solo QUALE errore, ma anche
    // CON QUALI valori (quanto e' stato inviato, chi ha provato a registrarsi).
    error ExactFeeRequired(uint256 sent, uint256 required);
    error AlreadyRegistered(address account);

    // Evento per chi osserva da fuori; `indexed` rende l'account filtrabile.
    event Registered(address indexed account, uint256 amount);

    /// @dev `external`: chiamabile solo dall'esterno. `payable`: accetta ETH con la call;
    /// senza questa parola ogni call con value > 0 reverterebbe.
    /// Non ha parametri: gli unici input sono msg.sender (chi) e msg.value (quanto).
    function register() external payable {
        // 1. CONTROLLI, tutti prima di modificare lo stato.
        // Registrazione unica: lo stesso indirizzo non puo' pagare e registrarsi due volte.
        if (registered[msg.sender]) {
            revert AlreadyRegistered(msg.sender);
        }

        // Fee ESATTA: `!=` rifiuta sia meno sia piu' di 1 ether.
        // Con `<` un utente che invia 2 ether verrebbe accettato (vedi il mutation lab).
        if (msg.value != REGISTRATION_FEE) {
            revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
        }

        // 2. EFFETTI: si arriva qui solo se tutti i controlli sono passati.
        registered[msg.sender] = true;
        registrationCount += 1;
        totalReceived += msg.value;

        // 3. LOG
        emit Registered(msg.sender, msg.value);
    }
}
