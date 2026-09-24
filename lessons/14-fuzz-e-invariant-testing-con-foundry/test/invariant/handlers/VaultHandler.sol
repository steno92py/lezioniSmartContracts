// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// HANDLER: il contratto che Foundry chiama durante l'invariant test, al posto del vault.
// Ogni funzione esterna e' un'"azione": riceve input casuali, li trasforma in una chiamata
// sensata al protocollo (actor scelto, importo nel dominio) e registra cosa e' successo.
//   Foundry -> handler.deposit(seed, raw) -> vm.prank(actor) -> vault.deposit(amount)
// Eredita Test per avere vm, bound, makeAddr e gli assert.
import {Test} from "forge-std/Test.sol";
import {CreditVault} from "../../../src/invariant/CreditVault.sol";
import {ExactToken} from "../../../src/invariant/ExactToken.sol";

contract VaultHandler is Test {
    uint256 public constant MAX_ACTION_AMOUNT = 1_000 ether;
    // Enorme rispetto ai depositi (al massimo 1_000 ether per azione): gli actor non restano
    // mai senza token, quindi deposit non reverte mai per saldo insufficiente.
    uint256 public constant INITIAL_ACTOR_BALANCE = 1_000_000_000 ether;

    CreditVault public immutable vault;
    ExactToken public immutable token;

    // Gli ACTOR: gli unici utenti del protocollo in questo modello (vedi MODEL.md).
    address[] internal actors;

    // GHOST VARIABLES: memoria del test, indipendente dal vault. Registrano i fatti osservati
    // senza ricopiare la logica del protocollo, e gli invarianti le confrontano con lo stato.
    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;
    // Contatori delle azioni: non entrano negli invarianti. Servono a capire se l'handler
    // esegue davvero deposit e withdraw o produce quasi solo no-op.
    uint256 public callsDeposit;
    uint256 public callsWithdraw;
    uint256 public callsAdversarialWithdraw;
    uint256 public noOpWithdraw;

    constructor(CreditVault vault_, ExactToken token_) {
        vault = vault_;
        token = token_;

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));

        // Ogni actor riceve token e approva il vault una volta per tutte.
        for (uint256 i; i < actors.length; ++i) {
            token.mint(actors[i], INITIAL_ACTOR_BALANCE);
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }
    }

    // Azione valida BOUNDED: l'input casuale viene sempre ricondotto a un deposito lecito.
    // In foundry.toml fail_on_revert = true: un revert inatteso in un'azione fa fallire la run,
    // per questo le azioni valide non devono mai produrre input invalidi.
    function deposit(uint256 actorSeed, uint256 rawAmount) external {
        address selectedActor = _actor(actorSeed);
        uint256 amount = bound(rawAmount, 1, MAX_ACTION_AMOUNT);

        // Il msg.sender con cui Foundry chiama l'handler non conta: il caller del protocollo
        // lo sceglie l'handler, esplicitamente.
        vm.prank(selectedActor);
        vault.deposit(amount);

        // Il ghost si aggiorna solo DOPO la call riuscita: registra un fatto avvenuto.
        ghostDeposited += amount;
        callsDeposit += 1;
    }

    function withdraw(uint256 actorSeed, uint256 rawAmount) external {
        address selectedActor = _actor(actorSeed);
        uint256 available = vault.credit(selectedActor);
        // Senza credito non esiste un prelievo valido: invece di revertire, l'azione diventa
        // un no-op (e lo conta).
        if (available == 0) {
            noOpWithdraw += 1;
            return;
        }
        uint256 amount = bound(rawAmount, 1, available);

        vm.prank(selectedActor);
        vault.withdraw(amount);

        ghostWithdrawn += amount;
        callsWithdraw += 1;
    }

    // Azione AVVERSARIA: chiede sempre piu' del credito disponibile. Il revert e' atteso, quindi
    // viene dichiarato con expectRevert e non conta come fallimento per fail_on_revert.
    // Dopo il revert l'handler verifica che nulla sia cambiato (rollback).
    function withdrawTooMuch(uint256 actorSeed, uint256 rawExtra) external {
        address selectedActor = _actor(actorSeed);
        uint256 available = vault.credit(selectedActor);
        uint256 extra = bound(rawExtra, 1, MAX_ACTION_AMOUNT);
        uint256 requested = available + extra;
        uint256 totalBefore = vault.totalCredit();
        uint256 balanceBefore = token.balanceOf(address(vault));

        vm.expectRevert(
            abi.encodeWithSelector(CreditVault.InsufficientCredit.selector, selectedActor, requested, available)
        );
        vm.prank(selectedActor);
        vault.withdraw(requested);

        assertEq(vault.credit(selectedActor), available);
        assertEq(vault.totalCredit(), totalBefore);
        assertEq(token.balanceOf(address(vault)), balanceBefore);
        callsAdversarialWithdraw += 1;
    }

    // Getter usati dagli invarianti per scorrere gli actor. Non sono tra i target selector,
    // quindi Foundry non li chiama come azioni.
    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // Da un seed casuale qualsiasi a uno dei tre actor: il modulo `%` da' sempre un indice valido.
    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }
}
