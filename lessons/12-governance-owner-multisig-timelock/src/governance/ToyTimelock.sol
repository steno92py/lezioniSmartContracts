// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Timelock minimale con proposer, executor, canceller e admin separati.
/// @dev Modello didattico; non sostituisce OpenZeppelin TimelockController.
contract ToyTimelock {
    enum Role {
        Proposer,
        Executor,
        Canceller
    }

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
        uint256 readyAt;
        bool done;
        bool cancelled;
    }

    address public immutable admin;
    uint256 public immutable minimumDelay;

    mapping(Role role => mapping(address account => bool enabled)) public hasRole;
    mapping(bytes32 id => Operation operation) private _operations;

    constructor(
        uint256 minimumDelay_,
        address proposer,
        address executor,
        address canceller,
        address admin_
    ) {
        if (minimumDelay_ == 0) revert InvalidDelay();
        if (proposer == address(0) || canceller == address(0) || admin_ == address(0)) {
            revert ZeroAddress();
        }

        minimumDelay = minimumDelay_;
        admin = admin_;
        hasRole[Role.Proposer][proposer] = true;
        hasRole[Role.Executor][executor] = true;
        hasRole[Role.Canceller][canceller] = true;
    }

    function setRole(Role role, address account, bool enabled) external {
        if (msg.sender != admin) revert OnlyAdmin(msg.sender);
        if (account == address(0) && role != Role.Executor) revert ZeroAddress();

        hasRole[role][account] = enabled;
        emit RoleUpdated(role, account, enabled);
    }

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
        if (delay < minimumDelay) revert InvalidDelay();

        id = hashOperation(target, value, data, predecessor, salt);
        Operation storage operation = _operations[id];
        OperationState current = getOperationState(id);
        if (current != OperationState.Unset && current != OperationState.Cancelled) {
            revert OperationAlreadyScheduled(id);
        }

        operation.readyAt = block.timestamp + delay;
        operation.done = false;
        operation.cancelled = false;
        emit OperationScheduled(id, target, operation.readyAt);
    }

    function cancel(bytes32 id) external {
        _requireRole(Role.Canceller);
        OperationState current = getOperationState(id);
        if (current != OperationState.Waiting && current != OperationState.Ready) {
            revert OperationNotPending(id);
        }

        _operations[id].cancelled = true;
        emit OperationCancelled(id);
    }

    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external payable returns (bytes memory returnData) {
        _requireExecutor();
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        Operation storage operation = _operations[id];
        if (getOperationState(id) != OperationState.Ready) {
            revert OperationNotReady(id, operation.readyAt, block.timestamp);
        }
        if (predecessor != bytes32(0) && getOperationState(predecessor) != OperationState.Done) {
            revert MissingPredecessor(predecessor);
        }

        operation.done = true;
        (bool success, bytes memory result) = target.call{ value: value }(data);
        if (!success) revert UnderlyingCallFailed(result);

        emit OperationExecuted(id, target);
        return result;
    }

    function getOperationState(bytes32 id) public view returns (OperationState) {
        Operation storage operation = _operations[id];
        if (operation.done) return OperationState.Done;
        if (operation.cancelled) return OperationState.Cancelled;
        if (operation.readyAt == 0) return OperationState.Unset;
        if (block.timestamp < operation.readyAt) return OperationState.Waiting;
        return OperationState.Ready;
    }

    function readyAt(bytes32 id) external view returns (uint256) {
        return _operations[id].readyAt;
    }

    function _requireRole(Role role) private view {
        if (!hasRole[role][msg.sender]) revert Unauthorized(msg.sender, role);
    }

    function _requireExecutor() private view {
        if (!hasRole[Role.Executor][msg.sender] && !hasRole[Role.Executor][address(0)]) {
            revert Unauthorized(msg.sender, Role.Executor);
        }
    }

    receive() external payable { }
}

