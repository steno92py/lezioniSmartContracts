// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// `view` nell'interfaccia e' una promessa del chiamante, non del chiamato: il compilatore usa
// una STATICCALL, che fa revertire il provider se prova a scrivere stato. Il valore restituito,
// pero', resta quello che il provider decide.
interface IValueProvider {
    function value() external view returns (uint256);
}
