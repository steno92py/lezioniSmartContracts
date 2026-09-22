// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title Registro didattico di depositi
/// @notice Mostra come calldata, msg.sender e msg.value diventano stato persistente.
/// @dev Non e' un escrow completo: l'ETH depositata non puo' essere prelevata.
contract EscrowLesson1 {
    uint256 public constant MAX_NOTE_BYTES = 256;

    error ZeroBeneficiary();
    error ZeroValue();
    error NoteTooLong(uint256 actualLength);
    error UnknownDeposit(uint256 id);

    struct Deposit {
        address payer;
        address beneficiary;
        uint256 amount;
        bytes32 noteHash;
    }

    uint256 public nextId;
    uint256 public totalRecorded;

    mapping(uint256 id => Deposit deposit) private _deposits;
    mapping(address beneficiary => uint256 amount) public credited;

    event DepositRecorded(
        uint256 indexed id,
        address indexed payer,
        address indexed beneficiary,
        uint256 amount,
        bytes32 noteHash
    );

    /// @notice Registra un deposito e accredita contabilmente il beneficiario.
    /// @param beneficiary Indirizzo a favore del quale viene registrato il deposito.
    /// @param note Nota arbitraria di massimo 256 byte; viene salvato soltanto il suo hash.
    /// @return id Identificativo progressivo del deposito appena creato.
    function record(address beneficiary, bytes calldata note)
        external
        payable
        returns (uint256 id)
    {
        if (beneficiary == address(0)) revert ZeroBeneficiary();
        if (msg.value == 0) revert ZeroValue();
        if (note.length > MAX_NOTE_BYTES) revert NoteTooLong(note.length);

        id = nextId;
        nextId = id + 1;

        bytes32 noteHash = keccak256(note);

        _deposits[id] = Deposit({
            payer: msg.sender, beneficiary: beneficiary, amount: msg.value, noteHash: noteHash
        });

        credited[beneficiary] += msg.value;
        totalRecorded += msg.value;

        emit DepositRecorded(id, msg.sender, beneficiary, msg.value, noteHash);
    }

    /// @notice Restituisce un deposito gia' registrato.
    function getDeposit(uint256 id) external view returns (Deposit memory deposit_) {
        if (id >= nextId) revert UnknownDeposit(id);
        deposit_ = _deposits[id];
    }
}

