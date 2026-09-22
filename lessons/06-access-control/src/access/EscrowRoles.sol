// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice RBAC minimale e ispezionabile per il laboratorio.
/// @dev Per produzione usare una libreria mantenuta e pinnata, come OpenZeppelin AccessControl.
contract EscrowRoles {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");

    error ZeroAccount();
    error MissingRole(address account, bytes32 role);

    mapping(bytes32 role => mapping(address account => bool member)) private _roles;
    mapping(bytes32 role => bytes32 adminRole) private _roleAdmins;

    bool public paused;
    bool public disputeResolved;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event PauseChanged(bool paused, address indexed pauser);
    event DisputeResolved(address indexed arbiter);

    constructor(address admin, address pauser, address arbiter) {
        if (admin == address(0) || pauser == address(0) || arbiter == address(0)) {
            revert ZeroAccount();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(ARBITER_ROLE, arbiter);
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert MissingRole(msg.sender, role);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    /// @dev Il valore di default e' DEFAULT_ADMIN_ROLE per tutti i ruoli del laboratorio.
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roleAdmins[role];
    }

    function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert ZeroAccount();
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function setPaused(bool value) external onlyRole(PAUSER_ROLE) {
        paused = value;
        emit PauseChanged(value, msg.sender);
    }

    function resolveDispute() external onlyRole(ARBITER_ROLE) {
        disputeResolved = true;
        emit DisputeResolved(msg.sender);
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
}

