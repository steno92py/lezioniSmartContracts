// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// `interface`: elenca solo le firme delle funzioni di un altro contratto. Serve a chiamarlo
// in modo tipizzato: IStaticPriceOracle(indirizzo).read().
interface IStaticPriceOracle {
    function read() external view returns (uint256);
}

// Mappa dei finding (schede complete in TRIAGE.md):
//   ST-01 unsafeExecute     low-level call con esito ignorato -> falso successo
//   ST-02 setAdmin          write admin senza authorization
//   ST-03 arbitraryExecute  target e calldata scelti dall'utente, eseguiti come StaticLab
//   ST-04 oracle/readOracle variabile mai inizializzata -> read path inutilizzabile
// Non tutti escono da un detector: ST-02 e ST-03 richiedono printer e review manuale.
/// @notice Codice intenzionalmente insicuro: serve soltanto per trovare e confermare finding.
contract StaticLab {
    address public admin;
    // ST-04: nessuna funzione scrive `oracle`, quindi resta per sempre address(0).
    address public oracle;
    bool public completed; // dovrebbe significare "l'azione esterna e' riuscita"

    constructor(address admin_) {
        admin = admin_;
    }

    // ST-01. `target.call(data)` e' una low-level call: invia bytes grezzi a un indirizzo e
    // NON reverte se la chiamata fallisce, ma restituisce (bool success, bytes result).
    // Qui il valore di ritorno viene scartato: se target reverte, l'esecuzione prosegue
    // e `completed` registra un successo mai avvenuto. Il compilatore stesso da' un warning.
    // Fix (SafeStaticLab.execute): call tipizzata di alto livello, che propaga il revert.
    function unsafeExecute(address target, bytes calldata data) external {
        target.call(data); // esito ignorato
        completed = true; // scritto anche quando la call e' fallita
    }

    // ST-03. Qui l'esito E' controllato, ma il problema e' la capability: chiunque sceglie
    // sia il target sia la calldata. Nel contratto chiamato msg.sender e' StaticLab, quindi
    // l'attaccante agisce con l'autorita' e gli asset del laboratorio:
    //
    //   attacker --arbitraryExecute(token, transfer(attacker, 100))--> StaticLab
    //   StaticLab --transfer(attacker, 100)--> token     (msg.sender = StaticLab)
    //
    // Fix: target immutabile, interfaccia ristretta e caller autorizzato.
    function arbitraryExecute(address target, bytes calldata data) external returns (bytes memory returnData) {
        (bool success, bytes memory result) = target.call(data);
        // require(cond, "msg"): se cond e' falsa, revert con un messaggio stringa.
        require(success, "CALL_FAILED");
        return result;
    }

    // ST-02. Una funzione "da admin" senza alcun controllo su msg.sender: chiunque puo'
    // nominarsi admin. Fix: onlyAdmin + trasferimento a due fasi (vedi SafeStaticLab).
    function setAdmin(address newAdmin) external {
        admin = newAdmin;
    }

    // ST-04. Con oracle = address(0) la call trova un indirizzo senza codice e reverte:
    // la funzione non puo' mai restituire un prezzo valido.
    function readOracle() external view returns (uint256) {
        return IStaticPriceOracle(oracle).read();
    }

    // `receive`: la funzione eseguita quando il contratto riceve ETH senza calldata.
    // Senza receive (o fallback payable) un semplice invio di ETH reverterebbe.
    receive() external payable {}
}
