// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IVault {
    function deposit() external payable;
    function withdraw() external;
}

/// @notice Fixture locale che rientra ricorsivamente finche' il limite lo consente.
contract LocalReentrantReceiver {
    IVault public immutable vault;
    uint256 public callbacks;
    uint256 public immutable maxCallbacks;

    constructor(IVault vault_, uint256 maxCallbacks_) {
        vault = vault_;
        maxCallbacks = maxCallbacks_;
    }

    function depositIntoVault() external payable {
        vault.deposit{ value: msg.value }();
    }

    function startWithdrawal() external {
        vault.withdraw();
    }

    receive() external payable {
        // Limite artificiale per un esperimento piccolo e deterministico.
        if (callbacks < maxCallbacks && address(vault).balance >= 1 ether) {
            callbacks += 1;
            vault.withdraw();
        }
    }
}

/// @notice Probe che cattura l'esito della callback senza far fallire il payout principale.
contract LocalReentrantProbe {
    IVault public immutable vault;
    bool public attemptedReentry;
    bool public reentrySucceeded;
    bytes4 public reentryError;

    constructor(IVault vault_) {
        vault = vault_;
    }

    function depositIntoVault() external payable {
        vault.deposit{ value: msg.value }();
    }

    function startWithdrawal() external {
        vault.withdraw();
    }

    receive() external payable {
        if (!attemptedReentry) {
            attemptedReentry = true;

            (bool ok, bytes memory returnData) =
                address(vault).call(abi.encodeCall(IVault.withdraw, ()));

            reentrySucceeded = ok;
            if (!ok && returnData.length >= 4) reentryError = bytes4(returnData);
        }
    }
}

/// @notice Receiver che rifiuta il payout per verificare il rollback degli Effects.
contract RejectingVaultReceiver {
    IVault public immutable vault;

    constructor(IVault vault_) {
        vault = vault_;
    }

    function depositIntoVault() external payable {
        vault.deposit{ value: msg.value }();
    }

    function startWithdrawal() external {
        vault.withdraw();
    }

    receive() external payable {
        revert("NO_ETH");
    }
}

