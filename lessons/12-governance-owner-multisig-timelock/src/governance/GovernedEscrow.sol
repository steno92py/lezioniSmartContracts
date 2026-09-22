// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Target amministrato con owner a due fasi e pauser separato.
contract GovernedEscrow {
    error ZeroAddress();
    error Unauthorized(address caller);
    error NotPendingOwner(address caller);
    error FeeTooHigh(uint256 feeBps);
    error AlreadyPaused();
    error NotPaused();
    error Paused();

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event PausedBy(address indexed caller);
    event Unpaused(address indexed caller);

    address public owner;
    address public pendingOwner;
    address public immutable emergencyPauser;

    uint256 public feeBps;
    address public oracle;
    bool public paused;
    uint256 public sensitiveActions;
    uint256 public exits;

    constructor(address initialOwner, address emergencyPauser_) {
        if (initialOwner == address(0) || emergencyPauser_ == address(0)) revert ZeroAddress();
        owner = initialOwner;
        emergencyPauser = emergencyPauser_;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    function transferOwnership(address candidate) external onlyOwner {
        if (candidate == address(0)) revert ZeroAddress();
        pendingOwner = candidate;
        emit OwnershipTransferStarted(owner, candidate);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);
        address oldOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function setFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > 1_000) revert FeeTooHigh(newFeeBps);
        uint256 oldFee = feeBps;
        feeBps = newFeeBps;
        emit FeeUpdated(oldFee, newFeeBps);
    }

    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroAddress();
        address oldOracle = oracle;
        oracle = newOracle;
        emit OracleUpdated(oldOracle, newOracle);
    }

    function pause() external {
        if (msg.sender != emergencyPauser) revert Unauthorized(msg.sender);
        if (paused) revert AlreadyPaused();
        paused = true;
        emit PausedBy(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!paused) revert NotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    function sensitiveAction() external {
        if (paused) revert Paused();
        sensitiveActions += 1;
    }

    /// @notice L'uscita resta disponibile anche durante la pausa.
    function exit() external {
        exits += 1;
    }
}

