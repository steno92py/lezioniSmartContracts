// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IStaticAction {
    function run(bytes calldata data) external;
}

/// @notice Remediation: target tipizzato e immutabile, caller autorizzato, admin a due fasi.
contract SafeStaticLab {
    error ZeroAddress();
    error Unauthorized(address caller);
    error NotPendingAdmin(address caller);

    event AdminTransferStarted(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event ActionCompleted(address indexed target);

    address public admin;
    address public pendingAdmin;
    IStaticAction public immutable action;
    bool public completed;

    constructor(address admin_, IStaticAction action_) {
        if (admin_ == address(0) || address(action_) == address(0)) revert ZeroAddress();
        admin = admin_;
        action = action_;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized(msg.sender);
        _;
    }

    function execute(bytes calldata data) external onlyAdmin {
        completed = true;
        emit ActionCompleted(address(action));
        action.run(data);
    }

    function transferAdmin(address candidate) external onlyAdmin {
        if (candidate == address(0)) revert ZeroAddress();
        pendingAdmin = candidate;
        emit AdminTransferStarted(admin, candidate);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin(msg.sender);
        address oldAdmin = admin;
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferred(oldAdmin, msg.sender);
    }
}

