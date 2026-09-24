// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IRouter } from "./interfaces/IRouter.sol";

/// @notice Verifica nel consumer una proprietà economica anche se il router dovrebbe rispettarla.
contract BoundedIntegrator {
    error InvalidRouter(address router);
    error ZeroMinimumOutput();
    error InsufficientOutput(uint256 minimum, uint256 actual);

    IRouter public immutable router;
    uint256 public lastOutput;

    constructor(IRouter router_) {
        if (address(router_).code.length == 0) revert InvalidRouter(address(router_));
        router = router_;
    }

    function execute(uint256 amountIn, uint256 minimumOutput) external returns (uint256 output) {
        // Un minimo zero accetterebbe qualunque output, anche nullo: il bound sarebbe finto.
        if (minimumOutput == 0) revert ZeroMinimumOutput();

        // Call HIGH-LEVEL via interfaccia: se il router reverte, il revert risale da solo e
        // annulla tutta la transazione (a differenza della low-level call).
        output = router.swap(amountIn, minimumOutput);
        // Compatibilita' ABI != compatibilita' semantica. La call e' andata a buon fine e il
        // valore e' un uint256 valido, ma il router potrebbe aver ignorato minimumOutput:
        // la proprieta' economica si verifica QUI, nel protocollo che ne dipende.
        if (output < minimumOutput) revert InsufficientOutput(minimumOutput, output);

        // Lo stato si aggiorna solo dopo che il risultato e' stato validato.
        lastOutput = output;
    }
}
