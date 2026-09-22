// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

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
        address target;
        uint256 value;
        bytes data;
        uint256 approvals;
        bool executed;
        bool exists;
    }

    address[] private _owners;
    mapping(address owner => bool) public isOwner;
    mapping(uint256 id => Transaction transaction) private _transactions;
    mapping(uint256 id => mapping(address owner => bool approved)) public approvedBy;

    uint256 public immutable threshold;
    uint256 public nextId;

    constructor(address[] memory owners_, uint256 threshold_) {
        if (threshold_ == 0 || threshold_ > owners_.length) {
            revert InvalidThreshold(threshold_, owners_.length);
        }

        for (uint256 i; i < owners_.length; ++i) {
            address owner = owners_[i];
            if (owner == address(0)) revert ZeroOwner();
            if (isOwner[owner]) revert DuplicateOwner(owner);
            isOwner[owner] = true;
            _owners.push(owner);
        }

        threshold = threshold_;
    }

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner(msg.sender);
        _;
    }

    function submit(address target, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (uint256 id)
    {
        if (target.code.length == 0) revert InvalidTarget(target);

        id = nextId++;
        Transaction storage pendingTx = _transactions[id];
        pendingTx.target = target;
        pendingTx.value = value;
        pendingTx.data = data;
        pendingTx.exists = true;

        emit Submitted(id, target, value, data);
    }

    function approve(uint256 id) external onlyOwner {
        Transaction storage pendingTx = _transaction(id);
        if (pendingTx.executed) revert AlreadyExecuted(id);
        if (approvedBy[id][msg.sender]) revert AlreadyApproved(id, msg.sender);

        approvedBy[id][msg.sender] = true;
        pendingTx.approvals += 1;
        emit Approved(id, msg.sender, pendingTx.approvals);
    }

    function execute(uint256 id) external onlyOwner returns (bytes memory returnData) {
        Transaction storage pendingTx = _transaction(id);
        if (pendingTx.executed) revert AlreadyExecuted(id);
        if (pendingTx.approvals < threshold) {
            revert ThresholdNotReached(pendingTx.approvals, threshold);
        }

        pendingTx.executed = true;
        (bool success, bytes memory result) =
            pendingTx.target.call{ value: pendingTx.value }(pendingTx.data);
        if (!success) revert CallFailed(result);

        emit Executed(id);
        return result;
    }

    function owners() external view returns (address[] memory) {
        return _owners;
    }

    function transaction(uint256 id)
        external
        view
        returns (address target, uint256 value, bytes memory data, uint256 approvals, bool executed)
    {
        Transaction storage item = _transaction(id);
        return (item.target, item.value, item.data, item.approvals, item.executed);
    }

    function _transaction(uint256 id) private view returns (Transaction storage item) {
        item = _transactions[id];
        if (!item.exists) revert UnknownTransaction(id);
    }

    receive() external payable { }
}
