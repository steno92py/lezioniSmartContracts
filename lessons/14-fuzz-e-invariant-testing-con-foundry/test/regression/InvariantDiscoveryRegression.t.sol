// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Dal controesempio al regression test. Quando un invariante fallisce, Foundry stampa la
// sequenza di chiamate che l'ha rotto; ridotta al minimo, diventa un test deterministico
// che resta nella suite anche dopo la correzione, cosi' il bug non puo' tornare in silenzio.
// Qui niente handler ne' casualita': ogni passo e' scritto a mano.
import {Test} from "forge-std/Test.sol";
import {CreditVault} from "../../src/invariant/CreditVault.sol";
import {ExactToken} from "../../src/invariant/ExactToken.sol";

contract InvariantDiscoveryRegressionTest is Test {
    ExactToken internal token;
    CreditVault internal vault;
    address internal alice;
    address internal bob;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        token = new ExactToken();
        vault = new CreditVault(token);

        token.mint(alice, 100 ether);
        token.mint(bob, 100 ether);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // Sequenza minima con due utenti e prelievi parziali, fino ad azzerare il credito di alice.
    // Alla fine si controllano gli stessi osservabili degli invarianti: credito per utente,
    // totale e token effettivamente nel vault.
    function test_Regression_MinimalSequencePreservesAccounting() public {
        _deposit(alice, 17 ether);
        _withdraw(alice, 16 ether);
        _deposit(bob, 2 ether);
        _withdraw(alice, 1 ether);

        assertEq(vault.credit(alice), 0);
        assertEq(vault.credit(bob), 2 ether);
        assertEq(vault.totalCredit(), 2 ether);
        assertEq(token.balanceOf(address(vault)), 2 ether);
    }

    // Versione deterministica dell'azione avversaria dell'handler: 1 ether oltre il credito.
    function test_Regression_OverWithdrawalPreservesAllAccounting() public {
        _deposit(alice, 17 ether);

        vm.expectRevert(abi.encodeWithSelector(CreditVault.InsufficientCredit.selector, alice, 18 ether, 17 ether));
        vm.prank(alice);
        vault.withdraw(18 ether);

        assertEq(vault.credit(alice), 17 ether);
        assertEq(vault.totalCredit(), 17 ether);
        assertEq(token.balanceOf(address(vault)), 17 ether);
    }

    // Helper `private`: ogni passo della sequenza si legge come una riga del controesempio.
    function _deposit(address actor, uint256 amount) private {
        vm.prank(actor);
        vault.deposit(amount);
    }

    function _withdraw(address actor, uint256 amount) private {
        vm.prank(actor);
        vault.withdraw(amount);
    }
}

