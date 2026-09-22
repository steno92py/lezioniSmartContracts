// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Modello didattico minimale; non sostituisce un TimelockController mantenuto.
contract FinalTimelock {
    error OnlyProposer();
    error OnlyExecutor();
    error AlreadyScheduled();
    error NotReady();
    error CallFailed(bytes reason);

    struct Operation {
        uint256 readyAt;
        bool done;
    }

    uint256 public immutable delay;
    address public immutable proposer;
    address public immutable executor;
    mapping(bytes32 id => Operation) public operations;

    constructor(uint256 delay_, address proposer_, address executor_) {
        delay = delay_;
        proposer = proposer_;
        executor = executor_;
    }

    function hashOperation(address target, bytes calldata data, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(target, data, salt));
    }

    function schedule(address target, bytes calldata data, bytes32 salt) external returns (bytes32 id) {
        if (msg.sender != proposer) revert OnlyProposer();
        id = hashOperation(target, data, salt);
        if (operations[id].readyAt != 0) revert AlreadyScheduled();
        operations[id].readyAt = block.timestamp + delay;
    }

    function execute(address target, bytes calldata data, bytes32 salt) external returns (bytes memory result) {
        if (msg.sender != executor) revert OnlyExecutor();
        bytes32 id = hashOperation(target, data, salt);
        Operation storage operation = operations[id];
        if (operation.readyAt == 0 || block.timestamp < operation.readyAt || operation.done) revert NotReady();
        operation.done = true;
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) revert CallFailed(returnData);
        return returnData;
    }
}

