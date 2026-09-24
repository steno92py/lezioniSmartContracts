// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { INotifier } from "./interfaces/INotifier.sol";

// Dipendenza ACCESSORIA: se il notifier fallisce, la release deve restare valida.
// Politica "fail-open" solo per la notifica; la release stessa resta "fail-closed".
//
//   buyer --release()--> NotificationEscrow --try notifyReleased--> notifier
//                         released = true        ok   -> NotificationSucceeded
//                         emit Released          fail -> NotificationFailed(reason)

/// @notice La release è critica; la notifica è esplicitamente best-effort.
contract NotificationEscrow {
    error InvalidNotifier(address notifier);
    error ZeroAddress();
    error OnlyBuyer(address caller);
    error AlreadyReleased();

    // Gli eventi rendono OSSERVABILE il fallimento: un failure accessorio non blocca, ma
    // nemmeno sparisce in silenzio.
    event NotificationSucceeded(address indexed notifier);
    event NotificationFailed(address indexed notifier, bytes reason);
    event Released(address indexed seller, uint256 amount);

    // `immutable`: fissati nel constructor, poi nessuno puo' sostituire il notifier.
    INotifier public immutable notifier;
    address public immutable buyer;
    address public immutable seller;
    uint256 public immutable amount;

    bool public released;

    constructor(INotifier notifier_, address buyer_, address seller_, uint256 amount_) {
        // `.code.length == 0`: all'indirizzo non c'e' codice. Una call di notifica verso un
        // EOA non farebbe nulla: meglio rifiutare la configurazione subito, al deploy.
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
        // CHECKS: solo il buyer, una volta sola.
        if (msg.sender != buyer) revert OnlyBuyer(msg.sender);
        if (released) revert AlreadyReleased();

        // EFFECTS: il diritto economico e' registrato PRIMA della call esterna.
        released = true;
        emit Released(seller, amount);

        // INTERACTION best-effort. `try/catch` funziona solo su call esterne: se
        // notifyReleased reverte, il revert viene catturato invece di annullare la release.
        // `reason` contiene i byte dell'errore del notifier (es. il selector di Nope()).
        // try/catch qui e' corretto SOLO perche' la notifica non decide chi riceve cosa: su
        // una dipendenza critica ignorare il fallimento creerebbe un falso successo.
        try notifier.notifyReleased(seller, amount) {
            emit NotificationSucceeded(address(notifier));
        } catch (bytes memory reason) {
            emit NotificationFailed(address(notifier), reason);
        }
    }
}
