// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Traccia esclusa dalla suite: copiala sotto test/fuzz e aggiungi gli import.

// TODO 1: fuzz amount nel dominio 1..type(uint128).max con bound.

// TODO 2: fuzz caller non buyer con assume e verifica il custom error completo.

// TODO 3: separa fee valide 0..1000 e invalide 1001..type(uint16).max.

// TODO 4: dimostra la monotonicità di quote(a) e quote(b) normalizzando la coppia.

// TODO 5: fuzza freshness valida e stale in due test con domini distinti.

// TODO 6: conserva un test deterministico per il boundary MAX_AGE esatto.

