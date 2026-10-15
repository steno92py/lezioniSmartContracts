// SPDX-License-Identifier: MIT
// Versione esatta del compilatore: dalla 0.8 un overflow aritmetico provoca un revert automatico.
pragma solidity 0.8.37;

/// @title Registro didattico con fee fissa, versione con prelievo
/// @notice Stesso contratto di FixedFeeRegistry con in piu' una tesoreria che ritira le fee:
/// l'ETH non resta bloccato.
/// @dev Da confrontare con src/FixedFeeRegistry.sol: le aggiunte sono segnate con "NOVITA'".
/// Sparisce il warning locked-ether della build.
contract FixedFeeRegistryFixed {
    // `constant`: valore scritto nel bytecode, non occupa storage e non puo' cambiare.
    // `1 ether` e' solo un'unita' di misura: vale 10**18 wei.
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // NOVITA': chi riceve le fee. Il contratto originale non dice a chi appartengano:
    // senza un destinatario deciso in anticipo nessuno potrebbe ritirarle.
    // `immutable`: si scrive una sola volta nel constructor e poi finisce nel bytecode,
    // come una constant. Nessuna funzione puo' cambiarla: niente owner, niente setter
    // da proteggere. E' il minimo indispensabile per far uscire l'ETH.
    address public immutable treasury;

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
    // NOVITA': errori del constructor e di withdrawFees().
    error ZeroTreasury(); // tesoreria address(0): le fee andrebbero perse per sempre
    error NotTreasury(address caller); // solo la tesoreria puo' ritirare
    error NothingToWithdraw(); // il contratto non ha ETH da mandare
    error TransferFailed(); // la tesoreria ha rifiutato l'ETH

    // Evento per chi osserva da fuori; `indexed` rende l'account filtrabile.
    event Registered(address indexed account, uint256 amount);

    // NOVITA': registra ogni prelievo riuscito.
    event FeesWithdrawn(address indexed treasury, uint256 amount);

    /// @notice NOVITA': fissa la tesoreria una volta per tutte.
    /// @param treasury_ Indirizzo che potra' ritirare le fee raccolte.
    constructor(address treasury_) {
        // address(0) e' il valore di default di un indirizzo: quasi sempre indica un errore.
        // Qui l'errore sarebbe definitivo, perche' la tesoreria non si puo' piu' cambiare.
        if (treasury_ == address(0)) revert ZeroTreasury();
        treasury = treasury_;
    }

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

    /// @notice NOVITA': la tesoreria ritira tutte le fee presenti nel contratto.
    /// @dev registrationCount e totalReceived non cambiano: restano il totale storico, e la
    /// proprieta' totalReceived == registrationCount * REGISTRATION_FEE continua a valere.
    function withdrawFees() external {
        // 1. CONTROLLI
        // Solo la tesoreria decide quando ritirare. Il destinatario non e' un parametro:
        // e' sempre `treasury`, quindi nessuno puo' dirottare le fee verso di se'.
        if (msg.sender != treasury) revert NotTreasury(msg.sender);
        // Si ritira il saldo reale, non totalReceived: il saldo e' cio' che c'e' davvero,
        // anche ETH arrivato senza passare da register(), che altrimenti resterebbe bloccato.
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();

        // 2. EFFETTI: nessuna variabile da azzerare. L'importo e' il saldo stesso, e il saldo
        // scende a zero PRIMA che il codice del destinatario venga eseguito: se la tesoreria
        // rientrasse in withdrawFees() durante l'invio troverebbe 0 e reverterebbe
        // (reentrancy, Lezione 5).

        emit FeesWithdrawn(treasury, amount);

        // 3. INTERAZIONE: l'invio dell'ETH e' l'ultima cosa.
        // .call non fallisce da sola: restituisce true/false e il risultato va controllato.
        (bool ok,) = treasury.call{ value: amount }("");
        // Se l'invio fallisce, il revert annulla tutto: le fee restano nel contratto.
        if (!ok) revert TransferFailed();
    }
}
