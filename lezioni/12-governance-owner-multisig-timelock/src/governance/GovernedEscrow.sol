// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Il contratto che possiede i privilegi. Chi e' `owner` qui decide tutto il resto:
// se l'owner e' il timelock, le funzioni onlyOwner si raggiungono solo passando dal delay.
// Il pauser e' un'autorita' separata e volutamente piu' debole: agisce subito, ma su poco.

/// @notice Target amministrato con owner a due fasi e pauser separato.
contract GovernedEscrow {
    error ZeroAddress();
    error Unauthorized(address caller);
    error NotPendingOwner(address caller);
    error FeeTooHigh(uint256 feeBps);
    error AlreadyPaused();
    error NotPaused();
    error Paused();

    // Ogni cambio di configurazione emette un evento con valore vecchio e nuovo:
    // chi monitora vede cosa cambia prima che l'effetto lo colpisca.
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event PausedBy(address indexed caller);
    event Unpaused(address indexed caller);

    address public owner;
    address public pendingOwner; // candidato proposto, non ancora owner
    address public immutable emergencyPauser;

    uint256 public feeBps; // basis point: 1 bps = 0,01%, quindi 1_000 bps = 10%
    address public oracle;
    bool public paused;
    uint256 public sensitiveActions; // contatori: rendono verificabile nei test cosa e' passato
    uint256 public exits;

    constructor(address initialOwner, address emergencyPauser_) {
        if (initialOwner == address(0) || emergencyPauser_ == address(0)) revert ZeroAddress();
        owner = initialOwner;
        emergencyPauser = emergencyPauser_;
        // Convenzione: il "trasferimento" iniziale parte da address(0), cosi' chi legge gli
        // eventi ricostruisce tutta la storia dell'ownership.
        emit OwnershipTransferred(address(0), initialOwner);
    }

    // Il modifier controlla msg.sender, cioe' il chiamante DIRETTO: quando esegue il
    // timelock, msg.sender e' il timelock, non chi ha proposto l'operazione.
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    // OWNERSHIP A DUE FASI:
    //   1. transferOwnership(candidate): l'owner propone, ma resta owner;
    //   2. acceptOwnership(): il candidato accetta e solo allora diventa owner.
    // Un indirizzo sbagliato nel passo 1 non fa perdere il controllo: nessuno potra'
    // accettare, e l'owner attuale puo' proporre di nuovo.
    function transferOwnership(address candidate) external onlyOwner {
        if (candidate == address(0)) revert ZeroAddress();
        pendingOwner = candidate;
        emit OwnershipTransferStarted(owner, candidate);
    }

    function acceptOwnership() external {
        // Chi accetta dimostra di controllare davvero il nuovo indirizzo.
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);
        address oldOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0); // la proposta e' consumata
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function setFee(uint256 newFeeBps) external onlyOwner {
        // Tetto nel codice: nemmeno l'owner legittimo puo' superare il 10%.
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

    // FAST PAUSE: il pauser agisce subito, senza delay, ma puo' solo fermare.
    function pause() external {
        if (msg.sender != emergencyPauser) revert Unauthorized(msg.sender);
        if (paused) revert AlreadyPaused();
        paused = true;
        emit PausedBy(msg.sender);
    }

    // SLOW RESTART: riaprire spetta all'owner (il timelock), quindi passa dal delay.
    // Autorita' diverse per pause e unpause limitano il danno di una chiave di emergenza
    // compromessa: puo' fermare il sistema, non riconfigurarlo ne' riaprirlo a piacere.
    function unpause() external onlyOwner {
        if (!paused) revert NotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    // Azione "normale" del protocollo: bloccata durante la pausa.
    function sensitiveAction() external {
        if (paused) revert Paused();
        sensitiveActions += 1;
    }

    /// @notice L'uscita resta disponibile anche durante la pausa.
    /// @dev Nessun controllo su `paused`, di proposito: una pausa non deve intrappolare
    /// gli utenti.
    function exit() external {
        exits += 1;
    }
}
