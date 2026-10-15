// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Traccia esclusa dalla suite. Copiala sotto test/ e aggiungi gli import quando inizi.

// TODO 1: ricostruisci tre frame annotando vault balance, credito, totalCredits e receiver balance.

// TODO 2: analizza rewardToken.transfer(...) prima di rewards[msg.sender] = 0.

// TODO 3: aggiungi moveCredit() e progetta un test locale di cross-function reentrancy.

// TODO 4: crea un receiver che rifiuta ETH e verifica il rollback di SafeVaultCEI.

// TODO 5: scrivi il regression test economico minimo che distingue vulnerable e safe.

// TODO 6: decidi quali entry point condividono la risorsa e quindi lo scope del lock.

// TODO 7: trasforma solvibilita' e callback count in un fuzz test con bound ragionevoli.

