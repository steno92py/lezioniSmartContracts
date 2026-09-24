// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

// Fuzz test negativo del vault: un prelievo oltre il credito reverte e non tocca la contabilita'.
import {Test} from "forge-std/Test.sol";
import {CreditVault} from "../../src/invariant/CreditVault.sol";
import {ExactToken} from "../../src/invariant/ExactToken.sol";

contract VaultNegativeFuzzTest is Test {
    ExactToken internal token;
    CreditVault internal vault;
    address internal alice;

    function setUp() public {
        alice = makeAddr("alice");
        token = new ExactToken();
        vault = new CreditVault(token);
        // Saldo piu' grande di qualunque deposito fuzzato (al massimo uint128.max):
        // un revert per saldo insufficiente non puo' confondere il test.
        token.mint(alice, type(uint192).max);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
    }

    function testFuzz_OverWithdrawalPreservesAccounting(uint128 rawDeposit, uint128 rawExtra) public {
        uint256 deposited = bound(rawDeposit, 1, type(uint128).max);
        uint256 extra = bound(rawExtra, 1, type(uint128).max);
        vm.prank(alice);
        vault.deposit(deposited);
        // Sempre almeno 1 wei oltre il credito, fino a molto oltre.
        uint256 requested = deposited + extra;

        vm.expectRevert(abi.encodeWithSelector(CreditVault.InsufficientCredit.selector, alice, requested, deposited));
        vm.prank(alice);
        vault.withdraw(requested);

        // Tre osservabili indipendenti: credito individuale, totale e token effettivi.
        assertEq(vault.credit(alice), deposited);
        assertEq(vault.totalCredit(), deposited);
        assertEq(token.balanceOf(address(vault)), deposited);
    }

    function test_Regression_ZeroDepositIsRejected() public {
        vm.expectRevert(CreditVault.ZeroAmount.selector);
        vm.prank(alice);
        vault.deposit(0);
    }

    // Prelievo zero con credito disponibile: il payload mostra requested = 0, available = 1 ether.
    function test_Regression_ZeroWithdrawalIsRejected() public {
        vm.prank(alice);
        vault.deposit(1 ether);

        vm.expectRevert(abi.encodeWithSelector(CreditVault.InsufficientCredit.selector, alice, 0, 1 ether));
        vm.prank(alice);
        vault.withdraw(0);
    }

    function test_Regression_ZeroTokenConfigurationIsRejected() public {
        vm.expectRevert(CreditVault.ZeroAddress.selector);
        new CreditVault(ExactToken(address(0)));
    }
}

