// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface INotifier {
    function notify() external;
}

/// @notice Caso da triage: callback possibile, ma state update prima della call e nessun write dopo.
contract NotifierFlow {
    error ZeroAddress();
    error AlreadyDone();

    event Finished(address indexed notifier);

    INotifier public immutable notifier;
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

