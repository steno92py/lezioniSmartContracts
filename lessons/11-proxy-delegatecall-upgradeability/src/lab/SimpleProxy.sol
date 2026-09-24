// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Un proxy separa tre cose che di solito coincidono:
//   address  quello del proxy: e' l'indirizzo che gli utenti chiamano;
//   storage  quello del proxy: i dati vivono qui e sopravvivono agli upgrade;
//   code     quello dell'implementation: la logica, sostituibile.
//
// Con `delegatecall` il proxy esegue il codice di un altro contratto DENTRO il proprio contesto:
// quel codice legge e scrive lo storage del proxy, e msg.sender resta il chiamante originale.
//
//   utente --call--> SimpleProxy --delegatecall--> SimpleLogicV1
//                    (storage, address)            (solo il codice)

/// @notice Proxy intenzionalmente insicuro: metadata nello slot 0 e upgrade senza autorizzazione.
contract SimpleProxy {
    // Vulnerabilita' 1: prima variabile di stato -> slot 0. Anche SimpleLogicV1.value e'
    // nello slot 0. Nell'EVM i nomi non esistono, solo i numeri di slot:
    //
    //   slot 0 del proxy
    //     letto da SimpleProxy   come `implementation` (address)
    //     letto da SimpleLogicV1 come `value`          (uint256)
    //
    // setValue(123) chiamato tramite proxy sovrascrive l'indirizzo dell'implementation.
    // La correzione e' EducationalERC1967Proxy: indirizzo salvato in uno slot pseudo-casuale.
    address public implementation;

    constructor(address implementation_) {
        implementation = implementation_;
    }

    // Vulnerabilita' 2: nessun controllo sul chiamante. Chiunque puo' sostituire il codice,
    // e con il codice il controllo di tutto lo storage del proxy.
    function upgradeTo(address newImplementation) external {
        implementation = newImplementation;
    }

    // `fallback`: eseguita quando la calldata non corrisponde a nessuna funzione del proxy.
    // Qui inoltra TUTTO all'implementation. Il blocco e' spiegato in EducationalERC1967Proxy.
    fallback() external {
        address target = implementation;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
