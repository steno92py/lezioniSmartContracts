// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Traccia esclusa dalla suite. Copiala sotto test/ e aggiungi gli import quando inizi.

// TODO 1: crea un DispatchProbe con foo(), receive() e fallback() che emettono eventi.
// Verifica la matrice calldata vuota/selector valido/selector sconosciuto, con 0 e 1 wei.

// TODO 2: rendi foo() nonpayable e confronta la call con 0 wei e quella con 1 wei.

// TODO 3: crea un seller che rifiuta ETH con custom error e verifica il rollback completo.

// TODO 4: forza 13 ether nell'Escrow con prezzo 5 ether e dimostra che il payout resta 5.

// TODO 5: analizza la variante che invia address(this).balance prima di aggiornare lo stato.

// TODO 6: ridisegna il payout come credito claimable + withdraw separata, prima su carta.

