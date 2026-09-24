// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Receiver usati dai test: contratti che fanno da "utente" del vault. Essendo contratti, quando
// ricevono ETH eseguono codice (receive) e possono reagire al pagamento.
// Tutti e tre hanno la stessa forma:
//   depositIntoVault()  deposita nel vault, cosi' il receiver ha un credito legittimo;
//   startWithdrawal()   chiama vault.withdraw(): da qui parte la catena di call;
//   receive()           cio' che il receiver fa quando il vault gli invia ETH.

// Interfaccia minima: i tre vault hanno queste funzioni, quindi un receiver li usa tutti.
interface IVault {
    function deposit() external payable;
    function withdraw() external;
}

/// @notice Fixture locale che rientra ricorsivamente finche' il limite lo consente.
contract LocalReentrantReceiver {
    IVault public immutable vault;
    uint256 public callbacks; // quante volte e' gia' rientrato
    uint256 public immutable maxCallbacks;

    constructor(IVault vault_, uint256 maxCallbacks_) {
        vault = vault_;
        maxCallbacks = maxCallbacks_;
    }

    function depositIntoVault() external payable {
        // Inoltra al vault l'ETH ricevuto: nel vault msg.sender sara' questo contratto.
        vault.deposit{ value: msg.value }();
    }

    function startWithdrawal() external {
        vault.withdraw();
    }

    // `receive()` gira quando il contratto riceve ETH con calldata vuota, come nella
    // msg.sender.call{ value: amount }("") del vault.
    receive() external payable {
        // Limite artificiale per un esperimento piccolo e deterministico.
        // Il controllo sul saldo evita di chiedere piu' di quanto il vault possieda: la call
        // fallirebbe e il revert annullerebbe l'intero attacco.
        if (callbacks < maxCallbacks && address(vault).balance >= 1 ether) {
            callbacks += 1;
            vault.withdraw(); // RIENTRO: il withdraw precedente non e' ancora terminato
        }
    }
}

/// @notice Probe che cattura l'esito della callback senza far fallire il payout principale.
/// @dev Con una call normale il revert del rientro risalirebbe e annullerebbe tutto il
/// withdraw: non si potrebbe verificare che il primo pagamento riesce e il secondo no.
contract LocalReentrantProbe {
    IVault public immutable vault;
    bool public attemptedReentry; // il probe ha davvero provato a rientrare?
    bool public reentrySucceeded; // il rientro e' riuscito?
    bytes4 public reentryError; // selettore dell'errore restituito dal rientro

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
        // Un solo tentativo: basta per dimostrare che il rientro viene respinto.
        if (!attemptedReentry) {
            attemptedReentry = true;

            // Low-level call: se withdraw reverte, `ok` vale false ma il probe NON reverte.
            // abi.encodeCall costruisce la calldata di withdraw() controllando i tipi.
            (bool ok, bytes memory returnData) =
                address(vault).call(abi.encodeCall(IVault.withdraw, ()));

            reentrySucceeded = ok;
            // I primi 4 byte dei dati di revert di un custom error sono il suo selettore.
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

    // Ogni ETH in arrivo viene rifiutato: nel vault la call restituisce ok = false.
    receive() external payable {
        revert("NO_ETH");
    }
}
