// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Modello didattico minimale; non sostituisce un TimelockController mantenuto.
/// @dev Governance ritardata: il proposer annuncia una chiamata, l'executor puo' eseguirla
/// solo dopo `delay` secondi. Nel frattempo chiunque puo' osservarla e reagire.
contract FinalTimelock {
    error OnlyProposer();
    error OnlyExecutor();
    error AlreadyScheduled();
    error NotReady();
    error CallFailed(bytes reason);

    struct Operation {
        uint256 readyAt; // 0 = mai programmata; altrimenti il timestamp da cui e' eseguibile
        bool done; // true dopo l'esecuzione: la stessa operazione non si ripete
    }

    uint256 public immutable delay;
    address public immutable proposer;
    address public immutable executor;
    // Mapping con nomi dei parametri (sintassi >= 0.8.18): id operazione -> stato.
    mapping(bytes32 id => Operation) public operations;

    constructor(uint256 delay_, address proposer_, address executor_) {
        delay = delay_;
        proposer = proposer_;
        executor = executor_;
    }

    // L'id e' l'hash di (target, calldata, salt): identifica in modo univoco la chiamata.
    // Il salt permette di programmare due volte la stessa chiamata con id diversi.
    // `pure`: non legge ne' scrive lo stato.
    function hashOperation(address target, bytes calldata data, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(target, data, salt));
    }

    function schedule(address target, bytes calldata data, bytes32 salt) external returns (bytes32 id) {
        if (msg.sender != proposer) revert OnlyProposer();
        id = hashOperation(target, data, salt); // return con nome: assegnare `id` basta
        if (operations[id].readyAt != 0) revert AlreadyScheduled();
        operations[id].readyAt = block.timestamp + delay;
    }

    function execute(address target, bytes calldata data, bytes32 salt) external returns (bytes memory result) {
        if (msg.sender != executor) revert OnlyExecutor();
        bytes32 id = hashOperation(target, data, salt);
        // `storage`: un riferimento allo slot, non una copia; i write modificano il mapping.
        Operation storage operation = operations[id];
        // Eseguibile solo se programmata, se il ritardo e' trascorso e se non gia' eseguita.
        if (operation.readyAt == 0 || block.timestamp < operation.readyAt || operation.done) revert NotReady();
        operation.done = true; // segnata prima della call esterna
        // Qui msg.sender per il target e' il timelock: e' lui a dover essere l'owner del target.
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) revert CallFailed(returnData);
        return returnData;
    }
}
