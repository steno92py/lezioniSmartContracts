// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { INotifier } from "./interfaces/INotifier.sol";

/// @notice La release è critica; la notifica è esplicitamente best-effort.
contract NotificationEscrow {
    error InvalidNotifier(address notifier);
    error ZeroAddress();
    error OnlyBuyer(address caller);
    error AlreadyReleased();

    event NotificationSucceeded(address indexed notifier);
    event NotificationFailed(address indexed notifier, bytes reason);
    event Released(address indexed seller, uint256 amount);

    INotifier public immutable notifier;
    address public immutable buyer;
    address public immutable seller;
    uint256 public immutable amount;

    bool public released;

    constructor(INotifier notifier_, address buyer_, address seller_, uint256 amount_) {
        if (address(notifier_).code.length == 0) {
            revert InvalidNotifier(address(notifier_));
        }
        if (buyer_ == address(0) || seller_ == address(0)) revert ZeroAddress();

        notifier = notifier_;
        buyer = buyer_;
        seller = seller_;
        amount = amount_;
    }

    function release() external {
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        if (released) revert AlreadyReleased();

        released = true;
        emit Released(seller, amount);

        try notifier.notifyReleased(seller, amount) {
            emit NotificationSucceeded(address(notifier));
        } catch (bytes memory reason) {
            emit NotificationFailed(address(notifier), reason);
        }
    }
}

