// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface INotifier {
    function notify() external;
}

// ST-05 in TRIAGE.md. Ordine delle operazioni in finish():
//
//   check    if (done) revert        la transizione avviene una sola volta
//   effect   done = true             stato aggiornato PRIMA della call esterna
//   call     notifier.notify()       il notifier puo' richiamare finish (callback)
//   log      emit Finished           nessuna scrittura di stato dopo la call
//
// Una callback che richiama finish() trova gia' done = true e riceve AlreadyDone.
// Vale nel modello ATTUALE: nuove funzioni o scritture dopo la call richiedono nuovo triage.
/// @notice Caso da triage: callback possibile, ma state update prima della call e nessun write dopo.
contract NotifierFlow {
    error ZeroAddress();
    error AlreadyDone();

    event Finished(address indexed notifier);

    INotifier public immutable notifier; // fissato al deploy: una trust assumption
    bool public done;

    constructor(INotifier notifier_) {
        if (address(notifier_) == address(0)) revert ZeroAddress();
        notifier = notifier_;
    }

    function finish() external {
        if (done) revert AlreadyDone();
        done = true;
        notifier.notify();
        emit Finished(address(notifier));
    }
}
