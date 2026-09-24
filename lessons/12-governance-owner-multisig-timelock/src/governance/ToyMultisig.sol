// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Ciclo di vita di una transazione del multisig (m-of-n: servono m approvazioni su n owner):
//
//   submit(target, value, data) --> approve x m --> execute --> target.call{value}(data)
//   (un owner propone)              (owner diversi)  (un owner qualsiasi)
//
// Il multisig risponde a "chi e quante persone devono approvare", non a "quanto aspettare":
// per il tempo serve il timelock.

/// @notice Multisig m-of-n minimale per testare proposta, approvazione ed esecuzione.
/// @dev Non sostituisce Safe o un wallet sottoposto ad audit.
contract ToyMultisig {
    error InvalidThreshold(uint256 threshold, uint256 ownersCount);
    error ZeroOwner();
    error DuplicateOwner(address owner);
    error NotOwner(address caller);
    error InvalidTarget(address target);
    error UnknownTransaction(uint256 id);
    error AlreadyApproved(uint256 id, address owner);
    error ThresholdNotReached(uint256 approvals, uint256 threshold);
    error AlreadyExecuted(uint256 id);
    error CallFailed(bytes reason);

    event Submitted(uint256 indexed id, address indexed target, uint256 value, bytes data);
    event Approved(uint256 indexed id, address indexed owner, uint256 approvals);
    event Executed(uint256 indexed id);

    struct Transaction {
        address target; // contratto da chiamare
        uint256 value; // wei da inviare con la call
        bytes data; // calldata: selector + argomenti codificati
        uint256 approvals; // quanti owner hanno approvato finora
        bool executed;
        bool exists; // distingue "id mai creato" da una struct piena di zeri
    }

    // Array dinamico in storage: serve solo a elencare gli owner (owners()).
    address[] private _owners;
    // Per i controlli si usa il mapping: una lettura costante, senza cicli sull'array.
    mapping(address owner => bool) public isOwner;
    mapping(uint256 id => Transaction transaction) private _transactions;
    // Mapping annidato: approvedBy[id][owner] = quell'owner ha gia' approvato quella tx?
    mapping(uint256 id => mapping(address owner => bool approved)) public approvedBy;

    uint256 public immutable threshold; // m: approvazioni necessarie
    uint256 public nextId;

    /// @dev `address[] memory`: l'array arriva come copia temporanea, valida solo durante
    /// il constructor; viene poi copiato elemento per elemento nello storage.
    constructor(address[] memory owners_, uint256 threshold_) {
        // threshold 0 = nessuna approvazione richiesta; threshold > n = nessuna tx eseguibile
        // (liveness persa per sempre). Entrambi si rifiutano al deploy.
        if (threshold_ == 0 || threshold_ > owners_.length) {
            revert InvalidThreshold(threshold_, owners_.length);
        }

        for (uint256 i; i < owners_.length; ++i) {
            address owner = owners_[i];
            if (owner == address(0)) revert ZeroOwner();
            // Un owner ripetuto gonfierebbe n: [A, A, B] sembrerebbe un x-of-3, ma le
            // persone sono due. La configurazione dichiarata deve essere quella reale.
            if (isOwner[owner]) revert DuplicateOwner(owner);
            isOwner[owner] = true;
            _owners.push(owner);
        }

        threshold = threshold_;
    }

    // `modifier`: codice riusabile che avvolge una funzione. `_;` indica dove viene
    // eseguito il corpo della funzione: qui DOPO il controllo sul chiamante.
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner(msg.sender);
        _;
    }

    function submit(address target, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (uint256 id)
    {
        // Un target senza codice accetterebbe qualunque call "con successo" senza fare nulla.
        if (target.code.length == 0) revert InvalidTarget(target);

        // `nextId++`: restituisce il valore attuale e POI lo incrementa.
        id = nextId++;
        // `storage`: pendingTx e' un puntatore allo slot nello storage, non una copia.
        // Scrivere pendingTx.target scrive direttamente _transactions[id].target.
        Transaction storage pendingTx = _transactions[id];
        pendingTx.target = target;
        pendingTx.value = value;
        pendingTx.data = data;
        pendingTx.exists = true;

        // Nota: submit NON approva. Anche chi propone deve chiamare approve.
        emit Submitted(id, target, value, data);
    }

    function approve(uint256 id) external onlyOwner {
        Transaction storage pendingTx = _transaction(id); // reverte se l'id non esiste
        if (pendingTx.executed) revert AlreadyExecuted(id);
        // Un owner vota una sola volta: senza questo controllo una chiave sola potrebbe
        // raggiungere la threshold chiamando approve piu' volte.
        if (approvedBy[id][msg.sender]) revert AlreadyApproved(id, msg.sender);

        approvedBy[id][msg.sender] = true;
        pendingTx.approvals += 1;
        emit Approved(id, msg.sender, pendingTx.approvals);
    }

    function execute(uint256 id) external onlyOwner returns (bytes memory returnData) {
        // CHECKS
        Transaction storage pendingTx = _transaction(id);
        if (pendingTx.executed) revert AlreadyExecuted(id);
        if (pendingTx.approvals < threshold) {
            revert ThresholdNotReached(pendingTx.approvals, threshold);
        }

        // EFFECTS prima della call: se il target provasse a richiamare execute(id) durante
        // la call, troverebbe gia' executed = true.
        pendingTx.executed = true;
        // INTERACTION: low-level call generica, con ETH (`{ value: ... }`) e calldata scelti
        // dalla proposta approvata. Il multisig puo' chiamare qualunque cosa gli owner votino.
        (bool success, bytes memory result) =
            pendingTx.target.call{ value: pendingTx.value }(pendingTx.data);
        // Se il target fallisce si reverte TUTTO, compreso `executed = true` qui sopra:
        // la transazione resta eseguibile. `result` porta l'errore originale del target.
        if (!success) revert CallFailed(result);

        emit Executed(id);
        return result;
    }

    function owners() external view returns (address[] memory) {
        return _owners;
    }

    // Getter esplicito: `_transactions` e' private e la struct contiene `bytes`, che il
    // getter automatico di `public` non restituirebbe in modo comodo.
    function transaction(uint256 id)
        external
        view
        returns (address target, uint256 value, bytes memory data, uint256 approvals, bool executed)
    {
        Transaction storage item = _transaction(id);
        return (item.target, item.value, item.data, item.approvals, item.executed);
    }

    // `private`: usabile solo in questo contratto. Centralizza il controllo di esistenza,
    // cosi' approve, execute e transaction non possono dimenticarlo.
    function _transaction(uint256 id) private view returns (Transaction storage item) {
        item = _transactions[id];
        if (!item.exists) revert UnknownTransaction(id);
    }

    // `receive`: eseguita quando il contratto riceve ETH senza calldata. Permette di
    // depositare ETH che le transazioni approvate potranno poi inviare.
    receive() external payable { }
}
