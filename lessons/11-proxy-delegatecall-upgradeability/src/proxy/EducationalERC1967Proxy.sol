// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Proxy ERC-1967 minimale per il laboratorio. Non usare in produzione.
/// @dev Il proxy non ha variabili di stato dichiarate: gli slot 0, 1, 2... restano tutti
/// all'implementation. L'unico dato del proxy vive in uno slot fisso scelto da ERC-1967.
/// Il proxy non ha nemmeno una funzione di upgrade: quella sta nell'implementation (UUPS).
contract EducationalERC1967Proxy {
    error ImplementationHasNoCode(address implementation);

    // Slot standard ERC-1967: keccak256("eip1967.proxy.implementation") - 1.
    // Un numero pseudo-casuale enorme: nessuna variabile dichiarata normalmente puo' finirci.
    // E' `constant`: vive nel bytecode, non occupa storage.
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Deploy e inizializzazione nella stessa transazione: nessuno puo' inserirsi tra i due
    /// passi e chiamare initialize al posto nostro.
    /// `bytes memory`: copia temporanea degli argomenti, che vive solo durante la call.
    constructor(address implementation_, bytes memory initializationData) payable {
        _setImplementation(implementation_);
        if (initializationData.length != 0) {
            // Esegue initialize(...) con il codice dell'implementation sullo storage del proxy.
            // Se fallisce, fallisce l'intero deploy: niente proxy a meta'.
            _delegateCall(implementation_, initializationData);
        }
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    // Qualunque funzione sconosciuta al proxy viene inoltrata all'implementation.
    fallback() external payable {
        _delegate(_implementation());
    }

    // `receive`: eseguita per un invio di ETH con calldata vuota. Anche questa viene inoltrata:
    // decide l'implementation se accettare l'ETH.
    receive() external payable {
        _delegate(_implementation());
    }

    // `private`: visibile solo in questo contratto, nemmeno nei contratti figli.
    function _setImplementation(address newImplementation) private {
        // Puntare a un indirizzo senza codice renderebbe ogni call al proxy un no-op silenzioso.
        if (newImplementation.code.length == 0) {
            revert ImplementationHasNoCode(newImplementation);
        }
        bytes32 slot = IMPLEMENTATION_SLOT;
        // sstore/sload: scrittura/lettura diretta di uno slot per numero. Solidity non permette
        // di dichiarare una variabile in uno slot scelto a mano, quindi serve l'assembly.
        assembly ("memory-safe") {
            sstore(slot, newImplementation)
        }
    }

    function _implementation() private view returns (address result) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            result := sload(slot)
        }
    }

    function _delegateCall(address target, bytes memory data) private {
        // delegatecall a basso livello: NON reverte da sola se la call fallisce, restituisce
        // success = false. Il controllo va fatto a mano, altrimenti l'errore viene ignorato.
        (bool success, bytes memory result) = target.delegatecall(data);
        if (!success) _revertWithData(result);
    }

    // Rilancia lo stesso errore ricevuto, cosi' il chiamante vede il motivo originale.
    // In memory un `bytes` e' [32 byte di lunghezza][dati]: si salta la lunghezza (0x20)
    // e si revertisce con i dati.
    function _revertWithData(bytes memory result) private pure {
        assembly ("memory-safe") {
            revert(add(result, 0x20), mload(result))
        }
    }

    // Il cuore del proxy, in quattro passi:
    function _delegate(address target) private {
        assembly ("memory-safe") {
            // 1. copia in memory tutta la calldata ricevuta (selettore + argomenti);
            calldatacopy(0, 0, calldatasize())
            // 2. la riesegue con il codice di target nel contesto di questo proxy; 0 = fallita;
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            // 3. copia in memory i dati restituiti (valore di ritorno o errore);
            returndatacopy(0, 0, returndatasize())
            // 4. li restituisce al chiamante cosi' come sono, con revert o return.
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
