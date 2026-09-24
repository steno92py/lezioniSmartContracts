// SPDX-License-Identifier: MIT
// Versione esatta del compilatore: tutti compilano lo stesso bytecode.
// Dalla 0.8 in poi un overflow aritmetico provoca un revert automatico.
pragma solidity 0.8.37;

/// @title Registro didattico di depositi, versione con prelievo
/// @notice Stesso contratto di EscrowLesson1 con in piu' withdraw(): l'ETH non resta bloccato.
/// @dev Da confrontare con src/EscrowLesson1.sol: le aggiunte sono segnate con "NOVITA'".
/// Sparisce il warning locked-ether della build.
contract EscrowLesson1Fixed {
    // `constant`: il valore e' scritto nel bytecode, non occupa storage e non cambia mai.
    uint256 public constant MAX_NOTE_BYTES = 256;

    // Custom error: costano meno di require("messaggio") e possono trasportare dati.
    // NoteTooLong riporta la lunghezza ricevuta, utile nel debug e nei test.
    error ZeroBeneficiary();
    error ZeroValue();
    error NoteTooLong(uint256 actualLength);
    error UnknownDeposit(uint256 id);
    // NOVITA': errori di withdraw().
    error NothingToWithdraw(); // chi chiama non ha credito da ritirare
    error TransferFailed(); // il destinatario ha rifiutato l'ETH

    // Un deposito registrato. Della nota si conserva solo l'hash: 32 byte fissi,
    // qualunque sia la lunghezza della nota originale.
    struct Deposit {
        address payer; // chi ha pagato: sara' sempre msg.sender
        address beneficiary; // a favore di chi e' registrato il deposito
        uint256 amount; // quanti wei: sara' sempre msg.value
        bytes32 noteHash; // keccak256 della nota
    }

    // Variabili di stato: vivono nello storage, cioe' sulla blockchain, e persistono
    // tra una transazione e l'altra. `public` genera un getter automatico: nextId().
    uint256 public nextId; // prossimo ID libero; coincide col numero di depositi creati
    uint256 public totalRecorded; // somma di tutti i wei registrati

    // `private` impedisce ad ALTRI CONTRATTI di leggerlo via codice, ma NON lo rende segreto:
    // chiunque puo' leggere lo storage di un contratto direttamente dalla blockchain.
    mapping(uint256 id => Deposit deposit) private _deposits;
    // Getter automatico: credited(indirizzo) restituisce il totale accreditato.
    mapping(address beneficiary => uint256 amount) public credited;

    // Evento: un log per chi osserva da fuori (frontend, indexer). I contratti non lo leggono.
    // I campi `indexed` (massimo 3) si possono filtrare, per esempio "tutti i depositi per BOB".
    event DepositRecorded(
        uint256 indexed id,
        address indexed payer,
        address indexed beneficiary,
        uint256 amount,
        bytes32 noteHash
    );

    // NOVITA': registra ogni prelievo riuscito.
    event Withdrawn(address indexed beneficiary, uint256 amount);

    /// @notice Registra un deposito e accredita contabilmente il beneficiario.
    /// @param beneficiary Indirizzo a favore del quale viene registrato il deposito.
    /// @param note Nota arbitraria di massimo 256 byte; viene salvato soltanto il suo hash.
    /// @return id Identificativo progressivo del deposito appena creato.
    /// @dev `external`: chiamabile solo dall'esterno del contratto.
    /// `payable`: accetta ETH; senza questa parola una call con value > 0 reverte.
    /// `bytes calldata`: la nota resta nell'input della call, in sola lettura e senza copie.
    function record(address beneficiary, bytes calldata note)
        external
        payable
        returns (uint256 id)
    {
        // 1. CONTROLLI, tutti prima di modificare lo stato.
        // Il chiamante sceglie ogni input: il contratto deve rifiutare quelli senza senso.
        // address(0) e' il valore di default di un indirizzo: quasi sempre indica un errore.
        if (beneficiary == address(0)) revert ZeroBeneficiary();
        // Un deposito da 0 wei creerebbe record vuoti nella contabilita'.
        if (msg.value == 0) revert ZeroValue();
        // La lunghezza della nota la decide chi chiama: il contratto le mette un limite.
        if (note.length > MAX_NOTE_BYTES) revert NoteTooLong(note.length);

        // 2. EFFETTI: scritture nello storage.
        // Si legge l'ID corrente e lo si consuma: ogni deposito riceve un ID unico.
        id = nextId;
        nextId = id + 1;

        // L'hash NON nasconde la nota: il testo originale resta visibile nella calldata
        // della transazione, che e' pubblica.
        bytes32 noteHash = keccak256(note);

        // payer e amount NON sono parametri: li fissa il contratto leggendo msg.sender
        // e msg.value. Nessuno puo' registrare un pagamento a nome di un altro o dichiarare
        // un importo diverso da quello che ha inviato davvero.
        _deposits[id] = Deposit({
            payer: msg.sender, beneficiary: beneficiary, amount: msg.value, noteHash: noteHash
        });

        credited[beneficiary] += msg.value; // contabilita' per beneficiario
        totalRecorded += msg.value; // contabilita' globale

        // 3. LOG: se piu' avanti la call dovesse revertire, anche l'evento verrebbe annullato.
        emit DepositRecorded(id, msg.sender, beneficiary, msg.value, noteHash);
    }

    /// @notice Restituisce un deposito gia' registrato.
    /// @dev `view`: legge lo stato senza modificarlo.
    function getDeposit(uint256 id) external view returns (Deposit memory deposit_) {
        // Un mapping non sa se una chiave "esiste": per un ID mai scritto restituisce una
        // struct piena di zeri. Senza questo controllo getDeposit(999) restituirebbe un
        // deposito fantasma invece di fallire.
        if (id >= nextId) revert UnknownDeposit(id);
        // Copia dallo storage in memory, l'area temporanea della call, per restituirlo.
        deposit_ = _deposits[id];
    }

    /// @notice NOVITA': il beneficiario ritira tutto il credito accumulato.
    /// @dev totalRecorded non cambia: resta il totale storico dei depositi registrati.
    function withdraw() external {
        // 1. CONTROLLI
        // Si ritira solo il PROPRIO credito: la chiave e' msg.sender, non un parametro.
        uint256 amount = credited[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        // 2. EFFETTI: il credito si azzera PRIMA di mandare l'ETH.
        // Con l'ordine inverso il destinatario potrebbe rientrare in withdraw() durante
        // l'invio e ritirare di nuovo lo stesso credito (reentrancy, Lezione 5).
        credited[msg.sender] = 0;

        emit Withdrawn(msg.sender, amount);

        // 3. INTERAZIONE: l'invio dell'ETH e' l'ultima cosa.
        // .call non fallisce da sola: restituisce true/false e il risultato va controllato.
        (bool ok,) = msg.sender.call{ value: amount }("");
        // Se l'invio fallisce, il revert annulla anche l'azzeramento: il credito resta intatto.
        if (!ok) revert TransferFailed();
    }
}
