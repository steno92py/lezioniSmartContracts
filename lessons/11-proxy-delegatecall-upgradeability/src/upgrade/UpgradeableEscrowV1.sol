// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IProxiable } from "./IProxiable.sol";

// Schema UUPS usato in questa lezione:
//
//   utente --call--> EducationalERC1967Proxy --delegatecall--> UpgradeableEscrowV1
//                    storage: owner, buyer...                  codice: initialize, fund,
//                    slot ERC-1967: implementation             upgradeToAndCall...
//
// Il proxy non sa fare upgrade: la funzione upgradeToAndCall sta QUI, nell'implementation,
// e quando gira tramite delegatecall scrive lo slot ERC-1967 del proxy.

/// @notice Implementation UUPS-like minimale per comprendere il meccanismo.
/// @dev Non sostituisce OpenZeppelin Contracts Upgradeable o i relativi validator.
contract UpgradeableEscrowV1 is IProxiable {
    error AlreadyInitialized(uint64 currentVersion);
    error InvalidAddress();
    error SameParty();
    error Unauthorized(address caller);
    error AlreadyFunded();
    error ZeroAmount();
    error MustBeCalledThroughActiveProxy();
    error MustNotBeCalledThroughProxy();
    error ImplementationHasNoCode(address implementation);
    error UnsupportedProxiableUUID(bytes32 received);
    error NotUUPSImplementation(address implementation);

    event Funded(address indexed buyer, uint256 amount);
    event Upgraded(address indexed implementation);

    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // `immutable` sta nel BYTECODE, non nello storage: anche eseguito via delegatecall dentro
    // il proxy, SELF vale sempre l'indirizzo di questa implementation. Permette di capire
    // "sto girando direttamente o tramite un proxy?" confrontandolo con address(this).
    address private immutable SELF = address(this);

    // Layout dello storage (verificalo con `forge inspect ... storageLayout`):
    //
    //   slot 0  [_initializedVersion uint64, 8 byte][owner address, 20 byte]  (packing)
    //   slot 1  buyer
    //   slot 2  seller
    //   slot 3  amount
    //   slot 4  funded
    //
    // Via proxy questi slot sono quelli DEL PROXY. Ogni versione futura deve lasciarli
    // identici (stesso ordine, stessi tipi) e aggiungere variabili solo in coda.
    uint64 private _initializedVersion; // 0 = mai inizializzato, 1 = V1, 2 = V2...
    address public owner;
    address public buyer;
    address public seller;
    uint256 public amount;
    bool public funded;

    // Il constructor gira una sola volta, sullo storage dell'IMPLEMENTATION, non del proxy:
    // per questo un contratto upgradeable usa initialize() al posto del constructor.
    // Qui il constructor serve solo a bloccare l'istanza dell'implementation: con la versione
    // al massimo, nessuno potra' chiamare initialize direttamente su di essa.
    constructor() {
        _initializedVersion = type(uint64).max;
    }

    // Modifier: codice riusabile che avvolge una funzione. `_;` indica dove si esegue il
    // corpo della funzione: qui DOPO il controllo.
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    // Due casi da rifiutare:
    //   address(this) == SELF          chiamata diretta all'implementation, non via proxy;
    //   _getImplementation() != SELF   chiamata da un contesto che non punta a questa versione.
    modifier onlyActiveProxy() {
        if (address(this) == SELF || _getImplementation() != SELF) {
            revert MustBeCalledThroughActiveProxy();
        }
        _;
    }

    /// @dev Fa le veci del constructor, ma sullo storage del proxy. Non ha controllo sul
    /// chiamante: la protezione e' chiamarla nel deploy stesso del proxy (vedi il constructor
    /// di EducationalERC1967Proxy). Un proxy lasciato non inizializzato puo' essere reclamato.
    function initialize(address owner_, address buyer_, address seller_) external {
        // Primo controllo: al secondo tentativo reverte, qualunque siano gli argomenti.
        _startInitialization(1);
        if (owner_ == address(0) || buyer_ == address(0) || seller_ == address(0)) {
            revert InvalidAddress();
        }
        if (buyer_ == seller_) revert SameParty();

        owner = owner_;
        buyer = buyer_;
        seller = seller_;
    }

    // Logica applicativa minima: registra un importo, non muove ETH ne' token.
    function fund(uint256 amount_) external {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        if (funded) revert AlreadyFunded(); // una sola volta
        if (amount_ == 0) revert ZeroAmount();

        amount = amount_;
        funded = true;
        emit Funded(msg.sender, amount_);
    }

    function initializationVersion() external view returns (uint64) {
        return _initializedVersion;
    }

    // `virtual`: i contratti figli (la V2) possono ridefinirla con `override`.
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    // Deve rispondere solo quando e' chiamata direttamente sull'implementation. Se rispondesse
    // anche tramite proxy, un upgrade potrebbe puntare per errore a un altro PROXY invece che
    // a un'implementation.
    function proxiableUUID() external view returns (bytes32) {
        if (address(this) != SELF) revert MustNotBeCalledThroughProxy();
        return IMPLEMENTATION_SLOT;
    }

    /// @dev Upgrade e migrazione nella stessa transazione. Guard nell'ordine:
    /// onlyActiveProxy (siamo nel proxy giusto), onlyOwner (autorizzazione), poi il controllo
    /// sulla nuova implementation. Chi controlla questa funzione controlla tutto lo storage.
    /// `bytes calldata`: argomento in sola lettura, letto direttamente dall'input della call.
    function upgradeToAndCall(address newImplementation, bytes calldata migrationData)
        external
        payable
        onlyActiveProxy
        onlyOwner
    {
        _checkNewImplementation(newImplementation);
        _setImplementation(newImplementation); // scrive lo slot ERC-1967 del proxy
        emit Upgraded(newImplementation);

        // Migrazione facoltativa (es. initializeV2) eseguita col codice NUOVO sullo storage del
        // proxy. Se reverte, reverte tutta la transazione e anche _setImplementation viene
        // annullata: il proxy resta sulla vecchia versione.
        if (migrationData.length != 0) {
            (bool success, bytes memory result) = newImplementation.delegatecall(migrationData);
            if (!success) _revertWithData(result);
        }
    }

    // `internal`: la V2 la riusa con targetVersion = 2. Ogni versione si inizializza una volta.
    function _startInitialization(uint64 targetVersion) internal {
        if (_initializedVersion >= targetVersion) {
            revert AlreadyInitialized(_initializedVersion);
        }
        _initializedVersion = targetVersion;
    }

    function _checkNewImplementation(address newImplementation) private view {
        // Prima si esclude un indirizzo senza codice: la call successiva non darebbe un errore
        // chiaro.
        if (newImplementation.code.length == 0) {
            revert ImplementationHasNoCode(newImplementation);
        }

        // try/catch: se la call esterna reverte (es. la funzione non esiste) non si propaga
        // il revert ma si esegue il ramo catch, che qui trasforma il caso in un errore preciso.
        try IProxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != IMPLEMENTATION_SLOT) revert UnsupportedProxiableUUID(slot);
        } catch {
            revert NotUUPSImplementation(newImplementation);
        }
    }

    function _setImplementation(address newImplementation) private {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            sstore(slot, newImplementation)
        }
    }

    function _getImplementation() internal view returns (address result) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            result := sload(slot)
        }
    }

    function _revertWithData(bytes memory result) private pure {
        assembly ("memory-safe") {
            revert(add(result, 0x20), mload(result))
        }
    }
}
