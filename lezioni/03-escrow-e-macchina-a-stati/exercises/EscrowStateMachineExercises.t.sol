// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Traccia esclusa dalla suite. Copiala sotto test/ e aggiungi gli import quando inizi.

// TODO 1: outsider non puo' chiamare cancelBeforeFunding; verifica revert e stato.

// TODO 2: dopo Cancelled, approveRelease deve fallire anche se chiama il buyer.

// TODO 3: sostituisci expectPartialRevert(selector) con expectRevert(payload completo)
// per verificare WrongValue(expected, actual) e tutti i suoi argomenti.

// TODO 4: rimuovi temporaneamente onlyState(State.Created) da fund e osserva quali
// regression test falliscono. Ripristina poi il contratto corretto.

// TODO 5: formula una proprieta' storica che inizi con:
// "Se lo stato e' ReleaseApproved, allora in passato...".

// TODO 6: progetta su carta l'aggiunta del ruolo arbiter prima di scrivere codice.
