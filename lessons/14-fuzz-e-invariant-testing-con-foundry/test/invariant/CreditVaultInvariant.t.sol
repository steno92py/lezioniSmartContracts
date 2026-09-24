// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// INVARIANT TEST (stateful): dopo setUp, Foundry esegue molte sequenze casuali di azioni
// dell'handler (runs = 128 sequenze, depth = 64 chiamate ciascuna, da foundry.toml) e dopo
// ogni chiamata esegue TUTTE le funzioni invariant_. Un invariante e' una proprieta' che deve
// valere in ogni stato raggiungibile, non solo alla fine di uno scenario scelto a mano.
// Se fallisce, Foundry stampa la sequenza di chiamate che l'ha rotto.
// Configurazione del perimetro (funzioni di StdInvariant, incluse in Test):
//   targetContract(a)         Foundry chiama SOLO il contratto a (qui l'handler), non il vault
//                             ne' il token direttamente;
//   targetSelector(sel)       e di quel contratto SOLO le funzioni elencate nei selector.
// Le precondizioni del modello (token exact-transfer, niente donation, tre actor) sono in
// MODEL.md: gli invarianti qui sotto valgono solo dentro quel perimetro.
import {Test} from "forge-std/Test.sol";
import {CreditVault} from "../../src/invariant/CreditVault.sol";
import {ExactToken} from "../../src/invariant/ExactToken.sol";
import {VaultHandler} from "./handlers/VaultHandler.sol";

contract CreditVaultInvariantTest is Test {
    ExactToken internal token;
    CreditVault internal vault;
    VaultHandler internal handler;

    function setUp() public {
        token = new ExactToken();
        vault = new CreditVault(token);
        handler = new VaultHandler(vault, token);

        // L'action space: le tre azioni dell'handler. `.selector` = i 4 byte che identificano
        // una funzione. actor() e actorCount() restano fuori: sono getter, non azioni.
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.withdraw.selector;
        selectors[2] = VaultHandler.withdrawTooMuch.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // Solvibilita' forte: i token nel vault sono esattamente il totale dovuto.
    // `==` e non `>=` perche' il modello esclude donation dirette al vault.
    function invariant_VaultBalanceEqualsTotalCredit() public view {
        assertEq(token.balanceOf(address(vault)), vault.totalCredit());
    }

    // Confronto con la memoria indipendente dell'handler: depositato - prelevato = credito.
    // Il primo assert evita l'underflow della sottrazione e rende chiaro il messaggio d'errore.
    function invariant_GhostNetDepositsEqualTotalCredit() public view {
        assertGe(handler.ghostDeposited(), handler.ghostWithdrawn());
        assertEq(handler.ghostDeposited() - handler.ghostWithdrawn(), vault.totalCredit());
    }

    // Somma cross-user: vale perche' solo i tre actor modellati possono depositare.
    function invariant_TotalCreditEqualsSumOfAllModelledActors() public view {
        uint256 actorCredits;
        for (uint256 i; i < handler.actorCount(); ++i) {
            actorCredits += vault.credit(handler.actor(i));
        }
        assertEq(actorCredits, vault.totalCredit());
    }

    // Conservazione: i token si spostano tra actor e vault, ma il totale non cambia mai.
    function invariant_TokensAreConservedAcrossActorsAndVault() public view {
        uint256 observed = token.balanceOf(address(vault));
        for (uint256 i; i < handler.actorCount(); ++i) {
            observed += token.balanceOf(handler.actor(i));
        }
        assertEq(observed, 3 * handler.INITIAL_ACTOR_BALANCE());
    }
}
