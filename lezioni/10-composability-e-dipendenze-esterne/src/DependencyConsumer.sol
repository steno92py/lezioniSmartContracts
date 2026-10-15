// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import { IValueProvider } from "./interfaces/IValueProvider.sol";

/// @notice Provider critico fail-closed con cache esplicitamente limitata nel tempo.
/// @dev Due proprieta' distinte:
/// safety   = mai usare un valore invalido (refresh rifiuta zero e valori fuori range);
/// liveness = continuare a funzionare se il provider si guasta (la cache, ma solo per
/// maximumCacheAge secondi: poi meglio fermarsi che usare un dato vecchio).
contract DependencyConsumer {
    error InvalidProvider(address provider);
    error InvalidConfiguration();
    error InvalidValue(uint256 value);
    error CacheUnavailable();
    error StaleCache(uint256 age, uint256 maximumAge);

    // L'INDIRIZZO del provider e' immutable, il suo COMPORTAMENTO no: lo stesso indirizzo
    // puo' cambiare risposta nel tempo (vedi MutableDependency).
    IValueProvider public immutable provider;
    uint256 public immutable maximumValue;
    uint256 public immutable maximumCacheAge; // in secondi

    uint256 public lastGoodValue; // ultimo valore che ha superato la validazione
    uint256 public lastUpdatedAt; // timestamp del blocco di quel refresh; 0 = mai aggiornato

    constructor(IValueProvider provider_, uint256 maximumValue_, uint256 maximumCacheAge_) {
        if (address(provider_).code.length == 0) {
            revert InvalidProvider(address(provider_));
        }
        // Limiti a zero renderebbero il contratto inutilizzabile: si rifiutano al deploy.
        if (maximumValue_ == 0 || maximumCacheAge_ == 0) revert InvalidConfiguration();

        provider = provider_;
        maximumValue = maximumValue_;
        maximumCacheAge = maximumCacheAge_;
    }

    function refresh() external returns (uint256 newValue) {
        // Fail-closed: se il provider reverte, il revert risale e refresh fallisce; la cache
        // precedente resta intatta perche' nulla e' stato ancora scritto.
        newValue = provider.value();
        // Validazione semantica del return value: zero e valori oltre il massimo sono
        // tipici di un provider guasto o manipolato.
        if (newValue == 0 || newValue > maximumValue) revert InvalidValue(newValue);

        lastGoodValue = newValue;
        // `block.timestamp`: l'orario del blocco corrente, in secondi.
        lastUpdatedAt = block.timestamp;
    }

    function cachedValue() external view returns (uint256) {
        // Copia locale: una sola lettura dallo storage invece di due.
        uint256 updatedAt = lastUpdatedAt;
        // Senza refresh riusciti lastGoodValue varrebbe 0: meglio un errore esplicito.
        if (updatedAt == 0) revert CacheUnavailable();

        uint256 age = block.timestamp - updatedAt;
        // `>` e non `>=`: un'eta' esattamente uguale a maximumCacheAge e' ancora accettata.
        if (age > maximumCacheAge) revert StaleCache(age, maximumCacheAge);

        return lastGoodValue;
    }
}
