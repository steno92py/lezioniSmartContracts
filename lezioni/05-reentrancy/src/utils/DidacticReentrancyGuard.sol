// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Implementazione minimale per osservare il funzionamento di un mutex anti-reentrancy.
/// @dev Nei progetti reali usare una dipendenza mantenuta, pinnata e revisionata.
/// `abstract`: non si distribuisce da solo, si eredita (SafeVaultGuarded is ...).
abstract contract DidacticReentrancyGuard {
    // Due stati del lucchetto. Si usano 1 e 2 invece di false/true (0/1): riscrivere uno slot
    // gia' diverso da zero costa meno gas che riportarlo da zero a un valore non nullo.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    // `private`: i contratti figli non possono toccare il lucchetto, solo usare il modifier.
    uint256 private _status = NOT_ENTERED;

    error ReentrantCall();

    // Un modifier "avvolge" il corpo della funzione: `_;` e' il punto in cui gira il corpo.
    //
    //   withdraw (lock: ENTERED) --call--> receive() --> withdraw: _status == ENTERED -> revert
    modifier nonReentrant() {
        // Se siamo gia' dentro una funzione protetta, il rientro viene rifiutato.
        if (_status == ENTERED) revert ReentrantCall();

        _status = ENTERED; // chiude il lucchetto PRIMA del corpo (e della sua call esterna)
        _;
        _status = NOT_ENTERED; // lo riapre solo quando il corpo e' terminato
        // Se il corpo reverte, anche la scrittura ENTERED viene annullata: il lucchetto non
        // resta bloccato per sempre.
    }
}
