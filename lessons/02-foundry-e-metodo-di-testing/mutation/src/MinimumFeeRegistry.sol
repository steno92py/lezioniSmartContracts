// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Mutante: copia di FixedFeeRegistry con UN solo operatore cambiato. Una "mutazione" e' un
// bug plausibile introdotto apposta: se nessun test diventa rosso, la suite non lo vede.
// Si compila solo col profilo `mutation` (vedi foundry.toml): la suite normale non lo tocca.

/// @notice Mutante volutamente errato: accetta qualsiasi importo maggiore o uguale alla fee.
/// @dev Esiste soltanto per mostrare se il regression test distingue `==` da `>=`.
contract MinimumFeeRegistry {
    uint256 public constant REGISTRATION_FEE = 1 ether;

    mapping(address account => bool isRegistered) public registered;
    uint256 public registrationCount;
    uint256 public totalReceived;

    error ExactFeeRequired(uint256 sent, uint256 required);
    error AlreadyRegistered(address account);

    function register() external payable {
        if (registered[msg.sender]) revert AlreadyRegistered(msg.sender);

        // MUTAZIONE: il requisito richiede `!=`, non `<`.
        // 0 e 0.5 ether vengono ancora rifiutati: i test su fee bassa restano verdi.
        // 2 ether invece passano: solo un test con fee TROPPO ALTA scopre il bug.
        if (msg.value < REGISTRATION_FEE) {
            revert ExactFeeRequired(msg.value, REGISTRATION_FEE);
        }

        registered[msg.sender] = true;
        registrationCount += 1;
        totalReceived += msg.value;
    }
}
