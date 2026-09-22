// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IStaticPriceOracle {
    function read() external view returns (uint256);
}

/// @notice Codice intenzionalmente insicuro: serve soltanto per trovare e confermare finding.
contract StaticLab {
    address public admin;
    address public oracle;
    bool public completed;

    constructor(address admin_) {
        admin = admin_;
    }

    function unsafeExecute(address target, bytes calldata data) external {
        target.call(data);
        completed = true;
    }

    function arbitraryExecute(address target, bytes calldata data) external returns (bytes memory returnData) {
        (bool success, bytes memory result) = target.call(data);
        require(success, "CALL_FAILED");
        return result;
    }

    function setAdmin(address newAdmin) external {
        admin = newAdmin;
    }

    function readOracle() external view returns (uint256) {
        return IStaticPriceOracle(oracle).read();
    }

    receive() external payable {}
}

