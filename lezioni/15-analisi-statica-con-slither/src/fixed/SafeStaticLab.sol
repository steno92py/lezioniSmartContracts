// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// L'unica azione esterna ammessa: una firma fissa invece di "qualunque calldata".
interface IStaticAction {
    function run(bytes calldata data) external;
}

// Remediation di StaticLab, finding per finding:
//   ST-01 call ignorata      -> call tipizzata di alto livello: se reverte, reverte tutto
//   ST-02 admin di chiunque  -> onlyAdmin + trasferimento in due fasi (propose / accept)
//   ST-03 call arbitraria    -> target immutabile scelto al deploy, solo l'admin esegue
//   ST-04 oracle mai settato -> la feature incompleta e' stata rimossa
/// @notice Remediation: target tipizzato e immutabile, caller autorizzato, admin a due fasi.
contract SafeStaticLab {
    error ZeroAddress();
    error Unauthorized(address caller);
    error NotPendingAdmin(address caller);

    event AdminTransferStarted(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event ActionCompleted(address indexed target);

    address public admin;
    address public pendingAdmin; // candidato proposto, non ancora admin
    // `immutable`: fissato nel constructor, nessuna funzione puo' cambiare il target.
    IStaticAction public immutable action;
    bool public completed;

    constructor(address admin_, IStaticAction action_) {
        // Un admin zero bloccherebbe ogni funzione onlyAdmin; un action zero renderebbe
        // execute inutilizzabile. Entrambi sono definitivi: meglio fallire al deploy.
        if (admin_ == address(0) || address(action_) == address(0)) revert ZeroAddress();
        admin = admin_;
        action = action_;
    }

    // `modifier`: un controllo riusabile che si "incolla" davanti al corpo della funzione.
    // `_;` indica il punto in cui viene eseguito il corpo: qui, solo dopo il controllo.
    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized(msg.sender);
        _;
    }

    function execute(bytes calldata data) external onlyAdmin {
        // Effetti PRIMA della call esterna (checks-effects-interactions).
        completed = true;
        emit ActionCompleted(address(action));
        // Call di alto livello: se action.run reverte, il revert risale fino a qui e
        // annulla anche `completed = true` e l'evento. Niente falso successo.
        action.run(data);
    }

    // Fase 1: l'admin corrente PROPONE un candidato. admin non cambia ancora.
    function transferAdmin(address candidate) external onlyAdmin {
        if (candidate == address(0)) revert ZeroAddress();
        pendingAdmin = candidate;
        emit AdminTransferStarted(admin, candidate);
    }

    // Fase 2: il candidato ACCETTA. Serve una transazione firmata da lui, quindi un
    // indirizzo sbagliato o senza chiave non puo' diventare admin per errore.
    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin(msg.sender);
        address oldAdmin = admin;
        admin = msg.sender;
        pendingAdmin = address(0); // la proposta si consuma: non si puo' riaccettare
        emit AdminTransferred(oldAdmin, msg.sender);
    }
}
