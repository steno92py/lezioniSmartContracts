// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IRouter } from "../interfaces/IRouter.sol";

// Tre router con la STESSA interfaccia e comportamenti diversi: per il compilatore sono
// tutti IRouter validi.

// Router corretto, ma il suo output si puo' cambiare dopo il deploy: simula una dipendenza
// che cambia comportamento allo stesso indirizzo.
contract GoodRouter is IRouter {
    uint256 public output = 1_000;

    function setOutput(uint256 newOutput) external {
        output = newOutput;
    }

    function swap(uint256, uint256) external view returns (uint256) {
        return output;
    }
}

// ABI-compatibile ma semanticamente sbagliato: ignora amountOutMin e restituisce 1.
contract WeirdRouter is IRouter {
    function swap(uint256, uint256) external pure returns (uint256) {
        return 1;
    }
}

// Router non disponibile: reverte sempre.
contract RevertingRouter is IRouter {
    error RouterUnavailable();

    function swap(uint256, uint256) external pure returns (uint256) {
        revert RouterUnavailable();
    }
}
