// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Il timelock risponde a "quanto tempo deve passare" tra la decisione e l'effetto.
// Il delay e' la finestra in cui utenti e canceller vedono l'operazione e possono reagire.
//
//   proposer --schedule--> [Waiting ... minimumDelay ...] --> Ready --execute--> Done
//                                     |                          |
//                                     +---- canceller: cancel ---+--> Cancelled
//
// Ruoli separati: chi propone (proposer) non e' per forza chi esegue (executor) ne' chi
// puo' annullare (canceller). L'admin assegna i ruoli.

/// @notice Timelock minimale con proposer, executor, canceller e admin separati.
/// @dev Modello didattico; non sostituisce OpenZeppelin TimelockController.
contract ToyTimelock {
    // `enum`: tipo con un insieme chiuso di valori, internamente 0, 1, 2...
    enum Role {
        Proposer,
        Executor,
        Canceller
    }

    // Lo stato NON e' salvato: getOperationState lo ricava da readyAt, done, cancelled
    // e dall'orario corrente. Unset (0) e' il default di un'operazione mai vista.
    enum OperationState {
        Unset,
        Waiting,
        Ready,
        Done,
        Cancelled
    }

    error ZeroAddress();
    error InvalidDelay();
    error Unauthorized(address caller, Role requiredRole);
    error OnlyAdmin(address caller);
    error OperationAlreadyScheduled(bytes32 id);
    error OperationNotPending(bytes32 id);
    error OperationNotReady(bytes32 id, uint256 readyAt, uint256 currentTimestamp);
    error MissingPredecessor(bytes32 predecessor);
    error UnderlyingCallFailed(bytes reason);

    event RoleUpdated(Role indexed role, address indexed account, bool enabled);
    event OperationScheduled(bytes32 indexed id, address indexed target, uint256 readyAt);
    event OperationCancelled(bytes32 indexed id);
    event OperationExecuted(bytes32 indexed id, address indexed target);

    struct Operation {
        uint256 readyAt; // timestamp da cui l'operazione e' eseguibile; 0 = mai schedulata
        bool done;
        bool cancelled;
    }

    address public immutable admin;
    uint256 public immutable minimumDelay; // in secondi

    // hasRole[ruolo][account]. Per l'executor, account = address(0) significa "chiunque".
    mapping(Role role => mapping(address account => bool enabled)) public hasRole;
    mapping(bytes32 id => Operation operation) private _operations;

    constructor(
        uint256 minimumDelay_,
        address proposer,
        address executor,
        address canceller,
        address admin_
    ) {
        // Un delay zero toglierebbe al timelock l'unica cosa che lo distingue.
        if (minimumDelay_ == 0) revert InvalidDelay();
        // L'executor NON e' nella lista: executor = address(0) e' una scelta valida
        // (esecuzione aperta a tutti, vedi _requireExecutor).
        if (proposer == address(0) || canceller == address(0) || admin_ == address(0)) {
            revert ZeroAddress();
        }

        minimumDelay = minimumDelay_;
        admin = admin_;
        hasRole[Role.Proposer][proposer] = true;
        hasRole[Role.Executor][executor] = true;
        hasRole[Role.Canceller][canceller] = true;
    }

    // setRole ha effetto immediato, senza passare dal delay.
    function setRole(Role role, address account, bool enabled) external {
        if (msg.sender != admin) revert OnlyAdmin(msg.sender);
        // Stessa regola del constructor: address(0) ha senso solo come executor aperto.
        if (account == address(0) && role != Role.Executor) revert ZeroAddress();

        hasRole[role][account] = enabled;
        emit RoleUpdated(role, account, enabled);
    }

    /// @dev L'id di un'operazione e' l'hash di TUTTO cio' che eseguira'. Chi esegue deve
    /// ripresentare esattamente gli stessi parametri: cambiare anche un byte di `data`
    /// produce un altro id, che non e' mai stato schedulato.
    /// `salt` distingue due operazioni altrimenti identiche; `predecessor` e' l'id di
    /// un'operazione che deve essere Done prima (bytes32(0) = nessuna dipendenza).
    /// `pure`: non legge lo stato, calcola solo l'hash.
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external returns (bytes32 id) {
        _requireRole(Role.Proposer);
        // Il proposer puo' scegliere un delay piu' lungo, mai piu' corto del minimo.
        if (delay < minimumDelay) revert InvalidDelay();

        id = hashOperation(target, value, data, predecessor, salt);
        Operation storage operation = _operations[id];
        OperationState current = getOperationState(id);
        // Si puo' schedulare solo un'operazione nuova o una gia' cancellata. Senza questo
        // controllo si potrebbe spostare il readyAt di una in attesa, o azzerare `done` di
        // una gia' eseguita e rieseguirla.
        if (current != OperationState.Unset && current != OperationState.Cancelled) {
            revert OperationAlreadyScheduled(id);
        }

        // Il conto alla rovescia parte dal blocco in cui viene schedulata.
        operation.readyAt = block.timestamp + delay;
        operation.done = false;
        operation.cancelled = false; // una rischedulazione riparte pulita
        emit OperationScheduled(id, target, operation.readyAt);
    }

    function cancel(bytes32 id) external {
        _requireRole(Role.Canceller);
        OperationState current = getOperationState(id);
        // Si annulla solo cio' che e' ancora in sospeso: non un'operazione mai schedulata,
        // gia' eseguita o gia' annullata.
        if (current != OperationState.Waiting && current != OperationState.Ready) {
            revert OperationNotPending(id);
        }

        _operations[id].cancelled = true;
        emit OperationCancelled(id);
    }

    /// @dev `payable`: chi esegue puo' allegare l'ETH che la call inoltrera' al target.
    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external payable returns (bytes memory returnData) {
        // CHECKS: chiamante, stato dell'operazione, dipendenza.
        _requireExecutor();
        // L'id si ricalcola dai parametri: si esegue solo cio' che e' stato schedulato.
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        Operation storage operation = _operations[id];
        // Ready esclude in un colpo solo: mai schedulata, ancora in attesa, annullata, fatta.
        if (getOperationState(id) != OperationState.Ready) {
            revert OperationNotReady(id, operation.readyAt, block.timestamp);
        }
        if (predecessor != bytes32(0) && getOperationState(predecessor) != OperationState.Done) {
            revert MissingPredecessor(predecessor);
        }

        // EFFECTS prima della call: l'operazione non puo' essere rieseguita dal target.
        operation.done = true;
        // INTERACTION: il timelock chiama il target. Per il target msg.sender e' il
        // TIMELOCK, ed e' per questo che il timelock deve essere l'owner del target.
        (bool success, bytes memory result) = target.call{ value: value }(data);
        // Se il target fallisce, il revert annulla anche `done = true`: l'operazione torna
        // Ready e resta visibile per una nuova revisione.
        if (!success) revert UnderlyingCallFailed(result);

        emit OperationExecuted(id, target);
        return result;
    }

    function getOperationState(bytes32 id) public view returns (OperationState) {
        Operation storage operation = _operations[id];
        // L'ordine dei controlli conta: done e cancelled prevalgono sul tempo.
        if (operation.done) return OperationState.Done;
        if (operation.cancelled) return OperationState.Cancelled;
        if (operation.readyAt == 0) return OperationState.Unset;
        // CONFINE: `<` significa che a block.timestamp == readyAt l'operazione e' gia' Ready.
        if (block.timestamp < operation.readyAt) return OperationState.Waiting;
        return OperationState.Ready;
    }

    function readyAt(bytes32 id) external view returns (uint256) {
        return _operations[id].readyAt;
    }

    function _requireRole(Role role) private view {
        if (!hasRole[role][msg.sender]) revert Unauthorized(msg.sender, role);
    }

    // Executor aperto: se address(0) ha il ruolo, chiunque puo' eseguire un'operazione
    // Ready. Non aggira il delay (execute controlla comunque lo stato), ma evita che
    // l'operazione resti bloccata se l'executor designato sparisce: e' un guadagno di liveness.
    function _requireExecutor() private view {
        if (!hasRole[Role.Executor][msg.sender] && !hasRole[Role.Executor][address(0)]) {
            revert Unauthorized(msg.sender, Role.Executor);
        }
    }

    receive() external payable { }
}
