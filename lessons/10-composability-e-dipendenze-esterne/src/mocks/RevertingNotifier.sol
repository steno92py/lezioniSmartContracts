// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { INotifier } from "../interfaces/INotifier.sol";

// Mock ostile: rispetta l'interfaccia ma fallisce sempre. Serve a provare che la release
// sopravvive a un notifier rotto.
contract RevertingNotifier is INotifier {
    error Nope();

    // `pure`: non legge ne' scrive stato. I parametri senza nome non vengono usati.
    function notifyReleased(address, uint256) external pure {
        revert Nope();
    }
}
