// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// RBAC (Role-Based Access Control): invece di un solo admin onnipotente, ogni operazione
// richiede un ruolo preciso. Due domande diverse per ogni ruolo:
//   chi POSSIEDE il ruolo       -> puo' eseguire l'operazione (hasRole);
//   chi AMMINISTRA il ruolo     -> puo' concederlo e revocarlo (getRoleAdmin).
// L'admin amministra PAUSER e ARBITER ma non li possiede: least privilege.

/// @notice RBAC minimale e ispezionabile per il laboratorio.
/// @dev Per produzione usare una libreria mantenuta e pinnata, come OpenZeppelin AccessControl.
contract EscrowRoles {
    // Un ruolo e' solo un identificatore a 32 byte. keccak256 di un nome leggibile produce
    // ID diversi per nomi diversi. DEFAULT_ADMIN_ROLE vale zero (vedi getRoleAdmin).
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");

    error ZeroAccount();
    error MissingRole(address account, bytes32 role);

    // Mapping annidato: _roles[ruolo][account] == true se l'account possiede il ruolo.
    mapping(bytes32 role => mapping(address account => bool member)) private _roles;
    // Per ogni ruolo, il ruolo che lo amministra. Nessuno lo scrive in questo contratto.
    mapping(bytes32 role => bytes32 adminRole) private _roleAdmins;

    bool public paused;
    bool public disputeResolved;

    // `sender` registra CHI ha concesso o revocato: utile per ricostruire la storia dei permessi.
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event PauseChanged(bool paused, address indexed pauser);
    event DisputeResolved(address indexed arbiter);

    constructor(address admin, address pauser, address arbiter) {
        if (admin == address(0) || pauser == address(0) || arbiter == address(0)) {
            revert ZeroAccount();
        }

        // Il constructor usa la funzione interna, senza controlli di ruolo: al deploy
        // nessuno ha ancora ruoli, quindi grantRole fallirebbe.
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(ARBITER_ROLE, arbiter);
    }

    // Modifier con parametro: lo stesso controllo serve per ruoli diversi.
    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert MissingRole(msg.sender, role);
        _;
    }

    /// @dev `public`: chiamabile sia dall'esterno sia dall'interno (qui dal modifier).
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    /// @dev Il valore di default e' DEFAULT_ADMIN_ROLE per tutti i ruoli del laboratorio.
    /// Un mapping mai scritto restituisce zero, e zero e' proprio DEFAULT_ADMIN_ROLE.
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roleAdmins[role];
    }

    // Il ruolo richiesto dipende dal ruolo da concedere: onlyRole(getRoleAdmin(role)).
    function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert ZeroAccount();
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        // Scrive ed emette l'evento solo se il ruolo c'era davvero: niente log fuorvianti.
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    // Operazioni quotidiane: ognuna richiede il proprio ruolo, e solo quello.
    function setPaused(bool value) external onlyRole(PAUSER_ROLE) {
        paused = value;
        emit PauseChanged(value, msg.sender);
    }

    function resolveDispute() external onlyRole(ARBITER_ROLE) {
        disputeResolved = true;
        emit DisputeResolved(msg.sender);
    }

    // `internal`: nessuno puo' chiamarla dall'esterno. Le uniche vie per arrivarci sono il
    // constructor e grantRole, che e' protetta da onlyRole.
    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
}
