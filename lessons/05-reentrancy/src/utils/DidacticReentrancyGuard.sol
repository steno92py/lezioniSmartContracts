// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Implementazione minimale per osservare il funzionamento di un mutex anti-reentrancy.
/// @dev Nei progetti reali usare una dipendenza mantenuta, pinnata e revisionata.
abstract contract DidacticReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status = NOT_ENTERED;

    error ReentrantCall();

    modifier nonReentrant() {
        if (_status == ENTERED) revert ReentrantCall();

        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

